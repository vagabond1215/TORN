# Travel Assistant

Rainmeter-based Torn foreign-market travel decision assistant.

The currently validated visible UI remains focused on **Xanax in the United Kingdom and Japan**, while the project has begun a controlled expansion to background-collect the full foreign market before exposing more items, filters, travel-context behavior, or route optimization.

## Current direction

Travel Assistant now separates:

```text
COLLECTED opportunities
        !=
VISIBLE opportunities
        !=
OPTIMIZER candidates
```

That means the application can begin learning every foreign-market stock cycle now without forcing unfinished categories/economics into the visible UI or future `Optimal` mode.

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

The initial expansion adds a fail-soft background collector for all 11 Torn foreign destinations:

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

Every valid item row returned by Prometheus/YATA is normalized to the existing observation schema and can begin accumulating restock/sellout history by `country + itemId`.

The shadow pass currently runs no more frequently than every 120 seconds and is intentionally isolated from the current UK/Japan Xanax primary markets. If shadow collection fails, it must not block the established updater/finalizer/heartbeat.

The background collector tracks observed markets in ignored `data/runtime/engine-state.json` and uses the same bounded raw/cycle history stores as the existing model.

## First multi-item metadata seeds

The committed item metadata now includes:

```text
206 Xanax          | Drug     | current primary/visible
266 Nessie Plushie | Plushie  | United Kingdom shadow seed
277 Cherry Blossom | Flower   | Japan shadow seed
```

Nessie and Cherry remain hidden and not optimizer-eligible during the collection-foundation rollout.

The shadow collector does **not** use this short list as a whitelist. Unknown provider-observed item IDs are still collected so history is not lost while canonical metadata catches up.

## Live sources

Preferred foreign-stock source:

```text
Prometheus
    ↓ unavailable
YATA
```

Foreign stock is crowd-sourced. Static Wiki shop tables are useful documentation, but the live provider payload determines which market rows are actually being observed.

A Torn API key enables resale/economics features and remains local/ignored. On the validated Windows machine, Torn API calls that hang under native Windows PowerShell use the existing bounded `curl.exe` workaround; foreign-stock providers continue using normal bounded requests.

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

After the shadow collector is validated on Windows:

1. enrich every observed item ID with canonical name/category metadata;
2. add a bounded/staggered Torn resale-price queue;
3. generalize category-specific capacity/economics;
4. expose Nessie + Cherry as the first multi-item UI proof;
5. add country/category filters;
6. add Torn travel-state destination filtering and arrival countdown;
7. populate full-country economics;
8. build `Optimal` as a bounded route scheduler comparing short, long and mixed-country trip sequences.

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

Focused shadow-collection checks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-ShadowCollection.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-ShadowCollectionTests.ps1
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
