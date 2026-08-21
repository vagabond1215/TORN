# Travel Assistant Agent Instructions

These instructions apply to the entire `RainMeter Projects/Travel Assistant/` subtree, regardless of whether work is performed through the GitHub connector, GPT, Codex, or a local development environment.

## Read order

Before changing code or data, read:

1. `AGENTS.md` — authoritative subtree rules and invariants.
2. `docs/README.md` — documentation routing and precedence.
3. `docs/NEXT_CODEX_RUN.md` — when **ACTIVE**, the current implementation scope.
4. `docs/ARCHITECTURE.md` — durable architecture and data contracts.
5. `docs/IMPLEMENTATION_STATUS.md` — current checkpoint and validation boundary.
6. `Readme.md` — human-facing overview.

If an older plan conflicts with an **ACTIVE** `NEXT_CODEX_RUN.md`, follow the active run while preserving every invariant here.

## Connector-first execution policy

- Prefer GPT + the connected GitHub connector for repository inspection, source/config/document edits, tests, and normal commits.
- Use local/Windows execution only for concrete behavior the connector cannot validate: Rainmeter rendering, Windows PowerShell behavior, local performance/resource checks, local API/provider behavior, or OS-specific integration.
- Never claim Windows/Rainmeter/live-provider validation that did not actually run.
- Work only inside `RainMeter Projects/Travel Assistant/` unless the user explicitly expands scope.
- Direct `main` edits remain allowed while this project is isolated/pre-use. Never force-push, rewrite unrelated history, or discard unrelated work.

## Product direction

Travel Assistant is expanding from the original UK/Japan Xanax proof into a generic Torn foreign-market assistant.

The expansion must keep three concepts separate:

```text
COLLECTED opportunities
        !=
VISIBLE opportunities
        !=
OPTIMIZER candidates
```

### Collection

- Background collection should be broad and automatic.
- Collect every valid foreign-shop row returned by the live provider for every configured foreign country, irrespective of item category.
- Provider-observed market identity is `country + itemId`.
- Collection filters must never depend on the current UI country/category filter.
- Traveling to one country may narrow the visible UI later, but must not stop background learning for other countries.

### Visibility

- The currently validated visible UI remains UK/Japan Xanax until a later explicit UI expansion pass is validated.
- Cherry Blossom and Nessie Plushie are seeded metadata for the first multi-item presentation proof, but remain hidden during the initial shadow-collection rollout.
- Future country/category filters are presentation filters only.
- While traveling outbound, future travel-aware presentation should show only the destination country's items and replace the static route duration with the API-derived arrival countdown while retaining the plane icon.

### Optimizer

- `Optimal` mode is a future scheduling layer, not a synonym for sorting by profit/item or profit/trip.
- Do not enable an item/country market for optimizer decisions until its economics, capacity semantics, current availability and evidence quality are adequately modeled.
- The optimizer must eventually compare many short trips, fewer long trips, and mixed-country sequences over a bounded planning horizon.
- Best expected profit is still subject to freshness, confidence and unresolved-economics guards.

## Non-negotiable recommendation/data invariants

1. **No recommendation beats a bad recommendation.** Suppress actionable travel advice when stock/resale data is stale, confidence is inadequate, the price regime is unsupported, sources materially disagree, travel economics are unresolved, or configured profitability gates fail.
2. **Observed history is truth, forecasts are not.** `0 -> positive` is an observed restock and `positive -> 0` an observed sellout. Provider predictions must never populate historical truth fields.
3. **Market identity is generic.** Keep history/model state isolated by `country + itemId`; never let one item's transitions create another item's cycles.
4. **Foreign price is first-class evidence.** Do not merge radically different price/depletion regimes as equivalent.
5. **Current depletion can shorten safety, never expand it beyond supporting historical evidence.**
6. **Best odds is not safe.** Keep probabilistic wording distinct from conservative `SAFE_WINDOW` wording.
7. **Profitability gates timing, not learning.** Continue collecting useful observations/cycles when an opportunity is unprofitable.
8. **Unknown economics are not zero economics.** Ticket-funded Business remains unresolved unless a known-free branch is established.
9. **Provider provenance is retained and normalized at the adapter boundary.** Provider-specific response structures must not leak into the core observation/cycle model.
10. **Collection failures must fail visibly but gracefully.** Background expansion must not take down the established visible Xanax path.
11. **Runtime data is not Git history.** Observations, cycles, caches, generated graphs/state, provider probes, local settings, credentials and shadow-collection errors stay ignored/local.
12. **Storage and compute remain bounded.** Do not turn Rainmeter's one-second update loop into network/model work.

## Current background-collection contract

The initial expansion uses a fail-soft `ShadowCollector.ps1`:

- current visible updater runs first;
- shadow collector runs afterward and before finalization;
- default shadow polling interval is 120 seconds;
- all 11 Torn foreign destinations are configured for collection;
- every valid provider row is normalized to the standard observation schema;
- current primary visible markets are skipped by shadow writes to avoid duplicate-cycle interference;
- newly observed markets are tracked in ignored runtime engine state;
- shadow failures are recorded locally and must not suppress the established updater/finalizer/heartbeat.

This is an intentionally conservative migration layer. A later refactor may unify visible and shadow collection behind one provider fetch, but must prove identical primary-market behavior before removing the fail-soft bridge.

## Observation / cycle contracts

Normalized observation:

