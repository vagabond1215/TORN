import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { stripTypeScriptTypes } from "node:module";
import test from "node:test";
import { DatabaseSync } from "node:sqlite";

const BLOOD_COVEN = 52984;
const OTHER_FACTION = 999999;
const T1 = "2026-08-10T01:00:00.000Z";
const T2 = "2026-08-10T02:00:00.000Z";
const T3 = "2026-08-10T03:00:00.000Z";

class D1StatementAdapter {
  constructor(database, sql, values = []) {
    this.database = database;
    this.sql = sql;
    this.values = values;
  }
  bind(...values) { return new D1StatementAdapter(this.database, this.sql, values); }
  async run() {
    const result = this.database.prepare(this.sql).run(...this.values);
    return { meta: { changes: result.changes }, results: [] };
  }
  async all() { return { results: this.database.prepare(this.sql).all(...this.values).map((row) => ({ ...row })) }; }
  async first() {
    const row = this.database.prepare(this.sql).get(...this.values);
    return row ? { ...row } : null;
  }
}

class D1DatabaseAdapter {
  constructor(database) { this.database = database; }
  prepare(sql) { return new D1StatementAdapter(this.database, sql); }
  async batch(statements) {
    this.database.exec("BEGIN");
    try {
      const results = [];
      for (const statement of statements) results.push(await statement.run());
      this.database.exec("COMMIT");
      return results;
    } catch (error) {
      this.database.exec("ROLLBACK");
      throw error;
    }
  }
}

const armoryModulePromise = readFile(new URL("../db/armory.ts", import.meta.url), "utf8").then(async (source) => {
  const javascript = stripTypeScriptTypes(source, { mode: "transform" });
  return import(`data:text/javascript;base64,${Buffer.from(javascript).toString("base64")}`);
});

const browserEventModulePromise = readFile(new URL("../db/browser-events.ts", import.meta.url), "utf8").then(async (source) => {
  const javascript = stripTypeScriptTypes(source, { mode: "transform" });
  return import(`data:text/javascript;base64,${Buffer.from(javascript).toString("base64")}`);
});

async function armoryDatabase() {
  const armory = await armoryModulePromise;
  const sqlite = new DatabaseSync(":memory:");
  const d1 = new D1DatabaseAdapter(sqlite);
  await armory.ensureArmorySchema(d1);
  return { armory, sqlite, d1 };
}

async function snapshot(state, {
  factionId = BLOOD_COVEN, eventKey, observedAt, category = "drugs", items = [],
}) {
  await state.armory.recordArmorySnapshot(state.d1, { factionId }, { eventKey, observedAt, category, items });
}

async function movement(state, {
  factionId = BLOOD_COVEN, eventKey, occurredAt, itemName = "Xanax", quantity = 1,
  action = "used", category = "drugs",
}) {
  return state.armory.recordArmoryMovement(state.d1, { factionId }, {
    eventKey, occurredAt, itemName, quantity, action, category,
  });
}

function quantity(sqlite, factionId = BLOOD_COVEN, itemName = "Xanax") {
  return sqlite.prepare("SELECT quantity FROM armory_items WHERE faction_id = ? AND item_name = ? COLLATE NOCASE")
    .get(factionId, itemName)?.quantity ?? 0;
}

function triggerSql(sqlite) {
  return sqlite.prepare("SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = 'apply_armory_item_effect'").get()?.sql ?? "";
}

function normalizedSql(sql) {
  return sql.replaceAll("`", "").replace(/IF NOT EXISTS/gi, "").replace(/\s+/g, " ").trim();
}

test("A1 chronological snapshots followed by a movement produce quantity 9", async () => {
  const state = await armoryDatabase();
  await snapshot(state, { eventKey: "snapshot:a1:t1", observedAt: T1, items: [{ name: "Xanax", quantity: 10 }] });
  await snapshot(state, { eventKey: "snapshot:a1:t2", observedAt: T2, items: [{ name: "Xanax", quantity: 10 }] });
  await movement(state, { eventKey: "movement:a1:t3", occurredAt: T3 });
  assert.equal(quantity(state.sqlite), 9);
  state.sqlite.close();
});

