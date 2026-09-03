# Travel Assistant Architecture

## Purpose

Travel Assistant is a lightweight Rainmeter-facing Torn foreign-market decision system. Collection, market validity, valuation, opportunity eligibility, ordering, and presentation remain separate concerns.

```text
COLLECTED provider rows
        !=
ACTIVE market relationships
        !=
ELIGIBLE opportunity candidates
        !=
VISIBLE opportunities
```

The current 0.6 product is a compact opportunity browser with selectable `UPCOMING`, `PROFIT`, and `PROFIT/HR` ordering; alphabetical Name order is fallback-only when timing/profit inputs are unavailable.

## Runtime layering

```text
Prometheus / YATA foreign stock
        ↓
ShadowCollector (single live-stock owner)
        ↓
observedMarkets + transition-only observations/cycles
        ↓
ProjectCollectedState (local compatibility projection)
        ↓
local catalog + engine schema
        ↓
FinalizeState
        ↓
TravelContext
        ↓
CycleForecastFilter (cadence-aware forecast eligibility; history retained)
        ↓
OpportunityState (dot-sources shared local helpers from OptimalRoute.ps1)
        ↓
WindowPlan / price refinement / FilterState
        ↓
private build state.kv
        ↓ exactly one final publication
finalized ui-state.kv
        ↓
visible heartbeat
        ↓
CycleAnalytics / TrendForecast
        ↓
ResalePriority / ResaleQueue
        ↓
StochasticForecast (shadow only; lowest-priority local stage)
```

Completed cycle rows remain retained for audit and long-horizon analysis. Route, window, and shadow-trend forecasts apply a market-specific cadence filter: markets normally completing at least eight cycles per day reject apparent cycles over 24 hours, other multi-cycle/day markets reject periods over 48 hours, and once-daily or slower markets retain a wider cadence-relative window. Transition boundaries also carry lower/upper observation bounds. The safe gap for each phase is the larger of three poll intervals or half its robust historical variance; the hard gap is bounded by the normal phase/cycle duration. Short gaps produce conservative availability/restock values, uncertain gaps are excluded from trend fitting, and hard gaps invalidate the current phase anchor instead of fabricating a cycle. The shadow trend pass is keyed to the completed-cycle file signature and skips its all-market recalculation/state rewrite when no cycle evidence changed. Fresh positive stock uses its observed restock quantity and live depletion rate for the active sellout estimate; restock timing begins only after observed stock reaches zero and uses the cleaned median out-of-stock delay.

`OptimalRoute.ps1` no longer has a standalone projection/main path; it is a shared local helper library for opportunity evidence, forecasting, waste-policy, resale, and capacity calculations. Inline graph rendering is a local side path. It makes no provider/Torn request.

## Market identity / validity

Identity is:

```text
country + itemId
```

Verified overrides in `config/foreign-market-overrides.json` supersede provider presence for new history/resale/opportunity work while preserving provenance.

Observed stock truth is limited to actual provider samples:

```text
0 -> positive = observed restock
positive -> 0 = observed sellout
```

Predictions never become history.

## Collection ownership

`ShadowCollector.ps1` is the normal heartbeat's sole live foreign-stock request path. It observes all 11 configured countries and all active provider market rows.

For every active market it updates current `engine-state.json` market metadata, including stock, foreign price, provider, and source timestamp. The retained observation database is stock-transition evidence: a new row is written when stock changes, not merely because provider timestamp or foreign price changed.

Transition JSONL appends use shared-access handles with bounded backoff. If a OneDrive/Rainmeter reader still holds the canonical history file, the collector writes the transition to a local pending journal, continues updating every market, and retries the merge on later heartbeats. Anchor reconciliation reads both canonical and pending observations, so a temporary file lock cannot roll current phase state backward.

`UpdateTracker.ps1` is retained only for explicit legacy compatibility actions such as `CycleTravelMode`; it is not called during a normal `Action=Update` heartbeat.

`ProjectCollectedState.ps1` projects legacy build-state stock/travel fields locally from the ShadowCollector engine state, avoiding a second provider request and a second history writer.

Filters, Ignore List, sort order, and graph expansion never narrow shared provider collection.

## State publication ownership

Generated state has two explicit roles:

```text
@Resources/Generated/state.kv     build/intermediate state
@Resources/Generated/ui-state-<epoch>-<id>.kv  immutable finalized Rainmeter state
@Resources/Generated/last-update.txt           generation manifest
```

Intermediate PowerShell stages mutate only the build artifact during the normal update chain. Each production Lua measure resolves the complete immutable generation named by `last-update.txt` directly; `ui-state.kv` remains a transition fallback for older numeric heartbeats. Keeping resolution inside each measure avoids a secondary `dofile` dependency during Rainmeter initialization.

