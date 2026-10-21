// Tasu · telegram-webhook edge function
// Telegram Bot API вебхукы: кіруде/тіркелуде телефонды растайды (SMS-сіз, тегін).
//
// Ағын (0026 миграциясы):
//   1) Пайдаланушы қосымшадан `t.me/<bot>?start=<токен>` арқылы ботты ашады.
//      → Telegram бізге `/start <токен>` мәтінін жібереді.
//      → Біз токенді осы chat_id-мен байланыстырып, ХАТТЫҢ АСТЫНА
//        «📱 Нөмірімді бөлісу» inline түймесін жібереміз (+ пернетақта
//        түймесін қосалқы жол ретінде).
//   2) Inline түйме Mini App-ты (web/tg/index.html) ашады, ол бірден
//      Telegram-ның «Нөмірді бөлісу» терезесін шығарады. Пернетақта
//      түймесінен айырмашылығы: хатпен бірге тұрады, жүйелік пернетақта
//      ашық тұрса да көрінеді (бұрын адамдар түймені таппай қалатын).
//      Келісілсе → Telegram НӨМІРДІ ӨЗІ РАСТАП, ботқа
//      contact жібереді (contact.user_id == from.id болса ғана — өз нөмірі).
//      → Біз сол chat_id-дегі күтіп тұрған токенді verified=true қыламыз.
//
// ТІЛ (0085): бот қосымшаның қай тілінен келсе, СОЛ тілде жауап береді —
// токенмен бірге сақталған `telegram_verifications.lang` ('kk' | 'ru').
// Токен жоқ болса — Telegram-ның өз тілі (language_code), әдепкі қазақша.
//
// Verify JWT = OFF (Telegram JWT жібермейді). Оның орнына вебхукты
// `secret_token` арқылы тіркейміз — Telegram әр сұраныста
// `X-Telegram-Bot-Api-Secret-Token` header-ін жібереді, соны тексереміз.
//
// Қажет Edge Function Secrets: TELEGRAM_BOT_TOKEN, TELEGRAM_WEBHOOK_SECRET.
// Қалауынша: TG_CONTACT_APP_URL — Mini App беті (әдепкі: веб домендегі /tg/).
import { createClient } from "jsr:@supabase/supabase-js@2";

const BOT_TOKEN = Deno.env.get("TELEGRAM_BOT_TOKEN") ?? "";
const WEBHOOK_SECRET = Deno.env.get("TELEGRAM_WEBHOOK_SECRET") ?? "";
const API = `https://api.telegram.org/bot${BOT_TOKEN}`;
/// Mini App беті (Cloudflare Pages, `main` тармағы). Тізім — домен ауысқанда
/// ескісі мен жаңасын қатар ұстауға болсын деп; бірінші жарияланғаны алынады.
const CONTACT_APP_URLS = [
  Deno.env.get("TG_CONTACT_APP_URL") ?? "https://gazelgo.pages.dev/tg/",
];

type Lang = "kk" | "ru";

/// Боттың барлық мәтіні — екі тілде.
const T = {
  kk: {
    share: "📱 Нөмірімді бөлісу",
    hello:
      "Сәлеметсіз бе! Кіру үшін Tasu қосымшасында нөміріңізді жазып, «Telegram арқылы растау» түймесін басыңыз.",
    expired:
      "Сілтеме ескірген. Қосымшаға оралып, «Telegram арқылы растау»-ды қайта басыңыз.",
    notOwn:
      "Өтінеміз, «📱 Нөмірімді бөлісу» түймесі арқылы ӨЗ нөміріңізді жіберіңіз.",
    notKz:
      "Нөмір қазақстандық форматта емес (+7 7XX XXX XX XX). Басқа нөмірмен көріңіз.",
    done: "✅ Нөміріңіз расталды! Tasu қосымшасына оралыңыз — бірден кіресіз.",
    noPending:
      "Белсенді растау табылмады. Қосымшадан «Telegram арқылы растау»-ды қайта бастаңыз.",
    welcome: "Tasu-ға қош келдіңіз! Кіру үшін нөміріңізді растайық.",
    pressBelow: "Нөміріңізді растау үшін төмендегі түймені басыңыз 👇",
  },
  ru: {
    share: "📱 Поделиться номером",
    hello:
      "Здравствуйте! Чтобы войти, введите номер в приложении Tasu и нажмите «Подтвердить через Telegram».",
    expired:
      "Ссылка устарела. Вернитесь в приложение и снова нажмите «Подтвердить через Telegram».",
    notOwn:
      "Пожалуйста, отправьте СВОЙ номер кнопкой «📱 Поделиться номером».",
    notKz:
      "Номер не казахстанский (+7 7XX XXX XX XX). Попробуйте другой номер.",
    done: "✅ Номер подтверждён! Вернитесь в приложение Tasu — вход выполнится сразу.",
    noPending:
      "Активное подтверждение не найдено. Начните заново в приложении: «Подтвердить через Telegram».",
    welcome: "Добро пожаловать в Tasu! Давайте подтвердим ваш номер для входа.",
    pressBelow: "Чтобы подтвердить номер, нажмите кнопку ниже 👇",
  },
} as const;

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

