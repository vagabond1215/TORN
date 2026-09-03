# Next Codex Run: Live Shadow Scoring and Calibration

**Status: ACTIVE — STOCHASTIC-V1.1 SHADOW CALIBRATION + RESTRICTED MULTI-CYCLE CHANCE FALLBACK; 0.6.0 RAINMETER ACCEPTANCE REMAINS OPEN**

The next forecasting phase is deliberately:

```text
live shadow scoring / backtesting
    -> calibration
        -> one authoritative general stochastic decision object
            -> only then general stochastic UI migration

Restricted exception already approved: multi-cycle fallback may expose only earliest-arrival pAnyStock as "Chance to hit: NN%" under its production gate.
```

Do not promote the general stochastic decision/search or label stochastic output Safe/Guaranteed. One explicit exception is now production: `MultiCycleChanceBridge.ps1` may show `Chance to hit: NN%` when the earliest feasible arrival spans >=2 weighted mean cycles, >=3 usable completed cycles exist, and stronger legacy current-cycle/Safe/Best guidance cannot act. Keep legacy actionable guidance as the production baseline and continue scoring the general stochastic model without future leakage.

Use ignored `data/runtime/stochastic-forecast.json` as the challenger artifact,
`data/runtime/stochastic-calibration-state.json` /
`stochastic-calibration.json` for prospective scoring, and
`tools/Invoke-StochasticReplay.ps1` for offline walk-forward scaffolding.
Prediction freezing, continuity-safe stock labels,
overall/evidence-quality/market/horizon Brier/log-loss buckets, exact-snapshot
quantity scoring, and deterministic zero-quantity scoring for continuity-confirmed
OOS outcomes are implemented.
The next run should validate them on Windows, measure their steady-state CPU/wall
cost, and then accumulate prospective evidence before considering regime
adaptation or any visible stochastic UI.

## Post-Codex connector review before the next run

The initial stochastic Phase-1/2 push was reviewed through the GitHub connector and
several correctness issues were fixed directly on `main`. Treat current `main`,
not the original `new forecast model setup` commit, as the starting point.

The review established/fixed:

- stable common-random-number sampling across minute updates;
- fail-closed missing travel times;
- left-censored current-stock retention after long collection gaps;
- generation-scoped legacy WindowPlan authority stamps;
- censor-aware schema-v2 offline history build/import;
- no direct 100% stock-now claim from an aged positive provider snapshot;
- current-stock survival conditioned on provider observation time;
- stochastic shadow execution after the production resale/MV queue;
- replay overlap comparators renamed to `empirical_all_overlap` and
  `empirical_overlap` because they are proxies, not exact production Safe/Best
  replay;
- no-positive-EV grids classified as `NO_ACTIONABLE_TRIP`; `WAIT` is reserved
  for a future explicit delay/value-of-information model.

Before adding model complexity, rerun the target Windows PowerShell focused suite
including `Run-StochasticCalibrationTests.ps1`, then run one production shadow
update and inspect all three stochastic artifacts. The pre-review 25.3-second /
~1 MB measurement is no longer authoritative because adaptive refinement,
observation-shape extraction, prospective evidence scans, and current-stock
conditioning changed. After 20-60 minutes, use updater performance telemetry to
measure `multi-cycle-chance-bridge`, `chance-history`, `resolve-chance-history`, `stochastic-forecast`, and `stochastic-calibration` stages. The bridge is pre-publication and therefore has a stricter latency budget than the shadow search; chance journaling/resolution are deliberately post-publication.

Also inspect `stochastic-calibration.json`: confirm `pendingCount` grows
reasonably, `maximumPendingPerMarket=24`, `maximumPendingTotal=4096`, and no
`stochastic-calibration-error.txt` is present. Do not interpret calibration
quality from a handful of resolved rows; first verify that prospective freezes and
later outcomes are accumulating at all.

Also inspect the new graph/replay telemetry after normal minute updates:

