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

All 11 Torn foreign destinations collect in the background while only UK/Japan remain visible/model-enabled.

Focused Windows tests reported PASS:

```text
Validate-ShadowCollection.ps1
Run-ShadowCollectionTests.ps1
Validate-RainmeterSkin.ps1
```

Live forced shadow pass:

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

This is the accepted operational baseline for broad background collection.

## Canonical item metadata — ACTIVE

The first live catalog contained 202 distinct item IDs across the 232 country-item markets.

### v2 multi-ID approach rejected on target Windows host

The original v2 metadata strategy passed its static/unit tests but failed twice in real transport:

```text
150 IDs / 20s -> 0 resolved -> timeout
40 IDs / 30s  -> 0 resolved -> timeout
```

The second failure occurred on the first 40-ID batch, so the issue is not just an oversized 150-ID response. Do not continue increasing timeout/batch size for this path.

### Current bulk metadata approach

`@Resources/Scripts/ItemMetadata.ps1` now uses the classic Torn bulk items selection:

```text
GET https://api.torn.com/torn/?selections=items
Authorization: ApiKey <local key>
```

The response is filtered locally to observed item IDs.

Behavior:

- one metadata request per refresh attempt;
- 6-hour default refresh cadence;
- 12-second default timeout;
- custom Travel Assistant User-Agent;
- key supplied through stdin Authorization header, never URL/process command line;
- canonical item `type` becomes the category (Drug, Flower, Plushie, Primary, Secondary, Melee, Temporary, Defensive, etc.);
- weapon subtype is retained separately as `weaponType`;
- unknown/missing type remains unresolved rather than guessed;
- market value is metadata/reference only and does not replace Item Market profitability logic;
- failures remain fail-soft and must not block the established updater/finalizer/heartbeat.

Runtime metadata fields:

```text
itemId
name
type
weaponType
category
categoryResolved
tradabilityKnown
isTradable
marketPrice
fetchedAt
source=torn_items_bulk
```

`RunUpdate.ps1` still serializes:

```text
UpdateTracker
ShadowCollector (fail-soft)
ItemMetadata (fail-soft / low-frequency)
FinalizeState
heartbeat
```

## Remaining acceptance for metadata phase

Run revised bulk metadata tests on Windows, then force one metadata refresh and inspect:

```text
engine-state.json -> metadataCollection
engine-state.json -> itemMetadata
```

Success requires:

- `source=torn_items_bulk`;
- recent `lastRefreshAt`;
- no metadata error;
- `itemsRequested` equals the distinct observed item count;
- `itemsResolved` equals or is very close to requested;
- populated canonical category list;
- correct sample metadata for Xanax, Nessie Plushie and Cherry Blossom when observed;
- current UK/Japan Xanax Rainmeter behavior unchanged.

## Distribution work also implemented

A whitelist-based `Build-Rmskin.ps1` and distribution validation now exist for future sharing. The package staging explicitly excludes local API settings, runtime history/state, generated output and credentials. Recipient-local settings are intended to survive package upgrades via Rainmeter skin merge semantics. This distribution path still requires Windows package-builder validation before a `.rmskin` should be published.

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

Earlier Settings/current-capacity interaction acceptance remains useful Windows evidence and is not erased by this expansion.
