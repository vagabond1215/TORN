# Next Codex Run: Armory Temporal Ordering and Sync Error Semantics

**Status: ACTIVE**

This is the authoritative current Codex task for `Faction Ledger/`. The previous payout-settlement and migration-ownership run is complete and its evidence is preserved in [`CODEX_MULTI_TENANCY_RUN.md`](./CODEX_MULTI_TENANCY_RUN.md). Do not rerun that completed scope unless a regression requires it.

## Read order

Before editing, read these in order:

1. [`../AGENTS.md`](../AGENTS.md) — subtree safety rules and non-negotiable data/sync invariants.
2. [`README.md`](./README.md) — documentation routing and instruction precedence.
3. **This file** — current actionable scope and acceptance criteria.
4. [`CODEX_MULTI_TENANCY_RUN.md`](./CODEX_MULTI_TENANCY_RUN.md) — architecture, completed migrations, and historical validation evidence.
5. GitHub issue **#2** and the latest reviews/comments on draft PR **#3**, if GitHub access is available.

If older documentation conflicts with this ACTIVE handoff, use this file for current scope while preserving every safety/data-integrity rule in `AGENTS.md`.

## Repository and branch

- Repository: `vagabond1215/TORN`
- Project: `Faction Ledger/`
- Working branch: `codex/faction-ledger-multitenancy`
- Integration branch: `agent/fix-faction-ledger-sync-safety`
- Draft PR: **#3**, Codex branch → integration branch
- Existing production tenant to preserve: Blood Coven, Torn faction ID `52984`
- Last connector-reviewed implementation head: `e66d9cb8665e3cf8629bdd8b6e907eae723ef41b`
- A later unrelated commit `af20b35207cd84a333d32ca29efb205e604c4e54` (`consolidation`) renamed `AUG2026 Growth Contest.xlsx` into `Growth comp/`. That binary workbook is user-owned and unrelated to Faction Ledger.

Treat live Git refs as authoritative. The SHAs above are context, not permission to reset or rewrite history.

## Safety boundary

Do not:

- merge PR #3 or PR #1;
- mark PR #3 ready for review unless explicitly asked after another review pass;
- deploy;
- connect to production D1;
- run remote Wrangler/D1 migrations;
- enable arbitrary-faction production writes;
- force-push, reset reviewed history, or discard user-owned work;
- weaken tests to obtain green output;
- delete or alter the Growth Contest workbook contents as part of this task.

Use only local/in-memory/Miniflare data for validation.

---

# Pass 0 — restore PR branch scope safely

The current Codex branch contains one unrelated workbook rename from commit `af20b35`.

Before handback, the Codex → integration PR must again contain only `Faction Ledger/` changes.

Use a history-preserving approach. Prefer a normal revert of the unrelated consolidation commit or an equivalent normal commit that restores the workbook path to the integration-branch state. Do not force-push or rewrite reviewed history.

The workbook contents must be preserved exactly. If the consolidation move is desired as separate repository work, leave it recoverable from Git history or move it to a separate branch/PR outside this Faction Ledger task.

Verify with:

```bash
git diff --name-status origin/agent/fix-faction-ledger-sync-safety...HEAD
```

No path outside `Faction Ledger/` may remain in PR #3 at handback.

---

# Blocker A — Armory snapshots can erase later movements

## Confirmed current behavior

`app/api/torn-browser/route.ts` stores Armory movements in `armory_item_effects` and immediately adjusts `armory_items` through `apply_armory_item_effect`.

However:

- `armory_item_effects` does not persist the Torn observation/event timestamp;
- the movement trigger does not advance an item/category observation timestamp;
- `importArmorySnapshot()` accepts/rejects a snapshot only against the previous `armory_snapshot_state.observed_at`;
- an accepted snapshot deletes the current category rows and replaces them with snapshot quantities.

Therefore this valid arrival order can lose a real movement:

```text
snapshot S1 observed at t1: Xanax = 10
movement M observed at t3: use 1 Xanax => current = 9
snapshot S2 observed at t2 arrives after M
S2 is newer than S1, so it is accepted
category is replaced with S2 value 10
movement M is erased even though t3 > t2
```

Multiple verified observers and queued delivery make this an ordinary out-of-order ingestion case, not merely theoretical clock skew.

## Required invariant

For each faction/category/item, canonical current Armory state must be equivalent to applying authoritative snapshots and idempotent movements in **observation-time order**, regardless of network/observer arrival order.

