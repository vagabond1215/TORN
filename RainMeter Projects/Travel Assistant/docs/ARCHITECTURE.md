# Travel Assistant Architecture

## Purpose

Travel Assistant is a lightweight Rainmeter-facing Torn foreign-market decision system.

The established visible presentation currently remains **Xanax in the United Kingdom and Japan**, but the system is now intentionally expanding its data layer across the entire foreign market before broadening the UI or enabling route optimization.

The architecture separates three populations:

```text
COLLECTED opportunities
        !=
VISIBLE opportunities
        !=
OPTIMIZER candidates
```

This separation is fundamental. Collection should be broad; visibility is user/context filtered; optimization requires sufficiently modeled economics and availability.

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
per-market availability/depletion evidence
        ↓
item metadata + resale + capacity/economics enrichment
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

Provider rows are normalized at the adapter boundary to:

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

Torn v2 Item Market supplies resale references for modeled items when a suitable local key is configured. On the validated Windows host, Torn API requests that hang under native Windows PowerShell are routed through bounded `curl.exe`; this workaround stays provider-specific.

## Market identity

The durable foreign-market identity is:

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

Names/categories are metadata. Historical isolation must never depend on display names.

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

The initial expansion intentionally does not rewrite the primary path. `ShadowCollector.ps1` is a migration bridge that runs after the primary updater and before finalization.

```text
UpdateTracker
      ↓
ShadowCollector (fail-soft)
      ↓
FinalizeState
      ↓
heartbeat
```

Shadow collector behavior:

- default cadence: 120 seconds;
- all 11 Torn foreign destinations configured with `collect: true`;
- normalize every valid item row returned for each collection country;
- record every observed market in ignored `engine-state.json -> observedMarkets`;
- append changed non-primary observations to the same bounded raw history;
- detect/write completed non-primary cycles using the same cycle contract;
- skip currently enabled-country + enabled-item primary markets so UK/Japan Xanax cannot be double-written by this bridge;
- persist health/error counters under `engine-state.json -> shadowCollection`;
- fail softly so the visible updater/finalizer/heartbeat continues even when the shadow path fails.

The extra provider fetch is accepted only as an initial migration boundary. Long-term architecture should use one shared live provider payload that fans out to all market observations after deterministic equivalence with the primary path is proven.

## Country configuration

`config/countries.json` now uses two separate concepts:

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

The nine newly added collection-only countries intentionally do not yet carry full travel-time/cost/capacity economics. Background history does not require those fields. Add economics deliberately before those markets become recommendation/optimizer candidates.

## Item configuration

`config/items.json` begins separating:

```text
enabled
collect
visible
optimizerEligible
countries
category
```

Current explicit metadata seeds:

```text
206 Xanax          Drug     visible / primary
266 Nessie Plushie Plushie  UK shadow seed
277 Cherry Blossom Flower   Japan shadow seed
```

The shadow collector does not use this short metadata list as a whitelist. Unknown provider-observed item IDs are still collected. Canonical metadata/category enrichment is a later pass.

This avoids losing history when Torn's foreign inventory changes before the committed metadata catalog is updated.

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

Profitability suppresses departure timing but never suppresses useful data collection/history.

Full-market expansion must **not** issue one Torn Item Market request per observed item every minute. Future broad resale enrichment requires a bounded staggered queue/cache per distinct item ID.

## Capacity authority

Current general carrying capacity is derived primarily from current `/user/perks` state plus selected travel-mode base:

```text
Standard: 10
Airstrip/WLT/qualified Business: 15
```

Current suitcase/enhancer and suitable active general bonuses are applied without double-counting property/stock travel-method base effects.

A successfully synced current-capacity bonus is authoritative for general capacity and replaces legacy inferred company/faction capacity additions.

Company/star metadata remains relevant for non-capacity effects such as free Business Class.

Before multi-category economics becomes recommendation/optimizer eligible, capacity must be split conceptually into:

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

The current compact cards remain stable during the shadow-collection rollout.

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

Country/category filters act only on **visible opportunities**. They must not change collection.

Future Torn travel-state normalization should expose a small local contract such as:

```text
travelState
destinationCountryId
departedAt
arrivalAt
timeLeft
travelMethod
```

Intended presentation behavior:

- at home: show normal filtered opportunities and configured route duration;
- outbound: force visible items to the target country and use arrival countdown instead of static flight duration;
- abroad: continue showing that country's items;
- returning to Torn: release forced foreign-country presentation.

The plane icon can remain unchanged; only the displayed time semantics change.

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

Approximately every two minutes during the initial expansion:

- fail-soft all-country shadow stock collection.

Do not add permanent background PowerShell/browser processes. Keep ignored state bounded and continue pruning the shared observation/cycle stores.

## Validation boundary

Focused shadow tests:

```powershell
.\tests\Validate-ShadowCollection.ps1
.\tests\Run-ShadowCollectionTests.ps1
```

They verify configuration coverage, primary-market protection, provider-row normalization and market/cycle identity isolation.

Windows/Rainmeter live validation remains required before the shadow rollout is considered operationally accepted. Connector-only work must not claim that validation has occurred.
