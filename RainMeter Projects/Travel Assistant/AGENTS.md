# Travel Assistant Agent Instructions

These instructions apply to the entire `RainMeter Projects/Travel Assistant/` subtree.

## Read order

Before changing code or data, read:

1. `AGENTS.md`
2. `docs/README.md`
3. `docs/NEXT_CODEX_RUN.md`
4. `docs/ARCHITECTURE.md`
5. `docs/IMPLEMENTATION_STATUS.md`
6. `Readme.md`

If an older plan conflicts with an **ACTIVE** `NEXT_CODEX_RUN.md`, follow the active run while preserving every invariant here.

## Connector-first execution

- Prefer GPT + the connected GitHub connector for inspection, source/config/doc edits, tests and commits.
- Use local Windows only for Rainmeter rendering, Windows PowerShell behavior, local provider/API behavior, performance/resource checks or OS-specific integration.
- Never claim Windows/Rainmeter/live-provider validation that did not run.
- Work only inside this subtree unless explicitly asked otherwise.
- Direct `main` edits remain allowed while the project is isolated/pre-use. Never force-push or rewrite unrelated work.

## Product direction

Travel Assistant is expanding from the UK/Japan Xanax proof into a generic Torn foreign-market assistant.

Keep these populations separate:

```text
COLLECTED opportunities
        !=
VISIBLE opportunities
        !=
OPTIMIZER candidates
```

### Collection

- Collect every valid foreign-shop row returned by the live provider for every configured foreign country, irrespective of category.
- Market identity is always `country + itemId`.
- UI filters and current travel destination must never stop background learning for other markets.

### Visibility

- The currently validated visible UI remains UK/Japan Xanax until a deliberate multi-item UI release passes validation.
- Nessie Plushie and Cherry Blossom remain the first hidden metadata/UI proof items.
- Future country/category filters are presentation filters only.
- Future outbound travel presentation should show only the destination country's items and replace static flight duration with arrival countdown while keeping the plane icon.

### Optimizer

- `Optimal` is a future scheduling layer, not a sort by profit/item or profit/trip.
- Do not make a market optimizer-eligible until economics, capacity semantics, current availability and evidence quality are adequately modeled.
- It must eventually compare many short trips, fewer long trips and mixed-country sequences over a bounded planning horizon.

## Non-negotiable data/recommendation invariants

1. Prefer no recommendation over weak/unsafe advice.
2. `0 -> positive` is an observed restock; `positive -> 0` is an observed sellout. Forecasts never become historical truth.
3. Keep history/model state isolated by `country + itemId`.
4. Foreign price is first-class evidence; do not merge radically different price regimes as equivalent.
5. Current depletion may shorten safety but never expand it beyond supporting history.
6. `BEST_ODDS` is not `SAFE_WINDOW`.
7. Profitability gates timing, not learning.
8. Unknown economics are not zero economics. Ticket-funded Business remains unresolved unless a known-free branch exists.
9. Provider provenance is retained and normalized at the adapter boundary.
10. Collection/enrichment failures must fail visibly but gracefully and must not break the established visible Xanax path.
11. Runtime observations, cycles, caches, generated state/graphs, local settings, credentials and errors stay ignored/local.
12. Storage/compute remain bounded. The one-second Rainmeter loop must not perform network/model work.

## Current background-collection contract

`ShadowCollector.ps1` is the active expansion bridge:

- visible updater runs first;
- shadow collector runs afterward;
- default shadow interval is 120 seconds;
- all 11 foreign destinations collect;
- every valid provider row normalizes to the observation schema;
- current primary visible markets are skipped by shadow writes;
- raw history writes only on stock/foreign-price changes;
- provider timestamp alone updates freshness without another raw observation;
- failures remain fail-soft.

Target-Windows acceptance on 2026-08-21 established:

```text
Prometheus
11 countries
232 observed country-item markets
51 changed observations on forced acceptance pass
no shadow error
```

A later refactor may unify visible and shadow collection behind one provider fetch only after equivalent primary behavior is proven.

## Current item-metadata contract

Catalog metadata must **not** run inside the Rainmeter heartbeat path.

Target-Windows testing established that all attempted Torn catalog transports timed out before returning metadata:

```text
v2 specific-items | 150 IDs | 20s
v2 specific-items |  40 IDs | 30s
classic torn/items bulk      | 12s
```

Therefore:

- `RunUpdate.ps1` must not invoke `ItemMetadata.ps1`;
- `ItemMetadata.ps1` is explicit/manual maintenance only;
- do not keep increasing Torn catalog timeouts/batch sizes;
- full catalog direction is a committed/offline metadata catalog refreshed outside the heartbeat.

