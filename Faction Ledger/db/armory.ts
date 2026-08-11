export type ArmoryContext = { factionId: number };

export type ArmoryMovement = {
  eventKey: string;
  itemName: string;
  quantity: number;
  action: string;
  category: unknown;
  occurredAt?: string | null;
};

export type ArmorySnapshot = {
  eventKey: string;
  observedAt: string;
  category: unknown;
  items: unknown[];
};

type JsonObject = Record<string, unknown>;
type SnapshotItem = { name: string; quantity: number; category: string };

export const applyArmoryItemEffectTrigger = `CREATE TRIGGER IF NOT EXISTS apply_armory_item_effect
  AFTER INSERT ON armory_item_effects
  WHEN NEW.delta != 0 AND (
    NOT EXISTS (
      SELECT 1 FROM armory_snapshot_state
      WHERE faction_id = NEW.faction_id AND category = NEW.category
    )
    OR (
      NEW.occurred_at IS NOT NULL
      AND julianday(NEW.occurred_at) > julianday((
        SELECT observed_at FROM armory_snapshot_state
        WHERE faction_id = NEW.faction_id AND category = NEW.category
      ))
    )
  )
  BEGIN
    INSERT INTO armory_items (faction_id, item_name, category, quantity, source, observed_at)
    VALUES (NEW.faction_id, NEW.item_name, NEW.category, MAX(0, NEW.delta), NEW.source, NEW.occurred_at)
    ON CONFLICT(faction_id, item_name) DO UPDATE SET
      quantity = MAX(0, armory_items.quantity + NEW.delta),
      category = CASE WHEN NEW.category = 'other' THEN armory_items.category ELSE NEW.category END,
      source = NEW.source,
      observed_at = COALESCE(NEW.occurred_at, armory_items.observed_at),
      updated_at = CURRENT_TIMESTAMP;
  END`;

function asObject(value: unknown): JsonObject {
  return value && typeof value === "object" && !Array.isArray(value) ? value as JsonObject : {};
}

function asInteger(value: unknown) {
  const number = Number(value);
  return Number.isSafeInteger(number) ? number : 0;
}

function normalizedTimestamp(value?: string | null) {
  const parsed = Date.parse(value ?? "");
  return Number.isFinite(parsed) ? new Date(parsed).toISOString() : null;
}