- `chance-history.jsonl` should retain one prospective row per projected market/minute and no rows older than eight hours;
- `resolved-arrival-history.jsonl` should begin filling only after recorded arrivals pass and truth becomes unambiguous;
- `chance-accuracy.json` should expose overall/per-market Brier, log loss, classification accuracy, observed hit rate, predicted rate, and calibration gap;
- `chance-history-error.txt` and `resolve-chance-history-error.txt` should be absent;
- an expanded graph should show the cyan 0..100% chance trace without a second Y-axis, faint periwinkle shading only between modeled >=50% chance-window crossings, plus the faint flight-shifted realized hit/miss waveform. Hover the periwinkle window/edges and blue/orange event ticks to confirm simple Chance window / Restocked / OoS relative-time tooltips. Strict error markers will appear only as predictions actually recorded after this implementation mature.

The flight-shifted realized waveform can populate immediately from retained observations and is intentionally hindsight-only. Do not use it to rebuild an “as known then” forecast. Time/price/phase features may be proposed from it, but promotion requires walk-forward/prospective improvement.

Known stochastic-v1.1 research gaps remain deliberately open:

- the fixed-grid structural miss is now mitigated by bounded independent
  coarse-to-fine discovery/refinement, but the candidate cap can still omit
  low-support peaks and needs target-host performance/calibration evidence;
- empirical piecewise depletion is now used when intermediate observations and
  sufficiently narrow censor bounds exist, but many cycles will still use the
  linear fallback and shape coverage/calibration must be measured;
- Torn resale MV is held fixed during each simulated horizon;
- replay now reports exact-snapshot quantity MAE/RMSE where scorable, while
  restock/sellout interval coverage, profit and regret remain scaffold extensions;
- no calibrated probabilities, change-point model, risk preference, or
  value-of-information solver exists.
- time-of-day conditioning and current-price-conditioned reweighting are not implemented; add them only if walk-forward/prospective scoring demonstrates incremental calibration value beyond joint-cycle resampling.

Do not solve all of these at once. First obtain post-review live shadow evidence.

Long-horizon central/shared-backend work is intentionally deferred and recorded in `FUTURE_DEVELOPMENT_INTENTS.md`. Do not begin that migration during the current acceptance/calibration run.

## Baseline already accepted on the target host

Immediately before the unified-filter redesign, target-host testing at commit `f5a4f0b` established the following:

- Rainmeter loaded without the prior Lua exception storm.
- `!SetOption: Skin "0" does not exist` was eliminated by collapsing the `string.gsub()` multi-return in `StateReader.safeText`.
- the intended compact opportunity cards were restored;
- FlagKit flags rendered;
- Item/Category/Country/Settings popup paths were working;
- the card presentation shown in the target screenshot is the protected visual baseline for this redesign.

Do **not** regress that card layout while accepting the new filter/header surface.

## Current main-view target

The main skin now deliberately has title chrome, update status, three selectable sorts, and the opportunity cards:

```text
Travel                                           [filter] [gear]
[UPCOMING] [GROSS PROFIT] [PROFIT/HR]

[FLAG]  <item> | <foreign cost>   Take:<cash>   Make:<profit>   [$]
        <SAFE/BEST / window guidance>                         [chart]

Updated ...
```

The retired main filter band must **not** return:

```text
ITEM All v   TRIP SHORT MED LONG v   CAT All v   RESET
```

Header rules:

- `Travel` remains the left title.
- A bundled 24x24 filter PNG is immediately left of a bundled 24x24 settings gear PNG.
- The icons are inline with the title and must not expand the skin header.
- The filter icon opens one unified filter panel.
- The gear opens the existing Opportunity Settings popup.
- The sort row moves upward into the space vacated by the retired filter band.
- The opportunity card stack moves upward by the same 32 px as a unit.

### Current card ownership

The old pre-redesign "protected card" boundary is superseded by the accepted compact-card implementation:

- `StateReader.lua` owns projected-row identity, immediate sorting/filtering, expansion identity, and row/card Y/H reflow.
- `CardPresenter.lua` owns visible first-line content and Safe/Best/window presentation.
- `OpportunityRows.inc` declares the fixed Item/Cost, Take, Make, money-button, chart-button, and inline-graph meters.
- `HeaderLayout.lua` performs only the 32 px header compaction and includes Take/Make in that shift.
- `CardTweaks.lua` and `FinalCardPolish.lua` remain non-destructive compatibility points.

