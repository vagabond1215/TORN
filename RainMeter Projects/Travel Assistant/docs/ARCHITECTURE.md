# Travel Assistant Architecture

## Purpose

Travel Assistant is a lightweight Rainmeter-facing Torn foreign-market decision system. Broad observation is intentionally separated from market validity, valuation, optimization and presentation.

```text
COLLECTED provider rows
        !=
ACTIVE market relationships
        !=
OPTIMIZER candidates
        !=
CURRENT purchase recommendation
```

The current 0.5 product is a **minimalist next-trip optimizer**. The earlier multi-card graph UI is retired from the default presentation.

## Layering

```text
Prometheus / YATA foreign stock
        ↓
provider normalization
        ↓
country + itemId observed rows
        ↓
verified market-validity overrides
        ↓
bounded observations / restock-sellout cycles
        ↓
local offline item metadata catalog
        ↓
bounded Torn MV cache
        ↓
current travel + Energy/Nerve context
        ↓
capacity/profile effects
        ↓
local next-trip optimizer
        ↓
local preference/filter projection
        ↓
minimal Rainmeter route + purchase rows
```

Settings/preferences are side inputs. They never rewrite observation history.

## Market identity / validity

Identity:

```text
country + itemId
```

Provider presence is not proof a foreign shop still sells that item. Verified overrides in `config/foreign-market-overrides.json` supersede provider presence for new history/resale/optimizer work while preserving provenance.

Accepted baseline at last target-Windows check:

```text
11 countries
232 provider country-item rows
5 verified legacy rows
227 active relationships
232/232 provider names
202 item IDs
202/202 categories resolved
```

Observed truth:

```text
0 -> positive = observed restock
positive -> 0 = observed sellout
```

Predictions never become history.

## Collection / retention

`UpdateTracker.ps1` keeps the original primary Xanax evidence path for compatibility. `ShadowCollector.ps1` observes all 11 countries and all valid provider rows while preventing duplicate primary writes.

Filters/Ignore List/optimizer selection never narrow shared provider collection.

Retention:

```text
high-resolution raw observations: ~48h
completed cycles:                 ~90d
stale live-provider guard:         5m
```

The former 8-hour graph setting may remain for diagnostics, but graphs are no longer part of the default main skin.

## Local catalog

Torn catalog metadata network calls are not allowed in the normal heartbeat after repeated target-host timeouts.

`LocalCatalog.ps1` precedence:

```text
richer manual Torn metadata
    > config item seed
    > verified item override
    > committed offline category snapshot
    > provider name + Unknown
```

Committed catalog references include:

```text
config/foreign-item-categories.json
config/foreign-market-overrides.json
```

`ItemMetadata.ps1` is explicit/manual maintenance only.

## MV / resale cache

`ResaleQueue.ps1` is the sole broad Torn Item Market request path.

Defaults:

```text
attempt cadence:          60s
freshness:                 6h
general failure backoff:   1h
priority failure retry:    5m
request timeout:           6s
requests/update:           <= 1
```

Cache row:

```text
price       # lowest usable listing/fallback, compatibility
lowest
average     # Torn MV authority for optimizer
fetchedAt
source=torn_itemmarket
```

The optimizer uses `average`, not `lowest`, for MV.

`ResalePriority.ps1` is local-only. It prioritizes optimizer MV blockers, retains compatibility priority for old visible/pinned seeds, parks ignored items, and never makes a request itself.

## Value semantics

Default optimizer valuation:

```text
sell basis = 100% Torn MV
fee deduction = 0
minimum profit = 0
minimum margin = 0
negative candidates allowed
```

Optional preference changes sell basis to 95% MV.

Price color:

```text
foreign <= sell basis -> green
foreign > sell basis  -> red
```

Profitability is ranking/context, not timing authority. `Show profitable items only` is an explicit candidate filter.

Legacy `FinalizeState.ps1` calculates compatibility economics without changing or clearing timing status.

## Capacity

General capacity derives from travel-mode base plus current synced profile effects:

```text
Standard: 10 base
Airstrip/WLT/qualified Business: 15 base
```

Accepted target profile:

```text
Airstrip general/Xanax = 18
Standard general/Xanax = 13
```

Category-only company effects stay isolated:

```text
Flower Shop 7★ -> +5 Flower only
Toy Shop    7★ -> +5 Plushie only
```

Country-plan allocation:

1. fill general slots with the best eligible purchase candidates;
2. add valid category-only slots with matching category candidates;
3. never apply Flower/Plushie slots to Xanax/other categories.

