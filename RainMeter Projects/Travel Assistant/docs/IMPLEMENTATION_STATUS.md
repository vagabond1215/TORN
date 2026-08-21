# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-21

**Active run:** complete offline foreign catalog + legacy-market filtering. See `docs/NEXT_CODEX_RUN.md`.

## Stable visible baseline

The Rainmeter presentation remains UK/Japan Xanax with the established operational path:

- automatic one-minute polling and heartbeat;
- Prometheus preferred live stock with YATA fallback;
- observed restock/sellout history;
- Torn Item Market resale through bounded `curl.exe`;
- current-capacity economics using `/user/perks` authority;
- compact cards with profit-colored prices, conditional restock indicator, and 8-hour graphs.

Data-layer expansion must not change this visible behavior until a later explicit UI phase.

## Full-market shadow collection — ACCEPTED

Current accepted target-Windows baseline:

```text
11 countries
232 observed country-item provider rows
232 / 232 rows with provider names
202 distinct item IDs
Prometheus healthy
no shadow error
```

History identity remains `country + itemId`; current primary UK/Japan Xanax writes are protected from shadow duplication.

## Torn catalog transport — REJECTED FOR HEARTBEAT USE

The target Windows host timed out before returning metadata on all tested Torn catalog strategies:

```text
v2 /torn/{ids}/items | 150 IDs | 20s | 0 resolved
v2 /torn/{ids}/items |  40 IDs | 30s | 0 resolved
classic torn/items    | bulk   | 12s | 0 resolved
```

`ItemMetadata.ps1` remains manual/maintenance-only. Runtime catalog knowledge must not depend on those requests.

## Local catalog — ACCEPTED

Target Windows previously passed the focused local-catalog and Rainmeter static tests and confirmed:

```text
observedItems:      202
metadataItems:      202
nameConflicts:      0
```

The initial committed seed rows remain:

```text
206 Xanax          Drug     config_seed
266 Nessie Plushie Plushie  config_seed
277 Cherry Blossom Flower   config_seed
```

## 197-ID offline category snapshot — LIVE COVERAGE CONFIRMED

`config/foreign-item-categories.json` vendors the 197-ID public `KNOWN_FOREIGN_ITEMS` category snapshot from `kgensorealk-sudo/MyTORNHelper` at commit `a3e957929ce6a4cd253c733467ad1dded74f8791`.

Travel Assistant normalizes:

```text
Defensive -> Armor
Other     -> Miscellaneous
```

The target catalog run resolved exactly 197 observed IDs through the seed/snapshot layer and surfaced five unresolved provider rows:

```text
21   Dual 92G Berettas | mexico
232  SIG 550           | mexico
327  Blank Tokens      | mexico
383  Platinum PDA      | united_arab_emirates
440  Pillow            | united_arab_emirates
```

Resolved category distribution before the five repairs:

```text
Alcohol           2
Armor            12
Artifact          8
Clothing         12
Drug             10
Enhancer           4
Flower            12
Material          12
Medical            1
Melee             27
Miscellaneous     41
Plushie           10
Primary           16
Secondary         15
Temporary         11
Tool               4
```

## Five verified legacy provider rows — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

The five unresolved rows were individually checked against current Torn Wiki item pages/current destination shop lists. They are not simply missing categories; they are legacy provider rows for markets no longer currently sold there.

Committed `config/foreign-market-overrides.json` records:

```text
21  Dual 92G Berettas -> Secondary      | mexico inactive
232 SIG 550           -> Primary        | mexico inactive
327 Blank Casino Chips-> Material       | mexico inactive; provider still says Blank Tokens
383 Digital Organizer -> Miscellaneous  | UAE inactive; provider still says Platinum PDA
440 Pillow            -> Melee          | UAE inactive
```

Important corrected invariant:

> A foreign-stock provider row means the provider knows/reports that country-item pair. It does not by itself prove the item is currently purchasable there.

`LocalCatalog.ps1` now applies precedence:

```text
richer manual Torn metadata
    > explicit config seed
    > verified item override
    > offline YATA category snapshot
    > provider name + Unknown
```

It annotates observed legacy markets with:

```text
catalogActive=false
catalogStatus=legacy_removed
catalogStatusSource=verified_override
```

and retains the provider row/history identity for provenance.

`ShadowCollector.ps1` also loads the inactive-market override set. It still updates `observedMarkets` and counts the raw provider row, but skips those five pairs before new observation/cycle history is written. `shadowCollection.legacyMarketsSeen` exposes the count.

Expected current live split after validation:

```text
provider rows observed: 232
verified legacy rows:      5
active candidate rows:   227
item metadata rows:      202
categories resolved:     202
unresolved items:          0
```

Existing historical rows are not deleted.

## Distribution

`Build-Rmskin.ps1` remains whitelist-based and now includes:

```text
config/foreign-item-categories.json
config/foreign-market-overrides.json
```

It still excludes recipient/local API settings, runtime history/state, generated output and credentials.

## Next phase after acceptance

Once the 202/202 category coverage and 5-row legacy suppression pass on target Windows:

1. bounded/staggered Item Market resale-price queue;
2. category-aware effective carrying capacity;
3. promote Nessie Plushie and Cherry Blossom as the first visible multi-item proof;
4. country/category filters;
5. Torn travel-state destination filtering and arrival countdown;
6. full-country economics population;
7. `Optimal` route scheduling only after sufficient availability/economic evidence exists.

## Existing validation debt retained

Earlier Settings/current-capacity interaction acceptance remains useful Windows evidence and is not erased by this expansion.