Retired independent-card pinning, standalone Viewer, selectable Name sort, standalone independent visible-item cards, and standalone OPTIMAL route UI must not return.

## Unified `TRIP & FILTERS` panel

All normal filter editing is consolidated into one detached WinForms panel.

### Countries — first section

Countries are grouped by the existing configured trip bands:

```text
SHORT:   Mexico, Cayman Islands, Canada
MEDIUM:  Hawaii, United Kingdom, Argentina, Switzerland
LONG:    Japan, China, United Arab Emirates, South Africa
```

Required behavior:

- country controls use compact FlagKit-backed toggle chips;
- each band has inline `All` / `None` actions;
- the Countries section also has global `All` / `None`;
- no separate trip-band toggle row is required;
- a display band is enabled when at least one country in that band is selected;
- `selectedTripBands` remains `short,medium,long` for broad candidate projection;
- `displayTripBands` is derived from the country selections saved by the unified panel;
- an intentionally empty country selection results in an empty display surface, while RESET restores all countries and all three visible bands.

### Categories — second section

- compact toggle chips;
- `All` / `None` actions;
- values are sourced from active/visible local catalog metadata;
- no network request is allowed while opening the panel.

### Items — third section

- searchable local item list;
- check-on-click item toggles;
- `All` / `None` actions;
- query matches local item name/category/id;
- active engine metadata may enrich the list, with committed `items.json` as the local fallback;
- no provider/Torn request occurs while searching or toggling.

### Save / Cancel / Reset

The panel stages edits in memory.

- `Cancel` discards all staged changes.
- `Save` writes one coherent preference state and starts one normal projection refresh.
- `Save` must use `Start-FilterProjectionRefresh`; it must not call `RunUpdate.ps1` directly.
- `Reset` stages all countries, categories and items selected, restores all display bands, and clears `showProfitableOnly`; the reset is persisted only when Save is pressed.

Backward-compatible launcher values `Item`, `Country`, and `Category` may remain accepted by `LaunchFilterPopup.ps1` / `PopupHost.ps1`, but they all route to the unified panel. `Ignore` remains a separate nested Settings popup.

## Compact-card rules — unchanged

The accepted compact card presentation remains authoritative:

- no visible rank number;
- recognizable FlagKit destination flag at left;
- country name is not appended to the item title;
- card title is item name only after the presentation pass;
- header economics remain the accepted foreign-cost / MV / per-item-profit presentation;
- lower line remains actionable Safe/Best state plus confidence/info and `Take:`;
- far-right control is the compact chart Shape button with visual active-state highlight;
- inline history expands in-card through the dedicated local renderer;
- `CardPresenter.lua` remains presentation-only;
- `StateReader.lua` remains authoritative for projected-row identity, local sort/filter state, flag identity, row visibility, and inline graph expansion.

### Safe / Best timing contract

Do not change this logic during filter/header work:

- Safe Window = full empirical scenario overlap, minimum 60 seconds;
- Safe rows suppress confidence and expose the info anchor;
- Best Hit requires strictly greater than 50% empirical support;
- Best confidence updates locally from retained cycles;
- Only flag and visible window/guidance text expose tooltips. Home window tooltips come directly from CardPresenter, traveling/returning/abroad tooltips from TravelStateWindowTweaks, and past departure timestamps are never presented as actionable times;
- outbound travel still filters to the recognized destination and uses landing timing;
- return travel releases that outbound filter.

## Sorting and graphs

Sorting remains:

- `UPCOMING` — earliest actionable/projected opportunity;
- `GROSS PROFIT` — highest total trip profit;
- `PROFIT/HR` — after-tax trip Net divided by configured round-trip flight hours.

Alphabetical Name ordering is fallback-only when no usable timing or profit inputs exist; it is not a selectable control.

Hit likelihood remains separate from sort score.

Inline graph remains:

- local-only `MeasureInlineGraph -> RenderInlineGraph.ps1`;
- one expanded row at a time;
- stable `country:itemId` identity;
- 8-hour visible history;
- no popup routing from the row chart button.

## State / updater architecture

Current production publication is the direct finalized-state architecture:

