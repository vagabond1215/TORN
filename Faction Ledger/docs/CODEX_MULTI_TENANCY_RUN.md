# Codex Run: Multi-Tenant Faction Ledger

## Objective

Evolve the current Blood Coven-specific Faction Ledger into a safely partitioned multi-faction application without losing existing faction `52984` data or weakening the synchronization invariants already implemented in draft PR #1.

Do **not** enable arbitrary-faction writes until the database, APIs, userscript state, dedupe keys, authorization, and tests are all faction-scoped.

## Starting point

- Repository: `vagabond1215/TORN`
- Project: `Faction Ledger/`
- Integration baseline: `agent/fix-faction-ledger-sync-safety`
- Codex working branch: `codex/faction-ledger-multitenancy`
- GitHub task: issue `#2`
- Existing tenant to preserve: Blood Coven, Torn faction ID `52984`
- Production store: Cloudflare D1
- Local store: Miniflare/Wrangler `.wrangler` state only
- Userscript: `public/blood-coven-treasury.user.js` (currently Blood-Coven branded; generalization comes after isolation)

Before editing, make sure the local repo is on the Codex working branch:

```bash
git fetch origin
git switch codex/faction-ledger-multitenancy
git status -sb
cd "Faction Ledger"
npm ci
npm run check
```

Record failures before changing code. Do not hide pre-existing failures by weakening tests.

---

## Target tenancy model

Create a first-class faction/tenant record keyed by Torn faction ID. Tenant context must come from a verified Torn identity/session or authorized treasury relationship, never from an arbitrary client-provided faction ID.

Suggested core shape:

```text
factions
  faction_id PK
  name
  slug/display metadata
  created_at
  updated_at

verified faction/member context
  member_id
  faction_id
  current member_name
  last_verified_at
```

Blood Coven (`52984`) must be seeded/backfilled as the tenant for all existing unscoped rows during migration.

### Canonical member identity

Use Torn `member_id` as durable identity. `member_name` is mutable display metadata.

For old name-only rows:

- backfill member ID from known mappings when unambiguous;
- preserve display name/history;
- do not silently merge ambiguous names;
- report unresolved rows for manual resolution rather than deleting them.

---

## Tables that must be faction-scoped

The repository mixes Drizzle-declared tables and runtime-created D1 tables. Audit both.

### Drizzle/static schema

- `accounts`
- `policies`
- `transactions`
- `pending_wars`
- `active_war`
- `war_member_baselines`
- `torn_browser_events`
- `treasury_leaders`
- `member_balances`
- `member_balance_entries`
- `payout_requests`
- `oc_holdings`
- `armory_items`

### Runtime/sync schema

- `member_balance_observations`
- `armory_snapshot_state`
- `armory_item_effects`
- `torn_sync_cursors`
- `script_sync_tokens`
- every additional `CREATE TABLE IF NOT EXISTS` table found during the audit

### Key/index expectations

Use faction-aware uniqueness:

- `member_balances`: canonical unique/primary identity `(faction_id, member_id)`; member name indexed as metadata
- `member_balance_entries`: `(faction_id, event_key)` unique
- `member_balance_observations`: `(faction_id, event_key)` unique
- `torn_browser_events`: `(faction_id, event_key)` unique
- `armory_items`: `(faction_id, item_name)` unique
- `armory_snapshot_state`: `(faction_id, category)` unique
- `armory_item_effects`: `(faction_id, event_key, item_name)` unique
- `oc_holdings`: `(faction_id, event_key)` unique
- `policies`: `(faction_id, source_key)` unique
- `treasury_leaders`: `(faction_id, email)` unique
- `war_member_baselines`: include `faction_id` in the key
- `torn_sync_cursors`: `(faction_id, source_key)` unique

Global surrogate integer IDs may remain global if convenient, but every tenant-owned query must still filter by `faction_id`.

---

## Implementation phases

### Phase 1 — tenant foundation and safe backfill

1. Add `factions` table and seed Blood Coven `52984`.
2. Add tenant columns to faction-owned tables.
3. Backfill legacy rows to `52984`.
4. Add faction-aware indexes/unique constraints using SQLite-safe rebuilds where primary keys must change.
5. Validate pre/post row counts and financial totals before making tenant IDs mandatory in application writes.

Do not use production reset/recreate as the migration strategy.