After `FilterState.ps1` completes, `RunUpdate.ps1` validates the build projection, writes a new immutable snapshot, then atomically advances the small manifest. A failed write or manifest switch leaves readers on the previous complete generation.

`RefreshFilters` is the explicit filter-save path. It does not perform another foreign-stock collection. The first OpportunityState pass identifies currently eligible items whose resale MV is missing/stale; the resale queue is then restricted to those item IDs for a bounded save-time pricing pass (maximum 40), after which OpportunityState/WindowPlan/price refinement run again before FilterState and final publication. Normal minute polling retains the one-request broad resale queue after heartbeat publication.

This avoids replacing the large file that six one-second Rainmeter readers have open. The shared atomic writer retains bounded retry/backoff for the small manifest; old disposable generations are pruned only after a grace period.

## Retention and historical truth

Retention remains:

```text
high-resolution observations: ~48h
completed cycles:             ~90d
stale live-provider guard:     5m
visible graph window:          8h
```

At the 48-hour boundary, `MaintainObservationHistory.ps1` may carry the final **actual observation** before the cutoff to the cutoff as `retention_baseline`. This is a safe state carry because it is derived from observed evidence.

Migration-era rows named `history_bootstrap` and `history_repair_baseline` are removed. They previously projected current market state backward through periods with no retained evidence and could create false flat stock histories. Missing historical intervals now remain unknown.

## Graph surface

The per-row chart button uses dedicated local `MeasureInlineGraph` and `RenderInlineGraph.ps1` plumbing.

The renderer:

- reads `data/runtime/observations.jsonl` first;
- uses committed seed evidence only when the market has no runtime evidence;
- ignores migration-era synthetic rows defensively;
- compresses consecutive identical stock levels;
- carries a state to the left edge only when a real predecessor observation exists;
- appends the current `observedMarkets` stock snapshot at the right edge;
- renders a generated PNG consumed by a native Rainmeter Image meter;
- draws seven internal vertical separators for eight one-hour segments;
- shows sparse numeric Y labels plus `-8h` / `now` X labels.

Graph-hover tooltip telemetry has been retired. The generated graph is display-only; window evidence remains on the card's window/guidance tooltip.

If the first real retained sample occurs inside the 8-hour window, the earlier portion is deliberately left without a fabricated stock line.

Changing sort order collapses the open inline graph. At most one graph is expanded.

The standalone WinForms Viewer, its launcher, and its Rainmeter measure are retired.

## Card presentation

Each compact row is:

```text
[FlagKit flag]  Item                         selected Profit / PROFIT/HR   [$]
                window / leave guidance                              [chart]
```

- No rank/place number.
- No country name/code in the card body.
- The left first-line content is item name only; foreign unit cost and exact full-load purchase cost move to the expanded economics strip. No variable-price reserve is applied.
- Signed total net profit is larger, right-aligned, and vertically centered over the two card text lines.
- Card fill is pure black to match the inline graph background; the existing gray card border, internal half divider, and right end-cap separators remain unchanged.
- Destination uses bundled FlagKit `@3x` PNG assets under the upstream MIT license. The flag/mask surface is `67x50` starting at the card origin so color extends beneath the border instead of leaving 1px bands. Three tiny alpha-mask assets (`both`, `top`, `bottom`) tint to `#Panel#` and clip the flag's left corners according to expansion state; a border-only `CardBorder` meter redraws the rounded card outline over the flag.
- The item-art cell spans exactly 48px from the flag edge to the text origin, matching the 48px card interior height. A transparent `44x44` item image sits inside with a 2px inset. `EnsureItemImages.ps1` caches Torn's direct `images/items/<id>/large.png` asset in `@Resources/Generated/Items`; missing/failed decorative art never blocks card rendering.
- Hovering the flag exposes country + configured one-way travel time.
- The `# Travel Assistant Architecture

## Purpose

Travel Assistant is a lightweight Rainmeter-facing Torn foreign-market decision system. Collection, market validity, valuation, opportunity eligibility, ordering, and presentation remain separate concerns.

```text
COLLECTED provider rows
        !=
ACTIVE market relationships
        !=
ELIGIBLE opportunity candidates
        !=
VISIBLE opportunities
```

The current 0.6 product is a compact opportunity browser with selectable `UPCOMING`, `PROFIT`, and `PROFIT/HR` ordering; alphabetical Name order is fallback-only when timing/profit inputs are unavailable.

## Runtime layering

```text
Prometheus / YATA foreign stock
        ↓
ShadowCollector (single live-stock owner)
        ↓
observedMarkets + transition-only observations/cycles
        ↓
ProjectCollectedState (local compatibility projection)
        ↓