## Travel + bars

`TravelContext.ps1` performs one bounded fail-soft request:

```text
/v2/user?selections=travel,basic,bars
```

Normalized travel fields:

```text
state
destination
destinationCountryId
filterActive
method
departedAt
arrivalAt
timeLeft
```

Normalized Energy/Nerve fields:

```text
current
maximum
increment
interval
tickTime
fullTime
```

Transient failures preserve the last successful foreign restriction and bars.

While outbound/abroad, route selection is restricted to the current foreign destination. Return travel defers the next outbound recommendation. Rainmeter ticks arrival countdown locally from stored timestamps.

## Energy / Nerve waste model

For a trip horizon, the optimizer estimates natural regeneration ticks and how much cannot fit below the natural maximum.

Policies:

```text
Allowed
Forbidden
Limited(max loss)
```

Special rule:

```text
Energy current > maximum -> Energy restriction bypassed
Nerve current  > maximum -> NO bypass
```

Unknown bars fail safe under Forbidden/Limited.

## Availability model

The optimizer never treats “provider says stock > 0” as guaranteed arrival availability.

In-stock while home/in flight:

```text
required age at arrival = current active-restock age + flight time
probability = fraction of completed availability durations surviving required age
```

A minimum completed-sample threshold is required.

Already abroad:

- fresh current positive stock is direct current-state evidence.

Sold out:

- requires completed `restockDelaySeconds + availabilitySeconds` evidence;
- arrival probability counts completed cycles whose modeled live interval covers arrival age;
- estimated quantity may use median observed 0→positive restock stock.

Stale markets and verified legacy relationships are excluded.

## Next-trip route planner

`OptimalRoute.ps1` is local-only.

For each eligible country it builds a capacity-constrained purchase plan from eligible markets, then derives:

```text
raw trip value
expected trip value (availability probability weighted)
round-trip/current-position travel cost
trip horizon
score = expected trip value / trip hours
```

It selects the highest current score and projects up to eight purchase rows.

This is deliberately a **next-trip** planner. The eventual bounded multi-trip sequence scheduler is a separate future layer and must compare repeated short trips, fewer long trips, and mixed-country sequences rather than merely sorting current routes.

## Filters / Ignore List

Persistent preferences live in ignored:

```text
data/runtime/preferences.json
```

Current filter bar:

```text
ITEM All ▾   TRIP SHORT MED LONG ▾   CAT All ▾   RESET
```

Item/Category selectors use the active local catalog.

Trip taxonomy:

```text
Short:  Mexico, Cayman Islands, Canada
Medium: Hawaii, United Kingdom, Argentina, Switzerland
Long:   Japan, China, UAE, South Africa
```

These are labels only; per-country travelSeconds/travelCosts are authoritative.

Ignore List excludes items from optimizer candidates and broad per-item MV requests but not shared provider collection/history.

## Rainmeter presentation

Main `TravelAssistant.ini` version 0.5 contains:

- Travel / Settings / Updated header;
- filter bar;
- one dynamically sized Optimal route block;
- route meta/value line;
- up to eight aligned purchase rows.

Each item row displays:

```text
left-aligned item name | quantity | foreign price (smaller muted MV) | modeled arrival chance
```

No default UK/JP item-card stack and no default graphs.

`StateReader.lua` performs only local state reads, countdown formatting, row visibility and panel resizing. Learning/no-route message and purchase rows are mutually exclusive in the route-body area.

## Runtime order

```text
UpdateTracker
      ↓
ShadowCollector            # fail-soft
      ↓
LocalCatalog               # local-only/fail-soft
      ↓
FinalizeState              # compatibility economics informational
      ↓
TravelContext              # bounded request, Update only
      ↓
OptimalRoute               # local-only
      ↓
FilterState                # local-only
      ↓
visible heartbeat
      ↓
ResalePriority             # local-only policy
      ↓
ResaleQueue                # max one request/update
```

`VisibleItems.ps1` is no longer production runtime. `ItemMetadata.ps1` remains manual-only.

## Performance / secrets

- one-second Rainmeter work is local-only;
- normal update ~once/minute;
- shadow collection ~120s minimum unless revalidated;
- one bounded travel/bars request/update;
- at most one broad MV request after heartbeat;
- no permanent background process;
- API key remains ignored/local and sent by stdin/header, never URL/process args.

## Distribution

Whitelist `.rmskin` packaging includes runtime scripts/config/catalog references and excludes credentials, local preferences, runtime history/state/cache/errors and generated artifacts.