/// Жазбадағы тіл (0085 бағаны) — болмаса Telegram-ның тілі.
function langOf(row: Record<string, unknown> | null, fallback: Lang): Lang {
  const v = row?.lang;
  return v === "ru" ? "ru" : v === "kk" ? "kk" : fallback;
}

async function handle(update: TgUpdate) {
  const msg = update.message;
  if (!msg) return;
  const chatId = msg.chat?.id;
  if (!chatId) return;
  // Токенсіз жағдайда — Telegram интерфейсінің тілі.
  const tgLang: Lang = (msg.from?.language_code ?? "").startsWith("ru")
    ? "ru"
    : "kk";

  // 1) /start <токен>
  const text = (msg.text ?? "").trim();
  if (text.startsWith("/start")) {
    const parts = text.split(/\s+/);
    const token = parts.length > 1 ? parts[1] : "";
    if (!token) {
      // Токенсіз /start: бұрын басталған растау болса — түймені қайта
      // береміз (адамдар түймені таппай /start-ты қайта жазады).
      const pending = await pendingRow(chatId);
      if (pending) {
        await askContact(chatId, langOf(pending, tgLang));
        return;
      }
      await send(chatId, T[tgLang].hello);
      return;
    }
    // Токенді осы chat_id-ге байлаймыз (біткен болса — елемейді).
    // `*` — 0085 (lang) әлі қолданылмаған серверде де сұраныс бұзылмасын.
    const { data: row } = await admin
      .from("telegram_verifications")
      .select("*")
      .eq("token", token)
      .gt("expires_at", new Date().toISOString())
      .maybeSingle();
    if (!row) {
      await send(chatId, T[tgLang].expired);
      return;
    }
    await admin
      .from("telegram_verifications")
      .update({ telegram_chat_id: chatId })
      .eq("token", token);
    await askContact(chatId, langOf(row, tgLang), true);
    return;
  }

  // 2) Контакт бөлісу
  const contact = msg.contact;
  if (contact) {
    const pending = await pendingRow(chatId);
    const lang = langOf(pending, tgLang);
    // Тек ӨЗ нөмірін бөліскенде ғана (басқа біреудің контактісі емес).
    if (!contact.user_id || contact.user_id !== msg.from?.id) {
      await send(chatId, T[lang].notOwn);
      return;
    }
    const phone = normalizeKz(contact.phone_number);
    if (!phone) {
      await send(chatId, T[lang].notKz, { remove_keyboard: true });
      return;
    }
    if (!pending) {
      // Mini App (tg-contact) нөмірді бұрын растап қойса — бұл хат сол
      // бөлісудің көшірмесі ғана: қате емес, «расталды» деп жауап береміз.
      const { data: done } = await admin
        .from("telegram_verifications")
        .select("*")
        .eq("telegram_chat_id", chatId)
        .eq("verified", true)
        .gt("expires_at", new Date().toISOString())
        .limit(1)
        .maybeSingle();
      if (done) {
        await send(chatId, T[langOf(done, tgLang)].done, {
          remove_keyboard: true,
        });
        return;
      }
      await send(chatId, T[tgLang].noPending, { remove_keyboard: true });
      return;
    }
    await admin
      .from("telegram_verifications")
      .update({
        phone,
        verified: true,
        telegram_user_id: contact.user_id,
      })
      .eq("token", pending.token as string);
    await send(chatId, T[lang].done, { remove_keyboard: true });
    return;
  }

  // 3) Басқа кез келген хат (нөмірді мәтінмен жазу, «қандай түйме?» т.б.):
  //    растау күтіп тұрса — түймені қайта жібереміз. Мәтінмен жазылған
  //    нөмірді қабылдамаймыз: оны Telegram растамайды (кез келген нөмір
  //    жазуға болады), тек түйме арқылы бөлісілген контакт — расталған.
  const pending = await pendingRow(chatId);
  if (pending) {
    await askContact(chatId, langOf(pending, tgLang));
  }
}

