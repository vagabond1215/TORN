# Travel Assistant Architecture

## Purpose

Travel Assistant is a lightweight Rainmeter-facing Torn foreign-market decision system.

The established visible presentation currently remains **Xanax in the United Kingdom and Japan**, while the data layer now collects the entire observed foreign market before broader UI or route optimization is enabled.

The architecture separates three populations:

```text
COLLECTED opportunities
        !=
VISIBLE opportunities
        !=
OPTIMIZER candidates
```

Collection is broad. Visibility is controlled by user/context filters. Optimizer eligibility requires sufficiently modeled economics, availability and confidence.

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
canonical Torn item metadata
        ↓
per-market availability/depletion evidence
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

## Provider boundaries

Current live-stock order:

```text
Prometheus
    ↓ unavailable
YATA
    ↓ unavailable
cached/local state + stale/failure handling
```

Foreign-shop stock is crowd-sourced provider data. The application must not treat a static Wiki shop table as the authoritative live catalog.

Provider rows normalize to:

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

Provider-specific country codes or response shapes must not leak into the core history/cycle model.

### Torn item metadata

Canonical item names/categories come from Torn API v2 specific-item metadata:

```text
GET /v2/torn/{ids}/items?sort=ASC
```

This requires only a public-access key. Specific-ID requests populate item details when available, which matters for weapon category identity.

The metadata pass is bounded and low-frequency:

- default refresh interval: 6 hours;
- distinct provider-observed item IDs only;
- maximum 150 item IDs per request batch;
- every attempt, including partial/error responses, respects the refresh interval unless manually forced;
- API key is passed to `curl.exe` through stdin configuration / Authorization header, never in the command line or URL;
- failures are fail-soft and do not block the visible updater/finalizer/heartbeat.

Runtime metadata is stored under:

```text
engine-state.json -> itemMetadata
engine-state.json -> metadataCollection
```

Per-item metadata currently retains:

```text
itemId
name
type
subType
category
categoryResolved
isTradable
marketPrice
shops
fetchedAt
source
```

Canonical category handling:

- non-weapons use Torn `type` directly;
- `Weapon` items use `details.category` when available, preserving `Primary`, `Secondary`, `Melee`, or `Temporary`;
- a weapon with missing details stays broad `Weapon` with `categoryResolved=false`; do not guess.

Torn `value.market_price` is stored as metadata/reference only. It does **not** replace the existing Item Market resale-price profitability gate.

### Torn Item Market

Torn v2 Item Market remains the current resale reference for modeled opportunities. Broad full-market resale expansion must use a bounded staggered queue/cache rather than one request per item every minute.

On the validated Windows host, Torn API requests that hang under native Windows PowerShell are routed through bounded `curl.exe` with the key supplied through stdin configuration.

## Market identity

Durable foreign-market identity is:

```text
country + itemId
```

Examples:

```text
united_kingdom:206   Xanax
united_kingdom:266   Nessie Plushie
japan:206            Xanax
japan:277            Cherry Blossom
```

Names/categories are metadata. Historical isolation never depends on display names.

## Observation and history model

Observed transitions have strict semantics:

```text
0 -> positive = observed restock
positive -> 0 = observed sellout
```

Completed cycle schema:

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

Forecasts never populate these truth fields.

Default retention:

- raw/high-resolution observations: approximately 48 hours;
- completed cycles: approximately 90 days;
- visible graph window: 8 hours.

The 5-minute live-source stale guard is a recommendation-safety threshold, not history retention.

## Primary collector and shadow collector

### Established primary path

`UpdateTracker.ps1` remains the established UK/Japan Xanax collector/model path. It owns the currently visible state and graphs.

### Full-market shadow path

`ShadowCollector.ps1` is the current expansion bridge. It runs after the primary updater and before metadata/finalization.

```text
UpdateTracker
      ↓
ShadowCollector (fail-soft)
      ↓
ItemMetadata (fail-soft / low-frequency)
      ↓
FinalizeState
      ↓
heartbeat
```

Shadow behavior:

- default cadence: 120 seconds;
- all 11 Torn foreign destinations have `collect: true`;
- normalize every valid item row returned for each collection country;
- record every observed market in ignored `engine-state.json -> observedMarkets`;
- append non-primary raw history only when stock or foreign price changes;
- provider timestamp changes alone update freshness metadata without producing another raw observation;
- detect/write completed non-primary cycles using the same cycle contract;
- skip currently enabled-country + enabled-item primary markets so UK/Japan Xanax cannot be double-written;
- persist health/error counters under `engine-state.json -> shadowCollection`;
- fail softly so visible functionality continues on shadow failure.

### Validated full-market baseline

Target-Windows validation on 2026-08-21 confirmed:

```text
provider:             prometheus
countriesSeen:        11
marketsSeen:          232
observedMarkets:      232
observationsWritten:  51 on forced acceptance pass
cyclesCompleted:      0 on that initial pass
lastError:            empty
```

The extra foreign-stock fetch is accepted as a migration bridge. Long-term architecture should use one shared provider payload that fans out to all market observations after primary behavior equivalence is proven.

## Country configuration

`config/countries.json` separates:

