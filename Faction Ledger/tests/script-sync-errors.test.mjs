import assert from "node:assert/strict";
import { readFile } from "node:fs/promises";
import { stripTypeScriptTypes } from "node:module";
import test from "node:test";
import { DatabaseSync } from "node:sqlite";

const BLOOD_COVEN = 52984;

class D1StatementAdapter {
  constructor(database, sql, values = []) { this.database = database; this.sql = sql; this.values = values; }
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
    const results = [];
    for (const statement of statements) results.push(await statement.run());
    return results;
  }
}

const modulesPromise = Promise.all([
  readFile(new URL("../db/tenant.ts", import.meta.url), "utf8"),
  readFile(new URL("../db/script-sync-errors.ts", import.meta.url), "utf8"),
  readFile(new URL("../db/script-sync.ts", import.meta.url), "utf8"),
]).then(async ([tenantSource, errorSource, syncSource]) => {
  const tenantUrl = `data:text/javascript;base64,${Buffer.from(stripTypeScriptTypes(tenantSource, { mode: "transform" })).toString("base64")}`;
  const errorsUrl = `data:text/javascript;base64,${Buffer.from(stripTypeScriptTypes(errorSource, { mode: "transform" })).toString("base64")}`;
  const linkedSync = syncSource
    .replaceAll('from "./tenant"', `from "${tenantUrl}"`)
    .replaceAll('from "./script-sync-errors"', `from "${errorsUrl}"`);
  const syncUrl = `data:text/javascript;base64,${Buffer.from(stripTypeScriptTypes(linkedSync, { mode: "transform" })).toString("base64")}`;
  return { errors: await import(errorsUrl), sync: await import(syncUrl) };
});

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), { status, headers: { "content-type": "application/json" } });
}

async function withFetch(mock, action) {
  const original = globalThis.fetch;
  globalThis.fetch = mock;
  try { return await action(); }
  finally { globalThis.fetch = original; }
}

function identityFetch(memberId, factionId, memberName = "Alice", factionName = "Blood Coven") {
  return async (input) => String(input).includes("/user/basic")
    ? jsonResponse({ profile: { id: memberId, name: memberName } })
    : jsonResponse({ faction: { id: factionId, name: factionName } });
}

async function sha256(value) {
  const digest = await crypto.subtle.digest("SHA-256", new TextEncoder().encode(value));
  return Array.from(new Uint8Array(digest), (byte) => byte.toString(16).padStart(2, "0")).join("");
}

async function staleTokenDatabase() {
  const { sync } = await modulesPromise;
  const sqlite = new DatabaseSync(":memory:");
  const d1 = new D1DatabaseAdapter(sqlite);
  await sync.ensureScriptSyncSchema(d1);
  const tokenId = "a".repeat(32);
  const secret = "b".repeat(64);
  sqlite.prepare(`INSERT INTO script_sync_tokens
    (token_id, member_id, member_name, faction_id, faction_name, token_hash, last_verified_at)
    VALUES (?, 101, 'Alice', 52984, 'Blood Coven', ?, '2000-01-01T00:00:00.000Z')`)
    .run(tokenId, await sha256(secret));
  const request = new Request("https://treasury.example/api/script-sync", { headers: {
    Authorization: `Bearer bc1.${tokenId}.${secret}`,
    "X-Torn-Api-Key": "valid_key_123",
  } });
  return { sync, sqlite, d1, request, tokenId };
}