test("A2 a delayed snapshot cannot erase a later movement", async () => {
  const state = await armoryDatabase();
  await snapshot(state, { eventKey: "snapshot:a2:t1", observedAt: T1, items: [{ name: "Xanax", quantity: 10 }] });
  await movement(state, { eventKey: "movement:a2:t3", occurredAt: T3 });
  await snapshot(state, { eventKey: "snapshot:a2:t2", observedAt: T2, items: [{ name: "Xanax", quantity: 10 }] });
  assert.equal(quantity(state.sqlite), 9);
  state.sqlite.close();
});

test("A3 a later deposit of an absent item survives a delayed empty snapshot", async () => {
  const state = await armoryDatabase();
  await snapshot(state, { eventKey: "snapshot:a3:t1", observedAt: T1, items: [] });
  await movement(state, { eventKey: "movement:a3:t3", occurredAt: T3, quantity: 2, action: "deposited" });
  await snapshot(state, { eventKey: "snapshot:a3:t2", observedAt: T2, items: [] });
  assert.equal(quantity(state.sqlite), 2);
  state.sqlite.close();
});

test("A4 duplicate movement keys apply exactly once", async () => {
  const state = await armoryDatabase();
  await snapshot(state, { eventKey: "snapshot:a4", observedAt: T1, items: [{ name: "Xanax", quantity: 10 }] });
  assert.equal(await movement(state, { eventKey: "movement:a4", occurredAt: T2 }), true);
  assert.equal(await movement(state, { eventKey: "movement:a4", occurredAt: T2 }), false);
  assert.equal(quantity(state.sqlite), 9);
  state.sqlite.close();
});

test("R1 duplicate category metadata cannot steer canonical durable movement state", async () => {
  const state = await armoryDatabase();
  await snapshot(state, {
    eventKey: "snapshot:r1:drugs", observedAt: T1, category: "drugs",
    items: [{ name: "Xanax", quantity: 10 }],
  });
  await snapshot(state, {
    eventKey: "snapshot:r1:medical", observedAt: T1, category: "medical",
    items: [{ name: "Xanax", quantity: 100 }],
  });
  await movement(state, {
    eventKey: "movement:r1:medical-history", occurredAt: T2, category: "medical",
    quantity: 5, action: "deposited",
  });
  assert.equal(quantity(state.sqlite), 105);

  assert.equal(await movement(state, {
    eventKey: "movement:replay-authority", occurredAt: T3, category: "drugs",
    quantity: 1, action: "used",
  }), true);
  assert.equal(quantity(state.sqlite), 9);

  assert.equal(await movement(state, {
    eventKey: "movement:replay-authority", occurredAt: T2, category: "medical",
    quantity: 50, action: "deposited",
  }), false);
  const durable = state.sqlite.prepare(`SELECT category, delta, occurred_at, source
    FROM armory_item_effects
    WHERE faction_id = ? AND event_key = ? AND item_name = ? COLLATE NOCASE`).get(
    BLOOD_COVEN, "movement:replay-authority", "Xanax",
  );
  assert.deepEqual({ ...durable }, { category: "drugs", delta: -1, occurred_at: T3, source: "activity" });
  assert.equal(state.sqlite.prepare(`SELECT COUNT(*) AS count FROM armory_item_effects
    WHERE faction_id = ? AND event_key = ?`).get(BLOOD_COVEN, "movement:replay-authority").count, 1);
  assert.deepEqual({ ...state.sqlite.prepare(`SELECT category, quantity FROM armory_items
    WHERE faction_id = ? AND item_name = ? COLLATE NOCASE`).get(BLOOD_COVEN, "Xanax") }, {
    category: "drugs", quantity: 9,
  });
  state.sqlite.close();
});

test("R2 exact duplicate replay remains idempotent while rebuilding from durable state", async () => {
  const state = await armoryDatabase();
  await snapshot(state, { eventKey: "snapshot:r2", observedAt: T1, items: [{ name: "Xanax", quantity: 10 }] });
  const accepted = { eventKey: "movement:r2", occurredAt: T2, quantity: 2, action: "used" };
  assert.equal(await movement(state, accepted), true);
  assert.equal(await movement(state, accepted), false);
  assert.equal(await movement(state, accepted), false);
  assert.equal(quantity(state.sqlite), 8);
  assert.equal(state.sqlite.prepare("SELECT COUNT(*) AS count FROM armory_item_effects WHERE faction_id = ? AND event_key = ?")
    .get(BLOOD_COVEN, accepted.eventKey).count, 1);
  state.sqlite.close();
});

