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
        <flight/remaining> <safe/best leave guidance> <certainty/info> Take: <$required cash>
```

Up to eight cards are visible, but the PowerShell projection retains a bounded local candidate pool so sort/trip controls do not operate on only the previous eight rows.

### Compact-card rules

- Remove visible `#1/#2/...` place numbers.
- Left side is a recognizable FlagKit destination flag with no separate tile/background strip.
- **Country name is visible only in the flag tooltip.** Hovering the flag shows country name plus configured one-way travel time.
- Card title shows **item name only**.
- Top-line economics show **net profit per item x planned inventory quantity = total net profit**. Current net-profit basis is the configured Torn MV resale basis less foreign purchase price; no hidden probability weighting is applied.
- In the top-line profit equation, monetary values retain the row economics color while the `$` symbols and `/ea xN =` connective text are white.
- Lower-left timing is muted gray. At home/not outbound it shows configured one-way flight duration.
- When Torn reports recognized **outbound travel** (`TravelState=traveling`, `TravelFilterActive=1`, destination country known), only that destination country's opportunities are valid/visible and the lower-left timing is replaced by a locally decrementing landing countdown derived from `TravelArrivalAt` (falling back to projected `TravelTimeLeft` anchored to `TravelContextLastSuccessAt`).
- Return travel to Torn must not show the prior foreign-destination countdown and releases the outbound foreign filter.
- Lower-middle is the actionable Safe/Best leave state. Do not repeat flight duration there.
- The actionable departure/status text itself is a tooltip hitbox. Hovering `LEAVE ...`, `LEAVE BEFORE ...`, or `LEAVE NOW` must show the window calculation described below.
- Safe hits suppress the confidence percentage. The otherwise-empty certainty slot displays a small `ⓘ` fallback tooltip anchor for Safe rows. Best Hit shows live confidence and that confidence text carries the same tooltip.
- Lower-right `Take:` is exact `foreign purchase price x planned quantity` for markets whose retained foreign price has never varied. Once retained analytics demonstrate real foreign-price variance (historical min/max, current-vs-last, or a retained price-change event), `Take:` becomes `foreign purchase price x planned quantity x 1.05`, rounded up to the next dollar. This buffer does not fabricate airfare or resale fees.
- Keep ASCII separators in visible card text to avoid Rainmeter encoding regressions except for the dedicated Safe-window `ⓘ` anchor.
- Far-right control is a compact `v`/`^` chevron, not the word `GRAPH`.
- `CardPresenter.lua` is presentation-only. `StateReader.lua` remains authoritative for local sorting, trip filtering, row identity/visibility and graph expansion.

## Safe Window / Best Hit Window

Completed empirical cycles are treated as repeating `(restock delay + stocked duration)` scenarios. The active forecast uses up to the **48 most recent valid completed cycles**; the longer 90-day cycle store and cycle analytics remain available for learning/analysis.

For each projected cycle, every retained scenario produces a stocked interval:

```text
projected restock -> projected sellout
```

The conservative bounds are:

```text
Early Restock = minimum projected restock
Early Sellout = minimum projected sellout
Late Restock  = maximum projected restock
Late Sellout  = maximum projected sellout

Safe Window = max(all restock starts) -> min(all sellout ends)
```

A Safe Window exists only when that full-scenario overlap is at least **60 seconds**. It is treated as the empirical equivalent of a guarantee and therefore does **not** print a confidence percentage on the card.

Example required behavior:

```text
restock range: 1h50m .. 2h10m
stocked duration: 30m

Early Restock: 1h50m -> 2h20m
Late Restock:  2h10m -> 2h40m
Safe Window:   2h10m -> 2h20m   # 10-minute all-scenario overlap
```

When no nontrivial Safe Window exists for the next usable cycle, Best Hit is the highest empirical-overlap landing segment. Confidence is:

```text
completed scenarios stocked at that landing time / usable completed scenarios
```

Best Hit is actionable only when support is **strictly greater than 50%**. Exactly 50% is not actionable.

Only one mode is printed on the card at a time:

- Before a Safe departure interval opens: `SAFE - LEAVE <countdown>`.
- While inside a non-momentary Safe departure interval: `SAFE - LEAVE BEFORE <countdown to close>`.
- After that Safe interval closes: treat it as missed and target the next usable cycle.
- Before a Best Hit target: `BEST - LEAVE <countdown>` with the target confidence.
- While the current departure would land with **>50%** support: `BEST - LEAVE NOW <live confidence>`.
- If a higher-confidence landing point becomes reachable before support ever falls to 50% or below, count down to that better point instead of keeping the weaker `LEAVE NOW`.
- Once an opened Best Hit falls to **50% or below**, treat it as missed and target the next usable cycle.