A delayed snapshot must never erase a later movement.

Duplicate movement event keys must still apply once per faction.

Historical OC rewards must remain isolated from current Armory state.

## Recommended design direction

Persist movement observation time durably, probably by adding an `occurred_at`/`observed_at` field to `armory_item_effects` through a new additive migration.

Then make snapshot application temporally convergent. A robust approach is:

1. treat the snapshot at time `S` as the authoritative base for that category at `S`;
2. rebuild/materialize the category from that snapshot;
3. replay or fold all durable Armory movement effects for that faction/category whose observation time is **after S**;
4. leave later effects idempotent by the existing faction-scoped event key;
5. ensure items absent from the older snapshot but introduced by later deposits/returns are not lost;
6. ensure later withdrawals/uses remain reflected;
7. preserve category normalization rules.

An equivalent design is acceptable if behavioral tests prove arrival-order independence. Do not solve this only with in-memory locks or by assuming queues arrive chronologically.

Be explicit about events whose historical `armory_item_effects` rows predate the new timestamp column. Do not invent precise historical timestamps. Preserve them and document the migration semantics.

## Required Armory regressions

Add behavioral DB tests for at least:

### A1 — chronological baseline

- snapshot at t1: item quantity 10
- snapshot at t2: quantity 10
- movement at t3: -1
- final quantity 9

### A2 — delayed snapshot arrival

Apply in arrival order:

- snapshot t1 quantity 10
- movement t3 -1
- snapshot t2 quantity 10

Final quantity must still be **9**.

### A3 — later deposit survives delayed snapshot

- snapshot t1: item absent/0
- deposit at t3: +2
- delayed snapshot t2: item absent/0

Final quantity must be **2**.

### A4 — duplicate movement remains exact-once

Same `(faction_id, event_key, item_name)` submitted twice changes quantity once.

### A5 — cross-faction identical movement key

The same event/item key in factions `52984` and `999999` applies independently.

### A6 — category isolation

A delayed snapshot for one category cannot rewrite another category.

### A7 — snapshot replay

Replaying the same snapshot event cannot multiply later movement effects.

### A8 — historical OC isolation

Existing OC history behavior still cannot inflate current Armory inventory.

---

# Blocker B — script-sync error semantics are inconsistent

## B1 — `/api/torn-browser` collapses all script errors to 401

`app/api/script-sync/route.ts` correctly serializes a `ScriptSyncAccessError` using:

- `error.status`;
- `error.code`;
- `error.currentFaction`.

But `app/api/torn-browser/route.ts` currently maps **every** `ScriptSyncAccessError` to HTTP `401` and returns only the message.

This is incorrect for retryable membership verification errors such as:

```text
code = membership_check_unavailable
status = 503
```

The userscript intentionally handles the statuses differently:

- `401` => clear faction-local token/key/queue/cache and sign out;
- `503` => retain local state and retry automatically.

A Torn outage occurring during POST revalidation can therefore be misreported as 401 and scrub valid local state.

### Required fix

Make `/api/torn-browser` preserve the same structured semantics as `/api/script-sync`:

```json
{
  "error": "...",
  "code": "membership_check_unavailable",
  "currentFaction": null
}
```

with `status: error.status`.

Do not collapse retryable errors to 401.

### Required tests

- mocked/constructed `ScriptSyncAccessError(..., "membership_check_unavailable", 503)` through browser POST returns 503 with code preserved;
- identity/faction/session failures still return their intended 401 code/current faction;
- userscript source/regression coverage continues to prove 401 clears local state and 503 retains it.

## B2 — invalid/revoked Torn API keys are treated like transient outages

`db/script-sync.ts::tornFetch()` currently converts any non-success Torn API response/error payload into:

```text
membership_check_unavailable / 503
```

That means an unmistakably invalid/revoked API key can be retained and retried forever as though Torn were temporarily unavailable.

### Required classification

Distinguish permanent credential/revalidation failures from transient availability failures.

At minimum:

- malformed/missing local key remains `membership_revalidation_required`;
- unmistakable invalid/revoked/unauthorized credential responses should require reconnect/revalidation and should not be labeled transient 503;
- network failures, timeouts, Torn 5xx/service failures, and genuinely ambiguous temporary API failures remain `membership_check_unavailable` / 503;
- do not revoke a valid script token merely because Torn is temporarily unavailable;
- do not guess on ambiguous Torn errors. Preserve retryable behavior unless the response clearly establishes a credential problem.