local catalog + engine schema
        ↓
FinalizeState
        ↓
TravelContext
        ↓
CycleForecastFilter (cadence-aware forecast eligibility; history retained)
        ↓
OpportunityState (dot-sources shared local helpers from OptimalRoute.ps1)
        ↓
WindowPlan / price refinement / FilterState
        ↓
private build state.kv
        ↓ exactly one final publication
finalized ui-state.kv
        ↓
visible heartbeat
        ↓
ResalePriority / ResaleQueue
```

Completed cycle rows remain retained for audit and long-horizon analysis. Route, window, and shadow-trend forecasts apply a market-specific cadence filter: markets normally completing at least eight cycles per day reject apparent cycles over 24 hours, other multi-cycle/day markets reject periods over 48 hours, and once-daily or slower markets retain a wider cadence-relative window. Transition boundaries also carry lower/upper observation bounds. The safe gap for each phase is the larger of three poll intervals or half its robust historical variance; the hard gap is bounded by the normal phase/cycle duration. Short gaps produce conservative availability/restock values, uncertain gaps are excluded from trend fitting, and hard gaps invalidate the current phase anchor instead of fabricating a cycle. The shadow trend pass is keyed to the completed-cycle file signature and skips its all-market recalculation/state rewrite when no cycle evidence changed. Fresh positive stock uses its observed restock quantity and live depletion rate for the active sellout estimate; restock timing begins only after observed stock reaches zero and uses the cleaned median out-of-stock delay.

`OptimalRoute.ps1` no longer has a standalone projection/main path; it is a shared local helper library for opportunity evidence, forecasting, waste-policy, resale, and capacity calculations. Inline graph rendering is a local side path. It makes no provider/Torn request.

## Market identity / validity

Identity is:

```text
country + itemId
```

Verified overrides in `config/foreign-market-overrides.json` supersede provider presence for new history/resale/opportunity work while preserving provenance.

Observed stock truth is limited to actual provider samples:

```text
0 -> positive = observed restock
positive -> 0 = observed sellout
```

Predictions never become history.

## Collection ownership

`ShadowCollector.ps1` is the normal heartbeat's sole live foreign-stock request path. It observes all 11 configured countries and all active provider market rows.

For every active market it updates current `engine-state.json` market metadata, including stock, foreign price, provider, and source timestamp. The retained observation database is stock-transition evidence: a new row is written when stock changes, not merely because provider timestamp or foreign price changed.

Transition JSONL appends use shared-access handles with bounded backoff. If a OneDrive/Rainmeter reader still holds the canonical history file, the collector writes the transition to a local pending journal, continues updating every market, and retries the merge on later heartbeats. Anchor reconciliation reads both canonical and pending observations, so a temporary file lock cannot roll current phase state backward.

`UpdateTracker.ps1` is retained only for explicit legacy compatibility actions such as `CycleTravelMode`; it is not called during a normal `Action=Update` heartbeat.

`ProjectCollectedState.ps1` projects legacy build-state stock/travel fields locally from the ShadowCollector engine state, avoiding a second provider request and a second history writer.

Filters, Ignore List, sort order, and graph expansion never narrow shared provider collection.

## State publication ownership

Generated state has two explicit roles:

```text
@Resources/Generated/state.kv     build/intermediate state
@Resources/Generated/ui-state-<epoch>-<id>.kv  immutable finalized Rainmeter state
@Resources/Generated/last-update.txt           generation manifest
```

Intermediate PowerShell stages mutate only the build artifact during the normal update chain. Each production Lua measure resolves the complete immutable generation named by `last-update.txt` directly; `ui-state.kv` remains a transition fallback for older numeric heartbeats. Keeping resolution inside each measure avoids a secondary `dofile` dependency during Rainmeter initialization.

After `FilterState.ps1` completes, `RunUpdate.ps1` validates the build projection, writes a new immutable snapshot, then atomically advances the small manifest. A failed write or manifest switch leaves readers on the previous complete generation.

`RefreshFilters` is the explicit filter-save path. It does not perform another foreign-stock collection. The first OpportunityState pass identifies currently eligible items whose resale MV is missing/stale; the resale queue is then restricted to those item IDs for a bounded save-time pricing pass (maximum 40), after which OpportunityState/WindowPlan/price refinement run again before FilterState and final publication. Normal minute polling retains the one-request broad resale queue after heartbeat publication.

This avoids replacing the large file that six one-second Rainmeter readers have open. The shared atomic writer retains bounded retry/backoff for the small manifest; old disposable generations are pruned only after a grace period.

## Retention and historical truth

Retention remains:

```text
high-resolution observations: ~48h
completed cycles:             ~90d
stale live-provider guard:     5m
visible graph window:          8h
```

At the 48-hour boundary, `MaintainObservationHistory.ps1` may carry the final **actual observation** before the cutoff to the cutoff as `retention_baseline`. This is a safe state carry because it is derived from observed evidence.

Migration-era rows named `history_bootstrap` and `history_repair_baseline` are removed. They previously projected current market state backward through periods with no retained evidence and could create false flat stock histories. Missing historical intervals now remain unknown.

## Graph surface

The per-row chart button uses dedicated local `MeasureInlineGraph` and `RenderInlineGraph.ps1` plumbing.

The renderer:

- reads `data/runtime/observations.jsonl` first;
- uses committed seed evidence only when the market has no runtime evidence;
- ignores migration-era synthetic rows defensively;
- compresses consecutive identical stock levels;
- carries a state to the left edge only when a real predecessor observation exists;
- appends the current `observedMarkets` stock snapshot at the right edge;
- renders a generated PNG consumed by a native Rainmeter Image meter;
- draws seven internal vertical separators for eight one-hour segments;
- shows sparse numeric Y labels plus `-8h` / `now` X labels.

Graph-hover tooltip telemetry has been retired. The generated graph is display-only; window evidence remains on the card's window/guidance tooltip.

If the first real retained sample occurs inside the 8-hour window, the earlier portion is deliberately left without a fabricated stock line.

Changing sort order collapses the open inline graph. At most one graph is expanded.

The standalone WinForms Viewer, its launcher, and its Rainmeter measure are retired.

## Card presentation

Each compact row is:

```text
[FlagKit flag]  Item                         selected Profit / PROFIT/HR   [$]
                window / leave guidance                              [chart]