export function normalizeArmoryCategory(value: unknown, itemName = "") {
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

async function missingColumns(db: D1Database, table: string, required: string[]) {
  const existing = await db.prepare("SELECT name FROM sqlite_master WHERE type = 'table' AND name = ?").bind(table).first<{ name: string }>();
  if (!existing) return [];
  const columns = await db.prepare(`PRAGMA table_info(${table})`).all<{ name: string }>();
  const names = new Set(columns.results.map((column) => column.name));
  return required.filter((column) => !names.has(column));
}

export async function assertArmorySchemaReady(db: D1Database) {
  const itemColumns = await missingColumns(db, "armory_items", ["observed_at"]);
  if (itemColumns.length) {
    throw new Error(`Armory schema migration required; armory_items is missing: ${itemColumns.join(", ")}.`);
  }
  const effectColumns = await missingColumns(db, "armory_item_effects", ["occurred_at"]);
  if (effectColumns.length) {
    throw new Error(`Armory schema migration required; armory_item_effects is missing: ${effectColumns.join(", ")}.`);
  }
}

export async function ensureArmorySchema(db: D1Database) {
  await assertArmorySchemaReady(db);
  await db.batch([
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
      occurred_at TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (faction_id, event_key, item_name)
    )`),
    db.prepare("CREATE INDEX IF NOT EXISTS idx_armory_effects_faction_category_occurred ON armory_item_effects(faction_id, category, occurred_at)"),
  ]);
  await assertArmorySchemaReady(db);
  await db.prepare(applyArmoryItemEffectTrigger).run();
}

export async function recordArmoryMovement(db: D1Database, context: ArmoryContext, movement: ArmoryMovement) {
  const itemName = movement.itemName.trim().slice(0, 80);
  if (!itemName) return false;
  const quantity = Math.max(1, Math.trunc(movement.quantity));
  const action = movement.action.trim().toLowerCase();
  const delta = ["deposited", "returned"].includes(action) ? quantity : -quantity;
  const category = normalizeArmoryCategory(movement.category, itemName);
  const inserted = await db.prepare(`INSERT OR IGNORE INTO armory_item_effects
    (faction_id, event_key, item_name, delta, category, source, occurred_at)
    VALUES (?, ?, ?, ?, ?, 'activity', ?)`)
    .bind(context.factionId, movement.eventKey, itemName, delta, category, normalizedTimestamp(movement.occurredAt)).run();
  return Boolean(inserted.meta.changes);
}

export async function recordArmorySnapshot(db: D1Database, context: ArmoryContext, snapshot: ArmorySnapshot) {
  const observedAt = normalizedTimestamp(snapshot.observedAt);
  if (!observedAt) return;
  const suppliedCategory = normalizeArmoryCategory(snapshot.category);
  const itemsByCategory = new Map<string, Map<string, SnapshotItem>>();

  for (const rawItem of snapshot.items.slice(0, 500)) {
    const item = asObject(rawItem);
    const name = String(item.name ?? item.itemName ?? "").trim().slice(0, 100);
    const quantity = asInteger(item.quantity);
    if (!name || quantity < 0 || quantity > 1_000_000_000) continue;
    const category = normalizeArmoryCategory(item.category ?? suppliedCategory, name);
    if (category === "other" && suppliedCategory !== "other") continue;
    const group = itemsByCategory.get(category) ?? new Map<string, SnapshotItem>();
    group.set(name.toLowerCase(), { name, quantity, category });
    itemsByCategory.set(category, group);
  }
  if (suppliedCategory !== "other" && !itemsByCategory.has(suppliedCategory)) {
    itemsByCategory.set(suppliedCategory, new Map());
  }

  for (const [category, itemMap] of itemsByCategory) {
    const acceptedSnapshot = db.prepare(`INSERT INTO armory_snapshot_state (faction_id, category, event_key, observed_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(faction_id, category) DO UPDATE SET
        event_key = excluded.event_key,
        observed_at = excluded.observed_at,
        updated_at = CURRENT_TIMESTAMP
      WHERE armory_snapshot_state.event_key != excluded.event_key AND (
        julianday(excluded.observed_at) > julianday(armory_snapshot_state.observed_at)
        OR (
          julianday(excluded.observed_at) = julianday(armory_snapshot_state.observed_at)
          AND excluded.event_key > armory_snapshot_state.event_key
        )
      )`).bind(context.factionId, category, snapshot.eventKey, observedAt);
    const isCurrentSnapshot = `EXISTS (
      SELECT 1 FROM armory_snapshot_state
      WHERE faction_id = ? AND category = ? AND event_key = ? AND observed_at = ?
    )`;
    const statements = [
      acceptedSnapshot,
      db.prepare(`DELETE FROM armory_items WHERE faction_id = ? AND category = ? AND ${isCurrentSnapshot}`)
        .bind(context.factionId, category, context.factionId, category, snapshot.eventKey, observedAt),
      ...Array.from(itemMap.values()).filter((item) => item.quantity > 0).map((item) => db.prepare(`INSERT INTO armory_items
        (faction_id, item_name, category, quantity, source, observed_at, updated_at)
        SELECT ?, ?, ?, ?, 'snapshot', ?, CURRENT_TIMESTAMP WHERE ${isCurrentSnapshot}
        ON CONFLICT(faction_id, item_name) DO UPDATE SET
          category = excluded.category,
          quantity = excluded.quantity,
          source = excluded.source,
          observed_at = excluded.observed_at,
          updated_at = CURRENT_TIMESTAMP`)
        .bind(context.factionId, item.name, category, item.quantity, observedAt,
          context.factionId, category, snapshot.eventKey, observedAt)),
      db.prepare(`WITH ordered_effects AS (
          SELECT item_name, category, delta, occurred_at, event_key,
            SUM(delta) OVER (
              PARTITION BY item_name COLLATE NOCASE
              ORDER BY julianday(occurred_at), event_key, item_name
              ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
            ) AS running_delta,
            ROW_NUMBER() OVER (
              PARTITION BY item_name COLLATE NOCASE
              ORDER BY julianday(occurred_at) DESC, event_key DESC, item_name DESC
            ) AS latest_rank
          FROM armory_item_effects
          WHERE faction_id = ? AND category = ? AND occurred_at IS NOT NULL
            AND julianday(occurred_at) > julianday(?)
            AND ${isCurrentSnapshot}
        ), effect_totals AS (
          SELECT item_name,
            SUM(delta) AS total_delta,
            MIN(running_delta) AS min_running_delta,
            MAX(CASE WHEN latest_rank = 1 THEN category END) AS category,
            MAX(CASE WHEN latest_rank = 1 THEN occurred_at END) AS occurred_at
          FROM ordered_effects
          GROUP BY item_name COLLATE NOCASE
        )
        INSERT INTO armory_items (faction_id, item_name, category, quantity, source, observed_at, updated_at)
        SELECT ?, totals.item_name, totals.category,
          MAX(0, COALESCE(current.quantity, 0) + totals.total_delta
            - MIN(0, COALESCE(current.quantity, 0) + MIN(0, totals.min_running_delta))),
          'activity', totals.occurred_at, CURRENT_TIMESTAMP
        FROM effect_totals AS totals
        LEFT JOIN armory_items AS current
          ON current.faction_id = ? AND current.item_name = totals.item_name COLLATE NOCASE
        WHERE ${isCurrentSnapshot}
        ON CONFLICT(faction_id, item_name) DO UPDATE SET
          category = excluded.category,
          quantity = excluded.quantity,
          source = excluded.source,
          observed_at = excluded.observed_at,
          updated_at = CURRENT_TIMESTAMP`)
        .bind(context.factionId, category, observedAt,
          context.factionId, category, snapshot.eventKey, observedAt,
          context.factionId, context.factionId,
          context.factionId, category, snapshot.eventKey, observedAt),
    ];
    await db.batch(statements);
  }
}
