# Next Codex Run: Offline Full Item Catalog

**Status: ACTIVE**

## Expansion rule

```text
collect broadly
show narrowly
optimize only after evidence/economics are ready
```

## Accepted prerequisites

### Full-market shadow collection

Operationally accepted on target Windows:

```text
Prometheus healthy
11 countries
232 observed country-item markets
202 distinct item IDs in the first live catalog
no shadow error
```

### Provider-name enrichment

Target Windows passed:

```text
Validate-ShadowCollection.ps1
Run-ShadowCollectionTests.ps1
Validate-RainmeterSkin.ps1
```

A forced live pass then reported:

```text
Observed markets: 232
Markets with provider names: 232
```

Provider-name enrichment is therefore accepted. Every currently observed market has a provider-supplied item name available for local catalog discovery/cross-checking.

### Torn catalog network isolation

The target host timed out on all attempted runtime Torn catalog transports:

```text
v2 /torn/{ids}/items | 150 IDs | 20s | 0 resolved
v2 /torn/{ids}/items |  40 IDs | 30s | 0 resolved
classic torn/items    | bulk   | 12s | 0 resolved
```

Do not reintroduce catalog network work into the Rainmeter heartbeat. `ItemMetadata.ps1` remains manual/maintenance-only.

Committed seed metadata is already accepted:

```text
206 Xanax          | Drug    | config_seed
266 Nessie Plushie | Plushie | config_seed
277 Cherry Blossom | Flower  | config_seed
```

## Current production runtime

The next implementation adds a local-only catalog stage:

```text
UpdateTracker
ShadowCollector (fail-soft)
LocalCatalog (fail-soft / no network)
FinalizeState
heartbeat
```

## Implemented local catalog layer

New production script:

```text
@Resources/Scripts/LocalCatalog.ps1
```

It reads only:

```text
engine-state.json -> observedMarkets
config/items.json
```

and builds/updates:

```text
engine-state.json -> itemMetadata
engine-state.json -> localCatalog
```

### Per-item local metadata

Every distinct observed item ID receives a local metadata row.

Known committed seeds use:

```text
source=config_seed
category=<committed category>
categoryResolved=true
```

All other observed items use:

```text
source=provider_name
name=<provider name>
category=Unknown
categoryResolved=false
```

until a verified offline category override is committed.

Additional local fields retain:

```text
providerName
providerNames
nameConflict
countries
```

If multiple provider names are ever observed for the same `itemId`, the conflict is retained explicitly instead of silently selecting a new identity.

### Rich metadata preservation

A manually acquired `source=torn_items_bulk` row is richer than the local fallback. `LocalCatalog.ps1` preserves its category/market metadata and only adds current provider/country context; local fallback must never downgrade richer metadata.

### Rewrite guard

A deterministic SHA-256 signature covers the observed item/name/country set plus committed category seeds. If that signature has not changed and metadata coverage is already complete, the local catalog returns without rewriting runtime state.

### Runtime health

`engine-state.json -> localCatalog` records:

```text
signature
lastBuildAt
observedItems
metadataItems
categoriesResolved
unresolvedItems
nameConflicts
```

## New focused tests

```text
tests/Validate-LocalCatalog.ps1
tests/Run-LocalCatalogTests.ps1
```

They are included in `tests/Run-All.ps1`.

The tests require:

- no network access from `LocalCatalog.ps1`;
- provider rows collapse by `itemId` across countries;
- provider-name disagreements remain visible;
- committed categories override provider-only fallback;
- unknown categories remain explicitly unresolved;
- signature generation is deterministic;
- rich Torn metadata is not downgraded;
- runtime order remains ShadowCollector -> LocalCatalog -> FinalizeState;
- `ItemMetadata.ps1` remains outside the heartbeat.

## Immediate Windows validation

Pull current `main`, then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-LocalCatalog.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-LocalCatalogTests.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-RainmeterSkin.ps1
```

Then run the local catalog directly once; it performs no network calls:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\@Resources\Scripts\LocalCatalog.ps1

$e = Get-Content .\data\runtime\engine-state.json -Raw | ConvertFrom-Json
$e.localCatalog | Format-List

$meta = @($e.itemMetadata.PSObject.Properties)
"Metadata items: $($meta.Count)"

$meta |
  Where-Object { $_.Name -in @('206','266','277') } |
  Select-Object Name,
    @{n='Item';e={$_.Value.name}},
    @{n='Category';e={$_.Value.category}},
    @{n='Resolved';e={$_.Value.categoryResolved}},
    @{n='Source';e={$_.Value.source}}
```

Expected on the current 202-item observed catalog:

```text
observedItems:       ~202
metadataItems:       >= observedItems
categoriesResolved:  >= 3
unresolvedItems:     observedItems - resolved items
nameConflicts:       ideally 0
```

The three known rows must remain Drug / Plushie / Flower with `config_seed` provenance.

## Next implementation after local-catalog acceptance

Populate verified **offline category overrides** for the remaining observed IDs. Use official Torn Wiki item-type/category pages and other Torn-derived static evidence outside runtime. Never infer a category merely from an item name.

The official Wiki currently documents the item taxonomy and includes categories such as Alcohol, Artifact, Clothing, Defensive, Drug, Enhancer, Flower, Medical, Melee, Other, Plushie, Primary, Secondary, Temporary, plus newer Tool and Material classifications.

Completion target for that phase:

- every provider-observed item ID is either category-resolved or explicitly unresolved;
- provenance for each resolved category is retained;
- no runtime Torn catalog dependency;
- the catalog is suitable for inclusion in the eventual `.rmskin`.

## Later phases

After offline categories are sufficiently complete:

1. bounded/staggered resale-price refresh;
2. general + category-specific carrying capacity;
3. visible Nessie/Cherry multi-item proof;
4. country/category filters;
5. travel-state destination filtering and arrival countdown;
6. full-country economics;
7. `Optimal` route scheduling only after sufficient evidence exists.