```

- No rank/place number.
- No country name/code in the card body.
- The left first-line content is item name only; foreign unit cost and exact full-load purchase cost move to the expanded economics strip. No variable-price reserve is applied.
- Signed total net profit is larger, right-aligned, and vertically centered over the two card text lines.
- Card fill is pure black to match the inline graph background; the existing gray card border, internal half divider, and right end-cap separators remain unchanged.
- Destination uses bundled FlagKit `@3x` PNG assets under the upstream MIT license. The flag/mask surface is `67x50` starting at the card origin so color extends beneath the border instead of leaving 1px bands. Three tiny alpha-mask assets (`both`, `top`, `bottom`) tint to `#Panel#` and clip the flag's left corners according to expansion state; a border-only `CardBorder` meter redraws the rounded card outline over the flag.
- The item-art cell spans exactly 48px from the flag edge to the text origin, matching the 48px card interior height. A transparent `44x44` item image sits inside with a 2px inset. `EnsureItemImages.ps1` caches Torn's direct `images/items/<id>/large.png` asset in `@Resources/Generated/Items`; missing/failed decorative art never blocks card rendering.
- Hovering the flag exposes country + configured one-way travel time.
 button expands a fixed 34px, two-row economics bar. Each half begins with a 40px `#Border#`-filled vertical label block (`Each` / `Total`). MV is top-left. Top-right displays whichever profitability metric is not primary: round-trip flight `$/hr` for `UPCOMING` / `PROFIT`, or signed Net for `PROFIT/HR`. Bottom-left displays foreign unit Price / exact total purchase Price, while Tax is right-aligned in the bottom-right cell when nonzero. The flight rate uses after-tax Each/Total net divided by `2 x` configured one-way flight seconds and intentionally excludes waiting/window time.
- `$` and chart are centered in the two halves of one T-divided right-edge end cap; active cells use Torn-lime fill and dark-gray icons. Active sort text plus the top filter/settings icons use the same Torn-lime UI accent. Their fills are inset one pixel so the card border and separators remain unobscured.
- Clicking the card body toggles both economics and inline graph expansion for that stable row key; the two end-cap controls continue to toggle their sections independently.
- Window/leave guidance is positioned low in the card body to minimize padding above the bottom border.
- The chart button expands the local 8-hour graph. Graph PNGs are black with a Torn-lime stock trace; cobalt-blue restock/in-stock and pumpkin-orange sellout/out-of-stock events are short ticks below the X axis.
- Tooltip ownership is limited to the Flag meter and the visible Leave/window meter. The former `Info`, graph-hover, and final WindowTooltipTweaks tooltip surfaces are retired. CardPresenter owns the home window tooltip and TravelStateWindowTweaks owns it while traveling/returning/abroad.
- A known 0% arrival case displays `NO HIT` rather than `LEAVE NOW`; unknown likelihood displays `WAIT DATA`.

`OpportunityRows.inc` is included after the full-panel background so cards render above, not beneath, the panel layer.