### Phase 2 — make Torn member ID canonical

Migrate member balances, requests, history, and other member-facing records to member ID.

Required behavior:

- Torn rename does not create a second balance;
- same member name can exist in two factions without collision;
- requests/history stay attached to the correct Torn member;
- unresolved legacy name-only records are preserved for manual resolution.

### Phase 3 — central tenant context

Add one reusable server-side tenant context helper. Avoid route-specific ad hoc faction checks.

Every route must derive the active faction from verified authorization, then use it in every SQL read/write. Audit at least:

- `/api/member-balance`
- `/api/script-sync`
- `/api/torn-browser`
- `/api/torn`
- treasury/budget/account routes used by `BudgetTracker`
- leader/access-management routes

A request-provided faction selector may select only among already-authorized factions; it must never grant authorization itself.

### Phase 4 — tenant-scope sync and dedupe

Stable Torn observation keys may be the same across factions, but all storage/effects must be namespaced by faction.

Preserve existing guarantees:

- duplicate observers apply one effect inside a faction;
- same event key may independently exist in another faction;
- explicit balance observations beat same-time inferred deltas;
- stale observations cannot overwrite newer canonical state;
- journal pruning cannot undo durable state;
- historical OC rewards do not alter current Armory inventory;
- Armory snapshots are per faction and category;
- Torn history cursors are per faction.

### Phase 5 — userscript tenant-safe state

Generalize the userscript only after server isolation works.

All faction-local GM state must be faction-namespaced or scrubbed before another faction activates:

- observer token
- local revalidation API key
- verified faction identity
- browser-event queue
- Armory/current balance cache
- server balance cache
- last-sync/freshness data
- future faction UI caches

On verified account/faction change:

1. validate membership before upload;
2. stop scanning/uploading previous tenant data;
3. revoke/abandon old session;
4. clear old tenant UI/cache;
5. do not flash old balance while the new tenant initializes;
6. create/select the new tenant only after Torn verification succeeds.

### Phase 6 — faction-scoped treasury authorization

`treasury_leaders` and all administrative access must be scoped to the active faction.

A person may be leader in faction A and ordinary member in faction B. Authorization must follow faction context.

### Phase 7 — observer/corroboration and freshness telemetry

Add safe diagnostics without using observer count in financial arithmetic.

Track/expose where useful:

- faction ID
- stable event key
- first/last observed timestamp
- number of distinct verified observer tokens/member IDs reporting the observation
- last direct push
- last successful membership verification
- queue depth reported by client
- last server balance observation
- last Armory snapshot by category
- war/OC history cursor and completion state

Never expose API keys, bearer secrets, or token hashes.

---

## Isolation tests Codex must add

Use local D1 only. Create two synthetic factions (for example `52984` and `999999`) and prove:

1. Same member name can exist in both factions with different member IDs/balances.
2. Same item name can have different Armory quantities.
3. Same event key produces one effect per faction, never one global collision and never duplicate effects within one faction.
4. Same OC key and policy/source key can coexist across tenants.
5. Treasury leader in faction A cannot read/mutate faction B.
6. Token for faction A cannot submit into faction B by altering payload/query fields.
7. History cursors advance independently.
8. Switching factions clears active client display and never shows stale faction-A data as faction B.
9. Replaying an acknowledged event after journal pruning still cannot double-apply its durable effect.
10. Migrating legacy Blood Coven rows preserves counts/totals.

Retain regression coverage for:

- travelling-member balance propagation;
- duplicate viewers;
- same-timestamp explicit-vs-delta ordering;
- stale snapshot rejection;
- Armory category snapshots;
- historical OC isolation from current inventory;
- old OC/war backfill;
- membership-change revocation;
- temporary Torn outage retains state and retries.

---

## Migration/financial validation

Before and after local migration compare at minimum:

```sql
SELECT COUNT(*) FROM transactions;
SELECT COALESCE(SUM(balance),0) FROM accounts;
SELECT COALESCE(SUM(balance),0), COALESCE(SUM(earned_total),0), COALESCE(SUM(paid_total),0) FROM member_balances;
SELECT COUNT(*) FROM member_balance_entries;
SELECT COUNT(*) FROM oc_holdings;
SELECT COUNT(*) FROM armory_items;
```

All legacy faction-owned rows should resolve to faction `52984` unless a documented exception requires manual resolution.

