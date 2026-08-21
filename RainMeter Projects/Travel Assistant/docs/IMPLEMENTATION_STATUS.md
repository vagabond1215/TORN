# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-21

**Active run:** full foreign-market shadow collection. See `docs/NEXT_CODEX_RUN.md`.

## Stable visible baseline

The current Rainmeter presentation remains UK/Japan Xanax and retains the previously validated operational path:

- Rainmeter junction install;
- automatic one-minute polling and heartbeat;
- Prometheus preferred live stock with YATA fallback;
- current foreign price/stock/source freshness;
- observed restock/sellout history;
- Torn Item Market resale via the bounded Windows `curl.exe` workaround;
- current-capacity economics using `/user/perks` authority;
- compact UK/Japan cards and 8-hour graphs.

Recent presentation work has also moved price/stock into the card header, added plane/delivery-truck vector icons, made `Out of Stock` red, formatted outage age as `Out of Stock for h:mm since HH:mm`, and made raw restock timing conditional/tooltipped.

These presentation changes are not the subject of the new shadow collector and should remain unchanged during its acceptance test.

## Full-market shadow collection implemented

### Collection countries

All 11 Torn foreign destinations are now configured with `collect: true` and Prometheus/YATA provider codes:

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

Only United Kingdom and Japan remain `enabled: true` for the current visible/model path.

### Initial item metadata

`config/items.json` now explicitly seeds:

- Xanax `[206]` — Drug — current visible/primary item;
- Nessie Plushie `[266]` — Plushie — UK hidden collection seed;
- Cherry Blossom `[277]` — Flower — Japan hidden collection seed.

The new `collect`, `visible`, `optimizerEligible` and `countries` fields begin separating background collection from later UI/optimizer eligibility.

Nessie/Cherry remain hidden and not optimizer-eligible in this rollout.

### ShadowCollector.ps1

New background collector behavior:

- default interval: 120 seconds;
- live provider order: Prometheus then YATA fallback;
- every valid provider stock row for every collection country is normalized;
- every observed `country:itemId` market is tracked in ignored runtime engine state;
- changed non-primary observations are appended to the shared bounded observation history;
- restock/sellout transitions produce completed cycles with existing schemas;
- currently visible primary markets are skipped, protecting UK/Japan Xanax from duplicate shadow writes;
- errors are fail-soft and written to ignored runtime state/error text;
- unexpected shadow failure does not block the established finalizer/heartbeat.

`RunUpdate.ps1` now serializes:

```text
UpdateTracker
ShadowCollector (fail-soft)
FinalizeState
heartbeat
```

The extra shadow provider request is an intentional migration bridge. The desired later architecture is one shared foreign-stock fetch fanning out to all markets after primary behavior equivalence is proven.

## New tests

Added:

```text
tests/Validate-ShadowCollection.ps1
tests/Run-ShadowCollectionTests.ps1
```

They are now included in `tests/Run-All.ps1`.

Coverage includes:

- 11-country provider-code contract;
- shadow-only vs visible-country separation;
- Xanax-only primary item guarantee during this rollout;
- Nessie/Cherry item metadata flags;
- multi-row provider normalization;
- malformed-row rejection;
- primary-market skip classification;
- country/item identity retention through observed restock/sellout cycles.

## Validation state

Connector/GitHub implementation is complete for the initial shadow layer, but Windows execution has **not yet been reported for these new tests or for the live shadow pass**.

Required focused Windows checks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-ShadowCollection.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Run-ShadowCollectionTests.ps1
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\tests\Validate-RainmeterSkin.ps1
```

Then allow at least two minutes of normal Rainmeter operation and inspect:

```powershell
$e = Get-Content .\data\runtime\engine-state.json -Raw | ConvertFrom-Json
$e.shadowCollection | Format-List
@($e.observedMarkets.PSObject.Properties).Count
```

Success requires a recent successful shadow poll, multiple hidden observed markets, no shadow error, and unchanged healthy UK/Japan Xanax behavior.

## Not implemented yet

- canonical metadata/category enrichment for every provider-observed item ID;
- broad resale-price refresh queue;
- category-specific Flower/Plushie capacity economics for general multi-item recommendations;
- visible Nessie/Cherry cards;
- country/category filters;
- Torn `/user/travel` destination/arrival-aware display;
- economics for all collection-only countries;
- `Optimal` route scheduling.

## Existing validation debt retained

The earlier Settings/current-capacity interaction acceptance (populate-only sync, Airstrip 18 / Standard 13 mode flip, Business gating and healthy following poll) remains useful Windows evidence. It was not invalidated or falsely marked complete by the shadow-collection expansion.
