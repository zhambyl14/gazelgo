// Tasu · kaspi-statement edge function
// ============================================================================
// Kaspi Pay выпискасын жүктеу және РАСТАЛҒАН толтыруларды сәйкестендіру.
//
// НЕГЕ КЕРЕК: бот чектің СУРЕТІН оқиды, ал сурет — шындықтың өзі емес, тек
// оның бейнесі. Боттың құрылымдық түрде көре алмайтын ЖАЛҒЫЗ нәрсесі бар:
// чек скриншот кезінде шын болып, кейін Kaspi-де қайтарылып алынса. Оны тек
// нақты банк выпискасымен салыстыру арқылы білуге болады.
//
// Бұл АВТО-РАСТАУДЫ БӨГЕМЕЙДІ: выписка әдетте растаудан кейін жүктеледі
// (аптасына/күніне бір рет). Оның рөлі — «бот 12 толтыруды растады, оның
// 11-і выпискада бар, 1-еуі ЖОҚ → тексеріңіз» деп айту.
//
// Ағын: модератор қосымшадан файлды `docs` bucket-іне жүктейді (өз папкасына,
// қолданыстағы саясат бойынша) → осы функцияны шақырады → файл талданып
// `kaspi_statement_entries`-ке жазылады → сәйкестендіру есебі қайтарылады.
//
// Verify JWT = ON — тек кірген пайдаланушы шақыра алады, әрі оның модератор
// екені бөлек тексеріледі.
// Қажет Edge Function Secrets: TOPUP_BOT_SECRET (міндетті емес: TOPUP_BOT_TOKEN)
// ============================================================================
import { createClient } from "jsr:@supabase/supabase-js@2";

const BOT_SECRET = Deno.env.get("TOPUP_BOT_SECRET") ?? "";
const TG_TOKEN = Deno.env.get("TOPUP_BOT_TOKEN") ?? "";

const admin = createClient(
  Deno.env.get("SUPABASE_URL")!,
  Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!,
);

Deno.serve(async (req: Request) => {
  if (req.method !== "POST") return json({ error: "METHOD_NOT_ALLOWED" }, 405);

  // ---- Шақырушы кім? ----
  const authHeader = req.headers.get("Authorization") ?? "";
  if (!authHeader.startsWith("Bearer ")) return json({ error: "AUTH" }, 401);

  const { data: userRes } = await admin.auth.getUser(authHeader.slice(7));
  const uid = userRes?.user?.id;
  if (!uid) return json({ error: "AUTH" }, 401);

  const { data: prof } = await admin
    .from("profiles").select("role").eq("id", uid).maybeSingle();
  if (prof?.role !== "moderator") return json({ error: "FORBIDDEN" }, 403);

  // ---- Файл ----
  let path = "";
  try {
    path = String((await req.json())?.path ?? "");
  } catch {
    return json({ error: "BAD_INPUT" }, 400);
  }
  if (!path) return json({ error: "BAD_INPUT" }, 400);

  const dl = await admin.storage.from("docs").download(path);
  if (dl.error || !dl.data) return json({ error: "FILE_NOT_FOUND" }, 404);
  const bytes = new Uint8Array(await dl.data.arrayBuffer());

  // ---- Талдау ----
  let rows: StatementRow[];
  try {
    rows = path.toLowerCase().endsWith(".csv")
      ? parseCsv(new TextDecoder().decode(bytes))
      : await parseXlsx(bytes);
  } catch (e) {
    console.error("PARSE_ERROR", e);
    return json({ error: "PARSE_FAILED", detail: String(e).slice(0, 300) }, 200);
  }

  if (rows.length === 0) {
    return json({
      ok: false,
      error: "NO_ROWS",
      hint: "Файлдан бірде-бір төлем жолы табылмады. Бағандар аты күтілгеннен " +
        "өзгеше болуы мүмкін — файлдың бір бетін жіберіңіз, ережені бейімдейміз.",
    }, 200);
  }

  // ---- Базаға жазу ----
  const { data: impRaw, error: impErr } = await admin.rpc("bot_import_statement", {
    p_secret: BOT_SECRET,
    p_rows: rows,
    p_source: path.split("/").pop() ?? "",
    p_actor: uid,
  });
  if (impErr) {
    console.error("IMPORT_ERROR", impErr);
    return json({ error: "IMPORT_FAILED" }, 200);
  }
  const imp = impRaw as { inserted: number; skipped: number };

  // ---- Сәйкестендіру ----
  // service_role-де `auth.uid()` жоқ, сондықтан рұқсат құпиямен беріледі.
  const { data: recon } = await admin.rpc("topup_reconciliation", {
    p_days: 30,
    p_secret: BOT_SECRET,
  });
  const all = (recon as ReconRow[] | null) ?? [];
  const missing = all.filter((r) => !r.matched);

  await alertTelegram(all.length, missing);

  return json({
    ok: true,
    parsed: rows.length,
    inserted: imp?.inserted ?? 0,
    skipped: imp?.skipped ?? 0,
    checked: all.length,
    missing: missing.length,
    missing_rows: missing.slice(0, 20),
  }, 200);
});

