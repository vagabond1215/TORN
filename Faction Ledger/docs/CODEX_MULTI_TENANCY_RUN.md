# Codex Run: Multi-Tenant Faction Ledger

## Objective

Evolve the current Blood Coven-specific Faction Ledger into a safely partitioned multi-faction application without losing existing faction `52984` data or weakening the synchronization invariants already implemented in draft PR #1.

Do **not** enable arbitrary-faction writes until the database, APIs, userscript state, dedupe keys, authorization, and tests are all faction-scoped.

## Starting point

- Repository: `vagabond1215/TORN`
- Project: `Faction Ledger/`
- Integration branch: `agent/fix-faction-ledger-sync-safety`
- Existing tenant to preserve: Blood Coven, Torn faction ID `52984`
- Production store: Cloudflare D1
- Local store: Miniflare/Wrangler `.wrangler` state only
- Userscript: `public/blood-coven-treasury.user.js` (currently Blood-Coven branded; generalization comes after isolation)

Before editing:

```bash
cd "Faction Ledger"
npm ci
npm run lint
npm test
```

Record failures before changing code. Do not hide pre-existing failures by weakening tests.

---

## Target tenancy model

Create a first-class faction/tenant record keyed by Torn faction ID. The authenticated tenant context must come from a verified Torn identity/session or an authorized treasury-leader relationship, not from an arbitrary request body/query parameter.

Suggested core shape:

```text
factions
  faction_id PK
  name
  slug/display metadata
  created_at
  updated_at

faction member/session context
  Torn member_id
  faction_id
  current verified member_name
  last_verified_at
```

Blood Coven (`52984`) must be seeded/backfilled as the tenant for all existing unscoped rows during migration.

### Canonical member identity

Use Torn `member_id` as durable identity. `member_name` is mutable display metadata.

Where old rows only contain a name:

- backfill member ID from existing known mappings when unambiguous;
- retain the display name;
- do not silently merge two ambiguous names;
- record/report rows requiring manual resolution rather than deleting them.

---

## Tables that must be faction-scoped

The repository currently mixes Drizzle-declared tables and runtime-created D1 tables. Audit both. At minimum, tenant-scope the following.

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
- any other `CREATE TABLE IF NOT EXISTS` table discovered during the audit

### Key/index expectations

Use faction-aware uniqueness, for example:

- `member_balances`: unique/primary identity on `(faction_id, member_id)`; name indexed as metadata
- `member_balance_entries`: `(faction_id, event_key)` unique
- `member_balance_observations`: `(faction_id, event_key)` unique
- `torn_browser_events`: `(faction_id, event_key)` unique
- `armory_items`: `(faction_id, item_name)` unique
- `armory_snapshot_state`: `(faction_id, category)` unique
- `armory_item_effects`: `(faction_id, event_key, item_name)` unique
- `oc_holdings`: `(faction_id, event_key)` unique
- `policies`: `(faction_id, source_key)` unique
- `treasury_leaders`: `(faction_id, email)` unique
- `war_member_baselines`: include `faction_id` in the key even where Torn war IDs appear globally unique
- `torn_sync_cursors`: `(faction_id, source_key)` unique

Global surrogate integer IDs may remain global if convenient, but every query still must filter by `faction_id`.

---

## Migration strategy

Do not rely on a production reset.

### Phase 1 — additive tenant columns

1. Add a `factions` table and seed Blood Coven `52984`.
2. Add nullable/defaultable `faction_id` columns to existing faction-owned tables.
3. Backfill all existing rows to `52984`.
4. Add faction-aware indexes/unique constraints using SQLite-safe table rebuilds where required.
5. Only after validation make tenant columns effectively required in application writes.

For tables whose old primary key must change (for example name/event/item keys), use explicit SQLite migration/rebuild steps. Preserve data and compare pre/post row counts and financial totals.

### Phase 2 — member ID migration

Migrate balance/account-facing member lookups to Torn member ID.

Required behavior:

- rename does not create a second balance;
- two factions can contain members with the same name without collision;
- requests/history remain attached to the correct Torn member ID;
- old name-only rows are preserved until resolved.

### Phase 3 — API tenant context

Introduce one reusable server helper for tenant context rather than duplicating faction checks.

Every route must derive the active faction from verified authorization, then use that faction in every SQL statement. Audit at least:

- `/api/member-balance`
- `/api/script-sync`
- `/api/torn-browser`
- `/api/torn`
- treasury/budget/account routes used by `BudgetTracker`
- leader/access-management routes

A request-provided `factionId` may select among factions the user is already authorized for, but must never grant access itself.

### Phase 4 — synchronization/dedupe tenancy

Stable observation keys are reusable across factions only when namespaced by `faction_id` at storage/processing time.

Preserve these existing rules:

- duplicate users observing the same event apply one effect;
- explicit balance observations beat same-time inferred deltas;
- old observations cannot overwrite newer state;
- event-journal pruning cannot undo durable state;
- old OC rewards do not mutate current Armory inventory;
- authoritative Armory snapshots are per faction **and** category;
- Torn historical cursors are per faction.

### Phase 5 — client storage and switching

Generalize the userscript only after server isolation works.

All faction-local GM storage must be either:

1. keyed/namespaced by faction ID, or
2. fully scrubbed before another faction is activated.

This includes:

- observer token
- local revalidation API key
- verified faction identity
- browser-event queue
- Armory/current balance cache
- server balance cache
- last-sync/freshness data
- any future UI cache

On verified faction/account change:

- stop scanning before upload;
- revoke/abandon previous token;
- clear previous tenant state from active UI;
- do not display old tenant balance while new tenant initializes;
- create/select the new tenant only after Torn verification succeeds.