test("R3 changed duplicate amount action and time cannot alter the accepted effect", async () => {
  const state = await armoryDatabase();
  await snapshot(state, { eventKey: "snapshot:r3", observedAt: T1, items: [{ name: "Xanax", quantity: 10 }] });
  assert.equal(await movement(state, {
    eventKey: "movement:r3", occurredAt: T2, quantity: 2, action: "used",
  }), true);
  assert.equal(await movement(state, {
    eventKey: "movement:r3", occurredAt: T3, quantity: 50, action: "deposited",
  }), false);
  assert.equal(quantity(state.sqlite), 8);
  assert.deepEqual({ ...state.sqlite.prepare(`SELECT delta, occurred_at, category, source
    FROM armory_item_effects WHERE faction_id = ? AND event_key = ?`).get(BLOOD_COVEN, "movement:r3") }, {
    delta: -2, occurred_at: T2, category: "drugs", source: "activity",
  });
  state.sqlite.close();
});

test("A5 identical movement keys apply independently across factions", async () => {
  const state = await armoryDatabase();
  await snapshot(state, { factionId: BLOOD_COVEN, eventKey: "snapshot:a5:b", observedAt: T1, items: [{ name: "Xanax", quantity: 10 }] });
  await snapshot(state, { factionId: OTHER_FACTION, eventKey: "snapshot:a5:o", observedAt: T1, items: [{ name: "Xanax", quantity: 20 }] });
  await movement(state, { factionId: BLOOD_COVEN, eventKey: "movement:a5", occurredAt: T2 });
  await movement(state, { factionId: OTHER_FACTION, eventKey: "movement:a5", occurredAt: T2 });
  assert.equal(quantity(state.sqlite, BLOOD_COVEN), 9);
  assert.equal(quantity(state.sqlite, OTHER_FACTION), 19);
  state.sqlite.close();
});

test("A6 a delayed snapshot changes only its own category", async () => {
  const state = await armoryDatabase();
  await snapshot(state, { eventKey: "snapshot:a6:drugs", observedAt: T1, category: "drugs", items: [{ name: "Xanax", quantity: 10 }] });
  await snapshot(state, { eventKey: "snapshot:a6:medical:t1", observedAt: T1, category: "medical", items: [{ name: "Morphine", quantity: 5 }] });
  await movement(state, { eventKey: "movement:a6:t3", occurredAt: T3 });
  await snapshot(state, { eventKey: "snapshot:a6:medical:t2", observedAt: T2, category: "medical", items: [{ name: "Morphine", quantity: 4 }] });
  assert.equal(quantity(state.sqlite), 9);
  assert.equal(quantity(state.sqlite, BLOOD_COVEN, "Morphine"), 4);
  state.sqlite.close();
});

test("A7 replaying a snapshot cannot multiply later movement effects", async () => {
  const state = await armoryDatabase();
  await snapshot(state, { eventKey: "snapshot:a7:t1", observedAt: T1, items: [{ name: "Xanax", quantity: 10 }] });
  await movement(state, { eventKey: "movement:a7:t3", occurredAt: T3 });
  const delayed = { eventKey: "snapshot:a7:t2", observedAt: T2, items: [{ name: "Xanax", quantity: 10 }] };
  await snapshot(state, delayed);
  await snapshot(state, delayed);
  assert.equal(quantity(state.sqlite), 9);
  state.sqlite.close();
});

test("A8 historical OC rewards do not change current Armory inventory", async () => {
  const state = await armoryDatabase();
  await snapshot(state, { eventKey: "snapshot:a8", observedAt: T1, items: [{ name: "Xanax", quantity: 10 }] });
  state.sqlite.exec("CREATE TABLE oc_holdings (faction_id INTEGER, event_key TEXT, items_json TEXT)");
  state.sqlite.prepare("INSERT INTO oc_holdings VALUES (?, ?, ?)").run(BLOOD_COVEN, "oc:a8", '[{"name":"Xanax","quantity":20}]');
  assert.equal(quantity(state.sqlite), 10);
  state.sqlite.close();
});

