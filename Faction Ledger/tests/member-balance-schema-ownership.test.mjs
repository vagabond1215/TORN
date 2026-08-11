import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { stripTypeScriptTypes } from "node:module";
import test from "node:test";
import { DatabaseSync } from "node:sqlite";

class D1StatementAdapter {
  constructor(database, sql, values = []) {
    this.database = database;
    this.sql = sql;
    this.values = values;
  }

  bind(...values) {
    return new D1StatementAdapter(this.database, this.sql, values);
  }

  async run() {
    const result = this.database.prepare(this.sql).run(...this.values);
    return { meta: { changes: result.changes }, results: [] };
  }

  async all() {
    return { results: this.database.prepare(this.sql).all(...this.values).map((row) => ({ ...row })) };
  }

  async first() {
    const row = this.database.prepare(this.sql).get(...this.values);
    return row ? { ...row } : null;
  }
}

class D1DatabaseAdapter {
  constructor(database) {
    this.database = database;
  }

  prepare(sql) {
    return new D1StatementAdapter(this.database, sql);
  }

  async batch(statements) {
    const results = [];
    for (const statement of statements) results.push(await statement.run());
    return results;
  }
}

async function loadMemberBalanceModule() {
  const [tenantSource, balanceSource] = await Promise.all([
    readFile(new URL("../db/tenant.ts", import.meta.url), "utf8"),
    readFile(new URL("../db/member-balances.ts", import.meta.url), "utf8"),
  ]);
  const tenantJavaScript = stripTypeScriptTypes(tenantSource, { mode: "transform" });
  const tenantUrl = `data:text/javascript;base64,${Buffer.from(tenantJavaScript).toString("base64")}`;
  const linkedBalanceSource = balanceSource.replaceAll('from "./tenant"', `from "${tenantUrl}"`);
  const balanceJavaScript = stripTypeScriptTypes(linkedBalanceSource, { mode: "transform" });
  const balanceUrl = `data:text/javascript;base64,${Buffer.from(balanceJavaScript).toString("base64")}`;
  return import(balanceUrl);
}

async function applyMigration(db, name) {
  const migration = await readFile(new URL(`../drizzle/${name}`, import.meta.url), "utf8");
  for (const statement of migration.split("--> statement-breakpoint").map((value) => value.trim()).filter(Boolean)) {
    db.exec(statement);
  }
}

function createPre0009BalanceSchema(db) {
  db.exec(`
    CREATE TABLE factions (
      faction_id INTEGER PRIMARY KEY, name TEXT NOT NULL, slug TEXT NOT NULL UNIQUE,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );
    CREATE TABLE faction_members (
      faction_id INTEGER NOT NULL, member_id INTEGER NOT NULL, member_name TEXT NOT NULL COLLATE NOCASE,
      last_verified_at TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (faction_id, member_id)
    );
    CREATE TABLE member_balances (
      id INTEGER PRIMARY KEY AUTOINCREMENT, faction_id INTEGER NOT NULL, member_id INTEGER,
      member_name TEXT NOT NULL COLLATE NOCASE, balance INTEGER NOT NULL DEFAULT 0,
      earned_total INTEGER NOT NULL DEFAULT 0, paid_total INTEGER NOT NULL DEFAULT 0,
      observed_at TEXT, observed_priority INTEGER NOT NULL DEFAULT 0,
      resolution_status TEXT NOT NULL DEFAULT 'unresolved', updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );
    CREATE UNIQUE INDEX member_balances_faction_member_unique
      ON member_balances(faction_id, member_id) WHERE member_id IS NOT NULL;
    CREATE TABLE member_balance_entries (
      faction_id INTEGER NOT NULL, event_key TEXT NOT NULL, member_id INTEGER,
      member_name TEXT NOT NULL COLLATE NOCASE, amount INTEGER NOT NULL,
      kind TEXT NOT NULL, source TEXT NOT NULL, summary TEXT NOT NULL DEFAULT '',
      occurred_at TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (faction_id, event_key)
    );
    CREATE TABLE member_balance_observations (
      faction_id INTEGER NOT NULL, event_key TEXT NOT NULL, member_id INTEGER,
      member_name TEXT NOT NULL COLLATE NOCASE, old_balance INTEGER NOT NULL,
      new_balance INTEGER NOT NULL, delta INTEGER NOT NULL, direction TEXT NOT NULL,
      summary TEXT NOT NULL DEFAULT '', occurred_at TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY (faction_id, event_key)
    );
    CREATE TABLE payout_requests (
      id INTEGER PRIMARY KEY AUTOINCREMENT, faction_id INTEGER NOT NULL, member_id INTEGER NOT NULL,
      member_name TEXT NOT NULL COLLATE NOCASE, amount INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'pending',
      delivery_preference TEXT NOT NULL DEFAULT 'offline', note TEXT NOT NULL DEFAULT '',
      requested_by_user_id TEXT NOT NULL, requested_by_email TEXT NOT NULL,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );
  `);
}

function columns(db) {
  return db.prepare("PRAGMA table_info(member_balance_entries)").all().map((row) => row.name);
}

