# Travel Assistant

Rainmeter-based Torn foreign-market travel decision assistant.

The last target-Windows-validated presentation is the established UK/Japan Xanax UI. The current committed **0.3.0 release candidate** adds Nessie Plushie under the United Kingdom and Cherry Blossom under Japan, plus a smaller parenthesized Torn Item Market reference beside each visible foreign-shop price. It is pending Windows/Rainmeter layout acceptance.

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

The application learns stock cycles broadly while exposing only deliberately promoted, economically understood rows.

## Current 0.3.0 presentation candidate

```text
United Kingdom
  Xanax
  Nessie Plushie

Japan
  Xanax
  Cherry Blossom
```

Each visible item uses:

```text
foreign shop price (Torn Item Market reference)
```

The foreign price remains the primary value and keeps profitability coloring. The value in parentheses is smaller/muted. If a broad resale reference has not been populated yet, the parenthesized value shows `-` until the bounded queue reaches it.

Nessie and Cherry remain presentation-only:

```text
visible=true
enabled=false
optimizerEligible=false
```

The existing plane/restock/decision line and 8-hour graphs are still **Xanax-specific** in this first multi-item release. Secondary rows show live provider stock, foreign price, current resale reference and capacity/economics context but do not claim independent trained departure timing yet.

Existing UI invariants are retained:

- UK above Japan;
- local vector flags;
- `Out of Stock for h:mm since HH:mm`, with only `Out of Stock` red;
- conditional delivery-truck restock timing for Xanax;
- 8-hour Xanax graphs with 60-minute grid lines;
- clickable `Travel` header;
- Settings top-right.

## Full-market background observation

All 11 Torn foreign destinations are observed. Current target-Windows baseline:

```text
Prometheus
11 countries
232 provider country-item rows
232 / 232 rows with provider names
202 distinct item IDs
5 verified legacy provider rows
227 active country-item markets
```

Provider presence is provenance, not unconditional proof of current shop membership. Verified inactive rows remain in ignored runtime metadata but are excluded from new learning/history/resale/display work.

## Local item/category catalog

Normal Rainmeter operation does **not** depend on Torn catalog metadata requests. Current catalog knowledge is packaged locally:

```text
202 observed item IDs
202 metadata rows
202 categories resolved
0 unresolved
0 provider-name conflicts
```

Committed references:

```text
config/foreign-item-categories.json
config/foreign-market-overrides.json
```

`ItemMetadata.ps1` remains manual/maintenance-only after repeated target-host Torn catalog timeouts.

## Broad resale-price population

`ResaleQueue.ps1` fills the shared Torn Item Market cache gradually:

```text
maximum requests per normal update: 1
minimum attempt interval:           60 seconds
broad freshness target:              6 hours
failed-item backoff:                  1 hour
request timeout:                      6 seconds
```

A live target-Windows request has succeeded with `status=OK` and the expected `torn_itemmarket` cache schema.

The queue runs after the visible heartbeat. Configured `visible=true` items are now prioritized among otherwise eligible stale/unpriced items, so Nessie/Cherry are filled ahead of hidden catalog rows without raising request frequency. Xanax retains its existing independent/fresher resale path.

## Category-aware carrying capacity

Target-Windows focused tests accepted:

```text
Airstrip general/Xanax = 18
Standard general/Xanax = 13
Flower Shop 7★ -> +5 Flower only
Toy Shop    7★ -> +5 Plushie only
```

So with the current general `+3`:

```text
qualifying Airstrip Flower/Plushie = 23
qualifying Standard Flower/Plushie = 18
Xanax remains unchanged            = 18 / 13
```

A positive `profitability.capacityOverride` remains authoritative.

## Runtime layering

Current production sequence:

```text
UpdateTracker
ShadowCollector
LocalCatalog
FinalizeState
VisibleItems        # local-only presentation enrichment
visible heartbeat
ResaleQueue         # max one bounded Torn market request
```

`VisibleItems.ps1` makes no network requests; it consumes already-collected stock, local metadata, resale cache and travel-profile economics.

## Learning / retention

Observed truth:

```text
0 -> positive stock = observed restock
positive stock -> 0 = observed sellout
```

Forecasts never become historical truth.

Default retained evidence:

- ~48 hours high-resolution observations;
- ~90 days completed cycles;
- 8 hours on the current Xanax graph.

The live stale threshold is a recommendation guard, not history expiry.

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

Because the installed skin is a junction to repository source, later pulls normally require only a Rainmeter refresh.

A whitelist-based `.rmskin` builder exists for sharing the skin without local API settings/history.

## Focused current validation

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-VisibleItems.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-VisibleItemsTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-ResaleQueue.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-ResaleQueueTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-RainmeterSkin.ps1
```

Static tests do not replace actual Rainmeter layout validation. See `docs/NEXT_CODEX_RUN.md` for the current acceptance procedure.

## Future sequence

After 0.3.0 UI acceptance:

1. country/category filters;
2. travel-state destination filtering and arrival countdown;
3. broader per-item timing/economics presentation as evidence matures;
4. full-country opportunity matrix;
5. `Optimal` as a bounded route scheduler rather than a simple profit sort.

## Documentation

Read in order:

1. `AGENTS.md`
2. `docs/README.md`
3. `docs/NEXT_CODEX_RUN.md`
4. `docs/ARCHITECTURE.md`
5. `docs/IMPLEMENTATION_STATUS.md`
6. `Readme.md`
