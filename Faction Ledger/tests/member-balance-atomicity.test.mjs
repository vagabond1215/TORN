import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { DatabaseSync } from "node:sqlite";

const BLOOD_COVEN = 52984;
const OTHER_FACTION = 999999;
const T0 = "2026-08-08T00:00:00.000Z";
const T1 = "2026-08-08T01:00:00.000Z";
const T2 = "2026-08-08T02:00:00.000Z";

const migrationPromise = readFile(new URL("../drizzle/0009_lyrical_morlocks.sql", import.meta.url), "utf8");

async function atomicDatabase() {
  const db = new DatabaseSync(":memory:");
  db.exec(`
    CREATE TABLE member_balances (
      id INTEGER PRIMARY KEY AUTOINCREMENT,
      faction_id INTEGER NOT NULL,
      member_id INTEGER,
      member_name TEXT NOT NULL COLLATE NOCASE,
      balance INTEGER NOT NULL DEFAULT 0 CHECK (balance >= 0),
      earned_total INTEGER NOT NULL DEFAULT 0 CHECK (earned_total >= 0),
      paid_total INTEGER NOT NULL DEFAULT 0 CHECK (paid_total >= 0),
      observed_at TEXT,
      observed_priority INTEGER NOT NULL DEFAULT 0,
      resolution_status TEXT NOT NULL DEFAULT 'unresolved',
      updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
    );
    CREATE UNIQUE INDEX member_balances_faction_member_unique
      ON member_balances(faction_id, member_id) WHERE member_id IS NOT NULL;
    CREATE INDEX idx_member_balances_faction_name ON member_balances(faction_id, member_name COLLATE NOCASE);
    CREATE TABLE member_balance_entries (
      faction_id INTEGER NOT NULL,
      event_key TEXT NOT NULL,
      member_id INTEGER,
      member_name TEXT NOT NULL COLLATE NOCASE,
      amount INTEGER NOT NULL,
      kind TEXT NOT NULL CHECK (kind IN ('credit', 'payout')),
      source TEXT NOT NULL CHECK (source IN ('war', 'oc', 'funds')),
      summary TEXT NOT NULL DEFAULT '',
      occurred_at TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (faction_id, event_key)
    );
    CREATE TABLE member_balance_observations (
      faction_id INTEGER NOT NULL,
      event_key TEXT NOT NULL,
      member_id INTEGER,
      member_name TEXT NOT NULL COLLATE NOCASE,
      old_balance INTEGER NOT NULL CHECK (old_balance >= 0),
      new_balance INTEGER NOT NULL CHECK (new_balance >= 0),
      delta INTEGER NOT NULL,
      direction TEXT NOT NULL CHECK (direction IN ('increase', 'decrease')),
      summary TEXT NOT NULL DEFAULT '',
      occurred_at TEXT,
      created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (faction_id, event_key)
    );
  `);
  const migration = await migrationPromise;
  for (const statement of migration.split("--> statement-breakpoint").map((value) => value.trim()).filter(Boolean)) {
    db.exec(statement);
  }
  db.exec(`
    CREATE TABLE test_balance_failure (enabled INTEGER NOT NULL);
    INSERT INTO test_balance_failure VALUES (0);
    CREATE TRIGGER force_balance_effect_failure
    BEFORE UPDATE OF balance, earned_total, paid_total, observed_at, observed_priority ON member_balances
    WHEN (SELECT enabled FROM test_balance_failure LIMIT 1) = 1
    BEGIN
      SELECT RAISE(ABORT, 'forced balance effect failure');
    END;
  `);
  return db;
}

function seedMember(db, factionId = BLOOD_COVEN, memberId = 101, name = "Alice", balance = 100, earned = 100, paid = 0) {
  db.prepare(`INSERT INTO member_balances
    (faction_id, member_id, member_name, balance, earned_total, paid_total, observed_at, observed_priority, resolution_status)
    VALUES (?, ?, ?, ?, ?, ?, ?, 2, 'verified')`).run(factionId, memberId, name, balance, earned, paid, T0);
}

