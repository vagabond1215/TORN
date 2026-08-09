import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import test from "node:test";
import { DatabaseSync } from "node:sqlite";

const BLOOD_COVEN = 52984;
const OTHER_FACTION = 999999;

function legacyDatabase() {
  const db = new DatabaseSync(":memory:");
  db.exec(`
    CREATE TABLE accounts (id INTEGER PRIMARY KEY AUTOINCREMENT, name TEXT NOT NULL, allocation_bps INTEGER NOT NULL DEFAULT 0, balance INTEGER NOT NULL DEFAULT 0, color TEXT NOT NULL DEFAULT 'lime', created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE transactions (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, amount INTEGER NOT NULL DEFAULT 0, from_account_id INTEGER, from_account_name TEXT, to_account_id INTEGER, to_account_name TEXT, note TEXT NOT NULL DEFAULT '', details TEXT NOT NULL DEFAULT '{}', actor_user_id TEXT, actor_email TEXT, actor_name TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
    CREATE INDEX idx_transactions_created_at ON transactions(created_at, id);
    CREATE TABLE policies (source_key TEXT PRIMARY KEY, label TEXT NOT NULL, tax_bps INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE pending_wars (war_id INTEGER PRIMARY KEY, faction_id INTEGER NOT NULL, opponent_name TEXT NOT NULL, started_at INTEGER NOT NULL, ended_at INTEGER NOT NULL, won INTEGER NOT NULL DEFAULT 0, gross_estimate INTEGER NOT NULL DEFAULT 0, reviewed_value INTEGER, reviewed_tax_bps INTEGER NOT NULL DEFAULT 2000, status TEXT NOT NULL DEFAULT 'pending', rewards_json TEXT NOT NULL DEFAULT '[]', members_json TEXT NOT NULL DEFAULT '[]', created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE active_war (war_id INTEGER PRIMARY KEY, faction_id INTEGER NOT NULL, opponent_name TEXT NOT NULL, started_at INTEGER NOT NULL, target INTEGER NOT NULL DEFAULT 0, our_score INTEGER NOT NULL DEFAULT 0, their_score INTEGER NOT NULL DEFAULT 0, our_chain INTEGER NOT NULL DEFAULT 0, their_chain INTEGER NOT NULL DEFAULT 0, members_json TEXT NOT NULL DEFAULT '[]', updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE war_member_baselines (war_id INTEGER NOT NULL, user_id INTEGER NOT NULL, name TEXT NOT NULL, base_hits INTEGER NOT NULL DEFAULT 0, base_xanax INTEGER NOT NULL DEFAULT 0, base_refills INTEGER NOT NULL DEFAULT 0, current_hits INTEGER NOT NULL DEFAULT 0, current_xanax INTEGER NOT NULL DEFAULT 0, current_refills INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(war_id,user_id));
    CREATE TABLE treasury_leaders (email TEXT PRIMARY KEY COLLATE NOCASE, display_name TEXT NOT NULL DEFAULT '', added_by TEXT NOT NULL DEFAULT '', created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE member_balances (member_name TEXT PRIMARY KEY COLLATE NOCASE, member_id INTEGER, balance INTEGER NOT NULL DEFAULT 0, earned_total INTEGER NOT NULL DEFAULT 0, paid_total INTEGER NOT NULL DEFAULT 0, observed_at TEXT, observed_priority INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE member_balance_entries (event_key TEXT PRIMARY KEY, member_id INTEGER, member_name TEXT NOT NULL COLLATE NOCASE, amount INTEGER NOT NULL, kind TEXT NOT NULL, source TEXT NOT NULL, summary TEXT NOT NULL DEFAULT '', occurred_at TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE member_balance_observations (event_key TEXT PRIMARY KEY, member_id INTEGER, member_name TEXT NOT NULL COLLATE NOCASE, old_balance INTEGER NOT NULL, new_balance INTEGER NOT NULL, delta INTEGER NOT NULL, direction TEXT NOT NULL, summary TEXT NOT NULL DEFAULT '', occurred_at TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE payout_requests (id INTEGER PRIMARY KEY AUTOINCREMENT, member_id INTEGER NOT NULL, member_name TEXT NOT NULL COLLATE NOCASE, amount INTEGER NOT NULL, status TEXT NOT NULL DEFAULT 'pending', delivery_preference TEXT NOT NULL DEFAULT 'offline', note TEXT NOT NULL DEFAULT '', requested_by_user_id TEXT NOT NULL, requested_by_email TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE oc_holdings (event_key TEXT PRIMARY KEY, crime_name TEXT NOT NULL, status TEXT NOT NULL DEFAULT 'held', cash_amount INTEGER NOT NULL DEFAULT 0, items_json TEXT NOT NULL DEFAULT '[]', summary TEXT NOT NULL DEFAULT '', occurred_at TEXT, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE armory_items (item_name TEXT PRIMARY KEY COLLATE NOCASE, category TEXT NOT NULL DEFAULT 'other', quantity INTEGER NOT NULL DEFAULT 0, source TEXT NOT NULL DEFAULT 'activity', updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE armory_snapshot_state (category TEXT PRIMARY KEY, event_key TEXT NOT NULL, observed_at TEXT NOT NULL, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE armory_item_effects (event_key TEXT NOT NULL, item_name TEXT NOT NULL COLLATE NOCASE, delta INTEGER NOT NULL DEFAULT 0, category TEXT NOT NULL DEFAULT 'other', source TEXT NOT NULL DEFAULT 'activity', created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(event_key,item_name));
    CREATE TABLE torn_browser_events (event_key TEXT PRIMARY KEY, event_type TEXT NOT NULL, category TEXT NOT NULL, occurred_at TEXT, summary TEXT NOT NULL, source_url TEXT NOT NULL DEFAULT '', payload_json TEXT NOT NULL DEFAULT '{}', created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE torn_sync_cursors (source_key TEXT PRIMARY KEY, next_offset INTEGER NOT NULL DEFAULT 0, complete INTEGER NOT NULL DEFAULT 0, updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP);
    CREATE TABLE script_sync_tokens (token_id TEXT PRIMARY KEY, member_id INTEGER NOT NULL, member_name TEXT NOT NULL COLLATE NOCASE, faction_id INTEGER, faction_name TEXT NOT NULL DEFAULT '', token_hash TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, last_used_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP, last_verified_at TEXT, expires_at TEXT, revoked_at TEXT, revoked_reason TEXT);

    INSERT INTO accounts(name,allocation_bps,balance,color) VALUES ('Reserve',6000,600,'gold'),('Operations',4000,400,'wine');
    INSERT INTO transactions(type,amount,note) VALUES ('deposit',1000,'legacy deposit');
    INSERT INTO policies(source_key,label,tax_bps) VALUES ('war','Ranked war',2000),('oc','Organized crime',500);
    INSERT INTO pending_wars VALUES (77,52984,'Opponent',1,2,1,5000,NULL,2000,'pending','[]','[]',CURRENT_TIMESTAMP,CURRENT_TIMESTAMP);
    INSERT INTO active_war VALUES (78,52984,'Opponent',3,100,10,5,2,1,'[]',CURRENT_TIMESTAMP);
    INSERT INTO war_member_baselines(war_id,user_id,name) VALUES (78,101,'Alice');
    INSERT INTO treasury_leaders(email,display_name,added_by) VALUES ('leader@example.com','Leader','seed');
    INSERT INTO member_balances(member_name,member_id,balance,earned_total,paid_total,observed_at,observed_priority) VALUES ('Alice',101,700,900,200,'2026-08-08T00:00:00.000Z',2),('Bob',NULL,300,300,0,'2026-08-08T00:00:00.000Z',2);
    INSERT INTO member_balance_entries(event_key,member_id,member_name,amount,kind,source) VALUES ('shared:event',101,'Alice',900,'credit','war');
    INSERT INTO member_balance_observations(event_key,member_id,member_name,old_balance,new_balance,delta,direction) VALUES ('obs:1',101,'Alice',0,700,700,'increase');
    INSERT INTO payout_requests(member_id,member_name,amount,status,delivery_preference,note,requested_by_user_id,requested_by_email) VALUES (101,'Alice',100,'pending','offline','','u','a@example.com');
    INSERT INTO oc_holdings(event_key,crime_name,cash_amount) VALUES ('oc:1','Blast From The Past',500);
    INSERT INTO armory_items(item_name,category,quantity,source) VALUES ('Xanax','drugs',25,'snapshot');
    INSERT INTO armory_snapshot_state(category,event_key,observed_at) VALUES ('drugs','snapshot:1','2026-08-08T00:00:00.000Z');
    INSERT INTO armory_item_effects(event_key,item_name,delta,category) VALUES ('legacy:move','Xanax',0,'drugs');
    INSERT INTO torn_browser_events(event_key,event_type,category,summary,source_url) VALUES ('shared:event','faction_news','funds','legacy','https://www.torn.com/factions.php');
    INSERT INTO torn_sync_cursors(source_key,next_offset,complete) VALUES ('organized_crimes',100,0);
    INSERT INTO script_sync_tokens(token_id,member_id,member_name,faction_id,faction_name,token_hash,last_verified_at) VALUES ('token-a',101,'Alice',52984,'Blood Coven','hash','2026-08-08T00:00:00.000Z');
  `);
  return db;
}