Add tenant-leakage probes for repository/API reads so tests fail if another synthetic tenant's rows appear.

---

## Suggested commit sequence

1. `Add tenant context and faction schema`
2. `Backfill Blood Coven tenant IDs`
3. `Make member ID canonical for balances`
4. `Tenant-scope treasury and transaction data`
5. `Tenant-scope Torn browser sync and dedupe`
6. `Tenant-scope Armory OC war state and cursors`
7. `Generalize faction session and userscript storage`
8. `Add observer and sync telemetry`
9. `Add multi-tenant migration and isolation tests`
10. `Update docs and remaining faction-specific assumptions`

Keep migration boundaries reviewable; do not squash them away before human review.

---

## Ready-to-use Codex prompt

> Work in `Faction Ledger/` on branch `codex/faction-ledger-multitenancy`, which is based on the prepared integration branch `agent/fix-faction-ledger-sync-safety`. Read `AGENTS.md`, GitHub issue #2, and `docs/CODEX_MULTI_TENANCY_RUN.md` first. Implement the staged multi-tenant refactor described there. Preserve all existing Blood Coven (`faction_id=52984`) data and current sync/idempotency behavior. Do not deploy, merge, connect tests to production D1, or enable arbitrary-faction writes until every durable table/API path is faction-scoped and two-tenant isolation tests pass. Make Torn member ID the canonical member identity. Add local migration/isolation tests. Run `npm run check` and `npm run db:generate` when schema changes require it, and inspect generated SQL. Keep commits reviewable. At the end, update this runbook with the commit range, migration files, commands/results, migration count/financial comparisons, unresolved risks, remaining Blood-Coven assumptions, and whether the branch is ready for human review. Do not claim production validation.

---

## Completion checklist

Mark only after local verification:

- [x] Baseline `npm run check` recorded (one pre-existing stale userscript assertion failed; details below)
- [x] `factions` tenant model added and Blood Coven seeded
- [x] All Drizzle/static tables tenant-audited
- [x] All runtime-created tables tenant-audited
- [x] Existing Blood Coven rows backfilled to `52984`
- [x] Torn member ID canonical for member-facing durable records
- [x] Treasury authorization faction-scoped
- [x] All API reads/writes tenant-scoped
- [x] Dedupe/idempotency keys tenant-scoped
- [x] Armory snapshots/history cursors tenant-scoped
- [x] Userscript state/UI tenant-safe
- [x] Confirmed faction/account switch cannot upload/show old tenant state
- [x] Observer/sync telemetry added
- [x] Two-faction collision/isolation tests pass
- [x] Existing sync regression tests pass
- [x] Generated migrations inspected
- [x] Local migration preserves Blood Coven counts/totals
- [x] Final `npm run check` passes
- [x] No production deploy/merge performed by Codex

## Handoff notes

When finished, append a dated section containing:

- commit range;
- generated migration files;
- commands and exit status;
- manual data-resolution cases;
- remaining Blood-Coven-specific constants/strings;
- production D1 migration blockers;
- rollback notes.

---

## Handoff â€” 2026-08-08

### Commit range and migration artifacts

- Starting commit: `38a9dbabf270447e854716e0c0101c6ceb9593b7`.
- Review range: `38a9dba..codex/faction-ledger-multitenancy` (the branch is intentionally unmerged and undeployed).
- Implementation commits: `e8c650f` (tenant-scoped durable paths and migration) and `b484cf3` (tenant-safe client state and isolation tests). This handoff note is committed separately after those reviewable boundaries.
- Generated and inspected migration: `drizzle/0008_sparkling_scream.sql`.
- Generated Drizzle metadata: `drizzle/meta/0008_snapshot.json` and the `drizzle/meta/_journal.json` entry.
- The generated SQL was not accepted blindly. Drizzle initially referenced columns absent from legacy tables and attempted to create runtime-owned tables that may already exist. The migration body was replaced with explicit SQLite rebuild/backfill statements while retaining the generated schema snapshot.

### Commands and results

