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

Focused tests passed:

```text
Validate-ShadowCollection.ps1
Run-ShadowCollectionTests.ps1
Validate-RainmeterSkin.ps1
```

Live forced shadow pass from the project directory reported:

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

Do not repeat the shadow acceptance unless later collection code changes.

## Current goal

Enrich every **distinct item ID** discovered by the live foreign-stock collector with canonical Torn metadata, without changing current UK/Japan Xanax UI/recommendation economics.

## Implemented metadata layer

New:

```text
@Resources/Scripts/ItemMetadata.ps1
tests/Validate-ItemMetadata.ps1
tests/Run-ItemMetadataTests.ps1
```

`RunUpdate.ps1` serializes:

```text
UpdateTracker
ShadowCollector (fail-soft)
ItemMetadata (fail-soft / low-frequency)
FinalizeState
heartbeat
```

### Metadata source

Use Torn API v2 specific-item metadata:

```text
GET /v2/torn/{ids}/items?sort=ASC
```

This is a public-key endpoint. Specific-ID requests populate details when available.

### Runtime contract

Ignored `engine-state.json` contains:

```text
itemMetadata
metadataCollection
```

Per-item metadata:

```text
itemId
name
type
subType
category
categoryResolved
isTradable
marketPrice
shops
fetchedAt
source=torn_items
```

Category rules:

- non-weapons use canonical Torn `type`;
- weapons use `details.category` when available, retaining Primary/Secondary/Melee/Temporary;
- missing weapon detail remains broad `Weapon` with `categoryResolved=false` rather than guessing.

Torn `marketPrice` is metadata/reference only in this phase. Do not feed it into the existing profitability gate.

## Windows validation already reported PASS

Target Windows passed:

```text
Validate-ItemMetadata.ps1
Run-ItemMetadataTests.ps1
Validate-RainmeterSkin.ps1
```

The live runtime had:

```text
observedMarkets:        232
distinctObservedItems:  202
```

The first forced metadata request did execute from the correct project directory, but the initial 150-ID / 20-second request timed out:

```text
lastRefreshAt:          0
lastAttemptAt:          1787342902
distinctObservedItems:  202
itemsRequested:         0
itemsResolved:          0
lastError:              curl.exe exceeded the 20s Torn metadata timeout.
```

This is accepted as a real transport/response-size boundary, not a path/cwd error.

## Revised rate/security/reliability boundaries

The metadata path is now intentionally more conservative:

- default refresh interval: 21,600 seconds / 6 hours;
- default batch size: **40 item IDs**;
- hard runtime batch cap: 100 IDs even if manually overridden;
- per-batch Torn curl timeout: **30 seconds**;
- the observed 202 distinct items therefore require six default batches (40 + 40 + 40 + 40 + 40 + 2);
- every successful batch is atomically checkpointed to ignored `engine-state.json` before the next request;
- if a later batch times out, already-returned metadata remains available;
- `itemsResolved` reports the number of metadata entries actually present in runtime state;
- all attempts, including partial/error attempts, respect the six-hour interval unless `-Force` is explicitly used;
- Torn requests use bounded `curl.exe --config -`;
- API key is supplied through stdin Authorization header, not URL/process command line;
- metadata failure is fail-soft and must not block finalization/heartbeat.

## Immediate Windows retry

Pull current `main`, then run only the metadata-focused checks because the previously reported tests passed against the earlier batch contract:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-ItemMetadata.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-ItemMetadataTests.ps1
```

Then force one live metadata refresh:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\@Resources\Scripts\ItemMetadata.ps1 -Force
```

Inspect only non-secret runtime state:

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

Optional unresolved-category check:

```powershell
$meta |
  Where-Object { $_.Value.categoryResolved -eq $false } |
  Select-Object Name, @{n='Item';e={$_.Value.name}}, @{n='Type';e={$_.Value.type}}, @{n='Category';e={$_.Value.category}}
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

- `source` = `torn_items`;
- `lastRefreshAt` recent;
- `lastError` empty;
- `distinctObservedItems` = current distinct observed ID count (202 in the first live catalog);
- `itemsRequested` = `distinctObservedItems`;
- `itemsResolved` equals or is very close to `itemsRequested`;
- canonical categories populated;
- sample metadata for Xanax `[206]`, Nessie Plushie `[266]`, Cherry Blossom `[277]` appears when those IDs are in the observed catalog.

If a later batch still times out, partial progress is now acceptable diagnostic evidence: `itemsResolved` must be greater than zero and the successful batch metadata must persist. Do not increase request frequency to compensate.

## Completion criteria

Mark this metadata run **COMPLETED** only when:

- the revised focused metadata tests pass on Windows;
- a forced metadata refresh completes, or a remaining specific Torn-side item/batch incompatibility is isolated without losing successful batch progress;
- runtime metadata/category state is populated and bounded;
- current visible Xanax functionality remains unchanged.

## Next implementation after completion

1. Add bounded/staggered Torn Item Market resale-price refresh for the observed catalog.
2. Generalize effective capacity into general + category-specific bonuses.
3. Promote Nessie Plushie and Cherry Blossom as the first visible multi-item proof.
4. Add country/category filters.
5. Add Torn `/user/travel` destination filtering and arrival countdown.
6. Populate full-country travel economics.
7. Build `Optimal` only after the opportunity matrix has sufficient availability/economic evidence.

## Existing validation debt retained

Earlier Settings/current-capacity interaction checks (populate-only Sync, Airstrip 18 / Standard 13 mode flip, Business gating, healthy next poll) remain useful Windows evidence and are not erased by expansion.
