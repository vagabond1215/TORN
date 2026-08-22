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
[time]  <window>  <leave>  <chance/LEARNING>  <foreign> (<MV>)

[FLAG]  <item>                                <$gross>   v
[time]  ...
```

Up to eight current/future opportunities may be shown.

### Compact-card rules

- Remove visible `#1/#2/...` place numbers.
- Left side is a destination flag tile.
- Bottom of that tile is a white strip containing the existing total elapsed/travel-time text.
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
- Zero-stock-only history must plot flat at zero rather than a fabricated `0..1` axis.

`VIEWER >` remains a **separate standalone WinForms market browser**. Do not conflate the popup Viewer with inline expansion.

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
- hourly context in the full Viewer;
- 48h high-resolution observation retention;
- 90d completed-cycle retention;
- change-only predecessor/baseline carry-forward;
- no provider/Torn request to view a graph;
- no forecast-to-history mutation.

The standalone Viewer retains its richer dropdown, labels and diagnostic graph. Inline graphs are deliberately compact.

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
  -Pattern '^Opportunity(Count|Message|SortMode|1(Key|Name|ChanceText|TimeText|GrossText|PriceText|MarketValueText))='
```

Then refresh Rainmeter and verify:

1. Fresh in-stock markets appear even if likelihood says `LEARNING`.
2. No `#1/#2/...` labels.
3. Every visible card has a recognizable country flag on the left.
4. The flag has a white bottom strip with dark elapsed/travel-time text.
5. Country name/code and center travel-time text are absent from the card body.
6. Gross is displayed as `$amount` only; no `gross x18`/quantity suffix.
7. NAME / UPCOMING / GROSS PROFIT / PROFIT/HR reorder immediately.
8. Row control is a `v` chevron.
9. Clicking it expands an in-card 8-hour graph and changes to `^`.
10. Opening another row collapses the first; at most one graph is open.
11. Collapsing/re-expanding does not open the standalone Viewer.
12. `VIEWER >` still opens the separate full Viewer popup.
13. Expanded graph follows the same market through sorting or safely collapses if the market disappears.
14. Zero-stock graph is flat at zero; nonzero retained history shows step changes where data exist.
15. The list remains populated through normal polling and does not flash to a learning placeholder.
16. SETTINGS and Item/Country/Category popups still open and save.
17. No visible PowerShell console or persistent `ERROR` remains.

If anything errors:

```powershell
Get-Content .\data\runtime\logs\travel-assistant.log -Tail 40
```

Send the focused acceptance output and screenshots of one collapsed-list view and one expanded inline graph before marking 0.6 accepted.

## After acceptance

1. Tune flag/chart proportions from the real Rainmeter render.
2. Calibrate probability model as completed cycles accumulate.
3. Add optional Chrome/browser notifications as a consumer of accepted local opportunity timing state.
4. Consider bounded multi-trip sequencing separately from the opportunity browser.
