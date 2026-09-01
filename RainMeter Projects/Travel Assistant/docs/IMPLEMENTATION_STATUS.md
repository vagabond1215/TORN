# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-26

**Active run:** 0.6.0 compact opportunity surface + unified filter/header redesign. `docs/NEXT_CODEX_RUN.md` is the authoritative target-Windows acceptance checklist.

## Accepted target-host baseline before this redesign

At commit `f5a4f0b`, target testing confirmed:

- Rainmeter loaded without the prior Lua exception storm;
- the `Skin "0" does not exist` SetOption flood was fixed;
- intended compact cards were restored;
- FlagKit flags rendered;
- the existing popup paths opened;
- the card screenshot supplied by the user is the protected visual baseline.

The current redesign must preserve that card presentation.

## Unified main header — IMPLEMENTED, TARGET ACCEPTANCE PENDING

The retired main filter band is removed:

```text
ITEM All v   TRIP SHORT MED LONG v   CAT All v   RESET
```

The new main chrome is:

```text
Travel                                           [filter] [gear]
Updated ...
NAME   UPCOMING   GROSS PROFIT   PROFIT/HR          VIEWER >
```

Implementation details:

- filter and settings are bundled 24x24 PNG Image meters;
- filter icon opens one unified compact filter popup;
- settings gear opens the existing Opportunity Settings popup;
- sort row moves upward into the retired filter-band space;
- `HeaderLayout.lua` shifts the already-laid-out opportunity stack upward exactly 32 px and reduces panel height by the same amount;
- the layout shim mutates only Y/PanelHeight and performs no provider/update work.

Protected card files were intentionally not edited by the redesign:

```text
@Resources/Includes/OpportunityRows.inc
@Resources/Scripts/CardPresenter.lua
@Resources/Scripts/CardTweaks.lua
```

## Unified filter panel — IMPLEMENTED, TARGET ACCEPTANCE PENDING

`OpenUnifiedFilterPopup.ps1` is a staged local WinForms editor.

### Countries

- grouped S / M / L rows from `config/countries.json`;
- FlagKit-backed flag-only chips with country-name tooltips;
- per-band ON/OFF controls inline with each row;
- `displayTripBands` is derived from bands containing at least one selected country;
- `selectedTripBands` remains all three for broad candidate projection.

### Categories

- compact toggle chips;
- ON/OFF;
- active local catalog categories.

### Items

- searchable `CheckedListBox` scoped live by the selected countries and categories;
- compact inline search and ON/OFF controls;
- search covers item name/category/id;
- engine metadata is optional; committed catalog is the local fallback.

### Persistence

- changes are staged until Save;
- Cancel writes nothing;
- Save writes one coherent preference state and calls `Start-FilterProjectionRefresh` once;
- Reset is aligned with Save/Cancel and stages all countries/categories/items selected, all display bands restored, and profitable-only cleared;
- Item/Country/Category legacy launcher values route to the unified panel;
- Ignore List remains separate for nested Opportunity Settings use.

The panel is local-only while browsing and filtering.

## Compact cards — IMPLEMENTED; REDESIGN MUST NOT CHANGE THEM

Accepted presentation remains:

- FlagKit destination flag;
- item-only title after presentation pass;
- accepted cost / MV / per-item profit header;
- Safe/Best timing guidance;
- info/confidence behavior;
- `Take:` cash requirement;
- compact `v` / `^` inline graph control;
- no rank number;
- no separate country label.

Safe/Best model, travel-state behavior, sort semantics and graph transport are unchanged by the filter/header redesign.

## State and updater architecture

Current production roles are:

```text
@Resources/Generated/state.kv       private mutable build state
@Resources/Generated/ui-state-<epoch>-<id>.kv immutable finalized UI snapshot
@Resources/Generated/last-update.txt          generation manifest
```

Production Lua readers resolve complete immutable generations directly from `last-update.txt`. The former `ui-state.kv` remains a transition fallback for a numeric legacy heartbeat; `PublishedState.lua` is retained only as a compatibility helper and is not loaded by production measures.

`LaunchUpdate.ps1` starts the long-running normal worker under PowerShell 7 and returns; the named updater mutex serializes workers. Popup saves use the normal launcher path rather than a direct Windows PowerShell `RunUpdate.ps1` process.

The resale priority pass does not accelerate legitimate empty-market responses (zero average and no listings); those retain the normal queue backoff so other stale items continue refreshing.

## Current runtime order

```text
MaintainObservationHistory -Phase PreUpdate
ShadowCollector
ProjectCollectedState
LocalCatalog
EnsureEngineStateSchema
FinalizeState
TravelContext
CurrentCapacityRefresh
CycleAnchorReconciler
OptimalRoute
OpportunityState
WindowPlan
PriceVariationRefiner
FilterState
atomic finalized ui-state.kv + numeric heartbeat
CycleAnalytics
TrendForecast
ResalePriority
ResaleQueue
```

## Validation status

Static/focused tests have been updated to guard:

- unified popup existence/routing;
- staged save/reset semantics;
- local-only popup behavior;
- bundled filter/settings image assets;
- removal of old main filter meters;
- 3 short / 4 medium / 4 long destination grouping;
- cadence-aware capture-gap exclusion without deleting retained cycles;
- live in-stock sellout priority followed by observed-OOS restock timing;
- 32 px geometry-only header compaction;
- existing card presenter and Rainmeter card contracts;
- popup launch detachment and updater routing;
- Viewer launcher validation against the reusable `.NET ProcessStartInfo` contract rather than retired `Start-Process`;
- full presentation-pipeline completion before any explicit Rainmeter redraw, preventing transient `UPDATE STALE` / intermediate-card flashes;
- compact 132 px hard-stale/no-row geometry;
- one compact updater performance sample per completed worker with per-stage pwsh CPU and wall milliseconds;
- elimination of the retired no-op PostUpdate history invocation;
- steady-state EngineState schema repair avoids scanning observations.jsonl unless an in-stock market actually lacks activeCycle;
- the Lua multi-return SetOption regression.

This execution environment does not provide Windows PowerShell/Rainmeter, so the redesigned WinForms surface and Rainmeter render have **not** been executed here. Target acceptance must run the focused checks and visual/interactivity checklist in `docs/NEXT_CODEX_RUN.md`.

## Next acceptance evidence required

1. focused filter/reset/Rainmeter/card tests pass on target Windows;
2. compact header screenshot shows Travel + filter PNG + gear PNG with no old filter band;
3. card screenshot matches the accepted card baseline except for the uniform 32 px upward shift;
4. unified filter screenshot shows country bands, categories and searchable items;
5. Save/Cancel/Reset round-trip correctly;
6. Settings/Ignore/Profile/Viewer remain functional;
7. Rainmeter log stays clean for at least two normal poll intervals;
8. after 20-60 minutes, run `tools\Analyze-UpdatePerformance.ps1` and use AvgCpuMs / P95CpuMs to select the next CPU optimization target.