/// Осы чаттағы ең соңғы расталмаған, мерзімі өтпеген растау (болмаса null).
async function pendingRow(
  chatId: number,
): Promise<Record<string, unknown> | null> {
  const { data } = await admin
    .from("telegram_verifications")
    .select("*")
    .eq("telegram_chat_id", chatId)
    .eq("verified", false)
    .gt("expires_at", new Date().toISOString())
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  return data ?? null;
}

/// «Нөмірімді бөлісу» түймесін жібереді.
///
/// Негізгісі — ХАТТЫҢ АСТЫНДАҒЫ inline түйме: ол Mini App-ты ашып, бірден
/// Telegram-ның «Нөмірді бөлісу» терезесін шығарады, жүйелік пернетақта
/// ашық тұрса да көрінеді. Қосалқысы — бұрынғы пернетақта түймесі (Mini App
/// жоқ ескі Telegram үшін): [first] болса, алдымен соны орнатамыз, inline
/// хат соңынан келеді — экранда ең төменгісі сол болсын.
async function askContact(chatId: number, lang: Lang, first = false) {
  const tx = T[lang];
  const replyKeyboard = {
    keyboard: [[{ text: tx.share, request_contact: true }]],
    resize_keyboard: true,
    is_persistent: true,
  };
  // Mini App беті әлі жарияланбаса (веб ескі нұсқада) — inline түйме
  // қосымшаның өзін ашып қояр еді. Ондай кезде бұрынғыдай тек пернетақта
  // түймесін береміз; бет шыққан сәтте inline түйме өзі қосылады.
  const appUrl = await contactAppUrl();
  if (!appUrl) {
    await send(chatId, tx.pressBelow, replyKeyboard);
    return;
  }
  if (first) {
    await send(chatId, tx.welcome, replyKeyboard);
  }
  // Mini App беті де сол тілде ашылсын.
  const sep = appUrl.includes("?") ? "&" : "?";
  await send(chatId, tx.pressBelow, {
    inline_keyboard: [[
      { text: tx.share, web_app: { url: `${appUrl}${sep}lang=${lang}` } },
    ]],
  });
}

/// Mini App беті шынымен жарияланған ба (SPA fallback-тағы Flutter беті
/// емес, ішінде `requestContact` бар біздің бет) — жарияланғанының
/// мекенжайы, әйтпесе null. Нәтиже 10 минут кэштеледі.
let appLive: { url: string | null; at: number } | null = null;
async function contactAppUrl(): Promise<string | null> {
  if (appLive && Date.now() - appLive.at < 10 * 60 * 1000) return appLive.url;
  let url: string | null = null;
  for (const u of CONTACT_APP_URLS) {
    try {
      const r = await fetch(u, { signal: AbortSignal.timeout(3000) });
      if (r.ok && (await r.text()).includes("requestContact")) {
        url = u;
        break;
      }
    } catch (_) {
      // келесі мекенжайды көреміз
    }
  }
  appLive = { url, at: Date.now() };
  return url;
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
    from?: { id: number; language_code?: string };
    contact?: {
      phone_number: string;
      user_id?: number;
    };
  };
}
