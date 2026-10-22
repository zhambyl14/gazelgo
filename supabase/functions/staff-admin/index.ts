// Tasu · staff-admin edge function
// Модератор қолдау қызметкерлерін басқарады (0084 миграциясы):
//   create       — телефон + құпиясөз + аты + рұқсаттар → жаңа аккаунт;
//   set_password — қызметкердің құпиясөзін ауыстыру;
//   set_disabled — уақытша өшіру / қайта қосу (кіре алмайды);
//   delete       — біржола жою (нөмір босайды).
// Рұқсаттарды өзгерту — mod_staff_set_perms RPC (бұл функция емес).
//
// verify_jwt = TRUE. Шақырушы ТОЛЫҚ модератор болуы шарт
// (profiles.role = 'moderator' және staff_perms IS NULL) — қызметкер
// басқа қызметкер аша алмайды. Әрекет тек staff_perms-і бар (яғни
// қызметкер) аккаунттарға қолданылады: толық модераторға, клиентке не
// орындаушыға тиіспейді.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

/// 0084-дегі staff_perm_keys()-пен бірдей.
const PERM_KEYS = new Set([
  "overview", "line", "live_map", "orders", "applications", "executors",
  "executors_edit", "executors_block", "clients", "balance", "topups", "support", "reports", "order_chats",
  "broadcast", "news", "vehicles", "settings", "audit",
]);

const EMAIL_DOMAIN = "phone.gazelgo.kz";
const BAN_FOREVER = "876000h"; // ~100 жыл

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  // ---------- шақырушы: тек толық модератор ----------
  const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: userData, error: authError } = await admin.auth.getUser(jwt);
  if (authError || !userData?.user) return json({ error: "AUTH" }, 401);
  const callerId = userData.user.id;
  const { data: caller } = await admin
    .from("profiles")
    .select("role, staff_perms")
    .eq("id", callerId)
    .maybeSingle();
  if (!caller || caller.role !== "moderator" || caller.staff_perms !== null) {
    return json({ error: "FORBIDDEN" }, 403);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "BAD_JSON" }, 400);
  }
  const action = String(body.action ?? "");

  try {
    switch (action) {
      case "create":
        return await create(admin, callerId, body);
      case "set_password":
        return await setPassword(admin, callerId, body);
      case "set_disabled":
        return await setDisabled(admin, callerId, body);
      case "delete":
        return await remove(admin, callerId, body);
      default:
        return json({ error: "BAD_ACTION" }, 400);
    }
  } catch (e) {
    console.error("STAFF_ADMIN_ERROR", e);
    return json({ error: "SERVER_ERROR" }, 500);
  }
});

type Admin = ReturnType<typeof createClient>;

async function create(admin: Admin, callerId: string, b: Record<string, unknown>) {
  const phone = normalizeKz(String(b.phone ?? ""));
  const password = String(b.password ?? "");
  const fullName = String(b.full_name ?? "").trim();
  const perms = cleanPerms(b.perms);
  if (!phone) return json({ error: "BAD_PHONE" }, 400);
  if (password.length < 6) return json({ error: "WEAK_PASSWORD" }, 400);
  if (fullName.length < 2) return json({ error: "BAD_NAME" }, 400);

  const { data: created, error } = await admin.auth.admin.createUser({
    email: `${phone}@${EMAIL_DOMAIN}`,
    password,
    email_confirm: true,
    // handle_new_user профильді 'client' етіп ашады — төменде ауыстырамыз.
    user_metadata: { full_name: fullName, phone, role: "client" },
  });
  if (error || !created?.user) {
    const code = /already|registered|exists/i.test(error?.message ?? "")
      ? "PHONE_TAKEN"
      : (error?.message ?? "SERVER_ERROR");
    return json({ error: code }, 400);
  }
  const id = created.user.id;

  // Профиль триггермен ашылады; болмай қалса — өзіміз саламыз.
  const { error: upErr } = await admin.from("profiles").upsert({
    id,
    role: "moderator",
    full_name: fullName,
    phone,
    staff_perms: perms,
  });
  if (upErr) {
    // Профильсіз аккаунт қалмасын.
    await admin.auth.admin.deleteUser(id);
    console.error("STAFF_PROFILE_ERROR", upErr);
    return json({ error: "SERVER_ERROR" }, 500);
  }
  // Қос рөл бағандары (0046) — қызметкер клиент тізімінде көрінбесін.
  await admin.from("profiles")
    .update({ has_client_role: false, has_executor_role: false })
    .eq("id", id);

  await audit(admin, callerId, "staff_create", id, { phone, perms });
  return json({ ok: true, id }, 200);
}

