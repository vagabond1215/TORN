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

Accepted live baseline:

```text
lastProvider:         prometheus
countriesSeen:        11
marketsSeen:          232
observedMarkets:      232
observationsWritten:  51 on the forced acceptance pass
lastError:            empty
```

History identity remains `country + itemId`, primary UK/Japan Xanax writes are protected from shadow duplication, and raw history is written only for stock/foreign-price changes.

## Provider-name enrichment — ACCEPTED

Target Windows passed:

```text
Validate-ShadowCollection.ps1
Run-ShadowCollectionTests.ps1
Validate-RainmeterSkin.ps1
```

A subsequent forced live pass reported:

```text
Observed markets: 232
Markets with provider names: 232
```

Provider names are now accepted discovery/cross-check metadata for the whole currently observed market. They do not replace item IDs as durable identity and they do not determine category/economics by themselves.

## Torn catalog transport — REJECTED FOR HEARTBEAT USE

The target Windows host timed out before returning metadata on all tested Torn catalog strategies:

```text
v2 /torn/{ids}/items | 150 IDs | 20s | 0 resolved
v2 /torn/{ids}/items |  40 IDs | 30s | 0 resolved
classic torn/items    | bulk   | 12s | 0 resolved
```

`ItemMetadata.ps1` remains manual/maintenance-only. Catalog network latency must not delay the skin.

## Committed metadata fallback — ACCEPTED

Target Windows validated and confirmed:

```text
206 Xanax          Drug     config_seed
266 Nessie Plushie Plushie  config_seed
277 Cherry Blossom Flower   config_seed
```

Seed metadata intentionally keeps market value/tradability unknown unless richer metadata exists.

## Local offline catalog — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

New:

```text
@Resources/Scripts/LocalCatalog.ps1
tests/Validate-LocalCatalog.ps1
tests/Run-LocalCatalogTests.ps1
```

`RunUpdate.ps1` now serializes:

```text
UpdateTracker
ShadowCollector (fail-soft)
LocalCatalog (fail-soft / local only)
FinalizeState
heartbeat
```

`LocalCatalog.ps1` performs **no network access**. It collapses the provider-observed market table by `itemId`, retains provider names/country membership, and builds `engine-state.json -> itemMetadata` for every distinct observed item.

Current category policy:

- committed items use their verified `config/items.json` name/category with `source=config_seed` and `categoryResolved=true`;
- unclassified provider-observed items use their provider name with `source=provider_name`, `category=Unknown`, `categoryResolved=false`;
- multiple provider names for one item ID are retained as `nameConflict=true` instead of silently choosing a new identity;
- richer manually acquired `source=torn_items_bulk` rows are preserved and only augmented with provider/country context.

A deterministic SHA-256 signature prevents needless runtime-state rewrites when provider names/country membership and committed seed metadata have not changed.

Runtime health is stored under:

```text
engine-state.json -> localCatalog
```

with:

```text
signature
lastBuildAt
observedItems
metadataItems
categoriesResolved
unresolvedItems
nameConflicts
```

## Remaining acceptance for local catalog

Run on target Windows:

```text
Validate-LocalCatalog.ps1
Run-LocalCatalogTests.ps1
Validate-RainmeterSkin.ps1
```

Then run `LocalCatalog.ps1` once and inspect `localCatalog` plus `itemMetadata`.

Expected current scale:

```text
observedItems:      ~202
metadataItems:      >= observedItems
categoriesResolved: >= 3
nameConflicts:      ideally 0
```

No network call should occur during that test.

## Active next goal: verified offline categories

After local-catalog acceptance, add verified category overrides for the remaining observed IDs using static/offline Torn-derived evidence. The official Torn Wiki item taxonomy currently documents the relevant categories, including Alcohol, Artifact, Clothing, Defensive, Drug, Enhancer, Flower, Medical, Melee, Other, Plushie, Primary, Secondary, Temporary, plus Tool and Material classifications.

Never infer category purely from item naming. Every observed item should eventually be resolved or explicitly left unresolved with provenance retained.

The resulting catalog must be suitable for inclusion in the eventual `.rmskin`, so recipients do not need Torn catalog access just to know item names/categories.

## Distribution work

A whitelist-based `.rmskin` package-builder path exists for future sharing. Distribution must exclude local API settings, runtime history/state, generated output and credentials. Recipient-local settings should survive package upgrades. Windows package-builder validation remains outstanding before publication.

## Later phases

After offline categories are sufficiently complete:

1. bounded/staggered Item Market resale-price queue;
2. category-aware effective carrying capacity;
3. promote Nessie Plushie and Cherry Blossom as the first visible multi-item proof;
4. country/category filters;
5. Torn travel-state destination filtering and arrival countdown;
6. full-country economics population;
7. `Optimal` route scheduling only after sufficient availability/economic evidence exists.

## Existing validation debt retained

Earlier Settings/current-capacity interaction acceptance remains useful Windows evidence and is not erased by this expansion.
