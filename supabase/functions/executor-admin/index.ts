// Tasu · executor-admin edge function
// Модератор орындаушыларды қолмен басқарады:
//   create — жаңа орындаушы аккаунтын ашу (құжатсыз, бірден расталған);
//   delete — орындаушыны жою (ТЕК толық модератор; тарихы болса анонимделеді);
//   delete_client — клиентті жою (ТЕК толық модератор; әрқашан анонимделеді);
//   update — аты, телефоны, қаласы, көлігі (түрі, маркасы, моделі, жылы,
//            мемлекеттік нөмірі) деректерін өзгерту.
//
// verify_jwt = TRUE. create/update — толық модератор не «executors_edit»
// рұқсаты бар қызметкер; delete — тек толық модератор (staff_perms IS NULL).
// Орындаушы нөмірі Telegram арқылы кіреді (tg-login) — құпиясөз кездейсоқ
// қойылады, адам оны көрмейді.
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const EMAIL_DOMAIN = "phone.gazelgo.kz";

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
    { auth: { persistSession: false, autoRefreshToken: false } },
  );

  // ---------- шақырушы: модератор + 'executors' рұқсаты ----------
  const jwt = (req.headers.get("authorization") ?? "").replace(/^Bearer\s+/i, "");
  const { data: userData, error: authError } = await admin.auth.getUser(jwt);
  if (authError || !userData?.user) return json({ error: "AUTH" }, 401);
  const callerId = userData.user.id;
  const { data: caller } = await admin
    .from("profiles")
    .select("role, staff_perms")
    .eq("id", callerId)
    .maybeSingle();
  if (!caller || caller.role !== "moderator") {
    return json({ error: "FORBIDDEN" }, 403);
  }
  const isFull = caller.staff_perms === null;
  const can = (perm: string) =>
    isFull ||
    (Array.isArray(caller.staff_perms) && caller.staff_perms.includes(perm));

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "BAD_JSON" }, 400);
  }
  const action = String(body.action ?? "");

  // create/update — 'executors_edit'; delete — ТЕК толық модератор.
  if ((action === "create" || action === "update") && !can("executors_edit")) {
    return json({ error: "NO_PERMISSION" }, 403);
  }
  if (
    (action === "delete" || action === "delete_client" ||
      action === "delete_draft") && !isFull
  ) {
    return json({ error: "NO_PERMISSION" }, 403);
  }

  try {
    switch (action) {
      case "create":
        return await create(admin, callerId, body);
      case "update":
        return await update(admin, callerId, body);
      case "delete_draft":
        return await removeDraft(admin, callerId, body);
      case "delete_client":
        return await removeClient(admin, callerId, body);
      case "delete":
        return await remove(admin, callerId, body);
      default:
        return json({ error: "BAD_ACTION" }, 400);
    }
  } catch (e) {
    console.error("EXECUTOR_ADMIN_ERROR", e);
    return json({ error: "SERVER_ERROR" }, 500);
  }
});

type Admin = ReturnType<typeof createClient>;

interface Vehicle {
  vehicle_type: string;
  vehicle_brand: string;
  vehicle_model: string;
  vehicle_year: number | null;
  vehicle_plate: string;
  city: string | null;
  delivery_on_foot?: boolean;
  vehicle_color?: string;
}