async function setPassword(admin: Admin, callerId: string, b: Record<string, unknown>) {
  const id = String(b.user_id ?? "");
  const password = String(b.password ?? "");
  if (password.length < 6) return json({ error: "WEAK_PASSWORD" }, 400);
  if (!(await isStaff(admin, id))) return json({ error: "NOT_STAFF" }, 400);
  const { error } = await admin.auth.admin.updateUserById(id, { password });
  if (error) return json({ error: error.message }, 400);
  await audit(admin, callerId, "staff_password", id, {});
  return json({ ok: true }, 200);
}

async function setDisabled(admin: Admin, callerId: string, b: Record<string, unknown>) {
  const id = String(b.user_id ?? "");
  const disabled = b.disabled === true;
  if (!(await isStaff(admin, id))) return json({ error: "NOT_STAFF" }, 400);
  const { error } = await admin.auth.admin.updateUserById(id, {
    ban_duration: disabled ? BAN_FOREVER : "none",
  });
  if (error) return json({ error: error.message }, 400);
  // blocked_at — сервер шектеуі (0084 pre-request) мен қосымша екеуі де
  // бірден көреді (бан тек жаңа токен алуды тоқтатады).
  await admin.from("profiles").update({
    blocked_at: disabled ? new Date().toISOString() : null,
    block_reason: disabled ? "Қызметкер аккаунты өшірілді" : null,
  }).eq("id", id);
  await audit(admin, callerId, disabled ? "staff_disable" : "staff_enable", id, {});
  return json({ ok: true }, 200);
}

async function remove(admin: Admin, callerId: string, b: Record<string, unknown>) {
  const id = String(b.user_id ?? "");
  if (!(await isStaff(admin, id))) return json({ error: "NOT_STAFF" }, 400);
  const { error } = await admin.auth.admin.deleteUser(id);
  if (error) {
    // Қызметкер жазған хаттар т.б. сілтемелер жоюға бөгет болса —
    // аккаунтты біржола жабамыз да, нөмірін босатамыз (қайта ашуға болсын).
    await admin.auth.admin.updateUserById(id, {
      email: `deleted-${id}@${EMAIL_DOMAIN}`,
      ban_duration: BAN_FOREVER,
    });
    await admin.from("profiles").update({
      phone: "",
      staff_perms: [],
      blocked_at: new Date().toISOString(),
      block_reason: "Қызметкер аккаунты жойылды",
      role: "client",
      has_client_role: false,
    }).eq("id", id);
  }
  await audit(admin, callerId, "staff_delete", id, {});
  return json({ ok: true }, 200);
}

async function isStaff(admin: Admin, id: string): Promise<boolean> {
  if (!id) return false;
  const { data } = await admin
    .from("profiles")
    .select("role, staff_perms")
    .eq("id", id)
    .maybeSingle();
  return !!data && data.role === "moderator" && data.staff_perms !== null;
}

function cleanPerms(raw: unknown): string[] {
  if (!Array.isArray(raw)) return [];
  return [...new Set(raw.map(String).filter((k) => PERM_KEYS.has(k)))].sort();
}

async function audit(
  admin: Admin,
  callerId: string,
  action: string,
  targetId: string,
  details: Record<string, unknown>,
) {
  try {
    await admin.from("mod_audit_log").insert({
      moderator_id: callerId,
      action,
      target_type: "staff",
      target_id: targetId,
      details,
    });
  } catch (_) { /* журнал жазылмаса да әрекет сәтті */ }
}

/// +7/8/10-таңбалы қазақстандық нөмірден 7XXXXXXXXXX шығарады, әйтпесе null.
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
