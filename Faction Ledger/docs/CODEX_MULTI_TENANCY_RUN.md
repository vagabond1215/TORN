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

- [ ] Baseline `npm run check` recorded/passing
- [ ] `factions` tenant model added and Blood Coven seeded
- [ ] All Drizzle/static tables tenant-audited
- [ ] All runtime-created tables tenant-audited
- [ ] Existing Blood Coven rows backfilled to `52984`
- [ ] Torn member ID canonical for member-facing durable records
- [ ] Treasury authorization faction-scoped
- [ ] All API reads/writes tenant-scoped
- [ ] Dedupe/idempotency keys tenant-scoped
- [ ] Armory snapshots/history cursors tenant-scoped
- [ ] Userscript state/UI tenant-safe
- [ ] Confirmed faction/account switch cannot upload/show old tenant state
- [ ] Observer/sync telemetry added or explicitly deferred with reason
- [ ] Two-faction collision/isolation tests pass
- [ ] Existing sync regression tests pass
- [ ] Generated migrations inspected
- [ ] Local migration preserves Blood Coven counts/totals
- [ ] Final `npm run check` passes
- [ ] No production deploy/merge performed by Codex

## Handoff notes

When finished, append a dated section containing:

- commit range;
- generated migration files;
- commands and exit status;
- manual data-resolution cases;
- remaining Blood-Coven-specific constants/strings;
- production D1 migration blockers;
- rollback notes.