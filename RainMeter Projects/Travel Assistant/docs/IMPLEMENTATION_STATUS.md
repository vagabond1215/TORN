# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-21

**Active run:** full foreign-market shadow collection. See `docs/NEXT_CODEX_RUN.md`.

## Stable visible baseline

The current Rainmeter presentation remains UK/Japan Xanax and retains the previously validated operational path:

- Rainmeter junction install;
- automatic one-minute polling and heartbeat;
- Prometheus preferred live stock with YATA fallback;
- current foreign price/stock/source freshness;
- observed restock/sellout history;
- Torn Item Market resale via the bounded Windows `curl.exe` workaround;
- current-capacity economics using `/user/perks` authority;
- compact UK/Japan cards and 8-hour graphs.

Recent presentation work has also moved price/stock into the card header, added plane/delivery-truck vector icons, made `Out of Stock` red, formatted outage age as `Out of Stock for h:mm since HH:mm`, and made raw restock timing conditional/tooltipped.

These presentation changes are not the subject of the new shadow collector and should remain unchanged during its acceptance test.

## Full-market shadow collection implemented

All 11 Torn foreign destinations are configured with `collect: true` and Prometheus/YATA provider codes. Only United Kingdom and Japan remain `enabled: true` for the current visible/model path.

`config/items.json` explicitly seeds:

- Xanax `[206]` — Drug — current visible/primary item;
- Nessie Plushie `[266]` — Plushie — UK hidden collection seed;
- Cherry Blossom `[277]` — Flower — Japan hidden collection seed.

The new `collect`, `visible`, `optimizerEligible`, and `countries` fields separate background collection from later UI/optimizer eligibility. The shadow collector itself is not limited to these three item IDs; it normalizes every valid provider row for every collection country.

`ShadowCollector.ps1`:

- defaults to a 120-second poll interval;
- uses Prometheus then YATA fallback;
- tracks every observed `country:itemId` market in ignored engine state;
- appends raw history only when stock or foreign price changes;
- retains source freshness in runtime metadata;
- creates completed cycles with existing country/item identity;
- skips current primary markets to protect UK/Japan Xanax from duplicate writes;
- is fail-soft and cannot block the existing finalizer/heartbeat.

`RunUpdate.ps1` serializes:

```text
UpdateTracker
ShadowCollector (fail-soft)
FinalizeState
heartbeat
```

The separate shadow provider request is an intentional migration bridge. The desired later architecture is one shared foreign-stock fetch fanning out to all markets after primary behavior equivalence is proven.

## Focused Windows validation

Reported PASS on the target Windows machine:

```text
Validate-ShadowCollection.ps1
Run-ShadowCollectionTests.ps1
Validate-RainmeterSkin.ps1
```

`Run-ShadowCollectionTests.ps1` specifically passed provider-row normalization, primary-market protection, provider-timestamp deduplication, stock/price-change recording, and country/item-isolated cycle completion.

The first attempt to inspect `engine-state.json` was run from `C:\Users\vagab` rather than the Travel Assistant directory, so the relative path resolved to `C:\Users\vagab\data\runtime\engine-state.json` and failed. The resulting `Observed markets: 1` output is not accepted as live shadow evidence because `$e` was not freshly loaded from the project runtime file.

## Remaining acceptance for this run

From the Travel Assistant directory, force one shadow poll and inspect the real ignored runtime state. Success requires:

- recent `lastPollAt`;
- `lastProvider` normally `prometheus` (or `yata` fallback);
- no `lastError`;
- multiple countries/markets seen;
- observed-market count substantially above the two visible Xanax markets;
- current UK/Japan Xanax cards remain healthy.

Once that succeeds, the next implementation phase is canonical item metadata/category enrichment followed by a bounded/staggered resale-price queue.

## Not implemented yet

- canonical metadata/category enrichment for every provider-observed item ID;
- broad resale-price refresh queue;
- category-specific Flower/Plushie capacity economics for general multi-item recommendations;
- visible Nessie/Cherry cards;
- country/category filters;
- Torn `/user/travel` destination/arrival-aware display;
- economics for all collection-only countries;
- `Optimal` route scheduling.

## Existing validation debt retained

The earlier Settings/current-capacity interaction acceptance (populate-only sync, Airstrip 18 / Standard 13 mode flip, Business gating and healthy following poll) remains useful Windows evidence. It was not invalidated or falsely marked complete by the shadow-collection expansion.
