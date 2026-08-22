# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-21

**Active run:** 0.6.0 ranked opportunity surface. See `docs/NEXT_CODEX_RUN.md`.

## Accepted data foundation

Target-Windows evidence already covers:

```text
11 foreign countries collected
232 provider country-item rows at last live check
227 active market relationships
202 distinct observed items
202 metadata rows
202 categories resolved
5 verified legacy provider rows excluded from new learning/economics work
```

Also accepted:

- provider-name enrichment on every observed market;
- offline category/catalog authority;
- bounded one-request-at-a-time Torn Item Market pricing;
- `/user/perks` general capacity behavior;
- Flower/Toy category-capacity isolation;
- Airstrip general/Xanax 18 and Standard 13 on the target profile.

## 0.6 opportunity UI — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

The rejected 0.5 single-route card has been replaced by a ranked opportunity list.

Primary controls:

```text
ITEM All ▾   TRIP SHORT MED LONG ▾   CAT All ▾   RESET
SORT  OPTIMAL  UPCOMING  PROFIT  TIME                 VIEWER >
```

Up to eight rows show:

```text
rank / OPTIMAL marker
item + destination
gross trip profit
current or modeled stock window
leave timing
modeled hit likelihood
total elapsed time
foreign price (Torn MV)
GRAPH
```

`OPTIMAL` is a sort and highlight, not a separate screen. It ranks `(gross profit × hit probability) / elapsed hours`. There is no separate Chance sort. The global optimum remains marked even while UPCOMING, PROFIT or TIME ordering is active.

## Opportunity evidence — IMPLEMENTED

`OpportunityState.ps1` is local-only and consumes retained stock/cycles, cached MV, current travel/bars, filters and capacity.

Current stock uses arrival-survival evidence. Sold-out markets use overlap of completed historical live intervals after sellout to locate supported future windows. Estimated restock quantity uses observed restock quantities when available.

The opportunity layer:

- excludes stale markets;
- requires fresh cached MV;
- honors Item/Trip/Country/Category filters and Ignore List;
- honors profitable-only when explicitly enabled;
- honors Energy/Nerve waste constraints for new outbound opportunities;
- preserves destination purchase guidance after travel is committed;
- fails closed for unresolved foreign destination states;
- never writes predicted history.

## Graph viewer — IMPLEMENTED

The item viewer remains an 8-hour diagnostic surface with hourly markers.

- General `VIEWER >` browses active markets.
- Every opportunity row has `GRAPH`.
- Row targeting uses stable `country:itemId`, not row number.
- The last observation before the 8-hour cutoff is carried to the left edge for change-only history continuity.
- Viewer is local-only and consumes no provider/Torn request.
- Learning retention remains 48h raw / 90d completed cycles.

## Popup reliability changes — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

Detached Settings, filter and viewer launchers explicitly quote script paths containing spaces. Filter saves recompute the opportunity projection immediately.

The Windows screenshot that motivated 0.6 showed `SETTINGS > ERROR` and non-opening popups, so these controls require explicit target-host retest before acceptance.

## Background optimizer — RETAINED

`OptimalRoute.ps1` remains the background one-best-next-trip planner for compatibility, diagnostics and MV-priority work. It is no longer the primary presentation surface.

## Runtime order

```text
UpdateTracker
ShadowCollector
LocalCatalog
FinalizeState
TravelContext
OptimalRoute
OpportunityState
FilterState
heartbeat
ResalePriority
ResaleQueue
```

## Value semantics

Default basis remains:

```text
100% Torn MV
0% Item Market fee deduction
0 minimum profit gate
0 minimum margin gate
negative-value candidates allowed
```

Optional setting uses 95% MV. `Show profitable items only` explicitly removes non-positive candidates.

Gross opportunity profit intentionally excludes travel cost. The OPTIMAL score probability-weights gross profit and normalizes it by full elapsed opportunity time.

## Validation status

Static/deterministic validators have been converted to the 0.6 opportunity contract, including:

- four explicit sort modes;
- no Chance sort;
- persistent global OPTIMAL marker;
- stable market-key graph targeting;
- graph carry-forward baseline;
- opportunity-model deterministic overlap/probability tests;
- Energy/Nerve integration;
- popup launcher quoting.

0.6 still requires target-Windows validation. Do not mark accepted until `tests/Run-CurrentAcceptance.ps1`, one normal production update, all popups/sort controls, row graphs and a Rainmeter screenshot pass.

## After 0.6 acceptance

1. refine visual row density/alignment from the actual Rainmeter render;
2. continue probability calibration from accumulated cycles;
3. add optional Chrome/browser notifications as a consumer of the accepted opportunity state;
4. later evaluate bounded multi-trip sequence scheduling separately from the opportunity browser.
