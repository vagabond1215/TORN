import { getD1 } from "../../../db";
import { ensureMemberBalanceSchema, recordBalanceEvent, recordBalanceObservation, recordExplicitBalance } from "../../../db/member-balances";
import { recordScriptSyncPush, requireScriptSyncActor, ScriptSyncAccessError } from "../../../db/script-sync";
import { rejectFactionOverride, type FactionContext } from "../../../db/tenant";
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
type ArmorySnapshotItem = { name: string; quantity: number; category: string };

const EVENT_JOURNAL_LIMIT = 5000;
const allowedTypes = new Set([
  "faction_news", "armory", "armory_movement", "armory_snapshot", "xanax_use", "faction_payout", "faction_deposit",
  "oc_credit", "oc_completion", "member_balance_change", "member_balance_snapshot", "ranked_war_report", "active_war",
]);

async function ensureSchema(db: D1Database) {
  await db.batch([
    db.prepare(`CREATE TABLE IF NOT EXISTS torn_browser_events (
      faction_id INTEGER NOT NULL,
      event_key TEXT NOT NULL,
      event_type TEXT NOT NULL,
      category TEXT NOT NULL,
      occurred_at TEXT,
      summary TEXT NOT NULL,
      source_url TEXT NOT NULL DEFAULT '',
      payload_json TEXT NOT NULL DEFAULT '{}',
      first_observed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_observed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (faction_id, event_key)
    )`),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_torn_browser_events_faction_created ON torn_browser_events(faction_id, created_at DESC)"),
    db.prepare(`CREATE TABLE IF NOT EXISTS pending_wars (
      faction_id INTEGER NOT NULL,
      war_id INTEGER NOT NULL,
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
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (faction_id, war_id)
    )`),
    db.prepare(`CREATE TABLE IF NOT EXISTS oc_holdings (
      faction_id INTEGER NOT NULL,
      event_key TEXT NOT NULL,
      crime_name TEXT NOT NULL,
      status TEXT NOT NULL DEFAULT 'held' CHECK (status IN ('held', 'distributed', 'dismissed')),
      cash_amount INTEGER NOT NULL DEFAULT 0 CHECK (cash_amount >= 0),
      items_json TEXT NOT NULL DEFAULT '[]',
      summary TEXT NOT NULL DEFAULT '',
      occurred_at TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (faction_id, event_key)
    )`),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_oc_holdings_faction_status_created ON oc_holdings(faction_id, status, created_at DESC)"),
    db.prepare(`CREATE TABLE IF NOT EXISTS armory_items (
      faction_id INTEGER NOT NULL,
      item_name TEXT NOT NULL COLLATE NOCASE,
      category TEXT NOT NULL DEFAULT 'other',
      quantity INTEGER NOT NULL DEFAULT 0 CHECK (quantity >= 0),
      source TEXT NOT NULL DEFAULT 'activity',
      observed_at TEXT,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (faction_id, item_name)
    )`),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_armory_items_faction_category_name ON armory_items(faction_id, category, item_name)"),
    db.prepare(`CREATE TABLE IF NOT EXISTS armory_snapshot_state (
      faction_id INTEGER NOT NULL,
      category TEXT NOT NULL,
      event_key TEXT NOT NULL,
      observed_at TEXT NOT NULL,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (faction_id, category)
    )`),
    db.prepare(`CREATE TABLE IF NOT EXISTS armory_item_effects (
      faction_id INTEGER NOT NULL,
      event_key TEXT NOT NULL,
      item_name TEXT NOT NULL COLLATE NOCASE,
      delta INTEGER NOT NULL DEFAULT 0,
      category TEXT NOT NULL DEFAULT 'other',
      source TEXT NOT NULL DEFAULT 'activity',
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (faction_id, event_key, item_name)
    )`),
    db.prepare(`INSERT OR IGNORE INTO armory_item_effects (faction_id, event_key, item_name, delta, category, source)
      SELECT faction_id, event_key,
        CASE WHEN event_type = 'xanax_use' THEN COALESCE(NULLIF(TRIM(json_extract(payload_json, '$.item')), ''), 'Xanax')
          ELSE TRIM(json_extract(payload_json, '$.item')) END,
        0, 'legacy', 'legacy'
      FROM torn_browser_events
      WHERE event_type IN ('armory_movement', 'xanax_use')
        AND (event_type = 'xanax_use' OR NULLIF(TRIM(json_extract(payload_json, '$.item')), '') IS NOT NULL)`),
    db.prepare("DROP TRIGGER IF EXISTS apply_armory_item_effect"),
    db.prepare(`CREATE TRIGGER apply_armory_item_effect
      AFTER INSERT ON armory_item_effects
      WHEN NEW.delta != 0
      BEGIN
        INSERT INTO armory_items (faction_id, item_name, category, quantity, source)
        VALUES (NEW.faction_id, NEW.item_name, NEW.category, MAX(0, NEW.delta), NEW.source)
        ON CONFLICT(faction_id, item_name) DO UPDATE SET
          quantity = MAX(0, armory_items.quantity + NEW.delta),
          category = CASE WHEN NEW.category = 'other' THEN armory_items.category ELSE NEW.category END,
          source = NEW.source,
          updated_at = CURRENT_TIMESTAMP;
      END`),
    db.prepare(`CREATE TABLE IF NOT EXISTS event_observers (
      faction_id INTEGER NOT NULL,
      event_key TEXT NOT NULL,
      observer_token_id TEXT NOT NULL,
      observer_member_id INTEGER NOT NULL,
      first_observed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      last_observed_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (faction_id, event_key, observer_token_id)
    )`),
    db.prepare(`CREATE TABLE IF NOT EXISTS sync_telemetry (
      faction_id INTEGER NOT NULL,
      source_key TEXT NOT NULL,
      last_success_at TEXT,
      last_observation_at TEXT,
      queue_depth INTEGER NOT NULL DEFAULT 0,
      details_json TEXT NOT NULL DEFAULT '{}',
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (faction_id, source_key)
    )`),
  ]);

  const columns = await db.prepare("PRAGMA table_info(armory_items)").all<{ name: string }>();
  if (!columns.results.some((column) => column.name === "observed_at")) {
    try { await db.prepare("ALTER TABLE armory_items ADD COLUMN observed_at TEXT").run(); }
    catch (error) { if (!/duplicate column/i.test(error instanceof Error ? error.message : String(error))) throw error; }
  }
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

function normalizeArmoryCategory(value: unknown, itemName = "") {
  const category = String(value ?? "").trim().toLowerCase().replace(/[_-]+/g, " ");
  if (/primary/.test(category)) return "primary";
  if (/secondary/.test(category)) return "secondary";
  if (/melee/.test(category)) return "melee";
  if (/temp|temporary/.test(category)) return "temporary";
  if (/\barmou?r\b/.test(category)) return "armor";
  if (/cloth/.test(category)) return "clothing";
  if (/medical|meds/.test(category)) return "medical";
  if (/drug/.test(category)) return "drugs";
  if (/booster/.test(category)) return "boosters";
  if (/candy|alcohol|energy drink|consumable/.test(category)) return "consumables";
  if (/utility|tool|material|enhancer/.test(category)) return "utility";
  if (/special/.test(category)) return "special";
  if (/xanax|vicodin|ecstasy|lsd|cannabis|opium|ketamine|pcp|shroom|speed/i.test(itemName)) return "drugs";
  if (/blood bag|first aid|medical|morphine|epinephrine|melatonin/i.test(itemName)) return "medical";
  return "other";
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
  const payloadLimit = eventType === "armory_snapshot" || eventType === "member_balance_snapshot" ? 60_000 : 12_000;
  if (payloadJson.length > payloadLimit) throw new Error("A browser event is too large.");
  return { eventKey, eventType, category, occurredAt, summary, sourceUrl, payload, payloadJson };
}

async function snapshot(db: D1Database, context: FactionContext) {
  const [count, latest, rows, ocRows, armoryRows, observerRows, telemetryRows] = await Promise.all([
    db.prepare("SELECT COUNT(*) AS count FROM torn_browser_events WHERE faction_id = ?").bind(context.factionId).first<{ count: number }>(),
    db.prepare("SELECT created_at FROM torn_browser_events WHERE faction_id = ? ORDER BY created_at DESC LIMIT 1").bind(context.factionId).first<{ created_at: string }>(),
    db.prepare("SELECT * FROM torn_browser_events WHERE faction_id = ? ORDER BY created_at DESC LIMIT 500").bind(context.factionId).all<BrowserEventRow>(),
    db.prepare("SELECT event_key AS eventKey, crime_name AS crimeName, status, cash_amount AS cashAmount, items_json AS itemsJson, summary, occurred_at AS occurredAt, created_at AS createdAt, updated_at AS updatedAt FROM oc_holdings WHERE faction_id = ? ORDER BY COALESCE(occurred_at, created_at) DESC LIMIT 500").bind(context.factionId).all<{ eventKey: string; crimeName: string; status: string; cashAmount: number; itemsJson: string; summary: string; occurredAt: string | null; createdAt: string; updatedAt: string }>(),
    db.prepare("SELECT item_name AS itemName, category, quantity, source, updated_at AS updatedAt FROM armory_items WHERE faction_id = ? AND quantity > 0 ORDER BY category, item_name").bind(context.factionId).all<{ itemName: string; category: string; quantity: number; source: string; updatedAt: string }>(),
    db.prepare("SELECT event_key AS eventKey, COUNT(*) AS observerCount FROM event_observers WHERE faction_id = ? GROUP BY event_key").bind(context.factionId).all<{ eventKey: string; observerCount: number }>(),
    db.prepare("SELECT source_key AS sourceKey, last_success_at AS lastSuccessAt, last_observation_at AS lastObservationAt, queue_depth AS queueDepth, details_json AS detailsJson, updated_at AS updatedAt FROM sync_telemetry WHERE faction_id = ? ORDER BY source_key").bind(context.factionId).all<{ sourceKey: string; lastSuccessAt: string | null; lastObservationAt: string | null; queueDepth: number; detailsJson: string; updatedAt: string }>(),
  ]);
  const observerCounts = new Map(observerRows.results.map((row) => [row.eventKey, row.observerCount]));
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
      observerCount: observerCounts.get(row.event_key) ?? 0,
      createdAt: row.created_at,
    };
  }).sort((a, b) => Date.parse(b.occurredAt ?? b.createdAt) - Date.parse(a.occurredAt ?? a.createdAt)).slice(0, 120);
  return {
    totalEvents: count?.count ?? 0,
    faction: { id: context.factionId, name: context.factionName },
    lastImportedAt: latest?.created_at ?? null,
    recentEvents,
    ocHoldings: ocRows.results.map((row) => ({ ...row, items: JSON.parse(row.itemsJson || "[]") })),
    armoryItems: armoryRows.results,
    syncTelemetry: telemetryRows.results.map((row) => ({ ...row, details: JSON.parse(row.detailsJson || "{}") })),
  };
}

