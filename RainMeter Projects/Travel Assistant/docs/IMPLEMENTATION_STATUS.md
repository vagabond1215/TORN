# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-21

**Active run:** offline foreign-item category resolution. See `docs/NEXT_CODEX_RUN.md`.

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

Current accepted target-Windows baseline:

```text
11 countries
232 observed country-item markets
232 / 232 markets with provider names
Prometheus healthy
no shadow error
```

History identity remains `country + itemId`, current primary UK/Japan Xanax writes are protected from shadow duplication, and raw history is written only for stock/foreign-price changes.

## Torn catalog transport — REJECTED FOR HEARTBEAT USE

The target Windows host timed out before returning metadata on all tested Torn catalog strategies:

```text
v2 /torn/{ids}/items | 150 IDs | 20s | 0 resolved
v2 /torn/{ids}/items |  40 IDs | 30s | 0 resolved
classic torn/items    | bulk   | 12s | 0 resolved
```

`ItemMetadata.ps1` remains manual/maintenance-only. Runtime catalog knowledge must not depend on those requests.

## Local catalog — ACCEPTED

Target Windows passed:

```text
Validate-LocalCatalog.ps1
Run-LocalCatalogTests.ps1
Validate-RainmeterSkin.ps1
```

The live local catalog reported:

```text
observedItems:      202
metadataItems:      202
categoriesResolved: 3
unresolvedItems:    199
nameConflicts:      0
```

Accepted seed rows:

```text
206 Xanax          Drug     config_seed
266 Nessie Plushie Plushie  config_seed
277 Cherry Blossom Flower   config_seed
```

`LocalCatalog.ps1` is local-only and collapses observed country-item markets into one item metadata row per distinct item ID while retaining provider-name and country context.

## Offline category snapshot — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

New committed data:

```text
config/foreign-item-categories.json
```

It vendors a 197-ID category snapshot from the public `KNOWN_FOREIGN_ITEMS` table in `kgensorealk-sudo/MyTORNHelper` at commit `a3e957929ce6a4cd253c733467ad1dded74f8791`. The upstream table documents itself as a comprehensive known foreign-item table using exact YATA categories.

The snapshot is metadata only. It does **not** create opportunities. `ShadowCollector.ps1` remains the authority for which country-item markets are currently observed.

Travel Assistant normalizes:

```text
Defensive -> Armor
Other     -> Miscellaneous
```

and otherwise retains the source category. The resulting category vocabulary is:

```text
Alcohol
Artifact
Armor
Clothing
Drug
Enhancer
Flower
Material
Medical
Melee
Miscellaneous
Plushie
Primary
Secondary
Temporary
Tool
```

`LocalCatalog.ps1` now applies metadata precedence:

```text
richer manual Torn metadata
    > explicit config seed
    > offline YATA category snapshot
    > provider name + Unknown
```

Snapshot-resolved rows use:

```text
source=offline_yata_category
categorySource=yata_abroad_snapshot
categoryResolved=true
```

An observed item absent from the static snapshot remains `Unknown` / unresolved instead of being guessed.

`engine-state.json -> localCatalog` now also records:

```text
offlineCategoryEntries
offlineMatchedItems
```

The deterministic catalog signature includes the offline category/source data so committed category updates cause a local rebuild without network activity.

## Focused acceptance still required

Run on target Windows:

```text
Validate-LocalCatalog.ps1
Run-LocalCatalogTests.ps1
Validate-RainmeterSkin.ps1
```

Then run `LocalCatalog.ps1` and inspect the actual counts.

Expected boundaries, not an assumed exact outcome:

- `offlineCategoryEntries = 197`;
- current `observedItems` remains around 202;
- a large majority of observed IDs should match the snapshot;
- `categoriesResolved` should rise sharply from 3;
- unmatched current IDs remain explicitly unresolved;
- current visible Xanax cards remain unchanged.

Once the actual unresolved IDs are known, verify those individually and extend the committed map only with supported categories.

## Distribution work

A whitelist-based `.rmskin` package-builder path exists. Distribution excludes local API settings, runtime history/state, generated output and credentials. Recipient-local settings are intended to survive package upgrades. Windows package-builder validation remains outstanding before publication.

## Later phases

After current categories are sufficiently complete:

1. bounded/staggered Item Market resale-price queue;
2. category-aware effective carrying capacity;
3. promote Nessie Plushie and Cherry Blossom as the first visible multi-item proof;
4. country/category filters;
5. Torn travel-state destination filtering and arrival countdown;
6. full-country economics population;
7. `Optimal` route scheduling only after sufficient availability/economic evidence exists.

## Existing validation debt retained

Earlier Settings/current-capacity interaction acceptance remains useful Windows evidence and is not erased by this expansion.
