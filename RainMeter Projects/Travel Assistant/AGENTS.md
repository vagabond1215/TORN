# Travel Assistant Agent Instructions

These instructions apply to the entire `RainMeter Projects/Travel Assistant/` subtree.

## Read order

Before changing code or data, read:

1. `AGENTS.md`
2. `docs/README.md`
3. `docs/NEXT_CODEX_RUN.md`
4. `docs/ARCHITECTURE.md`
5. `docs/IMPLEMENTATION_STATUS.md`
6. `Readme.md`

If older plans conflict with an **ACTIVE** `NEXT_CODEX_RUN.md`, follow the active run while preserving every invariant here.

## Execution

- Prefer the connected GitHub connector for repository inspection/edits/contracts/commits.
- Use the target Windows host only for real Rainmeter, Windows PowerShell, and live provider/Torn validation.
- Never claim Windows/live validation that did not run.
- Work only inside this subtree unless explicitly broadened.
- Direct `main` edits are allowed; never force-push or rewrite unrelated work.
- Never expose/request an API key or full local settings file.

## Core population split

Never conflate:

```text
COLLECTED provider rows
        !=
ACTIVE market relationships
        !=
ELIGIBLE opportunity candidates
        !=
VISIBLE opportunities
```

- Collection remains broad across every valid provider row and all 11 foreign countries.
- Market identity is `country + itemId`.
- Provider presence is evidence about a feed, not proof a shop relationship is still active.
- Verified legacy relationships remain observable for provenance but receive no new history/resale/opportunity work.
- UI filters, Ignore List, sorting, profitability display, travel destination, and graph expansion never delete retained history.

## Current product: 0.6 compact opportunity surface

The rejected single `OPTIMAL` route card and later user-facing `OPTIMAL` composite sort are both retired. Do not restore either.

Main Rainmeter UI concept:

```text
In Torn                                      [filter] [settings]

[UPCOMING] [PROFIT] [PROFIT/HR]

[FLAG]  <item>                              <selected Profit or PROFIT/HR>   [$]
        <window / leave guidance>                                      [chart]

Updated ...
```

Card rules:

- No visible row/place numbers (`#1`, `#2`, etc.).
- Left side is a recognizable FlagKit destination flag.
- The hidden canonical Name meter remains item-name-only for downstream row lookup.
- The left first-line content is the item name only. Foreign unit cost and exact full-load cost move into the expanded economics strip; price variation never adds a cash buffer.
- Expanded full-load Price is muted light gray; per-item Price retains the projected price color.
- The selected primary profitability metric occupies the right side of both text lines at 14 pt, vertically centers on the flag, and is right-aligned. `UPCOMING` / `PROFIT` show total after-tax Net; `PROFIT/HR` shows total after-tax Net divided by round-trip flight hours. The item line is 12 pt; window/guidance text is 9 pt. Positive values use `+` and green; negative values use `-` and red.
- The top-right `$` button and lower-right chart button are centered in the two halves of the card-edge end cap. Their active fill is inset one pixel so the card border and T separators always remain visible above/around the highlight.
- Inactive end-cap icons are light gray. Active controls use a Torn-lime fill with dark-gray icon/text. Active sort text plus the main filter/settings icons use Torn lime; the graph's cobalt event ticks are intentionally unchanged.
- At most one economics strip and one inline graph are expanded at a time; both track stable `country:itemId` identity. Clicking the card body toggles both sections together; the `$` and chart end-cap buttons retain independent control of their own section.
- Inline graph rendering uses a black background and Torn-lime stock trace. A thin cyan hit-probability trace overlays the same 8-hour X-axis on its own implicit 0..100% scale (bottom=0%, top=100%) with no second axis labels. A faint dotted realized-hit waveform is the observed stock history shifted left by configured one-way flight time: top=that departure would have hit, bottom=it would have missed. Confirmed replay outcomes may add small hit/miss/error markers. Cobalt-blue restock/in-stock and pumpkin-orange sellout/out-of-stock transitions remain short ticks in the gutter below the X axis.
- Expanded economics use equal Each/Total halves with a vertical 40px label block at the left of each half. Each half is split into equal left/right metric cells by a subtle vertical separator. Every metric cell renders its label on the left and its monetary value right-aligned at the cell edge; economics-strip typography is 9 pt. MV is top-left. Top-right shows the profitability metric not used by the primary card: round-trip flight `$/hr` for `UPCOMING` / `PROFIT`, or signed Net for `PROFIT/HR`. Bottom-left shows per-item foreign Price / exact total purchase Price, and bottom-right shows Tax when nonzero. `$/hr` is after-tax Each/Total net divided by `2 x` configured one-way flight seconds and excludes waiting/window time. The expansion remains 34px at 0% tax, with only Tax label/value hidden.
- The FlagKit image is the visual left end cap. It extends underneath the card's top/bottom border (`67x50` beginning at the card origin), eliminating the former 1px bands. A panel-tinted alpha mask clips the flag to the rounded left corners and a border-only overlay redraws the card edge above it. Collapsed cards round both left corners; graph-expanded cards keep only the top-left flag corner rounded; economics-expanded cards keep only the bottom-left flag corner rounded; if both expansions are open the flag edge is square because neither flag corner coincides with the card corner.
- The region between the flag's right edge and the item-name text is a true `48x48` square, matching the card's interior height. Decorative Torn item art is rendered `44x44` with a 2px inset inside that square and cached locally from Torn's direct item PNG path (`https://www.torn.com/images/items/<id>/large.png`).
- The window/guidance line sits low in the card with minimal bottom padding.
- Tooltip policy is strict: only the destination flag and the visible window/guidance text may expose tooltips. Header controls, sort buttons, item art/text, economics, profit, end-cap buttons, and graph hover do not.
- Active-window tooltips never present already-passed departure timestamps as actionable times. Once the departure window has opened they say `OPEN NOW`; expired Safe windows say `closed`, and only future departure/close timestamps remain.

