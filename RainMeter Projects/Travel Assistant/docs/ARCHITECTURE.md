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

The current 0.6 product is a compact opportunity browser with selectable `UPCOMING`, `GROSS PROFIT`, and `PROFIT/HR` ordering; alphabetical Name order is fallback-only when timing/profit inputs are unavailable.

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

`GraphHover.lua` and `BuildGraphHoverData.ps1` add local hover telemetry over the same generated graph.

If the first real retained sample occurs inside the 8-hour window, the earlier portion is deliberately left without a fabricated stock line.

Changing sort order collapses the open inline graph. At most one graph is expanded.

The standalone WinForms Viewer, its launcher, and its Rainmeter measure are retired.

## Card presentation

Each compact row is:

```text
[FlagKit flag]  Item | foreign cost | full-load cost   signed total net   [$]
                window / leave guidance                              [chart]
```

- No rank/place number.
- No country name/code in the card body.
- The left first-line content is Item / foreign unit cost / exact full-load cost; no variable-price reserve is applied.
- Signed total net profit is larger, right-aligned, and vertically centered over the two card text lines.
- Destination uses bundled FlagKit `@3x` PNG assets under the upstream MIT license. Three tiny alpha-mask assets (`both`, `top`, `bottom`) tint to `#Panel#` and clip the flag's left corners according to expansion state; a border-only `CardBorder` meter redraws the rounded card outline over the flag. This makes the flag a true left-side end cap without leaking square pixels outside the radius.
- Each row also has a transparent `28x28` item-art meter immediately right of the flag. `EnsureItemImages.ps1` caches Torn's direct `images/items/<id>/large.png` asset in `@Resources/Generated/Items`; missing/failed decorative art never blocks card rendering.
- Hovering the flag exposes country + configured one-way travel time.
- The `$` button expands a two-half 9pt economics row: per-item MV/Tax/Net on the left and total MV/Tax/Net on the right; the redundant Each/Total prefixes are omitted.
- `$` and chart are centered in the two halves of one T-divided right-edge end cap; active cells use Torn-lime fill and dark-gray icons. Their fills are inset one pixel so the card border and separators remain unobscured.
- Window/leave guidance is positioned low in the card body to minimize padding above the bottom border.
- The chart button expands the local 8-hour graph. Graph PNGs are black with a Torn-lime stock trace, cobalt-blue restock/in-stock transition lines, and pumpkin-orange sellout/out-of-stock transition lines.
- A known 0% arrival case displays `NO HIT` rather than `LEAVE NOW`; unknown likelihood displays `WAIT DATA`.

`OpportunityRows.inc` is included after the full-panel background so cards render above, not beneath, the panel layer.

## Provider and heartbeat freshness

`FilterState.ps1` records both the oldest and freshest active market source timestamps in the build state. The legacy header timestamp key is fed from the **freshest** active sample so one lagging country does not label the entire provider feed stale. The actual oldest timestamp is retained separately for diagnostics.

The visible heartbeat is written after finalized `ui-state.kv` publication and before broad MV queue work. A slow MV refresh therefore does not make otherwise-current foreign-stock state appear unrefreshed, and a failed UI publication cannot falsely advance the heartbeat.

## Local catalog and MV

Catalog network maintenance stays outside the one-second Rainmeter loop. `LocalCatalog.ps1` resolves metadata from committed/local sources.

`ResaleQueue.ps1` is the sole broad Torn Item Market request path. The opportunity layer consumes cached `itemmarket.item.average_price` as MV.

A successful item-market response with neither listings nor a positive average remains unresolved. It retains the normal one-hour retry backoff even when optimizer-prioritized, so one legitimately empty market cannot monopolize the single-request queue.

Value/tax basis:

```text
sale price = declared/list Torn MV
selected tax / trader rate = 0%..5%
tax is applied once to gross sale proceeds
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
profit/hr = net profit / total elapsed hours
```

Gross profit intentionally excludes travel cost; tax is a separate deduction into net profit. Hit probability is displayed separately and is not multiplied into `PROFIT/HR`.

## Travel + bars

`TravelContext.ps1` performs one bounded fail-soft user request for travel/basic/bars. Transient failures preserve the last successful destination/bar context. While outbound/abroad to a recognized destination, opportunity selection is restricted to that destination. `traveling_unknown` / `abroad_unknown` fails closed.

Energy/Nerve waste policies remain local decision constraints and never mutate observation history.

## Projection / interaction

`StateReader.lua` performs immediate local sorting so button response does not wait for PowerShell persistence. It reads only the last finalized `ui-state.kv`, so intermediate PowerShell mutations are never visible to the main Rainmeter surface. Genuine zero-result projections still replace the list when that completed generation is published.

Steady-state one-second Rainmeter work remains local-only. A newly visible uncached item may enqueue a bounded static PNG cache fill from `www.torn.com/images/items/...`; this decorative CDN fetch is separate from provider/Torn API ownership. Normal foreign-stock collection remains approximately once per minute; inline rendering is local/on-demand; API credentials remain ignored/local.