function metrics(db, where = "") {
  const suffix = where ? ` WHERE faction_id = ${Number(where)}` : "";
  return {
    transactions: db.prepare(`SELECT COUNT(*) AS value FROM transactions${suffix}`).get().value,
    accountBalance: db.prepare(`SELECT COALESCE(SUM(balance),0) AS value FROM accounts${suffix}`).get().value,
    member: db.prepare(`SELECT COALESCE(SUM(balance),0) AS balance, COALESCE(SUM(earned_total),0) AS earned, COALESCE(SUM(paid_total),0) AS paid FROM member_balances${suffix}`).get(),
    entries: db.prepare(`SELECT COUNT(*) AS value FROM member_balance_entries${suffix}`).get().value,
    observations: db.prepare(`SELECT COUNT(*) AS value FROM member_balance_observations${suffix}`).get().value,
    payoutRequests: db.prepare(`SELECT COUNT(*) AS value FROM payout_requests${suffix}`).get().value,
    ocs: db.prepare(`SELECT COUNT(*) AS value FROM oc_holdings${suffix}`).get().value,
    armory: db.prepare(`SELECT COUNT(*) AS value FROM armory_items${suffix}`).get().value,
    armorySnapshots: db.prepare(`SELECT COUNT(*) AS value FROM armory_snapshot_state${suffix}`).get().value,
    armoryEffects: db.prepare(`SELECT COUNT(*) AS value FROM armory_item_effects${suffix}`).get().value,
    pendingWars: db.prepare(`SELECT COUNT(*) AS value FROM pending_wars${suffix}`).get().value,
    activeWars: db.prepare(`SELECT COUNT(*) AS value FROM active_war${suffix}`).get().value,
    warBaselines: db.prepare(`SELECT COUNT(*) AS value FROM war_member_baselines${suffix}`).get().value,
    leaders: db.prepare(`SELECT COUNT(*) AS value FROM treasury_leaders${suffix}`).get().value,
    browserEvents: db.prepare(`SELECT COUNT(*) AS value FROM torn_browser_events${suffix}`).get().value,
    cursors: db.prepare(`SELECT COUNT(*) AS value FROM torn_sync_cursors${suffix}`).get().value,
    syncTokens: db.prepare(`SELECT COUNT(*) AS value FROM script_sync_tokens${suffix}`).get().value,
  };
}

