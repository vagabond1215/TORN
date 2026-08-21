# Next Codex Run: Canonical Item Metadata Enrichment

**Status: ACTIVE**

## Expansion rule

```text
collect broadly
show narrowly
optimize only after evidence/economics are ready
```

## Accepted prerequisite

Full-market shadow collection is operationally accepted:

```text
11 countries
232 observed country-item markets
202 distinct item IDs in the first live catalog
Prometheus healthy
no shadow error
```

Do not repeat shadow acceptance unless collection code changes.

## Metadata transport evidence

The target Windows host has now timed out on all attempted Torn catalog transports before returning any metadata:

```text
v2 /torn/{ids}/items | 150 IDs | 20s | 0 resolved
v2 /torn/{ids}/items |  40 IDs | 30s | 0 resolved
classic torn/items    | bulk   | 12s | 0 resolved
```

This is a proven host/endpoint boundary. Do not keep increasing timeouts or batch sizes.

## Current architecture

Metadata network maintenance is no longer part of the Rainmeter heartbeat path.

Production runtime order is again:

```text
UpdateTracker
ShadowCollector (fail-soft)
FinalizeState
heartbeat
```

`ItemMetadata.ps1` remains an explicit/manual maintenance tool only.

### Local committed metadata fallback

Before any optional network attempt, `ItemMetadata.ps1` imports the explicit committed item metadata from `config/items.json` into ignored runtime `itemMetadata` with:

```text
source=config_seed
marketPrice=0
tradabilityKnown=false
```

Current committed seeds:

```text
206 Xanax          | Drug
266 Nessie Plushie | Plushie
277 Cherry Blossom | Flower
```

A successful future Torn metadata refresh may replace these seed rows with richer `source=torn_items_bulk` rows. A Torn timeout must not erase or suppress the committed seed metadata.

## Immediate Windows validation

Pull current `main`, then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-ItemMetadata.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-ItemMetadataTests.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-RainmeterSkin.ps1
```

Then run the manual metadata tool once. It may still report the already-known Torn timeout; the important acceptance condition is that the committed seed metadata is present anyway:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\@Resources\Scripts\ItemMetadata.ps1 -Force

$e = Get-Content .\data\runtime\engine-state.json -Raw | ConvertFrom-Json
$e.metadataCollection | Format-List
$meta = @($e.itemMetadata.PSObject.Properties)
"Metadata items: $($meta.Count)"

$meta |
  Where-Object { $_.Name -in @('206','266','277') } |
  Select-Object Name,
    @{n='Item';e={$_.Value.name}},
    @{n='Category';e={$_.Value.category}},
    @{n='Source';e={$_.Value.source}}
```

Expected minimum result even if Torn times out:

```text
Metadata items: >= 3
206 Xanax          Drug     config_seed
266 Nessie Plushie Plushie  config_seed
277 Cherry Blossom Flower   config_seed
```

## Next implementation direction

Do not block further expansion on the target machine's Torn catalog timeout. The next catalog step should establish a **committed/offline full item metadata catalog** refreshed outside the Rainmeter heartbeat, then use that local catalog for categories and filtering.

After that:

1. bounded/staggered resale-price refresh;
2. general + category-specific carrying capacity;
3. visible Nessie/Cherry multi-item proof;
4. country/category filters;
5. travel-state destination filtering and arrival countdown;
6. full-country economics;
7. `Optimal` route scheduling only after sufficient evidence exists.
