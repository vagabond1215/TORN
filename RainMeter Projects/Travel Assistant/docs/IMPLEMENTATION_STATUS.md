# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-21

**Active run:** first visible multi-item release + parenthesized Torn market reference. See `docs/NEXT_CODEX_RUN.md`.

## Accepted data/economics baseline

Target Windows has accepted the broad catalog/market-validity foundation:

```text
provider:                    prometheus
countriesSeen:               11
provider country-item rows:  232
verified legacy rows:          5
active candidate markets:    227
observed item IDs:            202
metadata rows:                202
categoriesResolved:           202
unresolvedItems:                0
nameConflicts:                  0
```

The five verified legacy rows remain observable for provenance but are excluded from new history/cycle/resale/candidate work.

Torn catalog metadata network requests remain rejected for heartbeat use after all tested catalog strategies timed out on the target host. `ItemMetadata.ps1` is maintenance-only; normal catalog data is local/offline.

## Broad resale queue — LIVE ACCEPTED

Target Windows completed a successful bounded queue request:

```text
activeMarkets : 227
activeItems   : 197
pricedItems   : 2
freshItems    : 2
staleItems    : 195
successCount  : 1
failureCount  : 0
status        : OK
```

The returned row used the expected `torn_itemmarket` schema. Queue bounds remain one request per normal update, 60-second minimum cadence, 6-hour broad freshness, 1-hour failure backoff and 6-second request timeout.

The queue now additionally prioritizes configured `visible=true` items among otherwise eligible stale/unpriced candidates. This does **not** increase request frequency.

## Category-aware capacity — WINDOWS ACCEPTED

User reported all focused tests passed at `d30e1af`:

```text
Run-CurrentCapacityTests.ps1
Run-TravelProfileTests.ps1
Validate-RainmeterSkin.ps1
```

Accepted semantics:

```text
Airstrip general/Xanax capacity = 18
Standard general/Xanax capacity = 13
Flower Shop 7★ -> +5 only for Flower
Toy Shop    7★ -> +5 only for Plushie
```

Thus with current general `+3`:

```text
Airstrip Flower at qualifying Flower Shop = 23
Airstrip Plushie at qualifying Toy Shop    = 23
Standard qualifying Flower/Plushie         = 18
Xanax remains unchanged                    = 18 / 13
```

Positive explicit `profitability.capacityOverride` remains authoritative.

## First visible multi-item release — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

Skin version is now `0.3.0`.

Implemented visible rows:

```text
United Kingdom: Xanax + Nessie Plushie
Japan:          Xanax + Cherry Blossom
```

Nessie and Cherry are `visible=true` but remain `enabled=false` and `optimizerEligible=false`, so the established primary Xanax collector/model is not replaced.

New local-only presentation layer:

```text
@Resources/Scripts/VisibleItems.ps1
```

Runtime order:

```text
UpdateTracker
ShadowCollector
LocalCatalog
FinalizeState
VisibleItems
visible heartbeat
ResaleQueue
```

`VisibleItems.ps1` makes no network calls. It reads current provider-observed stock/foreign price, market validity, local metadata, shared `resaleCache`, saved company stars, and category-aware capacity/economics.

### Price convention

Every visible item now renders:

```text
foreign shop price (Torn Item Market reference)
```

The foreign price keeps profitability coloring. The parenthesized market reference is smaller and muted. Missing market references render as `-` until the bounded queue populates them. Stale broad references may remain visible as context but do not drive secondary profitability coloring.

### Deliberate first-release limits

- UK/JP 8-hour graphs remain Xanax graphs.
- Existing plane/restock/decision row remains Xanax timing/model output.
- Secondary Nessie/Cherry rows expose stock, foreign price, market reference, and economics/capacity context; they do not yet claim independent trained departure timing.
- No filters yet.
- No secondary item is optimizer eligible.

## Focused tests added/pending target Windows

```text
tests/Validate-VisibleItems.ps1
tests/Run-VisibleItemsTests.ps1
```

Existing resale/skin validators were extended for visible-item priority and the new market-value layout.

Required target-Windows acceptance is defined in `docs/NEXT_CODEX_RUN.md`. A Rainmeter screenshot is required for final layout confidence because static validation cannot prove text geometry/overlap.

## Next phases after UI acceptance

1. country/category presentation filters;
2. travel-state destination filtering and arrival countdown;
3. broader item timing/economics presentation when evidence supports it;
4. full-country opportunity matrix;
5. `Optimal` scheduling only after sufficient evidence/economics exist.