Sorting keeps the legacy internal mode key `gross` for preference compatibility, but the visible button is `PROFIT` and ranks by the same after-tax total Net displayed on the card. Comparison is signed descending, never absolute-value magnitude.

## Provider and heartbeat freshness

`FilterState.ps1` records both the oldest and freshest active market source timestamps in the build state. The legacy header timestamp key is fed from the **freshest** active sample so one lagging country does not label the entire provider feed stale. The actual oldest timestamp is retained separately for diagnostics.

The visible heartbeat is written after finalized `ui-state.kv` publication and before broad MV queue work. A slow MV refresh therefore does not make otherwise-current foreign-stock state appear unrefreshed, and a failed UI publication cannot falsely advance the heartbeat.

## Local catalog and MV

Catalog network maintenance stays outside the one-second Rainmeter loop. `LocalCatalog.ps1` resolves metadata from committed/local sources.

`ResaleQueue.ps1` is the sole broad Torn Item Market request path. The opportunity layer consumes cached `itemmarket.item.average_price` as MV.

A successful item-market response with neither listings nor a positive average remains unresolved. It retains the normal one-hour retry backoff even when optimizer-prioritized, so one legitimately empty market cannot monopolize the single-request queue.

Card typography is 12 pt for the combined item/cost line, 16 pt for total Net, and 9 pt for window/guidance text.

Value/tax basis:

```text
sale price = declared/list Torn MV
selected tax / trader rate = 0%..5%
tax is applied once to gross sale proceeds
- Settings-triggered preference saves queue `LaunchUpdate.ps1` with a 120-second mutex wait, so a concurrent updater cannot cause the new tax rate to miss the next published projection
0 minimum profit gate
0 minimum margin gate
```

## Capacity / economics

General capacity derives from travel-mode base plus synced profile effects. Opportunity quantity is bounded by both configured capacity and modeled/current available quantity.

```text
gross sale = quantity × declared MV
gross profit = gross sale - purchase cost
tax = floor(gross sale × selected rate)
net profit = gross profit - tax
profit/hr = net profit / round-trip flight hours
```

Gross profit intentionally excludes travel cost; tax is a separate deduction into net profit. Hit probability is displayed separately and is not multiplied into `PROFIT/HR`.

## Travel + bars

`TravelContext.ps1` performs one bounded fail-soft user request for travel/basic/bars. Transient failures preserve the last successful destination/bar context. While outbound/abroad to a recognized destination, opportunity selection is restricted to that destination. `traveling_unknown` / `abroad_unknown` fails closed.

Energy/Nerve waste policies remain local decision constraints and never mutate observation history.

## Projection / interaction

`StateReader.lua` performs immediate local sorting so button response does not wait for PowerShell persistence. It reads only the last finalized `ui-state.kv`, so intermediate PowerShell mutations are never visible to the main Rainmeter surface. Genuine zero-result projections still replace the list when that completed generation is published.

Steady-state one-second Rainmeter work remains local-only. A newly visible uncached item may enqueue a bounded static PNG cache fill from `www.torn.com/images/items/...`; this decorative CDN fetch is separate from provider/Torn API ownership. Normal foreign-stock collection remains approximately once per minute; inline rendering is local/on-demand; API credentials remain ignored/local.

## Authoritative legacy window pipeline

`WindowPlan.ps1` is the one production entrypoint for visible legacy timing.
`RunUpdate.ps1` never invokes `WindowPlanRefiner.ps1` independently. The entrypoint
currently delegates to that richer implementation module while its helpers are
consolidated, so the former simpler producer is no longer executed.

The pre-consolidation audit found that the refiner was **partially relied upon**,
not dead: `RunUpdate` called the simpler WindowPlan, then `FilterState` indirectly
called `WindowPlanRefiner`. The simpler pass handled only OOS recurring WP2
geometry and skipped live stock; the refiner additionally produced `CurrentStock`,
`StockEvidenceAt`, `ActiveRestockAt`, `ActiveSelloutEstimateAt`,
`NextRestockEstimateAt`, `MedianRestockDelaySeconds`,
`LiveCycleProjectionMode`, `WindowDataQuality/Reason`, current-cycle reachability
and deadline/safety fields, `NextCycleOrdinal`, `WindowMedianPeriodSeconds`, and
price-bound metadata. Those fields were not in OpportunityState's row-clear list,
and several refiner fast paths did not initialize them, so stale values could
survive when row identities moved between generations. FilterState no longer runs
forecast code; WindowPlan runs the richer implementation exactly once before price
refinement and filtering.

Visible timing ownership is explicit:

