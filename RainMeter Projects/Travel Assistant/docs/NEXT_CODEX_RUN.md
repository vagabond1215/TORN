# Next Codex Run: Canonical Item Metadata Enrichment

**Status: ACTIVE**

This is the authoritative execution handoff for `RainMeter Projects/Travel Assistant/`.

## Expansion rule

```text
collect broadly
show narrowly
optimize only after evidence/economics are ready
```

## Completed prerequisite: full-market shadow collection

The full-market collector is operationally accepted on the target Windows machine.

```text
lastProvider:         prometheus
countriesSeen:        11
marketsSeen:          232
observedMarkets:      232
observationsWritten:  51
cyclesCompleted:      0
lastError:            empty
```

Focused shadow tests and Rainmeter static validation passed. Do not repeat shadow acceptance unless collection code changes.

## Current goal

Enrich every distinct item ID discovered by the foreign-stock collector with canonical Torn name/category metadata without changing the current UK/Japan Xanax UI/recommendation economics.

The first live catalog contained:

```text
232 country-item markets
202 distinct item IDs
```

## Live metadata evidence so far

Windows static/unit metadata tests passed for the original v2 implementation.

Two real Torn metadata attempts then established that the v2 multi-ID path is unsuitable on this target host:

### Attempt 1

```text
150 IDs
20 second timeout
itemsResolved: 0
error: curl.exe exceeded the 20s Torn metadata timeout
```

### Attempt 2

```text
40 IDs
30 second timeout
itemsRequested: 40
itemsResolved: 0
error: curl.exe exceeded the 30s Torn metadata timeout
```

This is accepted as a real endpoint/host transport boundary. Do not continue increasing the v2 multi-ID timeout or batch size.

## Current metadata strategy

`ItemMetadata.ps1` now uses the classic Torn bulk item dictionary in **one request**:

```text
GET https://api.torn.com/torn/?selections=items
Authorization: ApiKey <local key>
```

Torn supports API keys in the Authorization header, so the key is not placed in the URL or process command line.

The bulk response is filtered locally to the provider-observed item IDs.

### Runtime contract

Ignored `engine-state.json` contains:

```text
itemMetadata
metadataCollection
```

Per observed item metadata:

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

The classic Torn items selection already exposes travel-relevant item `type` values such as Drug, Flower, Plushie, Primary, Secondary, Melee, Temporary, Defensive, etc., so `type` is the canonical category for this metadata phase.

`marketPrice` is reference metadata only. Do not feed it into the established profitability gate yet.

## Reliability/security boundaries

- default refresh interval: 21,600 seconds / 6 hours;
- exactly one Torn metadata request per refresh attempt;
- default request timeout: 12 seconds;
- custom `User-Agent: TravelAssistant-Rainmeter/1.0`;
- bounded `curl.exe --config -` transport;
- API key supplied through stdin Authorization header;
- no `?key=` query parameter;
- metadata failure remains fail-soft;
- the visible updater/finalizer/heartbeat must continue if metadata fails.

`RunUpdate.ps1` remains:

```text
UpdateTracker
ShadowCollector (fail-soft)
ItemMetadata (fail-soft / low-frequency)
FinalizeState
heartbeat
```

## Required Windows validation

Pull current `main`, then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-ItemMetadata.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-ItemMetadataTests.ps1
```

Then force one bulk metadata refresh:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\@Resources\Scripts\ItemMetadata.ps1 -Force
```

Reload ignored runtime state from disk:

```powershell
$e = Get-Content .\data\runtime\engine-state.json -Raw | ConvertFrom-Json
$e.metadataCollection | Format-List

$meta = @($e.itemMetadata.PSObject.Properties)
"Metadata items: $($meta.Count)"

$meta |
  Where-Object { $_.Name -in @('206','266','277') } |
  Select-Object Name,
    @{n='Item';e={$_.Value.name}},
    @{n='Category';e={$_.Value.category}},
    @{n='Tradable';e={$_.Value.isTradable}},
    @{n='MarketPrice';e={$_.Value.marketPrice}}

$e.metadataCollection.categories
```

If metadata reports an error:

```powershell
if (Test-Path .\data\runtime\item-metadata-error.txt) {
    Get-Content .\data\runtime\item-metadata-error.txt
}
```

Do not paste API keys or full local settings.

## Expected acceptance evidence

Ideal complete refresh:

```text
source:                torn_items_bulk
lastRefreshAt:         recent
lastError:             empty
distinctObservedItems: ~202
itemsRequested:        ~202
itemsResolved:         ~202
```

Canonical categories should be populated, and observed IDs 206/266/277 should resolve to Xanax / Nessie Plushie / Cherry Blossom when present.

Any missing observed ID should remain unresolved rather than guessed.

## Completion criteria

Mark this metadata run **COMPLETED** only when:

- revised bulk metadata tests pass on Windows;
- one forced bulk Torn metadata refresh succeeds;
- runtime metadata/category state is populated and bounded;
- current visible Xanax behavior remains unchanged.

## Next implementation after completion

1. Add bounded/staggered Torn Item Market resale-price refresh for the observed catalog.
2. Generalize effective capacity into general + category-specific bonuses.
3. Promote Nessie Plushie and Cherry Blossom as the first visible multi-item proof.
4. Add country/category filters.
5. Add Torn `/user/travel` destination filtering and arrival countdown.
6. Populate full-country travel economics.
7. Build `Optimal` only after the opportunity matrix has sufficient availability/economic evidence.
