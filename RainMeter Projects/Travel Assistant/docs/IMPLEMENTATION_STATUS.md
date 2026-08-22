# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-22

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

The rejected 0.5 single-route card has been replaced by a ranked opportunity list. The later user-facing `OPTIMAL` composite ranking has also been removed.

Primary controls:

```text
ITEM All v   TRIP SHORT MED LONG v   CAT All v   RESET
SORT  UPCOMING   GROSS PROFIT   PROFIT/HR          VIEWER >
```

Up to eight rows show:

```text
rank
item + destination
gross trip profit + quantity
current or modeled stock window
leave timing
modeled hit likelihood
total elapsed time
foreign price (Torn MV)
GRAPH
```

Ordering is intentionally transparent:

- `UPCOMING`: earliest supported/current window first.
- `GROSS PROFIT`: total trip gross descending.
- `PROFIT/HR`: total trip gross divided by total elapsed hours.
- Hit likelihood remains a separate displayed percentage and is not folded into any hidden score.

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

## Gross / profit-per-hour semantics — IMPLEMENTED

Gross trip profit is:

```text
(selected MV basis - foreign price) × modeled purchasable quantity
```

It intentionally excludes travel cost. The row now exposes quantity beside gross, and the tooltip explains the arithmetic.

`PROFIT/HR` is:

```text
gross trip profit / total elapsed hours
```

It is not probability-weighted. Likelihood is left visible for the player to judge independently.

## Projection / interaction stability — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

Recent target screenshots showed the opportunity rows disappearing to `Learning opportunities...` for a large portion of a polling cycle. The cause is intermediate compatibility-state publication while the full update pipeline is still running.

`StateReader.lua` now:

- captures the last complete `Opportunity*`/`UI*` projection during initialization;
- preserves it while the minute updater is between compatibility and opportunity projections;
- updates the selected sort highlight immediately;
- briefly defers the next automatic poll after an interactive action;
- gives text controls transparent rectangular hitboxes for more reliable clicking.

Pure sort changes also skip unnecessary `FilterState.ps1` recomputation and directly rebuild only the opportunity ordering.

## Graph viewer — IMPLEMENTED

The item viewer remains an 8-hour diagnostic surface with hourly markers.

- General `VIEWER >` browses active markets.
- Every opportunity row has `GRAPH`.
- Row targeting uses stable `country:itemId`, not row number.
- The last observation before the 8-hour cutoff is carried to the left edge for change-only history continuity.
- Change-only 48h pruning now preserves one boundary baseline per market.
- Markets whose old baseline was already lost receive a truthful retained/current bootstrap rather than invented intermediate history.
- Viewer is local-only and consumes no provider/Torn request.
- Learning retention remains 48h raw / 90d completed cycles.

## Popup reliability changes — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

Detached Settings, filter and viewer launchers use one hidden STA popup host. Runtime/popup failures go to:

```text
data/runtime/logs/travel-assistant.log
```

Windows PowerShell 5.1 generic collection enumeration bugs found during validation were removed from the preference/evidence/viewer/filter paths.

## Background optimizer — RETAINED

`OptimalRoute.ps1` remains the background one-best-next-trip planner for compatibility, diagnostics and MV-priority work. Its name no longer maps to a user-facing sort or badge.

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

## Validation status

Static/deterministic validators now cover:

- three transparent sort modes;
- migration from old `optimal/profit/time` sort IDs;
- no user-facing OPTIMAL badge/hidden score;
- gross quantity projection;
- raw gross-per-hour math;
- stable market-key graph targeting;
- graph carry-forward baseline and retention repair;
- Windows PowerShell 5.1 collection compatibility;
- opportunity-model deterministic overlap/probability tests;
- Energy/Nerve integration;
- hidden popup/logging contract;
- refresh-stable projection and responsive sort path.

0.6 still requires target-Windows validation. Do not mark accepted until `tests/Run-CurrentAcceptance.ps1`, one normal production update, all popups/sort controls, row graphs and a Rainmeter screenshot pass.

## After 0.6 acceptance

1. refine visual row density/alignment from the actual Rainmeter render;
2. continue probability calibration from accumulated cycles;
3. add optional Chrome/browser notifications as a consumer of the accepted opportunity state;
4. later evaluate bounded multi-trip sequence scheduling separately from the opportunity browser.