The Best Hit percentage is recalculated locally every Rainmeter second from the retained empirical cycle pairs. No provider/API request is required for the live countdown/confidence transition.

### Window tooltip contract

Hovering the actionable Safe/Best status must show the calculation used for that cycle. Best confidence carries the same tooltip; Safe rows also expose the `ⓘ` fallback anchor:

```text
Safe formula: max(restock starts) -> min(sellout ends)
Best formula: completed-cycle overlap / usable cycle count
Early Restock: <estimated earliest restock> - <estimated earliest sellout>
Late Restock: <estimated latest restock> - <estimated latest sellout>
Safe Window: <full-overlap interval or none>
Best Hit Window: <optimal landing time> [confidence]
```

The tooltip reports **arrival** intervals. The visible card translates the selected arrival interval back by the configured flight duration (or uses the current outbound landing time when already flying) to show the appropriate departure guidance.

`WindowPlan.ps1` is local-only and runs after `OpportunityState.ps1` and before `FilterState`/heartbeat. It projects compact `WP2` empirical cycle pairs plus the next bounded window groups into `state.kv`. It also prefixes the row's retained price-variance state for the conditional `Take:` buffer. `CardPresenter.lua` performs the second-by-second state transitions.

## Immediate ordering and trip filtering

Ordering:

- `NAME`: item name ascending, then destination.
- `UPCOMING`: earliest projected Safe/Best departure opportunity first after the completed WindowPlan projection.
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

- Fresh in-stock rows may remain visible while recurring-window evidence is still learning.
- Unknown likelihood is not a fake 0% or 100%.
- Profit/profit-hour can still be calculated from current stock, current foreign price, capacity and cached MV.
- Sold-out/future actionable windows require completed-cycle evidence.
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

1. No rank numbers; FlagKit flag remains the only printed country indicator.
2. Card title is item name only and top-right is `$net/ea xN = $total net`; both `$` symbols and `/ea xN =` render white.
3. At home, lower-left shows configured flight duration in muted gray.
4. While actively flying outbound to a recognized destination, only that country's items are shown and lower-left changes to a live countdown to landing.
5. Safe status hides confidence and exposes `ⓘ`; Best status shows live confidence.
6. Hovering `LEAVE ...` / `LEAVE BEFORE ...` / `LEAVE NOW`, Best confidence, or Safe `ⓘ` shows Early Restock, Late Restock, Safe Window, Best Hit Window and both formulas.
7. A Safe window before opening counts down `SAFE - LEAVE ...`.
8. During Safe departure overlap it becomes `SAFE - LEAVE BEFORE ...` and counts down to close.
9. After Safe close it automatically targets the next usable cycle.
10. Best Hit says `BEST - LEAVE NOW` only while the live departure has >50% modeled support.
11. Exactly 50% does not remain actionable.
12. If a stronger Best point can be reached without support dropping to <=50%, the card switches to the stronger point's countdown.
13. When an opened Best opportunity drops to <=50%, the card advances to the next usable cycle.
14. `Take:` equals exact purchase cash when retained foreign price is invariant; it includes the 5% buffer only after real foreign-price variance has been observed.
15. NAME / UPCOMING / GROSS PROFIT / PROFIT/HR reorder immediately against the full projected pool.
16. SHORT / MED / LONG toggle immediately, including OFF -> ON.
17. Row `v` expands only that in-card graph; it does not spawn the standalone Viewer.
18. Opening another row collapses the first; sorting/trip filtering collapses an open graph.
19. `VIEWER >` still opens the separate full Viewer popup.
20. The list remains populated through normal polling and popups leave no visible PowerShell console.

If anything errors:

```powershell
Get-Content .\data\runtime\logs\travel-assistant.log -Tail 40
```

For one suspicious row, inspect its compact plan with:

```powershell
Select-String .\@Resources\Generated\state.kv `
  -Pattern '^Opportunity1(Tooltip|WindowText|ChanceText|WindowStartAt|ProbabilityValue)='
```

The machine tooltip begins `WP2:` when a timing plan exists and carries a `PV0#` / `PV1#` envelope for fixed/variable foreign-price history. Send the focused acceptance output plus one screenshot showing a Safe or Best state before marking 0.6 accepted.

## After acceptance

1. Tune card/flag/chart proportions from the real Rainmeter render.
2. Calibrate recurring probability using retained cycle analytics and price/sellout regimes once sample sizes are sufficient.
3. Add optional Chrome/browser notifications as a consumer of accepted local opportunity timing state.
4. Consider bounded multi-trip sequencing separately from the opportunity browser.