function failEffects(db, enabled) {
  db.prepare("UPDATE test_balance_failure SET enabled = ?").run(enabled ? 1 : 0);
}

function insertEntry(db, {
  factionId = BLOOD_COVEN, eventKey, memberId = 101, memberName = "Alice", amount,
  kind = "credit", source = "war", occurredAt = T1, explicitBalance = null,
}) {
  return db.prepare(`INSERT OR IGNORE INTO member_balance_entries
    (faction_id, event_key, member_id, member_name, amount, kind, source, summary, occurred_at, explicit_balance)
    VALUES (?, ?, ?, ?, ?, ?, ?, '', ?, ?)`)
    .run(factionId, eventKey, memberId, memberName, amount, kind, source, occurredAt, explicitBalance);
}

function insertObservation(db, {
  factionId = BLOOD_COVEN, eventKey, memberId = 101, memberName = "Alice",
  oldBalance, newBalance, occurredAt = T1,
}) {
  const delta = newBalance - oldBalance;
  return db.prepare(`INSERT OR IGNORE INTO member_balance_observations
    (faction_id, event_key, member_id, member_name, old_balance, new_balance, delta, direction, summary, occurred_at)
    VALUES (?, ?, ?, ?, ?, ?, ?, ?, '', ?)`)
    .run(factionId, eventKey, memberId, memberName, oldBalance, newBalance, delta, delta >= 0 ? "increase" : "decrease", occurredAt);
}

function member(db, factionId = BLOOD_COVEN, memberId = 101) {
  const row = db.prepare(`SELECT balance, earned_total AS earned, paid_total AS paid, observed_at AS observedAt,
      observed_priority AS observedPriority
    FROM member_balances WHERE faction_id = ? AND member_id = ?`).get(factionId, memberId);
  return { ...row };
}

function markerCount(db, table, factionId, eventKey) {
  return db.prepare(`SELECT COUNT(*) AS value FROM ${table} WHERE faction_id = ? AND event_key = ?`).get(factionId, eventKey).value;
}

test("credit marker and effect roll back together, then retry applies exactly once", async () => {
  const db = await atomicDatabase();
  seedMember(db);
  failEffects(db, true);
  assert.throws(() => insertEntry(db, { eventKey: "atomic:credit:1", amount: 25 }), /forced balance effect failure/);
  assert.equal(markerCount(db, "member_balance_entries", BLOOD_COVEN, "atomic:credit:1"), 0);
  assert.deepEqual(member(db), { balance: 100, earned: 100, paid: 0, observedAt: T0, observedPriority: 2 });
  failEffects(db, false);
  assert.equal(insertEntry(db, { eventKey: "atomic:credit:1", amount: 25 }).changes, 1);
  assert.equal(insertEntry(db, { eventKey: "atomic:credit:1", amount: 25 }).changes, 0);
  assert.deepEqual(member(db), { balance: 125, earned: 125, paid: 0, observedAt: T1, observedPriority: 1 });
  assert.equal(markerCount(db, "member_balance_entries", BLOOD_COVEN, "atomic:credit:1"), 1);
  db.close();
});

test("payout marker and effect roll back together, then retry applies exactly once", async () => {
  const db = await atomicDatabase();
  seedMember(db);
  failEffects(db, true);
  assert.throws(() => insertEntry(db, { eventKey: "atomic:payout:1", amount: 30, kind: "payout", source: "funds" }), /forced balance effect failure/);
  assert.equal(markerCount(db, "member_balance_entries", BLOOD_COVEN, "atomic:payout:1"), 0);
  assert.deepEqual(member(db), { balance: 100, earned: 100, paid: 0, observedAt: T0, observedPriority: 2 });
  failEffects(db, false);
  assert.equal(insertEntry(db, { eventKey: "atomic:payout:1", amount: 30, kind: "payout", source: "funds" }).changes, 1);
  assert.equal(insertEntry(db, { eventKey: "atomic:payout:1", amount: 30, kind: "payout", source: "funds" }).changes, 0);
  assert.deepEqual(member(db), { balance: 70, earned: 100, paid: 30, observedAt: T1, observedPriority: 1 });
  assert.equal(markerCount(db, "member_balance_entries", BLOOD_COVEN, "atomic:payout:1"), 1);
  db.close();
});

