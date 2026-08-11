# Next Codex Run: Armory Same-Time Convergence and Timestamp Safety

**Status: ACTIVE**

This is the authoritative current Codex task for `Faction Ledger/`. The prior Armory delayed-snapshot and script-sync error pass completed at implementation/test SHA `4e2f3512d01afafbe378e8bd42585016db5f155e` with documentation tip `a9e386f677db707a6ae92e096b07b090ca670757`. Its full evidence is preserved in [`CODEX_MULTI_TENANCY_RUN.md`](./CODEX_MULTI_TENANCY_RUN.md) and PR #3.

Do not rerun or rewrite completed work unless required by the focused regressions below.

## Read order

1. [`../AGENTS.md`](../AGENTS.md)
2. [`README.md`](./README.md)
3. **This file**
4. [`CODEX_MULTI_TENANCY_RUN.md`](./CODEX_MULTI_TENANCY_RUN.md)
5. GitHub issue #2 and the latest reviews/comments on draft PR #3

## Repository / branch

- Repository: `vagabond1215/TORN`
- Project: `Faction Ledger/`
- Working branch: `codex/faction-ledger-multitenancy`
- Integration branch: `agent/fix-faction-ledger-sync-safety`
- Draft PR: #3
- Last connector-reviewed implementation tip before this handoff: `a9e386f677db707a6ae92e096b07b090ca670757`
- Production tenant to preserve: Blood Coven, faction `52984`

Treat live Git refs as authoritative. Do not reset to the SHA above.

## Safety boundary

Do not merge PR #3 or PR #1, mark PR #3 ready, deploy, contact production D1, run remote Wrangler/D1 migrations, enable arbitrary-faction writes, force-push, rewrite reviewed history, or discard unrelated user-owned work.

Use local/in-memory/Miniflare data only.

---

# Blocker A — same-timestamp Armory movements are still arrival-order dependent

The completed pass fixed delayed snapshots by adding `armory_item_effects.occurred_at`, a temporal movement trigger, and deterministic folding after a snapshot.

However, `apply_armory_item_effect` still applies newly inserted movements incrementally in **database arrival order** whenever `occurred_at` is later than the current snapshot.

The delayed-snapshot fold instead orders durable effects by:

`occurred_at`, then `event_key`.

These are not equivalent when two movements share the same Torn timestamp and the quantity floor at zero is reached.

The userscript parses Armory news timestamps only to whole seconds (`HH:MM:SS DD/MM/YY`), so distinct legitimate movements can share the same `occurred_at`.

Example from a snapshot base of quantity `1`, with both movements at the exact same timestamp:

- event `movement:a`: use/withdraw `2`
- event `movement:b`: deposit/return `2`

Arrival order A then B:

`1 -> 0 -> 2`

Arrival order B then A:

`1 -> 3 -> 1`

The same durable event set therefore materializes as either `2` or `1` depending on network/observer arrival order.

This violates the existing invariant in the previous handoff:

> canonical current Armory state must be equivalent to applying authoritative snapshots and idempotent movements in observation-time order, regardless of network/observer arrival order.

## Required fix

Make movement materialization deterministic for equal timestamps as well as different timestamps.

Use a stable total ordering such as:

1. `occurred_at`
2. `event_key`
3. `item_name` only if still needed as a final deterministic tie

The canonical quantity produced from a snapshot base plus the durable post-snapshot movement set must be independent of ingestion order.

Do not rely on insertion order.

A robust design may require recomputing the affected item/category from an authoritative snapshot base plus all later durable effects whenever a new movement is accepted, rather than incrementing the current materialized row blindly. If the current schema does not preserve enough snapshot-base information to do that safely, add the smallest durable schema needed and generate an additive migration.

Do not use the prunable `torn_browser_events` journal as the only source for authoritative snapshot base state.

Preserve:

- `(faction_id, event_key, item_name)` exact-once dedupe;
- category isolation;
- faction isolation;
- OC-history isolation;
- existing delayed-snapshot behavior;
- historical `NULL occurred_at` semantics without inventing timestamps.

## Required regressions

Add behavioral database tests proving at least:

### A1 — equal-time opposing movements converge

Start from snapshot quantity `1` at `t1`.

At the same timestamp `t2`, create two distinct durable events:

- withdrawal/use `2`
- deposit/return `2`

Run once with arrival order withdrawal -> deposit.
Run again from the same initial state with arrival order deposit -> withdrawal.