- `npm ci` â€” exit 0; 506 packages installed. NPM reported 21 dependency vulnerabilities (1 low, 4 moderate, 16 high); no dependency upgrades were made in this scoped pass.
- Baseline `npm run check` â€” exit 1 after lint and production build passed. The sole failure was the existing rendered-userscript assertion for the obsolete literal `oc_credit`; the current userscript records the underlying balance transition as `member_balance_change`. The assertion was updated to the actual durable event model rather than weakening ingestion coverage.
- `npx tsc --noEmit -p tsconfig.json` â€” exit 0.
- `npm run db:generate` â€” generated `0008_sparkling_scream.sql`; a second run after inspection reported `No schema changes, nothing to migrate`.
- `node --test tests/multitenancy-isolation.test.mjs` â€” exit 0; 3/3 tests passed.
- Final `npm run check` â€” exit 0; lint, production build, rendered HTML/userscript checks, migration preservation, and two-faction isolation all passed (6/6 tests).

### Local migration preservation evidence

The migration test constructs the prepared legacy static/runtime schema, seeds representative Blood Coven data, applies `0008`, and compares before/after values scoped to faction `52984`:

| Measure | Before | After |
| --- | ---: | ---: |
| Transactions | 1 | 1 |
| Account balance total | 1,000 | 1,000 |
| Member balance total | 1,000 | 1,000 |
| Member earned total | 1,200 | 1,200 |
| Member paid total | 200 | 200 |
| Member balance entries | 1 | 1 |
| Organized-crime holdings | 1 | 1 |
| Armory item rows | 1 | 1 |

The test also preserves the seeded pending war, active war, war baseline, payout request, balance observation, treasury leader, Armory snapshot/effect, browser journal event, history cursor, and script token. Every migrated faction-owned row is asserted to have `faction_id=52984`.

The synthetic second-faction tests prove that the two tenants can independently hold the same member name, account name, item name, event key, OC key, war ID, policy key, Armory snapshot category, and history cursor. Duplicate application inside one faction is rejected, distinct observers do not multiply effects, and replay after browser-journal pruning does not reapply the durable Armory effect.

### Canonical identity and manual-resolution cases

- Verified Torn member ID is the canonical lookup/update key. A Torn rename updates display metadata on the same `(faction_id, member_id)` balance instead of creating another balance.
- Legacy name-only balance rows are retained with `resolution_status='unresolved'` until a unique verified faction-member mapping is available.
- If multiple legacy names contain the same non-null member ID, the migration preserves every row but clears that duplicated canonical ID and marks those rows unresolved. It does not silently merge balances or history. Those cases require manual review against current Torn membership.
- Historical entry/request names remain display snapshots; durable request and current-balance lookup use member ID plus faction.

### Remaining Blood-Coven-specific assumptions

- `requireEnabledFaction` intentionally permits only faction `52984`. Arbitrary-faction creation/login/writes remain disabled even though the schema and tests now support isolated synthetic tenants.
- Treasury ChatGPT access currently selects the Blood Coven context; there is no user-facing authorized-faction selector yet.
- Product name, balance-page copy, userscript name/channel/file, notification text, default treasury policy labels, and several Torn DOM/news parsers remain Blood Coven branded.
- The userscript still validates faction `52984` before installing a sync identity. Its queue, token, API key, balance caches, server cache, and scanner position are now namespaced by verified faction/member and the previous scope is scrubbed before switching.
- Existing `system@blood-coven` / `local@blood-coven` attribution values remain historical/system metadata.

### Production D1 blockers and rollback notes

- No production D1 connection, migration, deploy, merge, or arbitrary-faction write was performed. All migration testing used an in-memory local SQLite database.
- Before production use, export/backup D1, capture the actual production `sqlite_master`/`PRAGMA table_info` output for every static and runtime table, and run the migration against a copy of that exact schema/data. The repository's earlier runtime-created tables mean historical environments may not be byte-for-byte identical.
- Re-run the documented production pre/post counts and financial totals on the copied database, including per-table unresolved member-ID reports, before scheduling the real migration.
- `armory_items.observed_at` is reset to `NULL` during the compatibility rebuild because that column was runtime-added and is not guaranteed to exist in every legacy environment. Item names, categories, quantities, source, and update timestamps are preserved. A production preflight can use an environment-specific migration variant if retaining that optional timestamp is required.
- The migration rebuilds primary-key tables. Production rollout needs a maintenance window that prevents concurrent writes between the preflight snapshot and migration completion.
- Rollback is restore-from-D1-backup/export (or a separately reviewed reverse migration). Do not use a destructive reset. Do not run `0008` against production until the schema preflight and backup restore rehearsal succeed.

