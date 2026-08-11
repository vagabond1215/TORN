# Next Codex Run: Final Main Reconciliation, Armory Same-Time Convergence, and Timestamp Safety

**Status: ACTIVE**

This is the authoritative current Codex task for `Faction Ledger/`.

This run has two purposes:

1. finish the narrow Armory same-time/timestamp-safety blockers found after the completed `0011` pass; and
2. perform the **one-time branch reconciliation needed to retire the long-lived Codex/integration branch workflow**.

Faction Ledger is pre-production and not in active service. After PR #3 is reviewed and merged into `main`, future Codex development should start from and push directly to `main` until a human explicitly declares the application actively used and restores branch/PR protection.

The prior Armory delayed-snapshot and script-sync error pass completed at implementation/test SHA `4e2f3512d01afafbe378e8bd42585016db5f155e` with documentation tip `a9e386f677db707a6ae92e096b07b090ca670757`. Its full evidence is preserved in [`CODEX_MULTI_TENANCY_RUN.md`](./CODEX_MULTI_TENANCY_RUN.md) and PR #3.

Do not rerun or rewrite completed work unless required by the focused regressions below.

## Read order

1. [`../AGENTS.md`](../AGENTS.md)
2. [`README.md`](./README.md)
3. **This file**
4. [`CODEX_MULTI_TENANCY_RUN.md`](./CODEX_MULTI_TENANCY_RUN.md)
5. GitHub issue #2 and the latest reviews/comments on PR #3

## Repository / transition state

- Repository: `vagabond1215/TORN`
- Project: `Faction Ledger/`
- **Temporary working branch for this final bridge run:** `codex/faction-ledger-multitenancy`
- **PR #3 target:** `main`
- Historical integration branch `agent/fix-faction-ledger-sync-safety` / PR #1 is superseded and is no longer the target.
- Last connector-reviewed implementation tip before direct-main policy staging: `a9e386f677db707a6ae92e096b07b090ca670757`
- Production tenant to preserve: Blood Coven, faction `52984`

Treat live Git refs as authoritative. Do not reset to the SHA above.

After PR #3 is eventually merged, **do not recreate this branch stack for ordinary pre-production work**. Start subsequent Codex runs with current `main`.

## Safety boundary

During this transition run:

- do not merge PR #3 from Codex; hand it back after validation for connector/human review and the one-time merge;
- do not deploy;
- do not contact production D1;
- do not run remote Wrangler/D1 migrations;
- do not enable arbitrary-faction writes;
- do not force-push or rewrite reviewed history;
- do not discard unrelated user-owned work.

Use local/in-memory/Miniflare data only.

Direct-to-`main` development after the bridge merge changes **branch policy only**. It does not relax any production-data or deployment safety rule.

---

# Pass 0 — reconcile current `main` into the final bridge branch

PR #3 now targets `main` directly, but the long-lived branch has diverged from current `main` and GitHub currently reports it as not mergeable until reconciliation.

Before implementing the Armory follow-up:

```bash
git fetch --all --prune
git switch codex/faction-ledger-multitenancy
git status -sb
git log --graph --decorate --oneline -12
git rev-parse HEAD
git rev-parse origin/codex/faction-ledger-multitenancy
git rev-parse origin/main
```

If the worktree is not clean or local/remote Codex history has unexpectedly diverged, stop and report it. Do not reset, rebase, or force-push automatically.

Then merge current `main` into the Codex branch with a **normal history-preserving merge**, not a rebase:

```bash
git merge --no-ff origin/main
```

If conflicts occur:

- inspect every conflict; do not blindly choose `ours` or `theirs` across the tree;
- for unrelated non-`Faction Ledger/` repository work, preserve the current `main` state unless doing so would discard distinct user-owned work that is not already represented elsewhere;
- the Growth Contest workbook/path is unrelated to Faction Ledger and current `main` is authoritative for its present repository state;
- for `Faction Ledger/` conflicts, preserve the accumulated tenant/sync/atomicity/Armory implementation while incorporating any legitimate newer `main` edits semantically;
- do not delete or rewrite unrelated user-owned files merely to make the merge clean.

After the merge, verify:

```bash
git diff --name-status origin/main...HEAD
git diff --check
```

The PR-to-main diff should contain only intended Faction Ledger development changes. If unrelated paths remain, clean them up with normal commits before handback.

Record the pre-merge and post-merge SHAs in the completion report.

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

This violates the existing invariant:

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

`cleanEvent()` normalizes a client-supplied `occurredAt` and can also prefer `payload.endedAt`. `importArmorySnapshot()` rejects snapshots more than five minutes in the future, but `importArmoryMovement()` currently forwards movement timestamps without the same future bound.

Because movement `occurred_at` now controls whether an effect survives and is replayed across later snapshots, an accidentally or deliberately far-future movement can remain "later than" authoritative snapshots for an extended period and repeatedly participate in rebuilds.

## Required fix

For Armory movements, reject or safely ignore impossible future occurrence times using the same general tolerance already used for snapshots (currently five minutes), unless there is a documented Torn-specific reason for a different bound.

Do not rewrite an invalid/future occurrence time to `now`; that would fabricate ordering evidence.

Preserve legitimate historical movement timestamps.

Also ensure a generic payload field irrelevant to Armory movement cannot silently override the movement timestamp into the future without validation.

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

Do not expand credential classification without a concrete reason and regression coverage.

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

After the `main` reconciliation and implementation, from `Faction Ledger/` run:

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
git fetch origin
git diff --name-status origin/main...HEAD
git log --graph --decorate --oneline -15
git status -sb
```

PR #3 must contain only intended Faction Ledger development changes relative to current `main`.

---

# Documentation / handback

Before marking this file COMPLETED:

1. append the final design and actual validation evidence to `CODEX_MULTI_TENANCY_RUN.md`;
2. append a dated completion result to this file;
3. record starting SHA, pre/post `origin/main` reconciliation SHAs, final SHA, exact commits, migration generated if any, command exit statuses, and remaining production blockers;
4. explicitly state the deterministic ordering rule for equal-time movements;
5. explicitly state the future-time validation rule;
6. confirm the final PR-to-main diff contains only intended Faction Ledger changes;
7. confirm no production D1 contact/deploy/force-push/arbitrary-faction enablement;
8. push normally to `codex/faction-ledger-multitenancy` and hand PR #3 back for connector/human review and the one-time merge to `main`.

Do **not** merge PR #3 from Codex during this run.

After PR #3 is merged, the repository policy changes to:

```text
main  ← normal Codex working branch during pre-production development
```

Future Codex sessions should fetch `main`, `git pull --ff-only origin main`, work directly there, validate, commit normally, and push to `main` unless a human explicitly changes the policy.

When the application is declared actively used, direct-to-`main` development must stop and branch/PR/CI protection must be restored before further production-affecting work.

Do not call this run complete unless identical durable Armory events produce the same current inventory regardless of observer/network arrival order, including equal timestamps and zero-floor cases, future movement timestamps are safely bounded, and the branch is reconciled cleanly with current `main`.