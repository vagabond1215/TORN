# Next Codex Run: Ranked Opportunity Surface

**Status: ACTIVE — 0.6.0 PENDING TARGET-WINDOWS / RAINMETER ACCEPTANCE**

## Product correction

The 0.5 single `OPTIMAL` route card was rejected as the primary UI. The intended product is a persistent opportunity surface with explicit, inspectable ordering.

The `OPTIMAL` presentation concept has now also been removed. There is no hidden composite score in the user-facing ordering.

Current main view:

```text
Travel                                      SETTINGS >
Updated ...

ITEM All v   TRIP SHORT MED LONG v   CAT All v   RESET
SORT  UPCOMING   GROSS PROFIT   PROFIT/HR          VIEWER >

#1  <item>   <country>                     <trip gross> <qty>
    <window>  <leave>  <hit likelihood>  <elapsed>  <foreign> (<MV>)  GRAPH
#2  <item>   <country>                     <trip gross> <qty>
    ...
```

Up to eight evidence-backed opportunities are shown.

## Ordering semantics

- `UPCOMING`: earliest current/modeled stock window first.
- `GROSS PROFIT`: highest total trip gross first.
- `PROFIT/HR`: gross trip profit divided by total elapsed hours.
- Hit likelihood remains a separate displayed percentage. It is **not** multiplied into any visible sort score.
- There is no `OPTIMAL`, Chance, or shortest-Time sort in the user-facing surface.

Gross profit is `(selected MV basis - foreign price) × modeled purchasable quantity` and intentionally does not subtract travel cost. Quantity is displayed beside gross so the arithmetic is inspectable. Total elapsed time includes required wait, outbound travel, return travel, and purchase buffer; a current return leg is included before the next outbound opportunity.

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

## Interaction / refresh stability

- Sort clicks use a shortened local-only projection path.
- Sort buttons update their active highlight immediately while the local re-sort finishes.
- Transparent hitboxes are applied to text controls so clicks are not limited to glyph pixels.
- The Lua reader captures the last complete opportunity/UI projection during initialization and preserves it while the minute update pipeline is publishing intermediate compatibility state. The skin must not flash back to `Learning opportunities...` during a normal poll.

## Popups

Settings, Item/Country/Category filters, Ignore List, Profile/API, and Viewer are detached PowerShell/WinForms surfaces. Launcher script paths must remain explicitly quoted because the repository path contains spaces. Runtime failures go to `data/runtime/logs/travel-assistant.log`.

## Runtime order

```text
UpdateTracker
ShadowCollector
LocalCatalog
FinalizeState
TravelContext
OptimalRoute          # background route / pricing-priority compatibility model
OpportunityState      # primary sortable UI projection
FilterState
heartbeat
ResalePriority
ResaleQueue
```

`OptimalRoute.ps1` remains internal/background only; do not reintroduce an `OPTIMAL` UI mode from its name.

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
  -Pattern '^Opportunity(Count|Message|SortMode|1(Key|Name|Country|ChanceText|TimeText|GrossText|QuantityText|ProfitHourText))='
```

Then refresh Rainmeter and verify:

1. no single-route card and no visible `OPTIMAL` badge/mode;
2. ranked opportunity rows remain visible throughout normal polling rather than flashing to `Learning opportunities...`;
3. `UPCOMING`, `GROSS PROFIT`, and `PROFIT/HR` visibly reorder rows;
4. hit likelihood remains displayed separately and does not change the mathematical definition of `PROFIT/HR`;
5. trip gross visibly includes quantity, e.g. `$777,870 gross x18`, and the tooltip explains unit spread × quantity;
6. Item/Country/Category filter popups open and update the list;
7. sort/filter controls respond promptly and do not revert after refresh;
8. `SETTINGS >` opens;
9. `VIEWER >` opens;
10. each row `GRAPH` opens the correct `country:itemId` graph;
11. graphs span 8 hours with hourly markers and left-edge continuity;
12. no controls or opportunity-row fields overlap;
13. no persistent `ERROR` remains after a successful normal update.

If anything errors, inspect only:

```powershell
Get-Content .\data\runtime\logs\travel-assistant.log -Tail 40
```

Send the acceptance output and screenshots before marking 0.6 accepted.

## After 0.6 acceptance

1. refine row density/visual hierarchy based on the real Rainmeter render;
2. calibrate availability probabilities as more cycles accumulate;
3. add optional browser notifications by consuming the accepted opportunity projection rather than duplicating timing logic;
4. later consider bounded multi-trip sequencing as a separate optimization layer.