Ordering is selectable and persistent only for:

- `UPCOMING`: soonest current/modeled stock window first.
- `PROFIT`: highest displayed after-tax total Net first. Sorting is signed descending: all positive profits rank above all negative profits, and negatives are ordered normally (`-$100` above `-$1,000`), never by absolute magnitude.
- `PROFIT/HR`: after-tax net trip profit divided by configured round-trip flight hours; waiting/window time is excluded.
- Alphabetical Name ordering is internal fallback only when the visible rows have neither usable timing nor usable profit inputs.
- Hit likelihood is a separate displayed metric; do not fold it into a hidden sort score.
- Multi-cycle fallback hit likelihood is `pAnyStock` at the earliest feasible arrival. Full-load `pTargetQty`, long-run occupancy `E[in-stock]/E[full cycle]`, flight/cycle ratio, and phase-dispersion diagnostics belong in tooltip/diagnostic context; they do not alter sort ranking.
- There is no user-facing `NAME`, `OPTIMAL`, Chance, or shortest-Time sort.
- The three main sort/filter controls use equal-width 104px buttons with bold 11 pt labels so UPCOMING / PROFIT / PROFIT/HR remain legible without changing the header height.
- Sort controls reorder already-projected rows immediately in Lua; persistence is a tiny local write and must not wait on a full opportunity recompute.

Economic semantics:

```text
gross sale = declared/list MV × quantity
gross profit = gross sale - purchase cost
tax = floor(gross sale × selected rate), where rate is 0%..5%
make = gross profit - tax
profit/hr = make / round-trip flight hours
```

Gross intentionally does not subtract travel cost. Total elapsed includes required wait, outbound travel, return travel, and purchase buffer; if returning to Torn, remaining return time precedes the next outbound opportunity.

Travel restrictions:

- While outbound/abroad to a recognized destination, visible opportunities are restricted to that destination.
- `traveling_unknown` / unresolved foreign destination fails closed rather than suggesting an unrelated trip.

## Current-stock vs forecast evidence

Fresh current stock is useful even before enough cycles exist to estimate arrival survival.

