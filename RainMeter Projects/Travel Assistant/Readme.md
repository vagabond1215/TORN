# Travel Assistant

Rainmeter-based Torn foreign-market opportunity assistant.

The current committed **0.6.0 candidate** presents a compact list of current/future foreign-market opportunities with transparent ordering, local historical graphs and profile-aware economics.

## Main view

```text
Travel                                      SETTINGS >
Updated ...

ITEM All v   TRIP SHORT MED LONG v   CAT All v   RESET
NAME   UPCOMING   GROSS PROFIT   PROFIT/HR          VIEWER >

[FLAG]  Xanax                                 $777,870   v
[55m ]  IN STOCK   LEAVE NOW   67%   $804,358 ($847,573)

[FLAG]  Plushie                                $79,614   v
[47m ]  IN STOCK   LEAVE NOW   LEARNING   $400 ($4,823)
```

Up to eight opportunities may be shown.

### Card layout

- No visible `#1/#2/...` ranks.
- Destination is represented by a flag on the left.
- A white strip under the flag carries the existing elapsed/travel-time value.
- Country code/name and duplicate time are omitted from the card body.
- Gross is shown as a bare dollar amount; `gross x18` is not printed.
- Quantity remains available in the tooltip/internal projection so gross arithmetic can still be inspected.
- The right-side `v` expands an 8-hour graph inside that card; it becomes `^` while open.
- Only one inline graph can be open at once.

## Sort modes

- **NAME** — alphabetical item name, then destination.
- **UPCOMING** — earliest current/modeled stock window first.
- **GROSS PROFIT** — highest total trip gross first.
- **PROFIT/HR** — gross trip profit divided by total elapsed hours.

Hit likelihood is shown separately and is not multiplied into any hidden presentation score. Sort changes are applied immediately to the current rows in Lua rather than waiting for a PowerShell/network update.

## Fresh stock and likelihood learning

Fresh current stock stays useful even before enough completed cycles exist to estimate arrival survival.

For a fresh in-stock market:

- trained likelihood shows as a percentage;
- untrained likelihood shows as **LEARNING**;
- the row remains visible rather than disappearing.

Sold-out/future windows remain evidence-gated and require completed sellout/restock + availability history.

## Economics

```text
gross = (selected MV basis - foreign price) × purchasable quantity
profit/hr = gross / total elapsed hours
```

Gross intentionally excludes travel cost. Total elapsed time includes waiting, outbound travel, return travel and purchase buffer.

Default value basis:

```text
100% Torn MV
no Item Market fee deduction
no minimum-profit or minimum-margin timing gate
negative-value candidates allowed
```

Settings can switch to 95% MV or explicitly show profitable items only.

## Graphs

Travel Assistant now has two graph surfaces.

### Inline card graph

Click a row's `v` control:

- the card expands inside the list;
- an 8-hour stock history is drawn locally;
- later cards move down;
- opening another card collapses the first;
- clicking the open card again collapses it;
- the graph follows stable `country:itemId` identity through sorting.

Inline graph rendering reads local retained observations only. It makes no Prometheus/YATA/Torn request.

### Standalone Viewer

`VIEWER >` still opens the separate full market browser with:

- market dropdown;
- richer graph diagnostics;
- hourly labels;
- observed restock/sellout markers;
- stable market-key targeting.

Inline expansion does not replace the standalone Viewer.

Both graph surfaces use an 8-hour display while learning retention remains approximately 48h raw observations / 90d completed cycles. Change-only history carries its prior state across the window boundary. Sold-out-only history stays flat at zero rather than showing an artificial `0..1` axis.

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
OptimalRoute        # background compatibility / MV priority
OpportunityState    # primary opportunity projection
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

Then run one production update and verify collapsed flag cards, one expanded inline graph, immediate sorting, Settings/filters and the separate standalone Viewer. See `docs/NEXT_CODEX_RUN.md` for the current exact checklist.

## Future notifications

Optional Chrome/browser notifications remain planned after this opportunity surface is accepted. They should consume the same accepted local timing projection rather than maintain a second forecasting model.
