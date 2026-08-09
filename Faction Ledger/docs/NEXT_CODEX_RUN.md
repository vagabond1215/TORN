# Next Codex Run: Payout Settlement Atomicity and Migration Ownership

**Status: COMPLETED**

This is the authoritative current Codex task for `Faction Ledger/`. The broader tenancy design and historical handoff evidence remain in [`CODEX_MULTI_TENANCY_RUN.md`](./CODEX_MULTI_TENANCY_RUN.md), but when this file is marked **ACTIVE**, execute this file's scope before returning to broader roadmap work.

## Read order

Before editing, read these in order:

1. [`../AGENTS.md`](../AGENTS.md) — subtree safety rules and non-negotiable data/sync invariants.
2. [`README.md`](./README.md) — documentation routing and which file is authoritative for the current run.
3. **This file** — current actionable task and acceptance criteria.
4. [`CODEX_MULTI_TENANCY_RUN.md`](./CODEX_MULTI_TENANCY_RUN.md) — architecture, migration history, completed phases, and prior validation evidence.
5. GitHub issue **#2** and the latest reviews/comments on draft PR **#3**, if GitHub access is available.

If an older prompt in `CODEX_MULTI_TENANCY_RUN.md` conflicts with this file, use this file for the current implementation scope while preserving every safety/integrity rule from `AGENTS.md` and the runbook.

## Repository and branch

- Repository: `vagabond1215/TORN`
- Project: `Faction Ledger/`
- Working branch: `codex/faction-ledger-multitenancy`
- Integration branch: `agent/fix-faction-ledger-sync-safety`
- Draft PR: **#3**, Codex branch → integration branch
- Existing production tenant to preserve: Blood Coven, Torn faction ID `52984`
- Last reviewed implementation head before this documentation handoff: `500948d124c33b9d99e90dc0054411c427cada27`

Treat the live Git refs as authoritative. The SHA above is context, not permission to reset history.

## Safety boundary

Do not:

- merge PR #3 or PR #1;
- mark PR #3 ready for review unless explicitly asked by a human after follow-up review;
- deploy the application;
- connect to production D1;
- run remote Wrangler/D1 migrations;
- enable arbitrary-faction production writes;
- force-push, rebase away reviewed history, or reset away user work;
- weaken existing tests to obtain a green run.

Use only local/in-memory/Miniflare data for validation.

---

# Current blockers

The previous run fixed the original partial-write window between durable balance event markers and canonical balance/totals by applying effects through faction-aware `AFTER INSERT` triggers. That design and its regression tests must remain intact.

Two follow-up defects remain.

## Blocker A — payout request settlement is not atomic with the payout event

Current browser payout processing effectively does:

```text
insert unique payout balance event
    ↓
AFTER INSERT trigger applies balance / paid_total
    ↓
recordBalanceEvent() returns true
    ↓
separate UPDATE payout_requests SET status = 'paid'
```

This leaves a new partial-write window:

```text
payout marker + balance effect commit
    ↓
payout_requests UPDATE fails
    ↓
client retries the same Torn event
    ↓
event marker is now a duplicate
    ↓
recordBalanceEvent() returns false
    ↓
request may remain pending forever
```

It is **not safe** to simply perform the request update on every duplicate replay: after a successful payout, a later replay of the old event could accidentally mark a newer payout request paid.

The current request lookup also uses `member_name`. Torn member ID is now the canonical durable identity, so a member rename can update the correct running balance while failing to settle that member's existing payout request.

### Required outcome

A newly accepted Torn payout event and the specific payout-request settlement it represents must be one recoverable exact-once database effect.

Required properties:

1. The payout event marker, current balance/`paid_total` mutation, and request status transition commit or roll back together.
2. A duplicate `(faction_id, event_key)` cannot settle another request.
3. Retrying after a forced failure can settle the original request correctly once.
4. Request matching uses canonical `(faction_id, member_id)` whenever an ID is resolved. `member_name` is display metadata, not authorization/identity.
5. A Torn rename cannot prevent the correct request from being settled.
6. If no matching open request existed when the event was first durably accepted, replaying that old event later must **not** settle a newly created request.
7. Cross-faction identical member names/event keys remain isolated.

