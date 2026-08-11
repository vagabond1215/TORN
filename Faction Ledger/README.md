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
- Current Armory state is snapshot-backed by category and folds durable post-snapshot movements by occurrence time; historical OC rewards remain historical and do not inflate current inventory. Equal-timestamp movement convergence and future-time sanity remain the current active review items.
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

Faction Ledger is currently **pre-production and not in active service**. The intended steady-state development workflow is therefore direct-to-`main`: once the current bridge PR is merged, Codex should start from current `main`, make normal commits, validate locally, and push directly to `main`.

When the application is moved into actual use, this policy must be reversed before further production-affecting development: restore feature branches/PR review, required CI, and appropriate branch protection.

### One-time transition now in progress

The accumulated Faction Ledger development history still lives on:

```text
codex/faction-ledger-multitenancy
```

PR #3 now targets:

```text
main
```

directly. The old `agent/fix-faction-ledger-sync-safety` integration layer / PR #1 is superseded and is no longer the development target.

Because the Codex branch and current `main` have long-running divergent history, this ACTIVE run is the final branch-based transition pass. Codex must:

1. fetch current refs;
2. merge current `origin/main` into `codex/faction-ledger-multitenancy` using a normal history-preserving merge;
3. preserve current `main` for unrelated repository work and semantically preserve the Faction Ledger implementation;
4. finish the ACTIVE Armory same-time/timestamp-safety blockers;
5. run the full validation suite;
6. push the reconciled branch and hand back for review/merge of PR #3.

After PR #3 is merged, new Codex work starts on `main` directly unless a human explicitly changes the policy.

### Read before editing

1. [`AGENTS.md`](./AGENTS.md) — always first; safety rules, current development-mode branch policy, and non-negotiable data/sync invariants.
2. [`docs/README.md`](./docs/README.md) — documentation routing and instruction precedence.
3. [`docs/NEXT_CODEX_RUN.md`](./docs/NEXT_CODEX_RUN.md) — when marked **ACTIVE**, this is the authoritative current task/prompt and handback checklist.
4. [`docs/CODEX_MULTI_TENANCY_RUN.md`](./docs/CODEX_MULTI_TENANCY_RUN.md) — broader architecture, completed migration plan, historical handoffs, and prior validation evidence.
5. GitHub issue **#2** and current PR/review discussion when GitHub access is available.

An older embedded prompt in the historical runbook must not override an **ACTIVE** `NEXT_CODEX_RUN.md`.

### Current handoff

`docs/NEXT_CODEX_RUN.md` is **ACTIVE** for a narrow connector-found Armory follow-up plus the one-time branch reconciliation. It currently covers:

- merge current `origin/main` into the Codex branch without rewriting history and ensure the resulting PR-to-main diff contains only intended Faction Ledger development changes;
- make equal-timestamp Armory movements deterministic so the same durable event set produces the same quantity regardless of observer/network arrival order, including zero-floor cases;
- add future-time sanity validation for Armory movements now that `occurred_at` controls replay across snapshots;
- preserve the completed delayed-snapshot convergence, exact-once dedupe, tenant/category isolation, OC-history isolation, and script-sync 401/503 semantics;
- keep any new schema evolution additive after `0011_thin_pyro.sql` and migration-owned for existing databases;
- hand back PR #3 for the one-time merge to `main`, after which the branch-based development workflow is retired.

Codex must update the rolling next-run file with results/status before handing control back. Significant architecture/migration outcomes should also be appended to the historical runbook rather than replacing its prior evidence.

## Production rollout boundary

Direct-to-`main` development while the app is pre-production does **not** mean production deployment is approved. Before production D1 migration or arbitrary-faction enablement, the repository still requires a verified D1 export/backup, exact production `sqlite_master`/`PRAGMA table_info` inspection, read-only unique-key preflight, migration rehearsal against a copy of the real data, pre/post financial and row-count comparison, unresolved member-identity review, concurrency rehearsal, restore rehearsal, and a maintenance window.