| Field family | Current owner |
|---|---|
| candidate identity and initial timing/probability values | `OpportunityState.ps1` |
| final Safe/Best/current-cycle timing, live anchors, quality fields, WP2 timing envelope | `WindowPlan.ps1` (implementation in `WindowPlanRefiner.ps1`) |
| price-variation fields and final PV tooltip envelope | `PriceVariationRefiner.ps1` |
| traveling/returning/abroad wording and window tooltip | `TravelStateWindowTweaks.lua` |
| home timing text and home window tooltip | `CardPresenter.lua` |
| row projection, sorting, and meter assignment | `StateReader.lua` |

`OpportunityState` clears every generation-scoped WindowPlan field before writing
new rows. WindowPlan initializes every owned field before any fast path and stamps
`LegacyWindowPlanAuthority=WindowPlan` plus the generation time. A refiner-era
value produced for an older row therefore cannot survive at the same row index.

## Censor-aware evidence

Polling timestamps are observation times, not exact event times. New observation
rows use schema 2. A `0 -> positive` transition stores the previous fresh timestamp
as the restock lower bound and the positive observation timestamp as the upper
bound; `positive -> 0` stores the analogous sellout bracket. Provider/source time
is authoritative when present, with local collection time only as fallback.

Completed schema-2 cycles retain restock, sellout, and previous-sellout bounds plus
conservative duration bounds. `evidenceQuality` uses a compact classification:
`bounded_fresh`, `bounded_gap`, `left_censored`, `right_censored`, or `incomplete`.
Active cycles remain durable in `engine-state.json` with
`isRightCensored=true`. Incomplete rows remain retained for audit but cannot teach
the forecast when a required boundary is unsafe. Bounds remain stored even when
their quality is too weak for forecasting.

Stock declines ending above zero record `depletionEvidence=observed_nonzero` and
the observed quantity delta. A transition ending at zero records
`depletionEvidence=sellout_censored`, `depletionCensored=true`, and only a demand
lower bound equal to the last observed positive stock. Missing provider rows do not
create observations or out-of-stock transitions.

## Stochastic-v1.1 shadow forecast

After immutable legacy UI publication, `StochasticForecast.ps1` reads retained
schema-2 cycles by stable `country:itemId`. It applies a 14-day exponential
recency half-life and evidence-quality weight, then resamples each cycle jointly so
restock delay, availability, restock quantity, foreign price, and censor bounds
keep their observed relationship. Event and duration values are sampled inside the
stored bounds.

Each of 128 deterministic seeded **scoring** scenarios is represented as stock
intervals, not second-by-second rows. Simulation continues through as many future
cycles as needed to pass the latest evaluated arrival. The default search starts
with a 15-minute base grid over 12 hours. If lower-quartile empirical availability
is shorter than that base step, an independently seeded 16-32 scenario discovery
pass identifies coarse cells containing simulated stock support that could be
missed between endpoints. At most four cells are refined with a bounded additional
candidate budget; uniform sub-grid points are supplemented by a few discovery
restock quantiles so very short bursts are not structurally invisible. The full
configured scoring scenarios are then regenerated independently and score the final
candidate set. This separation limits Monte Carlo optimizer bias from using the
same worlds both to discover and validate a peak.

Current stock is anchored to the provider observation timestamp.
Only an observation describing the exact forecast origin is treated as certain
current stock. Older-but-fresh positive evidence is propagated forward through the
learned survival distribution, so it may sell out before `Now`; later cycles remain
eligible when the observed cycle cannot survive to an evaluated arrival.

For completed future-cycle evidence, retained intermediate stock changes are mapped
onto normalized cycle progress and converted to a monotone piecewise empirical
depletion shape. The shape remains attached to the same joint cycle row as delay,
availability, restock quantity, and foreign price. A shape is rejected when the
combined restock/sellout censor width exceeds 50% of the observed cycle span; that
cycle can still teach timing but quantity uses the linear fallback. This avoids
turning coarse poll brackets into false within-cycle precision. `expectedQty`
remains capped at the projected player load; `expectedAvailableQty` is uncapped
market quantity for validation and diagnostics.

Travel feasibility is a separate transform: home departures add outbound time;
returning departures start no earlier than landing in Torn; outbound-to-target uses
the committed landing; abroad-at-target evaluates now; unknown or other-destination
travel fails closed.

The ignored, atomically replaced `data/runtime/stochastic-forecast.json` artifact
uses schema 1/model `stochastic-v1.1`. Per market it contains arrival points with
`pAnyStock`, `pTargetQty`, expected quantity, expected after-tax profit, and expected
after-tax profit/hour; evidence/sample diagnostics; best/last departure summaries;
and one mutually exclusive shadow decision. V1.1 defines target quantity as the
already projected trip quantity and utility as expected profit. The configured
`itemMarketFeePercent` and existing round-trip flight hours remain authoritative.

