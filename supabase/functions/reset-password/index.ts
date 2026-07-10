// GazelGo · reset-password edge function
// Құпиясөзді қалпына келтіру — SMS-сіз, Telegram арқылы. Пайдаланушы нөмірін
// Telegram-мен растайды (tg_token), сосын жаңа құпиясөз орнатады. Нөмір
// расталған жазбадан алынады (өтірік нөмірге жол жоқ), сол нөмірдің
// иесіне жаңа құпиясөз admin арқылы қойылады.
//
// verify_jwt = false (пайдаланушы кіре алмай тұр — сондықтан JWT жоқ).
import { createClient } from "jsr:@supabase/supabase-js@2";

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

  const tgToken = String(body.tg_token ?? "").trim();
  const newPassword = String(body.new_password ?? "");
  if (!tgToken) return json({ error: "TG_NOT_VERIFIED" }, 400);
  if (newPassword.length < 6) return json({ error: "WEAK_PASSWORD" }, 400);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // Telegram растауы (нөмір осы жазбадан ғана)
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

  // Осы нөмірдің иесін табу (profiles.phone = 7XXXXXXXXXX, id = auth user id)
  const { data: prof } = await admin
    .from("profiles")
    .select("id")
    .eq("phone", phone)
    .maybeSingle();
  if (!prof) return json({ error: "PHONE_NOT_FOUND" }, 400);

  const { error } = await admin.auth.admin.updateUserById(prof.id as string, {
    password: newPassword,
  });
  if (error) return json({ error: "SERVER_ERROR", detail: error.message }, 500);

  // Токенді жұмсаймыз
  try {
    await admin.from("telegram_verifications").delete().eq("token", tgToken);
  } catch (_) { /* 15 мин соң өзі ескіреді */ }

  return json({ ok: true, phone }, 200);
});

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