async function equalTimeResult(order, { factionId = BLOOD_COVEN, base = 1, delayedSnapshot = false } = {}) {
  const state = await armoryDatabase();
  await snapshot(state, { factionId, eventKey: "snapshot:equal:t1", observedAt: T1, items: [{ name: "Xanax", quantity: base }] });
  for (const kind of order) {
    await movement(state, {
      factionId,
      eventKey: kind === "withdraw" ? "movement:a" : "movement:b",
      occurredAt: T3,
      quantity: 2,
      action: kind === "withdraw" ? "used" : "deposited",
    });
  }
  if (delayedSnapshot) {
    await snapshot(state, { factionId, eventKey: "snapshot:equal:t2", observedAt: T2, items: [{ name: "Xanax", quantity: base }] });
  }
  return state;
}

test("A9 equal-time opposing movements converge by event key through the zero floor", async () => {
  for (const order of [["withdraw", "deposit"], ["deposit", "withdraw"]]) {
    const state = await equalTimeResult(order);
    assert.equal(quantity(state.sqlite), 2);
    state.sqlite.close();
  }
});

test("A10 duplicate observers cannot multiply the equal-time durable effect set", async () => {
  const state = await equalTimeResult(["withdraw", "deposit"]);
  await movement(state, { eventKey: "movement:b", occurredAt: T3, quantity: 2, action: "deposited" });
  await movement(state, { eventKey: "movement:a", occurredAt: T3, quantity: 2, action: "used" });
  assert.equal(quantity(state.sqlite), 2);
  assert.equal(state.sqlite.prepare("SELECT COUNT(*) AS count FROM armory_item_effects WHERE faction_id = ?").get(BLOOD_COVEN).count, 2);
  state.sqlite.close();
});

test("A11 equal-time keys remain independent across factions", async () => {
  const state = await armoryDatabase();
  for (const [factionId, base] of [[BLOOD_COVEN, 1], [OTHER_FACTION, 5]]) {
    await snapshot(state, { factionId, eventKey: `snapshot:equal:${factionId}`, observedAt: T1, items: [{ name: "Xanax", quantity: base }] });
    await movement(state, { factionId, eventKey: "movement:b", occurredAt: T3, quantity: 2, action: "deposited" });
    await movement(state, { factionId, eventKey: "movement:a", occurredAt: T3, quantity: 2, action: "used" });
  }
  assert.equal(quantity(state.sqlite, BLOOD_COVEN), 2);
  assert.equal(quantity(state.sqlite, OTHER_FACTION), 5);
  state.sqlite.close();
});

test("R6 duplicate replay in one faction cannot rematerialize another faction", async () => {
  const state = await armoryDatabase();
  for (const [factionId, base] of [[BLOOD_COVEN, 10], [OTHER_FACTION, 20]]) {
    await snapshot(state, {
      factionId, eventKey: `snapshot:r6:${factionId}`, observedAt: T1,
      items: [{ name: "Xanax", quantity: base }],
    });
    await movement(state, { factionId, eventKey: "movement:r6", occurredAt: T2 });
  }
  await movement(state, {
    factionId: BLOOD_COVEN, eventKey: "movement:r6", occurredAt: T3,
    quantity: 99, action: "deposited", category: "medical",
  });
  assert.equal(quantity(state.sqlite, BLOOD_COVEN), 9);
  assert.equal(quantity(state.sqlite, OTHER_FACTION), 19);
  assert.equal(state.sqlite.prepare("SELECT COUNT(*) AS count FROM armory_item_effects WHERE event_key = ?")
    .get("movement:r6").count, 2);
  state.sqlite.close();
});

test("A12 delayed snapshot folding matches live equal-time materialization in either arrival order", async () => {
  for (const order of [["withdraw", "deposit"], ["deposit", "withdraw"]]) {
    const live = await equalTimeResult(order);
    const delayed = await equalTimeResult(order, { delayedSnapshot: true });
    assert.equal(quantity(live.sqlite), 2);
    assert.equal(quantity(delayed.sqlite), quantity(live.sqlite));
    live.sqlite.close();
    delayed.sqlite.close();
  }
});