### Preferred design

Use a durable event-to-request association that is chosen inside the same database transaction that inserts the new payout event. A strong design is:

- add nullable `payout_request_id` to `member_balance_entries`;
- for payout entries with a resolved member ID, populate `payout_request_id` from a scalar subquery in the event `INSERT`, selecting the oldest eligible request for the same `faction_id` + `member_id` under the existing amount/status rules;
- extend the `apply_member_balance_entry` `AFTER INSERT` trigger so a **new** payout marker updates only `NEW.payout_request_id`;
- keep that update in the same outer SQLite/D1 transaction as the marker and canonical balance mutation;
- duplicates do not fire the trigger, so they cannot settle a later request.

The exact SQL may differ if you can prove an equivalent design has the same atomic, canonical-ID, and replay-safety properties.

Do **not** implement a check-then-update flow that leaves the selected request ID only in application memory. Do not use name-only request matching when `member_id` is available.

### Preserve current payout semantics

The current code chooses the oldest request in `pending`/`approved` state whose requested amount is no greater than the observed Torn payout amount. Preserve that policy unless a test or product requirement demonstrates it is wrong.

If the payout event has no resolved member ID, it may still update an unresolved balance/event ledger if existing rules allow it, but it must not guess which durable payout request belongs to that name.

---

## Blocker B — runtime schema repair can pre-consume formal migration 0009+

`ensureMemberBalanceSchema()` currently checks for `member_balance_entries.explicit_balance` and may execute a runtime:

```sql
ALTER TABLE member_balance_entries ADD COLUMN explicit_balance INTEGER;
```

It also creates balance triggers at runtime.

Formal migration `drizzle/0009_lyrical_morlocks.sql` unconditionally adds that column and creates those triggers. This creates an unsafe deployment-order dependency:

```text
database is at 0008
    ↓
new application code runs first
    ↓
runtime helper adds 0009 column/trigger state
    ↓
operator later applies formal 0009
    ↓
duplicate-column / duplicate-trigger migration failure
```

### Required outcome

Migration-owned evolution of an **existing** database must not be silently performed by request-time schema helpers.

Required properties:

1. Fresh/disposable database bootstrap may create the latest complete table shape.
2. If an already-existing `member_balance_entries` table lacks a column required by the current code, fail clearly with a migration-required error instead of altering the table at request time.
3. Do not silently add `explicit_balance`, `payout_request_id`, or future migration-owned columns to an existing table.
4. Only create runtime triggers after confirming the required columns exist.
5. A database fully migrated through the latest migration must start normally without duplicate migration work.
6. A database intentionally held at 0008 must not be mutated into a half-0009 state simply because an API route was called.

### Trigger upgrade requirement

If this run changes `apply_member_balance_entry`, remember that `CREATE TRIGGER IF NOT EXISTS` does **not** replace an existing 0009 trigger definition.

A follow-up migration must explicitly replace the old trigger when necessary, for example with a reviewed sequence equivalent to:

```sql
DROP TRIGGER IF EXISTS apply_member_balance_entry;
CREATE TRIGGER apply_member_balance_entry ...latest definition...;
```

Do not rewrite historical migration `0009` just to hide the upgrade. Generate/review an additive follow-up migration unless there is a compelling, documented reason otherwise.

---

# Implementation guidance

## Start by reconciling Git

From repository root:

```bash
git fetch --all --prune
git status -sb
git branch -vv
git switch codex/faction-ledger-multitenancy
git status -sb
git rev-parse HEAD
git rev-parse origin/codex/faction-ledger-multitenancy
git rev-parse origin/agent/fix-faction-ledger-sync-safety
```

