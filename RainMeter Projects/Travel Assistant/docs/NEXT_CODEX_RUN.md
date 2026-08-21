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

Do not repeat that acceptance unless collection behavior changes.

### Metadata isolation fallback

The target Windows host timed out on every attempted Torn catalog transport before returning metadata:

```text
v2 /torn/{ids}/items | 150 IDs | 20s | 0 resolved
v2 /torn/{ids}/items |  40 IDs | 30s | 0 resolved
classic torn/items    | bulk   | 12s | 0 resolved
```

This is a proven host/endpoint boundary. Metadata network maintenance is therefore **not part of the Rainmeter heartbeat path**.

Target Windows has now passed:

```text
Validate-ItemMetadata.ps1
Run-ItemMetadataTests.ps1
Validate-RainmeterSkin.ps1
```

Runtime seed metadata was confirmed:

```text
206 Xanax          | Drug    | config_seed
266 Nessie Plushie | Plushie | config_seed
277 Cherry Blossom | Flower  | config_seed
```

This fallback is accepted. Do not block further expansion on Torn catalog timeouts.

## Current production runtime

```text
UpdateTracker
ShadowCollector (fail-soft)
FinalizeState
heartbeat
```

`ItemMetadata.ps1` is manual/maintenance-only.

## Current goal

Build a committed/offline item catalog for the provider-observed foreign market without changing current visible UK/Japan Xanax behavior.

### Provider-name enrichment now implemented

The shadow collector now preserves provider-supplied item names when available:

```text
observation.itemName
engine-state.json -> observedMarkets.<country:itemId>.providerName
```

This is metadata only. Durable history identity remains:

```text
country + itemId
```

Provider names do not change cycle isolation, stock/price-change deduplication, visibility, or optimizer eligibility.

Focused validation was updated to require provider-name preservation:

```text
tests/Validate-ShadowCollection.ps1
tests/Run-ShadowCollectionTests.ps1
```

## Immediate Windows validation

Pull current `main`, then run only the focused shadow checks because collection source changed:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-ShadowCollection.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-ShadowCollectionTests.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-RainmeterSkin.ps1
```

Then force one live shadow pass:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\@Resources\Scripts\ShadowCollector.ps1 -Force

$e = Get-Content .\data\runtime\engine-state.json -Raw | ConvertFrom-Json
$markets = @($e.observedMarkets.PSObject.Properties)

"Observed markets: $($markets.Count)"
"Markets with provider names: $(@($markets | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_.Value.providerName) }).Count)"

$markets |
  Where-Object { $_.Name -in @('united_kingdom:266','japan:277') } |
  Select-Object Name,
    @{n='ProviderName';e={$_.Value.providerName}},
    @{n='Stock';e={$_.Value.lastStock}},
    @{n='Price';e={$_.Value.lastForeignPrice}}
```

Expected:

- observed market count remains around the accepted live catalog size;
- many/most rows have `providerName` when the active provider supplies names;
- Nessie/Cherry names appear when those rows are in the provider payload;
- no shadow error;
- current Rainmeter Xanax cards remain healthy.

## Offline catalog design

Next implementation after provider-name acceptance:

1. create a committed catalog keyed by `itemId`;
2. use provider names as discovery/cross-check evidence, not as the durable category authority;
3. populate canonical categories from verified external/Torn-derived metadata outside the Rainmeter heartbeat;
4. retain provenance per catalog entry;
5. validate that every currently observed item ID is either resolved or explicitly unresolved;
6. never guess a category to make filters/optimizer work.

The local catalog should be packaged with the eventual `.rmskin`, so recipients do not need a successful Torn catalog fetch just to know item names/categories.

## Later phases

After the offline catalog is sufficiently complete:

1. bounded/staggered resale-price refresh;
2. general + category-specific carrying capacity;
3. visible Nessie/Cherry multi-item proof;
4. country/category filters;
5. travel-state destination filtering and arrival countdown;
6. full-country economics;
7. `Optimal` route scheduling only after sufficient evidence exists.