test("A13 equal-time effects without a zero crossing converge to their arithmetic total", async () => {
  for (const order of [["withdraw", "deposit"], ["deposit", "withdraw"]]) {
    const state = await equalTimeResult(order, { base: 10 });
    assert.equal(quantity(state.sqlite), 10);
    state.sqlite.close();
  }
});

test("future movement timestamps are bounded while legitimate times remain accepted", async () => {
  const state = await armoryDatabase();
  const withinTolerance = new Date(Date.now() + 4 * 60 * 1000).toISOString();
  const beyondTolerance = new Date(Date.now() + 6 * 60 * 1000).toISOString();
  assert.equal(await movement(state, { eventKey: "movement:near-future", occurredAt: withinTolerance, action: "deposited" }), true);
  assert.equal(await movement(state, { eventKey: "movement:far-future", occurredAt: beyondTolerance, action: "deposited" }), false);
  assert.equal(await movement(state, { eventKey: "movement:historical", occurredAt: T2, action: "deposited" }), true);
  assert.equal(state.sqlite.prepare("SELECT COUNT(*) AS count FROM armory_item_effects").get().count, 2);
  assert.equal(state.sqlite.prepare("SELECT COUNT(*) AS count FROM armory_item_effects WHERE event_key = 'movement:far-future'").get().count, 0);
  assert.equal(quantity(state.sqlite), 2);
  state.sqlite.close();
});

test("new unknown-time movement is rejected before snapshot-backed durable state changes", async () => {
  const state = await armoryDatabase();
  await snapshot(state, { eventKey: "snapshot:null-time", observedAt: T1, items: [{ name: "Xanax", quantity: 10 }] });
  assert.equal(await movement(state, {
    eventKey: "movement:null-time", occurredAt: null, quantity: 2, action: "used",
  }), false);
  assert.equal(quantity(state.sqlite), 10);
  assert.equal(state.sqlite.prepare("SELECT COUNT(*) AS count FROM armory_item_effects WHERE faction_id = ?")
    .get(BLOOD_COVEN).count, 0);
  const route = await readFile(new URL("../app/api/torn-browser/route.ts", import.meta.url), "utf8");
  assert.match(route, /\(eventType === "armory_movement" \|\| eventType === "xanax_use"\) && !occurredAt/);
  assert.match(route, /Armory movement has an invalid occurrence time/);
  state.sqlite.close();
});

test("Armory parsing ignores irrelevant payload endedAt before future-time validation", async () => {
  const browserEvents = await browserEventModulePromise;
  const farFutureEndedAt = Math.floor((Date.now() + 24 * 60 * 60 * 1000) / 1000);
  assert.equal(browserEvents.normalizedBrowserOccurredAt("", T2, { endedAt: farFutureEndedAt }, false), T2);
  const route = await readFile(new URL("../app/api/torn-browser/route.ts", import.meta.url), "utf8");
  assert.match(route, /eventType !== "armory_movement" && eventType !== "xanax_use"/);
});

test("fresh bootstrap owns the latest Armory columns, index, and trigger", async () => {
  const state = await armoryDatabase();
  const effectColumns = state.sqlite.prepare("PRAGMA table_info(armory_item_effects)").all().map((row) => row.name);
  const snapshotColumns = state.sqlite.prepare("PRAGMA table_info(armory_snapshot_state)").all().map((row) => row.name);
  assert.equal(effectColumns.includes("occurred_at"), true);
  assert.equal(snapshotColumns.includes("items_json"), true);
  assert.ok(state.sqlite.prepare("SELECT 1 FROM sqlite_master WHERE type = 'index' AND name = 'idx_armory_effects_faction_category_occurred'").get());
  assert.match(triggerSql(state.sqlite), /NEW\.occurred_at/);
  assert.match(triggerSql(state.sqlite), /items_json/);
  state.sqlite.close();
});