If the worktree is clean and local is only behind origin, use `git pull --ff-only`.

If local/remote diverged or unrelated uncommitted work exists, stop and report it. Do not rebase/reset/force-push automatically.

## Files to inspect first

At minimum inspect:

- `app/api/torn-browser/route.ts`
- `db/member-balances.ts`
- `db/schema.ts`
- `drizzle/0009_lyrical_morlocks.sql`
- `drizzle/meta/0009_snapshot.json`
- `drizzle/meta/_journal.json`
- `tests/member-balance-atomicity.test.mjs`
- `tests/multitenancy-isolation.test.mjs`

Also inspect every caller of:

- `recordBalanceEvent`
- `prepareBalanceEventInsert`
- `recordBalanceObservation`
- `recordExplicitBalance`

Do not assume the browser route is the only payout-event producer.

## Schema/migration expectations

A schema change for durable payout association will likely require a migration after `0009`.

If schema changes:

```bash
npm run db:generate
```

Then manually inspect the generated migration and Drizzle metadata.

Expected migration responsibilities if using the preferred design:

- add nullable `member_balance_entries.payout_request_id`;
- replace `apply_member_balance_entry` with the new exact-request settlement logic;
- preserve `apply_member_balance_observation` unless its definition genuinely needs to change;
- do not replay historical balance events merely because the trigger is replaced;
- do not retroactively mark arbitrary historical payout requests paid;
- remain additive/reviewable after migrations `0008` and `0009`.

If Drizzle generation does not represent trigger SQL, extend the generated migration deliberately and document that manual portion, as was done for `0009`.

---

# Required regression tests

Add behavioral database tests. Source-code regex checks may supplement them but are not sufficient for the transactional invariants.

## 1. Payout event + request commit together

Seed:

- faction `52984`;
- member ID `101`;
- current balance `100`;
- pending payout request ID `R1` for member `101`, amount `30`.

Process one Torn payout event for `30`.

Assert:

- one event marker exists;
- marker records `R1` if using `payout_request_id`;
- balance is `70`;
- `paid_total` increased by exactly `30`;
- `R1` is `paid`.

Repeat the same event and assert nothing changes again.

## 2. Forced request-settlement failure rolls back the whole payout event

Install a test-only trigger or equivalent failure injection that aborts the payout-request status update.

First attempt must fail.

After failure assert:

- payout event marker count is `0`;
- balance and `paid_total` are unchanged;
- request remains pending/approved.

Disable failure and retry the same event.

Assert marker/balance/paid_total/request all reach the correct final state exactly once.

## 3. Rename safety

Seed request with:

- member ID `101`;
- historical display name `Old Name`.

Submit the payout event with verified/resolved member ID `101` and display name `New Name`.

Assert the request is settled by member ID despite the name change.

## 4. Old replay cannot settle a new request

Process event `payout:E1` successfully and settle request `R1`.

Then create new request `R2` for the same member.

Replay `payout:E1`.

Assert:

- `R2` remains open;
- no totals/balances change;
- event-to-request association still points only to `R1`.

## 5. Event with no request cannot settle a future request

Process a unique payout event when no eligible request exists.

Then create a request for the same member and replay the old event.

Assert the newly created request remains open.

## 6. Cross-faction isolation

Use the same display name and event key in factions `52984` and `999999` with faction-local payout requests.

Each event may settle only its own faction's request and balance.

## 7. Existing balance atomicity regression suite remains green

Retain failure/retry coverage for:

- credit events;
- payout balance effects;
- explicit observations;
- duplicate observers;
- same event key in two factions;
- explicit-vs-inferred same timestamp priority;
- stale unique lifetime totals;
- new-member convergence;
- ambiguous unresolved identities.

## 8. Migration-ownership regression

Add the strongest feasible local test for request-time schema behavior.

Prove at least:

- a fresh database receives the current complete bootstrap schema;
- an existing pre-0009/pre-current table shape is **not** silently altered by the runtime helper;
- the helper emits a clear migration-required failure when a required column is absent;
- after formal migrations are applied, the helper succeeds without additional schema drift.

Prefer behavioral execution over string matching. If project tooling prevents directly invoking the TypeScript helper in the Node SQLite test process, add the best executable seam available and document any remaining limitation instead of pretending a regex test proves runtime behavior.

---

# Additional review checks

While in these files, inspect for closely related defects, but do not expand into unrelated product work.

Verify:

- `payout_requests` reads/writes consistently use `faction_id` + `member_id` for durable identity;
- no rename-sensitive request transition remains where member ID is available;
- trigger SQL and runtime trigger definitions stay identical after the migration;
- migration ordering in `drizzle/meta/_journal.json` is correct;
- `npm run db:generate` after the final schema produces no surprise follow-up migration;
- browser journal replay still retries downstream idempotent effects without multiplying them;
- no old payout replay can consume a later request;
- no migration helper silently changes an existing production-shaped table.

Do not change Torn DOM parsing, Armory ordering, arbitrary-faction enablement, branding, or dependency versions in this run unless a direct regression from these fixes requires it.

---

# Validation

From `Faction Ledger/` run at minimum:

```bash
npm ci
npm run check
npx tsc --noEmit -p tsconfig.json
node --test tests/multitenancy-isolation.test.mjs
node --test tests/member-balance-atomicity.test.mjs
git diff --check
```

Run any new test file directly as well.

If schema changes:

```bash
npm run db:generate
```

Run it again after migration review; the second pass should report no unintended schema drift.

Record exact exit codes and test counts. Do not claim GitHub CI validation unless a workflow actually ran.

---

# Commit and push guidance

Keep changes reviewable. A reasonable sequence is:

1. `Make payout request settlement atomic and member-ID safe`
2. `Make balance schema evolution migration-owned`
3. `Add payout settlement and migration-ownership regressions`
4. `Document payout atomicity follow-up validation`

Fewer commits are fine if boundaries remain understandable.

Before pushing:

```bash
git status -sb
git diff --check
git log --oneline --decorate -12
git diff --stat origin/agent/fix-faction-ledger-sync-safety...HEAD
```

The integration diff must remain limited to `Faction Ledger/`.

Push normally:

```bash
git push origin codex/faction-ledger-multitenancy
```

Do not force-push.

---

# Documentation handback

Before finishing this run:

1. Append a dated result section to this file with:
   - starting/final SHA;
   - files changed;
   - exact payout-settlement design;
   - migration ownership behavior;
   - migration file(s) generated/reviewed;
   - commands, exit codes, and test counts;
   - remaining risks/blockers;
   - explicit confirmation that production D1 was not contacted and nothing was deployed/merged.
2. Change this file's status from **ACTIVE** to **COMPLETED** only if every blocker and regression criterion above is satisfied.
3. Append significant architecture/migration outcomes to `CODEX_MULTI_TENANCY_RUN.md`; keep its historical handoff evidence intact.
4. If a new follow-up blocker remains, replace the actionable section of this file with the next precise scope and leave status **ACTIVE** rather than forcing completion.
5. Keep `README.md`, `docs/README.md`, and `AGENTS.md` links accurate if documentation paths or workflow conventions change.

If GitHub access is available, comment on PR #3 with the fix commits and fresh validation evidence. Keep PR #3 draft. Do not merge it.

---

# Final Codex response

Report:

- starting and final branch SHA;
- whether a pull was required;
- files changed;
- payout request atomicity mechanism;
- how member rename safety is guaranteed;
- how duplicate/old replay is prevented from settling a new request;
- runtime migration-ownership behavior;
- migration generated/reviewed;
- every validation command and exit status;
- regression-test final values/counts;
- remaining production D1 blockers;
- PR #3 comment/update status;
- working-tree cleanliness;
- confirmation that nothing was deployed or merged.