```text
enabled = currently active visible/model country
collect = background data-collection country
```

Current visible countries:

```text
United Kingdom
Japan
```

Current collection countries:

```text
Mexico
Cayman Islands
Canada
Hawaii
United Kingdom
Argentina
Switzerland
Japan
China
United Arab Emirates
South Africa
```

The nine collection-only countries intentionally do not yet carry full recommendation economics. Background history does not require those fields. Add economics deliberately before they become recommendation/optimizer candidates.

## Item configuration

`config/items.json` separates:

```text
enabled
collect
visible
optimizerEligible
countries
category
```

Current explicit seeds:

```text
206 Xanax           Drug     visible / primary
266 Nessie Plushie  Plushie  UK hidden seed
277 Cherry Blossom  Flower   Japan hidden seed
```

The shadow collector does not use this short list as a whitelist. Unknown provider-observed IDs are collected and later enriched through Torn metadata.

## Availability model

Per-market evidence priority remains:

1. current live depletion when enough observations exist;
2. comparable historical cycles in the current/near foreign-price regime;
3. broader same-market history only with reduced confidence.

`SAFE_WINDOW` requires conservative historical support. Current depletion may shorten safety but never expand it beyond supported history.

`BEST_ODDS` is probabilistic and must not be rendered as safe.

Sparse, stale, incomparable or unsupported evidence yields no actionable departure advice.

## Profitability / resale architecture

For a modeled opportunity:

```text
netResalePrice = gross resale reference × (1 - selling fee)
netProfitPerItem = netResalePrice - foreignPrice
tripNet = (netProfitPerItem × usableCapacity) - effectiveTravelCost
```

Profitability suppresses departure timing but never suppresses useful collection/history.

Full-market expansion must **not** issue one Torn Item Market request per observed item every minute. Broad resale enrichment requires a bounded staggered queue/cache per distinct item ID.

## Capacity authority

Current general carrying capacity is derived primarily from current `/user/perks` state plus selected travel-mode base:

```text
Standard: 10
Airstrip/WLT/qualified Business: 15
```

Current suitcase/enhancer and suitable active general bonuses are applied without double-counting property/stock travel-method base effects.

A successfully synced current-capacity bonus is authoritative for general capacity and replaces legacy inferred company/faction capacity additions.

Company/star metadata remains relevant for non-capacity effects such as free Business Class.

Before multi-category economics becomes recommendation/optimizer eligible, capacity must be split into:

```text
general usable capacity
+ qualifying category-specific capacity
```

Required isolation:

- Flower Shop flower bonus applies only to Flower items;
- Toy Shop plushie bonus applies only to Plushie items;
- neither affects Xanax.

## Business travel safety branch

Ticket-funded Business economics remain unresolved.

Business may be used only when a known-free branch is established, currently modeled through 10-star Lingerie Store. Otherwise forced Business suppresses timing instead of assuming zero cost.

## Presentation architecture

Current compact cards remain stable during data-layer expansion.

Per destination:

```text
[flag] XANAX [profit-colored price] [stock / out-of-stock state]
[plane] flight time   [optional actionable delivery-truck restock]   [decision]
[8-hour stock graph]
```

Current presentation rules include:

- UK above Japan;
- equal graph widths;
- 8-hour graph window with 60-minute vertical divisions;
- price color: good/low-margin/bad economics;
- only the literal `Out of Stock` phrase is red;
- out-of-stock text format: `Out of Stock for h:mm since HH:mm`;
- delivery-truck restock indicator appears only while out of stock when predicted restock ETA exceeds flight time;
- hidden timing/history details remain in tooltips;
- `Travel` header opens Torn travel;
- Settings remains top-right.

## Future filters and travel context

Country/category filters act only on **visible opportunities**. They never change collection.

Future Torn travel-state normalization should expose:

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

The plane icon remains unchanged; only time semantics change.

## Future `Optimal` mode

`Optimal` is a separate scheduling layer above per-opportunity modeling.

It must evaluate a bounded planning horizon and compare:

- multiple shorter trips;
- one or two longer trips;
- mixed-country sequences;
- capacity/category effects;
- travel costs/fees;
- availability/restock/depletion evidence;
- confidence and stale-data guards;
- opportunity cost of choosing one route over another.

Do not implement `Optimal` as a simple sort by profit/item or profit/trip.

## Runtime / performance

Every second:

- local Lua/countdown/visibility/string work only.

Approximately every minute:

- serialized primary updater/model/finalizer.

Approximately every two minutes during the expansion bridge:

- fail-soft all-country shadow stock collection.

Approximately every six hours:

- fail-soft canonical Torn item metadata refresh for the distinct observed item IDs.

Do not add permanent background PowerShell/browser processes. Keep ignored state bounded and continue pruning shared observation/cycle stores.

## Validation boundary

Shadow collection has passed focused deterministic tests and live target-Windows acceptance.

Focused metadata tests:

```powershell
.\tests\Validate-ItemMetadata.ps1
.\tests\Run-ItemMetadataTests.ps1
```

These must pass on Windows, followed by one forced live metadata refresh and inspection of `metadataCollection` / `itemMetadata`, before metadata enrichment is treated as operationally accepted.
