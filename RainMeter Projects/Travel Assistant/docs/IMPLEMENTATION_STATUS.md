# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-21

**Active run:** bounded/staggered active-item resale-price queue. See `docs/NEXT_CODEX_RUN.md`.

## Stable visible baseline

The Rainmeter presentation remains UK/Japan Xanax with the established operational path:

- automatic one-minute polling and heartbeat;
- Prometheus preferred live stock with YATA fallback;
- observed restock/sellout history;
- current visible Xanax Torn Item Market resale through bounded `curl.exe`;
- current-capacity economics using `/user/perks` authority;
- compact cards with profit-colored prices, conditional restock indicator, and 8-hour graphs.

Data-layer expansion must not change this visible behavior until a later explicit UI phase.

## Full-market shadow collection / catalog — ACCEPTED

Latest target-Windows acceptance:

```text
lastProvider:                  prometheus
countriesSeen:                 11
marketsSeen:                   232
legacyMarketsSeen:               5
observationsWritten:            41 on the acceptance pass
cyclesCompleted:                 0 on that pass
lastError:                      empty

observedItems:                 202
metadataItems:                 202
categoriesResolved:            202
unresolvedItems:                 0
nameConflicts:                   0
offlineCategoryEntries:        197
offlineMatchedItems:            197
verifiedItemOverrides:            5
marketOverrides:                  5
inactiveObservedMarkets:          5
```

Current inferred active-market split for that provider snapshot:

```text
232 provider rows
- 5 verified legacy rows
= 227 active country-item markets
```

These counts are live baseline values, not timeless constants.

Accepted canonical repairs:

```text
327 Blank Casino Chips | provider still says Blank Tokens | Material | verified_override
383 Digital Organizer  | provider still says Platinum PDA | Miscellaneous | verified_override
```

Accepted legacy provider rows:

```text
mexico:21
mexico:232
mexico:327
united_arab_emirates:383
united_arab_emirates:440
```

They remain in `observedMarkets` for provenance but are annotated inactive and skipped before new shadow observation/cycle writes.

## Torn catalog transport — REJECTED FOR HEARTBEAT USE

The target Windows host timed out before returning metadata on all tested Torn catalog strategies:

```text
v2 /torn/{ids}/items | 150 IDs | 20s | 0 resolved
v2 /torn/{ids}/items |  40 IDs | 30s | 0 resolved
classic torn/items    | bulk   | 12s | 0 resolved
```

`ItemMetadata.ps1` remains manual/maintenance-only. Runtime catalog knowledge comes from committed local data plus provider names/verified overrides.

## Offline reference files — ACCEPTED

```text
config/foreign-item-categories.json
config/foreign-market-overrides.json
```

The category snapshot covers 197 current observed IDs; five individually verified overrides complete the current 202/202 category set and also mark stale country-item relationships inactive.

The `.rmskin` whitelist includes both files while continuing to exclude API keys, local settings and runtime data.

## Broad resale queue — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

New:

```text
@Resources/Scripts/ResaleQueue.ps1
tests/Validate-ResaleQueue.ps1
tests/Run-ResaleQueueTests.ps1
```

`RunUpdate.ps1` now completes the established visible pass first:

```text
UpdateTracker
ShadowCollector
LocalCatalog
FinalizeState
visible heartbeat
```

Then, only for normal `Update` actions, it runs the new queue fail-soft:

```text
ResaleQueue
```

This ordering protects visible polling health from broad resale latency.

### Queue defaults

```text
minimum attempt interval: 60s
broad cache freshness:     6h
failed-item backoff:        1h
request timeout:            6s
broad requests/run path:    1
```

The queue:

- collapses active `observedMarkets` to distinct item IDs;
- excludes `catalogActive=false` and `legacy_removed` rows;
- skips fresh cache entries;
- backs off failed items instead of retrying them every minute;
- prioritizes never-priced eligible items;
- writes the same `resaleCache` schema already consumed by current economics;
- never interprets a missing/zero price as real economics;
- uses `curl.exe --config -` with the key in the Authorization header through stdin, not URL/process arguments.

At the current scale, one request/minute can populate an initially empty ~197-active-item catalog in about 3.3 hours of loaded-skin runtime if requests succeed. The existing visible Xanax resale path remains independently fresher and unchanged.

Runtime health is stored under:

```text
engine-state.json -> resaleQueue
```

including active item/market counts, priced/fresh/stale counts, cumulative successes/failures, last item, status/error, and per-item attempt/backoff state.

## Focused acceptance still required

On target Windows:

```text
Validate-ResaleQueue.ps1
Run-ResaleQueueTests.ps1
Validate-RainmeterSkin.ps1
```

Then force exactly one queue attempt and inspect `engine-state.json -> resaleQueue` plus the last attempted `resaleCache` row.

Do not run the broad suite unless a focused failure indicates a wider regression.

## Next phase after acceptance

1. category-aware effective carrying capacity;
2. promote Nessie Plushie and Cherry Blossom as the first visible multi-item proof;
3. country/category filters;
4. Torn travel-state destination filtering and arrival countdown;
5. full-country economics population;
6. `Optimal` route scheduling after sufficient availability/economic evidence exists.

## Existing validation debt retained

Earlier Settings/current-capacity interaction acceptance remains useful Windows evidence and is not erased by this expansion.
