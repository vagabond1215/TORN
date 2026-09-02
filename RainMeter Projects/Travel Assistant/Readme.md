# Travel Assistant

Rainmeter-based Torn foreign-market opportunity assistant.

The current committed **0.6.0 candidate** presents a compact list of current/future foreign-market opportunities with transparent ordering, local historical graphs and profile-aware economics.

The next-generation stochastic forecast currently runs in **shadow mode only**.
It does not change cards, sorts, tooltips, filters, or Safe/Best guidance.

## Stochastic shadow artifact

Once per serialized update, a local-only challenger resamples retained completed
cycles as joint empirical observations, simulates through multiple future cycles,
applies physical travel feasibility, and evaluates expected after-tax economics.
Its ignored output is:

```text
data/runtime/stochastic-forecast.json
```

The schema includes arrival curves (`pAnyStock`, `pTargetQty`, expected quantity,
expected profit, and expected profit/hour), evidence diagnostics, and one mutually
exclusive shadow decision per market. Defaults are 128 deterministic seeded
scoring scenarios, a 15-minute **base** grid, a 12-hour departure search, and a
14-day recency half-life. For markets whose lower-quartile observed stock duration
is shorter than the base step, a small independently seeded discovery simulation
finds coarse cells containing hidden stock support; only the strongest cells are
refined, with a hard additional-candidate budget and restock-quantile anchors for
sub-minute bursts. Discovery worlds choose where to look but are not used to score
the published probability. These probabilities are not calibrated or user-facing.

Polling evidence is interval-censored: transition bounds are retained instead of
treating the later poll timestamp as exact. Stock declines to a positive value are
observed depletion; declines ending at zero are demand-censored lower bounds.

## Main view

```text
In Torn                                      [filter] [settings]

[UPCOMING] [GROSS PROFIT] [PROFIT/HR]

[FLAG]  Xanax | $775,013 | $21,700,364              +$...   [$]
        Restocks in ~47m                                      [chart]

[FLAG]  Ecstasy | $30,529 | $...                      +$...   [$]
        Collecting Data: See Weav3r                           [chart]

Updated ...
```

Up to eight opportunities may be shown.

### Card layout

- No visible row/place numbers.
- Destination is represented by a flag on the left.
- The visible left line is now the **item name only**. Foreign unit price and exact full-load purchase price live in the expanded economics strip so long values cannot crowd or truncate the primary card line.
- The right side is the selected primary profitability metric, rendered at 14 pt and centered vertically across both text lines. `UPCOMING` and `PROFIT` show signed after-tax total Net; `PROFIT/HR` shows signed after-tax total Net per round-trip flight hour. The item line remains 12 pt and the window/guidance line 9 pt.
- The top-right **$** button and lower-right chart button are centered in the two halves of one T-divided right-edge end cap. Active fills are inset so they do not paint over the border or T separators.
- Inactive icons are light gray; toggled controls use Torn-lime fill with dark-gray icon/text. Active sort text and the filter/settings icons use the same Torn-lime accent.
- The destination flag behaves as the card's left end cap and now extends behind the top/bottom border, removing the former 1px bands. Its visible left corners are alpha-masked to the card radius, with the bottom-left flag corner becoming square when the graph expands below it. A border-only overlay keeps the actual card edge visible above the flag.
- The space between the flag and item text is a 48×48 square matching the card's interior height. Torn's transparent item art is enlarged to 44×44 with a 2px inset in that square and cached from `https://www.torn.com/images/items/<itemId>/large.png` on demand.
- The window/guidance text is lowered close to the bottom border.
- Only one economics strip and one inline graph may be expanded at a time; each follows stable `country:itemId` identity through local reordering. Clicking the card body toggles both sections together, while the `$` and chart buttons still toggle their individual section.
- Inline graphs use a black background with a Torn-lime stock line. Cobalt-blue in-stock/restock and pumpkin-orange out-of-stock/sellout transitions are short ticks below the X axis so they do not cover the stock trace.
- Only the flag and the visible window/guidance line have tooltips. When a departure window is already open, its tooltip uses `OPEN NOW` instead of listing past departure timestamps; expired Safe windows are labeled `closed`.

Expanded economics are:

```text
[Each]  MV:$...          $/hr:+$...  || [Total]  MV:$...          $/hr:+$...
        Price:$...      5% Tax:$...            Price:$...      5% Tax:$...
```

`Each` and `Total` are separate vertical label blocks filled with the card-border gray and centered vertically. MV stays top-left. The top-right cell shows the profitability metric **not** shown as the large primary value: with `UPCOMING` / `PROFIT`, it is round-trip flight `$/hr`; with `PROFIT/HR`, it becomes signed Net. The lower-left cells show foreign unit **Price** and exact full-load **Price** respectively, while Tax moves to the lower-right cells and remains hidden at 0%. The strip stays 34px tall. `$/hr` is after-tax Each/Total net divided by `2 x` configured one-way flight seconds and excludes window/wait time.

## Sort modes

Selectable sorts are:

- **UPCOMING** — earliest current/modeled stock window first.
- **PROFIT** — highest displayed after-tax total Net first. Positive profits always rank above negatives; negative values are compared as signed numbers rather than by magnitude.
- **PROFIT/HR** — after-tax net trip profit divided by configured round-trip flight hours (`2 x` one-way flight time); window/wait time is excluded.

