// Tasu · tg-login edge function
// Бір қадамдық «Кіру» — құпиясөзсіз, тек Telegram растауымен.
//
// Ағын:
//   1) Қосымша нөмірді Telegram арқылы растайды (tg_start_verification →
//      бот/Mini App → telegram_verifications.verified = true).
//   2) Қосымша осы функцияға `{tg_token}` жібереді. Нөмір клиенттен ЕМЕС,
//      расталған жазбадан алынады (жалған нөмірге жол жоқ).
//   3) Осы нөмірге аккаунт БАР болса — сол адамға сессия жасап береміз
//      (`exists: true`, access/refresh токендер) да, токенді жұмсаймыз.
//      ЖОҚ болса — `exists: false`: қосымша тіркелуді бастайды (рөл, аты-жөні),
//      токен `signup` үшін сақталады (мерзімі 30 минутқа ұзартылады).
//
// Қауіпсіздік: бұл reset-password-пен бірдей деңгей — Telegram растаған
// нөмірдің иесі ғана кіре алады.
// verify_jwt = false (адам әлі кірмеген — JWT жоқ).
import { createClient, type SupabaseClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const URL = Deno.env.get("SUPABASE_URL")!;
const admin = createClient(URL, Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!, {
  auth: { persistSession: false, autoRefreshToken: false },
});

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "BAD_JSON" }, 400);
  }

  const tgToken = String(body.tg_token ?? "").trim();
  if (!tgToken) return json({ error: "TG_NOT_VERIFIED" }, 400);

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

  const { data: prof } = await admin
    .from("profiles")
    .select("id")
    .eq("phone", phone)
    .limit(1)
    .maybeSingle();

  if (!prof) {
    // Аккаунт жоқ — тіркелу басталады. Адам рөл мен атын таңдап
    // үлгеруі үшін токеннің мерзімін ұзартамыз.
    await admin
      .from("telegram_verifications")
      .update({ expires_at: new Date(Date.now() + 30 * 60 * 1000).toISOString() })
      .eq("token", tgToken);
    return json({ exists: false, phone }, 200);
  }

  const { data: u, error: uErr } = await admin.auth.admin.getUserById(
    prof.id as string,
  );
  const email = u?.user?.email ?? `${phone}@phone.gazelgo.kz`;
  if (uErr) console.error("TG_LOGIN_GET_USER", uErr.message);

  let session;
  try {
    session = await sessionFor(admin, email);
  } catch (e) {
    console.error("TG_LOGIN_SESSION", e);
    return json({ error: "SERVER_ERROR" }, 500);
  }

  // Токенді жұмсаймыз — қайта кіруге қолданылмасын.
  try {
    await admin.from("telegram_verifications").delete().eq("token", tgToken);
  } catch (_) { /* 15 мин соң өзі ескіреді */ }

  return json({
    exists: true,
    phone,
    access_token: session.access_token,
    refresh_token: session.refresh_token,
  }, 200);
});

/// Құпиясөзсіз сессия: admin magic-link жасап (хат ЖІБЕРІЛМЕЙДІ), оның
/// hashed_token-ін бірден растаймыз — нәтижесі кәдімгі кіру сессиясы.
async function sessionFor(admin: SupabaseClient, email: string) {
  const { data, error } = await admin.auth.admin.generateLink({
    type: "magiclink",
    email,
  });
  const hashed = data?.properties?.hashed_token;
  if (error || !hashed) throw new Error(error?.message ?? "NO_LINK");
  const anon = createClient(URL, Deno.env.get("SUPABASE_ANON_KEY")!, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
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
