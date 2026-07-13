// Tasu · telegram-webhook edge function
// Telegram Bot API вебхукы: тіркелуде телефонды растайды (SMS-сіз, тегін).
//
// Ағын (0026 миграциясы):
//   1) Пайдаланушы қосымшадан `t.me/<bot>?start=<токен>` арқылы ботты ашады.
//      → Telegram бізге `/start <токен>` мәтінін жібереді.
//      → Біз токенді осы chat_id-мен байланыстырып, «Нөмірімді бөлісу»
//        түймесі бар пернетақтаны көрсетеміз.
//   2) Пайдаланушы түймені басады → Telegram НӨМІРДІ ӨЗІ РАСТАП, ботқа
//      contact жібереді (contact.user_id == from.id болса ғана — өз нөмірі).
//      → Біз сол chat_id-дегі күтіп тұрған токенді verified=true қыламыз.
//
// Verify JWT = OFF (Telegram JWT жібермейді). Оның орнына вебхукты
// `secret_token` арқылы тіркейміз — Telegram әр сұраныста
// `X-Telegram-Bot-Api-Secret-Token` header-ін жібереді, соны тексереміз.
//
// Қажет Edge Function Secrets: TELEGRAM_BOT_TOKEN, TELEGRAM_WEBHOOK_SECRET.
import { createClient } from "jsr:@supabase/supabase-js@2";

const BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
const WEBHOOK_SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";
const API = `https://api.telegram.org/bot${BOT_TOKEN}`;

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("ok", { status: 200 });

  // Тек нағыз Telegram жібере алады (setWebhook кезінде орнатылған құпия).
  const secret = req.headers.get("X-Telegram-Bot-Api-Secret-Token");
  if (!WEBHOOK_SECRET || secret !== WEBHOOK_SECRET) {
    return new Response("forbidden", { status: 403 });
  }

  let update: TgUpdate;
  try {
    update = await req.json();
  } catch {
    return new Response("ok", { status: 200 }); // Telegram-ды қайталатпаймыз
  }

  try {
    await handle(update);
  } catch (e) {
    console.error("TG_HANDLE_ERROR", e);
  }
  // Әрқашан 200 — әйтпесе Telegram сол update-ті қайта-қайта жібере береді.
  return new Response("ok", { status: 200 });
});

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

async function handle(update: TgUpdate) {
  const msg = update.message;
  if (!msg) return;
  const chatId = msg.chat?.id;
  if (!chatId) return;

  // 1) /start <токен>
  const text = (msg.text ?? "").trim();
  if (text.startsWith("/start")) {
    const parts = text.split(/\s+/);
    const token = parts.length > 1 ? parts[1] : "";
    if (!token) {
      await send(chatId,
        "Сәлеметсіз бе! Тіркелуді аяқтау үшін Tasu қосымшасынан «Telegram арқылы растау» түймесін басыңыз.");
      return;
    }
    // Токенді осы chat_id-ге байлаймыз (біткен болса — елемейді)
    const { data: row } = await admin
      .from("telegram_verifications")
      .select("token, verified, expires_at")
      .eq("token", token)
      .gt("expires_at", new Date().toISOString())
      .maybeSingle();
    if (!row) {
      await send(chatId,
        "Сілтеме ескірген. Қосымшаға оралып, «Telegram арқылы растау»-ды қайта басыңыз.");
      return;
    }
    await admin
      .from("telegram_verifications")
      .update({ telegram_chat_id: chatId })
      .eq("token", token);
    await send(
      chatId,
      "Нөміріңізді растау үшін төмендегі түймені басыңыз 👇",
      {
        keyboard: [[{ text: "📱 Нөмірімді бөлісу", request_contact: true }]],
        resize_keyboard: true,
        one_time_keyboard: true,
      },
    );
    return;
  }

  // 2) Контакт бөлісу
  const contact = msg.contact;
  if (contact) {
    // Тек ӨЗ нөмірін бөліскенде ғана (басқа біреудің контактісі емес).
    if (!contact.user_id || contact.user_id !== msg.from?.id) {
      await send(chatId,
        "Өтінеміз, «📱 Нөмірімді бөлісу» түймесі арқылы ӨЗ нөміріңізді жіберіңіз.");
      return;
    }
    const phone = normalizeKz(contact.phone_number);
    if (!phone) {
      await send(chatId,
        "Нөмір қазақстандық форматта емес (+7 7XX XXX XX XX). Басқа нөмірмен көріңіз.",
        { remove_keyboard: true });
      return;
    }
    // Осы chat_id-дегі ең соңғы күтіп тұрған (расталмаған) токенді табамыз.
    const { data: pending } = await admin
      .from("telegram_verifications")
      .select("token")
      .eq("telegram_chat_id", chatId)
      .eq("verified", false)
      .gt("expires_at", new Date().toISOString())
      .order("created_at", { ascending: false })
      .limit(1)
      .maybeSingle();
    if (!pending) {
      await send(chatId,
        "Белсенді тіркелу табылмады. Қосымшадан «Telegram арқылы растау»-ды қайта бастаңыз.",
        { remove_keyboard: true });
      return;
    }
    await admin
      .from("telegram_verifications")
      .update({
        phone,
        verified: true,
        telegram_user_id: contact.user_id,
      })
      .eq("token", pending.token);
    await send(
      chatId,
      "✅ Нөміріңіз расталды! Tasu қосымшасына оралып, тіркелуді жалғастырыңыз.",
      { remove_keyboard: true },
    );
    return;
  }
}

/// +7/8/10-таңбалы қазақстандық нөмірден 7XXXXXXXXXX шығарады, әйтпесе null.
/// Тек ҚАЗАҚСТАН нөмірлері: екінші таңба да «7» болуы керек (+77...) —
/// ресейлік нөмірлер +79... болып басталады (екеуі +7 ел кодын бөліседі).
function normalizeKz(raw: string): string | null {
  let d = (raw ?? "").replace(/\D/g, "");
  if (d.length === 11 && d.startsWith("8")) d = "7" + d.slice(1);
  if (d.length === 10) d = "7" + d;
  if (d.length === 11 && d.startsWith("77")) return d;
  return null;
}

async function send(
  chatId: number,
  text: string,
  replyMarkup?: Record<string, unknown>,
) {
  try {
    await fetch(`${API}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: chatId,
        text,
        ...(replyMarkup ? { reply_markup: replyMarkup } : {}),
      }),
    });
  } catch (e) {
    console.error("TG_SEND_ERROR", e);
  }
}

interface TgUpdate {
  message?: {
    text?: string;
    chat?: { id: number };
    from?: { id: number };
    contact?: {
      phone_number: string;
      user_id?: number;
    };
  };
}