If exact Torn API error codes are needed, verify them against the official Torn API documentation during the Codex run rather than inventing numeric mappings.

### Required tests

Mock `fetch`/membership verification for at least:

- network failure => 503 `membership_check_unavailable`;
- Torn server 5xx => 503;
- clear invalid/unauthorized API-key response => reconnect/revalidation error, not transient 503;
- valid identity/faction => existing success path;
- changed identity/faction => existing revoke/signout semantics remain intact.

---

# Blocker C — finish migration ownership for Armory schema evolution

`ensureSchema()` in `app/api/torn-browser/route.ts` still does request-time:

```sql
ALTER TABLE armory_items ADD COLUMN observed_at TEXT
```

when the column is missing.

Migration `0008_sparkling_scream.sql` already formally creates/rebuilds the tenant-scoped `armory_items` table with `observed_at`.

Follow the migration-ownership rule already established for member-balance schema:

- a genuinely fresh disposable database may bootstrap the current complete table shape;
- an existing production-shaped table missing a formal migration-owned column should fail clearly before request-time schema mutation;
- do not silently mutate an old production database merely because a route was hit before its migration;
- if Blocker A adds another Armory column/trigger/table upgrade, put it in a new additive migration and make runtime/formal schema converge.

Add a behavioral schema-ownership test analogous to `member-balance-schema-ownership.test.mjs`:

1. fresh runtime bootstrap contains the latest Armory shape;
2. an existing pre-migration Armory table fails without being altered;
3. formally migrated DB starts without runtime schema drift;
4. formal trigger/schema definitions match fresh-runtime definitions where both own the same objects.

---

# Preserve completed invariants

Do not regress any previously completed work:

- faction isolation;
- Torn member ID canonical identity;
- payout request settlement atomicity and replay safety;
- balance event/observation exact-once triggers;
- explicit-vs-delta timestamp priority;
- journal pruning independence;
- OC history isolation;
- war/OC cursor isolation;
- tenant-safe userscript storage;
- production Blood Coven-only enablement gate;
- migration sequence `0008 → 0009 → 0010` and Blood Coven preservation.

Any new migration must append after `0010`; do not rewrite reviewed historical migrations unless a human explicitly approves that strategy.

---

# Validation

From `Faction Ledger/`, run at minimum:

```bash
npm ci
npm run check
npx tsc --noEmit -p tsconfig.json
node --test tests/multitenancy-isolation.test.mjs
node --test tests/member-balance-atomicity.test.mjs
node --test tests/member-balance-schema-ownership.test.mjs
```

Run every new targeted Armory/sync-error test directly as well.

If schema changes:

```bash
npm run db:generate
```

Inspect generated SQL and metadata manually. Run `npm run db:generate` a second time after final schema edits and verify there is no unexpected drift.

Finally:

```bash
git diff --check
git status -sb
git diff --name-status origin/agent/fix-faction-ledger-sync-safety...HEAD
```

The final PR diff must contain only `Faction Ledger/` paths.

---

# Suggested commit boundaries

Keep reviewable commits. A reasonable sequence is:

1. `Make Armory snapshot and movement ordering convergent`
2. `Preserve script sync error status and classify key failures`
3. `Make Armory schema evolution migration-owned`
4. `Add Armory ordering and sync error regressions`
5. `Document follow-up validation and rollout risks`

If the workbook cleanup requires a commit, keep it separate and obvious, for example:

`Revert unrelated Growth Contest consolidation from tenancy branch`

Do not squash reviewed tenancy history.

---

# Handback requirements

Before marking this file COMPLETED, append a dated result section here and a concise historical note to `CODEX_MULTI_TENANCY_RUN.md` containing:

- starting and final SHA;
- whether the unrelated workbook rename was removed from PR #3 without losing the file;
- implementation commits;
- schema/migration files generated;
- exact Armory ordering design;
- error-classification behavior;
- exact commands and exit statuses;
- behavioral final-state evidence for A1–A8 and B1/B2 tests;
- migration ownership evidence;
- remaining production blockers;
- confirmation that production D1 was not contacted;
- confirmation that nothing was deployed or merged.

Keep PR #3 draft and push normally. Do not force-push.

Do not call this run complete unless delayed Armory snapshots provably cannot erase later movements, transient membership failures remain retryable end-to-end, clear invalid-key failures are distinguished from outages, and the PR diff is restored to `Faction Ledger/` only.