async function applyTenantMigrations(db) {
  for (const path of ["../drizzle/0008_sparkling_scream.sql", "../drizzle/0009_lyrical_morlocks.sql", "../drizzle/0010_fluffy_luckman.sql"]) {
    const sql = await readFile(new URL(path, import.meta.url), "utf8");
    for (const statement of sql.split("--> statement-breakpoint").map((value) => value.trim()).filter(Boolean)) db.exec(statement);
  }
}

test("migration preserves Blood Coven rows and financial totals", async () => {
  const db = legacyDatabase();
  const before = metrics(db);
  await applyTenantMigrations(db);
  const after = metrics(db, BLOOD_COVEN);
  assert.deepEqual(after, before);
  for (const table of ["accounts","transactions","policies","pending_wars","active_war","war_member_baselines","treasury_leaders","member_balances","member_balance_entries","member_balance_observations","payout_requests","oc_holdings","armory_items","armory_snapshot_state","armory_item_effects","torn_browser_events","torn_sync_cursors","script_sync_tokens"]) {
    assert.equal(db.prepare(`SELECT COUNT(*) AS value FROM ${table} WHERE faction_id != ? OR faction_id IS NULL`).get(BLOOD_COVEN).value, 0, `${table} backfill`);
  }
  assert.equal(db.prepare("SELECT name FROM factions WHERE faction_id = ?").get(BLOOD_COVEN).name, "Blood Coven");
  assert.equal(db.prepare("SELECT resolution_status FROM member_balances WHERE faction_id = ? AND member_id = 101").get(BLOOD_COVEN).resolution_status, "verified");
  assert.equal(db.prepare("SELECT resolution_status FROM member_balances WHERE faction_id = ? AND member_name = 'Bob'").get(BLOOD_COVEN).resolution_status, "unresolved");
  db.close();
});

