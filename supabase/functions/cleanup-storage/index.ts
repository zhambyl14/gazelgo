// Tasu · cleanup-storage edge function
// pg_cron (supabase/migrations/0032_storage_retention_cron.sql) күн сайын
// осы функцияны шақырады:
//   (1) 5+ күн бұрын ЖАБЫЛҒАН қолдау тредтерін — хабарламаларымен және
//       Storage суреттерімен қоса — толық өшіреді (support_messages
//       support_threads-ке ON DELETE CASCADE-пен байланған).
//   (2) 5+ күн бұрын аяқталған/бас тартылған/мерзімі өткен заказдардың
//       Storage-тағы жүк фотоларын өшіреді. Заказдың өзі (тарих, дау
//       болғанда дәлел ретінде тарифтік/модерация есебі үшін) қалады —
//       тек `photos` бағаны бос массивке ауыстырылады.
//
// verify_jwt = false (Dashboard-та осылай қойыңыз — pg_net-тен, JWT-сіз
// шақырылады). Орнына `x-cron-secret` header тексеріледі — Edge Function
// Secrets-те сақталған CRON_SECRET-пен салыстырылады, сондықтан бұл
// endpoint-ті сырттан біреу біліп қалса да, секретсіз шақыра алмайды.
import { createClient } from "jsr:@supabase/supabase-js@2";

const RETENTION_DAYS = 5;
const MS_PER_DAY = 24 * 60 * 60 * 1000;

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") {
    return json({ error: "METHOD_NOT_ALLOWED" }, 405);
  }

  const secret = Deno.env.get("CRON_SECRET");
  if (!secret || req.headers.get("x-cron-secret") !== secret) {
    return json({ error: "FORBIDDEN" }, 403);
  }

  const admin = createClient(
    Deno.env.get("SUPABASE_URL")!,
    Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
  );

  const cutoff = new Date(Date.now() - RETENTION_DAYS * MS_PER_DAY)
    .toISOString();

  // ---------- 1) 5+ күн бұрын жабылған қолдау тредтері ----------
  let threadsDeleted = 0;
  let supportPhotosDeleted = 0;
  {
    const { data: threads } = await admin
      .from("support_threads")
      .select("id")
      .eq("status", "closed")
      .lt("closed_at", cutoff)
      .limit(500);

    const threadIds = (threads ?? []).map((t) => t.id as string);
    if (threadIds.length > 0) {
      const { data: msgs } = await admin
        .from("support_messages")
        .select("image_path")
        .in("thread_id", threadIds)
        .not("image_path", "is", null);

      const paths = (msgs ?? [])
        .map((m) => m.image_path as string | null)
        .filter((p): p is string => !!p);

      if (paths.length > 0) {
        await admin.storage.from("support").remove(paths).catch(() => {});
        supportPhotosDeleted = paths.length;
      }

      // support_messages ON DELETE CASCADE-пен бірге автоматты өшеді.
      const { error: delErr } = await admin
        .from("support_threads")
        .delete()
        .in("id", threadIds);
      if (!delErr) threadsDeleted = threadIds.length;
    }
  }

  // ---------- 2) 5+ күн бұрын аяқталған/бас тартылған заказ фотолары ----------
  let ordersCleaned = 0;
  let orderPhotosDeleted = 0;
  {
    const { data: orders } = await admin
      .from("orders")
      .select("id, photos, completed_at, cancelled_at, created_at")
      .in("status", ["completed", "cancelled", "expired"])
      .not("photos", "eq", "{}")
      .order("created_at", { ascending: true })
      .limit(500);

    for (const o of orders ?? []) {
      const paths = (o.photos as string[] | null) ?? [];
      if (paths.length === 0) continue;

      const ts = (o.completed_at ?? o.cancelled_at ?? o.created_at) as string;
      if (new Date(ts).getTime() > Date.now() - RETENTION_DAYS * MS_PER_DAY) {
        continue; // әлі сақтау мерзімі толмаған
      }

      await admin.storage.from("orders").remove(paths).catch(() => {});
      const { error: updErr } = await admin
        .from("orders")
        .update({ photos: [] })
        .eq("id", o.id);
      if (!updErr) {
        ordersCleaned++;
        orderPhotosDeleted += paths.length;
      }
    }
  }

  return json({
    ok: true,
    threadsDeleted,
    supportPhotosDeleted,
    ordersCleaned,
    orderPhotosDeleted,
  }, 200);
});

function json(data: unknown, status: number): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}
