# Travel Assistant

Rainmeter-based Torn foreign-market travel decision assistant.

The currently validated visible UI remains focused on **Xanax in the United Kingdom and Japan**, while the data layer now background-collects the full provider-observed foreign market and is beginning canonical item/category enrichment before broader UI or route optimization.

## Current direction

Travel Assistant separates:

```text
COLLECTED opportunities
        !=
VISIBLE opportunities
        !=
OPTIMIZER candidates
```

The application can learn foreign-market stock cycles broadly without forcing unfinished categories/economics into the visible UI or future `Optimal` mode.

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

## Full-market shadow collection

The expansion background-collects all 11 Torn foreign destinations:

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

Every valid item row returned by Prometheus/YATA is normalized to the existing observation schema and can accumulate restock/sellout history by `country + itemId`.

The shadow pass runs no more frequently than every 120 seconds and is isolated from the current UK/Japan Xanax primary markets. Raw history is written only when stock or foreign price changes; provider timestamp changes still update freshness metadata without creating another raw sample.

Target-Windows acceptance on 2026-08-21 confirmed:

```text
Prometheus
11 countries
232 observed country-item markets
51 changed observations on the forced acceptance pass
no shadow error
```

The background collector tracks observed markets in ignored `data/runtime/engine-state.json` and uses the same bounded raw/cycle history stores as the existing model.

## Canonical item metadata

`ItemMetadata.ps1` enriches the **distinct observed item IDs** using Torn API v2 specific-item metadata.

It records canonical:

```text
name
type / category
weapon category detail where available
tradability
Torn market-price reference
shop locations/prices
```

Metadata defaults to a six-hour cadence and requests at most 150 item IDs per batch. It uses bounded `curl.exe --config -`, passing the API key through stdin Authorization configuration rather than the URL or process command line.

Weapon items retain Torn's detailed `Primary`, `Secondary`, `Melee`, or `Temporary` category when available. Missing details remain unresolved `Weapon` rather than being guessed.

Torn `market_price` is **informational metadata only** at this stage. It does not replace the current Item Market profitability gate.

Metadata failures are fail-soft and cannot block the established Xanax finalizer/heartbeat.

## First multi-item seeds

Committed item configuration includes:

```text
206 Xanax           | Drug     | current primary/visible
266 Nessie Plushie  | Plushie  | United Kingdom hidden seed
277 Cherry Blossom  | Flower   | Japan hidden seed
```

Nessie and Cherry remain hidden and not optimizer-eligible during the data-layer rollout.

The collector does **not** use this short list as a whitelist. Unknown provider-observed IDs are collected first and enriched from Torn metadata later.

## Live sources

Preferred foreign-stock source:

```text
Prometheus
    ↓ unavailable
YATA
```

Foreign stock is crowd-sourced. Static Wiki shop tables are useful documentation, but the live provider payload determines which market rows are actually being observed.

A Torn API key enables metadata/resale/economics features and remains local/ignored. On the validated Windows machine, Torn API calls that hang under native Windows PowerShell use bounded `curl.exe` transport.

Never commit a limited/full-authority key.

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

After canonical metadata is accepted on Windows:

1. add a bounded/staggered Torn Item Market resale-price queue;
2. generalize category-specific capacity/economics;
3. expose Nessie + Cherry as the first multi-item UI proof;
4. add country/category filters;
5. add Torn travel-state destination filtering and arrival countdown;
6. populate full-country economics;
7. build `Optimal` as a bounded route scheduler comparing short, long and mixed-country trip sequences.

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

## Validation

Focused current expansion checks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-ShadowCollection.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-ShadowCollectionTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-ItemMetadata.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-ItemMetadataTests.ps1
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
