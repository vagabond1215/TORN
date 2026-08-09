# Faction Ledger

A Torn City faction treasury and synchronization application for balances, earmarked accounts, Armory inventory, organized crimes, ranked wars, and a clear financial audit trail.

## Current architecture

- **Cloudflare D1 is canonical production state.**
- Torn API and userscript DOM observations feed D1; the userscript queue/browser event journal are transport/audit layers, not the source of truth.
- Local development uses disposable Miniflare/Wrangler state under `.wrangler` and must not be treated as production data.
- Durable state and authorization on the Codex branch are faction-scoped, with Blood Coven (`faction_id=52984`) backfilled as the existing tenant.
- Torn member ID is the canonical durable member identity; member names are mutable display metadata.
- Browser observations are faction-scoped, deduplicated, and ordered so repeated viewers do not multiply financial/inventory effects and stale snapshots do not overwrite newer state.
- Current Armory state is snapshot-backed by category; historical OC rewards remain historical and do not inflate current inventory.
- Userscript sessions are dynamically revalidated against Torn faction membership before stale sessions upload more observations, and faction/member-local client storage is scoped/scrubbed on identity changes.
- Balance event/observation markers apply canonical balance effects transactionally through database triggers so a failed effect does not permanently consume the event key.

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

## Codex work

The current Codex working branch is:

```text
codex/faction-ledger-multitenancy
```

Its integration target is:

```text
agent/fix-faction-ledger-sync-safety
```

Do **not** start a current Codex pass from the integration branch; fetch it for comparison, but work on the Codex branch unless a human explicitly changes the handoff.

### Read before editing

1. [`AGENTS.md`](./AGENTS.md) — always first; safety rules and non-negotiable data/sync invariants.
2. [`docs/README.md`](./docs/README.md) — documentation routing and instruction precedence.
3. [`docs/NEXT_CODEX_RUN.md`](./docs/NEXT_CODEX_RUN.md) — when marked **ACTIVE**, this is the authoritative current task/prompt and handback checklist.
4. [`docs/CODEX_MULTI_TENANCY_RUN.md`](./docs/CODEX_MULTI_TENANCY_RUN.md) — broader architecture, completed migration plan, historical handoffs, and prior validation evidence.
5. GitHub issue **#2** and draft PR **#3** — current review/status context when GitHub access is available.

An older embedded prompt in the historical runbook must not override an **ACTIVE** `NEXT_CODEX_RUN.md`.

### Current handoff

At the time this README was updated, `docs/NEXT_CODEX_RUN.md` is **ACTIVE** and covers two review blockers:

- make Torn payout-request settlement atomic with the durable payout event and use canonical member ID rather than rename-sensitive member-name matching;
- stop request-time schema helpers from silently pre-applying formal migration-owned columns/trigger upgrades to existing databases.

Codex must update the rolling next-run file with results/status before handing control back. Significant architecture/migration outcomes should also be appended to the historical runbook rather than replacing its prior evidence.

## Production rollout boundary

Before production D1 migration or arbitrary-faction enablement, the repository requires a verified D1 export/backup, exact production `sqlite_master`/`PRAGMA table_info` inspection, read-only unique-key preflight, migration rehearsal against a copy of the real data, pre/post financial and row-count comparison, unresolved member-identity review, concurrency rehearsal, restore rehearsal, and a maintenance window.

Do not deploy or merge directly from Codex.