// ============================================================================
// XLSX / CSV талдау
// ============================================================================
// Kaspi выпискасының нақты баған аттары нұсқадан нұсқаға өзгеруі мүмкін,
// сондықтан бағандар аты бойынша ЕРКІН ізделеді: тапса — алады, таппаса —
// сол жолды өткізіп жібереді (жалған мән ойлап таппайды).
const COL = {
  date: /(дата|күн|уақыт|время|date|time)/i,
  amount: /(сумма|сома|amount|тұтыну|начисл|зачисл|поступ)/i,
  ref: /(квитанц|номер|нөмір|操作|транзакц|операц|reference|ref|id)/i,
  sender: /(отправит|жіберуші|плательщ|клиент|sender|payer|аты)/i,
};

async function parseXlsx(bytes: Uint8Array): Promise<StatementRow[]> {
  const XLSX = await import("npm:xlsx@0.18.5");
  const wb = XLSX.read(bytes, { type: "array", cellDates: true });
  const out: StatementRow[] = [];
  for (const name of wb.SheetNames) {
    const grid = XLSX.utils.sheet_to_json(wb.Sheets[name], {
      header: 1,
      raw: true,
      defval: null,
    }) as unknown[][];
    out.push(...gridToRows(grid));
  }
  return out;
}

function parseCsv(text: string): StatementRow[] {
  const sep = (text.match(/;/g)?.length ?? 0) > (text.match(/,/g)?.length ?? 0) ? ";" : ",";
  const grid = text.split(/\r?\n/).filter((l) => l.trim()).map((line) => splitCsv(line, sep));
  return gridToRows(grid);
}

function splitCsv(line: string, sep: string): string[] {
  const out: string[] = [];
  let cur = "", q = false;
  for (let i = 0; i < line.length; i++) {
    const c = line[i];
    if (q) {
      if (c === '"' && line[i + 1] === '"') { cur += '"'; i++; }
      else if (c === '"') q = false;
      else cur += c;
    } else if (c === '"') q = true;
    else if (c === sep) { out.push(cur); cur = ""; }
    else cur += c;
  }
  out.push(cur);
  return out;
}

// Тақырып жолын табу (алғашқы 20 жолдың ішінен), сосын қалғанын оқу.
function gridToRows(grid: unknown[][]): StatementRow[] {
  let hdr = -1;
  let map: { date: number; amount: number; ref: number; sender: number } | null = null;

  for (let i = 0; i < Math.min(grid.length, 20); i++) {
    const cells = (grid[i] ?? []).map((c) => String(c ?? ""));
    const m = {
      date: cells.findIndex((c) => COL.date.test(c)),
      amount: cells.findIndex((c) => COL.amount.test(c)),
      ref: cells.findIndex((c) => COL.ref.test(c)),
      sender: cells.findIndex((c) => COL.sender.test(c)),
    };
    if (m.date >= 0 && m.amount >= 0) { hdr = i; map = m; break; }
  }
  if (hdr < 0 || !map) return [];

  const out: StatementRow[] = [];
  for (let i = hdr + 1; i < grid.length; i++) {
    const row = grid[i] ?? [];
    const when = toDate(row[map.date]);
    const amt = toAmount(row[map.amount]);
    if (!when || amt == null || amt <= 0) continue;
    out.push({
      occurred_at: when.toISOString(),
      amount: Math.round(amt),
      txn_ref: map.ref >= 0 ? cleanRef(row[map.ref]) : null,
      sender_name: map.sender >= 0 ? cleanStr(row[map.sender]) : null,
    });
  }
  return out;
}

