# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-21

**Active run:** independent multi-item card correction. See `docs/NEXT_CODEX_RUN.md`.

## Accepted foundation

Target Windows acceptance already covers:

```text
11 foreign countries collected
232 provider country-item rows at last live check
227 active market relationships
202 distinct observed items
202 metadata rows
202 categories resolved
5 verified legacy provider rows excluded from new learning/economics work
```

Also accepted:

- existing UK/Japan Xanax collection/history/model path;
- current `/user/perks` general capacity behavior;
- category-specific Flower/Toy capacity isolation;
- broad one-request-at-a-time Torn Item Market transport;
- current Xanax graph/timing presentation.

## First multi-item screenshot — STRUCTURE REJECTED

The first 0.3.0 screenshot successfully displayed:

- Nessie Plushie and Cherry Blossom;
- their live foreign values and stock;
- parenthesized Torn market values;
- existing Xanax behavior.

However, the new items were rendered as indented rows inside the existing Xanax country cards.

That presentation is rejected because the durable opportunity identity is `country + itemId`; each item must therefore own its own card.

## Independent item cards — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

Skin candidate version:

```text
0.3.1
```

Current intended cards:

```text
UK + Xanax
UK + Nessie Plushie
JP + Xanax
JP + Cherry Blossom
```

Each card has its own:

- border/background;
- country flag;
- item name;
- foreign shop price;
- smaller muted parenthesized Torn market reference;
- stock/out-of-stock header;
- expand/collapse control.

The two Xanax cards retain their established graph/timing bodies.

Nessie/Cherry now own item-specific graph images generated locally from retained `country + itemId` observations. They still do not emit actionable departure timing; their expanded bodies remain learning/economics-only.

## Expansion/resource cap

Current default:

```text
MaxExpandedCards=2
```

Initial state:

```text
UK Xanax       expanded
UK Nessie      collapsed
JP Xanax       expanded
JP Cherry      collapsed
```

`StateReader.lua` enforces the maximum interactively. Expanding a third card collapses another expanded card first, preferring the same-country companion card.

The cap affects only Rainmeter presentation. Collection, history, metadata and resale population continue for all active markets.

## Market-value display

All visible card headers use:

```text
foreignPrice (marketValue)
```

The foreign price remains primary/profitability-colored. The parenthesized market reference is smaller and muted.

Missing/stale broad market values remain displayable/unresolved according to existing cache semantics and never become zero economics.

## Runtime order

```text
UpdateTracker
ShadowCollector
LocalCatalog
FinalizeState
VisibleItems
heartbeat
ResaleQueue
```

`VisibleItems.ps1` is local-only. It may render secondary graphs but performs no network access and writes no synthetic history.

Broad resale remains bounded to one Torn Item Market request per normal update.

## Current validation boundary

The independent-card code has been committed, but Windows/Rainmeter acceptance has not yet been reported.

Focused checks now required:

```text
Validate-VisibleItems.ps1
Run-VisibleItemsTests.ps1
Validate-RainmeterSkin.ps1
```

Then one normal `RunUpdate.ps1 -Action Update`, Rainmeter refresh and visual interaction check.

Do not mark 0.3.1 accepted until the user confirms separate card boundaries, correct expand/collapse reflow and preserved stock/market-value rendering.

## Next after acceptance

1. generalize independent card enumeration beyond the two proof secondary items;
2. add country/category presentation filters;
3. add Torn travel-state destination filtering and arrival countdown;
4. generalize timing/economics per item where evidence is sufficient;
5. build `Optimal` later as a bounded scheduling layer, not a simple sort.
