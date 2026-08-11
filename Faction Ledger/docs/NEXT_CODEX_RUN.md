# Next Codex Run: Armory Durable-Replay Authority

**Status: COMPLETED**

This is the authoritative current Codex task for `Faction Ledger/`.

Faction Ledger is pre-production and not in active service. Work directly on `main` under the development-mode policy in [`../AGENTS.md`](../AGENTS.md).

The prior Armory same-time/timestamp-safety run completed at implementation SHA `5d155ce7fb66ff9475811768650e89a6b90da2e8` with documentation SHA `41fd50a43fdbe97d2730c3c9d4572626f56eb19b`. That run added migration `0012_exotic_tarot.sql`, durable snapshot-base JSON, deterministic `(occurred_at, event_key, item_name)` rematerialization for snapshot-backed categories, and the five-minute future-time bound. Its full validation evidence is preserved in [`CODEX_MULTI_TENANCY_RUN.md`](./CODEX_MULTI_TENANCY_RUN.md).

Do not rewrite or broaden that completed work except as required by the focused replay-integrity regression below.

## Read order

1. [`../AGENTS.md`](../AGENTS.md)
2. [`README.md`](./README.md)
3. **This file**
4. [`CODEX_MULTI_TENANCY_RUN.md`](./CODEX_MULTI_TENANCY_RUN.md)
5. GitHub issue #2 and relevant merged PR/review history if GitHub access is available

## Start on `main`

```bash
git fetch origin
git switch main
git pull --ff-only origin main
git status -sb
git rev-parse HEAD
git rev-parse origin/main
```

Local and remote `main` must match before editing. If the worktree is dirty or local `main` diverged, stop and inspect rather than resetting, rebasing, or force-pushing automatically.

## Safety boundary

Direct-to-`main` development is allowed only because the application is still pre-production. Do not deploy, contact production D1, run remote Wrangler/D1 migrations, enable arbitrary-faction production writes, force-push, rewrite shared history, discard unrelated user-owned work, or weaken tests.

Use local/in-memory/Miniflare data only.

---

# Blocker — duplicate Armory replay can use non-canonical request metadata

## Confirmed current behavior

`POST /api/torn-browser` intentionally re-runs all derived importers for journal duplicates so downstream durable idempotency can recover from earlier importer failures.

For Armory movements this means a duplicate browser event calls `recordArmoryMovement()` again.

`recordArmoryMovement()` currently executes one D1 batch containing:

1. `INSERT OR IGNORE` into `armory_item_effects`; then
2. an Armory rematerialization query.

The rematerialization query uses the **current request's normalized `category` and `itemName` parameters** to choose the snapshot base and durable effect set.

If the insert is a duplicate, the durable event row is correctly left unchanged — but the second statement still runs.

Therefore the already-accepted durable event is not fully authoritative over replay behavior.

This matters because userscript Armory event identity is based on the stable event type plus `hash("armory|<summary>")`, while `payload.category` is observer/page-state metadata. Multiple observers or manual scans can therefore submit the same `eventKey` with different category metadata without changing the event identity.

A stale or differently classified duplicate must not be able to rematerialize current inventory using a category that was never accepted into the durable event row.

## Required invariant

Once `(faction_id, event_key, item_name)` exists in `armory_item_effects`, that durable row is the canonical accepted movement.

A replay of the same durable identity may be used to verify/self-heal materialization, but **request-time replay metadata must not be able to change which category, delta, occurrence time, or source is authoritative**.

Duplicate observer submissions must be semantically inert unless they deterministically rebuild state from the already-stored durable event set.

## Required fix

Choose the smallest design that makes replay authority explicit.

Preferred direction:

- derive rematerialization scope from the durable `armory_item_effects` row that owns `(faction_id, event_key, item_name)`, not from the replay payload; or
- make rematerialization conditional on a genuinely new accepted insert if duplicate self-healing is not needed.

Because the event insert and rematerialization already run in one database batch, do not reintroduce a marker-then-effect partial-write window.

If duplicate replays continue to trigger rematerialization, they must do so using canonical persisted metadata.

Do not solve this with an in-memory lock or by trusting the first/last observer's request payload outside the durable row.

Preserve:

- exact-once key `(faction_id, event_key, item_name)`;
- deterministic equal-time ordering from migration `0012`;
- zero-floor convergence;
- delayed-snapshot convergence;
- snapshot-base `items_json` semantics;
- legacy `NULL items_json` / `NULL occurred_at` preservation;
- faction/category isolation;
- OC-history isolation;
- five-minute future-time rejection;
- script-sync 401/503 behavior;
- Blood Coven `52984` data.

## Required behavioral regressions

Add database-level tests that exercise the real `recordArmoryMovement()` path.

### R1 — duplicate payload category cannot steer canonical state

Create authoritative snapshot bases for at least two categories and durable history that makes choosing the wrong category observably different.

Accept an Armory movement with:

- faction `52984`;
- stable event key `movement:replay-authority`;
- a specific item;
- canonical category A.

Then replay the same `(faction_id, event_key, item_name)` with category B.

Assert:

- `armory_item_effects` still contains exactly one durable row;
- the durable row's original category/delta/occurred time remain unchanged;
- current `armory_items` remains the result of canonical category A history;
- the replay cannot resurrect or rematerialize category B history over the current item.

### R2 — journal-style duplicate replay remains exact-once