function toDate(v: unknown): Date | null {
  if (v instanceof Date) return Number.isFinite(v.getTime()) ? v : null;
  const s = String(v ?? "").trim();
  if (!s) return null;

  // «31.07.2026 14:22» / «31.07.26 14:22»
  const m = s.match(/(\d{2})[.\-/](\d{2})[.\-/](\d{2,4})(?:\D{0,4}(\d{1,2}):(\d{2}))?/);
  if (m) {
    const yy = m[3].length === 2 ? `20${m[3]}` : m[3];
    // Выпискадағы уақыт — жергілікті (Asia/Almaty, UTC+5).
    const iso = `${yy}-${m[2]}-${m[1]}T${(m[4] ?? "00").padStart(2, "0")}:${m[5] ?? "00"}:00+05:00`;
    const d = new Date(iso);
    return Number.isFinite(d.getTime()) ? d : null;
  }
  const d = new Date(s);
  return Number.isFinite(d.getTime()) ? d : null;
}

function toAmount(v: unknown): number | null {
  if (typeof v === "number") return Number.isFinite(v) ? Math.abs(v) : null;
  const s = String(v ?? "").replace(/[\s ₸]/g, "").replace(",", ".");
  const n = Number(s.replace(/[^\d.\-]/g, ""));
  return Number.isFinite(n) && n !== 0 ? Math.abs(n) : null;
}

function cleanRef(v: unknown): string | null {
  const s = String(v ?? "").trim();
  return s && s.length <= 64 ? s : null;
}

function cleanStr(v: unknown): string | null {
  const s = String(v ?? "").trim();
  return s ? s.slice(0, 120) : null;
}

// ============================================================================
// Telegram ескертуі
// ============================================================================
async function alertTelegram(checked: number, missing: ReconRow[]) {
  if (!TG_TOKEN || missing.length === 0) return;

  const { data: chats } = await admin.rpc("bot_chats", { p_secret: BOT_SECRET });
  const ids = (chats as number[] | null) ?? [];
  if (ids.length === 0) return;

  const lines = [
    `⚠️ Выписка сәйкестендіру: ${checked} расталған толтырудың ` +
      `${missing.length}-і выпискада ТАБЫЛМАДЫ.`,
    "",
  ];
  for (const r of missing.slice(0, 10)) {
    const when = r.reviewed_at ? String(r.reviewed_at).slice(0, 16).replace("T", " ") : "—";
    lines.push(
      `• ${fmtT(r.amount)} · ${r.executor || "аты жоқ"} · ${when}` +
        (r.bot_verdict ? ` · ${r.bot_verdict}` : ""),
    );
  }
  if (missing.length > 10) lines.push(`… және тағы ${missing.length - 10}.`);
  lines.push("");
  lines.push(
    "Бұл әрқашан алаяқтық дегенді білдірмейді: выписка кезеңі толық " +
      "болмауы да мүмкін. Бірақ әрқайсысын қолмен тексерген жөн.",
  );

  for (const chatId of ids) {
    try {
      await fetch(`https://api.telegram.org/bot${TG_TOKEN}/sendMessage`, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ chat_id: chatId, text: lines.join("\n") }),
      });
    } catch (e) {
      console.error("TG_SEND_ERROR", e);
    }
  }
}

// ============================================================================
// Көмекші
// ============================================================================
function json(body: unknown, status: number) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

function fmtT(n: number): string {
  return `${Math.round(n).toString().replace(/\B(?=(\d{3})+(?!\d))/g, " ")} ₸`;
}

interface StatementRow {
  occurred_at: string;
  amount: number;
  txn_ref: string | null;
  sender_name: string | null;
}

interface ReconRow {
  topup_id: string;
  executor: string;
  amount: number;
  reviewed_at: string | null;
  bot_verdict: string | null;
  matched: boolean;
}
