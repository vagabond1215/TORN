# Next Codex Run: Full Foreign-Market Shadow Collection

**Status: ACTIVE**

This is the authoritative execution handoff for `RainMeter Projects/Travel Assistant/`.

## Goal

Start collecting useful history for the entire Torn foreign market **without changing the validated UK/Japan Xanax presentation or recommendation behavior**.

The expansion rule is now:

```text
collect broadly
show narrowly
optimize only after evidence/economics are ready
```

## Implemented in repository

### All-country collection configuration

`config/countries.json` now distinguishes visible/primary countries from collection countries:

- United Kingdom and Japan remain `enabled: true` for the current UI/model path;
- all 11 Torn foreign destinations have `collect: true` and Prometheus/YATA country codes;
- the other nine destinations remain `enabled: false` for this release.

Collection country/provider codes:

```text
mexico               mex
cayman_islands       cay
canada                can
hawaii                haw
united_kingdom        uni
argentina             arg
switzerland           swi
japan                 jap
china                 chi
united_arab_emirates  uae
south_africa          sou
```

### Initial item metadata seeds

`config/items.json` now explicitly separates collection/visibility/optimizer intent.

Current primary item:

```text
206 Xanax | Drug | visible | optimizer-eligible
```

First hidden multi-item proof metadata:

```text
266 Nessie Plushie  | Plushie | United Kingdom | hidden | not optimizer-eligible yet
277 Cherry Blossom  | Flower  | Japan          | hidden | not optimizer-eligible yet
```

The live shadow collector does **not** depend on this three-item list to decide what to collect. It normalizes every valid item row returned by the foreign-stock provider.

### Fail-soft shadow collector

`@Resources/Scripts/ShadowCollector.ps1`:

- defaults to a 120-second background polling interval;
- queries Prometheus with YATA fallback using the same provider contract as the existing updater;
- iterates all configured `collect: true` countries;
- normalizes every valid provider item row to the existing observation schema;
- tracks every observed `country:itemId` market in ignored `engine-state.json -> observedMarkets`;
- writes changed observations to the existing bounded `observations.jsonl`;
- detects and writes completed cycles using the existing cycle schema;
- skips current primary markets (enabled country + enabled item) so UK/Japan Xanax is not double-written by the shadow pass;
- stores collection health counters in `engine-state.json -> shadowCollection`;
- records errors in ignored `data/runtime/shadow-collection-error.txt`;
- returns fail-soft so background expansion cannot block current visible functionality.

`RunUpdate.ps1` now executes:

```text
existing UpdateTracker
        ↓
fail-soft ShadowCollector
        ↓
existing FinalizeState
        ↓
heartbeat
```

The separate shadow fetch is an intentional migration bridge. A future refactor should share one live provider payload between visible and shadow collection after behavior is proven equivalent.

## New focused validation

```powershell
.\tests\Validate-ShadowCollection.ps1
.\tests\Run-ShadowCollectionTests.ps1
```

The tests verify:

- exactly 11 collection countries/provider codes;
- only UK/Japan remain visible/enabled countries;
- Xanax remains the only enabled primary item;
- Nessie/Cherry metadata and hidden/optimizer flags;
- valid multi-item provider-row normalization;
- malformed provider rows are ignored;
- UK/Japan Xanax is classified as protected primary market;
- Nessie and non-primary-country Xanax remain shadow markets;
- cycle completion retains country/item identity and timing isolation.

Both tests are included in `tests/Run-All.ps1`.

## Required target-Windows validation

Do **not** broaden the UI or enable optimizer economics until this passes.

From the Travel Assistant directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-ShadowCollection.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-ShadowCollectionTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-RainmeterSkin.ps1
```

Then allow at least one normal Rainmeter update and one shadow interval (roughly two minutes).

Inspect only non-secret runtime state:

```powershell
$e = Get-Content .\data\runtime\engine-state.json -Raw | ConvertFrom-Json
$e.shadowCollection | Format-List
@($e.observedMarkets.PSObject.Properties).Count
```

Expected:

- `lastPollAt` is current/recent;
- `lastProvider` is `prometheus` normally, or `yata` if fallback is required;
- `countriesSeen` should be up to 11 when the provider payload contains all configured destinations;
- `marketsSeen` should be substantially greater than the current two Xanax markets;
- `lastError` should be empty on a successful pass;
- observed-market count should grow to the provider's current foreign-market set;
- current UK/Japan Xanax cards, graphs, profitability colors, stock headers and recommendations remain healthy.

Optional proof that the first hidden items are already being seen when present in the provider payload:

```powershell
$e.observedMarkets.PSObject.Properties |
  Where-Object { $_.Name -in @('united_kingdom:266','japan:277') } |
  Select-Object Name, Value
```

Do not paste API keys or full local settings.

## What is deliberately not implemented yet

- canonical name/category enrichment for every observed item ID;
- resale-price queue for the whole observed catalog;
- category-specific Flower/Plushie capacity economics for multi-item recommendations;
- Cherry/Nessie visible cards;
- country/category UI filters;
- Torn `/user/travel` destination/arrival-aware presentation;
- full country travel economics;
- `Optimal` route scheduling.

Those depend on proving the collection foundation first.

## Next implementation after shadow validation

1. Add canonical item metadata/category enrichment for observed item IDs rather than maintaining a static foreign-shop whitelist.
2. Add a bounded/staggered resale-price cache queue per distinct item ID.
3. Generalize capacity into general + category-specific bonuses.
4. Promote Nessie and Cherry as the first hidden-to-visible multi-item UI proof.
5. Add country/category filters.
6. Add travel-state filtering/arrival countdown.
7. Populate full opportunity economics before enabling `Optimal` mode.

## Existing validation debt retained

The earlier Settings/current-capacity interaction checks (populate-only Sync, 18/13 mode flip, Business gating, healthy next poll) remain useful Windows acceptance evidence. They are not erased by this expansion, but they are no longer the sole active implementation scope.

## Completion criteria for this run

Mark this shadow-collection run **COMPLETED** only after:

- both new focused tests pass on Windows;
- normal Rainmeter Xanax behavior remains unchanged;
- at least one successful shadow poll records multiple hidden markets without blocking the heartbeat;
- runtime storage/error behavior remains bounded/ignored.