```text
private mutable build: @Resources/Generated/state.kv
immutable UI snapshot: @Resources/Generated/ui-state-<epoch>-<id>.kv
manifest/heartbeat:     @Resources/Generated/last-update.txt
```

`RunUpdate.ps1` finalizes/filter-projects first, writes one immutable generation, then atomically advances the small manifest. Production Lua readers resolve the complete generation named by `last-update.txt`; `ui-state.kv` is only a legacy numeric-heartbeat fallback.

`PublishedState.lua` remains a compatibility helper only and is not loaded by production measures.

Updater rules remain:

- Rainmeter owns only the short launcher;
- long-running normal update is PowerShell 7;
- `LaunchUpdate.ps1` is reusable/spawn-only;
- named updater mutex prevents overlap;
- popup saves route through the normal updater path;
- no long-running Windows PowerShell `RunUpdate.ps1` process.

## Popup / diagnostics rules

- Popup hosts are hidden STA processes; no persistent console window.
- Launchers return after spawning; nested popup launches must not terminate their parent Settings host.
- Unified filter panel is local-only while browsing/editing.
- Settings gear opens Opportunity Settings.
- Ignore List and Profile/API remain nested Settings actions.

Runtime log:

```text
data/runtime/logs/travel-assistant.log
```

Rainmeter log should also remain free of repeating Lua / `!SetOption` errors.

### 2026-08-26 redraw-stability checkpoint

Target acceptance caught two follow-up issues after the unified-filter pull:

- the short RunCommand launcher's `FinishAction` must redraw only after `StateReader -> HeaderLayout -> CardPresenter -> CardTweaks -> FreshnessGuard -> TravelStateWindowTweaks -> FinalCardPolish`. The retired WindowTooltipTweaks pass must not return.

All explicit redraw paths now complete the entire presentation chain before `!Redraw`. `StateReader` also centralizes immediate sort/trip/graph redraws through that same chain. Hard-stale no-row mode uses the footer-aware 160 px minimum panel height.

### CPU profiling / first steady-state optimizations

The updater now records one compact `[performance]` line after each acquired worker. Each stage reports both pwsh CPU milliseconds and wall milliseconds, so API/network wait is not mistaken for processor work.

Two behavior-preserving reductions are already active:

- the retired `MaintainObservationHistory -Phase PostUpdate` call is no longer launched every minute because PreUpdate already owns migration cleanup and hourly pruning and PostUpdate now returns without extra work;
- `EnsureEngineStateSchema.ps1` first identifies in-stock markets with a genuinely missing `activeCycle`; only that exceptional repair state scans `observations.jsonl`. Normal heartbeats no longer parse the full history file for a repair that is not needed.

After 20-60 minutes of normal operation:

```powershell
cd "C:\Codex\TORN\RainMeter Projects\Travel Assistant"
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tools\Analyze-UpdatePerformance.ps1 -Last 60
```

Rank the next optimization target by `AvgCpuMs` and `P95CpuMs`, not wall time alone.

## Current economics/settings checkpoint

- Declared/list MV is always the sale price used for gross sale; the old 95% MV basis option is retired.
- Tax/trader rate options are 0%, 1%, 2%, 3%, 4%, and 5%.
- Tax is calculated exactly once as `floor(gross sale × rate)` and is subtracted only for net profit.
- `PROFIT/HR` uses after-tax net profit.
- Expanded economics use the current Each/Total label-block layout at 9 pt. Each half has a subtle internal vertical separator between its left/right metric cells; every cell keeps the label left and the monetary value independently right-aligned. MV is top-left; top-right shows the metric not used by the primary card (`$/hr` under UPCOMING/PROFIT, Net under PROFIT/HR). Bottom-left shows per-item foreign Price / exact total purchase Price, and bottom-right shows conditional Tax. `$/hr` uses after-tax Each/Total net divided by `2 x` configured one-way flight time, excluding window/wait time.

## Target-Windows acceptance for the new redesign

First pull and verify the requested commit:

```powershell
cd C:\Codex\TORN
git pull --ff-only origin main
git rev-parse --short HEAD

cd "C:\Codex\TORN\RainMeter Projects\Travel Assistant"
```

