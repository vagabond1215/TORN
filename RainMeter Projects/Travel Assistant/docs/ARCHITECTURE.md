# Travel Assistant Architecture

## Purpose

Travel Assistant is a lightweight Rainmeter-facing Torn foreign-market decision system. The visible UI remains the validated UK/Japan Xanax proof while the data layer expands across the entire observed foreign market.

The architecture keeps three populations separate:

```text
COLLECTED opportunities
        !=
VISIBLE opportunities
        !=
OPTIMIZER candidates
```

Collection is broad. Visibility is presentation/context filtered. Optimizer eligibility requires sufficiently modeled economics, availability and confidence.

## Layering

```text
Live foreign-stock providers
        ↓
provider normalization
        ↓
country + itemId observations
        ↓
bounded raw history / observed cycle detection
        ↓
local item metadata catalog
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

Foreign-shop stock is crowd-sourced provider data. Static Wiki shop tables are documentation/cross-check material, not the authority for whether a market row is currently observed.

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

## Market identity and history

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

Observed truth semantics:

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

`ShadowCollector.ps1` is the expansion bridge and collects every valid provider row for all 11 foreign countries while protecting current primary markets from duplicate history writes.

Current production heartbeat path:

```text
UpdateTracker
      ↓
ShadowCollector (fail-soft)
      ↓
FinalizeState
      ↓
heartbeat
```

Shadow behavior:

- default cadence: 120 seconds;
- all 11 foreign destinations have `collect: true`;
- all valid provider rows are normalized locally;
- observed markets are tracked in ignored `engine-state.json -> observedMarkets`;
- raw history is appended only when stock or foreign price changes;
- provider timestamp changes alone update freshness metadata without another raw observation;
- non-primary restock/sellout cycles use the same cycle contract;
- enabled-country + enabled-item primary markets are skipped by shadow writes;
- failures are recorded locally and fail soft.

Validated target-Windows baseline on 2026-08-21:

```text
provider:             prometheus
countriesSeen:        11
marketsSeen:          232
observedMarkets:      232
observationsWritten:  51 on acceptance pass
cyclesCompleted:      0 on that early pass
lastError:            empty
```

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
engine-state.json -> metadataCollection
```

### Committed metadata fallback

`config/items.json` contains explicit committed metadata for currently promoted/seeded items. When `ItemMetadata.ps1` is run manually, those rows are imported before any optional network attempt with:

```text
source=config_seed
marketPrice=0
tradabilityKnown=false
```

Current seeds:

```text
206 Xanax          | Drug
266 Nessie Plushie | Plushie
277 Cherry Blossom | Flower
```

A successful future maintenance refresh may replace a seed row with richer canonical metadata. A network failure must never erase committed seed metadata.

### Full catalog direction

The full provider-observed catalog should ultimately use a **committed/offline metadata catalog** refreshed outside the Rainmeter heartbeat. Item names/categories change slowly and are appropriate packaged reference data; stock/foreign price remain live provider data.

Do not infer unknown categories. Do not let metadata maintenance delays affect polling, finalization or heartbeat health.

## Country/item configuration

`config/countries.json` separates:

```text
enabled = current visible/model country
collect = background collection country
```

UK and Japan remain visible/model-enabled. All 11 Torn foreign destinations collect in the background.

`config/items.json` separates:

```text
enabled
collect
visible
optimizerEligible
countries
category
```

The explicit item list is not a whitelist for shadow collection. Unknown provider-observed IDs continue accumulating history even before catalog enrichment exists.

## Availability model

Evidence priority remains:

1. current live depletion when adequately sampled;
2. comparable historical cycles in the current/near foreign-price regime;
3. broader same-market history only with reduced confidence.

`SAFE_WINDOW` requires conservative historical support. Current depletion may shorten safety but never expand it beyond supporting history. `BEST_ODDS` remains probabilistic and must not be rendered as safe.

Sparse, stale, incomparable or unsupported evidence yields no actionable departure advice.

## Profitability / resale

For a modeled opportunity:

```text
netResalePrice = gross resale reference × (1 - selling fee)
netProfitPerItem = netResalePrice - foreignPrice
tripNet = (netProfitPerItem × usableCapacity) - effectiveTravelCost
```

Profitability suppresses departure timing, not collection/history.

Broad resale expansion must use a bounded staggered cache/queue. Never issue one Torn Item Market request per observed item every minute.

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

Country/category filters affect **visibility only** and never stop background collection.

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
- abroad: continue showing that country's items;
- returning to Torn: release forced foreign-country presentation.

The plane icon stays; only time semantics change.

## Future `Optimal` mode

`Optimal` is a scheduling layer above per-opportunity modeling. It must compare multiple short trips, fewer long trips and mixed-country sequences over a bounded planning horizon while accounting for capacity, fees/costs, availability/depletion evidence, confidence/freshness and opportunity cost.

Do not implement `Optimal` as a simple sort by profit/item or profit/trip.

## Runtime / performance

Every second:

- local Lua/countdown/visibility/string work only.

Approximately every minute:

- serialized visible updater/model/finalizer.

Approximately every two minutes during the expansion bridge:

- fail-soft all-country shadow stock collection.

Catalog metadata network maintenance:

- **not part of the Rainmeter heartbeat**;
- explicit/manual only until a committed offline catalog workflow is established.

Do not add permanent background PowerShell/browser processes. Keep runtime state bounded and continue pruning shared observation/cycle stores.

## Validation boundary

Shadow collection has passed focused deterministic tests and live target-Windows acceptance.

Metadata-focused checks now verify both the committed seed fallback and the absence of metadata network maintenance from `RunUpdate.ps1`:

```powershell
.\tests\Validate-ItemMetadata.ps1
.\tests\Run-ItemMetadataTests.ps1
```

A manual Torn metadata timeout is no longer a runtime-health failure. Full-catalog completion depends on establishing the offline/committed catalog workflow, not on increasing Rainmeter-side request timeouts.
