# Faction Ledger

A Torn City faction treasury and synchronization application for balances, earmarked accounts, Armory inventory, organized crimes, ranked wars, and a clear financial audit trail.

## Current architecture

- **Cloudflare D1 is canonical production state.**
- Torn API and userscript DOM observations feed D1; the userscript queue/browser event journal are transport/audit layers, not the source of truth.
- Local development uses disposable Miniflare/Wrangler state under `.wrangler` and must not be treated as production data.
- Durable state and authorization are faction-scoped, with Blood Coven (`faction_id=52984`) backfilled as the existing tenant.
- Torn member ID is the canonical durable member identity; member names are mutable display metadata.
- Browser observations are faction-scoped and deduplicated so repeated viewers do not multiply durable financial effects.
- Balance event/observation markers and payout-request settlement use database-side transactional effects so failed derived writes do not permanently consume event keys.
- Current Armory state is snapshot-backed by category. Migration `0012_exotic_tarot.sql` adds durable snapshot-base JSON and deterministic post-snapshot movement folding by `occurred_at`, `event_key`, then `item_name`; historical OC rewards remain historical and do not inflate current inventory.
- Armory movement times more than five minutes in the future are ignored, and generic `payload.endedAt` is not allowed to override Armory movement/Xanax-use occurrence time.
- A current connector review item remains: duplicate Armory journal replays must rematerialize from the already-accepted durable movement metadata rather than allowing replay request metadata to steer canonical state.
- Userscript sessions are dynamically revalidated against Torn faction membership before stale sessions upload more observations, and faction/member-local client storage is scoped/scrubbed on identity changes.

The application is **still intentionally Blood-Coven-only in production authorization**. The data model supports isolated synthetic tenants, but arbitrary-faction production creation/login/writes remain gated until production D1 migration rehearsal and all active review blockers are cleared.

## Features

- Percentage-based automatic distribution of faction proceeds
- Custom treasury accounts and transaction history
- Shared userscript observations for member balances and faction activity
- Category-based Armory inventory synchronization
- Organized-crime and ranked-war historical backfill
- Duplicate-event protection and stale-observation ordering
- Dynamic faction-membership revalidation for userscript sessions
- Faction-scoped durable state, authorization, cursors, and client caches
- Responsive treasury dashboard for desktop and mobile

## Local development

Requires Node.js 22.13 or newer.

```bash
npm ci
npm run dev
```

Validation:

```bash
npm run check
```

`npm run check` runs lint plus the production build and configured regression tests. Use `npm run db:generate` after Drizzle schema changes and inspect generated SQL/metadata before committing it. Never point local development or migration commands at production D1.

## Codex development workflow

Faction Ledger is currently **pre-production and not in active service**. Codex works directly on:

```text
main
```

PR #3 merged the accumulated Faction Ledger tenancy/synchronization development into `main`. PR #1 was closed unmerged as a superseded historical integration layer. The previous long-lived Codex/integration branch stack is retired.

For each Codex run:

```bash
git fetch origin
git switch main
git pull --ff-only origin main
git status -sb
```

If local `main` is dirty or diverged, stop and inspect instead of resetting/rebasing/force-pushing automatically.

Make normal commits, run the requested validation, and push directly to `main` while the application remains pre-production.

When the application is moved into actual use, this policy must be reversed before further production-affecting development: restore feature branches/PR review, required CI, and appropriate branch protection.

### Read before editing

1. [`AGENTS.md`](./AGENTS.md) — always first; safety rules, direct-main pre-production policy, and non-negotiable data/sync invariants.
2. [`docs/README.md`](./docs/README.md) — documentation routing and instruction precedence.
3. [`docs/NEXT_CODEX_RUN.md`](./docs/NEXT_CODEX_RUN.md) — when marked **ACTIVE**, this is the authoritative current task/prompt and handback checklist.
4. [`docs/CODEX_MULTI_TENANCY_RUN.md`](./docs/CODEX_MULTI_TENANCY_RUN.md) — broader architecture, completed migration plan, historical handoffs, and prior validation evidence.
5. GitHub issue **#2** and relevant review/history when GitHub access is available.

An older embedded prompt in the historical runbook must not override an **ACTIVE** `NEXT_CODEX_RUN.md`.

### Current handoff

`docs/NEXT_CODEX_RUN.md` is **ACTIVE** on `main` for a focused Armory durable-replay-authority follow-up. The previous same-time/timestamp-safety run completed at implementation SHA `5d155ce7` and documentation SHA `41fd50a` with migration `0012` and reported 52/52 aggregate tests.

The current task requires:

- once `(faction_id, event_key, item_name)` has been accepted into `armory_item_effects`, replay request metadata must not be able to choose a different category/effect scope during rematerialization;
- duplicate journal re-imports may self-heal only from canonical persisted movement metadata;
- mismatched-category/action/amount replay regressions must prove the durable accepted event remains authoritative;
- the completed equal-time ordering, zero-floor convergence, delayed-snapshot behavior, future-time bound, tenant/category isolation, OC-history isolation, and sync-error semantics must remain intact;
- audit the handling of newly ingested movements whose normalized occurrence time is missing, without inventing historical timestamps.

No schema change is expected for this replay-authority fix unless Codex demonstrates a genuine need; `db:generate` should otherwise report no drift.

Codex must update the rolling next-run file with results/status before handing control back. Significant architecture/migration outcomes should also be appended to the historical runbook rather than replacing prior evidence.

## Production rollout boundary

Direct-to-`main` development while the app is pre-production does **not** mean production deployment is approved. Before production D1 migration or arbitrary-faction enablement, the repository still requires a verified D1 export/backup, exact production `sqlite_master`/`PRAGMA table_info` inspection, read-only unique-key preflight, migration rehearsal against a copy of the real data, pre/post financial/row-count/Armory comparison, unresolved member-identity review, concurrency rehearsal, restore rehearsal, and a maintenance window.