/// Көлік өрістерін тексеріп тазалайды; қате болса мәтінді қайтарады.
async function readVehicle(
  admin: Admin,
  b: Record<string, unknown>,
): Promise<Vehicle | string> {
  const type = String(b.vehicle_type ?? "").trim();
  const brand = String(b.vehicle_brand ?? "").trim();
  const model = String(b.vehicle_model ?? "").trim();
  const plate = String(b.vehicle_plate ?? "").trim().toUpperCase();
  const city = String(b.city ?? "").trim();
  let year: number | null = null;
  if (b.vehicle_year != null && String(b.vehicle_year).trim() !== "") {
    year = Number(b.vehicle_year);
    if (!Number.isInteger(year) || year < 1950 || year > 2100) {
      return "BAD_YEAR";
    }
  }
  if (!type || type === "umay") return "BAD_VEHICLE_TYPE";
  // Жаяу курьер («Доставка», 0090): көлік деректері керек емес.
  const onFoot = type === "delivery" && b.delivery_on_foot === true;
  if (!onFoot && !brand) return "BAD_BRAND";
  if (!onFoot && !plate) return "BAD_PLATE";
  // Түр каталогта болуы керек (кесте болмаса тексермейміз).
  const { data: vt, error } = await admin
    .from("vehicle_types")
    .select("code")
    .eq("code", type)
    .maybeSingle();
  if (!error && !vt) return "BAD_VEHICLE_TYPE";
  return {
    vehicle_type: type,
    vehicle_brand: onFoot ? "" : brand,
    vehicle_model: onFoot ? "" : model,
    vehicle_year: onFoot ? null : year,
    vehicle_plate: onFoot ? "" : plate,
    city: city || null,
    // Көлік түсінің коды (0093): тек клиент жібергенде жазылады — баған
    // жоқ серверде (миграцияға дейін) бұрынғы мінез сақталады.
    ...(!onFoot && /^[a-z]{3,12}$/.test(String(b.vehicle_color ?? ""))
      ? { vehicle_color: String(b.vehicle_color) }
      : {}),
    // Баған (0090) тек «Доставка» түрінде және клиент жібергенде жазылады.
    ...(type === "delivery" && typeof b.delivery_on_foot === "boolean"
      ? { delivery_on_foot: onFoot }
      : {}),
  };
}

async function create(admin: Admin, callerId: string, b: Record<string, unknown>) {
  const phone = normalizeKz(String(b.phone ?? ""));
  const fullName = String(b.full_name ?? "").trim();
  if (!phone) return json({ error: "BAD_PHONE" }, 400);
  if (fullName.length < 2) return json({ error: "BAD_NAME" }, 400);
  const v = await readVehicle(admin, b);
  if (typeof v === "string") return json({ error: v }, 400);

  const { data: created, error } = await admin.auth.admin.createUser({
    email: `${phone}@${EMAIL_DOMAIN}`,
    password: randomPassword(),
    email_confirm: true,
    user_metadata: { full_name: fullName, phone, role: "executor" },
  });
  if (error || !created?.user) {
    const code = /already|registered|exists/i.test(error?.message ?? "")
      ? "PHONE_TAKEN"
      : (error?.message ?? "SERVER_ERROR");
    return json({ error: code }, 400);
  }
  const id = created.user.id;

  const { error: pErr } = await admin.from("profiles").upsert({
    id,
    role: "executor",
    full_name: fullName,
    phone,
  });
  const now = new Date().toISOString();
  const { error: eErr } = pErr ? { error: pErr } : await admin
    .from("executor_profiles")
    .insert({
      user_id: id,
      status: "approved",
      vehicle_size: "small",
      ...v,
      moderated_by: callerId,
      moderated_at: now,
    });
  if (pErr || eErr) {
    // Жартылай аккаунт қалмасын.
    await admin.auth.admin.deleteUser(id);
    console.error("EXECUTOR_CREATE_ERROR", pErr ?? eErr);
    return json({ error: "SERVER_ERROR" }, 500);
  }
  await admin.from("profiles")
    .update({ has_client_role: false, has_executor_role: true })
    .eq("id", id);

  await audit(admin, callerId, "executor_create", id, { phone, ...v });
  return json({ ok: true, id }, 200);
}

async function update(admin: Admin, callerId: string, b: Record<string, unknown>) {
  const id = String(b.user_id ?? "");
  if (!id) return json({ error: "BAD_USER" }, 400);
  const fullName = String(b.full_name ?? "").trim();
  if (fullName.length < 2) return json({ error: "BAD_NAME" }, 400);
  const v = await readVehicle(admin, b);
  if (typeof v === "string") return json({ error: v }, 400);

  const { data: ep } = await admin
    .from("executor_profiles")
    .select("user_id")
    .eq("user_id", id)
    .maybeSingle();
  if (!ep) return json({ error: "NOT_FOUND" }, 404);
  const { data: prof } = await admin
    .from("profiles")
    .select("phone")
    .eq("id", id)
    .maybeSingle();

  // Телефон: өзгерсе — кіру email-і де (нөмір@домен) ауысады.
  const rawPhone = String(b.phone ?? "").trim();
  let phone = prof?.phone ?? "";
  if (rawPhone) {
    const norm = normalizeKz(rawPhone);
    if (!norm) return json({ error: "BAD_PHONE" }, 400);
    if (norm !== phone) {
      const { error } = await admin.auth.admin.updateUserById(id, {
        email: `${norm}@${EMAIL_DOMAIN}`,
        email_confirm: true,
        user_metadata: { full_name: fullName, phone: norm },
      });
      if (error) {
        const code = /already|registered|exists/i.test(error.message)
          ? "PHONE_TAKEN"
          : error.message;
        return json({ error: code }, 400);
      }
      phone = norm;
    }
  }

  const { error: pErr } = await admin.from("profiles")
    .update({ full_name: fullName, phone })
    .eq("id", id);
  const { error: eErr } = pErr ? { error: pErr } : await admin
    .from("executor_profiles")
    .update(v)
    .eq("user_id", id);
  if (pErr || eErr) {
    console.error("EXECUTOR_UPDATE_ERROR", pErr ?? eErr);
    return json({ error: "SERVER_ERROR" }, 500);
  }
  await audit(admin, callerId, "executor_update", id, {
    full_name: fullName,
    phone,
    ...v,
  });
  return json({ ok: true }, 200);
}

