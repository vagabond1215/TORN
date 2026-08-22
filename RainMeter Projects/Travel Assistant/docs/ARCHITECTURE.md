# Travel Assistant Architecture

## Purpose

Travel Assistant is a lightweight Rainmeter-facing Torn foreign-market decision system. Broad observation is intentionally separated from market validity, valuation, opportunity ranking and presentation.

```text
COLLECTED provider rows
        !=
ACTIVE market relationships
        !=
ELIGIBLE opportunity candidates
        !=
VISIBLE ranked opportunities
```

The current 0.6 product is a **ranked opportunity browser**. The user-facing ordering is explicit and inspectable; it does not collapse the UI to one route and it does not hide likelihood inside a composite `OPTIMAL` score.

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
background next-trip route model
        ↓
ranked opportunity projection
        ↓
filters / selected transparent ordering
        ↓
Rainmeter opportunity rows + on-demand graphs
```

Settings/preferences are side inputs. They never rewrite observation history.

## Market identity / validity

Identity:

```text
country + itemId
```

Provider presence is not proof a foreign shop still sells that item. Verified overrides in `config/foreign-market-overrides.json` supersede provider presence for new history/resale/opportunity work while preserving provenance.

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

`UpdateTracker.ps1` keeps the original primary evidence path for compatibility. `ShadowCollector.ps1` observes all 11 countries and valid provider rows while preventing duplicate primary writes.

Filters/Ignore List/sorting never narrow shared provider collection.

Retention:

```text
high-resolution raw observations: ~48h
completed cycles:                 ~90d
stale live-provider guard:         5m
visible graph window:              8h
```

The graph horizon is display-only. It does not change learning retention. Change-only high-resolution pruning must preserve one predecessor/baseline per market across the retention cutoff so unchanged stock does not lose graph continuity.

## Local catalog and MV

Catalog network maintenance remains outside the normal heartbeat. `LocalCatalog.ps1` resolves metadata from committed/local sources.

`ResaleQueue.ps1` is the sole broad Torn Item Market request path. The route/opportunity layer uses cached `itemmarket.item.average_price` as MV.

Default value basis:

```text
100% Torn MV
0 Item Market fee deduction
0 minimum profit gate
0 minimum margin gate
```

Optional preference changes sell basis to 95% MV.

## Capacity

General capacity derives from travel-mode base plus synced profile effects:

```text
Standard: 10 base
Airstrip/WLT/qualified Business: 15 base
```

Category-only company effects remain isolated. Opportunity quantity uses the item-appropriate capacity and available/current or modeled restock quantity.

## Travel + bars

`TravelContext.ps1` performs one bounded fail-soft request:

```text
/v2/user?selections=travel,basic,bars
```

Transient failures preserve the last successful foreign restriction and bars. Its diagnostic file remains owned by the child script so internally caught failures are not immediately erased by the wrapper.

While outbound/abroad to a recognized destination, opportunity selection is restricted to that destination. `traveling_unknown` / `abroad_unknown` fails closed in `OpportunityState.ps1`.

## Availability model

For current in-stock markets, arrival survival is derived from completed availability durations. For sold-out markets, `OpportunityState.ps1` builds a time-after-sellout probability curve from completed:

```text
restockDelaySeconds
availabilitySeconds
```

Each historical cycle contributes a live interval:

```text
[restock delay, restock delay + availability duration)
```

The overlap count across those intervals yields modeled hit probability at a target purchase time. The next modeled window prefers the earliest future segment with at least 50% completed-cycle support; if no future segment reaches that support, the strongest future segment is used rather than inventing certainty.

Restock quantity may use the median observed `0 -> positive` quantity.

## Ranked opportunity model

`OpportunityState.ps1` is local-only and is the primary presentation projection.

For each eligible `country:itemId`, it derives:

```text
modeled/current purchase time
leave timing
hit probability
purchasable quantity
selected MV basis
profit per item
gross trip profit
total elapsed time
profit per hour
```

Gross trip profit:

```text
gross = quantity × (selected MV basis - foreign price)
```

It intentionally does not subtract travel cost because the primary UI is presenting gross trade economics. Quantity is projected separately so the displayed gross can be checked directly.

Profit per hour:

```text
profit/hr = gross trip profit / total elapsed hours
```

Hit probability is **not** multiplied into `PROFIT/HR`; it stays visible as a separate decision variable.

Total elapsed time includes any required wait plus outbound travel, return travel, and purchase buffer. If currently returning to Torn, remaining return time precedes the next outbound opportunity.

Visible sorts:

```text
UPCOMING      earliest current/modeled window first
GROSS PROFIT  gross trip profit descending
PROFIT/HR     gross trip profit / elapsed hours descending
```

There is no user-facing `OPTIMAL`, Chance, or shortest-Time sort.

## Energy / Nerve waste

The same bar-waste helpers used by the background route model are applied to the opportunity horizon.

Policies:

```text
Allowed
Forbidden
Limited(max loss)
```

- Energy above natural maximum bypasses Energy restriction.
- Nerve has no stacking bypass.
- Unknown bars fail safe for Forbidden/Limited.
- Constraints apply to new outbound opportunities.
- After travel is committed to a recognized destination, they do not remove destination purchase guidance.

## Background route planner

`OptimalRoute.ps1` remains local-only and continues to build one best next-trip plan for compatibility, diagnostics and MV-priority behavior. It is not a user-facing sort or badge.

## Filters / Ignore List / ordering

Persistent preferences live in ignored:

```text
data/runtime/preferences.json
```

Primary controls:

```text
ITEM All v   TRIP SHORT MED LONG v   CAT All v   RESET
SORT  UPCOMING   GROSS PROFIT   PROFIT/HR
```

Ignore List excludes items from opportunity/optimizer candidates and broad per-item MV requests but not shared provider collection/history.

## Projection stability / interaction

`UpdateTracker.ps1` still writes compatibility state early in a minute update, before `OpportunityState.ps1` finishes. `StateReader.lua` therefore preserves the last complete `Opportunity*`/`UI*` projection during intermediate writes so the skin does not flash to an empty learning state.

The reader captures that last complete projection during initialization as well as normal updates. Sort actions update their active visual state immediately and defer the next automatic poll briefly while local re-projection completes. Text buttons receive transparent rectangular hitboxes rather than relying on glyph pixels alone.

## Graph viewer

Every visible opportunity row carries a stable market key and can open `OpenItemViewer.ps1` focused on that exact `country:itemId`.

The viewer:

- reads only local retained observations and engine state;
- displays 8 hours with hourly time markers;
- shows observed restock/sellout transitions;
- carries the last observation before the cutoff to the left edge;
- never polls providers or Torn;
- can also browse the wider active market catalog from `VIEWER >`.

## Runtime order

```text
UpdateTracker
      ↓
ShadowCollector
      ↓
LocalCatalog
      ↓
FinalizeState
      ↓
TravelContext
      ↓
OptimalRoute            # local-only background route / MV-priority model
      ↓
OpportunityState        # local-only primary opportunity ranking
      ↓
FilterState
      ↓
visible heartbeat
      ↓
ResalePriority
      ↓
ResaleQueue
```

## Performance / secrets

- one-second Rainmeter work is local-only;
- normal update ~once/minute;
- shadow collection ~120s minimum unless revalidated;
- one bounded travel/bars request/update;
- at most one broad MV request after heartbeat;
- graph viewing is local/on-demand;
- no permanent background process;
- API key remains ignored/local and sent by stdin/header, never URL/process args.

## Future browser notifications

Notifications should be an optional consumer of the accepted opportunity projection, not a second availability model. They must be opt-in, dedupe repeated windows, and add no provider/Torn request path.
