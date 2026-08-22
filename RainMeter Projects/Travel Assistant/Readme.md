# Travel Assistant

Rainmeter-based Torn foreign-market travel decision assistant.

The current committed **0.4.0 candidate** has four independent item cards, persistent presentation filters, one pinned/favorite market, travel-destination relevance, profitable-only view, and a full-catalog Ignore List. It is pending target-Windows/Rainmeter acceptance for those new controls.

## Core separation

```text
COLLECTED provider rows
        !=
ACTIVE market candidates
        !=
VISIBLE opportunities
        !=
OPTIMIZER candidates
```

The application learns stock cycles broadly while exposing only deliberately promoted opportunities.

## Current visible proof cards

```text
United Kingdom
  Xanax
  Nessie Plushie

Japan
  Xanax
  Cherry Blossom
```

Each item is an independent card with its own border, flag, price, stock header, expand/collapse state, and graph body where supported.

Every header shows:

```text
foreign shop price (Torn Item Market reference)
```

The foreign value is primary/profitability-colored. The market reference in parentheses is smaller and muted. Missing broad resale remains `-` rather than becoming zero economics.

The default global expansion cap is two cards. Secondary Nessie/Cherry cards have their own retained-history graphs but still do not emit actionable Xanax-style departure timing.

## Filter bar

Below the update/source line:

```text
ITEM  All ▾   TRIP SHORT MED LONG ▾   CAT All ▾   RESET
```

- **ITEM** opens a persistent checkbox popup for currently renderable items.
- **SHORT / MED / LONG** independently toggle trip bands.
- The trip `▾` opens a persistent country selector for individual destination exceptions.
- **CAT** opens a persistent category selector.
- **RESET** restores presentation defaults but preserves pin, Ignore List, and travel mode.

Trip bands are presentation labels only:

```text
Short:  Mexico, Cayman Islands, Canada
Medium: Hawaii, United Kingdom, Argentina, Switzerland
Long:   Japan, China, UAE, South Africa
```

They do not replace existing per-country travel-time/economics data.

## Pin / favorite

Right-click an item title or expand glyph to pin/unpin one `country:itemId` market.

A pinned card:

- displays `★`;
- stays expanded;
- moves to the top;
- cannot be auto-collapsed;
- consumes one of the expanded-card slots.

At home a pin overrides ordinary Item/Trip/Country/Category/profitable-only filters. While traveling/abroad, destination relevance wins: a pinned UK card is hidden during a Japan trip. Ignore List also wins over pin.

Pin and filter state are stored only in ignored local runtime preferences.

## Settings

Settings includes:

```text
[ ] Show profitable items only
[ Ignore List... ]
```

Profitable-only hides opportunities whose current modeled economics are not positive/usable.

Ignore List enumerates the full local catalog. Ignored items are hidden and excluded from broad per-item Torn Item Market requests.

Ignore List does **not** stop shared Prometheus/YATA country-stock collection because those provider calls already return many items together; filtering one item would not save the provider request and would stop useful history collection.

## Travel relevance

A bounded fail-soft Torn travel/basic check projects the current destination. When traveling/abroad to a recognized foreign destination, the current card renderer hides other countries.

The travel context already retains arrival timestamps/time-left for a future locally ticking arrival countdown. The 0.4.0 candidate does not yet replace the static flight-duration text with that countdown.

## Full-market background observation

All 11 Torn foreign destinations are observed. Last accepted target-Windows baseline:

```text
Prometheus
11 countries
232 provider country-item rows
232 / 232 rows with provider names
202 distinct item IDs
5 verified legacy provider rows
227 active country-item markets
202 / 202 categories resolved locally
```

Provider presence is provenance, not unconditional proof of current shop membership. Verified inactive relationships remain retained but are excluded from new learning/resale/display work.

## Broad resale-price population

Broad Torn Item Market pricing remains bounded:

```text
max requests per normal update: 1
minimum attempt interval:       60 seconds
broad freshness target:          6 hours
hidden/general failure backoff:  1 hour
visible/pinned failure retry:    5 minutes
request timeout:                 6 seconds
```

Ignored items are parked outside this broad per-item queue. The established Xanax price path remains independent/fresher.

## Category-aware capacity

Accepted capacity behavior:

```text
Airstrip general/Xanax = 18
Standard general/Xanax = 13
Flower Shop 7★ -> +5 Flower only
Toy Shop    7★ -> +5 Plushie only
```

So qualifying Airstrip Flower/Plushie capacity can be 23 while Xanax remains 18.

## Runtime layering

```text
UpdateTracker
ShadowCollector
LocalCatalog
FinalizeState
TravelContext
VisibleItems
FilterState
visible heartbeat
ResalePriority
ResaleQueue
```

`VisibleItems`, `FilterState`, and `ResalePriority` are local-only. `TravelContext` and broad resale are bounded/fail-soft. Catalog metadata network maintenance remains manual-only.

## Local files and secrets

Local-only/ignored state includes:

```text
config/settings.local.json
data/runtime/preferences.json
runtime observations/cycles/cache/state/errors
@Resources/Generated/
```

API keys are never committed or packaged.

## Installation

Expected repository source:

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

A whitelist-based `.rmskin` builder exists for sharing the skin without local credentials/history/preferences.

## Current focused validation

For the 0.4.0 candidate:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-Filters.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-FilterPreferenceTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-TravelContext.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-TravelContextTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-VisibleItems.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-RainmeterSkin.ps1
```

Then run one normal update and refresh Rainmeter. Static tests do not replace actual interaction/layout validation.

## Future sequence

After 0.4.0 acceptance:

1. generalize card rendering beyond the four proof markets;
2. expose the full relevant item/category catalog through filters;
3. add locally ticking outbound arrival countdown;
4. generalize per-item timing where evidence is sufficient;
5. build the full-country opportunity view;
6. add `Optimal` later as a bounded route scheduler, not a simple profit sort.

## Documentation

Read in order:

1. `AGENTS.md`
2. `docs/README.md`
3. `docs/NEXT_CODEX_RUN.md`
4. `docs/ARCHITECTURE.md`
5. `docs/IMPLEMENTATION_STATUS.md`
6. `Readme.md`
