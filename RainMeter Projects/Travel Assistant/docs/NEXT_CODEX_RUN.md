# Next Codex Run: Compact Opportunity Cards + Unified Filters

**Status: ACTIVE — 0.6.0 PENDING TARGET-WINDOWS / RAINMETER ACCEPTANCE OF THE 2026-08-26 HEADER/FILTER REDESIGN**

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
- Safe/Best departure text remains a tooltip hitbox with Early Restock, Late Restock, Safe Window and Best Hit evidence;
- outbound travel still filters to the recognized destination and uses landing timing;
- return travel releases that outbound filter.

## Sorting and graphs

Sorting remains:

- `UPCOMING` — earliest actionable/projected opportunity;
- `GROSS PROFIT` — highest total trip profit;
- `PROFIT/HR` — trip profit divided by elapsed hours.

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

- the short RunCommand launcher's `FinishAction` redrew after `StateReader -> HeaderLayout -> CardPresenter -> CardTweaks` but before `FreshnessGuard -> TravelStateWindowTweaks -> WindowTooltipTweaks -> FinalCardPolish`. On a stale provider snapshot this exposed a sub-second intermediate render: header text could flash `UPDATE STALE` before `FORECAST ONLY`, and card meters could flash the intermediate styling.

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
- Expanded economics are split into per-item and total Gross / `<rate>% Tax` / Net halves; the old Per Hour field is no longer shown there.

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
4. UPCOMING / GROSS PROFIT / PROFIT/HR remain directly below the title as rounded buttons; Name is fallback-only.
5. Cards show `Item | unit cost | exact full-load cost` on the left and a large signed total Net on the right; there are no Take/Make labels or variable-price cash buffer.
6. The `$` and chart controls are centered in the T-divided end cap; inactive icons are light gray and active cells are Torn lime with dark icons.
7. Expanded economics are two equal 10pt halves: Each Gross/Tax/Net and Total Gross/Tax/Net.
8. Flags remain present; the Updated footer sits close beneath the final card without the old excess gap.
9. Filter image opens exactly one `TRIP & FILTERS` panel without a visible console.
10. Countries are grouped SHORT / MEDIUM / LONG and show FlagKit-backed toggles.
11. Global country All/None and each band All/None work.
12. Category chips and category All/None work.
13. Item search filters the local list while preserving each item's staged checked state.
14. Item All/None works.
15. Cancel makes no preference change.
16. Save closes only the filter panel, launches one normal refresh, and the skin remains responsive.
17. Reopen the panel and confirm saved country/category/item selections round-trip.
18. Reset + Save restores every country/category/item and all three country bands.
19. Gear image opens Opportunity Settings without expanding the main skin.
20. Ignore List opens from Settings without closing Settings.
21. Profile/API opens from Settings without closing Settings.
22. Sorting still works; all three sort buttons are equal width with centered labels, and an expanded inline graph still works.
23. Rainmeter log has zero repeating `publishedState`, `Skin "0"`, Lua nil-index, or malformed SetOption errors.
24. Rainmeter remains running through at least two normal 60-second polling intervals.

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