test("explicit observation marker and effect roll back together, then retry applies exactly once", async () => {
  const db = await atomicDatabase();
  seedMember(db);
  failEffects(db, true);
  assert.throws(() => insertObservation(db, { eventKey: "atomic:obs:1", oldBalance: 100, newBalance: 175 }), /forced balance effect failure/);
  assert.equal(markerCount(db, "member_balance_observations", BLOOD_COVEN, "atomic:obs:1"), 0);
  assert.deepEqual(member(db), { balance: 100, earned: 100, paid: 0, observedAt: T0, observedPriority: 2 });
  failEffects(db, false);
  assert.equal(insertObservation(db, { eventKey: "atomic:obs:1", oldBalance: 100, newBalance: 175 }).changes, 1);
  assert.equal(insertObservation(db, { eventKey: "atomic:obs:1", oldBalance: 100, newBalance: 175 }).changes, 0);
  assert.deepEqual(member(db), { balance: 175, earned: 100, paid: 0, observedAt: T1, observedPriority: 2 });
  assert.equal(markerCount(db, "member_balance_observations", BLOOD_COVEN, "atomic:obs:1"), 1);
  db.close();
});

test("duplicate observers cannot multiply a faction-local durable effect", async () => {
  const db = await atomicDatabase();
  seedMember(db);
  assert.equal(insertEntry(db, { eventKey: "observer:shared", amount: 15 }).changes, 1);
  assert.equal(insertEntry(db, { eventKey: "observer:shared", amount: 15 }).changes, 0);
  assert.deepEqual(member(db), { balance: 115, earned: 115, paid: 0, observedAt: T1, observedPriority: 1 });
  assert.equal(markerCount(db, "member_balance_entries", BLOOD_COVEN, "observer:shared"), 1);
  db.close();
});

test("the same event key applies independently in two factions", async () => {
  const db = await atomicDatabase();
  seedMember(db);
  seedMember(db, OTHER_FACTION, 202, "Alice", 200, 200);
  insertEntry(db, { eventKey: "shared:atomic", amount: 10 });
  insertEntry(db, { factionId: OTHER_FACTION, eventKey: "shared:atomic", memberId: 202, amount: 20 });
  assert.deepEqual(member(db), { balance: 110, earned: 110, paid: 0, observedAt: T1, observedPriority: 1 });
  assert.deepEqual(member(db, OTHER_FACTION, 202), { balance: 220, earned: 220, paid: 0, observedAt: T1, observedPriority: 1 });
  assert.equal(db.prepare("SELECT COUNT(*) AS value FROM member_balance_entries WHERE event_key = 'shared:atomic'").get().value, 2);
  db.close();
});

test("same-timestamp explicit observations beat inferred deltas in either arrival order", async () => {
  for (const explicitFirst of [false, true]) {
    const db = await atomicDatabase();
    seedMember(db);
    if (explicitFirst) insertObservation(db, { eventKey: "priority:obs", oldBalance: 100, newBalance: 175, occurredAt: T1 });
    insertEntry(db, { eventKey: "priority:credit", amount: 10, occurredAt: T1 });
    if (!explicitFirst) insertObservation(db, { eventKey: "priority:obs", oldBalance: 110, newBalance: 175, occurredAt: T1 });
    assert.deepEqual(member(db), { balance: 175, earned: 110, paid: 0, observedAt: T1, observedPriority: 2 });
    db.close();
  }
});

