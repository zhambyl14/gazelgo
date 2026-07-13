// Tasu · delete-account edge function
// App Store 5.1.1(v) / Play Market талабы: пайдаланушы аккаунтын қосымша
// ішінен өшіре алуы МІНДЕТТІ. verify_jwt = TRUE (тек өз аккаунтын өшіреді).
//
// БҰРЫН (0-нұсқа): auth.admin.deleteUser() → profiles CASCADE → orders.
// Бұл ЕКІ БАГ тудыратын: (1) orders.executor_id-де CASCADE жоқ — заказ
// тарихы бар орындаушы аккаунтын өшіре алмай, FK қатесімен сәтсіз аяқталады;
// (2) orders.client_id CASCADE болғандықтан, клиент өшірсе — қарсы тараптың
// (орындаушының) earnings/reviews жазбалары да жоғалады. (0020 миграциясын
// қараңыз.)
//
// ЕНДІ: аккаунт ӨШІРІЛМЕЙДІ — АНОНИМДЕЛЕДІ. Жеке дерек (аты, телефон,
// аватар, құжат фотолары) МӘҢГІ өшіріледі және STORAGE-тан да жойылады,
// кіру мүмкіндігі (email/құпиясөз) біржола жабылады — App Store/Play
// тұрғысынан бұл толыққанды «аккаунтты өшіру». Ал заказ транзакциялары
// (GPS маршруты, баға, уақыты) — заң бұзушылықты тергеу мақсатында да,
// қарсы тараптың өз тарихын сақтау үшін де — өзгеріссіз қалады
// (Пайдаланушы келісімі §6, lib/features/legal/legal_screen.dart).
import { createClient } from "jsr:@supabase/supabase-js@2";

const cors = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const ACTIVE = ["searching", "accepted", "arrived", "loading", "in_transit"];
const DOC_PATH_COLUMNS = [
  "id_doc_path",
  "license_path",
  "id_selfie_path",
  "license_selfie_path",
  "passport_path",
  "passport_selfie_path",
] as const;

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") return new Response("ok", { headers: cors });
  if (req.method !== "POST") {
    return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const jwt = (req.headers.get("authorization") ?? "").replace(
    /^Bearer\s+/i,
    "",
  );
  const { data: userData, error: authError } = await admin.auth.getUser(jwt);
  if (authError || !userData?.user) return json({ error: "AUTH" }, 401);
  const uid = userData.user.id;

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

  // ---------- storage-тан құжат/көлік/аватар файлдарын нақты өшіру ----------
  const docPaths: string[] = [];
  const { data: ep } = await admin
    .from("executor_profiles")
    .select(`${DOC_PATH_COLUMNS.join(",")},vehicle_photos`)
    .eq("user_id", uid)
    .maybeSingle();
  if (ep) {
    const row = ep as Record<string, unknown>;
    for (const k of DOC_PATH_COLUMNS) {
      const p = row[k];
      if (typeof p === "string" && p) docPaths.push(p);
    }
    for (const p of (row.vehicle_photos as string[] | null) ?? []) {
      if (p) docPaths.push(p);
    }
  }
  if (docPaths.length > 0) {
    await admin.storage.from("docs").remove(docPaths).catch(() => {});
  }

  const { data: prof } = await admin
    .from("profiles")
    .select("avatar_url")
    .eq("id", uid)
    .maybeSingle();
  const avatarUrl = prof?.avatar_url as string | null | undefined;
  if (avatarUrl) {
    const marker = "/avatars/";
    const idx = avatarUrl.indexOf(marker);
    if (idx >= 0) {
      const path = avatarUrl.slice(idx + marker.length);
      await admin.storage.from("avatars").remove([path]).catch(() => {});
    }
  }

  // ---------- жеке дерек — МӘҢГІ өшіру (кестеде) ----------
  await admin.from("profiles").update({
    full_name: "Өшірілген қолданушы",
    phone: "",
    avatar_url: null,
    deleted_at: new Date().toISOString(),
  }).eq("id", uid);

  if (ep) {
    await admin.from("executor_profiles").update({
      id_doc_path: null,
      license_path: null,
      id_selfie_path: null,
      license_selfie_path: null,
      passport_path: null,
      passport_selfie_path: null,
      vehicle_photos: [],
    }).eq("user_id", uid);
  }

  await admin.from("push_tokens").delete().eq("user_id", uid);

  // ---------- кіру мүмкіндігін біржола жабу ----------
  const lockEmail = `deleted-${uid}@phone.gazelgo.kz`;
  const randomPass = crypto.randomUUID() + crypto.randomUUID();
  const { error: lockError } = await admin.auth.admin.updateUserById(uid, {
    email: lockEmail,
    password: randomPass,
    user_metadata: {},
  });
  if (lockError) return json({ error: "DELETE_FAILED" }, 500);

  return json({ ok: true }, 200);
});

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { ...cors, "Content-Type": "application/json" },
  });
}
