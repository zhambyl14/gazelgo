// Tasu · topup-bot edge function
// ============================================================================
// @imagcheckerbot — толтыру чектерін тексеретін боттың Telegram вебхукы.
//
// Бұл ФУНКЦИЯ ТЕКСЕРМЕЙДІ — тексеруді `topup-verify` жасайды. Мұның екі ғана
// міндеті бар:
//   1) `/start <код>` — чатты тіркеу. Бот тек тіркелген чатқа жазады.
//   2) ✅/❌ түймесі (callback_query) — модератордың қолмен шешімі.
//
// НЕГЕ БӨЛЕК ФУНКЦИЯ (бар `telegram-webhook`-пен бірікпейді):
//   · Telegram бір ботқа бір ғана вебхук рұқсат етеді, ал @imagcheckerbot —
//     @tasuappbot-тан бөлек токен;
//   · `telegram-webhook` тек `message.text`/`message.contact` өңдейді,
//     `callback_query` мүлде жоқ;
//   · ең бастысы — телефон растау мен АҚША растауды бір құпияның артына
//     қоюға болмайды.
//
// Verify JWT = OFF (Telegram JWT жібермейді) — орнына setWebhook кезінде
// орнатылған `secret_token` тексеріледі.
// Қажет Edge Function Secrets:
//   TOPUP_BOT_TOKEN, TOPUP_BOT_WEBHOOK_SECRET, TOPUP_BOT_SECRET
// ============================================================================
import { createClient } from "jsr:@supabase/supabase-js@2";

const BOT_TOKEN = Deno.env.get("TOPUP_BOT_TOKEN") ?? "";
const WEBHOOK_SECRET = Deno.env.get("TOPUP_BOT_WEBHOOK_SECRET") ?? "";
const BOT_SECRET = Deno.env.get("TOPUP_BOT_SECRET") ?? "";
const API = `https://api.telegram.org/bot${BOT_TOKEN}`;

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return new Response("ok", { status: 200 });

  // Екі МҮЛДЕМ бөлек шақырушы бар:
  //   1) Telegram-ның өзі (webhook) — `X-Telegram-Bot-Api-Secret-Token`.
  //   2) Postgres триггері (0052, `notify_telegram_manual_review`) — модератор
  //      Tasu·Модератор ҚОСЫМШАСЫНАН қолмен растаса/қабылдамаса, Telegram
  //      чатына аудит хабары жіберу үшін `x-topup-secret` header-імен
  //      келеді (`topup-verify`-мен бірдей құпия).
  const internalSecret = req.headers.get("x-topup-secret");
  if (BOT_SECRET && internalSecret === BOT_SECRET) {
    try {
      const body = await req.json();
      if (body?.action === "manual_review" && body?.topup_id) {
        await notifyManualReview(String(body.topup_id));
      }
    } catch (e) {
      console.error("TOPUP_BOT_INTERNAL_ERROR", e);
    }
    return new Response("ok", { status: 200 });
  }

  // Тек нағыз Telegram жібере алады (setWebhook кезінде орнатылған құпия).
  const secret = req.headers.get("X-Telegram-Bot-Api-Secret-Token");
  if (!WEBHOOK_SECRET || secret !== WEBHOOK_SECRET) {
    return new Response("forbidden", { status: 403 });
  }

  let update: TgUpdate;
  try {
    update = await req.json();
  } catch {
    return new Response("ok", { status: 200 });
  }

  try {
    await handle(update);
  } catch (e) {
    console.error("TOPUP_BOT_ERROR", e);
  }
  // Әрқашан 200 — әйтпесе Telegram сол update-ті қайта-қайта жібере береді.
  return new Response("ok", { status: 200 });
});