test("B1 structured sync responses preserve retryable 503 and identity 401 semantics", async () => {
  const { errors } = await modulesPromise;
  const unavailable = errors.scriptSyncErrorResponse(new errors.ScriptSyncAccessError(
    "Torn unavailable", "membership_check_unavailable", 503,
  ));
  assert.equal(unavailable.status, 503);
  assert.deepEqual(await unavailable.json(), {
    error: "Torn unavailable", code: "membership_check_unavailable", currentFaction: null,
  });

  const changed = errors.scriptSyncErrorResponse(new errors.ScriptSyncAccessError(
    "Faction changed", "faction_changed", 401, { id: 999999, name: "Other" },
  ));
  assert.equal(changed.status, 401);
  assert.deepEqual(await changed.json(), {
    error: "Faction changed", code: "faction_changed", currentFaction: { id: 999999, name: "Other" },
  });

  const [browserRouteSource, scriptRoute] = await Promise.all([
    readFile(new URL("../app/api/torn-browser/route.ts", import.meta.url), "utf8"),
    readFile(new URL("../app/api/script-sync/route.ts", import.meta.url), "utf8"),
  ]);
  const moduleUrl = (source) => `data:text/javascript;base64,${Buffer.from(source).toString("base64")}`;
  const errorsSource = await readFile(new URL("../db/script-sync-errors.ts", import.meta.url), "utf8");
  const errorsUrl = moduleUrl(stripTypeScriptTypes(errorsSource, { mode: "transform" }));
  const dbUrl = moduleUrl(`
    const statement = { bind() { return this; }, async run() { return { meta: { changes: 0 } }; }, async all() { return { results: [] }; }, async first() { return null; } };
    const db = { prepare() { return statement; }, async batch() { return []; } };
    export function getD1() { return db; }
  `);
  const armoryUrl = moduleUrl(`
    export async function assertArmorySchemaReady() {}
    export async function ensureArmorySchema() {}
    export async function recordArmoryMovement() {}
    export async function recordArmorySnapshot() {}
  `);
  const browserEventsUrl = moduleUrl(`
    export function normalizedBrowserOccurredAt() { return null; }
  `);
  const balancesUrl = moduleUrl(`
    export async function ensureMemberBalanceSchema() {}
    export async function recordBalanceEvent() { return false; }
    export async function recordBalanceObservation() { return false; }
    export async function recordExplicitBalance() { return false; }
  `);
  const syncUrl = moduleUrl(`
    import { ScriptSyncAccessError, scriptSyncErrorResponse } from "${errorsUrl}";
    export { ScriptSyncAccessError, scriptSyncErrorResponse };
    export async function requireScriptSyncActor() { throw globalThis.__scriptSyncRouteError; }
    export async function recordScriptSyncPush() {}
  `);
  const tenantUrl = moduleUrl(`
    export function rejectFactionOverride() {}
  `);
  const accessUrl = moduleUrl(`
    export class TreasuryAccessError extends Error {}
    export async function requireTreasuryLeader() { throw new TreasuryAccessError("not used"); }
  `);
  const linkedBrowserRoute = browserRouteSource
    .replace('from "../../../db"', `from "${dbUrl}"`)
    .replace('from "../../../db/armory"', `from "${armoryUrl}"`)
    .replace('from "../../../db/browser-events"', `from "${browserEventsUrl}"`)
    .replace('from "../../../db/member-balances"', `from "${balancesUrl}"`)
    .replace('from "../../../db/script-sync"', `from "${syncUrl}"`)
    .replace('from "../../../db/tenant"', `from "${tenantUrl}"`)
    .replace('from "../../treasury-access"', `from "${accessUrl}"`);
  const browserRoute = await import(moduleUrl(stripTypeScriptTypes(linkedBrowserRoute, { mode: "transform" })));
  globalThis.__scriptSyncRouteError = new errors.ScriptSyncAccessError(
    "Torn unavailable", "membership_check_unavailable", 503,
  );
  try {
    const response = await browserRoute.POST(new Request("https://treasury.example/api/torn-browser", {
      method: "POST",
      headers: { Authorization: "Bearer bc1.test" },
      body: JSON.stringify({ events: [{
        eventKey: "sync:test",
        eventType: "faction_news",
        category: "news",
        summary: "test",
        sourceUrl: "https://www.torn.com/factions.php",
      }] }),
    }));
    assert.equal(response.status, 503);
    assert.deepEqual(await response.json(), {
      error: "Torn unavailable", code: "membership_check_unavailable", currentFaction: null,
    });
  } finally {
    delete globalThis.__scriptSyncRouteError;
  }
  assert.match(scriptRoute, /return scriptSyncErrorResponse\(error\)/);
});