test("two factions isolate identities, keys, inventory, policy, authorization, cursors, and replay effects", async () => {
  const db = legacyDatabase();
  await applyTenantMigrations(db);
  db.prepare("INSERT INTO factions(faction_id,name,slug) VALUES (?,?,?)").run(OTHER_FACTION,"Synthetic Faction","synthetic-faction");
  db.prepare("INSERT INTO member_balances(faction_id,member_id,member_name,balance,resolution_status) VALUES (?,?,?,?, 'verified')").run(OTHER_FACTION,202,"Alice",999);
  db.prepare("INSERT INTO accounts(faction_id,name,allocation_bps,balance,color) VALUES (?,?,?,?,?)").run(OTHER_FACTION,"Reserve",10000,999,"gold");
  db.prepare("INSERT INTO armory_items(faction_id,item_name,category,quantity,source) VALUES (?,?,?,?,?)").run(OTHER_FACTION,"Xanax","drugs",10,"snapshot");
  db.prepare("INSERT INTO armory_snapshot_state(faction_id,category,event_key,observed_at) VALUES (?,?,?,?)").run(OTHER_FACTION,"drugs","snapshot:1","2026-08-08T01:00:00.000Z");
  db.prepare("INSERT INTO member_balance_entries(faction_id,event_key,member_id,member_name,amount,kind,source) VALUES (?,?,?,?,?,?,?)").run(OTHER_FACTION,"shared:event",202,"Alice",50,"credit","war");
  assert.equal(db.prepare("INSERT OR IGNORE INTO member_balance_entries(faction_id,event_key,member_id,member_name,amount,kind,source) VALUES (?,?,?,?,?,?,?)").run(BLOOD_COVEN,"shared:event",101,"Alice",50,"credit","war").changes, 0);
  db.prepare("INSERT INTO oc_holdings(faction_id,event_key,crime_name) VALUES (?,?,?)").run(OTHER_FACTION,"oc:1","Blast From The Past");
  db.prepare("INSERT INTO pending_wars(faction_id,war_id,opponent_name,started_at,ended_at) VALUES (?,?,?,?,?)").run(OTHER_FACTION,77,"Other Opponent",1,2);
  db.prepare("INSERT INTO torn_browser_events(faction_id,event_key,event_type,category,summary,source_url) VALUES (?,?,?,?,?,?)").run(OTHER_FACTION,"shared:event","faction_news","funds","other","https://www.torn.com/factions.php");
  db.prepare("INSERT INTO policies(faction_id,source_key,label,tax_bps) VALUES (?,?,?,?)").run(OTHER_FACTION,"war","Ranked war",1000);
  db.prepare("INSERT INTO treasury_leaders(faction_id,email,display_name,added_by) VALUES (?,?,?,?)").run(BLOOD_COVEN,"only-a@example.com","Only A","seed");
  db.prepare("INSERT INTO torn_sync_cursors(faction_id,source_key,next_offset,complete) VALUES (?,?,?,?)").run(OTHER_FACTION,"organized_crimes",300,1);

  assert.equal(db.prepare("SELECT balance FROM member_balances WHERE faction_id=? AND member_id=?").get(BLOOD_COVEN,101).balance,700);
  assert.equal(db.prepare("SELECT balance FROM member_balances WHERE faction_id=? AND member_id=?").get(OTHER_FACTION,202).balance,1049);
  assert.equal(db.prepare("SELECT balance FROM accounts WHERE faction_id=? AND name='Reserve'").get(BLOOD_COVEN).balance,600);
  assert.equal(db.prepare("SELECT balance FROM accounts WHERE faction_id=? AND name='Reserve'").get(OTHER_FACTION).balance,999);
  assert.equal(db.prepare("SELECT quantity FROM armory_items WHERE faction_id=? AND item_name='Xanax'").get(BLOOD_COVEN).quantity,25);
  assert.equal(db.prepare("SELECT quantity FROM armory_items WHERE faction_id=? AND item_name='Xanax'").get(OTHER_FACTION).quantity,10);
  assert.equal(db.prepare("SELECT COUNT(*) AS value FROM member_balance_entries WHERE event_key='shared:event'").get().value,2);
  assert.equal(db.prepare("SELECT COUNT(*) AS value FROM oc_holdings WHERE event_key='oc:1'").get().value,2);
  assert.equal(db.prepare("SELECT COUNT(*) AS value FROM pending_wars WHERE war_id=77").get().value,2);
  assert.equal(db.prepare("SELECT COUNT(*) AS value FROM torn_browser_events WHERE event_key='shared:event'").get().value,2);
  assert.equal(db.prepare("SELECT COUNT(*) AS value FROM armory_snapshot_state WHERE category='drugs'").get().value,2);
  assert.equal(db.prepare("SELECT tax_bps FROM policies WHERE faction_id=? AND source_key='war'").get(BLOOD_COVEN).tax_bps,2000);
  assert.equal(db.prepare("SELECT tax_bps FROM policies WHERE faction_id=? AND source_key='war'").get(OTHER_FACTION).tax_bps,1000);
  assert.equal(db.prepare("SELECT COUNT(*) AS value FROM treasury_leaders WHERE faction_id=? AND email='only-a@example.com'").get(OTHER_FACTION).value,0);
  assert.equal(db.prepare("SELECT next_offset FROM torn_sync_cursors WHERE faction_id=? AND source_key='organized_crimes'").get(BLOOD_COVEN).next_offset,100);
  assert.equal(db.prepare("SELECT next_offset FROM torn_sync_cursors WHERE faction_id=? AND source_key='organized_crimes'").get(OTHER_FACTION).next_offset,300);

  db.prepare("INSERT INTO event_observers(faction_id,event_key,observer_token_id,observer_member_id) VALUES (?,?,?,?)").run(BLOOD_COVEN,"shared:move","observer-a",101);
  db.prepare("INSERT INTO event_observers(faction_id,event_key,observer_token_id,observer_member_id) VALUES (?,?,?,?)").run(BLOOD_COVEN,"shared:move","observer-b",102);
  assert.equal(db.prepare("SELECT COUNT(*) AS value FROM event_observers WHERE faction_id=? AND event_key='shared:move'").get(BLOOD_COVEN).value,2);

  db.prepare("INSERT INTO armory_item_effects(faction_id,event_key,item_name,delta,category,source) VALUES (?,?,?,?,?,?)").run(BLOOD_COVEN,"shared:move","Xanax",-1,"drugs","activity");
  assert.equal(db.prepare("INSERT OR IGNORE INTO armory_item_effects(faction_id,event_key,item_name,delta,category,source) VALUES (?,?,?,?,?,?)").run(BLOOD_COVEN,"shared:move","Xanax",-1,"drugs","activity").changes,0);
  db.prepare("INSERT INTO armory_item_effects(faction_id,event_key,item_name,delta,category,source) VALUES (?,?,?,?,?,?)").run(OTHER_FACTION,"shared:move","Xanax",-1,"drugs","activity");
  db.prepare("DELETE FROM torn_browser_events WHERE faction_id=?").run(BLOOD_COVEN);
  assert.equal(db.prepare("INSERT OR IGNORE INTO armory_item_effects(faction_id,event_key,item_name,delta,category,source) VALUES (?,?,?,?,?,?)").run(BLOOD_COVEN,"shared:move","Xanax",-1,"drugs","activity").changes,0);
  assert.equal(db.prepare("SELECT quantity FROM armory_items WHERE faction_id=? AND item_name='Xanax'").get(BLOOD_COVEN).quantity,24);
  assert.equal(db.prepare("SELECT quantity FROM armory_items WHERE faction_id=? AND item_name='Xanax'").get(OTHER_FACTION).quantity,9);
  db.prepare("INSERT INTO oc_holdings(faction_id,event_key,crime_name,items_json) VALUES (?,?,?,?)").run(BLOOD_COVEN,"oc:xanax-history","OC reward",'[{"name":"Xanax","quantity":20}]');
  assert.equal(db.prepare("SELECT quantity FROM armory_items WHERE faction_id=? AND item_name='Xanax'").get(BLOOD_COVEN).quantity,24);
  db.close();
});

