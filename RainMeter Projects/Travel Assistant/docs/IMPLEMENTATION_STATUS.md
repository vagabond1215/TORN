# Travel Assistant Implementation Status

**Checkpoint:** 2026-09-02

**Active run:** stochastic-v1 live shadow scoring/calibration, while 0.6.0 compact
opportunity surface target-Windows acceptance remains open. `docs/NEXT_CODEX_RUN.md`
is the authoritative next-run handoff.

## Stochastic-window Phase 1/2 — IMPLEMENTED IN SHADOW MODE

- `WindowPlan.ps1` is the single production legacy timing entrypoint and now runs
  the richer current-cycle/Safe/Best implementation;
- generation-scoped refiner fields are cleared and initialized, eliminating stale
  cross-generation values;
- observation schema 2 records depletion evidence; a zero-ending interval is
  explicitly demand-censored and stores only a lower bound;
- cycle schema 2 retains transition bounds, explicit evidence quality,
  left-censored partial starts, and durable right-censored active cycles;
- `StochasticForecast.ps1` performs deterministic, recency-weighted empirical
  joint-cycle resampling through multiple future cycles;
- the default 128 scenarios evaluate a 15-minute grid over a 12-hour departure
  search and publish only ignored `data/runtime/stochastic-forecast.json`;
- the stochastic stage runs after immutable legacy UI publication and fails soft;
- `tools/Invoke-StochasticReplay.ps1` provides chronological no-future-leakage
  scoring scaffolding for stochastic-v1 and five deterministic baselines.

No stochastic state, probability, sort, tooltip, or layout is user-facing. Existing
Safe/Best behavior remains the production baseline.

## Accepted target-host baseline before this redesign

At commit `f5a4f0b`, target testing confirmed:

- Rainmeter loaded without the prior Lua exception storm;
- the `Skin "0" does not exist` SetOption flood was fixed;
- intended compact cards were restored;
- FlagKit flags rendered;
- the existing popup paths opened;
- the card screenshot supplied by the user is the protected visual baseline.

The current main branch has since advanced beyond that pre-redesign card snapshot. Current card ownership and geometry are defined by `AGENTS.md`, `ARCHITECTURE.md`, `CardPresenter.lua`, `StateReader.lua`, and `Validate-CardDetailLayout.ps1`.

## Unified main header — IMPLEMENTED, TARGET ACCEPTANCE PENDING

The retired main filter band is removed:

```text
ITEM All v   TRIP SHORT MED LONG v   CAT All v   RESET
```

The new main chrome is:

```text
Travel                                           [filter] [gear]
Updated ...
[UPCOMING] [GROSS PROFIT] [PROFIT/HR]
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
- compact highlighted chart-button inline graph control;
- no rank number;
- no separate country label.

Safe/Best model, travel-state behavior and graph transport remain current. The standalone OPTIMAL route UI, independent visible-item cards, card pinning, standalone Viewer, and selectable Name sort are retired; `OptimalRoute.ps1` remains only as a shared local helper library.

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
OpportunityState
WindowPlan
PriceVariationRefiner
FilterState
atomic finalized ui-state.kv + numeric heartbeat
    CycleAnalytics
    TrendForecast
    StochasticForecast       # shadow-only; after UI publication; fail-soft
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
- full presentation-pipeline completion before any explicit Rainmeter redraw, preventing transient `UPDATE STALE` / intermediate-card flashes;
- compact 160 px hard-stale/no-row geometry with footer reserve;
- one compact updater performance sample per completed worker with per-stage pwsh CPU and wall milliseconds;
- elimination of the retired no-op PostUpdate history invocation;
- steady-state EngineState schema repair avoids scanning observations.jsonl unless an in-stock market actually lacks activeCycle;
- observation/cycle history readers used by inline graph, graph hover, cycle-anchor repair, and engine-schema repair use delete-sharing streams so they cannot block the collector's append/atomic-replace path;
- ShadowCollector engine-state publication uses the shared unique-temp atomic writer and per-journal append mutexes, eliminating fixed .tmp collisions under Rainmeter/OneDrive contention;
- the Lua multi-return SetOption regression.
- censor-aware transition bounds and provider-source clock authority;
- observed nonzero depletion versus sellout-censored demand;
- left/right-censored cycle retention and weaker collection-gap quality;
- authoritative WindowPlan ownership and stale-field clearing;
- stochastic multi-cycle arrival simulation, travel feasibility, tax authority,
  determinism, replay cutoffs, zero-network behavior, and fail-soft order.

The 2026-09-02 retained-history performance check covered 72 projected markets.
The initial 256-scenario diagnostic completed in about 35.2 seconds; the runtime
default was therefore set to 128 scenarios. The final default run completed in
25.30 seconds wall time under Windows PowerShell 5.1 (24.66 seconds recorded
inside the stage), produced 49 arrival points per sufficiently trained market,
and wrote a 1,011,026-byte artifact. All emitted probabilities were within
`[0,1]`; the 72 market decisions were 47 insufficient-data, 16 leave-in, seven
leave-now, and two wait. This stays within the once-per-minute shadow-stage
budget, but artifact size and unchanged-input caching remain optimization targets.

This execution environment does not provide Windows PowerShell/Rainmeter, so the redesigned WinForms surface and Rainmeter render have **not** been executed here. Target acceptance must run the focused checks and visual/interactivity checklist in `docs/NEXT_CODEX_RUN.md`.

## Next acceptance evidence required

1. focused filter/reset/Rainmeter/card tests pass on target Windows;
2. compact header screenshot shows Travel + filter PNG + gear PNG with no old filter band;
3. card screenshot matches the accepted card baseline except for the uniform 32 px upward shift;
4. unified filter screenshot shows country bands, categories and searchable items;
5. Save/Cancel/Reset round-trip correctly;
6. Settings/Ignore/Profile remain functional and inline chart expansion is functional;
7. Rainmeter log stays clean for at least two normal poll intervals;
8. after 20-60 minutes, run `tools\Analyze-UpdatePerformance.ps1` and use AvgCpuMs / P95CpuMs to select the next CPU optimization target.
