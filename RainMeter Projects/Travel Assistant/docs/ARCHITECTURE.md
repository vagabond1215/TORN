# Travel Assistant Architecture

## Purpose

Travel Assistant is a lightweight Rainmeter-facing Torn foreign-market decision system. The visible UI remains the validated UK/Japan Xanax proof while the data layer expands across the entire observed foreign market.

The architecture keeps three populations separate:

```text
COLLECTED provider rows
        !=
ACTIVE market candidates
        !=
VISIBLE opportunities
        !=
OPTIMIZER candidates
```

Collection is broad. Provider rows are then checked against verified market-validity exceptions. Visibility is presentation/context filtered. Optimizer eligibility requires sufficiently modeled economics, availability, market validity and confidence.

## Layering

```text
Live foreign-stock providers
        ↓
provider normalization
        ↓
provider-observed country + itemId rows
        ↓
verified market-validity overrides
        ↓
active-market bounded history / cycle detection
        ↓
local offline item metadata catalog
        ↓
resale + capacity/economics enrichment
        ↓
per-opportunity recommendation state
        ↓
future filter / travel-context layer
        ↓
future route optimizer
        ↓
compact generated state
        ↓
Rainmeter presentation
```

Settings and current user travel profile are side inputs to economics/presentation. They never rewrite observed history.

## Live provider boundary

Current foreign-stock order:

```text
Prometheus
    ↓ unavailable
YATA
    ↓ unavailable
cached/local state + stale/failure handling
```

Foreign-shop stock is crowd-sourced provider data. A provider row proves only that the provider currently reports that `country + itemId` pair; it does **not** by itself prove the item remains purchasable in that country.

Static Wiki destination tables are documentation/cross-check material and may also contain stale rows. Item-specific histories/current destination lists can be used to establish explicit verified exceptions.

Normalized observation schema:

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

Provider-specific country codes and response shapes stop at the adapter boundary.

## Market identity, validity and history

Durable market identity is:

```text
country + itemId
```

Examples:

```text
united_kingdom:206
united_kingdom:266
japan:206
japan:277
```

Names/categories are metadata and never define historical identity.

`config/foreign-market-overrides.json` carries explicit verified exceptions where a provider still reports a legacy market. Current verified inactive pairs are:

```text
mexico:21
mexico:232
mexico:327
united_arab_emirates:383
united_arab_emirates:440
```

For these rows:

- provider metadata is retained in `observedMarkets`;
- the market is annotated `catalogActive=false` / `catalogStatus=legacy_removed`;
- new shadow observation/cycle writes are suppressed;
- later display/resale/optimizer stages must treat the market as ineligible;
- existing historical rows are retained.

Observed truth semantics for active markets:

```text
0 -> positive = observed restock
positive -> 0 = observed sellout
```

Completed cycles retain country/item identity, foreign-price regime, restock quantity/timestamps, availability duration, prior sellout and source provenance. Forecasts never populate historical truth fields.

Default retention:

- raw/high-resolution observations: approximately 48 hours;
- completed cycles: approximately 90 days;
- visible graph window: 8 hours.

The five-minute live-source stale guard is a recommendation-safety threshold, not history retention.

## Primary and shadow collectors

`UpdateTracker.ps1` remains the established visible UK/Japan Xanax collector/model path.

`ShadowCollector.ps1` is the expansion bridge. It observes every valid provider row for all 11 foreign countries, protects current primary markets from duplicate writes, and excludes verified inactive legacy markets before new background history/cycle writes.

Current production heartbeat path:

```text
UpdateTracker
      ↓
ShadowCollector (fail-soft)
      ↓
LocalCatalog (fail-soft / local only)
      ↓
FinalizeState
      ↓
heartbeat
```

Shadow behavior:

- default cadence: 120 seconds;
- all 11 foreign destinations have `collect: true`;
- all valid provider rows are normalized locally;
- all provider rows remain tracked in ignored `engine-state.json -> observedMarkets`;
- `config/foreign-market-overrides.json` identifies verified inactive market pairs;
- inactive pairs are skipped before new raw history/cycle writes;
- raw history for active markets is appended only when stock or foreign price changes;
- provider timestamp changes alone update freshness metadata without another raw observation;
- non-primary active restock/sellout cycles use the same cycle contract;
- enabled-country + enabled-item primary markets are skipped by shadow writes;
- failures are recorded locally and fail soft.

