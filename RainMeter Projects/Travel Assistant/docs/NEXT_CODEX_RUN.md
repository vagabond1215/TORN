# Next Codex Run: Full Foreign-Market Shadow Collection

**Status: ACTIVE**

This is the authoritative execution handoff for `RainMeter Projects/Travel Assistant/`.

## Goal

Start collecting useful history for the entire Torn foreign market **without changing the validated UK/Japan Xanax presentation or recommendation behavior**.

The expansion rule is:

```text
collect broadly
show narrowly
optimize only after evidence/economics are ready
```

## Implemented

- all 11 foreign destinations configured for background collection;
- UK/Japan remain the only currently enabled visible/model countries;
- Xanax `[206]` remains the only primary visible item;
- Nessie Plushie `[266]` and Cherry Blossom `[277]` are hidden metadata seeds;
- `ShadowCollector.ps1` normalizes every valid provider row for all collection countries;
- observed markets are tracked by `country:itemId` in ignored runtime engine state;
- raw history is written only for stock or foreign-price changes;
- provider timestamp refresh alone does not create another raw observation;
- restock/sellout cycles preserve country/item identity;
- visible UK/Japan Xanax markets are skipped by the shadow writer;
- shadow failures are fail-soft and cannot block finalization/heartbeat;
- the shadow pass currently uses a separate 120-second Prometheus/YATA request as a migration bridge.

## Windows validation already reported PASS

The target Windows machine passed:

```text
Validate-ShadowCollection.ps1
Run-ShadowCollectionTests.ps1
Validate-RainmeterSkin.ps1
```

The focused tests confirmed:

- 11 collection countries/provider codes;
- current visible scope remains UK/Japan Xanax;
- valid multi-row normalization;
- malformed-row rejection;
- primary-market protection;
- provider timestamp alone is deduplicated;
- stock/price changes create history;
- completed cycles remain isolated by country/item.

## Immediate remaining validation

The first runtime inspection was accidentally executed from `C:\Users\vagab`, so the relative `data\runtime\engine-state.json` path pointed outside the project and did not validate live shadow collection.

From the Travel Assistant directory, run a forced shadow poll and inspect the real runtime state:

```powershell
cd "C:\Codex\TORN\RainMeter Projects\Travel Assistant"

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\@Resources\Scripts\ShadowCollector.ps1 -Force

$e = Get-Content .\data\runtime\engine-state.json -Raw | ConvertFrom-Json
$e.shadowCollection | Format-List
"Observed markets: $(@($e.observedMarkets.PSObject.Properties).Count)"

$e.observedMarkets.PSObject.Properties |
  Where-Object { $_.Name -in @('united_kingdom:266','japan:277') } |
  Select-Object Name, Value
```

Expected live evidence:

- `lastPollAt` is recent;
- `lastProvider` is normally `prometheus`, or `yata` on fallback;
- `countriesSeen` is multiple and ideally all 11;
- `marketsSeen` is substantially greater than two;
- `lastError` is empty;
- observed-market count is substantially greater than the visible Xanax pair;
- Nessie/Cherry rows appear if those markets are present in the provider payload.

Then confirm the current UK/Japan Xanax cards still update normally in Rainmeter.

## Completion criteria

Mark this run **COMPLETED** when:

- the focused Windows tests above remain passing;
- one successful live shadow poll records multiple hidden markets;
- the existing heartbeat/finalizer continues normally;
- current UK/Japan Xanax UI/recommendations remain healthy;
- runtime state remains ignored/bounded.

## Next implementation after completion

1. Canonical Torn item name/category enrichment for every provider-observed item ID.
2. Bounded/staggered Torn Item Market resale-price queue per distinct item.
3. General + category-specific effective capacity economics.
4. Promote Nessie and Cherry as the first visible multi-item proof.
5. Add country/category filters.
6. Add Torn travel-state destination filtering and arrival countdown.
7. Populate full opportunity economics before enabling `Optimal` route scheduling.

## Existing validation debt retained

The earlier Settings/current-capacity interaction checks (populate-only Sync, Airstrip 18 / Standard 13 mode flip, Business gating, healthy next poll) remain useful Windows acceptance evidence and are not erased by this expansion.
