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

[FLAG]  <item>             <$net/ea> x<qty> = <$total net>   v
        <flight/remaining> <status/window + leave> <certainty> Take: <$buy cash +5%>
```

Up to eight cards are visible, but the PowerShell projection retains a bounded local candidate pool so sort/trip controls do not operate on only the previous eight rows.

### Compact-card rules

- Remove visible `#1/#2/...` place numbers.
- Left side is a recognizable FlagKit destination flag with no separate tile/background strip.
- **Country name is visible only in the flag tooltip.** Hovering the flag shows country name plus configured one-way travel time.
- Card title shows **item name only**.
- Top-line economics show **net profit per item x planned inventory quantity = total net profit**. Current net-profit basis is the configured Torn MV resale basis less foreign purchase price; no hidden probability weighting is applied.
- Lower-left timing is muted gray. At home/not outbound it shows configured one-way flight duration.
- When Torn reports recognized **outbound travel** (`TravelState=traveling`, `TravelFilterActive=1`, destination country known), only that destination country's opportunities are valid/visible and the lower-left timing is replaced by a locally decrementing landing countdown derived from `TravelArrivalAt` (falling back to projected `TravelTimeLeft` anchored to `TravelContextLastSuccessAt`).
- Return travel to Torn must not show the prior foreign-destination countdown and releases the outbound foreign filter.
- Lower-middle text combines current/modeled stock window with the leave instruction.
- Hit likelihood/certainty remains a separate visible field.
- Lower-right `Take:` is `foreign purchase price x planned quantity x 1.05`, rounded up to the next dollar. This is purchase cash plus a 5% carry buffer; it does not fabricate airfare or resale fees.
- Keep ASCII separators in visible card text to avoid Rainmeter encoding regressions.
- Far-right control is a compact `v`/`^` chevron, not the word `GRAPH`.
- `CardPresenter.lua` is presentation-only. `StateReader.lua` remains authoritative for local sorting, trip filtering, row identity/visibility and graph expansion.

## Immediate ordering and trip filtering

Ordering:

- `NAME`: item name ascending, then destination.
- `UPCOMING`: earliest current/modeled stock window first.
- `GROSS PROFIT`: highest total trip profit first. Label is retained for now even though the compact card describes the displayed spread as net profit.
- `PROFIT/HR`: trip profit / total elapsed hours, descending.
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
- Profit/profit-hour can still be calculated from current stock, current foreign price, capacity and cached MV.
- Sold-out/future opportunities require completed cycle evidence.
- Completed cycles are modeled as repeating empirical `out-of-stock delay + stocked duration` pairs so a trip may deliberately target a later stock cycle when the current cycle cannot survive the flight.
- Cycle analytics retain min/max/mean/variance for restock and sellout durations plus material price/sellout regimes for later calibrated forecasting.
- Stale stock, unresolved MV, explicit filters, waste policy, or travel restriction may still legitimately remove a row. A positive cached MV up to the bounded stale-MV display limit may remain visible as stale while resale refresh catches up.

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
4. Flag hover is the only country-name display and shows country + one-way travel time.
5. Card title visibly shows item name only.
6. Top-right reads `$net/ea xN = $total net`.
7. At home, lower-left shows the configured flight duration in muted gray.
8. While actively flying outbound to a recognized destination, only that country's items are shown and lower-left changes to a live countdown to landing.
9. Return travel to Torn does not retain the outbound-country countdown/filter.
10. Lower-middle shows stock/window plus leave instruction; certainty remains separate.
11. Lower-right reads `Take: $...` and equals purchase cash plus 5%.
12. NAME / UPCOMING / GROSS PROFIT / PROFIT/HR reorder immediately against the full projected pool.
13. SHORT / MED / LONG toggle color and visible rows immediately, including OFF -> ON, without waiting for PowerShell opportunity recomputation.
14. Row `v` expands only that in-card graph; it does not spawn the standalone Viewer.
15. The graph has seven internal hourly vertical separators.
16. Opening another row collapses the first; sorting/trip filtering collapses an open graph.
17. `VIEWER >` still opens the separate full Viewer popup.
18. Zero-stock graph stays flat at zero; nonzero retained history shows real transitions.
19. The list remains populated through normal polling.
20. SETTINGS and popups still work with no visible PowerShell console.

If anything errors:

```powershell
Get-Content .\data\runtime\logs\travel-assistant.log -Tail 40
```

Send the focused acceptance output plus one collapsed-card screenshot and one expanded-card screenshot before marking 0.6 accepted.

## After acceptance

1. Tune card/flag/chart proportions from the real Rainmeter render.
2. Calibrate recurring probability using the retained cycle analytics and price/sellout regimes once sample sizes are sufficient.
3. Add optional Chrome/browser notifications as a consumer of accepted local opportunity timing state.
4. Consider bounded multi-trip sequencing separately from the opportunity browser.