### Readiness

The branch is ready for human code/migration review and exact-production-copy rehearsal. It is not yet approved for production D1, deployment, merge, or enabling non-Blood-Coven tenants.

---

## Reconciliation handoff — 2026-08-08

### Git reconciliation and cleanup

- Starting local branch: `codex/faction-ledger-multitenancy` at `5f180732ff66639813a0d5d7adb89fa9f3e6ed38`.
- Starting remote branch: `origin/codex/faction-ledger-multitenancy` at the same SHA, `5f180732ff66639813a0d5d7adb89fa9f3e6ed38`.
- Integration base: `origin/agent/fix-faction-ledger-sync-safety` at `38a9dbabf270447e854716e0c0101c6ceb9593b7`. There was no local branch with that name, so comparisons used the authoritative remote-tracking ref.
- `git fetch --all --prune` completed successfully. No pull or fast-forward was required because local and remote Codex refs already matched and the worktree was clean.
- Commit `5f180732ff66639813a0d5d7adb89fa9f3e6ed38` was verified to contain exactly 13 added PNG files under `Blissful Reverie/` and no `Faction Ledger/` changes. Its parent is the complete Faction Ledger handoff commit `d3a7ff5b927b3e98eca30a8124f16273a12799d1`.
- The unrelated commit was removed from the branch contents with a normal, recoverable revert: `fb27cd8` (`Revert "Refactor Faction Ledger for multi-tenant faction isolation"`). No reset, rebase, history rewrite, or force-push was used.
- Final implementation/cleanup SHA before this documentation-only handoff commit: `fb27cd8`. The exact pushed branch-tip SHA is reported in the task handoff after the documentation commit is created and the remote ref is verified.

### Integration diff after cleanup

The merge-base comparison against `origin/agent/fix-faction-ledger-sync-safety` contains only these 21 `Faction Ledger/` paths; no unrelated project files remain:

- `app/BudgetTracker.tsx`
- `app/MemberBalance.tsx`
- `app/api/access/route.ts`
- `app/api/budget/route.ts`
- `app/api/member-balance/route.ts`
- `app/api/script-sync/route.ts`
- `app/api/torn-browser/route.ts`
- `app/api/torn/route.ts`
- `app/treasury-access.ts`
- `db/member-balances.ts`
- `db/schema.ts`
- `db/script-sync.ts`
- `db/tenant.ts`
- `docs/CODEX_MULTI_TENANCY_RUN.md`
- `drizzle/0008_sparkling_scream.sql`
- `drizzle/meta/0008_snapshot.json`
- `drizzle/meta/_journal.json`
- `package.json`
- `public/blood-coven-treasury.user.js`
- `tests/multitenancy-isolation.test.mjs`
- `tests/rendered-html.test.mjs`

### Fresh validation results

- `npm.cmd ci` — exit 0; 506 packages installed. NPM reported 21 dependency vulnerabilities (1 low, 4 moderate, 16 high); dependency upgrades were not introduced during this scoped reconciliation.
- `npm.cmd run check` — exit 0; ESLint passed, the production build completed, and all 6 rendered/migration/isolation tests passed.
- `npx.cmd tsc --noEmit -p tsconfig.json` — exit 0.
- `node --test tests\\multitenancy-isolation.test.mjs` — exit 0; 3/3 tests passed.
- `npm.cmd run db:generate` — exit 0 and reported `No schema changes, nothing to migrate`; no follow-up migration or metadata changes were generated.
- `git diff --check` — exit 0.

### Audit and migration evidence

- Reviewed every changed durable query/runtime table in the access, budget, member-balance, script-sync, Torn browser, Torn API, treasury access, balance, tenant, schema, and userscript paths. Reads, writes, conflict targets, cursor keys, event keys, Armory keys, authorization, and replay guards are faction-scoped to verified context.
- Verified that client-supplied faction overrides are rejected and that product writes remain gated by `requireEnabledFaction` to Blood Coven faction `52984`.
- Reviewed `drizzle/0008_sparkling_scream.sql`, `drizzle/meta/0008_snapshot.json`, and `drizzle/meta/_journal.json`. The snapshot contains the expected 22 tables and the journal has a single ordered `0008_sparkling_scream` entry.
- The local migration test again preserved the seeded legacy counts and totals: 1 transaction; 1,000 account balance; 1,000 member balance; 1,200 earned; 200 paid; 1 balance entry; 1 OC holding; and 1 Armory item. All other seeded tenant-owned rows also remained assigned to faction `52984`.
- The synthetic isolation test again proved independent coexistence for identical member names, item names, event keys, OC keys, war IDs, policy keys, Armory categories, and history cursor keys, while duplicate observers and replay after journal pruning did not duplicate durable effects.
- No implementation defect was found during reconciliation, so no production code or migration behavior was changed beyond the unrelated-asset revert and this appended evidence.