Final canonical quantity must be identical in both runs and match the documented deterministic tie ordering.

### A2 — same-time duplicate observer replay

The same two movement event keys observed/replayed by multiple clients must not multiply effects.

### A3 — same-time cross-faction isolation

The same event keys/timestamps must remain independently valid in factions `52984` and `999999`.

### A4 — delayed snapshot plus equal-time later effects

Prove a delayed snapshot followed by folding the same equal-time effect set produces the exact same final quantity as the normal live-ingestion path in either arrival order.

### A5 — no-zero-crossing sanity

Equal-time movements whose running quantity never reaches zero must still converge to the arithmetic total and must not be accidentally double-applied.

---

# Blocker B — movement timestamps need future-time sanity bounds

`cleanEvent()` normalizes a client-supplied `occurredAt` (and can also prefer `payload.endedAt`). `importArmorySnapshot()` rejects snapshots more than five minutes in the future, but `importArmoryMovement()` currently forwards movement timestamps without the same future bound.

Because movement `occurred_at` now controls whether an effect survives and is replayed across later snapshots, an accidentally or deliberately far-future movement can remain "later than" authoritative snapshots for an extended period and repeatedly participate in rebuilds.

## Required fix

For Armory movements, reject or safely ignore impossible future occurrence times using the same general tolerance already used for snapshots (currently five minutes), unless there is a documented Torn-specific reason for a different bound.

Do not rewrite an invalid/future occurrence time to `now`; that would fabricate ordering evidence.

Preserve legitimate historical movement timestamps.

Also ensure a generic payload field that is irrelevant to Armory movement cannot silently override the movement timestamp into the future without validation.

## Required regressions

- movement timestamp within tolerance is accepted;
- movement timestamp beyond tolerance is rejected/ignored without changing `armory_item_effects` or `armory_items`;
- a far-future `payload.endedAt` cannot poison an Armory movement's temporal order;
- valid historical movements remain accepted.

---

# Re-check completed script-sync work

Do not broaden this run into another sync refactor. Run the existing sync-error suite and confirm the prior behavior remains intact:

- retryable Torn/network/5xx failures => structured 503, local state retained;
- clear key errors 1/2/16/18 and malformed/missing keys => structured 401/revalidation;
- identity/faction changes retain revoke/sign-out semantics.

The current key-code mapping matches Torn's published API error definitions for 1, 2, 16, and 18; do not expand credential classification without a concrete reason and regression coverage.

---

# Schema / migration rules

If the same-time convergence fix needs new durable snapshot-base state or ordering fields:

- update `db/schema.ts`;
- run `npm.cmd run db:generate`;
- create a new additive migration after `0011_thin_pyro.sql`;
- inspect generated SQL manually;
- do not rewrite migrations `0008` through `0011`;
- keep runtime bootstrap and formal migration schemas convergent;
- existing production-shaped databases must fail clearly rather than self-mutating migration-owned columns at request time.

Preserve Blood Coven `52984` rows and current quantities during migration tests.

---

# Validation

From `Faction Ledger/` run:

```bash
npm.cmd ci
npm.cmd run check
npx.cmd tsc --noEmit -p tsconfig.json
node --test tests\multitenancy-isolation.test.mjs
node --test tests\member-balance-atomicity.test.mjs
node --test tests\member-balance-schema-ownership.test.mjs
node --test tests\armory-ordering.test.mjs
node --test tests\script-sync-errors.test.mjs
npm.cmd run db:generate
git diff --check
```

Run any new focused Armory tie-order/timestamp test directly as well.

Do not weaken tests to obtain green output.

Before handback verify:

```bash
git diff --name-status origin/agent/fix-faction-ledger-sync-safety...HEAD
```

PR #3 must contain only intended `Faction Ledger/` changes.

---

# Documentation / handback

Before marking this file COMPLETED:

1. append the final design and actual validation evidence to `CODEX_MULTI_TENANCY_RUN.md`;
2. append a dated completion result to this file;
3. record starting SHA, final SHA, exact commits, migration generated if any, command exit statuses, and remaining production blockers;
4. explicitly state the deterministic ordering rule for equal-time movements;
5. explicitly state the future-time validation rule;
6. confirm no production D1 contact/deploy/merge/force-push/arbitrary-faction enablement;
7. keep PR #3 draft and push normally.

Do not call this run complete unless identical durable Armory events produce the same current inventory regardless of observer/network arrival order, including equal timestamps and zero-floor cases.