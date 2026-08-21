# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-21

**Active run:** canonical item metadata enrichment for the full provider-observed foreign catalog. See `docs/NEXT_CODEX_RUN.md`.

## Stable visible baseline

The Rainmeter presentation remains UK/Japan Xanax with the validated operational path:

- automatic one-minute polling and heartbeat;
- Prometheus preferred live stock with YATA fallback;
- observed restock/sellout history;
- Torn Item Market resale through bounded `curl.exe`;
- current-capacity economics using `/user/perks` authority;
- compact cards with profit-colored prices, conditional restock indicator, and 8-hour graphs.

Data-layer expansion must not change this visible behavior until a later explicit UI phase.

## Full-market shadow collection — ACCEPTED

All 11 Torn foreign destinations now collect in the background while only UK/Japan remain visible/model-enabled.

Focused Windows tests reported PASS:

```text
Validate-ShadowCollection.ps1
Run-ShadowCollectionTests.ps1
Validate-RainmeterSkin.ps1
```

Live forced shadow pass from the correct project directory reported:

```text
lastProvider:         prometheus
countriesSeen:        11
marketsSeen:          232
observedMarkets:      232
observationsWritten:  51
cyclesCompleted:      0
lastErrorAt:          0
lastError:            empty
```

This is accepted as the operational baseline for broad background collection. The initial `cyclesCompleted=0` is expected on a first/early pass; cycles require observed restock/sellout transitions over time.

Shadow collection remains fail-soft, skips UK/Japan Xanax primary writes, and records raw history only when stock or foreign price changes.

## Canonical item metadata — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

New `@Resources/Scripts/ItemMetadata.ps1` enriches the distinct item IDs discovered by shadow collection using Torn API v2 specific-item metadata.

Production contract:

```text
GET /v2/torn/{ids}/items?sort=ASC
```

Behavior:

- public-key request;
- default refresh every 6 hours;
- maximum 150 item IDs per request batch;
- bounded retries: every attempt respects the six-hour cadence unless manually forced;
- secure `curl.exe --config -` transport so the key is not placed in the process command line or URL;
- canonical name/type/category/tradability/market-price/shop metadata stored in ignored `engine-state.json`;
- weapon rows use Torn `details.category` to retain Primary/Secondary/Melee/Temporary identity when available;
- unresolved weapon detail remains `Weapon` with `categoryResolved=false` rather than guessing;
- Torn `market_price` is metadata only and does not replace existing Item Market profitability logic;
- failures are fail-soft and do not block finalization or heartbeat.

`RunUpdate.ps1` now serializes:

```text
UpdateTracker
ShadowCollector (fail-soft)
ItemMetadata (fail-soft / low-frequency)
FinalizeState
heartbeat
```

New focused tests:

```text
tests/Validate-ItemMetadata.ps1
tests/Run-ItemMetadataTests.ps1
```

Both are included in `tests/Run-All.ps1`.

## Remaining acceptance for metadata phase

Run the two focused metadata tests on Windows, then force one metadata refresh and inspect:

```text
engine-state.json -> metadataCollection
engine-state.json -> itemMetadata
```

Success requires:

- no metadata error;
- `source=torn_items`;
- `distinctObservedItems > 0`;
- `itemsRequested` equals the number of distinct observed item IDs;
- `itemsResolved` is equal or very close to requested, with any discrepancy investigated rather than silently guessed;
- populated canonical category list;
- correct sample metadata for Xanax, Nessie Plushie and Cherry Blossom when those IDs are observed;
- current UK/Japan Xanax Rainmeter behavior unchanged.

## Next planned phases

After metadata acceptance:

1. bounded/staggered Item Market resale-price queue for the observed catalog;
2. category-aware effective carrying capacity (general + Flower/Plushie-specific effects);
3. promote Nessie Plushie and Cherry Blossom as the first visible multi-item proof;
4. country/category filters;
5. Torn travel-state destination filtering and arrival countdown;
6. full-country economics population;
7. `Optimal` route scheduling only after sufficient availability/economic evidence exists.

## Existing validation debt retained

Earlier Settings/current-capacity interaction acceptance (populate-only sync, Airstrip 18 / Standard 13 mode flip, Business gating, healthy following poll) remains useful Windows evidence and is not erased by this expansion.
