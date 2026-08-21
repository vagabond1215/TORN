# Travel Assistant Architecture

## Purpose

Travel Assistant is a lightweight Rainmeter-facing Torn foreign-market decision system. It separates broad observation from current market validity, presentation, and eventual route optimization.

```text
COLLECTED provider rows
        !=
ACTIVE market candidates
        !=
VISIBLE opportunities
        !=
OPTIMIZER candidates
```

The last validated visible baseline is UK/Japan Xanax. The current committed `0.3.0` release candidate adds UK Nessie Plushie and Japan Cherry Blossom as presentation-only secondary rows pending target-Windows/Rainmeter acceptance.

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
primary per-opportunity recommendation state
        ↓
local visible-item enrichment
        ↓
future filter / travel-context layer
        ↓
future route optimizer
        ↓
Rainmeter presentation
```

Settings/current travel profile are side inputs. They never rewrite observed history.

## Provider boundary and market identity

Current live stock preference:

```text
Prometheus
    ↓ unavailable
YATA
    ↓ unavailable
cached/local state + stale/failure handling
```

Market identity is always:

```text
country + itemId
```

A provider row proves only that the provider reports that pair. It does not prove the relationship is still purchasable. Verified exceptions in `config/foreign-market-overrides.json` supersede provider presence for learning/display/resale/optimizer eligibility while preserving provenance.

Current verified inactive pairs:

```text
mexico:21
mexico:232
mexico:327
united_arab_emirates:383
united_arab_emirates:440
```

For inactive rows:

- keep `observedMarkets` provenance;
- annotate `catalogActive=false` / `catalogStatus=legacy_removed`;
- suppress new shadow observations/cycles;
- suppress display/resale/optimizer work;
- retain existing history.

Normalized active observation:

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

Observed truth:

```text
0 -> positive = observed restock
positive -> 0 = observed sellout
```

Forecasts never become history.

Retention:

- raw observations: ~48h;
- completed cycles: ~90d;
- current graph: 8h.

The 5-minute stale guard is a recommendation-safety threshold, not retention.

## Primary and shadow collection

`UpdateTracker.ps1` remains the established primary UK/Japan Xanax collector/model path.

`ShadowCollector.ps1` observes all 11 countries at a default 120-second cadence and protects current primary markets from duplicate history writes.

Accepted target-Windows baseline:

```text
provider:                    prometheus
countries:                   11
provider country-item rows:  232
verified legacy rows:          5
active markets:              227
provider names:              232 / 232
item IDs:                    202
categories resolved:         202 / 202
```

These are live baseline values, not constants.

## Offline catalog

Torn catalog network metadata must not block Rainmeter. The target host timed out on all attempted catalog strategies, so `ItemMetadata.ps1` is manual/maintenance-only.

`LocalCatalog.ps1` performs no network work. Current precedence:

```text
richer manually acquired Torn metadata
        >
config/items.json seed
        >
verified item override
        >
197-ID offline YATA category snapshot
        >
provider name + Unknown
```

Committed references:

```text
config/foreign-item-categories.json
config/foreign-market-overrides.json
```

Current 202 observed IDs are fully resolved locally. Newly observed unknown IDs remain unresolved until verified; names are not used to guess categories.

## Resale-price architecture

The primary Xanax updater keeps its independent/fresher Torn Item Market path.

`ResaleQueue.ps1` populates the shared broad `resaleCache` for distinct active items only.

Queue defaults:

```text
minimum interval:    60s
broad freshness:      6h
failure backoff:       1h
request timeout:       6s
requests/run path:     1
```

Transport is bounded `curl.exe --config -`; API key is supplied in the Authorization header through stdin, never URL/process arguments.

Successful row:

```text
price
lowest
average
fetchedAt
source=torn_itemmarket
```

Missing/zero price remains unresolved.

Candidate ordering:

1. skip fresh cache rows;
2. skip items still in failure backoff;
3. among eligible rows, prioritize configured `visible=true` items;
4. then normal unpriced/stale catalog ordering.

Visible priority changes ordering only; it does not increase request frequency.

A target-Windows live queue request has succeeded with `status=OK`.

## Capacity/economics authority

General capacity prefers current `/user/perks` plus travel-mode base:

```text
Standard: 10
Airstrip/WLT/qualified Business: 15
```

A synced current-capacity bonus is authoritative for **general/Xanax** capacity and prevents general company/faction double counting.

Accepted current example:

```text
Airstrip general/Xanax = 18
Standard general/Xanax = 13
```

Category-specific company effects excluded from that general number are added only for matching items:

```text
Flower Shop 7★ -> +5 Flower
Toy Shop    7★ -> +5 Plushie
```

Thus:

```text
qualifying Airstrip Flower/Plushie = 23
qualifying Standard Flower/Plushie = 18
Xanax remains 18 / 13
```

A positive `profitability.capacityOverride` remains authoritative.

For a modeled active opportunity:

```text
netResalePrice = gross resale reference × (1 - selling fee)
netProfitPerItem = netResalePrice - foreignPrice
tripNet = (netProfitPerItem × usableCapacity) - effectiveTravelCost
```

Unknown economics are never treated as zero economics.

## Runtime order

Current production order:

```text
UpdateTracker
      ↓
