# Next Codex Run: Offline Foreign-Item Categories

**Status: ACTIVE**

## Expansion rule

```text
collect broadly
show narrowly
optimize only after evidence/economics are ready
```

## Accepted prerequisites

The target Windows machine has accepted the broad hidden catalog foundation:

```text
Prometheus healthy
11 foreign countries
232 observed country-item markets
232 / 232 markets with provider names
202 distinct observed item IDs
202 / 202 local metadata rows
0 provider-name conflicts
```

Focused validations already reported PASS for shadow collection, provider-name enrichment, local-catalog normalization, and Rainmeter static structure.

The accepted pre-category local catalog reported:

```text
observedItems:      202
metadataItems:      202
categoriesResolved: 3
unresolvedItems:    199
nameConflicts:      0
```

The three committed category seeds remain:

```text
206 Xanax          | Drug    | config_seed
266 Nessie Plushie | Plushie | config_seed
277 Cherry Blossom | Flower  | config_seed
```

## Torn catalog transport boundary

Do not reintroduce catalog network calls into the Rainmeter heartbeat. The target host timed out before returning metadata on all attempted Torn catalog strategies:

```text
v2 /torn/{ids}/items | 150 IDs | 20s | 0 resolved
v2 /torn/{ids}/items |  40 IDs | 30s | 0 resolved
classic torn/items    | bulk   | 12s | 0 resolved
```

`ItemMetadata.ps1` remains explicit/manual maintenance only.

## Current production runtime

```text
UpdateTracker
ShadowCollector (fail-soft)
LocalCatalog (fail-soft / local-only)
FinalizeState
heartbeat
```

`LocalCatalog.ps1` performs no network access.

## Implemented offline category snapshot

New committed data:

```text
config/foreign-item-categories.json
```

Snapshot provenance is retained in-file:

```text
source.id:         yata_abroad_snapshot
upstream repo:     kgensorealk-sudo/MyTORNHelper
upstream commit:   a3e957929ce6a4cd253c733467ad1dded74f8791
upstream path:     src/server/abroadItems.ts
upstream table:    KNOWN_FOREIGN_ITEMS
source entries:    197
reviewed:          2026-08-21
```

The upstream table identifies itself as a comprehensive abroad-item table using exact YATA categories and contains 197 static known foreign items. It is a category snapshot, **not** the live-market authority.

Only item IDs already observed by the live provider are enriched from this file. Snapshot-only/stale IDs do not create opportunities or history.

### Category normalization

The snapshot uses YATA/Torn-era category vocabulary. Travel Assistant normalizes two labels for future filter semantics:

```text
Defensive -> Armor
Other     -> Miscellaneous
```

The resulting local category set is:

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

### Category precedence

For an observed `itemId`, metadata precedence is:

```text
manually acquired richer Torn metadata
        >
explicit config/items.json seed
        >
offline YATA category snapshot
        >
provider name + Unknown category
```

Snapshot-resolved rows use:

```text
source=offline_yata_category
categorySource=yata_abroad_snapshot
categoryResolved=true
```

An observed ID absent from the snapshot remains:

```text
source=provider_name
category=Unknown
categoryResolved=false
```

Never infer a missing category from the display name.

### Local catalog health additions

`engine-state.json -> localCatalog` now also records:

```text
offlineCategoryEntries
offlineMatchedItems
```

The catalog signature includes snapshot category/source data, so updating the committed mapping automatically triggers a local rebuild without network activity.

## Focused Windows acceptance

Pull current `main`, then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-LocalCatalog.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-LocalCatalogTests.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-RainmeterSkin.ps1
```

Then rebuild the real local catalog; this command is local-only:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\@Resources\Scripts\LocalCatalog.ps1
```

Inspect:

```powershell
$e = Get-Content .\data\runtime\engine-state.json -Raw | ConvertFrom-Json
$e.localCatalog | Format-List

$meta = @($e.itemMetadata.PSObject.Properties)
"Resolved: $(@($meta | Where-Object { $_.Value.categoryResolved -eq $true }).Count)"
"Unresolved: $(@($meta | Where-Object { $_.Value.categoryResolved -ne $true }).Count)"

$meta |
  Where-Object { $_.Value.categoryResolved -ne $true } |
  Select-Object Name,
    @{n='Item';e={$_.Value.name}},
    @{n='ProviderNames';e={$_.Value.providerNames -join ' | '}},
    @{n='Countries';e={$_.Value.countries -join ' | '}}
```

Also inspect the category distribution:

```powershell
$meta |
  Where-Object { $_.Value.categoryResolved -eq $true } |
  Group-Object { $_.Value.category } |
  Sort-Object Name |
  Select-Object Name, Count
```

## Expected result

The static snapshot has 197 entries while the live provider currently exposes 202 distinct item IDs, and the two sets are not assumed identical. Therefore:

- `offlineCategoryEntries` should be 197;
- `offlineMatchedItems` should be a large majority of the 202 observed IDs;
- `categoriesResolved` should rise sharply above 3;
- any current ID not represented by the snapshot must remain explicitly unresolved;
- current UK/Japan Xanax behavior must remain unchanged.

Do **not** assume the final unresolved count in advance.

## Completion of this phase

After the Windows result:

1. record the actual snapshot-match/resolution counts;
2. individually research every remaining unresolved current item ID;
3. add only verified category entries with provenance;
4. repeat until the current observed catalog is fully resolved or a specific item is intentionally documented as unresolved.

## Later phases

After current categories are sufficiently complete:

1. bounded/staggered resale-price refresh;
2. general + category-specific carrying capacity;
3. visible Nessie Plushie / Cherry Blossom multi-item proof;
4. country/category filters;
5. travel-state destination filtering and arrival countdown;
6. full-country economics;
7. `Optimal` route scheduling only after sufficient evidence exists.
