# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-21

**Active run:** canonical item metadata enrichment for the full provider-observed foreign catalog. See `docs/NEXT_CODEX_RUN.md`.

## Stable visible baseline

The Rainmeter presentation remains UK/Japan Xanax with the validated operational path:

- automatic one-minute polling and heartbeat;
- Prometheus preferred live stock with YATA fallback;
- observed restock/sellout history;
- Torn Item Market resale through bounded `curl.exe`;
- current-capacity economics using `/user/perks` authority;
- compact cards with profit-colored prices, conditional restock indicator, and 8-hour graphs.

## Full-market shadow collection — ACCEPTED

Live target-Windows evidence:

```text
lastProvider:         prometheus
countriesSeen:        11
marketsSeen:          232
observedMarkets:      232
observationsWritten:  51
cyclesCompleted:      0
lastError:            empty
```

The first live catalog contained 202 distinct item IDs.

## Canonical item metadata — TRANSPORT BLOCKED, RUNTIME ISOLATED

Static/unit metadata tests passed, but all live Torn catalog requests on the target Windows host timed out before returning metadata:

```text
v2 /torn/{ids}/items | 150 IDs | 20s | 0 resolved
v2 /torn/{ids}/items |  40 IDs | 30s | 0 resolved
classic torn/items    | bulk   | 12s | 0 resolved
```

Do not keep increasing metadata timeout/batch size.

### Heartbeat safety fix

`ItemMetadata.ps1` is no longer invoked by `RunUpdate.ps1`.

Current production runtime order:

```text
UpdateTracker
ShadowCollector (fail-soft)
FinalizeState
heartbeat
```

This prevents catalog maintenance from delaying the one-minute Rainmeter update path.

### Committed metadata fallback

`ItemMetadata.ps1` remains available as an explicit/manual maintenance tool. Before any optional Torn network attempt it imports the committed rows from `config/items.json` into runtime metadata with `source=config_seed`.

Current committed seed metadata:

```text
206 Xanax          | Drug
266 Nessie Plushie | Plushie
277 Cherry Blossom | Flower
```

Seed rows deliberately keep `marketPrice=0` and `tradabilityKnown=false`; unknown live economics are not inferred.

A later successful catalog refresh may replace seed rows with richer metadata, but a network timeout must not leave the known seed catalog empty.

## Distribution work implemented

`Build-Rmskin.ps1` uses whitelist-based staging and explicitly excludes local API settings, runtime history/state, generated output, and credentials. Recipient-local settings are preserved on package updates through Rainmeter merge semantics. Windows staging/package validation is still required before publishing a `.rmskin`.

## Next planned phases

1. establish a committed/offline full item metadata catalog refreshed outside the Rainmeter heartbeat;
2. bounded/staggered Item Market resale-price queue;
3. category-aware capacity (general + Flower/Plushie-specific effects);
4. visible Nessie/Cherry proof;
5. country/category filters;
6. travel-state destination filtering and arrival countdown;
7. full-country economics;
8. `Optimal` route scheduling after sufficient evidence exists.

## Existing validation debt retained

Earlier Settings/current-capacity interaction acceptance remains useful Windows evidence and is not erased by this expansion.