```text
schemaVersion
timestamp
country
itemId
stock
foreignPrice
source
sourceTimestamp
```

Completed cycle:

```text
schemaVersion
country
itemId
foreignPrice
restockAt
restockQuantity
soldOutAt
availabilitySeconds
previousSoldOutAt
restockDelaySeconds
source
```

Default retention remains approximately:

- high-resolution observations: 48 hours;
- completed cycles: 90 days;
- visible graph window: 8 hours.

The live-provider stale threshold is a safety/freshness guard, not a history-retention threshold.

## Capacity / travel-profile authority

For current carrying capacity, prefer the player's current `/user/perks` state rather than requiring faction-upgrade permissions.

Current mode base capacity:

- Standard: 10;
- Airstrip/WLT/qualified Business: 15.

Current active general bonuses are derived from suitable current perk buckets, with property/stock travel-method effects excluded from additive capacity to avoid double-counting the selected mode base.

A successfully synced current-capacity bonus is authoritative for general capacity and replaces legacy inferred company/faction capacity additions. Legacy fields may remain readable for backward compatibility.

Company/star modeling is still required for non-capacity effects such as free Business Class. Category-specific capacity must be handled separately before multi-category economics becomes optimizer-eligible:

- Flower Shop flower capacity applies only to Flower items;
- Toy Shop plushie capacity applies only to Plushie items;
- neither may increase Xanax capacity.

A positive explicit `profitability.capacityOverride` remains authoritative where supported.

## Provider / web-data policy

- Treat Prometheus, YATA, Weav3r, DroqsDB and other services as replaceable adapters.
- Prefer structured endpoints over browser scraping.
- Foreign stock is provider-observed/crowd-sourced; do not assume a static Wiki table is the live catalog authority.
- The live provider payload determines what markets are currently observed; canonical Torn metadata will later provide item names/categories.
- Do not create one foreign-stock request per item. A country-stock payload should fan out locally to all item observations.
- Resale-price enrichment is a separate concern and must be cached/staggered rather than issuing hundreds of Torn Item Market requests every minute.
- Source disagreement lowers confidence; do not silently average incompatible source states.

## API keys / secrets

- Limited/higher-authority keys remain local only and must never be committed.
- Settings stores the key only in ignored local configuration and masks it by default.
- Never print, log or request that the user paste the full key into chat.
- Do not broaden key permissions merely for convenience.
- Keep the validated bounded `curl.exe` workaround scoped to Torn API calls that require it on the target Windows environment.

## Performance / resource budget

- One-second Rainmeter work: local string/countdown/visibility updates only.
- Primary network/model pass: approximately once per minute.
- Initial broad shadow collection: no more frequent than 120 seconds unless explicitly revalidated.
- Avoid permanent background PowerShell/browser processes.
- Keep updater executions serialized.
- Reuse provider payloads locally where practical; the current separate shadow request is a migration bridge, not the desired long-term architecture.
- Graph generation remains compact; do not create thousands of Rainmeter meters for samples.

## Current UI invariants

Until a deliberate multi-item UI release:

- dark charcoal theme;
- UK card above Japan card;
- country flags remain local Rainmeter vector shapes, not claimed official Torn assets;
- header shows item name, profitability-colored foreign price, and current stock/out-of-stock state;
- only the literal `Out of Stock` warning is red; elapsed/since text remains normal;
- flight row uses a plane icon;
- actionable restock timing uses a delivery-truck icon and is shown only when stock is out and predicted restock ETA exceeds flight time;
- hidden restock/history context remains available in the tooltip;
- graphs remain equal width with an 8-hour visible window and 60-minute vertical divisions;
- `Travel` header opens Torn travel;
- top-right Settings remains available.

## Stable machine-readable statuses

Keep status logic keyed to codes, not display strings. Current vocabulary includes:

```text
SAFE_WINDOW
BEST_ODDS
TOO_EARLY
WINDOW_CLOSED
INSUFFICIENT_HISTORY
PRICE_REGIME_UNVERIFIED
SOURCE_DISAGREEMENT
LOW_MARGIN
UNPROFITABLE
STALE_DATA
CHECK_EXTERNAL
```

Add new codes deliberately and document their semantics.

## Validation expectations

For changes touching collection/config/model behavior:

- validate JSON syntax;
- run PowerShell parser/static validation on changed scripts;
- exercise provider normalization from fixtures/synthetic payloads;
- prove item/country cycle isolation;
- prove primary visible markets are protected from duplicate shadow writes;
- verify retention remains bounded;
- verify ignored runtime/local files remain ignored;
- run focused tests first and avoid broad unrelated reruns unless source changes justify them;
- do not claim live/Rainmeter validation until it runs on Windows.

Current shadow-focused checks include:

```powershell
.\tests\Validate-ShadowCollection.ps1
.\tests\Run-ShadowCollectionTests.ps1
```

The full suite remains `tests/Run-All.ps1` when a broad run is justified.

## Documentation / handoff

- Keep `docs/ARCHITECTURE.md` synchronized with durable structural decisions.
- Keep `docs/NEXT_CODEX_RUN.md` as the rolling active implementation handoff.
- Keep `docs/IMPLEMENTATION_STATUS.md` factual about what was implemented versus what still needs Windows/live validation.
- Keep `Readme.md` human-readable and current.
- If a new blocker/follow-up becomes the active scope, update the rolling handoff rather than creating competing task documents.