test("existing pre-migration Armory tables fail without runtime mutation", async () => {
  const armory = await armoryModulePromise;
  for (const setup of [
    "CREATE TABLE armory_items (faction_id INTEGER, item_name TEXT);",
    "CREATE TABLE armory_items (faction_id INTEGER, item_name TEXT, observed_at TEXT); CREATE TABLE armory_item_effects (faction_id INTEGER, event_key TEXT, item_name TEXT);",
    "CREATE TABLE armory_items (faction_id INTEGER, item_name TEXT, observed_at TEXT); CREATE TABLE armory_item_effects (faction_id INTEGER, event_key TEXT, item_name TEXT, occurred_at TEXT); CREATE TABLE armory_snapshot_state (faction_id INTEGER, category TEXT, event_key TEXT, observed_at TEXT);",
  ]) {
    const sqlite = new DatabaseSync(":memory:");
    sqlite.exec(setup);
    const before = sqlite.prepare("SELECT type, name, sql FROM sqlite_master ORDER BY type, name").all().map((row) => ({ ...row }));
    await assert.rejects(armory.ensureArmorySchema(new D1DatabaseAdapter(sqlite)), /Armory schema migration required/);
    assert.deepEqual(sqlite.prepare("SELECT type, name, sql FROM sqlite_master ORDER BY type, name").all().map((row) => ({ ...row })), before);
    sqlite.close();
  }
});

test("formal migration preserves legacy effects with unknown time and converges with runtime schema", async () => {
  const armory = await armoryModulePromise;
  const sqlite = new DatabaseSync(":memory:");
  sqlite.exec(`
    CREATE TABLE armory_items (
      faction_id INTEGER NOT NULL, item_name TEXT NOT NULL COLLATE NOCASE, category TEXT NOT NULL,
      quantity INTEGER NOT NULL, source TEXT NOT NULL, observed_at TEXT, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (faction_id, item_name)
    );
    CREATE TABLE armory_snapshot_state (
      faction_id INTEGER NOT NULL, category TEXT NOT NULL, event_key TEXT NOT NULL, observed_at TEXT NOT NULL,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (faction_id, category)
    );
    CREATE TABLE armory_item_effects (
      faction_id INTEGER NOT NULL, event_key TEXT NOT NULL, item_name TEXT NOT NULL COLLATE NOCASE,
      delta INTEGER NOT NULL, category TEXT NOT NULL, source TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (faction_id, event_key, item_name)
    );
    CREATE TRIGGER apply_armory_item_effect AFTER INSERT ON armory_item_effects BEGIN SELECT 1; END;
    INSERT INTO armory_items(faction_id,item_name,category,quantity,source) VALUES (52984,'Xanax','drugs',24,'activity');
    INSERT INTO armory_snapshot_state(faction_id,category,event_key,observed_at) VALUES (52984,'drugs','legacy:snapshot','2026-08-01T00:00:00.000Z');
    INSERT INTO armory_item_effects(faction_id,event_key,item_name,delta,category,source) VALUES (52984,'legacy:unknown','Xanax',-1,'drugs','activity');
  `);
  for (const migrationName of ["0011_thin_pyro.sql", "0012_exotic_tarot.sql"]) {
    const migration = await readFile(new URL(`../drizzle/${migrationName}`, import.meta.url), "utf8");
    for (const statement of migration.split("--> statement-breakpoint").map((value) => value.trim()).filter(Boolean)) sqlite.exec(statement);
  }
  assert.equal(quantity(sqlite), 24);
  assert.equal(sqlite.prepare("SELECT occurred_at FROM armory_item_effects WHERE event_key = 'legacy:unknown'").get().occurred_at, null);
  assert.equal(sqlite.prepare("SELECT items_json FROM armory_snapshot_state LIMIT 1").get().items_json, null);
  const migratedTrigger = triggerSql(sqlite);
  const beforeObjects = sqlite.prepare("SELECT type, name, sql FROM sqlite_master WHERE name IN ('armory_item_effects','armory_snapshot_state','apply_armory_item_effect','idx_armory_effects_faction_category_occurred') ORDER BY type, name").all().map((row) => ({ ...row }));
  await armory.ensureArmorySchema(new D1DatabaseAdapter(sqlite));
  assert.deepEqual(sqlite.prepare("SELECT type, name, sql FROM sqlite_master WHERE name IN ('armory_item_effects','armory_snapshot_state','apply_armory_item_effect','idx_armory_effects_faction_category_occurred') ORDER BY type, name").all().map((row) => ({ ...row })), beforeObjects);

  const fresh = await armoryDatabase();
  assert.equal(normalizedSql(migratedTrigger), normalizedSql(triggerSql(fresh.sqlite)));
  fresh.sqlite.close();
  sqlite.close();
});
