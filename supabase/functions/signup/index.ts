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

  const email = String(body.email ?? "").trim().toLowerCase();
  const password = String(body.password ?? "");
  const fullName = String(body.full_name ?? "").trim();
  const phone = String(body.phone ?? "").trim();
  const role = String(body.role ?? "client");

  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    return json({ error: "BAD_EMAIL" }, 400);
  }
  if (password.length < 6) return json({ error: "WEAK_PASSWORD" }, 400);
  if (fullName.length < 2) return json({ error: "BAD_NAME" }, 400);
  if (phone.replace(/\D/g, "").length < 10) return json({ error: "BAD_PHONE" }, 400);
  if (role !== "client" && role !== "executor") {
    return json({ error: "BAD_ROLE" }, 400);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

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
  return json({ ok: true }, 200);
});

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
