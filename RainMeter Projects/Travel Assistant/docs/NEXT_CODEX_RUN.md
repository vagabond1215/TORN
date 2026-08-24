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

[FLAG]  <item> - <country>                    <$gross>   v
        <window>  <leave>  <chance>    BUY <$foreign>/ea | MV <$MV>
```

Up to eight cards are visible, but the PowerShell projection retains a bounded local candidate pool so sort/trip controls do not operate on only the previous eight rows.

### Compact-card rules

- Remove visible `#1/#2/...` place numbers.
- Left side is a recognizable FlagKit destination flag with no separate tile/background strip.
- Hovering the flag shows country name plus configured one-way travel time.
- Card title shows **item name + country name**; do not show a separate country abbreviation.
- Visible gross is only `$amount`; no `gross` suffix and no `xN` suffix.
- Quantity remains in internal projection/tooltips for inspectable economics.
- Lower-right price text explicitly distinguishes `BUY $foreign/ea` from `MV $marketValue`.
- Use ASCII separators in card text (`-`, `|`) to avoid Rainmeter encoding regressions.
- Far-right control is a compact `v`/`^` chevron, not the word `GRAPH`.

## Immediate ordering and trip filtering

Ordering:

- `NAME`: item name ascending, then destination.
- `UPCOMING`: earliest current/modeled stock window first.
- `GROSS PROFIT`: highest trip gross first.
- `PROFIT/HR`: trip gross / total elapsed hours, descending.
- Hit likelihood remains a separate decision variable and is not multiplied into any sort score.

Both sort and trip-band clicks must update the visible list immediately in Lua against the already-projected candidate pool.

Trip bands:

```text
SHORT:  Mexico, Cayman Islands, Canada
MED:    Hawaii, United Kingdom, Argentina, Switzerland
LONG:   Japan, China, UAE, South Africa
```

Persistent preferences separate candidate scope from display scope:

```text
selectedTripBands = short,medium,long   # always retained for candidate projection
displayTripBands  = user-selected visible bands
```

`FilterPreferences.ps1 -Action ToggleTripBand` is a tiny local persistence write. It must not invoke `OpportunityState.ps1` or wait on a provider/model recomputation.

## Inline card graph

The row chevron expands an 8-hour stock graph **inside that card/list**.

- Only one inline graph may be expanded at a time.
- Opening a different card collapses the previous one.
- Clicking the open card again collapses it.
- Sort or trip-band changes collapse the open graph.
- Stable `country:itemId` identity targets graph data.
- Expanded cards reflow later rows and panel height.
- Inline graph rendering is local-only through dedicated `MeasureInlineGraph` / `RenderInlineGraph.ps1`.
- It must never route through the standalone Viewer launcher.
- An open inline graph can refresh locally at approximately one-minute cadence.
- The 8-hour graph has seven evenly spaced internal vertical separators: one-hour segments.
- Y-axis labels are sparse: retained numeric maximum at the upper-left, `0` at the lower-left.
- X-axis keeps `-8h` at the lower-left; the right edge means now.
- Do not display `8H STOCK`, `max`, retained-point counts, stock-change counts, or other graph summary prose.
- Zero-stock-only history must plot flat at zero rather than a fabricated `0..1` axis.

`VIEWER >` remains a **separate standalone WinForms market browser**. The row chevron must never open it.

## Current stock and recurring likelihood

Fresh current stock must not vanish because completed-cycle likelihood evidence is incomplete.

- Fresh in-stock rows may show `LEARNING` in the likelihood field.
- Unknown likelihood is not a fake 0% or 100%.
- Gross/profit-hour can still be calculated from current stock, current foreign price, capacity and cached MV.
- Sold-out/future opportunities require completed cycle evidence.
- Completed cycles are modeled as repeating empirical `out-of-stock delay + stocked duration` pairs so a trip may deliberately target a later stock cycle when the current cycle cannot survive the flight.
- Stale stock, unresolved MV, explicit filters, waste policy, or travel restriction may still legitimately remove a row.

## History / Viewer

Both inline and standalone graph surfaces use the same retained local truth:

- 8-hour visible history;
- 48h high-resolution observation retention;
- 90d completed-cycle retention;
- change-only predecessor/baseline carry-forward only when backed by a real predecessor;
- no provider/Torn request to view a graph;
- no forecast-to-history mutation.

The standalone Viewer retains its richer dropdown and diagnostics. Inline graphs are deliberately compact.

## Popups / diagnostics

Settings, Item/Country/Category filters, Ignore List, Profile/API and standalone Viewer use hidden STA popup hosts. No PowerShell console should remain visible.

Runtime failures:

```text
data/runtime/logs/travel-assistant.log
```

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
3. Every card has a recognizable FlagKit country flag.
4. Flag hover shows country + one-way travel time.
5. Card title visibly shows `item - country`.
6. Lower-right text clearly reads `BUY $.../ea | MV $...`.
7. Gross is `$amount` only.
8. NAME / UPCOMING / GROSS PROFIT / PROFIT/HR reorder immediately against the full projected pool.
9. SHORT / MED / LONG toggle color and visible rows immediately, including OFF -> ON, without waiting for PowerShell opportunity recomputation.
10. Row `v` expands only that in-card graph; it does not spawn the standalone Viewer.
11. The graph has seven internal hourly vertical separators.
12. Opening another row collapses the first; sorting/trip filtering collapses an open graph.
13. `VIEWER >` still opens the separate full Viewer popup.
14. Zero-stock graph stays flat at zero; nonzero retained history shows real transitions.
15. The list remains populated through normal polling.
16. SETTINGS and popups still work with no visible PowerShell console.

If anything errors:

```powershell
Get-Content .\data\runtime\logs\travel-assistant.log -Tail 40
```

Send the focused acceptance output plus one collapsed-card screenshot and one expanded-card screenshot before marking 0.6 accepted.

## After acceptance

1. Tune card/flag/chart proportions from the real Rainmeter render.
2. Calibrate recurring probability as completed cycles accumulate.
3. Add optional Chrome/browser notifications as a consumer of accepted local opportunity timing state.
4. Consider bounded multi-trip sequencing separately from the opportunity browser.