const ACTIVE_ORDER = ["searching", "accepted", "arrived", "loading", "in_transit"];
const DOC_PATH_COLUMNS = [
  "id_doc_path",
  "license_path",
  "id_selfie_path",
  "license_selfie_path",
  "passport_path",
  "passport_selfie_path",
  "tech_passport_path",
  "tech_passport_selfie_path",
  "insurance_path",
  "insurance_selfie_path",
] as const;

/// Орындаушыны жою (тек толық модератор). Заказ тарихы жоқ болса — аккаунт
/// біржола өшеді. Тарихы болса (orders.executor_id FK) — delete-account
/// сияқты АНОНИМДЕЛЕДІ: жеке дерек өшіп, кіру жабылады, заказ жазбалары
/// (қарсы тараптың тарихы) қалады, орындаушы тізімнен кетеді.
async function remove(admin: Admin, callerId: string, b: Record<string, unknown>) {
  const id = String(b.user_id ?? "");
  if (!id) return json({ error: "BAD_USER" }, 400);
  if (id === callerId) return json({ error: "FORBIDDEN" }, 403);

  const { data: ep } = await admin
    .from("executor_profiles")
    .select(`${DOC_PATH_COLUMNS.join(",")},vehicle_photos,busy_order_id`)
    .eq("user_id", id)
    .maybeSingle();
  if (!ep) return json({ error: "NOT_FOUND" }, 404);
  const { data: target } = await admin
    .from("profiles")
    .select("role")
    .eq("id", id)
    .maybeSingle();
  if (!target || target.role === "moderator") {
    return json({ error: "FORBIDDEN" }, 403);
  }

  const { data: active, error: aErr } = await admin
    .from("orders")
    .select("id")
    .eq("executor_id", id)
    .in("status", ACTIVE_ORDER)
    .limit(1);
  if (aErr) return json({ error: "SERVER_ERROR" }, 500);
  if ((active ?? []).length > 0 || ep.busy_order_id) {
    return json({ error: "HAS_ACTIVE_ORDERS" }, 400);
  }

  // Құжат файлдары: аяқталған заказы болса 30 күн сақталады (тергеу
  // сұрауы үшін, delete-account-пен бірдей), әйтпесе бірден өшеді.
  const row = ep as Record<string, unknown>;
  const paths: string[] = [];
  for (const k of DOC_PATH_COLUMNS) {
    const p = row[k];
    if (typeof p === "string" && p) paths.push(p);
  }
  for (const p of (row.vehicle_photos as string[] | null) ?? []) {
    if (p) paths.push(p);
  }
  const { count: done } = await admin
    .from("orders")
    .select("id", { count: "exact", head: true })
    .eq("executor_id", id)
    .eq("status", "completed");
  if (paths.length > 0) {
    if ((done ?? 0) > 0) {
      const purgeAfter = new Date(Date.now() + 30 * 86400_000).toISOString();
      try {
        await admin.from("storage_purge_queue").insert(
          paths.map((path) => ({ bucket: "docs", path, purge_after: purgeAfter })),
        );
      } catch (_) { /* кезек болмаса да жалғасамыз */ }
    } else {
      try {
        await admin.storage.from("docs").remove(paths);
      } catch (_) { /* файл өшпесе де аккаунт өшеді */ }
    }
  }

  const { data: before } = await admin
    .from("profiles")
    .select("full_name, phone")
    .eq("id", id)
    .maybeSingle();

  // Клиент ретінде заказы бар аккаунтты біржола өшіруге болмайды:
  // orders.client_id CASCADE — қарсы тараптың тарихы жоғалар еді.
  const { count: asClient } = await admin
    .from("orders")
    .select("id", { count: "exact", head: true })
    .eq("client_id", id);
  let hard = (asClient ?? 0) === 0;
  if (hard) {
    const { error: delErr } = await admin.auth.admin.deleteUser(id);
    if (delErr) hard = false;
  }
  if (!hard && !(await anonymize(admin, id))) {
    return json({ error: "SERVER_ERROR" }, 500);
  }

  await audit(admin, callerId, "executor_delete", id, {
    full_name: before?.full_name ?? null,
    phone: before?.phone ?? null,
    anonymized: !hard,
  });
  return json({ ok: true, anonymized: !hard }, 200);
}

