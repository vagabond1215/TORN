# Travel Assistant

Rainmeter-based Torn foreign-market next-trip assistant.

The current committed **0.5.0 candidate** replaces the earlier multi-card graph view with one compact optimal next-trip recommendation. It is pending target-Windows/Rainmeter acceptance.

## What it does

Travel Assistant continuously learns foreign stock/restock behavior across all 11 destinations, keeps a local item/category catalog, gradually caches Torn MV, and chooses the best currently supportable next trip under the user's filters and bar-waste constraints.

```text
COLLECTED provider rows
        !=
ACTIVE market relationships
        !=
OPTIMIZER candidates
        !=
CURRENT purchase recommendation
```

## Minimal main view

```text
Travel                                      SETTINGS >
Updated ...
ITEM All ▾   TRIP SHORT MED LONG ▾   CAT All ▾   RESET

OPTIMAL • <destination>              <expected value>
<arrival/out> • <slots> • <hit chance> • E loss • N loss
<item>          xN   $foreign ($MV)   <arrival chance>
```

Only the item(s) the selected trip should purchase are shown. Item names are consistently left-aligned. MV is shown in parentheses at a smaller muted size.

The old default UK/Japan card stack and graphs are not part of the 0.5 main surface.

## Route inputs

The current next-trip planner considers:

- active foreign markets and current stock;
- foreign shop price;
- Torn MV (`itemmarket.item.average_price`);
- travel method/time/cost;
- general and category-only carrying capacity;
- retained restock/sellout/availability history;
- modeled chance an item is available on arrival;
- Energy/Nerve regeneration waste;
- Item/Trip/Country/Category filters;
- Ignore List.

It currently scores **next trips**, not full multi-trip sequences. A later scheduler can compare repeated short trips, fewer long trips, and mixed-country sequences over a bounded horizon.

## Value / color behavior

Default:

```text
100% Torn MV basis
no Item Market fee deduction
no minimum-profit or minimum-margin timing gate
negative-value candidates allowed
```

Settings can switch to 95% MV.

```text
foreign price <= selected MV basis -> green
foreign price > selected MV basis  -> red
```

`Show profitable items only` explicitly excludes non-positive item spreads. Otherwise users may still choose/receive negative-value trade candidates when they are optimal under the active filter set.

## Energy / Nerve settings

Settings supports independently:

```text
Energy Waste: Allowed / Forbidden / Limited
Max Energy Loss
Nerve Waste:  Allowed / Forbidden / Limited
Max Nerve Loss
```

If Energy is already above its natural maximum, the Energy waste restriction is bypassed to support stacking scenarios. Nerve does not receive that bypass.

The same bounded Torn user request supplies travel state plus bar data (`travel,basic,bars`).

## Filters / Ignore List

Filter bar:

```text
ITEM All ▾   TRIP SHORT MED LONG ▾   CAT All ▾   RESET
```

Item/Category selectors use the active local catalog. Trip bands are presentation labels only:

```text
Short:  Mexico, Cayman Islands, Canada
Medium: Hawaii, United Kingdom, Argentina, Switzerland
Long:   Japan, China, UAE, South Africa
```

Ignore List uses the complete local metadata catalog. Ignored items are excluded from optimizer candidates and broad per-item MV requests. Shared Prometheus/YATA country-stock collection/history continues because ignoring one item does not save those shared provider calls.

## Current accepted data baseline

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

Provider presence is provenance, not unconditional proof of current shop membership. Verified inactive relationships remain retained but are excluded from new learning/resale/optimizer work.

## Broad MV queue

```text
max Torn Item Market requests/update: 1
minimum attempt interval:             60 seconds
MV freshness target:                   6 hours
general failure backoff:               1 hour
optimizer-priority failure retry:      5 minutes
request timeout:                       6 seconds
```

Optimizer MV blockers are prioritized without increasing the request cap.

## Capacity

Accepted current-capacity behavior:

```text
Airstrip general/Xanax = 18
Standard general/Xanax = 13
Flower Shop 7★ -> +5 Flower only
Toy Shop    7★ -> +5 Plushie only
```

The planner fills general slots first, then matching category-only slots.

## Runtime layering

```text
UpdateTracker
ShadowCollector
LocalCatalog
FinalizeState
TravelContext
OptimalRoute
FilterState
visible heartbeat
ResalePriority
ResaleQueue
```

`OptimalRoute`, `FilterState`, and `ResalePriority` are local-only. Catalog metadata network maintenance remains manual-only.

## Local files / secrets

Ignored/local state includes:

```text
config/settings.local.json
data/runtime/preferences.json
runtime observations/cycles/cache/state/errors
@Resources/Generated/
```

API keys are never committed or packaged.

## Installation

Repository source is expected at approximately:

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

A whitelist-based `.rmskin` builder exists for sharing without local credentials/history/preferences.

## Current validation

The 0.5 candidate requires focused Windows tests plus one live update and Rainmeter screenshot. Use `docs/NEXT_CODEX_RUN.md` for the current commands; static validation does not replace actual Rainmeter rendering/API behavior.

## Documentation

Read in order:

1. `AGENTS.md`
2. `docs/README.md`
3. `docs/NEXT_CODEX_RUN.md`
4. `docs/ARCHITECTURE.md`
5. `docs/IMPLEMENTATION_STATUS.md`
6. `Readme.md`