ShadowCollector (fail-soft)
      ↓
LocalCatalog (fail-soft / local-only)
      ↓
FinalizeState
      ↓
VisibleItems (fail-soft / local-only)
      ↓
visible heartbeat
      ↓
ResaleQueue (fail-soft / max one request, Update only)
```

`VisibleItems.ps1` is intentionally local-only. A failure there leaves the established primary Xanax state intact.

The broad resale request runs after heartbeat so lower-priority pricing latency cannot make visible update health stale.

## First multi-item presentation layer

Committed `0.3.0` release candidate:

```text
United Kingdom
  Xanax
  Nessie Plushie

Japan
  Xanax
  Cherry Blossom
```

Item configuration:

```text
206 Xanax           visible=true  enabled=true   optimizerEligible=true
266 Nessie Plushie  visible=true  enabled=false  optimizerEligible=false
277 Cherry Blossom  visible=true  enabled=false  optimizerEligible=false
```

The secondary rows therefore do not broaden `UpdateTracker`'s primary model.

### Price semantics

Each visible row renders:

```text
foreign shop price (Torn Item Market reference)
```

- foreign shop price remains first-class provider evidence and keeps profitability color;
- parenthesized resale reference is smaller/muted;
- missing reference displays as `-`;
- a stale broad reference may remain visible for context but cannot produce a GOOD/LOW_MARGIN/UNPROFITABLE secondary color until fresh.

### Deliberate first-release boundary

The existing:

- plane/travel time;
- actionable restock truck;
- departure decision;
- 8-hour graph;
- graph overlay/timing tooltip

remain **Xanax-specific**.

Secondary Nessie/Cherry rows show stock, foreign price, resale reference, category-aware capacity and economics context, but do not yet claim independent trained departure timing.

This is intentional: visibility does not imply optimizer eligibility or fully modeled timing.

## Future filters and travel context

Country/category filters affect visibility only and never stop background observation/learning of other active markets.

Future normalized travel state:

```text
travelState
destinationCountryId
departedAt
arrivalAt
timeLeft
travelMethod
```

Intended behavior:

- at home: normal filtered opportunities;
- outbound: force destination-country visibility and show arrival countdown instead of static flight duration;
- abroad: destination-country active items only;
- returning: release forced foreign-country view.

Plane icon remains; time semantics change.

## Future `Optimal`

`Optimal` is a scheduling layer above per-opportunity modeling. It must compare short-trip repetition, longer routes and mixed-country sequences over a bounded horizon using market validity, capacity, resale/foreign economics, travel cost/time, availability/depletion evidence, confidence/freshness and opportunity cost.

Do not implement it as a simple profit/item or profit/trip sort.

## Performance

- every second: local Lua/countdown/visibility/string work only;
- primary serialized update: ~1 minute;
- shadow provider observation: no more often than ~120s unless revalidated;
- `VisibleItems`: local-only;
- broad resale: max one bounded Torn market request per normal update after heartbeat;
- catalog metadata network maintenance: not in heartbeat;
- no permanent background PowerShell/browser processes.

## Distribution

The `.rmskin` builder is whitelist-based. It includes runtime `.ps1`/`.lua` scripts and committed offline catalog files while excluding:

- `settings.local.json` / API key;
- runtime history/state;
- generated files;
- local errors/cache.

## Validation boundary

Accepted on target Windows:

- broad shadow/provider collection;
- complete current offline catalog/legacy suppression;
- one live broad resale request;
- category-aware capacity focused tests.

Current `0.3.0` UI candidate still requires focused PowerShell/static tests plus actual Rainmeter visual acceptance. See `docs/NEXT_CODEX_RUN.md`.