/// Аккаунтты АНОНИМДЕУ (delete-account сияқты): жеке дерек өшеді, кіру
/// жабылады, заказ жазбалары (қарсы тараптың тарихы) қалады, клиент/
/// орындаушы тізімдерінен кетеді. Сәтті болса true.
async function anonymize(admin: Admin, id: string): Promise<boolean> {
  await admin.from("profiles").update({
    full_name: "Өшірілген қолданушы",
    phone: "",
    avatar_url: null,
    deleted_at: new Date().toISOString(),
    has_client_role: false,
    has_executor_role: false,
  }).eq("id", id);
  try { await admin.from("push_tokens").delete().eq("user_id", id); } catch (_) { /* */ }
  const { error: epErr } = await admin
    .from("executor_profiles")
    .delete()
    .eq("user_id", id);
  if (epErr) {
    // Тізімде көрінсе де, кіре алмайтындай болсын.
    await admin.from("executor_profiles").update({
      status: "blocked",
      id_doc_path: null,
      license_path: null,
      id_selfie_path: null,
      license_selfie_path: null,
      passport_path: null,
      passport_selfie_path: null,
      vehicle_photos: [],
    }).eq("user_id", id);
  }
  const { error: lockErr } = await admin.auth.admin.updateUserById(id, {
    email: `deleted-${id}@${EMAIL_DOMAIN}`,
    password: crypto.randomUUID() + crypto.randomUUID(),
    user_metadata: {},
    ban_duration: "876000h",
  });
  if (lockErr) {
    console.error("ACCOUNT_LOCK_ERROR", lockErr);
    return false;
  }
  return true;
}

/// Клиентті жою (тек толық модератор). Әрқашан анонимдеу: клиенттің
/// заказдары орындаушылардың табыс/пікір тарихымен байланысты, оларды
/// өшіруге болмайды. Белсенді заказы барда тоқтатамыз.
async function removeClient(admin: Admin, callerId: string, b: Record<string, unknown>) {
  const id = String(b.user_id ?? "");
  if (!id) return json({ error: "BAD_USER" }, 400);
  if (id === callerId) return json({ error: "FORBIDDEN" }, 403);

  const { data: target } = await admin
    .from("profiles")
    .select("role, full_name, phone, avatar_url, deleted_at")
    .eq("id", id)
    .maybeSingle();
  if (!target || target.role === "moderator" || target.deleted_at) {
    return json({ error: "NOT_FOUND" }, 404);
  }

  const { data: active, error: aErr } = await admin
    .from("orders")
    .select("id")
    .or(`client_id.eq.${id},executor_id.eq.${id}`)
    .in("status", ACTIVE_ORDER)
    .limit(1);
  if (aErr) return json({ error: "SERVER_ERROR" }, 500);
  if ((active ?? []).length > 0) {
    return json({ error: "HAS_ACTIVE_ORDERS" }, 400);
  }

  // Аватар файлы: аяқталған заказы болса 30 күн сақталады, әйтпесе бірден өшеді.
  const marker = "/avatars/";
  const url = target.avatar_url as string | null;
  const idx = url ? url.indexOf(marker) : -1;
  if (url && idx >= 0) {
    const path = url.slice(idx + marker.length);
    const { count: done } = await admin
      .from("orders")
      .select("id", { count: "exact", head: true })
      .or(`client_id.eq.${id},executor_id.eq.${id}`)
      .eq("status", "completed");
    if ((done ?? 0) > 0) {
      try {
        await admin.from("storage_purge_queue").insert({
          bucket: "avatars",
          path,
          purge_after: new Date(Date.now() + 30 * 86400_000).toISOString(),
        });
      } catch (_) { /* */ }
    } else {
      try { await admin.storage.from("avatars").remove([path]); } catch (_) { /* */ }
    }
  }

  if (!(await anonymize(admin, id))) return json({ error: "SERVER_ERROR" }, 500);
  await audit(admin, callerId, "client_delete", id, {
    full_name: target.full_name ?? null,
    phone: target.phone ?? null,
  });
  return json({ ok: true }, 200);
}