Do not call the run complete unless both current blockers are covered by behavioral tests and the full existing suite still passes.

---

## Result — 2026-08-09

### Git state and files changed

- Starting branch/SHA: `codex/faction-ledger-multitenancy` at `107d0e2a81de0c0e78ab7f9a8760fa0fce3580ca`.
- Local and remote branch refs matched after `git fetch --all --prune`; no pull or fast-forward was required and the starting worktree was clean.
- Implementation/migration commit: `bd377cf` (`Make payout request settlement atomic and member-ID safe`).
- Regression commit: `4b7a43f` (`Add payout settlement and migration ownership regressions`).
- Final implementation/test SHA before this documentation handoff: `4b7a43f`. The exact pushed branch-tip SHA is reported in the task handoff and PR comment after the documentation commit is created.
- Changed paths for this follow-up: `app/api/torn-browser/route.ts`, `db/member-balances.ts`, `db/schema.ts`, `drizzle/0010_fluffy_luckman.sql`, `drizzle/meta/0010_snapshot.json`, `drizzle/meta/_journal.json`, `package.json`, `tests/member-balance-atomicity.test.mjs`, `tests/member-balance-schema-ownership.test.mjs`, `tests/multitenancy-isolation.test.mjs`, this handoff, and `docs/CODEX_MULTI_TENANCY_RUN.md`.

### Exact payout-settlement design

- `member_balance_entries` now has nullable `payout_request_id`. `prepareBalanceEventInsert()` resolves Torn member ID first and, only for a new payout with a resolved ID, selects the oldest eligible `pending`/`approved` request for the same `(faction_id, member_id)` whose amount is no greater than the observed payout. Selection occurs as a scalar subquery inside the event `INSERT`, not as an application-memory check/update sequence.
- The upgraded `apply_member_balance_entry` trigger applies the canonical balance and `paid_total`, validates the exact selected request is still faction/member-local and open, and marks only `NEW.payout_request_id` paid. The event marker, balance/totals, and request transition therefore share the outer SQLite/D1 statement transaction and roll back together on any trigger-side failure.
- Duplicate `(faction_id, event_key)` inserts do not fire the trigger. An old replay retains its original association (or `NULL`) and cannot consume a newer request. An event accepted without an eligible request cannot settle a request created later.
- Request identity uses canonical `(faction_id, member_id)`. A payout with resolved member ID `101` settles that member's request even when its historical request name is `Old Name` and the event/current display name is `New Name`. When no member ID can be resolved, the existing unresolved balance behavior remains available but no payout request is guessed by name.
- The separate name-based request update was removed from the Torn browser route. Optional `memberId`/`recipientId` event payload values are used when present; otherwise the existing verified faction-member resolver is used.

### Migration ownership and reviewed migration

- Generated and reviewed additive migration `drizzle/0010_fluffy_luckman.sql` and snapshot `drizzle/meta/0010_snapshot.json`; the journal entry is ordered after `0009`. Drizzle generated the nullable column addition. The migration was deliberately extended to `DROP TRIGGER IF EXISTS apply_member_balance_entry` and recreate the latest definition because `CREATE TRIGGER IF NOT EXISTS` cannot upgrade the `0009` trigger. Historical migration `0009` was not rewritten.
- A genuinely fresh database runtime bootstrap creates `member_balance_entries` with both `explicit_balance` and `payout_request_id`, then creates the latest triggers.
- If `member_balance_entries` already exists without either required migration-owned column, `ensureMemberBalanceSchema()` fails before its foundation/table/trigger batch with a clear `Member balance schema migration required` error. It no longer executes request-time `ALTER TABLE` repair.
- Runtime trigger creation occurs only after required columns are confirmed. A database migrated through `0009` and `0010` starts successfully; executable tests prove the helper does not alter the migrated entry-table or trigger definitions, and the formal/runtime trigger SQL normalizes identically.

