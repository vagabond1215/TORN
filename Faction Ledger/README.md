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
- Once an Armory movement is durably accepted, replay/rematerialization derives authority from the persisted `armory_item_effects` row rather than replay request metadata. New movements without a normalized occurrence time are rejected before journal acknowledgement/durable application; migrated historical `NULL occurred_at` rows remain preserved without invented timestamps.
- Userscript sessions are dynamically revalidated against Torn faction membership before stale sessions upload more observations, and faction/member-local client storage is scoped/scrubbed on identity changes.

The application is **still intentionally Blood-Coven-only in production authorization**. The data model supports isolated synthetic tenants, but arbitrary-faction production creation/login/writes remain gated until production D1 migration rehearsal and the pre-go-live controls are complete.

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
3. [`docs/NEXT_CODEX_RUN.md`](./docs/NEXT_CODEX_RUN.md) — authoritative current task only when marked **ACTIVE**; otherwise it preserves the latest completed handoff/result.
4. [`docs/CODEX_MULTI_TENANCY_RUN.md`](./docs/CODEX_MULTI_TENANCY_RUN.md) — broader architecture, completed migration plan, historical handoffs, and prior validation evidence.
5. GitHub issues/review history when relevant.

An older embedded prompt in the historical runbook must not override an **ACTIVE** `NEXT_CODEX_RUN.md`.

### Current handoff state

`docs/NEXT_CODEX_RUN.md` is currently **COMPLETED**. The latest completed pass is the Armory durable-replay-authority follow-up at implementation SHA `c13d9f9d8bb59fcedddbe68cfed292299626a51f` with documentation SHA `c79fa4b0206e256692767ca483232d5703d3577e`.

That pass completed the remaining reviewed Armory correctness work without a schema change:

- duplicate journal re-imports rematerialize from canonical persisted movement metadata;
- replay category/action/amount/time cannot alter an already accepted effect;
- exact duplicate and cross-faction replay remain idempotent/isolated;
- equal-time ordering, zero-floor convergence, delayed-snapshot behavior, future-time bounds, OC isolation, and script-sync error semantics remain covered;
- new normalized timestamp-less movements are rejected, while migrated historical `NULL occurred_at` effects remain preserved.

The reported local validation for that pass is recorded in `docs/NEXT_CODEX_RUN.md` and `docs/CODEX_MULTI_TENANCY_RUN.md`. There is still no dedicated Faction Ledger GitHub CI check, so pre-go-live CI/security/branch-protection work remains tracked separately in issue #6.

## Production rollout boundary

Direct-to-`main` development while the app is pre-production does **not** mean production deployment is approved. Before production D1 migration or arbitrary-faction enablement, the repository still requires a verified D1 export/backup, exact production `sqlite_master`/`PRAGMA table_info` inspection, read-only unique-key preflight, migration rehearsal against a copy of the real data, pre/post financial/row-count/Armory comparison, unresolved member-identity review, concurrency rehearsal, restore rehearsal, and a maintenance window.
