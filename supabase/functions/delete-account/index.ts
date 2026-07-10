// GazelGo · delete-account edge function
// App Store 5.1.1(v) / Play Market талабы: пайдаланушы аккаунтын қосымша
// ішінен өшіре алуы МІНДЕТТІ. verify_jwt = TRUE (тек өз аккаунтын өшіреді).
//
// profiles.id → auth.users ON DELETE CASCADE, ал orders/offers/reviews т.б.
// profiles-ке cascade — сондықтан auth.users жазбасын өшіру пайдаланушының
// барлық дербес деректерін тізбектей өшіреді (94-V Заңдағы «өшіру құқығы»).
// Белсенді заказ тұрғанда өшіруге болмайды — қарсы тарап зардап шекпеуі үшін.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const ACTIVE = ["searching", "accepted", "arrived", "loading", "in_transit"];

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") {
    return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // JWT-ден пайдаланушыны анықтау (verify_jwt қосулы болса да,
  // uid-ды өзіміз аламыз — басқа аккаунтты өшіру мүмкін болмауы үшін)
  const jwt = (req.headers.get("authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  );
  const { data: userData, error: authError } = await admin.auth.getUser(jwt);
  if (authError || !userData?.user) return json({ error: "AUTH" }, 401);
  const uid = userData.user.id;

  // Белсенді заказ бар ма? (клиент ретінде де, орындаушы ретінде де)
  const { data: activeOrders, error: qError } = await admin
    .from("orders")
    .select("id")
    .or(`client_id.eq.${uid},executor_id.eq.${uid}`)
    .in("status", ACTIVE)
    .limit(1);
  if (qError) return json({ error: "SERVER_ERROR" }, 500);
  if ((activeOrders ?? []).length > 0) {
    return json({ error: "HAS_ACTIVE_ORDERS" }, 400);
  }

  const { error } = await admin.auth.admin.deleteUser(uid);
  if (error) return json({ error: "DELETE_FAILED" }, 500);
  return json({ ok: true }, 200);
});

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