### Commands and exact results

- `git fetch --all --prune` — exit 0.
- Baseline `npm.cmd ci` — exit 0; 506 packages installed. NPM reported 21 existing dependency vulnerabilities (1 low, 4 moderate, 16 high); no dependency versions were changed.
- Baseline `npm.cmd run check` — exit 0; 16/16 tests passed before edits.
- First `npm.cmd run db:generate` — exit 0; generated `0010_fluffy_luckman.sql` and `0010_snapshot.json`.
- Focused development runs: `node --test tests\\member-balance-atomicity.test.mjs` — exit 0, 16/16; `node --test tests\\member-balance-schema-ownership.test.mjs` — exit 0, 4/4; `node --test tests\\multitenancy-isolation.test.mjs` — exit 0, 3/3.
- Final `npm.cmd run check` — exit 0; lint and production build passed, 26/26 aggregate tests passed.
- Final `npx.cmd tsc --noEmit -p tsconfig.json` — exit 0.
- Final direct `node --test tests\\multitenancy-isolation.test.mjs` — exit 0, 3/3.
- Final direct `node --test tests\\member-balance-atomicity.test.mjs` — exit 0, 16/16.
- Final direct `node --test tests\\member-balance-schema-ownership.test.mjs` — exit 0, 4/4.
- Second `npm.cmd run db:generate` — exit 0; `No schema changes, nothing to migrate`.
- `git diff --check` — exit 0 before documentation; rerun after documentation is recorded in the final task handoff.

### Regression final-state evidence

- Normal payout from balance `100` with request `R1=30`: one marker associated to `R1`, balance `70`, `paid_total=30`, `R1=paid`; duplicate replay changes nothing.
- Forced request-settlement abort: marker count `0`, balance `100`, `paid_total=0`, request still pending; removing the failure and retrying produces marker `1`, balance `70`, `paid_total=30`, request paid exactly once.
- Rename: request stored as `Old Name`, resolved member ID `101`, event name `New Name`; the same request is paid and canonical balance metadata becomes `New Name`.
- Old replay: after `R1` is paid and `R2` is created, replay leaves `R2=pending`, balance `70`, and `paid_total=30`; association remains `R1`.
- No-request replay: original association remains `NULL`; a future request stays pending.
- Same name/event key in factions `52984` and `999999`: each marker associates only with its own faction-local request; final balances are `70` and `160`, paid totals `30` and `40`.
- Existing credit/observation rollback, duplicate observer, timestamp priority, stale lifetime-total, new-member convergence, ambiguous identity, migration preservation, and two-faction isolation tests remain green.

### Remaining risks and safety confirmation

- Production D1 still requires export/backup, exact `sqlite_master`/`PRAGMA table_info` inspection, read-only conflict preflight, exact-copy rehearsal of `0008` through `0010`, pre/post financial comparisons, unresolved member review, local Miniflare concurrency exercise, restore rehearsal, and a maintenance window before migration.
- Name-only payout observations intentionally do not guess a request when no unambiguous verified member-ID mapping exists. Improving Torn DOM member-ID capture is separate product work, not a reason to weaken canonical identity here.
- The runtime-helper behavioral seam uses Node's experimental SQLite and `stripTypeScriptTypes` APIs in tests; production code has no new dependency or runtime reliance on those APIs.
- GitHub issue #2, draft PR #3 comments/reviews, and review-thread state were inspected through the connected GitHub app. The two active blockers match this completed scope; there were no unresolved inline review threads.
- The repository was clean at the start. During final documentation, unrelated user-owned workbook changes appeared outside `Faction Ledger/` (`AUG2026 Growth Contest.xlsx` moved under `Growth comp/`, plus an Excel lock file); they were preserved and not staged or committed by this run.
- Production D1 was not contacted. No Wrangler remote command, deployment, merge, PR-ready transition, arbitrary-faction write enablement, force-push, rebase, or history reset was performed.
