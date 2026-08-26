# Next Codex Run: Compact Opportunity Cards + Unified Filters

**Status: ACTIVE — 0.6.0 PENDING TARGET-WINDOWS / RAINMETER ACCEPTANCE OF THE 2026-08-26 HEADER/FILTER REDESIGN**

## Baseline already accepted on the target host

Immediately before the unified-filter redesign, target-host testing at commit `f5a4f0b` established the following:

- Rainmeter loaded without the prior Lua exception storm.
- `!SetOption: Skin "0" does not exist` was eliminated by collapsing the `string.gsub()` multi-return in `StateReader.safeText`.
- the intended compact opportunity cards were restored;
- FlagKit flags rendered;
- Item/Category/Country/Settings/Viewer popup paths were working;
- the card presentation shown in the target screenshot is the protected visual baseline for this redesign.

Do **not** regress that card layout while accepting the new filter/header surface.

## Current main-view target

The main skin now deliberately has only title chrome, update status, sorting, Viewer, and the existing opportunity cards:

```text
Travel                                           [filter] [gear]
Updated ...
NAME   UPCOMING   GROSS PROFIT   PROFIT/HR          VIEWER >

[FLAG]  <item>       <foreign cost>  MV:<market value> | <profit/ea>     v
        <SAFE/BEST guidance>   <info/confidence>                Take: <$cash>
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

### Protected card boundary

The header/filter redesign must not alter card internals. In particular, do not modify these files as part of this redesign:

```text
@Resources/Includes/OpportunityRows.inc
@Resources/Scripts/CardPresenter.lua
@Resources/Scripts/CardTweaks.lua
```

`HeaderLayout.lua` is the only new card-adjacent presentation layer. Its contract is intentionally narrow:

- detect a freshly laid-out stack at the historical `Y=120` origin;
- shift the existing card meters upward exactly 32 px;
- reduce `PanelHeight` by exactly 32 px;
- mutate `Y` only;
- never mutate card X/W/H/text/colors/economics/flag identity or graph content;
- never launch a command, update, provider request, or popup.

This avoids rewriting the large `StateReader.lua` layout path during a UX-only change.

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
- far-right control remains the compact `v` / `^` chevron;
- inline history expands in-card and never routes through the standalone Viewer;
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

## Sorting and graphs — unchanged

Sorting remains:

- `NAME` — item name ascending, then destination;
- `UPCOMING` — earliest actionable/projected opportunity;
- `GROSS PROFIT` — highest total trip profit;
- `PROFIT/HR` — trip profit divided by elapsed hours.

Hit likelihood remains separate from sort score.

Inline graph remains:

- local-only `MeasureInlineGraph -> RenderInlineGraph.ps1`;
- one expanded row at a time;
- stable `country:itemId` identity;
- 8-hour visible history;
- no Viewer popup routing from the row chevron.

`VIEWER >` remains the separate standalone market browser.

## State / updater architecture

Current production publication is the direct finalized-state architecture:

```text
private mutable build: @Resources/Generated/state.kv
final UI snapshot:     @Resources/Generated/ui-state.kv
heartbeat:             @Resources/Generated/last-update.txt
```

`RunUpdate.ps1` finalizes/filter-projects first, then atomically replaces `ui-state.kv`, then advances the numeric heartbeat. Production Lua readers read finalized `ui-state.kv` directly.

`PublishedState.lua` exists only as a compatibility shim for transitional/stale loaded Lua and must not become the production publication architecture again without new target evidence.

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
- Viewer remains separate.

Runtime log:

```text
data/runtime/logs/travel-assistant.log
```

Rainmeter log should also remain free of repeating Lua / `!SetOption` errors.

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
4. NAME / UPCOMING / GROSS PROFIT / PROFIT/HR / VIEWER remain directly below update status.
5. Cards are visually identical to the accepted pre-redesign reference except the whole stack begins ~32 px higher.
6. Flags remain present and card title/economics/Safe-Best/Take geometry is unchanged.
7. Filter image opens exactly one `TRIP & FILTERS` panel without a visible console.
8. Countries are grouped SHORT / MEDIUM / LONG and show FlagKit-backed toggles.
9. Global country All/None and each band All/None work.
10. Category chips and category All/None work.
11. Item search filters the local list while preserving each item's staged checked state.
12. Item All/None works.
13. Cancel makes no preference change.
14. Save closes only the filter panel, launches one normal refresh, and the skin remains responsive.
15. Reopen the panel and confirm saved country/category/item selections round-trip.
16. Reset + Save restores every country/category/item and all three country bands.
17. Gear image opens Opportunity Settings without expanding the main skin.
18. Ignore List opens from Settings without closing Settings.
19. Profile/API opens from Settings without closing Settings.
20. Viewer remains separate and functional.
21. Sorting still works and an expanded graph still works.
22. Rainmeter log has zero repeating `publishedState`, `Skin "0"`, Lua nil-index, or malformed SetOption errors.
23. Rainmeter remains running through at least two normal 60-second polling intervals.

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
