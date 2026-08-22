# Travel Assistant Architecture

## Purpose

Travel Assistant is a lightweight Rainmeter-facing Torn foreign-market decision system. Broad observation is intentionally separated from market validity, valuation, opportunity eligibility, ordering and presentation.

```text
COLLECTED provider rows
        !=
ACTIVE market relationships
        !=
ELIGIBLE opportunity candidates
        !=
VISIBLE opportunities
```

The current 0.6 product is a compact opportunity browser. It does not collapse the UI to one route and does not hide likelihood inside a composite `OPTIMAL` score.

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
background compatibility route model
        ↓
current/future opportunity projection
        ↓
filters + transparent visible ordering
        ↓
compact Rainmeter cards
        ↙                         ↘
one-at-a-time inline graph     standalone Viewer
```

Settings/preferences are side inputs. They never rewrite observation history.

## Market identity / validity

Identity is:

```text
country + itemId
```

Provider presence is not proof a foreign shop still sells an item. Verified overrides in `config/foreign-market-overrides.json` supersede provider presence for new history/resale/opportunity work while preserving provenance.

Recorded target baseline:

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

`UpdateTracker.ps1` keeps compatibility evidence/state. `ShadowCollector.ps1` observes all 11 countries and valid provider rows while preventing duplicate primary writes.

Filters, Ignore List, ordering and graph expansion never narrow shared provider collection.

Retention:

```text
high-resolution raw observations: ~48h
completed cycles:                 ~90d
stale live-provider guard:         5m
visible graph window:              8h
```

The graph horizon is display-only. Change-only pruning preserves one predecessor/baseline per market so unchanged state remains drawable across the retention boundary.

## Local catalog and MV

Catalog network maintenance stays outside the normal heartbeat. `LocalCatalog.ps1` resolves metadata from committed/local sources.

`ResaleQueue.ps1` is the sole broad Torn Item Market request path. The opportunity layer consumes cached `itemmarket.item.average_price` as MV.

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

Category-only company effects remain isolated. Opportunity quantity uses item-appropriate capacity and current/modelled available quantity. Quantity remains projected internally even though the compact card no longer prints `xN` beside gross.

## Travel + bars

`TravelContext.ps1` performs one bounded fail-soft request:

```text
/v2/user?selections=travel,basic,bars
```

Transient failures preserve the last successful foreign restriction and bars. While outbound/abroad to a recognized destination, opportunity selection is restricted to that destination. `traveling_unknown` / `abroad_unknown` fails closed.

## Availability model

### Fresh current stock

Current observed stock is useful before enough completed cycles exist to model arrival survival.

For a fresh in-stock market:

- calculate trip economics from current foreign price, current stock/capacity and cached MV;
- if arrival probability is trained, display the modeled percentage;
- if not trained, keep the row visible with likelihood `LEARNING`;
- never substitute an invented percentage for unknown likelihood.

This separates observed present state from learned future survival confidence.

### Sold-out / future windows

For sold-out markets, `OpportunityState.ps1` uses completed:

```text
restockDelaySeconds
availabilitySeconds
```

Each cycle contributes:

```text
[restock delay, restock delay + availability duration)
```

Overlap yields modeled hit probability at a target purchase time. A future sold-out opportunity still requires sufficient completed evidence; the relaxed `LEARNING` rule applies to current observed stock, not invented future windows.

Restock quantity may use the median observed `0 -> positive` quantity.

## Opportunity economics / ordering

For each eligible market the projection derives:

```text
current/future purchase time
leave timing
hit probability or LEARNING
purchasable quantity
selected MV basis
unit spread
gross trip profit
total elapsed time
profit per hour
```

```text
gross = quantity × (selected MV basis - foreign price)
profit/hr = gross / total elapsed hours
```

Gross intentionally excludes travel cost. Hit probability is **not** multiplied into `PROFIT/HR`.

Visible sorts:

```text
NAME          item name ascending, then destination
UPCOMING      earliest current/modeled window first
GROSS PROFIT  gross trip profit descending
PROFIT/HR     gross / elapsed hours descending
```

Sorts are applied immediately in `StateReader.lua` to the current projection. PowerShell persistence is not on the visual critical path.

## Compact card presentation

Each row is intentionally sparse:

```text
[flag]  Item name                              $gross   v
[time]  window   leave   chance/LEARNING   foreign (MV)
```

- No visible rank/place number.
- No country name/code in the body.
- No duplicate elapsed-time field in the body.
- Destination is encoded by a vector flag tile.
- The flag's white lower strip carries the elapsed/travel-time text.
- Gross is a bare dollar value; quantity remains in tooltip/projected state.
- Right-side `v`/`^` controls inline graph expansion.

The flag graphics are local Rainmeter Shape approximations for all 11 destinations; no binary flag assets are required.

## Inline graph architecture

`RenderInlineGraph.ps1` is a local-only renderer. It reads seed/runtime observations + engine state and writes a bounded generated key/value graph specification:

```text
@Resources/Generated/inline-graph-<country_item>.kv
```

The spec contains a Rainmeter Shape path, summary, max stock and retained point/change counts.

`StateReader.lua`:

- tracks `expandedKey` by stable market identity;
- allows at most one expanded graph;
- reflows lower rows and panel height;
- applies compact grid/path Shape options to the expanded card;
- follows the expanded market if sorting moves it;
- locally refreshes an open graph around once/minute.

The existing `MeasureItemViewer`/`LaunchItemViewer.ps1` transport is reused. `inline_<marketKey>` routes synchronously to `RenderInlineGraph.ps1` and exits; ordinary market keys still route to the standalone popup host.

No provider/Torn request is made by inline rendering.

## Standalone Viewer

`VIEWER >` remains a separate detached WinForms browser. It retains:

- market dropdown;
- richer labels/diagnostics;
- 8-hour graph with hourly markers;
- restock/sellout visual markers;
- truthful zero-stock axis;
- stable `country:itemId` targeting.

The standalone Viewer and inline graph share retained local truth but are separate UI surfaces.

## Energy / Nerve waste

Policies remain:

```text
Allowed
Forbidden
Limited(max loss)
```

- Energy above natural maximum bypasses Energy restriction.
- Nerve has no stacking bypass.
- Unknown bars fail safe for Forbidden/Limited.
- Constraints apply to new outbound opportunities.
- After travel is committed to a recognized destination, constraints do not erase destination purchase guidance.

## Background route planner

`OptimalRoute.ps1` remains local-only and builds one best next-trip plan for compatibility, diagnostics and MV-priority behavior. Its name does not imply a user-facing `OPTIMAL` mode.

## Filters / local state

Preferences live in ignored:

```text
data/runtime/preferences.json
```

Primary controls:

```text
ITEM All v   TRIP SHORT MED LONG v   CAT All v   RESET
NAME   UPCOMING   GROSS PROFIT   PROFIT/HR
```

Ignore List excludes items from opportunity/background optimizer candidates and broad per-item MV requests but not shared provider collection/history.

## Projection stability / interaction

`UpdateTracker.ps1` can publish compatibility state before `OpportunityState.ps1` completes. `StateReader.lua` therefore retains the last complete opportunity/UI projection through intermediate writes and through transient learning-only zero projections.

Interactive ordering and expansion are local UI operations and should not wait on the normal network update pipeline.

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
OptimalRoute
      ↓
OpportunityState
      ↓
FilterState
      ↓
visible heartbeat
      ↓
ResalePriority
      ↓
ResaleQueue
```

Inline graph rendering is an on-demand local side path, not a network heartbeat stage.

## Performance / secrets

- one-second Rainmeter work: local-only;
- sort/expand UI state: local-only;
- inline graph render: local/on-demand and at most roughly once/minute while open;
- normal update: roughly once/minute;
- shadow collection: roughly 120s minimum;
- one bounded travel/bars request/update;
- at most one broad MV request after heartbeat;
- no permanent background process;
- API key stays ignored/local and is sent by stdin/header, never URL/process args.

## Future browser notifications

Notifications remain an optional future consumer of accepted opportunity timing state. They must not duplicate the forecasting model or add provider/Torn request paths.
