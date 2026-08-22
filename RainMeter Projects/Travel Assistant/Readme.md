# Travel Assistant

Rainmeter-based Torn foreign-market opportunity assistant.

The current committed **0.6.0 candidate** presents a ranked list of evidence-backed item/country opportunities. Optimizer intelligence is an ordering/highlight layer rather than a single-route replacement screen.

## Main view

```text
Travel                                      SETTINGS >
Updated ...

ITEM All ▾   TRIP SHORT MED LONG ▾   CAT All ▾   RESET
SORT  OPTIMAL  UPCOMING  PROFIT  TIME                 VIEWER >

#1  OPTIMAL  <item>   <country>                     <gross>
    <window>  <leave>  <hit likelihood>  <elapsed>  <foreign> (<MV>)  GRAPH
#2           <item>   <country>                     <gross>
    ...
```

Up to eight opportunities are shown.

## Sort modes

- **OPTIMAL** — probability-weighted gross trip profit per total elapsed hour.
- **UPCOMING** — earliest current/modeled stock window first.
- **PROFIT** — highest gross trip profit first.
- **TIME** — shortest full elapsed opportunity first.

There is no separate Chance sort. Hit likelihood is shown on every opportunity and is already part of OPTIMAL. The globally best economic opportunity keeps an `OPTIMAL` marker even while another ordering is selected.

Gross profit is trade spread × modeled purchasable quantity and intentionally excludes travel cost. Total elapsed time includes waiting, outbound travel, return travel and purchase buffer.

## Evidence model

Travel Assistant learns from foreign stock/restock behavior across all 11 destinations and retains historical evidence independently of the visible UI.

```text
COLLECTED provider rows
        !=
ACTIVE market relationships
        !=
ELIGIBLE opportunity candidates
        !=
VISIBLE ranked opportunities
```

Current in-stock opportunities require evidence that stock is likely to survive until arrival. Sold-out opportunities require completed sellout→restock and availability history; supported future windows are derived from overlap of those completed historical live intervals. Forecasts never become history.

## Graphs

Graphs remain available on demand:

- `VIEWER >` opens the broad item/market viewer;
- every visible opportunity has `GRAPH`;
- row graph targeting uses stable `country:itemId` identity;
- graphs display the last 8 hours with hourly markers;
- change-only history carries the last pre-window observation into the graph’s left edge;
- learning retention remains ~48h raw observations / ~90d completed cycles;
- viewing a graph makes no provider or Torn request.

## Filters / Ignore List

Primary filters:

```text
ITEM All ▾   TRIP SHORT MED LONG ▾   CAT All ▾   RESET
```

Item/Category selectors use the active local catalog. Trip bands are presentation labels only:

```text
Short:  Mexico, Cayman Islands, Canada
Medium: Hawaii, United Kingdom, Argentina, Switzerland
Long:   Japan, China, UAE, South Africa
```

Ignore List excludes items from opportunities/background optimizer candidates and broad per-item MV requests. Shared provider stock/history collection continues.

## Value and capacity

Default value basis:

```text
100% Torn MV
no Item Market fee deduction
no minimum-profit or minimum-margin timing gate
negative-value candidates allowed
```

Settings can switch to 95% MV or explicitly show profitable items only.

Capacity remains profile-aware and category-aware. Current accepted profile behavior includes:

```text
Airstrip general/Xanax = 18
Standard general/Xanax = 13
Flower Shop 7★ -> +5 Flower only
Toy Shop    7★ -> +5 Plushie only
```

## Energy / Nerve

Settings support independently:

```text
Energy Waste: Allowed / Forbidden / Limited
Max Energy Loss
Nerve Waste:  Allowed / Forbidden / Limited
Max Nerve Loss
```

Energy above natural maximum bypasses Energy waste restriction. Nerve does not. Waste policies constrain new outbound opportunities but do not remove purchase guidance once travel is already committed to a recognized destination.

## Runtime layering

```text
UpdateTracker
ShadowCollector
LocalCatalog
FinalizeState
TravelContext
OptimalRoute        # background route / MV-priority model
OpportunityState    # primary ranked opportunity projection
FilterState
visible heartbeat
ResalePriority
ResaleQueue
```

The one-second Rainmeter loop and graph viewer are local-only. Normal runtime keeps one bounded travel/bars request and at most one broad Torn Item Market request/update.

## Current data baseline

Last target-Windows acceptance:

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

These are recorded baseline counts, not timeless constants.

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

The 0.6 candidate is pending target-Windows/Rainmeter acceptance. Run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-CurrentAcceptance.ps1
```

Then run one production update, refresh Rainmeter, test all four sort controls, Settings/filters/Viewer, and at least one row `GRAPH` action. See `docs/NEXT_CODEX_RUN.md` for the current acceptance procedure.

## Future notifications

Optional Chrome/browser notifications remain planned after the 0.6 opportunity surface is accepted. They should consume the same accepted local opportunity timing projection rather than maintain a second forecasting model.
