# Travel Assistant

Rainmeter-based Torn foreign-market travel decision assistant.

The currently validated visible UI remains focused on **Xanax in the United Kingdom and Japan**, while the data layer now observes the full provider-reported foreign market, filters verified legacy shop rows, maintains a complete local category catalog for the current dataset, and is beginning staggered resale-price population before broader UI or route optimization.

## Current direction

Travel Assistant separates:

```text
COLLECTED provider rows
        !=
ACTIVE market candidates
        !=
VISIBLE opportunities
        !=
OPTIMIZER candidates
```

The application can learn foreign-market stock cycles broadly without forcing unfinished economics into the visible UI or future `Optimal` mode.

## Current visible UI

The skin currently shows UK and Japan Xanax cards with:

- country flag;
- Xanax foreign price in the item header, colored by current trip profitability;
- current stock or an out-of-stock warning;
- out-of-stock format `Out of Stock for h:mm since HH:mm`, with only `Out of Stock` colored red;
- plane icon + current route duration;
- delivery-truck restock timing only when the destination is out of stock and the predicted restock ETA is longer than the flight time;
- hidden timing/history detail in tooltips;
- 8-hour stock graphs with 60-minute vertical divisions;
- top-right Settings;
- clickable `Travel` header opening Torn travel.

Current visible behavior remains deliberately conservative: stale, unsupported, unresolved or unprofitable opportunities do not receive departure recommendations.

## Full-market background observation

The expansion observes all 11 Torn foreign destinations:

```text
Mexico
Cayman Islands
Canada
Hawaii
United Kingdom
Argentina
Switzerland
Japan
China
United Arab Emirates
South Africa
```

Every valid item row returned by Prometheus/YATA is normalized by `country + itemId`. Provider presence is retained as provenance, but it is not blindly treated as proof that a shop relationship is still current.

Latest target-Windows baseline:

```text
Prometheus
11 countries
232 provider country-item rows
232 / 232 rows with provider names
202 distinct item IDs
5 verified legacy provider rows
227 active country-item markets
no shadow error
```

Verified legacy rows remain visible in ignored runtime metadata but are excluded before new learning/history/resale work:

```text
mexico:21
mexico:232
mexico:327
united_arab_emirates:383
united_arab_emirates:440
```

The shadow pass runs no more frequently than every 120 seconds. Raw history is written only when stock or foreign price changes; provider timestamp changes still update freshness metadata without creating another raw sample.

## Complete local item/category catalog

Normal Rainmeter operation does **not** depend on Torn catalog metadata requests. The target Windows machine repeatedly timed out on attempted bulk/specific Torn catalog transports, so item/category metadata is packaged locally instead.

Committed references:

```text
config/foreign-item-categories.json
config/foreign-market-overrides.json
```

The current live catalog is fully category-resolved locally:

```text
202 observed item IDs
202 metadata rows
202 categories resolved
0 unresolved
0 provider-name conflicts
```

The 197-ID foreign category snapshot is supplemented by five individually verified overrides. Two provider aliases are corrected canonically while retaining the provider name separately:

```text
Blank Tokens  -> Blank Casino Chips | Material
Platinum PDA  -> Digital Organizer  | Miscellaneous
```

`ItemMetadata.ps1` remains an explicit/manual maintenance tool only; it is not part of the Rainmeter heartbeat.

## Broad resale-price population

`ResaleQueue.ps1` gradually fills the shared Torn Item Market resale cache for active observed items.

It is intentionally bounded:

```text
maximum broad requests per update: 1
minimum attempt interval:          60 seconds
broad cache freshness target:       6 hours
failed-item backoff:                 1 hour
request timeout:                     6 seconds
```

The queue runs **after** the established visible finalizer and heartbeat. Therefore a lower-priority broad pricing miss cannot make the current UK/Japan skin look stale or broken.

Only items with at least one active market relationship are eligible. Verified `catalogActive=false` / `legacy_removed` markets do not receive broad valuation work.

The queue prioritizes never-priced eligible items, then stale cache rows. Failed items back off instead of blocking the rest of the catalog.

On the current roughly 197-active-item set, one successful request/minute can populate an initially empty broad resale cache in about 3.3 hours while the skin is loaded. This six-hour target is for broad population/reference data; current visible Xanax keeps its existing independent/fresher resale behavior.

Torn Item Market requests use bounded `curl.exe --config -` on the validated Windows host, with the API key supplied through an Authorization header on stdin rather than in the URL or process arguments.

## First multi-item seeds

Committed item configuration includes:

```text
206 Xanax           | Drug     | current primary/visible
266 Nessie Plushie  | Plushie  | United Kingdom hidden seed
277 Cherry Blossom  | Flower   | Japan hidden seed
```

Nessie and Cherry remain hidden and not optimizer-eligible during the data-layer rollout.

## Current capacity/economics

Current general carrying capacity prefers current `/user/perks` state plus selected mode base rather than requiring faction-upgrade permissions.

Base capacities:

```text
Standard: 10
Airstrip/WLT/qualified Business: 15
```

Current active general bonuses are applied without double-counting the selected travel method.

Before multi-category opportunities become recommendation/optimizer candidates, item-specific capacity must remain isolated:

- Flower Shop flower capacity applies only to Flower items;
- Toy Shop plushie capacity applies only to Plushie items;
- neither affects Xanax.

Ticket-funded Business remains economically unresolved. The known-safe free branch remains qualified free Business travel such as the modeled 10-star Lingerie Store condition.

## Learning / retention

Observed truth:

```text
0 -> positive stock = observed restock
positive stock -> 0 = observed sellout
```

Forecasts never become historical truth.

Default retained evidence:

- approximately 48 hours of high-resolution observations;
- approximately 90 days of completed cycles;
- 8 hours visible on the current graph.

The live stale threshold is a recommendation-safety guard, not a history-expiry rule.

## Future expansion sequence

After broad resale population is accepted on Windows:

1. generalize category-specific capacity/economics;
2. expose Nessie + Cherry as the first multi-item UI proof;
3. add country/category filters;
4. add Torn travel-state destination filtering and arrival countdown;
5. populate full-country economics;
6. build `Optimal` as a bounded route scheduler comparing short, long and mixed-country trip sequences.

`Optimal` will not simply sort by profit/item or profit/trip. It must eventually consider travel time, return time, capacity, stock survival, restock/depletion evidence, fees/costs, confidence and opportunity cost across a planning horizon.

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

Because the installed skin is a junction to the repository source, later pulls normally require only a Rainmeter refresh.

A whitelist-based `.rmskin` builder also exists for sharing the skin without sharing local API settings/history. Recipient-local `settings.local.json` is not packaged.

## Validation

Focused current expansion checks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-ResaleQueue.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-ResaleQueueTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-RainmeterSkin.ps1
```

Full deterministic suite when justified:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-All.ps1
```

Repository/static tests do not replace actual Windows/Rainmeter/provider validation.

## Documentation

Read in this order before making changes:

1. `AGENTS.md`
2. `docs/README.md`
3. `docs/NEXT_CODEX_RUN.md`
4. `docs/ARCHITECTURE.md`
5. `docs/IMPLEMENTATION_STATUS.md`
6. `Readme.md`