const UUID_RE = /[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}/i;

/// Тіркелуді аяқтамаған адамның аккаунтын жою (тек толық модератор), ол
/// қайта таза тіркеле алуы үшін: аккаунт + осы нөмірдің аяқталмаған
/// жазбалары өшеді. САҚТЫҚ: орындаушы профилі НЕ заказы бар аккаунтқа
/// тиіспейміз (нағыз пайдаланушы) — қате қайтарамыз. Аккаунт мүлдем
/// ашылмаған болса (мыс. Telegram растауда тоқтаған) — тек жазба өшеді.
async function removeDraft(admin: Admin, callerId: string, b: Record<string, unknown>) {
  const draftId = String(b.draft_id ?? "");
  if (!draftId) return json({ error: "BAD_USER" }, 400);

  const { data: draft } = await admin
    .from("registration_drafts")
    .select("id, draft_key, phone, full_name, completed_at")
    .eq("id", draftId)
    .maybeSingle();
  if (!draft) return json({ error: "NOT_FOUND" }, 404);
  if (draft.completed_at) return json({ error: "DRAFT_COMPLETED" }, 400);

  // Аккаунтты табу: кілттегі UUID бойынша, болмаса телефон бойынша.
  const phone = String(draft.phone ?? "").replace(/\D/g, "");
  let userId: string | null = String(draft.draft_key ?? "").match(UUID_RE)?.[0] ?? null;
  if (userId) {
    const { data: p } = await admin.from("profiles").select("id").eq("id", userId).maybeSingle();
    if (!p) userId = null;
  }
  if (!userId && phone.length >= 10) {
    const { data: p } = await admin.from("profiles").select("id").eq("phone", phone).maybeSingle();
    userId = (p?.id as string | undefined) ?? null;
  }

  let deletedAccount = false;
  if (userId) {
    if (userId === callerId) return json({ error: "FORBIDDEN" }, 403);
    const { data: target } = await admin
      .from("profiles")
      .select("role")
      .eq("id", userId)
      .maybeSingle();
    if (!target || target.role === "moderator") return json({ error: "FORBIDDEN" }, 403);

    const { data: ep } = await admin
      .from("executor_profiles").select("user_id").eq("user_id", userId).maybeSingle();
    const { count: orders } = await admin
      .from("orders")
      .select("id", { count: "exact", head: true })
      .or(`client_id.eq.${userId},executor_id.eq.${userId}`);
    if (ep || (orders ?? 0) > 0) return json({ error: "ACCOUNT_IN_USE" }, 400);

    const { error: delErr } = await admin.auth.admin.deleteUser(userId);
    if (delErr) {
      if (!(await anonymize(admin, userId))) return json({ error: "SERVER_ERROR" }, 500);
    }
    deletedAccount = true;
  }

  // Осы нөмірдің аяқталмаған жазбалары (және осы жазба) өшеді.
  await admin.from("registration_drafts").delete().eq("id", draftId);
  if (phone.length >= 10) {
    try {
      await admin.from("registration_drafts").delete()
        .eq("phone", draft.phone as string).is("completed_at", null);
    } catch (_) { /* */ }
  }

  await audit(admin, callerId, "draft_account_delete", userId ?? draftId, {
    full_name: draft.full_name ?? null,
    phone: draft.phone ?? null,
    account_deleted: deletedAccount,
  });
  return json({ ok: true, account_deleted: deletedAccount }, 200);
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
      target_type: "executor",
      target_id: targetId,
      details,
    });
  } catch (_) { /* журнал жазылмаса да әрекет сәтті */ }
}

function randomPassword(): string {
  const b = new Uint8Array(24);
  crypto.getRandomValues(b);
  return [...b].map((x) => x.toString(16).padStart(2, "0")).join("");
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