Accepted target-Windows provider baseline on 2026-08-21:

```text
provider:        prometheus
countriesSeen:   11
marketsSeen:     232 provider rows
observedMarkets: 232
provider names:  232 / 232
item IDs:        202 distinct
lastError:       empty
```

After the verified legacy override implementation, the expected current split is:

```text
raw provider rows: 232
legacy rows:         5
active candidates: 227
```

These are current live counts, not permanent schema constants.

The separate shadow provider request is a migration bridge. Long-term architecture should share one foreign-stock payload after primary behavior equivalence is proven.

## Item metadata architecture

Catalog metadata must not block the Rainmeter heartbeat.

Three Torn catalog strategies were tested on the target Windows host and all timed out before returning metadata:

```text
v2 specific-items | 150 IDs | 20s
v2 specific-items |  40 IDs | 30s
classic torn/items bulk      | 12s
```

Therefore `ItemMetadata.ps1` is **manual/maintenance-only** and is not invoked by `RunUpdate.ps1`.

Runtime metadata lives under:

```text
engine-state.json -> itemMetadata
engine-state.json -> localCatalog
engine-state.json -> metadataCollection
```

### Local offline catalog

`LocalCatalog.ps1` performs no network access. It collapses provider rows by `itemId`, retains provider names/country membership and merges committed local metadata.

Current precedence:

```text
richer manually acquired Torn metadata
        >
config/items.json seed
        >
verified item override
        >
197-ID offline YATA category snapshot
        >
provider name + Unknown category
```

Current committed reference files:

```text
config/foreign-item-categories.json
config/foreign-market-overrides.json
```

`foreign-item-categories.json` contains the 197-ID YATA-derived foreign-category snapshot and normalizes:

```text
Defensive -> Armor
Other     -> Miscellaneous
```

`foreign-market-overrides.json` contains five individually verified item repairs plus per-country inactive-market status. Two canonical-name corrections are important:

```text
327 Blank Tokens   -> Blank Casino Chips
383 Platinum PDA   -> Digital Organizer
```

The target provider currently exposes 202 distinct item IDs. The 197-ID snapshot plus five verified item overrides are intended to make current category coverage 202/202 without runtime Torn catalog access.

### Committed seeds

`config/items.json` contains explicit metadata for currently promoted/seeded items:

```text
206 Xanax          | Drug
266 Nessie Plushie | Plushie
277 Cherry Blossom | Flower
```

When `ItemMetadata.ps1` is run manually, those rows are imported before any optional network attempt with:

```text
source=config_seed
marketPrice=0
tradabilityKnown=false
```

A successful future maintenance refresh may replace a local row with richer canonical metadata. A network failure must never erase committed local metadata.

Do not infer unknown categories from item names. Do not let metadata maintenance delays affect polling, finalization or heartbeat health.

## Country/item configuration

`config/countries.json` separates:

```text
enabled = current visible/model country
collect = background observation country
```

UK and Japan remain visible/model-enabled. All 11 Torn foreign destinations are observed in the background.

`config/items.json` separates:

```text
enabled
collect
visible
optimizerEligible
countries
category
```

The explicit item list is not a whitelist for shadow observation. Unknown provider-observed IDs still enter `observedMarkets`; verified inactive market overrides determine whether they receive continuing learning/history.

## Availability model

Evidence priority remains:

1. current live depletion when adequately sampled;
2. comparable historical cycles in the current/near foreign-price regime;
3. broader same-market history only with reduced confidence.

`SAFE_WINDOW` requires conservative historical support. Current depletion may shorten safety but never expand it beyond supporting history. `BEST_ODDS` remains probabilistic and must not be rendered as safe.

Sparse, stale, incomparable, inactive or unsupported evidence yields no actionable departure advice.

## Profitability / resale

For an active modeled opportunity:

