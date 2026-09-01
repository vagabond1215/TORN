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

The current 0.6 product is a compact opportunity browser with explicit `NAME`, `UPCOMING`, `GROSS PROFIT`, and `PROFIT/HR` ordering.

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
OptimalRoute compatibility model
        ↓
OpportunityState
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

Inline graph rendering and the standalone Viewer are local side paths. They make no provider/Torn request.

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

Filters, Ignore List, sort order, graph expansion, and Viewer selection never narrow shared provider collection.

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

## Graph surfaces

### Inline card graph

The row chevron uses a dedicated local `MeasureInlineGraph` and `RenderInlineGraph.ps1`. It never routes through the standalone Viewer launcher.

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

If the first real retained sample occurs inside the 8-hour window, the earlier portion is deliberately left without a fabricated stock line.

Changing sort order collapses the open inline graph. At most one row is expanded.

### Standalone Viewer

`VIEWER >` remains a detached WinForms market browser with its own market dropdown and richer diagnostics. It reads the same retained local observation file. History maintenance purges synthetic migration rows before it renders, so both graph surfaces converge on the same observed evidence.

## Card presentation

Each compact row is:

```text
[FlagKit flag]  Item name                         $gross   v
                window   leave   chance       foreign (MV)
```

- No rank/place number.
- No country name/code in the card body.
- No duplicate travel/elapsed-time text in the body.
- Destination uses bundled FlagKit `@3x` PNG assets under the upstream MIT license.
- Hovering the flag exposes country + configured one-way travel time.
- Gross is a bare dollar amount; projected quantity remains available to economics/tooltips.
- A known 0% arrival case displays `NO HIT` rather than `LEAVE NOW`; unknown likelihood displays `WAIT DATA`.

`OpportunityRows.inc` is included after the full-panel background so cards render above, not beneath, the panel layer.

## Provider and heartbeat freshness

`FilterState.ps1` records both the oldest and freshest active market source timestamps in the build state. The legacy header timestamp key is fed from the **freshest** active sample so one lagging country does not label the entire provider feed stale. The actual oldest timestamp is retained separately for diagnostics.

The visible heartbeat is written after finalized `ui-state.kv` publication and before broad MV queue work. A slow MV refresh therefore does not make otherwise-current foreign-stock state appear unrefreshed, and a failed UI publication cannot falsely advance the heartbeat.

## Local catalog and MV

Catalog network maintenance stays outside the one-second Rainmeter loop. `LocalCatalog.ps1` resolves metadata from committed/local sources.

`ResaleQueue.ps1` is the sole broad Torn Item Market request path. The opportunity layer consumes cached `itemmarket.item.average_price` as MV.

A successful item-market response with neither listings nor a positive average remains unresolved. It retains the normal one-hour retry backoff even when optimizer-prioritized, so one legitimately empty market cannot monopolize the single-request queue.

Default value basis:

```text
100% Torn MV
0 Item Market fee deduction
0 minimum profit gate
0 minimum margin gate
```

Optional preference changes the sell basis to 95% MV.

## Capacity / economics

General capacity derives from travel-mode base plus synced profile effects. Opportunity quantity is bounded by both configured capacity and modeled/current available quantity.

```text
gross = quantity × (selected MV basis - foreign price)
profit/hr = gross / total elapsed hours
```

Gross intentionally excludes travel cost. Hit probability is displayed separately and is not multiplied into `PROFIT/HR`.

## Travel + bars

`TravelContext.ps1` performs one bounded fail-soft user request for travel/basic/bars. Transient failures preserve the last successful destination/bar context. While outbound/abroad to a recognized destination, opportunity selection is restricted to that destination. `traveling_unknown` / `abroad_unknown` fails closed.

Energy/Nerve waste policies remain local decision constraints and never mutate observation history.

## Projection / interaction

`StateReader.lua` performs immediate local sorting so button response does not wait for PowerShell persistence. It reads only the last finalized `ui-state.kv`, so intermediate PowerShell mutations are never visible to the main Rainmeter surface. Genuine zero-result projections still replace the list when that completed generation is published.

One-second Rainmeter work remains local-only. Normal foreign-stock collection is approximately once per minute; inline rendering is local/on-demand; API credentials remain ignored/local.
