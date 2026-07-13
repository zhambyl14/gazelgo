// Tasu · otp edge function
// Телефон + құпиясөз аутентификациясы, SMS кодын Mobizon арқылы жіберу.
//
// Actions (POST body { action, ... }):
//   send     { phone, purpose }                  → код жібереді (лимитпен)
//   register { phone, password, full_name, role, code } → тіркеу (код расталса)
//   reset    { phone, password, code }           → құпиясөзді ауыстыру (код расталса)
//
// Аккаунт синтетикалық email арқылы құрылады: 7XXXXXXXXXX@phone.gazelgo.kz
//
// Қажетті құпиялар (Dashboard → Edge Functions → Secrets):
//   MOBIZON_API_KEY  — Mobizon API кілті (міндетті)
//   OTP_SECRET       — код хэшінің тұзы (міндетті емес; болмаса service key)
// verify_jwt = false (көпшілікке ашық endpoint).

import { createClient } from "jsr:@supabase/supabase-js@2";

const EMAIL_DOMAIN = "phone.gazelgo.kz";
const CODE_TTL_MS = 5 * 60 * 1000; // код 5 минут жарамды
const MAX_VERIFY = 5; // 5 қате тексеруден соң блок
const WINDOW_RESET_MS = 24 * 60 * 60 * 1000; // 24 сағат тынышталса — лимит нөлден
// Эскалация: 1-ші жіберуден соң 90с, 2-ден соң 5мин, 3+ соң 2 сағат.
const COOLDOWNS = [90, 300, 7200];

// Тест нөмірлер: нақты SMS жіберілмейді, коды тұрақты, лимитсіз.
// (App Store/тексеру мен әзірлеу үшін.) Нөмір — нормаланған 7XXXXXXXXXX.
const TEST_CODES: Record<string, string> = {
  "77474005347": "111111",
};

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "BAD_JSON" }, 400);
  }

  const action = String(body.action ?? "");
  const phone = normalizePhone(String(body.phone ?? ""));
  if (!phone) return json({ error: "BAD_PHONE" }, 400);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );
  const email = `${phone}@${EMAIL_DOMAIN}`;

  try {
    switch (action) {
      case "send":
        return await handleSend(admin, phone, email, String(body.purpose ?? ""));
      case "register":
        return await handleRegister(admin, phone, email, body);
      case "reset":
        return await handleReset(admin, phone, email, body);
      default:
        return json({ error: "BAD_ACTION" }, 400);
    }
  } catch (e) {
    console.error("otp error", e);
    return json({ error: "SERVER_ERROR" }, 500);
  }
});

// ---------------- send ----------------
async function handleSend(
  admin: ReturnType<typeof createClient>,
  phone: string,
  email: string,
  purpose: string,
): Promise<Response> {
  if (purpose !== "register" && purpose !== "reset") {
    return json({ error: "BAD_PURPOSE" }, 400);
  }

  // Аккаунт бар-жоғын мақсатқа қарай тексереміз.
  const existingId = await userIdByEmail(admin, email);
  if (purpose === "register" && existingId) {
    return json({ error: "PHONE_TAKEN" }, 409);
  }
  if (purpose === "reset" && !existingId) {
    return json({ error: "PHONE_NOT_FOUND" }, 404);
  }

  const now = Date.now();
  const testCode = TEST_CODES[phone];

  const { data: row } = await admin
    .from("sms_otps")
    .select("*")
    .eq("phone", phone)
    .maybeSingle();

  // Лимит: рұқсат етілген сәтке жетпеген болса — қалғанын қайтарамыз.
  // Тест нөмірлерге лимит қолданылмайды.
  if (!testCode && row?.next_allowed_at) {
    const nextMs = new Date(row.next_allowed_at as string).getTime();
    if (now < nextMs) {
      return json(
        { error: "RATE_LIMITED", retry_after: Math.ceil((nextMs - now) / 1000) },
        429,
      );
    }
  }

  // Эскалация терезесі: ұзақ тыныштықтан соң нөлден бастаймыз.
  let sendCount = (row?.send_count as number) ?? 0;
  let windowStart = row?.window_started_at
    ? new Date(row.window_started_at as string).getTime()
    : now;
  if (!row || now - windowStart > WINDOW_RESET_MS) {
    sendCount = 0;
    windowStart = now;
  }
  sendCount += 1;
  const cooldown = testCode
    ? 0
    : COOLDOWNS[Math.min(sendCount - 1, COOLDOWNS.length - 1)];

  // Тест нөмір: тұрақты код, нақты SMS жіберілмейді.
  const code = testCode ?? String(Math.floor(100000 + Math.random() * 900000));
  const codeHash = await sha256(code + otpSecret() + phone);

  if (!testCode) {
    const sent = await sendSms(
      phone,
      `Tasu коды: ${code}. Ешкімге бермеңіз.`,
    );
    if (!sent) return json({ error: "SMS_FAILED" }, 502);
  }

  await admin.from("sms_otps").upsert({
    phone,
    purpose,
    code_hash: codeHash,
    expires_at: new Date(now + CODE_TTL_MS).toISOString(),
    verify_attempts: 0,
    send_count: sendCount,
    window_started_at: new Date(windowStart).toISOString(),
    last_sent_at: new Date(now).toISOString(),
    next_allowed_at: new Date(now + cooldown * 1000).toISOString(),
  });

  return json({ ok: true, retry_after: cooldown }, 200);
}