### Remaining risks and product boundary

- Legacy name-only member rows remain `unresolved`; duplicated or ambiguous legacy member IDs/names require manual review and are not guessed or merged.
- `armory_items.observed_at` intentionally migrates as `NULL` for compatibility with historical runtime schemas that may not contain the column. Inventory names, categories, quantities, source, and update timestamps remain preserved.
- Product authorization and userscript identity remain intentionally Blood-Coven-only (`52984`); arbitrary-faction production creation, login, selection, and writes are still disabled.
- Before production D1 work: export/backup D1, inspect the exact production `sqlite_master` and `PRAGMA table_info` state, rehearse `0008` against a copy, compare pre/post counts and financial totals, review unresolved member mappings, and rehearse backup restoration. Concurrent writes require a maintenance window.
- Rollback remains restore from the verified D1 backup/export or use of a separately reviewed reverse migration. Do not use a destructive reset.
- This reconciliation did not connect to production D1, run Wrangler migration/deploy commands, deploy the application, merge a branch/PR, enable arbitrary-faction writes, or touch `main`.

---

## Balance atomicity handoff — 2026-08-08 23:13:11 -04:00

### Git state and scope

- Starting branch/SHA: `codex/faction-ledger-multitenancy` at `9183452362285d87b6efcd529b58de60fbee4c5e`.
- Local and `origin/codex/faction-ledger-multitenancy` matched, the worktree was clean, and no pull or fast-forward was required.
- Implementation commit: `357b1ff` (`Make balance event application atomic and retry-safe`).
- Regression/preflight commit: `9bff35e` (`Add balance failure-recovery regression tests`).
- Final implementation/test SHA before this documentation-only commit: `9bff35e746f45c3f6f319e29d9da2ff247643e36`. The exact pushed branch-tip SHA is reported in the task handoff after this documentation commit is created and verified remotely.

Changed paths in this targeted run:

- `app/api/budget/route.ts`
- `app/api/torn-browser/route.ts`
- `db/member-balances.ts`
- `db/schema.ts`
- `docs/CODEX_MULTI_TENANCY_RUN.md`
- `drizzle/0009_lyrical_morlocks.sql`
- `drizzle/meta/0009_snapshot.json`
- `drizzle/meta/_journal.json`
- `drizzle/preflight/0008_tenant_conflicts.sql`
- `package.json`
- `tests/member-balance-atomicity.test.mjs`
- `tests/multitenancy-isolation.test.mjs`

### Atomic and retry-safe design

- New inserts into faction-scoped `member_balance_entries` and `member_balance_observations` now invoke faction-aware SQLite/D1 `AFTER INSERT` triggers. The trigger adopts one unambiguous unresolved row or upserts the canonical `(faction_id, member_id)` row, then applies current balance, observation priority, and lifetime earned/paid totals inside the same database transaction as the unique event marker.
- A duplicate `(faction_id, event_key)` insert changes no row, so the `AFTER INSERT` trigger does not run and cannot double-apply the effect.
- If identity adoption, canonical-row creation, or balance/totals mutation fails, SQLite aborts the outer marker insert and rolls back every trigger-side change. The marker is therefore not permanently consumed and the same event can be retried safely.
- Ambiguous name-only legacy rows raise an atomic error before effect application; the marker rolls back and the rows remain unresolved for manual review. Verified Torn member ID remains canonical and member names remain mutable metadata.
- `explicit_balance` was added to `member_balance_entries` so an explicit credit observation can carry priority 2 through the database trigger. Inferred deltas remain priority 1. The trigger applies current-balance changes only when the timestamp is newer, or when an equal timestamp has equal/higher priority; unique stale credits/payouts still increment lifetime totals exactly once.
- Browser journal duplicates now retry their derived idempotent imports. This makes the bounded `torn_browser_events` journal transport-only: a previous derived-effect failure can recover even when the journal row already exists.
- Ranked-war account allocation, treasury transaction, member credit markers, and pending-war status now execute in one D1 batch. A failed member credit trigger rolls back the whole war settlement instead of leaving a recorded war with a partial payout ledger.
- Torn-browser payout requests are marked paid only when `recordBalanceEvent` reports a genuinely new inserted/applied payout marker; duplicate events continue to return `false`.

