// Tasu · executor-admin edge function
// Модератор орындаушыларды қолмен басқарады:
//   create — жаңа орындаушы аккаунтын ашу (құжатсыз, бірден расталған);
//   update — аты, телефоны, қаласы, көлігі (түрі, маркасы, моделі, жылы,
//            мемлекеттік нөмірі) деректерін өзгерту.
//
// verify_jwt = TRUE. Шақырушы модератор болуы шарт: толық модератор
// (staff_perms IS NULL) не 'executors' рұқсаты бар қызметкер.
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
  if (
    caller.staff_perms !== null &&
    !(Array.isArray(caller.staff_perms) &&
      caller.staff_perms.includes("executors"))
  ) {
    return json({ error: "NO_PERMISSION" }, 403);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ error: "BAD_JSON" }, 400);
  }

  try {
    switch (String(body.action ?? "")) {
      case "create":
        return await create(admin, callerId, body);
      case "update":
        return await update(admin, callerId, body);
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
  if (!brand) return "BAD_BRAND";
  if (!plate) return "BAD_PLATE";
  // Түр каталогта болуы керек (кесте болмаса тексермейміз).
  const { data: vt, error } = await admin
    .from("vehicle_types")
    .select("code")
    .eq("code", type)
    .maybeSingle();
  if (!error && !vt) return "BAD_VEHICLE_TYPE";
  return {
    vehicle_type: type,
    vehicle_brand: brand,
    vehicle_model: model,
    vehicle_year: year,
    vehicle_plate: plate,
    city: city || null,
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