The full departure-search/decision surface remains a shadow diagnostic. A restricted production bridge reuses the same simulator at exactly one earliest-feasible arrival for long-flight/short-cycle fallback display; that selective `pAnyStock` use does not promote the stochastic decision object. Limitations include
sparse empirical depletion-shape coverage with a linear fallback, a bounded
adaptive search that can still omit low-support cells, no value-of-information
solver, no online change-point model, and no risk-preference surface. The offline replay currently
compares stochastic-v1.1 with simple mean/median and empirical overlap proxies;
`empirical_all_overlap` / `empirical_overlap` are not an exact historical replay
of production WindowPlan Safe/Best decisions. Promotion requires frozen live
scoring, calibration, one accepted authoritative stochastic decision object, and
only then a separate visible UI migration.

### Production multi-cycle chance bridge

`MultiCycleChanceBridge.ps1` executes after authoritative legacy `WindowPlan` and before price/filter/UI publication. It is local-only and fail-soft. Rather than running the full 12-hour candidate search, it constructs one physically feasible earliest arrival: leave now from Torn, leave immediately after a return completes, or evaluate an already committed landing. Other-destination travel fails closed and already-abroad state does not need this fallback.

Using the same `Select-SFJointCycleEvidence` and `Invoke-SFMarketForecast` functions as stochastic-v1.1, it evaluates 256 seeded scenarios with adaptive-grid search disabled. The bridge is eligible only with at least three usable completed cycles and an arrival-horizon / weighted-mean-full-cycle ratio of at least 2.0.

The bridge also computes interpretable timing diagnostics from the weighted evidence:

- weighted mean full-cycle duration = OOS duration + in-stock duration;
- weighted mean in-stock duration;
- long-run occupancy baseline = `E[in-stock] / E[full cycle]`;
- weighted full-cycle timing standard deviation;
- expected complete cycles crossed = `floor(arrival horizon / mean cycle)`;
- an independence-reference phase standard deviation = `sqrt(N) * cycle timing SD`.

The occupancy and phase-dispersion values are diagnostics/baselines only. The displayed probability is the simulator's `pAnyStock`, not a Gaussian approximation and not the occupancy ratio. `CardPresenter.lua` consumes the bridge only when legacy current-stock/Safe/Best guidance cannot produce an actionable state; actionable legacy guidance always retains precedence. The visible text is `Chance to hit: NN%` and the tooltip explicitly says the result is a modeled arrival probability, not a Safe/Best guarantee.

Time-of-day conditioning and current-price-conditioned weighting are intentionally not part of this first production bridge. Historical foreign price remains joint with each resampled cycle, preserving observed price/duration association without asserting a causal or current-price effect. Those conditioning variables require walk-forward/prospective evidence before promotion.

### Current-stock slow-depletion safety fallback

The authoritative legacy window refiner has one deliberately narrow escape hatch for long-lived current stock whose restock boundary was missed. It uses only the current uninterrupted positive-stock run from retained observations. Sellout-censored intervals, zero states, positive jumps/restocks, and long source gaps reset or exclude depletion evidence.

Eligibility requires fresh positive stock, a future physically feasible arrival, at least three uncensored `observed_nonzero` depletion samples spanning at least 600 seconds, and a conservative runway gate. The observed rate is the 90th percentile of current-run depletion, multiplied by 1.5 and floored at 60 units/hour. The resulting runway must be at least `max(2 * arrival_horizon, arrival_horizon + 1800s)`. When true, the state becomes `current_stock_safe` and the card says `Safe Window Open`. No probability is emitted (`ProbabilityValue=-1`), no completed cycle is created, and recurring Safe/Best evidence is unchanged.

### Flight-aligned chance history and retrospective truth

After visible UI/heartbeat publication, `ChanceHistory.ps1` journals the finalized modeled hit probability for each projected market at most once per minute. Legacy WindowPlan exposes a separate `ImmediateArrivalProbabilityValue` at the physically earliest arrival for this purpose; the journal never reuses `ProbabilityValue` when that field describes a recommended future Safe/Best window. Arrivals beyond legacy current/+1-cycle support remain unknown so they can be handled by the multi-cycle model rather than being mislabeled 0%. The ignored `chance-history.jsonl` retains eight hours and stores `forecastAt`, physically feasible `departureAt` / `arrivalAt`, configured one-way flight seconds, travel mode, model/source, target quantity, and the probability. Long-flight markets prefer the eligible multi-cycle `pAnyStock`; otherwise the legacy arrival probability is recorded when it represents a genuinely future travel arrival.