function triggerSql(db) {
  return db.prepare("SELECT sql FROM sqlite_master WHERE type = 'trigger' AND name = 'apply_member_balance_entry'").get()?.sql ?? "";
}

function normalizedTrigger(sql) {
  return sql.replaceAll("`", "").replace(/IF NOT EXISTS/gi, "").replace(/\s+/g, " ").trim();
}

test("fresh runtime bootstrap creates the latest member balance shape and trigger", async () => {
  const { ensureMemberBalanceSchema } = await loadMemberBalanceModule();
  const sqlite = new DatabaseSync(":memory:");
  await ensureMemberBalanceSchema(new D1DatabaseAdapter(sqlite));
  assert.equal(columns(sqlite).includes("explicit_balance"), true);
  assert.equal(columns(sqlite).includes("payout_request_id"), true);
  assert.match(triggerSql(sqlite), /payout_request_id/);
  sqlite.close();
});

test("an existing pre-migration table fails clearly without runtime schema mutation", async () => {
  const { ensureMemberBalanceSchema } = await loadMemberBalanceModule();
  const sqlite = new DatabaseSync(":memory:");
  sqlite.exec("CREATE TABLE member_balance_entries (faction_id INTEGER NOT NULL, event_key TEXT NOT NULL, PRIMARY KEY (faction_id, event_key));");
  const beforeColumns = columns(sqlite);
  const beforeObjects = sqlite.prepare("SELECT type, name, sql FROM sqlite_master ORDER BY type, name").all().map((row) => ({ ...row }));
  await assert.rejects(
    ensureMemberBalanceSchema(new D1DatabaseAdapter(sqlite)),
    /schema migration required.*explicit_balance, payout_request_id/i,
  );
  assert.deepEqual(columns(sqlite), beforeColumns);
  assert.deepEqual(sqlite.prepare("SELECT type, name, sql FROM sqlite_master ORDER BY type, name").all().map((row) => ({ ...row })), beforeObjects);
  sqlite.close();
});

test("formal migrations own existing schema evolution and match the runtime trigger", async () => {
  const { ensureMemberBalanceSchema } = await loadMemberBalanceModule();
  const migrated = new DatabaseSync(":memory:");
  createPre0009BalanceSchema(migrated);
  await applyMigration(migrated, "0009_lyrical_morlocks.sql");
  await applyMigration(migrated, "0010_fluffy_luckman.sql");
  const migratedColumns = columns(migrated);
  const migratedTrigger = triggerSql(migrated);
  await ensureMemberBalanceSchema(new D1DatabaseAdapter(migrated));
  assert.deepEqual(columns(migrated), migratedColumns);
  assert.equal(triggerSql(migrated), migratedTrigger);

  const fresh = new DatabaseSync(":memory:");
  await ensureMemberBalanceSchema(new D1DatabaseAdapter(fresh));
  assert.equal(normalizedTrigger(triggerSql(migrated)), normalizedTrigger(triggerSql(fresh)));
  migrated.close();
  fresh.close();
});

test("the runtime event insert selects and settles a request by canonical member ID", async () => {
  const { ensureMemberBalanceSchema, recordBalanceEvent } = await loadMemberBalanceModule();
  const sqlite = new DatabaseSync(":memory:");
  const d1 = new D1DatabaseAdapter(sqlite);
  await ensureMemberBalanceSchema(d1);
  sqlite.prepare(`INSERT INTO member_balances
    (faction_id, member_id, member_name, balance, earned_total, paid_total, observed_at, observed_priority, resolution_status)
    VALUES (52984, 101, 'Old Name', 100, 100, 0, '2026-08-08T00:00:00.000Z', 2, 'verified')`).run();
  const requestId = Number(sqlite.prepare(`INSERT INTO payout_requests
    (faction_id, member_id, member_name, amount, requested_by_user_id, requested_by_email)
    VALUES (52984, 101, 'Old Name', 30, 'user', 'member@example.com')`).run().lastInsertRowid);
  const context = { factionId: 52984, factionName: "Blood Coven" };
  const event = {
    eventKey: "runtime:settlement", memberId: 101, memberName: "New Name", amount: 30,
    kind: "payout", source: "funds", summary: "payout", occurredAt: "2026-08-08T01:00:00.000Z",
  };
  assert.equal(await recordBalanceEvent(d1, context, event), true);
  assert.equal(await recordBalanceEvent(d1, context, event), false);
  assert.deepEqual(
    { ...sqlite.prepare("SELECT balance, paid_total AS paid, member_name AS memberName FROM member_balances WHERE faction_id = 52984 AND member_id = 101").get() },
    { balance: 70, paid: 30, memberName: "New Name" },
  );
  assert.deepEqual(
    { ...sqlite.prepare("SELECT payout_request_id AS payoutRequestId FROM member_balance_entries WHERE faction_id = 52984 AND event_key = 'runtime:settlement'").get() },
    { payoutRequestId: requestId },
  );
  assert.equal(sqlite.prepare("SELECT status FROM payout_requests WHERE id = ?").get(requestId).status, "paid");
  sqlite.close();
});