Run the focused redesign checks first:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-Filters.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-FilterReset.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-RainmeterSkin.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-CardPresenter.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-OpportunityStateTests.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-StatePublicationArchitecture.ps1
```

If those pass, run the full focused suite:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-CurrentAcceptance.ps1
```

Then fully restart Rainmeter so no pre-pull Lua chunk remains loaded, and verify visually/interactively:

1. Header is one compact line: `Travel`, filter image, gear image.
2. `SETTINGS >` text is gone.
3. ITEM/TRIP/CAT/RESET main band is gone.
4. UPCOMING / PROFIT / PROFIT/HR remain directly below the title as equal 104px rounded buttons with bold 11 pt labels; Name is fallback-only. PROFIT sorts by the displayed signed after-tax total Net, so every positive row ranks above every negative row.
5. Cards show item name only on the left. The large right-side value is total Net under UPCOMING/PROFIT and total round-trip-flight `$/hr` under PROFIT/HR. Unit and exact full-load prices are moved into the expanded strip.
6. The `$` and chart controls are centered in the T-divided end cap; inactive icons are light gray and active Torn-lime fills are inset so the card border/T separators remain visible.
7. Expanded economics use gray vertical `Each` / `Total` label blocks and 9 pt text. A subtle drawn vertical separator divides the two metric cells inside each half; labels sit left and monetary values align to the right edge of their cells. MV is top-left. Top-right is the non-primary profitability metric: `$/hr` under UPCOMING/PROFIT, Net under PROFIT/HR. Bottom-left is Price (unit / total), bottom-right is conditional Tax. The bar remains 34px at 0% Tax, and no text `|` characters appear in the expanded strip.
8. Flags act as left end caps. The 48px square immediately to the right contains 44px Torn item art with a 2px inset; item text begins after that square. Card fill is pure black while gray borders/separators remain visible.
9. Inline graphs are black with a lime stock line, cobalt in-stock/restock markers, and pumpkin out-of-stock/sellout markers. Main sort/filter/settings accents are Torn lime. Card item text is 12 pt, the large primary profitability value is 14 pt, expanded economics text is 9 pt, and the window/guidance line is 9 pt and sits close to the card's bottom border; the Updated footer remains close beneath the final card.
10. Filter image opens exactly one `TRIP & FILTERS` panel without a visible console.
11. Countries are grouped SHORT / MEDIUM / LONG and show FlagKit-backed toggles.
12. Global country All/None and each band All/None work.
13. Category chips and category All/None work.
14. Item search filters the local list while preserving each item's staged checked state.
15. Item All/None works.
16. Cancel makes no preference change.
17. Save closes only the filter panel, launches the dedicated `RefreshFilters` recompute, and the skin remains responsive. Newly enabled category/item rows with retained stock should be calculated in that save-time pass; missing/stale MV targets are priced before publication rather than deferred to later polls. Verify a deselected country and category disappear immediately after the published generation advances.
18. Reopen the panel and confirm saved country/category/item selections round-trip.
19. Reset + Save restores every country/category/item and all three country bands and performs the same refresh/recompute.
20. Clicking a card body opens both its economics strip and inline graph; clicking it again when both are open closes both. `$` and chart retain independent behavior.
21. Gear image opens Opportunity Settings without expanding the main skin.
22. Ignore List opens from Settings without closing Settings.
23. Profile/API opens from Settings without closing Settings.
24. Sorting still works; all three sort buttons are equal width with centered labels, and an expanded inline graph still works.
25. Rainmeter log has zero repeating `publishedState`, `Skin "0"`, Lua nil-index, or malformed SetOption errors.
26. Rainmeter remains running through at least two normal 60-second polling intervals.

If any popup fails, inspect:

```powershell
Get-Content .\data\runtime\logs\travel-assistant.log -Tail 100
```

If Rainmeter logs an error, capture the Rainmeter log and the approximate time since skin load before changing unrelated runtime/history/API data.

## Acceptance boundary

Do not mark the new header/filter redesign accepted solely from static tests. Required target evidence is:

- one screenshot of the compact main header + unchanged cards;
- one screenshot of the unified filter panel showing the country-band/category/item sections;
- clean Rainmeter log after filter Save and at least two poll intervals;
- focused test output.

Only after that should 0.6.0 UI acceptance be advanced.
