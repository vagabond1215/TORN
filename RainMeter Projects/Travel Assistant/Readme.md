# Travel Assistant

Rainmeter-based Torn foreign-market opportunity assistant.

The current committed **0.6.0 candidate** presents a compact list of current/future foreign-market opportunities with transparent ordering, local historical graphs and profile-aware economics.

## Main view

```text
In Torn                                      [filter] [settings]

[UPCOMING] [GROSS PROFIT] [PROFIT/HR]

[FLAG]  Xanax | $771,397   Take: $22,679,072   Make: $2,069,508   [$]
        Restocks in ~47m                                      [chart]

[FLAG]  Ecstasy | $30,529  Take: $897,553      Make: $188,748     [$]
        Collecting Data: See Weav3r                           [chart]

Updated ...
```

Up to eight opportunities may be shown.

### Card layout

- No visible row/place numbers.
- Destination is represented by a flag on the left.
- The visible first line uses fixed columns: **Item | foreign cost**, **Take**, and **Make**.
- `Take` is exact purchase cash for fixed-price markets and adds a 5% reserve only for demonstrated variable-price markets.
- `Make` is after-tax profit and never subtracts the unused Take reserve.
- The top-right **$** button expands/collapses the one-line economics strip and highlights while open.
- The lower-right chart button expands/collapses the local 8-hour stock graph and highlights while open. `$` and chart occupy the two halves of one T-divided right-edge end cap.
- Only one economics strip and one inline graph may be expanded at a time; each follows stable `country:itemId` identity through local reordering.

Expanded economics are:

```text
MV:$...  Each:$...  Gross:$...  Per Hour:$...  <rate>% Tax:$...
```

Labels are white. MV value is gold-yellow; Each/Gross/Per Hour values are white; Tax value is muted gray at zero and light red when nonzero.

## Sort modes

Selectable sorts are:

- **UPCOMING** — earliest current/modeled stock window first.
- **GROSS PROFIT** — highest total trip gross first.
- **PROFIT/HR** — after-tax net trip profit divided by total elapsed hours.

Alphabetical **Name** ordering is not selectable. It is used only as an internal fallback when the visible rows have neither usable timing nor usable profit inputs.

Hit likelihood remains separate from the sort score. Sort changes are applied immediately to current rows in Lua rather than waiting for a PowerShell/network update.

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
profit/hr = make / total elapsed hours
```

`Take` is the purchase-cash requirement: exact purchase cost for fixed-price markets, or `ceil(purchase cost × 1.05)` when retained evidence shows variable pricing. The 5% reserve is cash-on-hand only and never reduces `Make`.

Gross profit intentionally excludes travel cost. Total elapsed time includes waiting, outbound travel, return travel and purchase buffer.

Settings control a 0%, 1%, 2%, 3%, 4%, or 5% sale-tax / trader rate plus profitable-only filtering. The declared MV itself is never discounted by this rate.

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
FilterState
visible heartbeat
ResalePriority
ResaleQueue
```

Inline graph rendering is a separate local on-demand side path. The one-second Rainmeter loop is local-only. Normal runtime keeps one bounded travel/bars request and at most one broad Torn Item Market request/update.

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