test("userscript clears faction state for 401 but retains it for retryable 503", async () => {
  const source = await readFile(new URL("../public/blood-coven-treasury.user.js", import.meta.url), "utf8");
  assert.match(source, /if \(status === 401\)[\s\S]*?clearFactionState\(/);
  assert.match(source, /else if \(status === 503\)[\s\S]*?Existing local state was retained/);
  const retryBranch = source.match(/else if \(status === 503\)([\s\S]*?)\n\s*}/)?.[1] ?? "";
  assert.doesNotMatch(retryBranch, /clearFactionState\(/);
});

test("B2 network failures remain retryable membership 503 errors", async () => {
  const { sync } = await modulesPromise;
  await withFetch(async () => { throw new TypeError("network down"); }, async () => {
    await assert.rejects(sync.currentTornIdentity("valid_key_123"), (error) =>
      error instanceof sync.ScriptSyncAccessError
      && error.status === 503
      && error.code === "membership_check_unavailable");
  });
});

test("B2 Torn server failures remain retryable membership 503 errors", async () => {
  const { sync } = await modulesPromise;
  await withFetch(async () => jsonResponse({ error: { code: 17, error: "Backend error" } }, 503), async () => {
    await assert.rejects(sync.currentTornIdentity("valid_key_123"), (error) =>
      error instanceof sync.ScriptSyncAccessError
      && error.status === 503
      && error.code === "membership_check_unavailable");
  });
});

test("B2 an official incorrect-key response requires reconnect instead of transient retry", async () => {
  const { sync } = await modulesPromise;
  await withFetch(async () => jsonResponse({ error: { code: 2, error: "Incorrect Key" } }, 400), async () => {
    await assert.rejects(sync.currentTornIdentity("invalid_key_123"), (error) =>
      error instanceof sync.ScriptSyncAccessError
      && error.status === 401
      && error.code === "membership_revalidation_required");
  });
});

test("B2 malformed local keys still require membership revalidation", async () => {
  const { sync } = await modulesPromise;
  await assert.rejects(sync.currentTornIdentity("bad"), (error) =>
    error instanceof sync.ScriptSyncAccessError
    && error.status === 401
    && error.code === "membership_revalidation_required");
});

test("B2 valid identity and faction preserve the existing script session", async () => {
  const state = await staleTokenDatabase();
  await withFetch(identityFetch(101, BLOOD_COVEN, "Alice Renamed"), async () => {
    const actor = await state.sync.scriptSyncActor(state.request, state.d1);
    assert.equal(actor.memberId, 101);
    assert.equal(actor.memberName, "Alice Renamed");
    assert.equal(actor.factionId, BLOOD_COVEN);
  });
  const row = state.sqlite.prepare("SELECT revoked_at, member_name FROM script_sync_tokens WHERE token_id = ?").get(state.tokenId);
  assert.equal(row.revoked_at, null);
  assert.equal(row.member_name, "Alice Renamed");
  state.sqlite.close();
});

test("B2 changed identity and faction retain existing revoke and signout semantics", async () => {
  for (const scenario of [
    { memberId: 202, factionId: BLOOD_COVEN, code: "identity_changed", currentFaction: { id: BLOOD_COVEN, name: "Blood Coven" } },
    { memberId: 101, factionId: 999999, factionName: "Other", code: "faction_changed", currentFaction: { id: 999999, name: "Other" } },
  ]) {
    const state = await staleTokenDatabase();
    await withFetch(identityFetch(scenario.memberId, scenario.factionId, "Alice", scenario.factionName), async () => {
      await assert.rejects(state.sync.scriptSyncActor(state.request, state.d1), (error) =>
        error instanceof state.sync.ScriptSyncAccessError
        && error.status === 401
        && error.code === scenario.code
        && assert.deepEqual(error.currentFaction, scenario.currentFaction) === undefined);
    });
    const row = state.sqlite.prepare("SELECT revoked_at, revoked_reason FROM script_sync_tokens WHERE token_id = ?").get(state.tokenId);
    assert.ok(row.revoked_at);
    assert.match(row.revoked_reason, scenario.code === "identity_changed" ? /identity changed/ : /faction changed/);
    state.sqlite.close();
  }
});
