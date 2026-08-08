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
const allowedTypes = new Set(["faction_news", "armory", "armory_movement", "xanax_use", "faction_payout", "faction_deposit", "oc_credit", "oc_completion", "member_balance_snapshot", "ranked_war_report", "active_war"]);

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
      reviewed_tax_bps INTEGER NOT NULL DEFAULT 2000 CHECK (reviewed_tax_bps BETWEEN 0 AND 10000),
      status TEXT NOT NULL DEFAULT 'pending' CHECK (status IN ('pending', 'recorded', 'dismissed')),
      rewards_json TEXT NOT NULL DEFAULT '[]',
      members_json TEXT NOT NULL DEFAULT '[]',
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`),
    db.prepare(`CREATE TABLE IF NOT EXISTS oc_holdings (
      event_key TEXT PRIMARY KEY,
      crime_name TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'held' CHECK (status IN ('held', 'distributed', 'dismissed')),
      cash_amount INTEGER NOT NULL DEFAULT 0 CHECK (cash_amount >= 0),
      items_json TEXT NOT NULL DEFAULT '[]',
      summary TEXT NOT NULL DEFAULT '',
      occurred_at TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_oc_holdings_status_created ON oc_holdings(status, created_at DESC)"),
    db.prepare(`CREATE TABLE IF NOT EXISTS armory_items (
      item_name TEXT PRIMARY KEY COLLATE NOCASE,
      category TEXT NOT NULL DEFAULT 'other',
      quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
      source TEXT NOT NULL DEFAULT 'activity',
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    )`),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_armory_items_category_name ON armory_items(category, item_name)"),
  ]);
}

function asObject(value: unknown): JsonObject {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonObject : {};
}

function asInteger(value: unknown) {
  const number = Number(value);
  return Number.isSafeInteger(number) ? number : 0;
}

function normalizedOccurredAt(summary: string, occurredAt: string | null, payload: JsonObject) {
  const endedAt = asInteger(payload.endedAt);
  if (endedAt > 0) return new Date(endedAt * 1000).toISOString();
  const matches = Array.from(summary.matchAll(/(\d{2}):(\d{2}):(\d{2})\s*(\d{2})\/(\d{2})\/(\d{2})/g));
  const match = matches.at(-1);
  if (match) return new Date(Date.UTC(2000 + Number(match[6]), Number(match[5]) - 1, Number(match[4]), Number(match[1]), Number(match[2]), Number(match[3]))).toISOString();
  if (occurredAt) {
    const legacy = occurredAt.match(/^(\d{2})\/(\d{2})\/(\d{2})\s+(\d{2}):(\d{2}):(\d{2})$/);
    if (legacy) return new Date(Date.UTC(2000 + Number(legacy[3]), Number(legacy[2]) - 1, Number(legacy[1]), Number(legacy[4]), Number(legacy[5]), Number(legacy[6]))).toISOString();
    const parsed = Date.parse(occurredAt);
    if (Number.isFinite(parsed)) return new Date(parsed).toISOString();
  }
  return null;
}

function cleanEvent(input: BrowserEventInput) {
  const eventKey = String(input.eventKey ?? "").trim();
  const eventType = String(input.eventType ?? "").trim();
  const category = String(input.category ?? "").trim().slice(0, 40);
  const rawOccurredAt = String(input.occurredAt ?? "").trim().slice(0, 40) || null;
  const summary = String(input.summary ?? "").replace(/\s+/g, " ").trim().slice(0, 500);
  const sourceUrl = String(input.sourceUrl ?? "").trim().slice(0, 500);
  const payload = asObject(input.payload);
  const occurredAt = normalizedOccurredAt(summary, rawOccurredAt, payload);

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
  const [count, latest, rows, ocRows, armoryRows] = await Promise.all([
    db.prepare("SELECT COUNT(*) AS count FROM torn_browser_events").first<{ count: number }>(),
    db.prepare("SELECT created_at FROM torn_browser_events ORDER BY created_at DESC LIMIT 1").first<{ created_at: string }>(),
    db.prepare("SELECT * FROM torn_browser_events ORDER BY created_at DESC LIMIT 500").all<BrowserEventRow>(),
    db.prepare("SELECT event_key AS eventKey, crime_name AS crimeName, status, cash_amount AS cashAmount, items_json AS itemsJson, summary, occurred_at AS occurredAt, created_at AS createdAt, updated_at AS updatedAt FROM oc_holdings ORDER BY created_at DESC LIMIT 100").all<{ eventKey: string; crimeName: string; status: string; cashAmount: number; itemsJson: string; summary: string; occurredAt: string | null; createdAt: string; updatedAt: string }>(),
    db.prepare("SELECT item_name AS itemName, category, quantity, source, updated_at AS updatedAt FROM armory_items WHERE quantity > 0 ORDER BY category, item_name").all<{ itemName: string; category: string; quantity: number; source: string; updatedAt: string }>(),
  ]);
  const recentEvents = rows.results.map((row) => {
    const payload = JSON.parse(row.payload_json || "{}") as JsonObject;
    return {
      eventKey: row.event_key,
      eventType: row.event_type,
      category: row.category,
      occurredAt: normalizedOccurredAt(row.summary, row.occurred_at, payload),
      summary: row.summary,
      sourceUrl: row.source_url,
      payload,
      createdAt: row.created_at,
    };
  }).sort((a, b) => Date.parse(b.occurredAt ?? b.createdAt) - Date.parse(a.occurredAt ?? a.createdAt)).slice(0, 120);
  return {
    totalEvents: count?.count ?? 0,
    lastImportedAt: latest?.created_at ?? null,
    recentEvents,
    ocHoldings: ocRows.results.map((row) => ({ ...row, items: JSON.parse(row.itemsJson || "[]") })),
    armoryItems: armoryRows.results,
  };
}