### Behavioral regression evidence

`tests/member-balance-atomicity.test.mjs` installs migration `0009` into local in-memory SQLite and forces trigger-side canonical updates to fail with `RAISE(ABORT)`. It then retries the same durable key:

| Scenario | Failed attempt | Final successful/repeated retry state |
| --- | --- | --- |
| Credit 25 from balance/earned 100 | marker 0; balance 100; earned 100 | marker 1; balance 125; earned 125 |
| Payout 30 from balance 100 | marker 0; balance 100; paid 0 | marker 1; balance 70; paid 30 |
| Explicit observation 100 → 175 | marker 0; balance 100 | marker 1; balance 175; priority 2 |
| Duplicate observers, credit 15 | second insert ignored | marker 1; balance/earned 115 |
| Same key in factions 52984/999999 | independent inserts | balances 110/220; two markers |
| Same timestamp, inferred +10 and explicit 175 | tested in both arrival orders | balance 175; earned 110; priority 2 |
| Newer explicit 200 then stale credit 25 | stale current effect rejected | balance 200; earned 125 |
| Newly seen member, distinct credits 10/20 | tested in both serial arrival orders | one canonical row; balance/earned 30; two markers |

The test also proves ambiguous unresolved names abort without consuming a marker. True simultaneous network-request scheduling is not reproduced by Node's synchronous in-memory SQLite driver; the database uniqueness/trigger transaction is exercised in both serial orders, but local Miniflare/D1 concurrency remains a pre-production rehearsal item.

### Schema, migration, and preflight

- Added generated migration `drizzle/0009_lyrical_morlocks.sql`, then manually inspected and extended it with the two required triggers. It is additive: one nullable `member_balance_entries.explicit_balance` column plus `apply_member_balance_entry` and `apply_member_balance_observation` triggers. Historical `0008` was not rewritten.
- Added generated snapshot `drizzle/meta/0009_snapshot.json` and journal entry. A second `npm.cmd run db:generate` reported `No schema changes, nothing to migrate`.
- Existing migration tests now apply both `0008` and `0009`; legacy Blood Coven counts and financial totals remain unchanged because trigger creation does not replay historical markers.
- Added read-only local preflight `drizzle/preflight/0008_tenant_conflicts.sql`. It reports duplicate legacy account names that would conflict with `accounts_faction_name_unique` and duplicate non-null member IDs that require canonical-identity review. It never deletes or merges rows.

### Fresh commands and results

- `npm.cmd ci` — exit 0; 506 packages installed. NPM again reported 21 dependency vulnerabilities (1 low, 4 moderate, 16 high); dependency upgrades were outside this integrity fix.
- `npm.cmd run check` — exit 0; lint/build passed and 16/16 tests passed.
- `npx.cmd tsc --noEmit -p tsconfig.json` — exit 0.
- `node --test tests\\multitenancy-isolation.test.mjs` — exit 0; 3/3 tests passed.
- `node --test tests\\member-balance-atomicity.test.mjs` — exit 0; 10/10 tests passed.
- `npm.cmd run db:generate` — exit 0; no further schema changes after `0009`.
- `git diff --check` — exit 0.

### Remaining production blockers and safety

- Before any production D1 migration: export/backup D1; inspect actual `sqlite_master` and `PRAGMA table_info` for every static/runtime table; run the read-only unique-key preflight; rehearse `0008` and `0009` against an exact production copy; compare row counts and financial totals; review unresolved member identities; exercise concurrent ingestion through local Miniflare; rehearse restore; and schedule a maintenance window.
- Rollback remains restoration from a verified D1 export/backup or a separately reviewed reverse migration. Do not use a destructive reset.
- This run did not contact production D1, run remote Wrangler/D1 commands, deploy, merge PR #3 or PR #1, mark PR #3 ready, enable arbitrary-faction writes, rewrite reviewed history, or touch `main`.
