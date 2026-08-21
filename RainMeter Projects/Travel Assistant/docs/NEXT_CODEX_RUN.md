# Next Codex Run: Category-Aware Carrying Capacity

**Status: ACTIVE**

## Expansion rule

```text
collect broadly
show narrowly
optimize only after evidence/economics are ready
```

## Accepted baseline

Target Windows has accepted the current catalog/market-validity layer:

```text
provider:                     prometheus
countriesSeen:                11
provider country-item rows:   232
legacy provider rows:           5
active candidate markets:     227
observed item IDs:             202
metadata rows:                 202
categoriesResolved:            202
unresolvedItems:                 0
nameConflicts:                   0
```

The broad resale queue also completed a clean live request:

```text
activeMarkets: 227
activeItems:   197
pricedItems:     2
freshItems:      2
staleItems:    195
successCount:    1
failureCount:    0
status:          OK
lastItemId:       4
```

The successful row used the established `torn_itemmarket` cache schema. The visible UI remains UK/Japan Xanax only.

## Current production runtime

```text
UpdateTracker
ShadowCollector (fail-soft)
LocalCatalog (fail-soft / local-only)
FinalizeState
visible heartbeat
ResaleQueue (fail-soft, max one request/run)
```

Catalog metadata network maintenance remains outside the heartbeat.

## Implemented category-aware capacity

The accepted current-capacity model remains the authority for **general/Xanax** carrying capacity:

```text
base travel capacity
+ current suitcase/general active bonus
```

For the currently synced example:

```text
Airstrip general/Xanax capacity = 18
Standard general/Xanax capacity = 13
```

Category-specific company perks are now modeled separately from that general number.

### Important non-double-counting rule

`currentCapacity` / `currentCapacityBonus` represent the general/Xanax capacity and intentionally excluded Flower/Toy category-specific capacity from the original `/user/perks` parser.

Therefore after a current-capacity sync:

- general company/faction capacity is **not inferred again**;
- a matching item-specific company bonus **is** allowed on top, because it was never included in the Xanax/general number.

Current known category effects:

```text
Flower Shop 7★ -> +5 only for Flower items
Toy Shop    7★ -> +5 only for Plushie items
```

Examples with a general Airstrip capacity of 18:

```text
Xanax at Flower Shop 7★       = 18
Cherry Blossom at Flower 7★   = 23
Xanax at Toy Shop 7★          = 18
Nessie Plushie at Toy Shop 7★ = 23
```

Standard mode with the same active general `+3` and matching category `+5` produces 18 slots (`10 + 3 + 5`).

A positive explicit `profitability.capacityOverride` remains authoritative and exact.

## CurrentCapacity parser cross-check

`CurrentCapacity.ps1` now also parses category-specific Flower/Plushie perk strings independently from general capacity.

New production helpers include:

```text
Get-TornTravelCapacityCategoryFromPerkText
Get-TornCategoryTravelCapacityBonusFromPerkText
Get-TornCategoryTravelCapacityPerks
Get-TornEffectiveItemCapacity
```

`Get-TornEffectiveXanaxCapacity` remains a backward-compatible Drug wrapper. Category-specific perks may be recognized/exposed by the parser but never increase Xanax capacity.

An unparseable Flower-specific perk can make a direct Flower parser result unresolved without making unrelated Drug capacity unresolved.

The normal TravelProfile economics path derives the category bonus from the already-synced company type/star profile, avoiding new persisted settings fields and avoiding another runtime API dependency.

## Focused Windows acceptance

Run only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-CurrentCapacityTests.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-TravelProfileTests.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-RainmeterSkin.ps1
```

The focused capacity tests must prove:

- Xanax remains unchanged by Flower/Plushie bonuses;
- category perk text parses separately from general travel capacity;
- Flower +5 applies only to Flower;
- Plushie +5 applies only to Plushie;
- current general `+3` plus category `+5` gives Airstrip 23 / Standard 18;
- current general company/faction capacity remains non-double-counted;
- a positive explicit capacity override remains authoritative.

No full suite is required unless these changes expose an unrelated regression.

## After acceptance

Promote **Nessie Plushie** and **Cherry Blossom** as the first visible multi-item proof while keeping the current Xanax cards/functionality intact.

That UI/model phase should consume:

- active-market validity;
- local canonical category/name metadata;
- broad resale cache;
- category-aware carrying capacity;
- existing country/item history isolation.

Then proceed to country/category filters, travel-state destination filtering/arrival countdown, full-country economics and finally `Optimal` scheduling after sufficient evidence exists.