- A fresh in-stock market may remain visible with `ChanceText=LEARNING` / unknown probability.
- Never fabricate a percentage for an untrained current market.
- `LEARNING` likelihood must not erase the row or collapse the entire surface.
- Known arrival probabilities remain displayed as percentages.
- A restricted production multi-cycle fallback may show `Chance to hit: NN%` when the earliest feasible arrival spans at least two weighted mean full cycles, at least three usable completed joint cycles exist, and legacy current-cycle/Safe/Best guidance cannot produce an actionable result. It reuses stochastic-v1.1 joint-cycle renewal simulation at exactly one earliest-feasible arrival; it is not a second forecasting model and must never be labeled Safe/Guaranteed.
- When fresh positive stock is already observed but its restock boundary is left-censored, `WindowPlanRefiner` may replace Collecting Data with `Safe Window Open` only if >=3 uncensored positive-stock depletion samples span >=10 minutes and a pessimistic current-run depletion rate still gives at least 2x the time-to-arrival (and >=30 minutes extra) of runway. The guarded rate uses the 90th-percentile observed nonzero depletion x1.5 with a hard floor of 60 units/hour. This fallback never fabricates a percentage and never teaches recurring cycle history.
- Sold-out/future opportunities still require completed sellout→restock + availability evidence before a future window is shown.
- If already at a recognized destination, fresh current stock remains direct current-state evidence.

This distinction is deliberate: current observed stock is a fact; future survival/restock confidence is learned context.

## Graphs and history

There is one graph surface: the inline card graph.

- Opened with the per-row chart Shape button.
- Rendered inside the Rainmeter card/list.
- One expanded market at a time.
- Uses dedicated `MeasureInlineGraph` -> `RenderInlineGraph.ps1` local rendering. Graph-hover tooltip telemetry is retired; the graph is display-only.
- Refreshing an open graph is local-only and may occur at approximately one-minute cadence.
- The standalone WinForms Viewer and its launcher are retired; do not restore them.

The inline graph:

- displays an 8-hour history window;
- uses retained observations only plus truthful carried-baseline continuity;
- never polls Prometheus/YATA/Torn;
- never turns a forecast into observed history;
- never invents a restock or sellout transition;
- preserves learning retention independently (48h high-resolution observations / 90d completed cycles).
- stores live forecast probabilities separately in ignored `data/runtime/chance-history.jsonl`, one market/minute for 8 hours;
- stores strictly resolved forecast/outcome pairs separately in `resolved-arrival-history.jsonl` plus `chance-accuracy.json`; future evidence labels the later outcome but never alters the previously recorded probability;
- may render a flight-shifted realized-hit proxy from actual retained stock for hindsight pattern analysis, but that hindsight waveform is truth/diagnostic only and must never feed forecasting evidence.

Change-only history must carry the last predecessor across the display/retention cutoff. A previous bootstrap-only migration hole may be repaired to a carried baseline using recorded `firstSeenAt` and unchanged current state; this is continuity metadata, not a fabricated transition.

A sold-out-only graph must remain visually flat at zero, not use a fake `0..1` stock axis.

## Filters and local UI state

Persistent local UI state lives in ignored `data/runtime/preferences.json`.

Current schema includes:

```text
travelMode
itemMarketFeePercent          # sole tax/trader-rate authority; integer 0..5
itemFilterAll
selectedItemIds
selectedTripBands            # always all candidate bands in schema 7
displayTripBands             # user-selected visible trip bands
selectedCountryIds
categoryFilterAll
selectedCategories
showProfitableOnly
ignoredItemIds
energyWastePolicy
maxEnergyLoss
nerveWastePolicy
maxNerveLoss
sortMode                     # upcoming | gross | profit_per_hour
```

Legacy sort migration:

```text
optimal -> profit_per_hour
profit  -> gross
time    -> upcoming
name    -> upcoming
```

Item and Category popups use the active local catalog, not only old proof-card seeds. The Country popup follows `displayTripBands`; `selectedTripBands` remains the broad candidate scope.

Trip bands are presentation/filter taxonomy only:

```text
Short:  Mexico, Cayman Islands, Canada
Medium: Hawaii, United Kingdom, Argentina, Switzerland
Long:   Japan, China, UAE, South Africa
```

Never use these labels as travel-time/economics authority.

### Ignore List

- Enumerates the complete local metadata catalog when available.
- Ignored items are excluded from opportunity/background optimizer eligibility and broad per-item Torn MV requests.
- Shared country-level Prometheus/YATA stock collection remains broad because suppressing one item does not save that provider request.
- Ignore/unignore never deletes historical evidence.

## Value/profitability semantics

Profitability is presentation/ranking context, not permission to learn and not a timing-window gate.

Value and tax basis:

```text
sale price = declared/list Torn MV (itemmarket.item.average_price)
selected tax / trader rate = integer 0%..5%
tax applies once to gross sale proceeds
minimum profit gate = 0
minimum margin gate = 0
```

