import { getD1 } from "../../../db";
import { assertArmorySchemaReady, ensureArmorySchema, recordArmoryMovement, recordArmorySnapshot } from "../../../db/armory";
import { normalizedBrowserOccurredAt } from "../../../db/browser-events";
import { ensureMemberBalanceSchema, recordBalanceEvent, recordBalanceObservation, recordExplicitBalance } from "../../../db/member-balances";
import { recordScriptSyncPush, requireScriptSyncActor, ScriptSyncAccessError, scriptSyncErrorResponse } from "../../../db/script-sync";
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

const EVENT_JOURNAL_LIMIT = 5000;
const allowedTypes = new Set([
  "faction_news", "armory", "armory_movement", "armory_snapshot", "xanax_use", "faction_payout", "faction_deposit",
  "oc_credit", "oc_completion", "member_balance_change", "member_balance_snapshot", "ranked_war_report", "active_war",
]);

async function ensureSchema(db: D1Database) {
  await assertArmorySchemaReady(db);
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
  await ensureArmorySchema(db);
  await db.prepare(`INSERT OR IGNORE INTO armory_item_effects
    (faction_id, event_key, item_name, delta, category, source, occurred_at)
    SELECT faction_id, event_key,
      CASE WHEN event_type = 'xanax_use' THEN COALESCE(NULLIF(TRIM(json_extract(payload_json, '$.item')), ''), 'Xanax')
        ELSE TRIM(json_extract(payload_json, '$.item')) END,
      0, 'legacy', 'legacy', occurred_at
    FROM torn_browser_events
    WHERE event_type IN ('armory_movement', 'xanax_use')
      AND (event_type = 'xanax_use' OR NULLIF(TRIM(json_extract(payload_json, '$.item')), '') IS NOT NULL)`).run();
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
  const rawOccurredAt = String(input.occurredAt ?? "").trim().slice(0, 40) || null;
  const summary = String(input.summary ?? "").replace(/\s+/g, " ").trim().slice(0, 500);
  const sourceUrl = String(input.sourceUrl ?? "").trim().slice(0, 500);
  const payload = asObject(input.payload);
  const allowPayloadEndedAt = eventType !== "armory_movement" && eventType !== "xanax_use";
  const occurredAt = normalizedBrowserOccurredAt(summary, rawOccurredAt, payload, allowPayloadEndedAt);

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
      occurredAt: normalizedBrowserOccurredAt(row.summary, row.occurred_at, payload),
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
  if (!itemName) return;
  await recordArmoryMovement(db, context, {
    eventKey: event.eventKey,
    itemName,
    quantity: Math.max(1, asInteger(event.payload.quantity)),
    action: String(event.payload.action ?? "used"),
    category: event.payload.category,
    occurredAt: event.occurredAt,
  });
}

async function importArmorySnapshot(db: D1Database, context: FactionContext, event: ReturnType<typeof cleanEvent>) {
  if (event.eventType !== "armory_snapshot") return;
  const observedAtMs = Date.parse(event.occurredAt ?? "");
  if (!Number.isFinite(observedAtMs) || observedAtMs > Date.now() + 5 * 60 * 1000) return;
  const rawItems = Array.isArray(event.payload.items) ? event.payload.items.slice(0, 500) : [];
  await recordArmorySnapshot(db, context, {
    eventKey: event.eventKey,
    observedAt: new Date(observedAtMs).toISOString(),
    category: event.payload.category,
    items: rawItems,
  });
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
    if (error instanceof ScriptSyncAccessError) return scriptSyncErrorResponse(error);
    const status = error instanceof TreasuryAccessError ? 403
      : /invalid|incomplete|only|large|no browser|too many/i.test(message) ? 400 : 500;
    return Response.json({ error: message }, { status });
  }
}
