# Faction Ledger Codex Instructions

These instructions apply to the entire `Faction Ledger/` subtree.

## Working branch and safety

- Integration baseline: `agent/fix-faction-ledger-sync-safety`.
- Codex implementation branch: `codex/faction-ledger-multitenancy`, created from the prepared integration baseline. Do all large tenancy-refactor commits there.
- Do not commit directly to `main`. Do not merge, deploy, force-push, or retarget production from Codex.
- Production Cloudflare D1 is canonical. Local `.wrangler` / Miniflare state is disposable development data.
- Never point local tests or migrations at production D1. Never use destructive resets, `DROP`-and-recreate production tables, or force-push history.
- Prefer additive, idempotent migrations with explicit backfills and validation queries. Preserve existing Blood Coven data (faction ID `52984`).
- Do not enable arbitrary-faction writes until every durable read/write path is tenant-scoped and isolation tests pass.

## Required data invariants

1. **Faction isolation:** every durable faction-owned row must be attributable to a `faction_id`, and every API query/mutation must scope by the authenticated/verified faction. A client-supplied faction ID alone is never authorization.
2. **Torn member ID is canonical identity:** use Torn `member_id`/user ID as the durable member key. Names are mutable display metadata and must not be primary identity.
3. **Idempotent observations:** the same Torn event observed by multiple users must apply once. Dedupe keys must be faction-scoped (`faction_id` + stable event key/ID).
4. **Ordering:** newer Torn observations win. At the same timestamp, explicit balances (`from X to Y`, full snapshots, direct balance observations) beat inferred deltas.
5. **Prunable transport:** `torn_browser_events` and userscript queues are transport/audit journals, not canonical state. Pruning them must never roll back balances, inventory, OC history, wars, or treasury accounts.
6. **Armory truth:** current Armory inventory comes from authoritative category snapshots plus later idempotent movements. Historical OC rewards are history and must not inflate current Armory inventory.
7. **Membership-before-upload:** userscript direct sync must validate current Torn identity/faction before uploading queued observations once the membership freshness window is stale. Confirmed identity/faction changes revoke the session and scrub faction-local client state; temporary Torn/API failures retain state and retry.
8. **No cross-faction stale UI:** switching faction/account must clear old faction token, API key, queue, cached balances, injected balance UI, and any other local faction-specific state before a new tenant is displayed.

## Validation commands

From `Faction Ledger/`:

```bash
npm ci
npm run check
```

`npm run check` executes lint plus the production build/rendered-HTML test path.

After Drizzle schema changes:

```bash
npm run db:generate
```

Inspect generated migrations before committing them. Do not treat generated SQL as correct without checking tenant keys, uniqueness, backfills, and existing-row preservation.

## Refactor sequence

Follow `docs/CODEX_MULTI_TENANCY_RUN.md`. Do not skip directly to arbitrary-faction login. The expected order is:

1. baseline tests;
2. tenant context/schema foundation;
3. member-ID migration;
4. faction-scope all durable tables and runtime-created tables;
5. tenant-scope all API reads/writes and dedupe keys;
6. tenant-scoped client storage and faction switching;
7. corroboration/sync telemetry;
8. isolation/concurrency/migration tests;
9. only then enable non-Blood-Coven tenant creation/login.

## Definition of done for a Codex pass

- `npm run check` passes.
- Schema/migration changes preserve Blood Coven data and have a local migration test.
- Two synthetic factions can hold the same member name, item name, event key, policy key, and similar records without collision or cross-read.
- Duplicate multi-observer submissions change durable financial/inventory state once.
- Membership/faction change clears local stale state and cannot upload observations to the previous tenant.
- Update `docs/CODEX_MULTI_TENANCY_RUN.md` with completed items, deviations, commands/results, generated migrations, and remaining risks before handing control back.