```text
netResalePrice = gross resale reference × (1 - selling fee)
netProfitPerItem = netResalePrice - foreignPrice
tripNet = (netProfitPerItem × usableCapacity) - effectiveTravelCost
```

Profitability suppresses departure timing, not collection/history for active markets.

Broad resale expansion must use a bounded staggered cache/queue. Never issue one Torn Item Market request per observed item every minute. `catalogActive=false` markets must not receive resale/optimizer work.

## Capacity authority

Current general carrying capacity prefers current `/user/perks` plus selected mode base:

```text
Standard: 10
Airstrip/WLT/qualified Business: 15
```

Current suitcase/general bonuses are applied without double-counting property/stock travel-method base effects. A synced current-capacity bonus is authoritative for general capacity.

Before multi-category economics becomes eligible, capacity must split into:

```text
general usable capacity
+ qualifying category-specific capacity
```

Required isolation:

- Flower Shop flower capacity applies only to Flower items;
- Toy Shop plushie capacity applies only to Plushie items;
- neither affects Xanax.

Ticket-funded Business remains unresolved. Business timing is allowed only when a known-free branch is established.

## Presentation

Current compact cards stay stable until a deliberate multi-item UI release.

Per destination:

```text
[flag] XANAX [profit-colored price] [stock / out-of-stock state]
[plane] flight time   [optional actionable delivery-truck restock]   [decision]
[8-hour stock graph]
```

Current invariants include UK above Japan, equal graph widths, 60-minute grid divisions, profit-colored price, only the literal `Out of Stock` phrase red, `Out of Stock for h:mm since HH:mm`, actionable delivery-truck restock timing, clickable `Travel` header and top-right Settings.

## Future filters and travel context

Country/category filters affect **visibility only** and never stop background observation/learning of other active markets.

Future travel-state normalization should expose:

```text
travelState
destinationCountryId
departedAt
arrivalAt
timeLeft
travelMethod
```

Intended behavior:

- at home: normal filtered opportunities and configured route duration;
- outbound: force target-country items and show arrival countdown instead of static flight duration;
- abroad: continue showing that country's active items;
- returning to Torn: release forced foreign-country presentation.

The plane icon stays; only time semantics change.

## Future `Optimal` mode

`Optimal` is a scheduling layer above per-opportunity modeling. It must compare multiple short trips, fewer long trips and mixed-country sequences over a bounded planning horizon while accounting for market validity, capacity, fees/costs, availability/depletion evidence, confidence/freshness and opportunity cost.

Do not implement `Optimal` as a simple sort by profit/item or profit/trip.

## Runtime / performance

Every second:

- local Lua/countdown/visibility/string work only.

Approximately every minute:

- serialized visible updater/model/finalizer.

Approximately every two minutes during the expansion bridge:

- fail-soft all-country shadow stock observation.

Catalog metadata network maintenance:

- **not part of the Rainmeter heartbeat**;
- explicit/manual only; normal category/market validity comes from committed local files.

Do not add permanent background PowerShell/browser processes. Keep runtime state bounded and continue pruning shared observation/cycle stores.

## Distribution

The `.rmskin` builder is whitelist-based and must include both committed offline catalog files while excluding local credentials/runtime state:

```text
config/foreign-item-categories.json
config/foreign-market-overrides.json
```

Recipient-local `settings.local.json`, runtime history/state and generated files must never be packaged.

## Validation boundary

Shadow collection has passed focused deterministic tests and live target-Windows acceptance for broad provider observation. Local catalog mechanics have also passed target-Windows focused validation.

The current narrow acceptance adds:

```powershell
.\tests\Validate-ShadowCollection.ps1
.\tests\Run-ShadowCollectionTests.ps1
.\tests\Validate-LocalCatalog.ps1
.\tests\Run-LocalCatalogTests.ps1
.\tests\Validate-RainmeterSkin.ps1
```

It must prove:

- 202/202 current item categories resolve locally;
- five verified provider rows are annotated inactive;
- those rows remain observable for provenance;
- those rows are skipped before new shadow history/cycle writes;
- current UK/Japan Xanax presentation remains unchanged.

A manual Torn metadata timeout is not a runtime-health failure. Future resale/optimizer work must consume only active market candidates.