`ResolveChanceHistory.ps1` runs afterward and never modifies the frozen forecast. Once an arrival has passed, it reuses `StochasticCalibration.ps1` confirmed-outcome semantics to label any-stock truth only from unambiguous later evidence. Resolved rows are retained for the same eight-hour departure window in `resolved-arrival-history.jsonl`; `chance-accuracy.json` reports Brier, root-Brier, log loss, mean absolute outcome error, classification accuracy at 0.5, mean predicted probability, observed hit rate, and calibration gap overall/per market/per source. This is strict prospective replay: future evidence labels the outcome only.

### Hindsight departure-window visualization and local hit testing

The renderer keeps the prospective and retrospective layers semantically separate. `chance-history.jsonl` drives the cyan line directly on an implicit 0..100% scale. No 0.50 display threshold is applied; every recorded probability is rendered, and gaps greater than the existing evidence-continuity allowance remain gaps.

Periwinkle is reserved for hindsight truth. The renderer shifts actual retained stock transitions backward by the currently configured one-way country flight duration, producing departure-time coordinates. Contiguous shifted intervals whose later observed state was positive stock become `realizedWindows`. Each window is filled across the plot height with a low-alpha periwinkle brush and exact opening/closing boundaries. Because truth is only known after the corresponding arrival, the latest possible hindsight endpoint is `now - flightSeconds`; periwinkle never represents a live recommendation.

`ResolveChanceHistory.ps1` supplies a separate validation layer. When enabled, the graph may draw a faint error whisker from the frozen historical probability to the later binary HIT/MISS outcome and a small endpoint. Its hover text reports forecast percentage, actual outcome, and Brier contribution. This is the analog/quality information retained for model evaluation rather than inventing a second “true probability” curve from one realized event.

`RenderInlineGraph.ps1` publishes up to 48 semantic hover regions into the generated graph KV. Hindsight-window and resolved-forecast regions take priority; remaining slots are assigned to the most recent observed restock/OoS transition ticks. `StateReader.lua` maps these image-relative rectangles onto the single global `InlineGraphHitboxes.inc` meter pool. Tooltips are local display metadata only. The historical `GraphHover.lua` / `BuildGraphHoverData.ps1` subsystem remains retired.

Every overlay except actual stock quantity is independently configurable through `graphVisuals` in local settings: `showGrid`, `showTransitions`, `showChance`, `showHindsightWindows`, `showAccuracyMarkers`, and `showTooltips`. Stock quantity remains mandatory.

Projected early/late restock and sellout boundaries are not rendered in the current past-only graph. They would have value as an advanced forecast overlay, but current projected timestamps are often future times; collapsing them onto the `now` edge would be misleading. Add them only with a legitimate future-time graph domain or a separate forecast gutter.

### Prospective stochastic calibration

`StochasticCalibration.ps1` runs after `StochasticForecast.ps1` and remains
strictly shadow-only/fail-soft. It maintains two ignored atomic artifacts:

```text
data/runtime/stochastic-calibration-state.json
data/runtime/stochastic-calibration.json
```

The state freezes at most one selected best-expected-profit arrival for each
`modelVersion × marketKey × hour bucket`. The source stochastic artifact must be
no more than five minutes old and the selected arrival must be strictly after the
artifact generation timestamp. This excludes `BUY_NOW` / already-observable
zero-horizon states from prospective calibration.

After the frozen arrival passes, later retained evidence may resolve it. An exact
provider snapshot at the arrival can score stock, required quantity and uncapped
quantity. A completed cycle can score stock success only inside the confirmed
`restockUpperBoundAt <= arrival < soldOutLowerBoundAt` interval. Between-cycle
stock failure is accepted only when the later cycle durably preserves
`previousSoldOutUpperBoundAt` plus a forecast-usable
`previousSellOutBoundaryQuality` linking it to the earlier sellout; adjacency of
two retained cycle rows alone is never treated as proof of continuous OOS. Such a
continuity-proven OOS interval also determines target-quantity failure and exact
available quantity zero, so those two metrics do not require a coincident provider
snapshot for OOS outcomes.

Unresolved predictions remain pending for at most seven days and then become
`expired_unscorable`; they never enter calibration aggregates. Backpressure also
bounds state growth: by default no new row is frozen when that model/market already
has 24 unresolved predictions or when total pending reaches 4,096. Capacity
pressure never deletes, relabels, or prematurely expires an existing prediction.

Scored records increment model-wide, evidence-quality, market-specific, and
forecast-horizon Brier/log-loss/reliability aggregates. Horizon strata are
`<=30m`, `30m_to_2h`, `2h_to_6h`, and `gt_6h`; exact-snapshot quantity
MAE/RMSE is carried in the same aggregate scopes. Recent
scored/expired records are bounded for audit while aggregate statistics are
retained. Brier uses the raw probability; only log loss is epsilon-clipped. No
calibration mapping is applied back to forecast probabilities yet.
