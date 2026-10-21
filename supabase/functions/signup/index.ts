// Tasu · signup edge function
// Email-растаусыз тіркелу: admin.createUser(email_confirm: true).
// verify_jwt = false (бұл көпшілікке ашық тіркелу endpoint-і).
//
// Екі режим:
//   • `password` берілсе — бұрынғы ағын (ескі қосымша нұсқалары): аккаунт
//     құрылады, қосымша өзі құпиясөзбен кіреді.
//   • `password` ЖОҚ болса — жаңа бір қадамдық «Кіру» (tg-login): құпиясөз
//     кездейсоқ қойылады да, жауапта бірден сессия (access/refresh) қайтады.
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: cors });
  }
  if (req.method !== "POST") {
    return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "BAD_JSON" }, 400);
  }

  const passwordless = body.password == null || body.password === "";
  const password = passwordless ? randomPassword() : String(body.password);
  const fullName = String(body.full_name ?? "").trim();
  const role = String(body.role ?? "client");
  const tgToken = String(body.tg_token ?? "").trim();

  if (password.length < 6) return json({ error: "WEAK_PASSWORD" }, 400);
  if (fullName.length < 2) return json({ error: "BAD_NAME" }, 400);
  if (role !== "client" && role !== "executor") {
    return json({ error: "BAD_ROLE" }, 400);
  }
  if (!tgToken) return json({ error: "TG_NOT_VERIFIED" }, 400);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // Телефон Telegram арқылы РАСТАЛҒАН болуы шарт — нөмір клиенттен емес, осы
  // расталған жазбадан алынады (жалған нөмірмен тіркелуге жол жоқ).
  const { data: verif } = await admin
    .from("telegram_verifications")
    .select("phone, verified, expires_at")
    .eq("token", tgToken)
    .maybeSingle();
  if (
    !verif || !verif.verified || !verif.phone ||
    new Date(verif.expires_at).getTime() < Date.now()
  ) {
    return json({ error: "TG_NOT_VERIFIED" }, 400);
  }
  const phone = String(verif.phone);
  const email = `${phone}@phone.gazelgo.kz`;

  // IP бойынша rate-limit: сағатына 5 тіркелу (0018 миграциясындағы
  // auth_events кестесі). Кесте әлі жоқ болса — тіркелуді бұзбаймыз
  // (fail-open), тек лимитсіз өтеді.
  const ip = (req.headers.get("x-forwarded-for") ?? "unknown")
    .split(",")[0].trim();
  try {
    const since = new Date(Date.now() - 60 * 60 * 1000).toISOString();
    const { count, error: cntError } = await admin
      .from("auth_events")
      .select("id", { count: "exact", head: true })
      .eq("ip", ip)
      .eq("kind", "signup")
      .gte("created_at", since);
    if (!cntError && (count ?? 0) >= 5) {
      return json({ error: "RATE_LIMITED", retry_after: 3600 }, 429);
    }
  } catch (_) { /* лимитсіз жалғасамыз */ }

  const { error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: fullName, phone, role },
  });

  const taken = !!error && /already/i.test(error.message);
  if (error && !(taken && passwordless)) {
    return json({ error: taken ? "EMAIL_TAKEN" : error.message }, 400);
  }
  // Құпиясөзсіз режимде нөмір бұрын тіркелген болып шықса (мыс. екі
  // құрылғыдан қатар) — қате емес: нөмір Telegram-мен расталған, иесін
  // сол аккаунтқа кіргіземіз.
  let session: { access_token: string; refresh_token: string } | null = null;
  if (passwordless) {
    try {
      session = await sessionFor(admin, email);
    } catch (e) {
      console.error("SIGNUP_SESSION", e);
      return json({ error: "SERVER_ERROR" }, 500);
    }
  }
  if (!taken) {
    try {
      await admin.from("auth_events").insert({ ip, kind: "signup" });
    } catch (_) { /* журнал жазылмаса да тіркелу сәтті */ }
  }
  // Верификация токенін жұмсаймыз — қайта тіркеуге қолданылмасын.
  try {
    await admin.from("telegram_verifications").delete().eq("token", tgToken);
  } catch (_) { /* өшпесе де 15 мин соң өзі ескіреді */ }
  return json({
    ok: true,
    phone,
    existed: taken,
    ...(session
      ? {
        access_token: session.access_token,
        refresh_token: session.refresh_token,
      }
      : {}),
  }, 200);
});

/// Құпиясөзсіз тіркелудегі кездейсоқ құпиясөз (адам оны ешқашан көрмейді —
/// кіру Telegram арқылы).
function randomPassword(): string {
  const b = new Uint8Array(24);
  crypto.getRandomValues(b);
  return [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
}

/// Құпиясөзсіз сессия (tg-login-мен бірдей): admin magic-link жасап (хат
/// ЖІБЕРІЛМЕЙДІ), оның hashed_token-ін бірден растаймыз.
async function sessionFor(admin: SupabaseClient, email: string) {
  const { data, error } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email,
  });
  const hashed = data?.properties?.hashed_token;
  if (error || !hashed) throw new Error(error?.message ?? "NO_LINK");
  const anon = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_ANON_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );
  const { data: v, error: vErr } = await anon.auth.verifyOtp({
    token_hash: hashed,
    type: "magiclink",
  });
  if (vErr || !v?.session) throw new Error(vErr?.message ?? "NO_SESSION");
  return v.session;
}

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
