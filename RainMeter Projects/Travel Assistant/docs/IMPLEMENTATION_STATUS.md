# Travel Assistant Implementation Status

**Checkpoint:** 2026-09-02

**Active run:** stochastic-v1.1 live shadow scoring/calibration, while 0.6.0 compact
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
- the default 128 scoring scenarios begin from a 15-minute base grid over a
  12-hour departure search; short-duration markets use bounded coarse-to-fine
  refinement chosen by independent discovery worlds and publish only ignored
  `data/runtime/stochastic-forecast.json`;
- the stochastic stage runs after immutable legacy UI publication and fails soft;
- `tools/Invoke-StochasticReplay.ps1` provides chronological no-future-leakage
  scoring scaffolding for stochastic-v1.1 and five simple empirical/deterministic
  comparators.

No stochastic state, probability, sort, tooltip, or layout is user-facing. Existing
Safe/Best behavior remains the production baseline.

### Post-Codex connector review

A static connector review of the initial stochastic push found and corrected several
Phase-1/2 edge cases before any promotion work:

- Monte Carlo common-random-number seeds are stable across minute updates instead
  of rotating with wall-clock minute, preventing artificial probability jitter when
  retained evidence has not changed;
- missing one-way travel time fails closed instead of becoming zero-duration travel;
- a long same-phase in-stock collection gap invalidates the old phase anchor but
  retains the new positive snapshot as left-censored/right-censored current evidence;
- the global legacy WindowPlan authority stamp is cleared before every opportunity
  projection and is stamped again only after the authoritative timing pass succeeds;
- offline history building/import now accepts censor-aware schema 2 and preserves
  restock/sellout bounds instead of rebuilding schema-1 exact-event cycles;
- an aged positive provider snapshot is no longer promoted directly to 100% stock-now
  probability; with learned cycle evidence, current-stock survival is conditioned on
  the provider observation time and may sell out before the forecast origin;
- stochastic shadow work now runs after the production resale/MV queue so its
  tens-of-seconds workload does not delay the bounded cache-refresh request;
- replay's simple all-cycle/fractional overlap comparators are named
  `empirical_all_overlap` / `empirical_overlap`; they are not claimed to be an
  exact historical execution of production Safe/Best logic.

These connector changes are statically reviewed only in this environment. The
Windows PowerShell 5.1 focused suite and production shadow runtime must be rerun on
the target host before treating the post-review branch as runtime-accepted.

The connector continuation also implemented bounded adaptive arrival search.
When lower-quartile empirical stock duration is shorter than the base grid step,
a separately seeded 16-32-scenario discovery pass ranks coarse cells by hidden
stock support. At most four cells are refined, with at most 192 additional
candidates plus restock-quantile anchoring inside that same cap. The configured
full scenario count then scores those candidates independently; discovery worlds
do not supply the reported probabilities. This remains shadow-only and requires
target-host performance/calibration evidence before promotion.

Stochastic-v1.1 now also consumes retained intermediate stock observations for
future-cycle quantity. Informative positive-stock declines form a monotone
piecewise depletion shape tied to the sampled cycle; shapes with transition-censor
width greater than 50% of cycle span are rejected and use linear fallback. The
runtime artifact exposes uncapped expected available quantity separately from
requested-load quantity. Offline replay admits only observations whose evidence
timestamp is at or before the historical decision time, and quantity error is
scored only when an exact retained provider snapshot exists at the historical
arrival.

Prospective live shadow scoring is now implemented in
`StochasticCalibration.ps1`. It freezes one genuinely future best-arrival
prediction per model/market/hour, rejects stale artifacts and zero-horizon states,
and resolves outcomes only from later unambiguous retained evidence. Completed
cycle rows now persist `previousSellOutBoundaryQuality`, allowing between-cycle
OOS outcomes only when continuity is explicitly proven. Unresolved rows expire
without affecting metrics. Calibration summaries maintain overall,
evidence-quality, market-specific, and forecast-horizon
Brier/log-loss/reliability statistics. Target/quantity metrics use exact
snapshots when observed and continuity-confirmed OOS as deterministic
target-failure/zero-quantity outcomes. New freezes stop at 24 unresolved rows per
model/market or 4,096 globally, without dropping pending evidence. Brier uses raw
probabilities while log loss alone is clipped for numerical stability. No
calibration transform is user-facing.

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
    ResalePriority
ResaleQueue
    StochasticForecast       # shadow-only; last, fail-soft
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
leave-now, and two wait. This stayed within the once-per-minute shadow-stage
budget for that pre-review run, but artifact size and unchanged-input caching remain
optimization targets. Because stochastic sampling/current-stock conditioning changed
during connector review, rerun this performance/decision-count measurement before
using the recorded numbers as the current baseline.

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
