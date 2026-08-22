# Next Codex Run: Compact Opportunity Cards

**Status: ACTIVE — 0.6.0 PENDING TARGET-WINDOWS / RAINMETER ACCEPTANCE**

## Product direction

The primary surface is a compact persistent opportunity list. The retired single-route `OPTIMAL` UI and later composite `OPTIMAL` sort must not return.

Current main view target:

```text
Travel                                      SETTINGS >
Updated ...

ITEM All v   TRIP SHORT MED LONG v   CAT All v   RESET
NAME   UPCOMING   GROSS PROFIT   PROFIT/HR          VIEWER >

[FLAG]  <item>                                <$gross>   v
 time   <window>  <leave>  <chance/LEARNING>  <foreign> (<MV>)
```

Up to eight current/future opportunities may be shown.

### Compact-card rules

- Remove visible `#1/#2/...` place numbers.
- Left side is a destination flag with travel/elapsed-time text directly beneath it on the normal card background.
- Do **not** draw the former white travel-time strip or a separate flag-tile background/outline.
- Country name/code and elapsed time do not appear again in the card body.
- Visible gross is only `$amount`; no `gross` suffix and no `xN` suffix.
- Quantity remains in internal projection/tooltips for inspectable economics.
- Far-right control is a compact `v`/`^` chevron, not the word `GRAPH`.

## Inline card graph

The row chevron expands an 8-hour stock graph **inside that card/list**.

- Only one inline graph may be expanded at a time.
- Opening a different card collapses the previous one.
- Clicking the open card again collapses it.
- Stable `country:itemId` identity follows the market through visible sorting.
- Expanded cards reflow later rows and panel height.
- The graph is local-only and uses `RenderInlineGraph.ps1` plus generated Rainmeter Shape-path data.
- An open inline graph can refresh locally at approximately one-minute cadence.
- The 8-hour graph has seven evenly spaced internal vertical separators: one-hour segments.
- Y-axis labels are sparse: retained numeric maximum at the upper-left, `0` at the lower-left.
- X-axis keeps `-8h` at the lower-left; the right edge implicitly means now.
- Do not display `8H STOCK`, `max`, retained-point counts, stock-change counts, or other graph summary prose.
- Zero-stock-only history must plot flat at zero rather than a fabricated `0..1` axis.

`VIEWER >` remains a **separate standalone WinForms market browser**. The row chevron must never open it. Because `MeasureItemViewer` uses dynamic variables, the Lua reader must explicitly refresh that RunCommand measure before `Run` so a stale prior Viewer key cannot leak into an inline request.

## Ordering

- `NAME`: item name ascending, then destination.
- `UPCOMING`: earliest current/modeled stock window first.
- `GROSS PROFIT`: highest trip gross first.
- `PROFIT/HR`: trip gross / total elapsed hours, descending.
- Hit likelihood remains a separate decision variable and is not multiplied into any sort score.

Sort clicks must reorder the already-projected rows immediately in Lua. The PowerShell action only persists the preference and must not delay visual sorting.

## Current stock and learning

Fresh current stock must not vanish because completed-cycle likelihood evidence is incomplete.

- Fresh in-stock rows may show `LEARNING` in the likelihood field.
- Unknown likelihood is not a fake 0% or 100%.
- Gross/profit-hour can still be calculated from current stock, current foreign price, capacity and cached MV.
- Sold-out/future windows still require completed cycle evidence.
- Stale stock, unresolved MV, explicit filters, waste policy, or travel restriction may still legitimately remove a row.

## History / Viewer

Both inline and standalone graph surfaces use the same retained local truth:

- 8-hour visible history;
- 48h high-resolution observation retention;
- 90d completed-cycle retention;
- change-only predecessor/baseline carry-forward;
- no provider/Torn request to view a graph;
- no forecast-to-history mutation.

The standalone Viewer retains its richer dropdown and diagnostics. Inline graphs are deliberately compact.

## Popups / diagnostics

Settings, Item/Country/Category filters, Ignore List, Profile/API and standalone Viewer use hidden STA popup hosts. No PowerShell console should remain visible.

Runtime failures:

```text
data/runtime/logs/travel-assistant.log
```

## Runtime order

```text
UpdateTracker
ShadowCollector
LocalCatalog
FinalizeState
TravelContext
OptimalRoute          # background compatibility / MV priority
OpportunityState      # primary opportunity projection
FilterState
heartbeat
ResalePriority
ResaleQueue
```

Inline rendering is outside that network heartbeat and local-only.

## Target-Windows acceptance

```powershell
cd C:\Codex\TORN
git pull --ff-only origin main
git rev-parse --short HEAD

cd "C:\Codex\TORN\RainMeter Projects\Travel Assistant"

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-CurrentAcceptance.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\@Resources\Scripts\RunUpdate.ps1 -Action Update
```

Then refresh Rainmeter and verify:

1. Fresh in-stock markets appear even if likelihood says `LEARNING`.
2. No rank numbers.
3. Every card has a recognizable country flag and visible time directly beneath it.
4. No white strip/background behind the travel time.
5. Country name/code and duplicate center travel-time text are absent.
6. Gross is `$amount` only.
7. NAME / UPCOMING / GROSS PROFIT / PROFIT/HR reorder immediately.
8. Row `v` expands only that in-card graph; it does not spawn the standalone Viewer.
9. The graph has seven internal hourly vertical separators.
10. Graph labels are only numeric Y max, `0`, and `-8h`; no summary/count prose.
11. Opening another row collapses the first; at most one graph is open.
12. `VIEWER >` still opens the separate full Viewer popup.
13. Zero-stock graph stays flat at zero; nonzero retained history shows real step changes.
14. The list remains populated through normal polling.
15. SETTINGS and filters still work with no visible PowerShell console.

If anything errors:

```powershell
Get-Content .\data\runtime\logs\travel-assistant.log -Tail 40
```

Send the focused acceptance output plus one collapsed-card screenshot and one expanded-card screenshot before marking 0.6 accepted.

## After acceptance

1. Tune flag/chart proportions from the real Rainmeter render.
2. Calibrate probability model as completed cycles accumulate.
3. Add optional Chrome/browser notifications as a consumer of accepted local opportunity timing state.
4. Consider bounded multi-trip sequencing separately from the opportunity browser.