Economic color is based on after-tax net item profitability when MV is fresh; stale MV remains muted.

Negative-value items remain legal candidates unless `Show profitable items only` is explicitly enabled. Legacy `FinalizeState.ps1` economics are informational only and must not rewrite timing status/history.

## Availability/evidence invariants

1. Prefer unknown likelihood over invented confidence.
2. `0 -> positive` is an observed restock; `positive -> 0` is an observed sellout.
3. Forecasts never become history.
4. History is isolated by `country + itemId`.
5. Foreign price is first-class evidence.
6. Current depletion may shorten support, never expand conservative historical support.
7. Fresh current in-stock rows can be visible while arrival likelihood is `LEARNING`.
8. Sold-out future opportunities require completed cycle evidence.
9. Estimated future restock quantity may use observed `0 -> positive` quantities.
10. Stale provider markets are not visible opportunity candidates.
11. Change-only pruning preserves one predecessor/baseline per market.
12. Sorting and inline graph expansion never write forecast history.
13. Chance history / resolved replay history are forecast diagnostics, not observations; they never enter `observations.jsonl` or `cycles.jsonl`.
14. Hindsight flight-shifted hit/miss data may evaluate pattern quality but must never be used as if it were known at the original departure timestamp.

## Energy / Nerve constraints

Travel context obtains bars in the existing bounded user request (`travel,basic,bars`).

Policies are independent:

```text
Energy Waste: Allowed | Forbidden | Limited
Max Energy Loss: N

Nerve Waste:  Allowed | Forbidden | Limited
Max Nerve Loss: N
```

- Loss is modeled natural regeneration wasted over the full opportunity horizon.
- If `energy.current > energy.maximum`, Energy waste policy is bypassed.
- Nerve does not receive that bypass.
- Unknown bar data fails safe for any non-Allowed policy.
- Waste constraints filter new outbound opportunities.
- After travel is committed to a recognized destination, waste constraints must not make destination guidance disappear.

## Capacity authority

Prefer current `/user/perks` sync for carrying capacity.

Mode base:

```text
Standard: 10
Airstrip/WLT/qualified Business: 15
```

Accepted synced example:

```text
Airstrip general/Xanax = 18
Standard general/Xanax = 13
```

Category-only company effects remain isolated:

- Flower Shop 7★: +5 Flower only.
- Toy Shop 7★: +5 Plushie only.
- Neither increases Xanax/general capacity.

Positive explicit `profitability.capacityOverride` remains authoritative where supported.

## Travel context

`TravelContext.ps1` may make one bounded fail-soft Torn user request per normal update:

```text
/v2/user?selections=travel,basic,bars
```

It retains destination/travel timestamps plus Energy/Nerve bars. On transient failure preserve the last successful foreign restriction/bar context. Its diagnostic file is child-owned and must survive internally caught request failures.

## Catalog baseline

Recorded target-Windows baseline from 2026-08-21:

```text
Prometheus
11 countries
232 observed country-item provider rows
232/232 provider names
202 distinct item IDs
202/202 categories resolved
5 verified legacy rows
227 active country-item markets
```

Verified legacy rows:

```text
mexico:21
mexico:232
mexico:327
united_arab_emirates:383
united_arab_emirates:440
```

Do not hard-code these live counts as timeless constants.

Catalog network maintenance remains manual-only. `RunUpdate.ps1` must not invoke `ItemMetadata.ps1`.

Local metadata precedence:

```text
richer manual Torn metadata
    > explicit config seed
    > verified item override
    > offline category snapshot
    > provider name + Unknown
```

## Broad resale/MV queue

`ResaleQueue.ps1`:

- active relationships only;
- at most one Torn Item Market request per update;
- default cadence 60s, freshness 6h, general failure backoff 1h, timeout 6s;
- key only via stdin curl config + Authorization header;
- successful cache survives later failures;
- missing/zero price remains unresolved.

`ResalePriority.ps1` is local-only and may prioritize pricing blockers or park ignored IDs. It never makes its own request or increases the one-request cap.

## Runtime order

