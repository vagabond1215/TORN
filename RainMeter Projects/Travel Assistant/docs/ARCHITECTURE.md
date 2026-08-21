# Travel Assistant Architecture

## Purpose

Travel Assistant is a lightweight Rainmeter-facing Torn foreign-market decision system. The visible UI remains the validated UK/Japan Xanax proof while the data layer expands across the entire observed foreign market.

The architecture keeps four populations separate:

```text
COLLECTED provider rows
        !=
ACTIVE market candidates
        !=
VISIBLE opportunities
        !=
OPTIMIZER candidates
```

Collection is broad. Provider rows are checked against verified market-validity exceptions. Visibility is presentation/context filtered. Optimizer eligibility requires sufficiently modeled economics, availability, market validity and confidence.

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
bounded/staggered resale cache
        ↓
category-aware capacity/economics
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

Foreign-shop stock is crowd-sourced provider data. A provider row proves only that the provider reports that `country + itemId` pair; it does **not** by itself prove the item remains purchasable in that country.

Static Wiki destination tables are documentation/cross-check material and may also contain stale rows. Item-specific history/current destination evidence can establish explicit verified exceptions.

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
- later display/resale/optimizer stages treat the market as ineligible;
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

The visible production pass is:

```text
UpdateTracker
      ↓
ShadowCollector (fail-soft)
      ↓
LocalCatalog (fail-soft / local only)
      ↓
FinalizeState
      ↓
visible heartbeat
```

Current accepted target-Windows provider/catalog baseline on 2026-08-21:

```text
provider:                      prometheus
countriesSeen:                 11
provider rows:                 232
legacy rows:                     5
active country-item markets:   227
provider names:                232 / 232
item IDs:                      202 distinct
categories resolved:           202 / 202
lastError:                     empty
```

These are current live counts, not permanent constants.

The separate shadow provider request is a migration bridge. Long-term architecture should share one foreign-stock payload after primary behavior equivalence is proven.

## Item metadata architecture

Catalog metadata must not block the Rainmeter heartbeat.

Three Torn catalog strategies were tested on the target Windows host and all timed out before returning metadata:

```text
v2 specific-items | 150 IDs | 20s
v2 specific-items |  40 IDs | 30s
classic torn/items bulk      | 12s
```

Therefore `ItemMetadata.ps1` is manual/maintenance-only and is not invoked by `RunUpdate.ps1`.

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

Committed reference files:

```text
config/foreign-item-categories.json
config/foreign-market-overrides.json
```

The target provider currently exposes 202 distinct item IDs. The 197-ID snapshot plus five verified item overrides resolve the current 202/202 category set without runtime Torn catalog access.

Canonical corrections retained separately from provider aliases include:

```text
327 Blank Tokens -> Blank Casino Chips
383 Platinum PDA -> Digital Organizer
```

Do not infer unknown categories from item names. Future newly observed IDs stay unresolved until locally verified.

## Resale-price architecture

The current visible Xanax path already maintains a short-lived Torn Item Market cache used by `FinalizeState.ps1`. Broad-market expansion must not turn that into hundreds of synchronous API calls.

`ResaleQueue.ps1` therefore populates the shared `engine-state.json -> resaleCache` gradually.

### Active-item scope

The queue derives distinct item IDs only from provider rows that remain active:

```text
catalogActive != false
and
catalogStatus != legacy_removed
```

A legacy-only item receives no new broad valuation work. If an item appears in both an inactive legacy market and another active market, its active relationship still makes the item eligible for resale pricing.

### Runtime order

Broad resale runs **after** `FinalizeState` and the visible heartbeat:

```text
UpdateTracker
ShadowCollector
LocalCatalog
FinalizeState
visible heartbeat
ResaleQueue
```

This introduces a deliberate one-update lag before a newly fetched broad resale row could affect future generalized economics, while protecting visible heartbeat health from a lower-priority pricing request.

### Queue bounds

Default broad-population policy:

