# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-21

**Active run:** offline full item catalog enrichment. See `docs/NEXT_CODEX_RUN.md`.

## Stable visible baseline

The Rainmeter presentation remains UK/Japan Xanax with the established operational path:

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

Accepted live forced shadow pass:

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

Shadow collection remains fail-soft, skips UK/Japan Xanax primary writes, and records raw history only when stock or foreign price changes.

## Torn catalog transport — REJECTED FOR HEARTBEAT USE

The target Windows host timed out before returning metadata on all tested Torn catalog strategies:

```text
v2 /torn/{ids}/items | 150 IDs | 20s | 0 resolved
v2 /torn/{ids}/items |  40 IDs | 30s | 0 resolved
classic torn/items    | bulk   | 12s | 0 resolved
```

Do not keep increasing these timeouts inside the live skin.

`ItemMetadata.ps1` is now manual/maintenance-only. Normal runtime is:

```text
UpdateTracker
ShadowCollector
FinalizeState
heartbeat
```

so catalog network latency cannot delay the Rainmeter heartbeat.

## Committed metadata fallback — ACCEPTED

Target Windows passed:

```text
Validate-ItemMetadata.ps1
Run-ItemMetadataTests.ps1
Validate-RainmeterSkin.ps1
```

Runtime fallback metadata was confirmed:

```text
206 Xanax          Drug     config_seed
266 Nessie Plushie Plushie  config_seed
277 Cherry Blossom Flower   config_seed
```

Seed metadata intentionally keeps market value/tradability unknown unless richer metadata is available. A failed optional Torn maintenance attempt must not erase these committed rows.

## Provider-name enrichment — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

The shadow collector now retains provider-supplied item names when present:

```text
normalized observation -> itemName
observedMarkets entry  -> providerName
```

This is discovery/display metadata only. History/model identity remains `country + itemId` and the current visibility/optimizer flags are unchanged.

Focused tests were updated:

```text
tests/Validate-ShadowCollection.ps1
tests/Run-ShadowCollectionTests.ps1
```

Required Windows acceptance:

1. rerun those two focused checks plus `Validate-RainmeterSkin.ps1`;
2. force one shadow pass;
3. confirm the observed-market count remains healthy and provider names populate for a substantial portion of the catalog;
4. confirm Nessie/Cherry names when those rows are present;
5. confirm no shadow error/current UI regression.

## Active next goal: offline full catalog

The local/package-shipped catalog should ultimately cover every provider-observed item ID with:

```text
itemId
name
category
categoryResolved
provenance
```

Provider names may be used as discovery/cross-check evidence. Categories must come from verified metadata and remain unresolved when evidence is insufficient; do not guess merely to enable filters or optimization.

This catalog should be committed and included in the future `.rmskin`, so recipients do not depend on a successful Torn catalog response for basic item identity/category data.

## Distribution work

A whitelist-based `Build-Rmskin.ps1` and distribution validation exist for future sharing. Package staging excludes local API settings, runtime history/state, generated output and credentials. Recipient-local settings are intended to survive package upgrades via Rainmeter skin merge semantics. Windows package-builder validation remains outstanding before publication.

## Later phases

After the offline catalog is sufficiently complete:

1. bounded/staggered Item Market resale-price queue;
2. category-aware effective carrying capacity;
3. promote Nessie Plushie and Cherry Blossom as the first visible multi-item proof;
4. country/category filters;
5. Torn travel-state destination filtering and arrival countdown;
6. full-country economics population;
7. `Optimal` route scheduling only after sufficient availability/economic evidence exists.

## Existing validation debt retained

Earlier Settings/current-capacity interaction acceptance remains useful Windows evidence and is not erased by this expansion.