Current production order:

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
OpportunityState        # primary opportunity projection; dot-sources OptimalRoute helpers
WindowPlan
MultiCycleChanceBridge  # restricted pAnyStock fallback; no departure-grid optimization
PriceVariationRefiner
FilterState
immutable UI generation + last-update manifest
CycleAnalytics
TrendForecast
ResalePriority
ResaleQueue              # <= 1 market request
```

`OptimalRoute.ps1` is helper-only local infrastructure for opportunity forecasting/economics tests; its standalone OPTIMAL route/UI stage is retired. The old independent-card `VisibleItems.ps1` and card-pinning path are removed. Inline graph rendering is handled separately by `RenderInlineGraph.ps1`.

## Projection / interaction stability

- The steady-state one-second Lua loop is local-only. If a newly visible item has no cached decorative art, Lua may enqueue one bounded `EnsureItemImages.ps1` fetch for the missing static PNG; failed IDs are throttled for five minutes.
- `state.kv` is a private build artifact. Rainmeter consumes complete immutable `ui-state-<epoch>-<id>.kv` generations selected by `last-update.txt`.
- Never replace a hot Rainmeter-read state pathname as the normal publication mechanism; a failed generation must leave the previous complete generation visible.
- Never flash an already-populated surface to `Learning opportunities...` because a child stage is still running.
- A transient learning-only zero pass is not authoritative over a previously valid nonzero projection.
- Sorts are immediate local Lua reorderings.
- Text/button controls need stable rectangular hitboxes.
- Inline expansion reflows immediately without a provider/Torn API call. Item-art CDN fetches are independent decorative cache fills and do not alter provider/API request ownership.

## Runtime diagnostics / popup contract

- Rolling local log: `data/runtime/logs/travel-assistant.log`.
- Runtime/popup failures should include component and source context.
- Stale compact error markers may clear after successful component runs.
- Popups launch through hidden STA PowerShell; no visible console should persist.
- Popup launchers are spawn-only and reusable: after spawning they `return` rather than `exit`, so nested popup calls do not terminate the parent Settings host.
- Settings/filter saves that need a projection refresh route through `Start-FilterProjectionRefresh` / `LaunchUpdate.ps1`; do not start `RunUpdate.ps1` directly under Windows PowerShell 5.1. Settings, Filter, Ignore, and Reset changes use mutex-waiting `RefreshFilters`: it recomputes against the retained all-market stock snapshot, targets missing/stale resale prices for newly eligible items (bounded to 40 explicit requests), reruns opportunity economics, and only then publishes the new UI generation.
- Runtime logs/history/preferences/generated graph specs remain ignored/local.

## Secrets / local files

- API key and `config/settings.local.json` stay local/ignored.
- Runtime observations, cycles, caches, preferences, state, errors and generated artifacts stay ignored/local.
- Never put the key in URL/process arguments when stdin/header transport is available.
- Do not broaden API permissions for convenience.

## Performance budget

- steady-state one-second Rainmeter loop: local only, except a bounded on-demand static item-art cache fill for newly visible uncached IDs;
- `MultiCycleChanceBridge.ps1` is local-only/network-free and may reuse stochastic-v1.1 only for a single earliest-feasible arrival with adaptive departure search disabled; it must not move the full 12-hour stochastic search onto the pre-publication critical path.
- immediate row sorting: local Lua only;
- inline graph renderer: local/on demand, roughly no more often than once/minute while expanded;
- serialized updater: roughly once/minute;
- shadow collection: no more often than ~120s unless revalidated;
- travel/bars: one bounded request per normal update;
- broad MV queue: at most one lower-priority request after heartbeat;
- no permanent background PowerShell/browser process.

## Browser notifications

Browser/Chrome notifications remain a future optional companion. They must consume accepted local opportunity timing state, remain opt-in, dedupe repeated windows, and add no provider/Torn request path.

## Distribution

`.rmskin` packaging must include runtime scripts/config/catalog references and exclude secrets and local runtime/generated data. Ensure `RenderInlineGraph.ps1` is packaged automatically with other runtime scripts; generated `inline-graph-*.kv` files must not be packaged.

## Current validation boundary

The 0.6 compact opportunity implementation is **pending target-Windows/Rainmeter acceptance**. The Item filter popup has target-host evidence from the 2026-08-26 Codex pass; the other popup/nested Settings paths still require target-host interaction acceptance. Do not call 0.6 accepted until focused parser/deterministic tests, one production update, visible current-stock rows, flag rails, economics/graph expansion, sort/filter controls and screenshots pass on the target host.

See `docs/NEXT_CODEX_RUN.md` for the current exact acceptance commands.