// ---------------- register ----------------
async function handleRegister(
  admin: ReturnType<typeof createClient>,
  phone: string,
  email: string,
  body: Record<string, unknown>,
): Promise<Response> {
  const password = String(body.password ?? "");
  const fullName = String(body.full_name ?? "").trim();
  const role = String(body.role ?? "client");
  const code = String(body.code ?? "");

  if (password.length < 6) return json({ error: "WEAK_PASSWORD" }, 400);
  if (fullName.length < 2) return json({ error: "BAD_NAME" }, 400);
  if (role !== "client" && role !== "executor") {
    return json({ error: "BAD_ROLE" }, 400);
  }

  const verify = await verifyCode(admin, phone, "register", code);
  if (verify) return verify; // қате болса — жауап дайын

  // Телефон провайдерін баптамай-ақ жұмыс істеу үшін тек синтетикалық email
  // қолданамыз; нақты нөмір profiles.phone-ге метадеректен түседі.
  const { error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { full_name: fullName, phone: `+${phone}`, role },
  });
  if (error) {
    const code = /already/i.test(error.message) ? "PHONE_TAKEN" : error.message;
    return json({ error: code }, 400);
  }

  await consume(admin, phone);
  return json({ ok: true }, 200);
}

// ---------------- reset ----------------
async function handleReset(
  admin: ReturnType<typeof createClient>,
  phone: string,
  email: string,
  body: Record<string, unknown>,
): Promise<Response> {
  const password = String(body.password ?? "");
  const code = String(body.code ?? "");
  if (password.length < 6) return json({ error: "WEAK_PASSWORD" }, 400);

  const userId = await userIdByEmail(admin, email);
  if (!userId) return json({ error: "PHONE_NOT_FOUND" }, 404);

  const verify = await verifyCode(admin, phone, "reset", code);
  if (verify) return verify;

  const { error } = await admin.auth.admin.updateUserById(userId, { password });
  if (error) return json({ error: error.message }, 400);

  await consume(admin, phone);
  return json({ ok: true }, 200);
}

// ---------------- helpers ----------------

/// Кодты тексереді. ОК болса null; әйтпесе дайын қате-жауап қайтарады.
async function verifyCode(
  admin: ReturnType<typeof createClient>,
  phone: string,
  purpose: string,
  code: string,
): Promise<Response | null> {
  if (!/^\d{6}$/.test(code)) return json({ error: "OTP_WRONG" }, 400);
  const { data: row } = await admin
    .from("sms_otps")
    .select("*")
    .eq("phone", phone)
    .maybeSingle();
  if (!row || !row.code_hash) return json({ error: "OTP_NOT_FOUND" }, 400);
  if (row.purpose !== purpose) return json({ error: "OTP_NOT_FOUND" }, 400);
  if (new Date(row.expires_at as string).getTime() < Date.now()) {
    return json({ error: "OTP_EXPIRED" }, 400);
  }
  if ((row.verify_attempts as number) >= MAX_VERIFY) {
    return json({ error: "OTP_LOCKED" }, 429);
  }
  const hash = await sha256(code + otpSecret() + phone);
  if (hash !== row.code_hash) {
    await admin
      .from("sms_otps")
      .update({ verify_attempts: (row.verify_attempts as number) + 1 })
      .eq("phone", phone);
    return json({ error: "OTP_WRONG" }, 400);
  }
  return null; // сәтті
}

/// Кодты «жұмсалды» деп белгілейді (қайта қолдануға болмайды).
async function consume(admin: ReturnType<typeof createClient>, phone: string) {
  await admin
    .from("sms_otps")
    .update({ code_hash: null })
    .eq("phone", phone);
}

async function userIdByEmail(
  admin: ReturnType<typeof createClient>,
  email: string,
): Promise<string | null> {
  const { data } = await admin.rpc("otp_user_id", { p_email: email });
  return (data as string | null) ?? null;
}

/// Mobizon арқылы SMS жіберу. Сәтті болса true.
async function sendSms(phone: string, text: string): Promise<boolean> {
  const key = Deno.env.get("MOBIZON_API_KEY");
  if (!key) {
    console.error("MOBIZON_API_KEY not set");
    return false;
  }
  try {
    const url = new URL("https://api.mobizon.kz/service/message/sendSMSMessage");
    url.searchParams.set("apiKey", key);
    url.searchParams.set("recipient", phone);
    url.searchParams.set("text", text);
    const res = await fetch(url.toString(), { method: "POST" });
    if (!res.ok) return false;
    const j = await res.json();
    // Mobizon: code === 0 → сәтті.
    return j?.code === 0;
  } catch (e) {
    console.error("mobizon error", e);
    return false;
  }
}

function normalizePhone(raw: string): string | null {
  let d = raw.replace(/\D/g, "");
  if (d.length === 11 && d.startsWith("8")) d = "7" + d.slice(1);
  if (d.length === 10) d = "7" + d;
  if (d.length === 11 && d.startsWith("7")) return d;
  return null;
}

function otpSecret(): string {
  return Deno.env.get("OTP_SECRET") ??
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY") ?? "gazelgo";
}

async function sha256(s: string): Promise<string> {
  const buf = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(s),
  );
  return [...new Uint8Array(buf)]
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
