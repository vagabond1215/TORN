# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-21

**Active run:** category-aware carrying capacity. See `docs/NEXT_CODEX_RUN.md`.

## Stable visible baseline

The Rainmeter presentation remains UK/Japan Xanax with the established operational path:

- automatic one-minute polling and heartbeat;
- Prometheus preferred live stock with YATA fallback;
- observed restock/sellout history;
- current visible Xanax Torn Item Market resale through bounded `curl.exe`;
- current-capacity economics using `/user/perks` authority;
- compact cards with profit-colored prices, conditional restock indicator, and 8-hour graphs.

Data-layer expansion must not change this visible behavior until a later explicit UI phase.

## Full-market shadow collection / catalog — ACCEPTED

Latest target-Windows baseline:

```text
provider:                      prometheus
countriesSeen:                 11
provider marketsSeen:          232
legacyMarketsSeen:               5
active candidate markets:      227
observed item IDs:              202
metadata rows:                  202
categoriesResolved:             202
unresolvedItems:                  0
nameConflicts:                    0
```

The five verified legacy provider rows remain observable for provenance but are skipped before new history/cycle/resale work.

Committed catalog data:

```text
config/foreign-item-categories.json
config/foreign-market-overrides.json
```

The current canonical corrections include:

```text
327 Blank Casino Chips | provider alias Blank Tokens | Material
383 Digital Organizer  | provider alias Platinum PDA | Miscellaneous
```

## Torn catalog transport — REJECTED FOR HEARTBEAT USE

The target Windows host timed out before returning metadata on all tested Torn catalog strategies:

```text
v2 /torn/{ids}/items | 150 IDs | 20s | 0 resolved
v2 /torn/{ids}/items |  40 IDs | 30s | 0 resolved
classic torn/items    | bulk   | 12s | 0 resolved
```

`ItemMetadata.ps1` remains manual/maintenance-only. Runtime catalog knowledge comes from committed local data plus provider names/verified overrides.

## Broad resale queue — LIVE REQUEST ACCEPTED

The current broad queue is implemented as a post-heartbeat, fail-soft, one-request-at-a-time population path.

Target Windows live result:

```text
lastAttemptAt : 1787351181
lastSuccessAt : 1787351181
lastItemId    : 4
activeMarkets : 227
activeItems   : 197
pricedItems   : 2
freshItems    : 2
staleItems    : 195
successCount  : 1
failureCount  : 0
status        : OK
lastError     : empty
```

The new cache row was structurally valid:

```text
price     : 500
lowest    : 500
average   : 234
source    : torn_itemmarket
```

This is live transport acceptance. Do not claim the focused resale PowerShell tests passed unless their output is separately reported.

Queue defaults remain:

```text
minimum attempt interval: 60s
broad cache freshness:     6h
failed-item backoff:        1h
request timeout:            6s
broad requests/run path:    1
```

The existing visible Xanax pricing path remains independently fresher.

## Category-aware carrying capacity — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

`CurrentCapacity.ps1` now separates category-specific travel-capacity perk parsing from general/Xanax capacity.

New helpers:

```text
Get-TornTravelCapacityCategoryFromPerkText
Get-TornCategoryTravelCapacityBonusFromPerkText
Get-TornCategoryTravelCapacityPerks
Get-TornEffectiveItemCapacity
```

`Get-TornEffectiveXanaxCapacity` remains a backward-compatible Drug wrapper and cannot receive Flower/Plushie capacity.

The main TravelProfile economics path uses the already-synced company type/star profile for the two currently known category-specific company effects:

```text
Flower Shop 7★ -> +5 Flower slots only
Toy Shop    7★ -> +5 Plushie slots only
```

This is intentionally applied even when current general capacity is known, because the accepted general/Xanax capacity parser excluded those category-specific bonuses by design. General company/faction capacity remains suppressed after a current-capacity sync, preventing double counting.

With current general Airstrip capacity `18` (`15 + 3`):

```text
Xanax                       18
Flower at Flower Shop 7★    23
Plushie at Toy Shop 7★      23
```

With Standard mode and the same general `+3`:

```text
matching Flower/Plushie     18  (10 + 3 + 5)
```

A positive explicit `profitability.capacityOverride` remains exact/authoritative.

Updated focused tests:

```text
tests/Run-CurrentCapacityTests.ps1
tests/Run-TravelProfileTests.ps1
```

Windows acceptance is still required before promoting Nessie/Cherry into visible economics.

## Focused acceptance now required

Run:

```text
Run-CurrentCapacityTests.ps1
Run-TravelProfileTests.ps1
Validate-RainmeterSkin.ps1
```

Do not run the broad suite unless a focused failure indicates a wider regression.

## Next phase after acceptance

1. promote Nessie Plushie and Cherry Blossom as the first visible multi-item proof;
2. country/category filters;
3. Torn travel-state destination filtering and arrival countdown;
4. full-country economics population;
5. `Optimal` route scheduling after sufficient availability/economic evidence exists.

## Existing validation debt retained

Earlier Settings/current-capacity interaction acceptance remains useful Windows evidence and is not erased by this expansion.
