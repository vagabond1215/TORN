# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-26

**Active run:** 0.6.0 compact opportunity surface. See `docs/NEXT_CODEX_RUN.md` for the authoritative acceptance checklist.

## Accepted data foundation

Previously target-Windows validated foundation:

```text
11 foreign countries collected
232 provider country-item rows at last live check
227 active market relationships
202 distinct observed items
202 metadata rows
202 categories resolved
5 verified legacy provider rows excluded from new learning/economics work
```

Also previously accepted:

- provider-name enrichment and offline category/catalog authority;
- bounded one-request Torn Item Market pricing;
- `/user/perks` general capacity behavior;
- Flower/Toy category-capacity isolation;
- Airstrip general/Xanax 18 and Standard 13 on the target profile.

These are historical target-host baselines, not timeless live counts.

## 0.6 compact opportunity UI — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

Primary controls:

```text
ITEM All v   TRIP SHORT MED LONG v   CAT All v   RESET
NAME   UPCOMING   GROSS PROFIT   PROFIT/HR          VIEWER >
```

Current compact card target:

```text
[FLAG]  item             $net/ea xN = $total net   v
        flight/remaining  Safe/Best guidance  info/confidence  Take: $cash
```

Implemented behavior includes:

- no visible rank numbers;
- country appears only in the flag tooltip;
- FlagKit flag assets rather than vector flag approximations;
- item-only card title;
- visible per-item × quantity = total economics equation;
- home one-way flight time / recognized-outbound live landing countdown;
- Safe/Best live guidance with detailed arrival-window tooltip;
- Safe confidence suppression with `ⓘ` fallback anchor;
- conditional 5% `Take:` buffer only after retained foreign-price variance is demonstrated;
- `v`/`^` inline graph control;
- immediate local NAME / UPCOMING / GROSS PROFIT / PROFIT/HR sorting;
- immediate local SHORT / MED / LONG display filtering.

Fresh observed in-stock markets may remain visible with `LEARNING` likelihood while recurring evidence is incomplete. Sold-out future opportunities still require completed-cycle evidence.

## Trip-band model — IMPLEMENTED

Schema 7 separates candidate scope from visible scope:

```text
selectedTripBands = short,medium,long   # always retained for candidate projection
displayTripBands  = user-selected visible bands
```

Trip-band clicks filter/reorder the already-projected candidate pool immediately in Lua and persist via a tiny local write.

The Country popup now follows `displayTripBands`. Country selections outside currently visible bands are preserved so re-enabling a band restores its prior country-level exceptions.

## Inline card graph — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

`StateReader.lua` owns inline expansion state and invokes dedicated `MeasureInlineGraph` / `RenderInlineGraph.ps1` local rendering.

- only one graph expanded at a time;
- stable `country:itemId` identity through sorting;
- lower rows and panel height reflow locally;
- open graph may refresh locally around once/minute;
- 8-hour retained history only;
- no provider/Torn request;
- no forecast-to-history mutation;
- zero-stock-only history remains flat at zero.

The live inline path does **not** use the standalone Viewer launcher. `LaunchItemViewer.ps1` retains legacy `inline_` compatibility only.

`VIEWER >` remains a separate detached WinForms market browser.

## Immutable UI publication — IMPLEMENTED, PENDING STEADY-STATE TARGET ACCEPTANCE

The 2026-08-26 stale-publication incident established that fresh provider/engine data was reaching the machine while Rainmeter-facing publication could stall on Windows file-sharing contention.

Current state roles are:

```text
@Resources/Generated/state.kv                    = private mutable build state
@Resources/Generated/ui-state-<epoch>-<id>.kv    = immutable complete UI generation
@Resources/Generated/last-update.txt              = epoch|generation manifest
@Resources/Generated/ui-state.kv                  = legacy startup fallback
```

`RunUpdate.ps1` publishes one complete immutable generation only after `FilterState`, then atomically advances the small manifest. `PublishedState.lua` caches the selected complete generation so a failed or in-flight update cannot expose partial build state.

`LaunchUpdate.ps1` is spawn-only and starts the long-running worker under `pwsh.exe`; the named updater mutex serializes workers and tolerates an abandoned predecessor.

## Popup / Settings finalization — CODE COMPLETE, TARGET INTERACTION ACCEPTANCE PENDING

The target-host Item filter popup was observed opening during the 2026-08-26 Codex pass before that run exhausted its token budget.

Follow-up repository finalization hardened the remaining paths:

- Item/Country/Category/Ignore, Opportunity Settings, Profile/API and Viewer launchers use hidden detached process contracts;
- launchers `return` after spawning rather than `exit`, making nested popup calls safe;
- `Ignore List...` and `Profile / API...` can be launched from Opportunity Settings without the launcher intentionally terminating the parent host;
- Opportunity Settings and Profile/API saves route through `LaunchUpdate.ps1` rather than launching `RunUpdate.ps1` directly under Windows PowerShell 5.1;
- launcher/runtime failures are written to the bounded runtime log;
- static acceptance rejects regression to nested-launcher `exit 0`, direct WinPS updater bypasses, or Country-popup use of the candidate-only trip-band field.

Still requiring target-host interaction acceptance: Opportunity Settings, Category, Country, Ignore List, Profile/API and standalone Viewer open/save behavior.

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
immutable UI generation + last-update manifest
CycleAnalytics
TrendForecast
ResalePriority
ResaleQueue
```

`OptimalRoute.ps1` remains background compatibility/diagnostics/MV-priority logic; it does not define the user-facing opportunity surface.

## Validation status

Focused acceptance covers, among other contracts:

- updater PS7/spawn-only runtime and named mutex;
- immutable UI publication architecture;
- four transparent sort modes and immediate local sorting;
- schema-7 trip-band persistence and display filtering;
- fresh in-stock `LEARNING` likelihood behavior;
- card presentation and Safe/Best tooltip semantics;
- dedicated inline graph transport and exclusive expansion;
- retained-history truthfulness;
- Energy/Nerve constraints;
- Windows PowerShell 5.1 helper compatibility;
- reusable hidden popup launchers and bounded runtime diagnostics.

This environment did not provide PowerShell/Rainmeter, so the post-finalization focused suite was **not** executed here. Do not mark 0.6 accepted until `tests/Run-CurrentAcceptance.ps1`, one synchronous `pwsh.exe` production update, and the full visual/popup checklist in `docs/NEXT_CODEX_RUN.md` pass on the target Windows host.

## After 0.6 acceptance

1. tune final card/flag/graph proportions from the real Rainmeter render;
2. continue probability calibration as retained cycles accumulate;
3. add optional browser notifications consuming accepted local timing state;
4. evaluate bounded multi-trip sequence scheduling separately.