`ItemMetadata.ps1` must seed committed `config/items.json` metadata before any optional network attempt. Seed rows use:

```text
source=config_seed
marketPrice=0
tradabilityKnown=false
```

Current committed seeds:

```text
206 Xanax          | Drug
266 Nessie Plushie | Plushie
277 Cherry Blossom | Flower
```

A later successful maintenance refresh may replace seed rows with richer canonical metadata. Network failure must never erase known seed metadata.

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

Default retention:

- high-resolution observations: 48 hours;
- completed cycles: 90 days;
- visible graph window: 8 hours.

The live stale threshold is a safety guard, not history retention.

## Capacity / travel-profile authority

Prefer current `/user/perks` for carrying capacity rather than faction-upgrade permissions.

Current mode base:

- Standard: 10;
- Airstrip/WLT/qualified Business: 15.

A synced current-capacity bonus is authoritative for general capacity and replaces legacy inferred company/faction additions. Property/stock travel-method effects must not be double-counted.

Company/star modeling still matters for non-capacity effects such as free Business Class.

Before multi-category economics becomes optimizer-eligible:

- Flower Shop flower capacity applies only to Flower items;
- Toy Shop plushie capacity applies only to Plushie items;
- neither may increase Xanax capacity.

A positive explicit `profitability.capacityOverride` remains authoritative where supported.

## Provider / web-data policy

- Treat Prometheus, YATA, Torn, Weav3r, DroqsDB and other services as replaceable adapters.
- Prefer structured endpoints over scraping when practical.
- Live foreign stock is provider-observed/crowd-sourced; static Wiki tables are not live-catalog authority.
- Do not create one stock request per item; a country payload must fan out locally.
- Full item names/categories should come from a committed/offline catalog once established.
- Resale pricing is separate and must be cached/staggered rather than hundreds of Torn market calls per minute.
- Source disagreement lowers confidence; do not silently average incompatible states.

## API keys / secrets

- API keys remain local and ignored; never commit them.
- Settings masks the key by default.
- Never ask the user to paste the full key into chat.
- Do not broaden permissions for convenience.
- Use bounded `curl.exe` only where required on the target Windows host.
- Never put a key in process arguments or request URLs when stdin/header transport is available.

## Performance budget

- one-second Rainmeter work: local string/countdown/visibility only;
- primary updater/model/finalizer: about once per minute;
- broad shadow collection: no more often than 120 seconds unless revalidated;
- item catalog network maintenance: **not in the heartbeat**, explicit/manual only until the offline catalog workflow exists;
- no permanent background PowerShell/browser processes;
- updater executions stay serialized;
- graph generation remains compact.

## Current UI invariants

Until a deliberate multi-item release:

- dark charcoal theme;
- UK above Japan;
- local vector country flags, not claimed official Torn assets;
- header shows item name, profitability-colored foreign price and stock/out-of-stock state;
- only literal `Out of Stock` is red;
- out-of-stock text is `Out of Stock for h:mm since HH:mm`;
- plane icon on travel row;
- delivery-truck restock timing only when out of stock and predicted restock ETA exceeds flight time;
- hidden timing/history remains in tooltip;
- equal 8-hour graphs with 60-minute divisions;
- `Travel` header opens Torn travel;
- Settings remains top-right.

## Stable status codes

Keep logic keyed to codes, not display strings. Current vocabulary includes:

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

## Validation expectations

For collection/config/model changes:

- validate JSON;
- run PowerShell parser/static checks;
- exercise provider/metadata normalization from fixtures/synthetic payloads;
- prove country/item cycle isolation;
- prove primary markets are protected from duplicate shadow writes;
- prove metadata network maintenance stays outside `RunUpdate.ps1`;
- verify retention and ignored-runtime boundaries;
- run focused tests before broad suites;
- never claim live/Rainmeter validation until it runs on Windows.

Current focused expansion checks:

```powershell
.\tests\Validate-ShadowCollection.ps1
.\tests\Run-ShadowCollectionTests.ps1
.\tests\Validate-ItemMetadata.ps1
.\tests\Run-ItemMetadataTests.ps1
```

Use `tests/Run-All.ps1` only when a broad run is justified.

## Documentation / handoff

- Keep `docs/ARCHITECTURE.md` synchronized with durable decisions.
- Keep `docs/NEXT_CODEX_RUN.md` as the active rolling handoff.
- Keep `docs/IMPLEMENTATION_STATUS.md` factual about implemented vs validated behavior.
- Keep `Readme.md` human-readable/current.
- Update the rolling handoff rather than creating competing task documents.