test("routes derive tenant from verified context and client state is faction scoped", async () => {
  const [browserRoute, budgetRoute, accessRoute, memberRoute, balances, script] = await Promise.all([
    readFile(new URL("../app/api/torn-browser/route.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/api/budget/route.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/api/access/route.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/api/member-balance/route.ts", import.meta.url), "utf8"),
    readFile(new URL("../db/member-balances.ts", import.meta.url), "utf8"),
    readFile(new URL("../public/blood-coven-treasury.user.js", import.meta.url), "utf8"),
  ]);
  assert.match(browserRoute, /rejectFactionOverride\(body/);
  assert.match(browserRoute, /access\.actor/);
  assert.match(budgetRoute, /rejectFactionOverride\(payload, actor\)/);
  assert.match(accessRoute, /WHERE faction_id = \?/);
  assert.match(memberRoute, /WHERE faction_id = \? AND member_id = \?/);
  assert.match(balances, /incoming > current \|\| \(incoming === current && priority >= row\.observed_priority\)/);
  assert.match(browserRoute, /previous && Date\.parse\(previous\.observed_at\) > observedAtMs/);
  assert.match(browserRoute, /event\.eventType === "member_balance_snapshot"/);
  assert.match(script, /ACTIVE_SCOPE_KEY/);
  assert.match(script, /scopedKey\(QUEUE_KEY\)/);
  assert.match(script, /clearFactionState\("Faction identity changed/);
  assert.match(script, /queueDepth: queue\(\)\.length/);
  assert.match(script, /status === 503/);
  assert.match(script, /Existing local state was retained/);
});