```text
minimum attempt interval: 60s
cache freshness target:    6h
failed-item backoff:        1h
per-request timeout:        6s
requests per run path:      1
```

At roughly 197 active distinct items, one successful request/minute can populate an initially empty active catalog in about 3.3 hours of loaded-skin runtime. This is population/reference freshness, not the final optimizer refresh policy.

Future optimization may prioritize a much smaller set of economically competitive candidates for more frequent refresh while retaining slower broad coverage.

### Candidate ordering

The queue:

- skips fresh resale cache rows;
- skips recent failures still in backoff;
- prioritizes never-priced eligible items;
- then refreshes stale cached items;
- advances past failures rather than allowing one bad item to block catalog population.

### Transport and cache schema

The queue uses:

```text
GET https://api.torn.com/v2/market/{itemId}/itemmarket?limit=1
```

through bounded `curl.exe --config -` because the target Windows host has validated curl for Torn Item Market while native PowerShell can hang.

The API key is supplied only through an Authorization header written to curl stdin; never through request URLs or process arguments.

Successful cache entry:

```text
price
lowest
average
fetchedAt
source=torn_itemmarket
```

The lowest listing is preferred, with Torn's average as fallback. Missing/zero price remains unresolved and is never treated as zero economics.

Queue health is stored under:

```text
engine-state.json -> resaleQueue
```

with aggregate active/priced/fresh/stale counts plus per-item attempt/backoff state.

The current visible Xanax updater retains its existing independent/fresher cache behavior; broad queue policy does not relax current departure gating.

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

The explicit item list is not a whitelist for shadow observation. Unknown provider-observed IDs still enter `observedMarkets`; verified inactive market overrides determine whether they receive continuing learning/history/economics work.

## Availability model

Evidence priority remains:

1. current live depletion when adequately sampled;
2. comparable historical cycles in the current/near foreign-price regime;
3. broader same-market history only with reduced confidence.

`SAFE_WINDOW` requires conservative historical support. Current depletion may shorten safety but never expand it beyond supporting history. `BEST_ODDS` remains probabilistic and must not be rendered as safe.

Sparse, stale, incomparable, inactive or unsupported evidence yields no actionable departure advice.

## Profitability / economics

For an active modeled opportunity:

```text
netResalePrice = gross resale reference × (1 - selling fee)
netProfitPerItem = netResalePrice - foreignPrice
tripNet = (netProfitPerItem × usableCapacity) - effectiveTravelCost
```

Profitability suppresses departure timing, not learning/history for active markets.

`catalogActive=false` markets must not receive resale/economics/optimizer work.

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

Country/category filters affect visibility only and never stop background observation/learning of other active markets.

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

- serialized visible updater/model/finalizer;
- at most one lower-priority broad resale request after the visible heartbeat.

Approximately every two minutes during the expansion bridge:

- fail-soft all-country shadow stock observation.

Catalog metadata network maintenance:

- not part of the Rainmeter heartbeat;
- explicit/manual only; normal category/market validity comes from committed local files.

Do not add permanent background PowerShell/browser processes. Keep runtime state bounded and continue pruning shared observation/cycle stores.

## Distribution

The `.rmskin` builder is whitelist-based and includes both committed offline catalog files while excluding local credentials/runtime state:

```text
config/foreign-item-categories.json
config/foreign-market-overrides.json
```

All `.ps1`/`.lua` runtime scripts, including `ResaleQueue.ps1`, are staged from `@Resources/Scripts` by the builder.

Recipient-local `settings.local.json`, runtime history/state and generated files must never be packaged.

## Validation boundary

Shadow collection and the complete current offline catalog have passed focused deterministic tests and target-Windows live acceptance.

Current resale-queue acceptance is intentionally narrow:

```powershell
.\tests\Validate-ResaleQueue.ps1
.\tests\Run-ResaleQueueTests.ps1
.\tests\Validate-RainmeterSkin.ps1
```

Then run one explicit `ResaleQueue.ps1 -Force` attempt and inspect only queue/cache health. Do not claim broad live pricing acceptance until that target-Windows evidence exists.
