# Next Codex Run: Verify Complete Offline Catalog

**Status: ACTIVE**

## Expansion rule

```text
collect broadly
show narrowly
optimize only after evidence/economics are ready
```

## Accepted baseline

Target Windows has already established:

```text
11 foreign countries
232 provider country-item rows
232 / 232 provider rows with names
202 distinct observed item IDs
202 local metadata rows
0 provider-name conflicts
```

The visible UI remains UK/Japan Xanax only.

## Category snapshot result

The committed 197-ID YATA-derived category snapshot resolved 197 of the 202 current item IDs.

The five remaining rows reported by target Windows were:

```text
21   Dual 92G Berettas | mexico
232  SIG 550           | mexico
327  Blank Tokens      | mexico
383  Platinum PDA      | united_arab_emirates
440  Pillow            | united_arab_emirates
```

Their absence from the snapshot exposed a more important issue: all five are legacy provider rows for markets no longer currently sold there.

## Verified repairs now committed

`config/foreign-market-overrides.json` adds canonical item metadata plus per-market status:

```text
21  Dual 92G Berettas  | Secondary     | mexico inactive
232 SIG 550            | Primary       | mexico inactive
327 Blank Casino Chips | Material      | mexico inactive | provider alias Blank Tokens
383 Digital Organizer  | Miscellaneous | UAE inactive    | provider alias Platinum PDA
440 Pillow             | Melee         | UAE inactive
```

Evidence was checked against current Torn Wiki item pages and current destination shop listings.

Corrected invariant:

> A live-provider row is provider evidence that a country-item relationship exists in its dataset. It is not sufficient proof by itself that the item remains currently purchasable in that country.

## Runtime behavior

`LocalCatalog.ps1` now uses precedence:

```text
richer manually acquired Torn metadata
    > config/items.json seed
    > verified item override
    > 197-ID offline YATA category snapshot
    > provider name + Unknown
```

Verified legacy markets are annotated in `observedMarkets`:

```text
catalogActive=false
catalogStatus=legacy_removed
catalogStatusSource=verified_override
```

`ShadowCollector.ps1` still records the provider row in `observedMarkets` and counts it in `marketsSeen`, but it loads the inactive-market override set and skips those pairs before new observation/cycle writes.

New health counter:

```text
shadowCollection.legacyMarketsSeen
```

Existing historical rows are retained.

## Expected current split

```text
provider rows observed: 232
legacy provider rows:      5
active candidate rows:   227
observed item IDs:       202
categories resolved:     202
unresolved item IDs:       0
```

Do not hard-code 232/202 as timeless catalog constants; they are the current live baseline.

## Focused Windows acceptance

Pull current `main`, then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-ShadowCollection.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-ShadowCollectionTests.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-LocalCatalog.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-LocalCatalogTests.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-RainmeterSkin.ps1
```

Then force one current provider pass and rebuild local metadata:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\@Resources\Scripts\ShadowCollector.ps1 -Force

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\@Resources\Scripts\LocalCatalog.ps1
```

Inspect:

```powershell
$e = Get-Content .\data\runtime\engine-state.json -Raw | ConvertFrom-Json
$e.shadowCollection | Format-List
$e.localCatalog | Format-List

$meta = @($e.itemMetadata.PSObject.Properties)
"Resolved: $(@($meta | Where-Object { $_.Value.categoryResolved -eq $true }).Count)"
"Unresolved: $(@($meta | Where-Object { $_.Value.categoryResolved -ne $true }).Count)"

$legacy = @(
  $e.observedMarkets.PSObject.Properties |
  Where-Object { $_.Value.PSObject.Properties['catalogActive'] -and $_.Value.catalogActive -eq $false }
)
"Inactive observed markets: $($legacy.Count)"

$legacy |
  Select-Object Name,
    @{n='ProviderName';e={$_.Value.providerName}},
    @{n='Status';e={$_.Value.catalogStatus}},
    @{n='Reason';e={$_.Value.catalogStatusReason}}
```

Expected target-Windows result for the current provider dataset:

```text
shadowCollection.marketsSeen       = 232
shadowCollection.legacyMarketsSeen = 5
localCatalog.observedItems          = 202
localCatalog.categoriesResolved     = 202
localCatalog.unresolvedItems        = 0
localCatalog.inactiveObservedMarkets= 5
```

The two renamed canonical metadata rows should be:

```text
327 Blank Casino Chips | Material      | verified_override
383 Digital Organizer  | Miscellaneous | verified_override
```

Their provider names should remain available separately for provenance.

## Distribution

`Build-Rmskin.ps1` now stages both offline catalog files:

```text
config/foreign-item-categories.json
config/foreign-market-overrides.json
```

Local API settings/runtime history remain excluded.

## Next implementation after acceptance

Move to the bounded/staggered Item Market resale-price queue for active market candidates only. Legacy `catalogActive=false` markets must not receive valuation/optimizer work.

Then:

1. category-aware carrying capacity;
2. visible Nessie/Cherry multi-item proof;
3. country/category filters;
4. travel-state destination filtering and arrival countdown;
5. full-country economics;
6. `Optimal` scheduling after sufficient evidence exists.
