import { getD1 } from "../../../db";
import { ensureMemberBalanceSchema, recordBalanceEvent } from "../../../db/member-balances";
import { requireTreasuryLeader, TreasuryAccessError } from "../../treasury-access";

type JsonObject = Record<string, unknown>;
type BrowserEventInput = {
  eventKey?: unknown;
  eventType?: unknown;
  category?: unknown;
  occurredAt?: unknown;
  summary?: unknown;
  sourceUrl?: unknown;
  payload?: unknown;
};
type BrowserEventRow = {
  event_key: string;
  event_type: string;
  category: string;
  occurred_at: string | null;
  summary: string;
  source_url: string;
  payload_json: string;
  created_at: string;
};

const BLOOD_COVEN_ID = 52984;
const allowedTypes = new Set(["faction_news", "armory", "xanax_use", "faction_payout", "faction_deposit", "oc_credit", "ranked_war_report", "active_war"]);

async function ensureSchema(db: D1Database) {
  await db.batch([
    db.prepare(`CREATE TABLE IF NOT EXISTS torn_browser_events (
      event_key TEXT PRIMARY KEY,
      event_type TEXT NOT NULL,
      category TEXT NOT NULL,
      occurred_at TEXT,
      summary TEXT NOT NULL,
      source_url TEXT NOT NULL DEFAULT '',
      payload_json TEXT NOT NULL DEFAULT '{}',
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_torn_browser_events_created ON torn_browser_events(created_at DESC)"),
    db.prepare(`CREATE TABLE IF NOT EXISTS pending_wars (
      war_id INTEGER PRIMARY KEY,
      faction_id INTEGER NOT NULL,
      opponent_name TEXT NOT NULL,
      started_at INTEGER NOT NULL,
      ended_at INTEGER NOT NULL,
      won INTEGER NOT NULL DEFAULT 0,
      gross_estimate INTEGER NOT NULL DEFAULT 0,
      reviewed_value INTEGER,
      status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'recorded', 'dismissed')),
      rewards_json TEXT NOT NULL DEFAULT '[]',
      members_json TEXT NOT NULL DEFAULT '[]',
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`),
  ]);
}

function asObject(value: unknown): JsonObject {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonObject : {};
}

function asInteger(value: unknown) {
  const number = Number(value);
  return Number.isSafeInteger(number) ? number : 0;
}

function cleanEvent(input: BrowserEventInput) {
  const eventKey = String(input.eventKey ?? "").trim();
  const eventType = String(input.eventType ?? "").trim();
  const category = String(input.category ?? "").trim().slice(0, 40);
  const occurredAt = String(input.occurredAt ?? "").trim().slice(0, 40) || null;
  const summary = String(input.summary ?? "").replace(/\s+/g, " ").trim().slice(0, 500);
  const sourceUrl = String(input.sourceUrl ?? "").trim().slice(0, 500);
  const payload = asObject(input.payload);

  if (!/^[a-z0-9:_-]{8,120}$/i.test(eventKey)) throw new Error("A browser event has an invalid key.");
  if (!allowedTypes.has(eventType)) throw new Error("A browser event has an invalid type.");
  if (!category || !summary) throw new Error("A browser event is incomplete.");
  let parsedUrl: URL;
  try { parsedUrl = new URL(sourceUrl); }
  catch { throw new Error("A browser event has an invalid Torn URL."); }
  if (parsedUrl.protocol !== "https:" || parsedUrl.hostname !== "www.torn.com") {
    throw new Error("Browser imports are accepted only from Torn.");
  }
  const payloadJson = JSON.stringify(payload);
  if (payloadJson.length > 12_000) throw new Error("A browser event is too large.");
  return { eventKey, eventType, category, occurredAt, summary, sourceUrl, payload, payloadJson };
}

async function snapshot(db: D1Database) {
  const [count, latest, rows] = await Promise.all([
    db.prepare("SELECT COUNT(*) AS count FROM torn_browser_events").first<{ count: number }>(),
    db.prepare("SELECT created_at FROM torn_browser_events ORDER BY created_at DESC LIMIT 1").first<{ created_at: string }>(),
    db.prepare("SELECT * FROM torn_browser_events ORDER BY created_at DESC LIMIT 120").all<BrowserEventRow>(),
  ]);
  return {
    totalEvents: count?.count ?? 0,
    lastImportedAt: latest?.created_at ?? null,
    recentEvents: rows.results.map((row) => ({
      eventKey: row.event_key,
      eventType: row.event_type,
      category: row.category,
      occurredAt: row.occurred_at,
      summary: row.summary,
      sourceUrl: row.source_url,
      payload: JSON.parse(row.payload_json || "{}") as JsonObject,
      createdAt: row.created_at,
    })),
  };
}

async function importWarReport(db: D1Database, event: ReturnType<typeof cleanEvent>) {
  if (event.eventType !== "ranked_war_report") return;
  const warId = asInteger(event.payload.warId);
  const grossEstimate = asInteger(event.payload.totalValue);
  if (warId <= 0 || grossEstimate <= 0) return;
  const opponentName = String(event.payload.opponentName ?? "Unknown faction").trim().slice(0, 80) || "Unknown faction";
  const endedAt = asInteger(event.payload.endedAt) || Math.floor(Date.now() / 1000);
  const won = event.payload.won === false ? 0 : 1;
  await db.prepare(`INSERT INTO pending_wars
    (war_id, faction_id, opponent_name, started_at, ended_at, won, gross_estimate, rewards_json, members_json)
    VALUES (?, ?, ?, ?, ?, ?, ?, '[]', '[]')
    ON CONFLICT(war_id) DO UPDATE SET
      gross_estimate = CASE WHEN pending_wars.status = 'pending' THEN excluded.gross_estimate ELSE pending_wars.gross_estimate END,
      opponent_name = CASE WHEN pending_wars.status = 'pending' THEN excluded.opponent_name ELSE pending_wars.opponent_name END,
      updated_at = CURRENT_TIMESTAMP`)
    .bind(warId, BLOOD_COVEN_ID, opponentName, endedAt, endedAt, won, grossEstimate).run();
}

async function importMemberBalance(db: D1Database, event: ReturnType<typeof cleanEvent>) {
  if (event.eventType !== "oc_credit" && event.eventType !== "faction_payout") return;
  await ensureMemberBalanceSchema(db);
  const memberName = String(event.payload.memberName ?? event.payload.recipientName ?? "").trim().slice(0, 80);
  const amount = asInteger(event.payload.amount);
  if (!memberName || amount <= 0) return;
  if (event.eventType === "oc_credit") {
    const newBalance = asInteger(event.payload.newBalance);
    await recordBalanceEvent(db, {
      eventKey: event.eventKey,
      memberName,
      amount,
      kind: "credit",
      source: "oc",
      summary: event.summary,
      occurredAt: event.occurredAt,
      explicitBalance: newBalance > 0 ? newBalance : undefined,
    });
  } else {
    await recordBalanceEvent(db, {
      eventKey: event.eventKey,
      memberName,
      amount,
      kind: "payout",
      source: "funds",
      summary: event.summary,
      occurredAt: event.occurredAt,
    });
    await db.prepare(`UPDATE payout_requests SET status = 'paid', updated_at = CURRENT_TIMESTAMP
      WHERE id = (SELECT id FROM payout_requests WHERE member_name = ? COLLATE NOCASE
        AND status IN ('pending', 'approved') AND amount <= ? ORDER BY created_at ASC LIMIT 1)`)
      .bind(memberName, amount).run();
  }
}

export async function GET() {
  try {
    const db = getD1();
    await ensureSchema(db);
    await requireTreasuryLeader(db);
    return Response.json(await snapshot(db));
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Unable to load browser imports." }, { status: error instanceof TreasuryAccessError ? 403 : 500 });
  }
}

export async function POST(request: Request) {
  try {
    const body = await request.json() as { events?: BrowserEventInput[] };
    if (!Array.isArray(body.events) || body.events.length === 0) throw new Error("No browser events were supplied.");
    if (body.events.length > 100) throw new Error("Too many browser events were supplied at once.");
    const events = body.events.map(cleanEvent);
    const db = getD1();
    await ensureSchema(db);
    await requireTreasuryLeader(db);
    await db.batch(events.map((event) => db.prepare(`INSERT OR IGNORE INTO torn_browser_events
      (event_key, event_type, category, occurred_at, summary, source_url, payload_json)
      VALUES (?, ?, ?, ?, ?, ?, ?)`)
      .bind(event.eventKey, event.eventType, event.category, event.occurredAt, event.summary, event.sourceUrl, event.payloadJson)));
    for (const event of events) {
      await importWarReport(db, event);
      await importMemberBalance(db, event);
    }
    return Response.json({ acceptedKeys: events.map((event) => event.eventKey), ...(await snapshot(db)) });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to import browser events.";
    return Response.json({ error: message }, { status: error instanceof TreasuryAccessError ? 403 : /invalid|incomplete|only|large|no browser|too many/i.test(message) ? 400 : 500 });
  }
}
