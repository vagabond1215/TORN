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
- filter icon opens one unified `TRIP & FILTERS` popup;
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

- grouped SHORT / MEDIUM / LONG from `config/countries.json`;
- FlagKit-backed compact chips;
- All/None globally and per band;
- `displayTripBands` is derived from bands containing at least one selected country;
- `selectedTripBands` remains all three for broad candidate projection.

### Categories

- compact toggle chips;
- All/None;
- active local catalog categories.

### Items

- searchable `CheckedListBox`;
- All/None;
- search covers item name/category/id;
- engine metadata is optional; committed catalog is the local fallback.

### Persistence

- changes are staged until Save;
- Cancel writes nothing;
- Save writes one coherent preference state and calls `Start-FilterProjectionRefresh` once;
- Reset stages all countries/categories/items selected, all display bands restored, and profitable-only cleared;
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
@Resources/Generated/ui-state.kv    finalized atomic UI snapshot
@Resources/Generated/last-update.txt numeric heartbeat
```

Production Lua readers read finalized `ui-state.kv` directly. `PublishedState.lua` remains only a compatibility shim for stale/transitional loaded Lua.

`LaunchUpdate.ps1` starts the long-running normal worker under PowerShell 7 and returns; the named updater mutex serializes workers. Popup saves use the normal launcher path rather than a direct Windows PowerShell `RunUpdate.ps1` process.

## Current runtime order

```text
MaintainObservationHistory -Phase PreUpdate
ShadowCollector
ProjectCollectedState
MaintainObservationHistory -Phase PostUpdate
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
- 32 px geometry-only header compaction;
- existing card presenter and Rainmeter card contracts;
- popup launch detachment and updater routing;
- the Lua multi-return SetOption regression.

This execution environment does not provide Windows PowerShell/Rainmeter, so the redesigned WinForms surface and Rainmeter render have **not** been executed here. Target acceptance must run the focused checks and visual/interactivity checklist in `docs/NEXT_CODEX_RUN.md`.

## Next acceptance evidence required

1. focused filter/reset/Rainmeter/card tests pass on target Windows;
2. compact header screenshot shows Travel + filter PNG + gear PNG with no old filter band;
3. card screenshot matches the accepted card baseline except for the uniform 32 px upward shift;
4. unified filter screenshot shows country bands, categories and searchable items;
5. Save/Cancel/Reset round-trip correctly;
6. Settings/Ignore/Profile/Viewer remain functional;
7. Rainmeter log stays clean for at least two normal poll intervals.