// ============================================================================
// Модератор ҚОСЫМШАДАН қолмен шешім қабылдағанда — Telegram аудиті
// ============================================================================
// Бот пен Telegram түймесі арқылы қабылданған шешімдердің ізі Telegram
// чатының өзінде қалады (хабарлама/callback ретінде). Бірақ модератор
// қосымшадан («Толтырулар» бетінен) қабылдаса/қабылдамаса, бұған дейін бұл
// ЕШҚАНДАЙ Telegram жазбасын қалдырмайтын. Енді осы функция сол олқылықты
// толтырады.
async function notifyManualReview(topupId: string) {
  const { data: t } = await admin
    .from("topup_requests")
    .select("id, amount, status, note, reviewed_by, executor_id")
    .eq("id", topupId)
    .maybeSingle();
  if (!t) return;

  const { data: chats } = await admin.rpc("bot_chats", { p_secret: BOT_SECRET });
  const ids = (chats as number[] | null) ?? [];
  if (ids.length === 0) return;

  const { data: executor } = await admin
    .from("profiles").select("full_name, phone").eq("id", t.executor_id)
    .maybeSingle();

  let reviewerName: string | null = null;
  if (t.reviewed_by) {
    const { data: reviewer } = await admin
      .from("profiles").select("full_name").eq("id", t.reviewed_by)
      .maybeSingle();
    reviewerName = reviewer?.full_name ?? null;
  }

  const approved = t.status === "approved";
  const head = approved
    ? `🧑‍💼 Модератор қосымшадан РАСТАДЫ · ${fmtT(t.amount)}`
    : `🧑‍💼 Модератор қосымшадан ҚАБЫЛДАМАДЫ · ${fmtT(t.amount)}`;

  const lines = [head];
  lines.push(
    `👤 ${executor?.full_name || "аты жоқ"} · ${executor?.phone || "—"}`,
  );
  lines.push(`✍️ ${reviewerName || "белгісіз модератор"}`);
  if (!approved && t.note) {
    lines.push("");
    lines.push(`❗ Себебі: ${t.note}`);
  }

  const text = lines.join("\n");
  for (const chatId of ids) {
    try {
      // parse_mode ЖОҚ — модератордың өз жазған мәтіні (t.note) кез
      // келген нәрсе болуы мүмкін, Markdown/HTML ретінде оқылмауы керек.
      await fetch(`${API}/sendMessage`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ chat_id: chatId, text }),
      });
    } catch (e) {
      console.error("TG_SEND_ERROR", chatId, e);
    }
  }
}

function fmtT(n: number): string {
  return `${Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ")} ₸`;
}

async function handle(update: TgUpdate) {
  if (update.callback_query) return await onCallback(update.callback_query);
  if (update.message) return await onMessage(update.message);
}

// ============================================================================
// 1) /start <код> — чатты тіркеу
// ============================================================================
async function onMessage(msg: NonNullable<TgUpdate["message"]>) {
  const chatId = msg.chat?.id;
  if (!chatId) return;

  const text = (msg.text ?? "").trim();
  if (!text.startsWith("/start")) {
    if (await isRegistered(chatId)) {
      await send(chatId, "Бот жұмыс істеп тұр. Жаңа толтыру өтінімдері осында келеді.");
    }
    return;
  }

  const code = text.split(/\s+/)[1] ?? "";
  if (!code) {
    await send(
      chatId,
      "Сәлеметсіз бе! Тіркелу үшін кодпен жіберіңіз:\n/start <код>\n\n" +
        "Кодты Supabase → app_secrets → topup_bot_join_code ішінен аласыз.",
    );
    return;
  }

  const title = msg.chat?.title ?? msg.chat?.username ??
    [msg.from?.first_name, msg.from?.last_name].filter(Boolean).join(" ");

  const { data, error } = await admin.rpc("bot_register_chat", {
    p_secret: BOT_SECRET,
    p_chat: chatId,
    p_code: code,
    p_title: title ?? "",
  });

  if (error) {
    console.error("REGISTER_ERROR", error);
    await send(chatId, "Ішкі қате. Кейінірек қайталаңыз.");
    return;
  }

  await send(
    chatId,
    data === true
      ? "✅ Тіркелдіңіз. Енді Kaspi чектері мен бот шешімдері осында келеді."
      : "❌ Код қате.",
  );
}

