# Faction Ledger

A Torn City faction treasury and synchronization application for balances, earmarked accounts, Armory inventory, organized crimes, ranked wars, and a clear financial audit trail.

## Current architecture

- **Cloudflare D1 is canonical production state.**
- Torn API and userscript DOM observations feed D1; the userscript queue/browser event journal are transport/audit layers, not the source of truth.
- Local development uses disposable Miniflare/Wrangler state under `.wrangler` and must not be treated as production data.
- Browser observations are deduplicated and ordered so repeated viewers do not multiply financial/inventory effects and stale snapshots do not overwrite newer state.
- Current Armory state is snapshot-backed by category; historical OC rewards remain historical and do not inflate current inventory.
- Userscript sessions are dynamically revalidated against Torn faction membership before stale sessions upload more observations.

The current draft branch still treats Blood Coven (`faction_id=52984`) as the only enabled production tenant. The next refactor is to partition all durable state and authorization by faction before enabling arbitrary factions.

## Features

- Percentage-based automatic distribution of faction proceeds
- Custom treasury accounts and transaction history
- Shared userscript observations for member balances and faction activity
- Category-based Armory inventory synchronization
- Organized-crime and ranked-war historical backfill
- Duplicate-event protection and stale-observation ordering
- Dynamic faction-membership revalidation for userscript sessions
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

`npm run check` runs lint plus the production build/rendered-HTML test path. Use `npm run db:generate` after Drizzle schema changes and inspect generated SQL before committing it.

## Codex work

Before a Codex implementation pass, read:

1. [`AGENTS.md`](./AGENTS.md) — safety rules and non-negotiable sync/data invariants.
2. [`docs/CODEX_MULTI_TENANCY_RUN.md`](./docs/CODEX_MULTI_TENANCY_RUN.md) — staged multi-tenant/member-ID migration plan, acceptance tests, and a ready-to-use Codex prompt.

For the current refactor, start from branch `agent/fix-faction-ledger-sync-safety`. Do not deploy or point local tests at production D1. Preserve existing Blood Coven data and only enable non-Blood-Coven tenant writes after two-tenant isolation tests pass.