function armoryCategory(itemName: string) {
  if (/xanax|vicodin|ecstasy|lsd|cannabis|opium|ketamine|pcp|shroom|speed/i.test(itemName)) return "drugs";
  if (/blood bag|first aid|medical|morphine|epinephrine|melatonin/i.test(itemName)) return "medical";
  return "other";
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
  if (event.eventType === "member_balance_snapshot") {
    await ensureMemberBalanceSchema(db);
    const members = Array.isArray(event.payload.members) ? event.payload.members.slice(0, 250) : [];
    for (const rawMember of members) {
      const member = asObject(rawMember);
      const memberName = String(member.name ?? "").trim().slice(0, 80);
      const balance = asInteger(member.balance);
      if (!memberName || balance < 0) continue;
      await db.prepare(`INSERT INTO member_balances (member_name, balance) VALUES (?, ?)
        ON CONFLICT(member_name) DO UPDATE SET balance = excluded.balance, updated_at = CURRENT_TIMESTAMP`)
        .bind(memberName, balance).run();
    }
    return;
  }
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

async function importOcHolding(db: D1Database, event: ReturnType<typeof cleanEvent>) {
  if (event.eventType !== "oc_completion" || event.payload.success === false) return;
  const crimeName = String(event.payload.crimeName ?? "Organized crime").trim().slice(0, 100) || "Organized crime";
  const cashAmount = Math.max(0, asInteger(event.payload.cashAmount));
  const status = event.payload.status === "distributed" ? "distributed" : "held";
  const items = (Array.isArray(event.payload.items) ? event.payload.items : []).slice(0, 30).map((rawItem) => {
    const item = asObject(rawItem);
    return { name: String(item.name ?? "").trim().slice(0, 80), quantity: Math.max(0, asInteger(item.quantity)) };
  }).filter((item) => item.name && item.quantity > 0);
  await db.prepare(`INSERT OR IGNORE INTO oc_holdings
    (event_key, crime_name, status, cash_amount, items_json, summary, occurred_at) VALUES (?, ?, ?, ?, ?, ?, ?)`)
    .bind(event.eventKey, crimeName, status, cashAmount, JSON.stringify(items), event.summary, event.occurredAt).run();
  for (const item of items) {
    await db.prepare(`INSERT INTO armory_items (item_name, category, quantity, source) VALUES (?, ?, ?, 'oc')
      ON CONFLICT(item_name) DO UPDATE SET quantity = armory_items.quantity + excluded.quantity,
      category = excluded.category, source = 'oc', updated_at = CURRENT_TIMESTAMP`)
      .bind(item.name, armoryCategory(item.name), item.quantity).run();
  }
}

async function importArmoryMovement(db: D1Database, event: ReturnType<typeof cleanEvent>) {
  if (event.eventType !== "armory_movement" && event.eventType !== "xanax_use") return;
  const itemName = String(event.payload.item ?? (event.eventType === "xanax_use" ? "Xanax" : "")).trim().slice(0, 80);
  const quantity = Math.max(1, asInteger(event.payload.quantity));
  const action = String(event.payload.action ?? "used").toLowerCase();
  if (!itemName) return;
  const delta = ["deposited", "returned"].includes(action) ? quantity : -quantity;
  await db.prepare(`INSERT INTO armory_items (item_name, category, quantity, source) VALUES (?, ?, MAX(0, ?), 'activity')
    ON CONFLICT(item_name) DO UPDATE SET quantity = MAX(0, armory_items.quantity + ?),
    category = excluded.category, updated_at = CURRENT_TIMESTAMP`)
    .bind(itemName, armoryCategory(itemName), delta, delta).run();
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
      await importOcHolding(db, event);
      await importArmoryMovement(db, event);
    }
    return Response.json({ acceptedKeys: events.map((event) => event.eventKey), ...(await snapshot(db)) });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to import browser events.";
    return Response.json({ error: message }, { status: error instanceof TreasuryAccessError ? 403 : /invalid|incomplete|only|large|no browser|too many/i.test(message) ? 400 : 500 });
  }
}