// ============================================================================
// 2) ✅/❌ түймесі — модератордың қолмен шешімі
// ============================================================================
async function onCallback(cq: NonNullable<TgUpdate["callback_query"]>) {
  const chatId = cq.message?.chat?.id;
  const data = cq.data ?? "";

  // `tv:a:<uuid>` / `tv:r:<uuid>` — 41 байт, Telegram-ның 64 байт шегіне сыяды.
  const m = data.match(
    /^tv:(a|r):([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12})$/i,
  );
  if (!m || !chatId) {
    await answer(cq.id, "Белгісіз команда.");
    return;
  }

  // Тек ТІРКЕЛГЕН чаттан келген шешім қабылданады — әйтпесе callback_data-ны
  // көрген кез келген адам ақшаны растай алар еді.
  if (!(await isRegistered(chatId))) {
    await answer(cq.id, "Бұл чат тіркелмеген.");
    return;
  }

  const approve = m[1].toLowerCase() === "a";
  const topupId = m[2];
  const who = [cq.from?.first_name, cq.from?.last_name].filter(Boolean).join(" ") ||
    cq.from?.username || String(cq.from?.id ?? "telegram");

  const { error } = await admin.rpc("bot_review_topup", {
    p_secret: BOT_SECRET,
    p_topup: topupId,
    p_approve: approve,
    p_note: approve
      ? `Telegram арқылы расталды (${who})`
      : `Telegram арқылы қабылданбады (${who})`,
    p_actor: who,
  });

  if (error) {
    // `ALREADY_REVIEWED` — екі рет басылса шығады, бұл ҚАТЕ ЕМЕС: базадағы
    // қорғаныс дұрыс жұмыс істегенін білдіреді.
    const msg = String(error.message ?? "");
    await answer(
      cq.id,
      msg.includes("ALREADY_REVIEWED")
        ? "Бұл өтінім әлдеқашан қаралған."
        : msg.includes("NOT_FOUND")
        ? "Өтінім табылмады."
        : "Қате: орындалмады.",
    );
    await stripButtons(chatId, cq.message?.message_id);
    return;
  }

  await answer(cq.id, approve ? "✅ Расталды, баланс толтырылды." : "❌ Қабылданбады.");
  await stripButtons(chatId, cq.message?.message_id);
  await send(
    chatId,
    `${approve ? "✅" : "❌"} ${who} шешім қабылдады: ` +
      `${approve ? "расталды" : "қабылданбады"}.`,
  );
}

// ============================================================================
// Көмекші функциялар
// ============================================================================
async function isRegistered(chatId: number): Promise<boolean> {
  const { data, error } = await admin.rpc("bot_chats", { p_secret: BOT_SECRET });
  if (error) {
    console.error("BOT_CHATS_ERROR", error);
    return false;
  }
  return ((data as number[] | null) ?? []).some((id) => Number(id) === Number(chatId));
}

async function send(chatId: number, text: string) {
  // parse_mode ӘДЕЙІ жоқ — мәтінде пайдаланушы аты болуы мүмкін.
  await tg("sendMessage", { chat_id: chatId, text });
}

async function answer(callbackId: string, text: string) {
  await tg("answerCallbackQuery", {
    callback_query_id: callbackId,
    text,
    show_alert: false,
  });
}

// Түймелерді алып тастау — қос басуды болдырмайды. Нағыз қорғаныс бәрібір
// базада (`apply_topup_review` → `ALREADY_REVIEWED`), бұл тек ыңғайлылық үшін.
async function stripButtons(chatId: number, messageId?: number) {
  if (!messageId) return;
  await tg("editMessageReplyMarkup", {
    chat_id: chatId,
    message_id: messageId,
    reply_markup: { inline_keyboard: [] },
  });
}

async function tg(method: string, body: Record<string, unknown>) {
  try {
    const r = await fetch(`${API}/${method}`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(body),
    });
    if (!r.ok) {
      console.error("TG_HTTP", method, r.status, (await r.text()).slice(0, 200));
    }
  } catch (e) {
    console.error("TG_SEND_ERROR", method, e);
  }
}

// ============================================================================
// Типтер
// ============================================================================
interface TgChat {
  id: number;
  title?: string;
  username?: string;
}

interface TgUser {
  id: number;
  first_name?: string;
  last_name?: string;
  username?: string;
}

interface TgUpdate {
  message?: {
    message_id?: number;
    text?: string;
    chat?: TgChat;
    from?: TgUser;
  };
  callback_query?: {
    id: string;
    data?: string;
    from?: TgUser;
    message?: {
      message_id?: number;
      chat?: TgChat;
    };
  };
}