Replay the same event with its original metadata multiple times.

Assert effect count stays one and quantity does not multiply.

### R3 — changed duplicate amount/action cannot alter accepted effect

Replay the same durable identity with a different quantity/action.

Assert the stored delta remains authoritative and materialized quantity does not change to match the replay request.

### R4 — equal-time convergence remains intact

Re-run the existing opposing equal-time movement cases in both arrival orders and prove the result remains deterministic through the zero floor.

### R5 — delayed snapshot equivalence remains intact

The same durable effect set must still produce identical materialization through the live and delayed-snapshot paths.

### R6 — cross-faction isolation

The same event key remains independently valid in factions `52984` and `999999`; a duplicate replay in one faction cannot rematerialize the other.

## Secondary audit — new unknown-time movements

Review the behavior of a **new** movement whose normalized `occurredAt` is `NULL` after a snapshot base exists.

Historical migrated `NULL occurred_at` rows must remain preserved without inventing timestamps.

For new ingestion, make sure the behavior is deliberate and covered: do not silently claim a movement was canonically applied if it is durably accepted but intentionally excluded from snapshot-backed materialization. If the existing userscript/API contract guarantees a timestamp, a focused rejection/validation regression is preferable to inventing an occurrence time.

Do not broaden this into historical timestamp backfill.

---

# Schema / migration expectation

This replay-authority fix should not normally require a schema change because the canonical metadata already exists in `armory_item_effects`.

If no schema change is required:

```bash
npm.cmd run db:generate
```

must report no schema drift and **no new migration should be created**.

If you discover a genuine schema requirement, explain it before generating an additive migration after `0012_exotic_tarot.sql`; do not rewrite migrations `0008` through `0012`.

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

Run any new replay-authority test file directly as well.

Do not weaken existing tests to obtain green output.

Before push:

```bash
git fetch origin
git status -sb
git log --oneline --decorate -12
git diff --check
```

If `origin/main` moved during the run, reconcile safely before pushing. Fast-forward when possible; if both sides contain new commits, stop and inspect rather than force-pushing.

---

# Documentation / handback

Before marking this file COMPLETED:

1. append the design and actual validation evidence to `CODEX_MULTI_TENANCY_RUN.md`;
2. append a dated completion result here;
3. record starting/final `main` SHAs and exact commits;
4. state whether schema changed and whether `db:generate` produced anything;
5. explain why a duplicate replay cannot use request metadata to steer canonical Armory state;
6. record the new regression results, including mismatched-category replay;
7. record the result of the new-`NULL occurredAt` audit;
8. confirm no production D1 contact, deployment, remote migration, force-push, or arbitrary-faction enablement;
9. push validated normal commits directly to `main`.

Do not call this run complete while duplicate replay payload metadata can influence materialization after the durable event identity has already been accepted.

---

## Completion result - 2026-08-11

- Started from clean, synchronized `main` at `e04729ef26d344d3b1eb1e2ebb13b6cf87d68522`.
- Final tested implementation SHA before this documentation-only commit: `c13d9f9d8bb59fcedddbe68cfed292299626a51f` (`Make Armory replay use durable metadata`). The documentation commit and final pushed `main` tip are reported in the task handoff.
- `recordArmoryMovement()` still inserts the exact-once durable effect and rematerializes in one atomic D1 batch. Its rebuild now begins by selecting the owning `(faction_id, event_key, item_name)` row and derives item name, category, source, deltas, and occurrence ordering from persisted effects. Replay-supplied category, amount, action, or occurrence time cannot select a different snapshot/effect history or overwrite accepted metadata.
- No schema changed. `npm.cmd run db:generate` reported `No schema changes, nothing to migrate`; no migration or Drizzle metadata was created or modified.
- New replay regressions prove mismatched category metadata cannot replace canonical `drugs / 9` with unrelated `medical / 105` history; exact duplicate replays remain one effect; changed duplicate amount/action/time cannot alter the stored delta; and the same event key remains independent across factions `52984` and `999999`. Existing equal-time zero-floor and delayed-snapshot equivalence cases remain green.
- New normalized `NULL occurredAt` movements are deliberately rejected before browser-journal insertion and again in `recordArmoryMovement()` before the atomic batch. The userscript contract always supplies an occurrence time (using parsed Torn time or its existing current-time fallback). Historical migrated `NULL occurred_at` rows remain preserved and are neither rejected retroactively nor assigned invented timestamps.
- Validation: `npm.cmd ci` exit 0 (506 packages); baseline and final `npm.cmd run check` exit 0, with final aggregate 57/57; TypeScript exit 0; multitenancy 3/3; member-balance atomicity 16/16; member-balance schema ownership 4/4; Armory ordering/replay 23/23; script-sync semantics 8/8; `db:generate` no drift; `git diff --check` exit 0.
- Blood Coven faction `52984`, exact-once effects, deterministic equal-time ordering, zero-floor convergence, delayed snapshots, snapshot-base JSON, legacy null preservation, faction/category isolation, OC isolation, five-minute future rejection, and script-sync 401/503 behavior remain intact.
- No production D1 connection, deployment, remote Wrangler/D1 migration, force-push, shared-history rewrite, or arbitrary-faction enablement occurred. Production remains gated on backup/export, exact-schema inspection, exact-copy migration/concurrency/restore rehearsal, count/financial/Armory comparison, unresolved-identity review, and a maintenance window.