### Phase 6 — treasury authorization

Move treasury leader membership from global email authorization to faction-scoped authorization.

A person may be a leader in faction A and an ordinary member in faction B. Authorization checks must reflect the active faction.

### Phase 7 — observer/corroboration telemetry

Add durable/aggregated diagnostics without making observer count part of financial arithmetic.

Useful fields/outputs:

- faction ID
- stable event key
- first/last observed time
- number of distinct verified observer tokens/member IDs that reported it
- last direct push
- last successful membership verification
- queue depth reported by the client
- last server balance observation
- last Armory category snapshot per category
- history cursor/complete state for wars and OCs

Do not expose API keys or raw observer secrets in telemetry.

---

## Isolation tests Codex must add

Use local D1 only. Create two synthetic factions (for example `52984` and `999999`) and prove all of the following:

1. Same member name can exist in both factions with different Torn member IDs/balances.
2. Same item name can have different quantities in both Armories.
3. Same event key submitted to both factions produces one effect **per faction**, not one global effect and not two effects inside one faction.
4. Same OC key and policy/source key can coexist across tenants.
5. Treasury leader in faction A cannot read or mutate faction B.
6. Member/session token for faction A cannot submit observations into faction B by modifying payload fields.
7. History cursors advance independently.
8. Switching from faction A to faction B clears/changes the active client display and never flashes A's stale balance as B's.
9. Replaying an acknowledged event after `torn_browser_events` pruning still cannot double-apply the durable effect.
10. Migrating existing Blood Coven rows preserves row counts and totals.

Also retain regression tests for:

- travelling-member balance propagation;
- duplicate viewers;
- same-timestamp explicit-vs-delta ordering;
- stale snapshot rejection;
- Armory category snapshots;
- historical OC isolation from current inventory;
- old OC/war backfill;
- membership change revocation;
- Torn API outage retains state and retries.

---

## Financial/migration validation

Before and after local migration, capture and compare at minimum:

```sql
SELECT COUNT(*) FROM transactions;
SELECT COALESCE(SUM(balance),0) FROM accounts;
SELECT COALESCE(SUM(balance),0), COALESCE(SUM(earned_total),0), COALESCE(SUM(paid_total),0) FROM member_balances;
SELECT COUNT(*) FROM member_balance_entries;
SELECT COUNT(*) FROM oc_holdings;
SELECT COUNT(*) FROM armory_items;
```

After backfill, all legacy faction-owned rows should resolve to faction `52984` unless intentionally documented otherwise.

Add tenant leakage probes: for every repository function/route that loads tenant-owned data, tests should fail if removing the faction predicate would allow the second synthetic tenant's rows to appear.

---

## Recommended implementation commits

Keep commits reviewable. Suggested sequence:

1. `Add tenant context and faction schema`
2. `Backfill Blood Coven tenant IDs`
3. `Make member ID canonical for balances`
4. `Tenant-scope treasury and transaction data`
5. `Tenant-scope Torn browser sync and dedupe`
6. `Tenant-scope Armory OC war state and cursors`
7. `Generalize faction session and userscript storage`
8. `Add observer and sync telemetry`
9. `Add multi-tenant migration and isolation tests`
10. `Update docs and remove Blood-Coven-only assumptions where appropriate`

Do not squash away useful migration boundaries until review is complete.

---

## Codex prompt

Use this verbatim or nearly verbatim for the local Codex run:

> Work in `Faction Ledger/` on branch `agent/fix-faction-ledger-sync-safety`. Read `AGENTS.md` and `docs/CODEX_MULTI_TENANCY_RUN.md` first. Implement the multi-tenant refactor in the staged order described there. Preserve all existing Blood Coven (`faction_id=52984`) data and current sync/idempotency behavior. Do not deploy, merge, connect tests to production D1, or enable arbitrary-faction writes until every durable table/API path is faction-scoped and two-tenant isolation tests pass. Make Torn member ID the canonical member identity. Add local migration/isolation tests, run `npm run lint`, `npm test`, and `npm run db:generate` when schema changes require it. Inspect generated SQL. At the end, summarize changed files, migration behavior, tests/results, unresolved risks, and whether the branch is safe for human review. Update this runbook's completion checklist rather than claiming production validation.

---

## Completion checklist

Codex should mark these only after actually verifying them locally.

- [ ] Baseline `npm run lint` recorded/passing
- [ ] Baseline `npm test` recorded/passing
- [ ] `factions` tenant model added and Blood Coven seeded
- [ ] All static schema tables tenant-audited
- [ ] All runtime-created tables tenant-audited
- [ ] Existing Blood Coven rows backfilled to `52984`
- [ ] Torn member ID is canonical for balances/member-facing records
- [ ] Treasury authorization faction-scoped
- [ ] All API reads/writes tenant-scoped
- [ ] Dedupe/idempotency keys tenant-scoped
- [ ] Armory snapshots/cursors tenant-scoped
- [ ] Userscript storage and active UI tenant-safe
- [ ] Confirmed faction/account change scrubs previous active state
- [ ] Observer/sync telemetry added or explicitly deferred with reason
- [ ] Two-faction collision/isolation tests pass
- [ ] Existing sync regression tests pass
- [ ] Generated migrations inspected
- [ ] Local migration preserves Blood Coven counts/totals
- [ ] `npm run lint` passes after changes
- [ ] `npm test` passes after changes
- [ ] No production deploy/merge performed by Codex

## Handoff notes

When finished, append a short dated section here containing:

- commit range;
- migration files generated;
- commands run and exit status;
- any manual data-resolution cases;
- remaining Blood-Coven-specific constants/strings;
- blockers before production D1 migration;
- rollback notes.