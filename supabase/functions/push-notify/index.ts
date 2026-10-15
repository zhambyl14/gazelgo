// Tasu · push-notify edge function
// Postgres триггерден (pg_net, `send_push()` RPC, 0025 миграциясы)
// шақырылады: title/body/data + міндетті емес target_user_ids жібереді.
// target_user_ids болмаса — БАРЛЫҚ модераторға broadcast (0019-дағы ескі
// «жаңа өтінім» тәртібімен үйлесімді), болса — тек сол пайдаланушыларға
// (мыс. қолдау чатындағы жеке жауап). Қосымша толық жабық болса да жеткізіледі.
//
// Verify JWT = OFF (pg_net JWT жібермейді) — орнына `x-push-secret` тексеріледі
// (PUSH_TRIGGER_SECRET). Google-ге FCM HTTP v1 API арқылы шығамыз: service
// account кілтімен JWT құрып, OAuth2 access_token аламыз (firebase-admin
// SDK-сыз — Deno-да ол жоқ, қолмен RS256 қол қоямыз).
//
// Диагностика: `validate_only: true` берілсе, FCM хабарды ЖІБЕРМЕЙ тек
// тексереді (токен жарамды ма, кілт дұрыс па). `all_tokens: true` —
// target_user_ids-ке қарамай, базадағы БАРЛЫҚ токенді алады (тек
// validate_only-мен бірге рұқсат). Әр FCM қатесі журналға жазылады.
import { createClient } from "jsr:@supabase/supabase-js@2";

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  }

  const expected = Deno.env.get("PUSH_TRIGGER_SECRET");
  const got = req.headers.get("x-push-secret");
  if (!expected || !got || got !== expected) {
    return json({ error: "FORBIDDEN" }, 403);
  }

  let body: {
    title?: string;
    body?: string;
    // Орысша нұсқасы (0045) — берілмесе, қазақшасы қолданылады. Әр
    // пайдаланушыға `profiles.lang` бойынша БІР ҒАНА тіл жіберіледі.
    title_ru?: string;
    body_ru?: string;
    data?: Record<string, unknown>;
    target_user_ids?: string[] | null;
    validate_only?: boolean;
    all_tokens?: boolean;
  };
  try {
    body = await req.json();
  } catch {
    body = {};
  }
  if (!body.title || !body.body) {
    return json({ error: "BAD_INPUT" }, 400);
  }
  const validateOnly = body.validate_only === true;

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  let tokenRows: { token: string; user_id: string; platform: string }[] = [];
  if (validateOnly && body.all_tokens === true) {
    const { data, error } = await admin
      .from("push_tokens")
      .select("token, user_id, platform");
    if (error) return json({ error: "SERVER_ERROR" }, 500);
    tokenRows = data ?? [];
  } else {
    let targetIds = Array.isArray(body.target_user_ids)
      ? body.target_user_ids.filter((id): id is string => typeof id === "string")
      : [];

    // target_user_ids жіберілмесе — әдепкі бойынша барлық модератор (ескі
    // «жаңа өтінім» broadcast тәртібі).
    if (targetIds.length === 0) {
      const { data: mods, error: modError } = await admin
        .from("profiles")
        .select("id")
        .eq("role", "moderator");
      if (modError) return json({ error: "SERVER_ERROR" }, 500);
      targetIds = (mods ?? []).map((m) => m.id as string);
    }
    if (targetIds.length === 0) {
      console.log("push: no targets", body.data?.type ?? "");
      return json({ ok: true, sent: 0 }, 200);
    }

    const { data, error } = await admin
      .from("push_tokens")
      .select("token, user_id, platform")
      .in("user_id", targetIds);
    if (error) return json({ error: "SERVER_ERROR" }, 500);
    tokenRows = data ?? [];
  }

  // Бір токен бірнеше рет келмеуі керек (әйтпесе БІР құрылғыға екі
  // хабарландыру түседі).
  const byToken = new Map<string, { user_id: string; platform: string }>();
  for (const r of tokenRows) {
    byToken.set(r.token, { user_id: r.user_id, platform: r.platform });
  }
  const tokens = [...byToken.keys()];
  if (tokens.length === 0) {
    console.log("push: targets have no tokens", body.data?.type ?? "");
    return json({ ok: true, sent: 0 }, 200);
  }

  // Әр пайдаланушының тілі (0045). Оқу сәтсіз болса — бәріне қазақша.
  const userIds = [...new Set([...byToken.values()].map((v) => v.user_id))];
  const langOf = new Map<string, string>();
  const { data: langRows } = await admin
    .from("profiles")
    .select("id, lang")
    .in("id", userIds);
  for (const r of langRows ?? []) {
    langOf.set(r.id as string, (r.lang as string) === "ru" ? "ru" : "kk");
  }

  let accessToken: string;
  try {
    accessToken = await getGoogleAccessToken();
  } catch (e) {
    console.error("FCM_AUTH_FAILED", String(e));
    return json({ error: "FCM_AUTH_FAILED", detail: String(e) }, 500);
  }
  const projectId = Deno.env.get("FCM_PROJECT_ID")!;

  // FCM `data` — тек жолдар (string) болуы керек, әйтпесе БҮКІЛ хабар
  // 400 INVALID_ARGUMENT-пен қайтарылады.
  const data: Record<string, string> = {};
  for (const [k, v] of Object.entries(body.data ?? {})) {
    if (v !== null && v !== undefined) data[k] = String(v);
  }
  const titleKk = body.title;
  const bodyKk = body.body;
  const titleRu = body.title_ru ?? titleKk;
  const bodyRu = body.body_ru ?? bodyKk;

  let sent = 0;
  const staleTokens: string[] = [];
  const errors: Record<string, number> = {};

  const sendOne = async (token: string) => {
    const owner = byToken.get(token)!;
    const ru = langOf.get(owner.user_id) === "ru";
    const title = ru ? titleRu : titleKk;
    const bodyText = ru ? bodyRu : bodyKk;
    try {
      const res = await fetch(
        `https://fcm.googleapis.com/v1/projects/${projectId}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${accessToken}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify({
            validate_only: validateOnly,
            message: {
              token,
              notification: { title, body: bodyText },
              data: { ...data, title, body: bodyText },
              android: {
                priority: "high",
                notification: {
                  // Қосымша ЖАБЫҚ кезде жүйе осы каналмен көрсетеді —
                  // heads-up (экранға қалқып шығу) + дыбыс + брендтік
                  // белгіше/түс.
                  channel_id: "gazelgo_high",
                  icon: "ic_stat_notify",
                  color: "#FFC400",
                  default_sound: true,
                  notification_priority: "PRIORITY_HIGH",
                },
              },
              apns: {
                headers: { "apns-priority": "10", "apns-push-type": "alert" },
                payload: { aps: { sound: "default" } },
              },
              // Web (PWA, gazelgo.pages.dev): firebase-messaging-sw.js
              // хабарды өзі көрсетеді, басқанда қосымша ашылады.
              webpush: {
                headers: { Urgency: "high" },
                notification: {
                  icon: "/icons/Icon-192.png",
                  badge: "/icons/Icon-192.png",
                },
                fcm_options: { link: "/" },
              },
            },
          }),
        },
      );
      if (res.ok) {
        sent++;
        return;
      }
      const errText = await res.text();
      const code =
        /UNREGISTERED|SENDER_ID_MISMATCH|THIRD_PARTY_AUTH_ERROR|INVALID_ARGUMENT|QUOTA_EXCEEDED|UNAVAILABLE|INTERNAL|PERMISSION_DENIED|UNAUTHENTICATED/
          .exec(errText)?.[0] ?? `HTTP_${res.status}`;
      errors[`${owner.platform}:${code}`] =
        (errors[`${owner.platform}:${code}`] ?? 0) + 1;
      console.error(
        "FCM_SEND_ERROR",
        owner.platform,
        res.status,
        errText.slice(0, 400),
      );
      // Токен жарамсыз (қосымша жойылған, басқа Firebase жобасынан т.б.) —
      // базадан өшіреміз, әйтпесе әр жолы бос сұраныс жібере береміз.
      if (
        res.status === 404 ||
        /UNREGISTERED|SENDER_ID_MISMATCH|registration token is not a valid/i
          .test(errText)
      ) {
        staleTokens.push(token);
      }
    } catch (e) {
      errors[`${owner.platform}:FETCH_FAILED`] =
        (errors[`${owner.platform}:FETCH_FAILED`] ?? 0) + 1;
      console.error("FCM_SEND_FAILED", owner.platform, String(e));
    }
  };

  // Параллель (10-нан) — көп алушы болса да функция тез аяқталады.
  for (let i = 0; i < tokens.length; i += 10) {
    await Promise.all(tokens.slice(i, i + 10).map(sendOne));
  }

  if (staleTokens.length > 0 && !validateOnly) {
    await admin.from("push_tokens").delete().in("token", staleTokens);
  }

  const result = {
    ok: true,
    validate_only: validateOnly,
    tokens: tokens.length,
    sent,
    stale: staleTokens.length,
    errors,
  };
  console.log("push:", body.data?.type ?? "", JSON.stringify(result));
  return json(result, 200);
});

/// Google service account кілтімен (RS256, JWT bearer flow) OAuth2
/// access_token алады — `firebase-admin` жоқ Deno ортасында осылай.
async function getGoogleAccessToken(): Promise<string> {
  const saJson = Deno.env.get("FCM_SERVICE_ACCOUNT_JSON");
  if (!saJson) throw new Error("FCM_SERVICE_ACCOUNT_JSON is not set");
  const sa = JSON.parse(saJson) as {
    client_email: string;
    private_key: string;
  };

  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claims = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${base64url(JSON.stringify(header))}.${base64url(JSON.stringify(claims))}`;

  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToDer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sigBuf = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${base64urlBytes(new Uint8Array(sigBuf))}`;

  const tokenRes = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });
  const tokenJson = await tokenRes.json();
  if (!tokenRes.ok) {
    throw new Error(`token exchange failed: ${JSON.stringify(tokenJson)}`);
  }
  return tokenJson.access_token as string;
}

function base64url(str: string): string {
  return base64urlBytes(new TextEncoder().encode(str));
}

function base64urlBytes(bytes: Uint8Array): string {
  let bin = "";
  for (const b of bytes) bin += String.fromCharCode(b);
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

function pemToDer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const bin = atob(b64);
  const bytes = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) bytes[i] = bin.charCodeAt(i);
  return bytes.buffer;
}

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