test("a stale unique credit increments lifetime earned without rolling back current balance", async () => {
  const db = await atomicDatabase();
  seedMember(db, BLOOD_COVEN, 101, "Alice", 100, 100);
  insertObservation(db, { eventKey: "stale:newer", oldBalance: 100, newBalance: 200, occurredAt: T2 });
  insertEntry(db, { eventKey: "stale:credit", amount: 25, occurredAt: T1 });
  assert.deepEqual(member(db), { balance: 200, earned: 125, paid: 0, observedAt: T2, observedPriority: 2 });
  db.close();
});

test("distinct events for a newly seen verified member converge on one canonical row", async () => {
  for (const amounts of [[10, 20], [20, 10]]) {
    const db = await atomicDatabase();
    insertEntry(db, { eventKey: `new:${amounts[0]}`, memberId: 303, memberName: "New Member", amount: amounts[0], occurredAt: T1 });
    insertEntry(db, { eventKey: `new:${amounts[1]}`, memberId: 303, memberName: "New Member", amount: amounts[1], occurredAt: T1 });
    assert.equal(db.prepare("SELECT COUNT(*) AS value FROM member_balances WHERE faction_id = ? AND member_id = ?").get(BLOOD_COVEN, 303).value, 1);
    assert.deepEqual(member(db, BLOOD_COVEN, 303), { balance: 30, earned: 30, paid: 0, observedAt: T1, observedPriority: 1 });
    assert.equal(db.prepare("SELECT COUNT(*) AS value FROM member_balance_entries WHERE faction_id = ? AND member_id = ?").get(BLOOD_COVEN, 303).value, 2);
    db.close();
  }
});

test("ambiguous unresolved names abort without consuming the event marker", async () => {
  const db = await atomicDatabase();
  db.prepare("INSERT INTO member_balances(faction_id,member_id,member_name) VALUES (?,NULL,?)").run(BLOOD_COVEN, "Duplicate");
  db.prepare("INSERT INTO member_balances(faction_id,member_id,member_name) VALUES (?,NULL,?)").run(BLOOD_COVEN, "Duplicate");
  assert.throws(() => insertEntry(db, { eventKey: "ambiguous:event", memberId: null, memberName: "Duplicate", amount: 10 }), /ambiguous member balance identity/);
  assert.equal(markerCount(db, "member_balance_entries", BLOOD_COVEN, "ambiguous:event"), 0);
  assert.equal(db.prepare("SELECT COUNT(*) AS value FROM member_balances WHERE faction_id = ? AND member_name = ? COLLATE NOCASE").get(BLOOD_COVEN, "Duplicate").value, 2);
  db.close();
});

test("local migration preflight reports duplicate account names and canonical member IDs", async () => {
  const db = new DatabaseSync(":memory:");
  db.exec(`
    CREATE TABLE accounts (name TEXT NOT NULL);
    CREATE TABLE member_balances (member_id INTEGER, member_name TEXT NOT NULL);
    INSERT INTO accounts VALUES ('Reserve'), ('Reserve'), ('Operations');
    INSERT INTO member_balances VALUES (101, 'Alice'), (101, 'Alice old'), (NULL, 'Unknown');
  `);
  const preflight = await readFile(new URL("../drizzle/preflight/0008_tenant_conflicts.sql", import.meta.url), "utf8");
  const statements = preflight.split("--> statement-breakpoint").map((value) => value.trim()).filter(Boolean);
  assert.deepEqual(db.prepare(statements[0]).all().map((row) => ({ ...row })), [{ conflict: "accounts_faction_name_unique", keyValue: "Reserve", rowCount: 2 }]);
  assert.deepEqual(db.prepare(statements[1]).all().map((row) => ({ ...row })), [{ conflict: "member_balances_faction_member_unique", keyValue: "101", rowCount: 2 }]);
  db.close();
});
