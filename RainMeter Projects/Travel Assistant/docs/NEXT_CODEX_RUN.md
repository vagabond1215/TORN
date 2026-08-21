# Next Codex Run: Bounded Resale-Price Queue

**Status: ACTIVE**

## Expansion rule

```text
collect broadly
show narrowly
optimize only after evidence/economics are ready
```

## Accepted catalog baseline

Target Windows has now accepted the complete current offline catalog and legacy-market filtering:

```text
provider:                     prometheus
countriesSeen:                11
provider country-item rows:   232
legacy provider rows:           5
active candidate markets:     227
observed item IDs:             202
metadata rows:                 202
categoriesResolved:            202
unresolvedItems:                 0
nameConflicts:                   0
```

Accepted legacy rows:

```text
mexico:21
mexico:232
mexico:327
united_arab_emirates:383
united_arab_emirates:440
```

Accepted canonical repairs:

```text
327 Blank Casino Chips | provider alias Blank Tokens | Material
383 Digital Organizer  | provider alias Platinum PDA | Miscellaneous
```

The visible UI remains UK/Japan Xanax only.

## Current production runtime

The established visible/data path remains:

```text
UpdateTracker
ShadowCollector (fail-soft)
LocalCatalog (fail-soft / local-only)
FinalizeState
visible heartbeat
```

New broad resale population runs **after** the heartbeat:

```text
ResaleQueue (fail-soft, max one request/run)
```

This ordering is intentional: broad-market resale latency must not make the current visible skin look unhealthy.

## Implemented resale queue

New production script:

```text
@Resources/Scripts/ResaleQueue.ps1
```

It reads current `engine-state.json -> observedMarkets` and builds a distinct item set only from active markets.

A market is excluded when:

```text
catalogActive=false
```

or defensively when:

```text
catalogStatus=legacy_removed
```

Therefore the five verified legacy provider rows remain observable for provenance but receive no broad resale work.

### Queue bounds

Defaults:

```text
minimum attempt interval: 60 seconds
broad cache freshness:     21600 seconds / 6 hours
failed-item backoff:        3600 seconds / 1 hour
request timeout:            6 seconds
requests per run path:      1
```

At the current roughly 197 active distinct-item scale, one successful request/minute can populate an initially empty active catalog in roughly 3.3 hours of loaded-skin runtime without an API burst.

This six-hour cache is the broad population/reference cache. The current visible Xanax updater retains its existing independent/fresher resale behavior and is not weakened by this change.

### Candidate selection

The queue skips:

- items whose resale cache is still fresh;
- verified inactive/legacy-only items;
- recently failed items still within backoff.

Never-priced eligible items are populated before old stale entries. Stale cached entries re-enter after the broad freshness interval.

### API/key handling

The queue uses the existing specific-item endpoint:

```text
https://api.torn.com/v2/market/{itemId}/itemmarket?limit=1
```

Transport uses bounded `curl.exe --config -` with URL and Authorization header passed through stdin. The API key is never placed in the URL or process arguments.

A successful cache row keeps the established resale schema:

```text
price
lowest
average
fetchedAt
source=torn_itemmarket
```

No usable price remains unresolved; zero is never interpreted as real economics.

### Runtime health

`engine-state.json -> resaleQueue` tracks:

```text
lastRunAt
lastAttemptAt
lastSuccessAt
lastItemId
activeMarkets
activeItems
pricedItems
freshItems
staleItems
successCount
failureCount
status
lastErrorAt
lastError
attempts
```

Per-item attempts retain failure/backoff state without overwriting the last successful resale cache row.

## Focused tests added

```text
tests/Validate-ResaleQueue.ps1
tests/Run-ResaleQueueTests.ps1
```

They are included in `tests/Run-All.ps1`.

The focused tests verify:

- active market rows collapse to distinct item IDs;
- `catalogActive=false` and `legacy_removed` rows are excluded;
- fresh caches are skipped;
- failed items back off instead of blocking the queue;
- never-priced eligible items are prioritized;
- the parser prefers the lowest listing and falls back to average price;
- a zero/no-price response remains unresolved;
- only one production broad Item Market invocation exists per queue run path;
- curl/key handling remains stdin/header based;
- the broad queue runs after the visible heartbeat and only for normal `Update` actions.

## Immediate Windows validation

Pull current `main`, then run only the focused checks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-ResaleQueue.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-ResaleQueueTests.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-RainmeterSkin.ps1
```

Then run one explicit live queue attempt:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\@Resources\Scripts\ResaleQueue.ps1 -Force
```

Inspect without exposing the API key:

```powershell
$e = Get-Content .\data\runtime\engine-state.json -Raw | ConvertFrom-Json
$e.resaleQueue | Format-List

"Resale cache rows: $(@($e.resaleCache.PSObject.Properties).Count)"

$lastId = [string]$e.resaleQueue.lastItemId
if (-not [string]::IsNullOrWhiteSpace($lastId) -and $lastId -ne '0') {
    $e.resaleCache.PSObject.Properties[$lastId].Value | Format-List
}
```

Healthy first-run boundaries:

```text
activeMarkets: approximately 227 for the current provider dataset
activeItems: approximately 197 if the five inactive IDs have no other active market
status: OK, or a bounded ERROR with one item backed off
lastItemId: one active item ID
```

Do not assume these live counts are permanent constants.

If `status=ERROR`, show only:

```powershell
$e.resaleQueue.lastItemId
$e.resaleQueue.lastError
```

Do not expose the API key or full local settings.

## Acceptance target

Before advancing:

- focused tests pass on Windows;
- one explicit live queue request completes within the bounded timeout or fails cleanly/backoffs one item;
- current UK/Japan Xanax UI remains healthy;
- no verified legacy market receives a resale attempt;
- repeated normal Rainmeter updates gradually increase `pricedItems` without API bursts.

## Next implementation after acceptance

Move to category-aware effective carrying capacity:

```text
general travel capacity
+ category-specific capacity when applicable
```

Required isolation:

- Flower Shop flower bonus only for Flower items;
- Toy Shop plushie bonus only for Plushie items;
- neither may increase Xanax capacity.

Then promote Nessie Plushie / Cherry Blossom as the first visible multi-item proof, followed by filters, travel-state destination behavior, full economics and finally `Optimal` scheduling.
