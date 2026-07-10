// GazelGo · signup edge function
// Email-растаусыз тіркелу: admin.createUser(email_confirm: true).
// verify_jwt = false (бұл көпшілікке ашық тіркелу endpoint-і).
import { createClient } from "jsr:@supabase/supabase-js@2";

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

  const password = String(body.password ?? "");
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

  if (error) {
    const code = /already/i.test(error.message) ? "EMAIL_TAKEN" : error.message;
    return json({ error: code }, 400);
  }
  try {
    await admin.from("auth_events").insert({ ip, kind: "signup" });
  } catch (_) { /* журнал жазылмаса да тіркелу сәтті */ }
  // Верификация токенін жұмсаймыз — қайта тіркеуге қолданылмасын.
  try {
    await admin.from("telegram_verifications").delete().eq("token", tgToken);
  } catch (_) { /* өшпесе де 15 мин соң өзі ескіреді */ }
  return json({ ok: true, phone }, 200);
});

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
