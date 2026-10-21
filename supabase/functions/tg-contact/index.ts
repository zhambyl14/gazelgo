// Tasu · tg-contact edge function
// Нөмірді Telegram Mini App арқылы растау — START-сыз, бір түртумен.
//
// Ағын:
//   1) Қосымша `t.me/<bot>?startapp=<токен>` ашады → Telegram бірден ботың
//      Main Mini App-ын (web/tg/) ашады, токен `start_param` болып келеді.
//   2) Mini App `{action:'link', init_data}` жібереді → токенді осы Telegram
//      пайдаланушысына байлаймыз (telegram_chat_id = user.id). Осыдан кейін
//      ботқа келетін contact хаты да (telegram-webhook) сол токенді табады —
//      екі тәуелсіз жол, біреуі істемей қалса да екіншісі растайды.
//   3) Mini App бірден `requestContact()` шақырады → адам «Бөлісу» басады →
//      `{action:'verify', init_data, contact}` жібереді. `contact` — Telegram
//      ҚОЛ ҚОЙҒАН жауап: оны да, init_data-ны да бот токенімен тексереміз
//      (жалған нөмір жіберу мүмкін емес), contact.user_id == user.id болса
//      токенді verified=true қыламыз.
//
// verify_jwt = false (Telegram ішінен шақырылады, JWT жоқ); қорғаныс —
// Telegram қолтаңбасы. Қажет құпия: TELEGRAM_BOT_TOKEN.
import { createClient } from "jsr:@supabase/supabase-js@2";

const BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
const MAX_AGE_SEC = 60 * 60; // қолтаңба 1 сағат жарамды

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  if (!BOT_TOKEN) return json({ error: "NOT_CONFIGURED" }, 500);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "BAD_JSON" }, 400);
  }

  // Қосымша сұрайды: START-сыз ағынды қолдануға бола ма? (BotFather-де
  // боттың Main Mini App-ы бапталса ғана — әйтпесе `startapp` сілтемесі
  // жай чатты ашып, токен жоғалады.)
  if (body.action === "status") {
    return json({ miniapp: await hasMainWebApp() }, 200);
  }

  const init = await verifySigned(String(body.init_data ?? ""));
  if (!init) return json({ error: "BAD_INIT_DATA" }, 401);
  const user = parseJson(init.get("user"));
  const userId = Number(user?.id);
  const token = init.get("start_param") ?? "";
  if (!userId || !/^[A-Za-z0-9_-]{8,128}$/.test(token)) {
    return json({ error: "NO_TOKEN" }, 400);
  }

  const { data: row } = await admin
    .from("telegram_verifications")
    .select("*")
    .eq("token", token)
    .gt("expires_at", new Date().toISOString())
    .maybeSingle();
  if (!row) return json({ error: "EXPIRED" }, 410);
  // Тіл (0085): Mini App беті қосымшаның тілінде көрінсін.
  const lang = row.lang === "ru" ? "ru" : row.lang === "kk" ? "kk" : null;
  if (row.verified) return json({ ok: true, verified: true, lang }, 200);

  if (body.action === "link") {
    await admin
      .from("telegram_verifications")
      .update({ telegram_chat_id: userId })
      .eq("token", token);
    return json({ ok: true, lang }, 200);
  }

  if (body.action === "verify") {
    const signed = await verifySigned(String(body.contact ?? ""));
    if (!signed) return json({ error: "BAD_CONTACT" }, 401);
    const contact = parseJson(signed.get("contact"));
    if (!contact || Number(contact.user_id) !== userId) {
      return json({ error: "NOT_OWN_CONTACT" }, 400);
    }
    const phone = normalizeKz(String(contact.phone_number ?? ""));
    if (!phone) return json({ error: "NOT_KZ_PHONE" }, 400);
    await admin
      .from("telegram_verifications")
      .update({
        phone,
        verified: true,
        telegram_user_id: userId,
        telegram_chat_id: userId,
      })
      .eq("token", token);
    return json({ ok: true, verified: true }, 200);
  }

  return json({ error: "BAD_ACTION" }, 400);
});

/// Боттың Main Mini App-ы бар ма (Bot API getMe → has_main_web_app).
/// 5 минут кэштеледі; қате болса — false (қосымша ескі ағынмен жүреді).
let mainApp: { ok: boolean; at: number } | null = null;
async function hasMainWebApp(): Promise<boolean> {
  if (mainApp && Date.now() - mainApp.at < 5 * 60 * 1000) return mainApp.ok;
  let ok = false;
  try {
    const r = await fetch(`https://api.telegram.org/bot${BOT_TOKEN}/getMe`, {
      signal: AbortSignal.timeout(3000),
    });
    const j = await r.json();
    ok = j?.result?.has_main_web_app === true;
  } catch (_) {
    ok = false;
  }
  mainApp = { ok, at: Date.now() };
  return ok;
}

/// Telegram Mini App қолтаңбасын тексеру (initData және requestContact
/// жауабы бірдей тәсілмен қол қойылады): hash-тан басқа өрістер сұрыпталып
/// `key=value` жолдарымен біріктіріледі, кілт = HMAC_SHA256("WebAppData",
/// bot_token). Дұрыс әрі ескірмеген болса — өрістерді қайтарады.
async function verifySigned(raw: string): Promise<URLSearchParams | null> {
  if (!raw) return null;
  const params = new URLSearchParams(raw);
  const hash = params.get("hash");
  if (!hash) return null;
  const pairs: string[] = [];
  params.forEach((v, k) => {
    if (k !== "hash") pairs.push(`${k}=${v}`);
  });
  pairs.sort();
  const secret = await hmac(new TextEncoder().encode("WebAppData"), BOT_TOKEN);
  const calc = toHex(await hmac(secret, pairs.join("\n")));
  if (calc !== hash) return null;
  const authDate = Number(params.get("auth_date") ?? 0);
  if (!authDate || Date.now() / 1000 - authDate > MAX_AGE_SEC) return null;
  return params;
}

async function hmac(key: Uint8Array, msg: string): Promise<Uint8Array> {
  const k = await crypto.subtle.importKey(
    "raw",
    key,
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign("HMAC", k, new TextEncoder().encode(msg));
  return new Uint8Array(sig);
}

function toHex(b: Uint8Array): string {
  return [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
}

function parseJson(s: string | null): Record<string, unknown> | null {
  if (!s) return null;
  try {
    return JSON.parse(s);
  } catch {
    return null;
  }
}

/// +7/8/10-таңбалы қазақстандық нөмірден 7XXXXXXXXXX шығарады, әйтпесе null
/// (telegram-webhook-пен бірдей: тек +77…).
function normalizeKz(raw: string): string | null {
  let d = (raw ?? "").replace(/\D/g, "");
  if (d.length === 11 && d.startsWith("8")) d = "7" + d.slice(1);
  if (d.length === 10) d = "7" + d;
  if (d.length === 11 && d.startsWith("77")) return d;
  return null;
}

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
