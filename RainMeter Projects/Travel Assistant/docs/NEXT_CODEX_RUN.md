# Next Codex Run: Ranked Opportunity Surface

**Status: ACTIVE — 0.6.0 PENDING TARGET-WINDOWS / RAINMETER ACCEPTANCE**

## Product correction

The 0.5 single `OPTIMAL` route card was rejected as the primary UI. The intended product is the opportunity surface with optimizer intelligence layered onto its ordering.

`OPTIMAL` is a sort mode, not a separate screen.

Current main view:

```text
Travel                                      SETTINGS >
Updated ...

ITEM All ▾   TRIP SHORT MED LONG ▾   CAT All ▾   RESET
SORT  OPTIMAL  UPCOMING  PROFIT  TIME                 VIEWER >

#1  OPTIMAL  <item>   <country>                     <gross>
    <window>  <leave>  <hit likelihood>  <elapsed>  <foreign> (<MV>)  GRAPH
#2           <item>   <country>                     <gross>
    ...
```

Up to eight evidence-backed opportunities are shown.

## Ordering semantics

- `OPTIMAL`: `(gross trip profit × modeled hit probability) / total elapsed hours`.
- `UPCOMING`: earliest current/modeled stock window first.
- `PROFIT`: highest gross trip profit first.
- `TIME`: shortest total elapsed opportunity first.
- There is **no separate Chance sort**. Hit likelihood is displayed and folded into `OPTIMAL`.
- The globally best optimal opportunity remains marked `OPTIMAL` even while another ordering is selected.

Gross profit is item resale spread × modeled purchasable quantity and intentionally does not subtract travel cost. Total elapsed time includes required wait, outbound travel, return travel, and purchase buffer; a current return leg is included before the next outbound opportunity.

## Opportunity evidence

- Fresh current stock uses the existing arrival-survival model.
- Sold-out opportunities require completed sellout→restock plus availability evidence.
- Upcoming windows come from overlap of completed historical live intervals after sellout.
- Minimum availability samples remain controlled by optimizer settings.
- Forecasts never become history.
- Stale provider rows are excluded.
- Unresolved foreign travel (`traveling_unknown` / `abroad_unknown`) fails closed in the primary opportunity projection.

## Energy / Nerve

The opportunity layer uses the same policies as the route model:

```text
Energy Waste: Allowed | Forbidden | Limited
Nerve Waste:  Allowed | Forbidden | Limited
```

Energy stacked above natural maximum bypasses Energy restriction; Nerve has no equivalent bypass. Unknown bars fail safe under Forbidden/Limited. Constraints apply to new outbound opportunities but must not remove guidance after travel is committed to a recognized destination.

## Graphs

Graphs remain part of the product as on-demand diagnostics:

- every visible opportunity row has `GRAPH`;
- `VIEWER >` opens the general market browser;
- graph targeting uses stable `country:itemId`, not visible row number;
- visible window is 8 hours with hourly markers;
- last known observation before the cutoff is carried into the left edge;
- 48h raw-learning and 90d completed-cycle retention remain independent;
- graph viewing is local-only and consumes no provider/Torn API request.

## Popups

Settings, Item/Country/Category filters, Ignore List, Profile/API, and Viewer are detached PowerShell/WinForms surfaces. Launcher script paths must remain explicitly quoted because the repository path contains spaces.

## Runtime order

```text
UpdateTracker
ShadowCollector
LocalCatalog
FinalizeState
TravelContext
OptimalRoute          # background route / pricing-priority model
OpportunityState      # primary sortable UI projection
FilterState
heartbeat
ResalePriority
ResaleQueue
```

## Target-Windows acceptance

From repository root:

```powershell
cd C:\Codex\TORN
git pull --ff-only origin main
git rev-parse --short HEAD

cd "C:\Codex\TORN\RainMeter Projects\Travel Assistant"

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-CurrentAcceptance.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\@Resources\Scripts\RunUpdate.ps1 -Action Update

Select-String .\@Resources\Generated\state.kv `
  -Pattern '^(Opportunity|UIOldestMarketSourceTimestamp)'

if (Test-Path .\data\runtime\opportunity-state-error.txt) {
  Get-Content .\data\runtime\opportunity-state-error.txt
}
```

Then refresh Rainmeter and verify:

1. no single-route `OPTIMAL` card;
2. ranked opportunity rows are visible when evidence supports them;
3. `OPTIMAL`, `UPCOMING`, `PROFIT`, and `TIME` visibly reorder rows;
4. there is no Chance sort;
5. the globally best economic row retains its `OPTIMAL` badge under other sorts;
6. Item/Country/Category filter popups open and update the list;
7. `SETTINGS >` opens;
8. `VIEWER >` opens;
9. each row `GRAPH` opens the correct `country:itemId` graph;
10. graphs span 8 hours with hourly markers and left-edge continuity;
11. no controls or opportunity-row fields overlap;
12. no persistent `ERROR` remains after a successful normal update.

Send the acceptance output and a screenshot before marking 0.6 accepted.

## After 0.6 acceptance

1. refine row density/visual hierarchy based on the real Rainmeter render;
2. calibrate availability probabilities as more cycles accumulate;
3. add optional browser notifications by consuming the accepted opportunity projection rather than duplicating timing logic;
4. later consider bounded multi-trip sequencing as a separate optimization layer.