Alphabetical **Name** ordering is not selectable. It is used only as an internal fallback when the visible rows have neither usable timing nor usable profit inputs.

Hit likelihood remains separate from the sort score. Sort changes are applied immediately to current rows in Lua rather than waiting for a PowerShell/network update.

Saving trip/category/item/Ignore filters starts a dedicated `RefreshFilters` pass. It reuses the already-collected foreign-stock snapshot, refreshes only newly eligible missing/stale resale prices (up to 40 items on the explicit save), reruns opportunity calculations, and publishes after that recompute so items that were previously filtered out do not have to wait for later minute polls.

## Fresh stock and likelihood learning

Fresh current stock stays useful even before enough completed cycles exist to estimate arrival survival.

For a fresh in-stock market:

- trained likelihood shows as a percentage;
- untrained likelihood shows as **LEARNING**;
- the row remains visible rather than disappearing.

Sold-out/future windows remain evidence-gated and require completed sellout/restock + availability history.

## Economics

```text
sale price = declared/list MV
gross sale = MV × quantity
purchase cost = foreign price × quantity
gross profit = gross sale - purchase cost
tax = floor(gross sale × selected 0%..5% rate)
make = gross profit - tax
profit/hr = make / round-trip flight hours
```

`Full-load cost` is always exact `foreign unit cost × quantity`. Historical price variation remains useful evidence but no longer adds any automatic purchase-cash buffer.

Gross profit intentionally excludes travel cost. Total elapsed time includes waiting, outbound travel, return travel and purchase buffer.

Settings control a 0%, 1%, 2%, 3%, 4%, or 5% sale-tax / trader rate plus profitable-only filtering. The declared MV itself is never discounted by this rate. Saving Settings uses the same mutex-waiting `RefreshFilters` projection path as filter saves, ensuring the published Tax, Net, and flight-rate values are recalculated from the newly selected rate without issuing another foreign-stock collection request.

## Graphs

Each card has one local inline graph surface.

Click the chart button:

- the card expands inside the list;
- an 8-hour stock history is drawn locally;
- later cards move down;
- opening another graph collapses the first;
- clicking the active chart button collapses it;
- the graph follows stable `country:itemId` identity through sorting.

Inline graph rendering reads retained local observations only. It makes no Prometheus/YATA/Torn request. The standalone WinForms Viewer has been removed.

The graph uses an 8-hour display while learning retention remains approximately 48h raw observations / 90d completed cycles. Change-only history carries its prior state across the window boundary. Sold-out-only history stays flat at zero rather than showing an artificial `0..1` axis.

## Filters / Ignore List

Primary filters:

```text
S [flags...] ON OFF
M [flags...] ON OFF
L [flags...] ON OFF
CATEGORIES ... ON OFF
ITEMS [search] ON OFF
```

The item list is scoped immediately by the current country and category selections. Reset, Save, and Cancel share the bottom action row.

Trip bands are presentation labels only:

```text
Short:  Mexico, Cayman Islands, Canada
Medium: Hawaii, United Kingdom, Argentina, Switzerland
Long:   Japan, China, UAE, South Africa
```

Ignore List excludes items from opportunities/background optimizer candidates and broad per-item MV requests. Shared provider stock/history collection continues.

## Capacity / travel profile

Capacity remains profile-aware and category-aware. Recorded profile behavior includes:

```text
Airstrip general/Xanax = 18
Standard general/Xanax = 13
Flower Shop 7★ -> +5 Flower only
Toy Shop    7★ -> +5 Plushie only
```

Energy/Nerve waste policies remain independently configurable and constrain new outbound opportunities while preserving guidance after travel is already committed to a recognized destination.

## Runtime layering

```text
UpdateTracker
ShadowCollector
LocalCatalog
FinalizeState
TravelContext
OpportunityState    # primary opportunity projection (uses local helpers from OptimalRoute.ps1)
WindowPlan / PriceVariationRefiner
FilterState
visible heartbeat
CycleAnalytics / TrendForecast / StochasticForecast (shadow)
ResalePriority
ResaleQueue
```

Inline graph rendering is a separate local on-demand side path. Steady-state one-second Rainmeter work is local; when a newly visible item lacks cached art, the skin may enqueue one bounded static PNG fetch from Torn's item-image path. This decorative fetch is separate from the travel/bars and broad Torn Item Market API request limits.

## Current data baseline

Recorded last target-Windows baseline:

```text
Prometheus
11 countries
232 provider country-item rows
232/232 rows with provider names
202 distinct item IDs
202/202 categories resolved
5 verified legacy provider rows
227 active country-item markets
```

These are baseline counts, not timeless constants.

## Installation

Repository source is expected approximately at:

```text
C:\Codex\TORN\RainMeter Projects\Travel Assistant\
```

Install/junction setup:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\Install.ps1
```

Load:

```text
Travel Assistant\TravelAssistant.ini
```

## Current validation

The compact 0.6 candidate is pending target-Windows/Rainmeter acceptance. Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-CurrentAcceptance.ps1
```

Then run one production update and verify collapsed flag cards, the $ economics strip, one expanded inline graph, immediate sorting, and Settings/filters. See `docs/NEXT_CODEX_RUN.md` for the current exact checklist.

## Future notifications

Optional Chrome/browser notifications remain planned after this opportunity surface is accepted. They should consume the same accepted local timing projection rather than maintain a second forecasting model.