async function importWarReport(db: D1Database, context: FactionContext, event: ReturnType<typeof cleanEvent>) {
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
    ON CONFLICT(faction_id, war_id) DO UPDATE SET
      gross_estimate = CASE WHEN pending_wars.status = 'pending' THEN excluded.gross_estimate ELSE pending_wars.gross_estimate END,
      opponent_name = CASE WHEN pending_wars.status = 'pending' THEN excluded.opponent_name ELSE pending_wars.opponent_name END,
      updated_at = CURRENT_TIMESTAMP`)
    .bind(warId, context.factionId, opponentName, endedAt, endedAt, won, grossEstimate).run();
}

async function importMemberBalance(db: D1Database, context: FactionContext, event: ReturnType<typeof cleanEvent>) {
  if (event.eventType === "member_balance_snapshot") {
    await ensureMemberBalanceSchema(db);
    const observedAt = Date.parse(event.occurredAt ?? "");
    if (!Number.isFinite(observedAt) || observedAt > Date.now() + 5 * 60 * 1000) return;
    const observedAtIso = new Date(observedAt).toISOString();
    const members = Array.isArray(event.payload.members) ? event.payload.members.slice(0, 250) : [];
    for (const rawMember of members) {
      const member = asObject(rawMember);
      const memberName = String(member.name ?? "").trim().slice(0, 80);
      const balance = asInteger(member.balance);
      if (!memberName || balance < 0) continue;
      await recordExplicitBalance(db, context, memberName, balance, observedAtIso);
    }
    return;
  }
  if (event.eventType === "member_balance_change") {
    await ensureMemberBalanceSchema(db);
    const memberName = String(event.payload.memberName ?? "").trim().slice(0, 80);
    const oldBalance = asInteger(event.payload.oldBalance);
    const newBalance = asInteger(event.payload.newBalance);
    const direction = String(event.payload.direction ?? (newBalance >= oldBalance ? "increase" : "decrease"));
    if (!memberName || oldBalance < 0 || newBalance < 0 || !new Set(["increase", "decrease"]).has(direction)) return;
    await recordBalanceObservation(db, context, {
      eventKey: event.eventKey,
      memberName,
      oldBalance,
      newBalance,
      direction: direction as "increase" | "decrease",
      summary: event.summary,
      occurredAt: event.occurredAt,
    });
    return;
  }
  if (event.eventType !== "oc_credit" && event.eventType !== "faction_payout") return;
  await ensureMemberBalanceSchema(db);
  const memberName = String(event.payload.memberName ?? event.payload.recipientName ?? "").trim().slice(0, 80);
  const amount = asInteger(event.payload.amount);
  if (!memberName || amount <= 0) return;
  if (event.eventType === "oc_credit") {
    const newBalance = asInteger(event.payload.newBalance);
    await recordBalanceEvent(db, context, {
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
    const memberId = asInteger(event.payload.memberId ?? event.payload.recipientId);
    await recordBalanceEvent(db, context, {
      eventKey: event.eventKey,
      memberId: memberId > 0 ? memberId : undefined,
      memberName,
      amount,
      kind: "payout",
      source: "funds",
      summary: event.summary,
      occurredAt: event.occurredAt,
    });
  }
}

async function importOcHolding(db: D1Database, context: FactionContext, event: ReturnType<typeof cleanEvent>) {
  if (event.eventType !== "oc_completion" || event.payload.success === false) return;
  const crimeId = asInteger(event.payload.crimeId);
  const holdingKey = crimeId > 0 ? `oc:${crimeId}` : event.eventKey;
  const crimeName = String(event.payload.crimeName ?? "Organized crime").trim().slice(0, 100) || "Organized crime";
  const cashAmount = Math.max(0, asInteger(event.payload.cashAmount));
  const status = event.payload.status === "distributed" ? "distributed" : "held";
  const items = (Array.isArray(event.payload.items) ? event.payload.items : []).slice(0, 60).map((rawItem) => {
    const item = asObject(rawItem);
    return { name: String(item.name ?? "").trim().slice(0, 80), quantity: Math.max(0, asInteger(item.quantity)) };
  }).filter((item) => item.name && item.quantity > 0);
  await db.prepare(`INSERT INTO oc_holdings
    (faction_id, event_key, crime_name, status, cash_amount, items_json, summary, occurred_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)
    ON CONFLICT(faction_id, event_key) DO UPDATE SET crime_name = excluded.crime_name, status = excluded.status,
      cash_amount = excluded.cash_amount, items_json = excluded.items_json, summary = excluded.summary,
      occurred_at = COALESCE(excluded.occurred_at, oc_holdings.occurred_at), updated_at = CURRENT_TIMESTAMP`)
    .bind(context.factionId, holdingKey, crimeName, status, cashAmount, JSON.stringify(items), event.summary, event.occurredAt).run();
}

async function importArmoryMovement(db: D1Database, context: FactionContext, event: ReturnType<typeof cleanEvent>) {
  if (event.eventType !== "armory_movement" && event.eventType !== "xanax_use") return;
  const itemName = String(event.payload.item ?? (event.eventType === "xanax_use" ? "Xanax" : "")).trim().slice(0, 80);
  const quantity = Math.max(1, asInteger(event.payload.quantity));
  const action = String(event.payload.action ?? "used").toLowerCase();
  if (!itemName) return;
  const delta = ["deposited", "returned"].includes(action) ? quantity : -quantity;
  const category = normalizeArmoryCategory(event.payload.category, itemName);
  await db.prepare(`INSERT OR IGNORE INTO armory_item_effects (faction_id, event_key, item_name, delta, category, source)
    VALUES (?, ?, ?, ?, ?, 'activity')`)
    .bind(context.factionId, event.eventKey, itemName, delta, category).run();
}

async function importArmorySnapshot(db: D1Database, context: FactionContext, event: ReturnType<typeof cleanEvent>) {
  if (event.eventType !== "armory_snapshot") return;
  const observedAtMs = Date.parse(event.occurredAt ?? "");
  if (!Number.isFinite(observedAtMs) || observedAtMs > Date.now() + 5 * 60 * 1000) return;
  const observedAt = new Date(observedAtMs).toISOString();
  const rawItems = Array.isArray(event.payload.items) ? event.payload.items.slice(0, 500) : [];
  const suppliedCategory = normalizeArmoryCategory(event.payload.category);
  const itemsByCategory = new Map<string, Map<string, ArmorySnapshotItem>>();

  for (const rawItem of rawItems) {
    const item = asObject(rawItem);
    const name = String(item.name ?? item.itemName ?? "").trim().slice(0, 100);
    const quantity = asInteger(item.quantity);
    if (!name || quantity < 0 || quantity > 1_000_000_000) continue;
    const category = normalizeArmoryCategory(item.category ?? suppliedCategory, name);
    if (category === "other" && suppliedCategory !== "other") continue;
    const group = itemsByCategory.get(category) ?? new Map<string, ArmorySnapshotItem>();
    group.set(name.toLowerCase(), { name, quantity, category });
    itemsByCategory.set(category, group);
  }

  if (itemsByCategory.size === 0) return;
  for (const [category, itemMap] of itemsByCategory) {
    const previous = await db.prepare("SELECT event_key, observed_at FROM armory_snapshot_state WHERE faction_id = ? AND category = ?").bind(context.factionId, category)
      .first<{ event_key: string; observed_at: string }>();
    if (previous?.event_key === event.eventKey) continue;
    if (previous && Date.parse(previous.observed_at) > observedAtMs) continue;
    const items = Array.from(itemMap.values());
    const statements = [
      db.prepare("DELETE FROM armory_items WHERE faction_id = ? AND category = ?").bind(context.factionId, category),
      ...items.filter((item) => item.quantity > 0).map((item) => db.prepare(`INSERT INTO armory_items
        (faction_id, item_name, category, quantity, source, observed_at, updated_at) VALUES (?, ?, ?, ?, 'snapshot', ?, CURRENT_TIMESTAMP)
        ON CONFLICT(faction_id, item_name) DO UPDATE SET category = excluded.category, quantity = excluded.quantity,
          source = 'snapshot', observed_at = excluded.observed_at, updated_at = CURRENT_TIMESTAMP`)
        .bind(context.factionId, item.name, category, item.quantity, observedAt)),
      db.prepare(`INSERT INTO armory_snapshot_state (faction_id, category, event_key, observed_at) VALUES (?, ?, ?, ?)
        ON CONFLICT(faction_id, category) DO UPDATE SET event_key = excluded.event_key, observed_at = excluded.observed_at, updated_at = CURRENT_TIMESTAMP`)
        .bind(context.factionId, category, event.eventKey, observedAt),
    ];
    await db.batch(statements);
  }
}

async function pruneEventJournal(db: D1Database, context: FactionContext) {
  await db.prepare(`DELETE FROM torn_browser_events WHERE event_key IN (
    SELECT event_key FROM torn_browser_events WHERE faction_id = ? ORDER BY created_at DESC LIMIT -1 OFFSET ?
  ) AND faction_id = ?`).bind(context.factionId, EVENT_JOURNAL_LIMIT, context.factionId).run();
}

async function requireImporter(request: Request, db: D1Database) {
  if ((request.headers.get("authorization") ?? "").startsWith("Bearer ")) {
    const actor = await requireScriptSyncActor(request, db);
    return { mode: "script" as const, actor };
  }
  return { mode: "leader" as const, actor: await requireTreasuryLeader(db) };
}

export async function GET() {
  try {
    const db = getD1();
    await ensureSchema(db);
    const actor = await requireTreasuryLeader(db);
    return Response.json(await snapshot(db, actor));
  } catch (error) {
    return Response.json({ error: error instanceof Error ? error.message : "Unable to load browser imports." }, { status: error instanceof TreasuryAccessError ? 403 : 500 });
  }
}

export async function POST(request: Request) {
  try {
    const body = await request.json() as { events?: BrowserEventInput[]; queueDepth?: unknown; factionId?: unknown };
    if (!Array.isArray(body.events) || body.events.length === 0) throw new Error("No browser events were supplied.");
    if (body.events.length > 100) throw new Error("Too many browser events were supplied at once.");
    const events = body.events.map(cleanEvent);
    const db = getD1();
    await ensureSchema(db);
    const access = await requireImporter(request, db);
    rejectFactionOverride(body as Record<string, unknown>, access.actor);
    const context: FactionContext = access.actor;
    const newEvents: typeof events = [];
    for (const event of events) {
      const inserted = await db.prepare(`INSERT OR IGNORE INTO torn_browser_events
        (faction_id, event_key, event_type, category, occurred_at, summary, source_url, payload_json)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)`)
        .bind(context.factionId, event.eventKey, event.eventType, event.category, event.occurredAt, event.summary, event.sourceUrl, event.payloadJson).run();
      if (inserted.meta.changes) newEvents.push(event);
      else await db.prepare("UPDATE torn_browser_events SET last_observed_at = CURRENT_TIMESTAMP WHERE faction_id = ? AND event_key = ?")
        .bind(context.factionId, event.eventKey).run();
      if (access.mode === "script") {
        await db.prepare(`INSERT INTO event_observers
          (faction_id, event_key, observer_token_id, observer_member_id) VALUES (?, ?, ?, ?)
          ON CONFLICT(faction_id, event_key, observer_token_id) DO UPDATE SET last_observed_at = CURRENT_TIMESTAMP`)
          .bind(context.factionId, event.eventKey, access.actor.tokenId, access.actor.memberId).run();
      }
    }
    // Derived imports own their durable idempotency. Re-run them for journal duplicates so a
    // prior failure after journal insertion can recover instead of permanently consuming work.
    for (const event of events) {
      await importWarReport(db, context, event);
      await importMemberBalance(db, context, event);
      await importOcHolding(db, context, event);
      await importArmoryMovement(db, context, event);
      await importArmorySnapshot(db, context, event);
    }
    await pruneEventJournal(db, context);
    const acceptedKeys = events.map((event) => event.eventKey);
    const queueDepth = asInteger(body.queueDepth);
    const latestObservation = events.map((event) => event.occurredAt).filter(Boolean).sort().at(-1) ?? null;
    await db.prepare(`INSERT INTO sync_telemetry
      (faction_id, source_key, last_success_at, last_observation_at, queue_depth, details_json)
      VALUES (?, 'browser_events', CURRENT_TIMESTAMP, ?, ?, ?)
      ON CONFLICT(faction_id, source_key) DO UPDATE SET
        last_success_at = CURRENT_TIMESTAMP,
        last_observation_at = COALESCE(excluded.last_observation_at, sync_telemetry.last_observation_at),
        queue_depth = excluded.queue_depth,
        details_json = excluded.details_json,
        updated_at = CURRENT_TIMESTAMP`)
      .bind(context.factionId, latestObservation, queueDepth, JSON.stringify({ accepted: acceptedKeys.length, newJournalEvents: newEvents.length })).run();
    if (access.mode === "script") {
      await recordScriptSyncPush(db, access.actor, queueDepth);
      return Response.json({ acceptedKeys, newEventCount: newEvents.length });
    }
    return Response.json({ acceptedKeys, newEventCount: newEvents.length, ...(await snapshot(db, context)) });
  } catch (error) {
    const message = error instanceof Error ? error.message : "Unable to import browser events.";
    const status = error instanceof ScriptSyncAccessError ? 401
      : error instanceof TreasuryAccessError ? 403
        : /invalid|incomplete|only|large|no browser|too many/i.test(message) ? 400 : 500;
    return Response.json({ error: message }, { status });
  }
}
