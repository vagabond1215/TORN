# Next Codex Run: Independent Multi-Item Cards

**Status: ACTIVE — PENDING TARGET-WINDOWS ACCEPTANCE**

## Expansion rule

```text
collect broadly
show narrowly
optimize only after evidence/economics are ready
```

## Accepted baseline before this UI correction

The target Windows machine has already accepted:

- full 11-country shadow collection;
- 232 provider country-item rows / 227 active markets at the last live check;
- 202 locally resolved item metadata rows;
- verified legacy-market suppression;
- bounded broad resale transport;
- category-aware capacity with Xanax/general capacity isolated from Flower/Toy bonuses;
- the original UK/Japan Xanax graph/timing cards.

The first multi-item screenshot then exposed a presentation error: Nessie Plushie and Cherry Blossom were rendered as subordinate rows inside the existing Xanax country cards.

That composition is rejected.

## Correct item-card identity

The presentation identity is now the same durable market identity used by the data model:

```text
country + itemId
```

Each visible opportunity owns a separate Rainmeter card.

Current configured cards:

```text
United Kingdom + 206 Xanax
United Kingdom + 266 Nessie Plushie
Japan          + 206 Xanax
Japan          + 277 Cherry Blossom
```

The new intended layout is:

```text
[ UK flag | XANAX          | foreign price (market value) | stock ]
  expanded Xanax body / graph

[ UK flag | Nessie Plushie | foreign price (market value) | stock ]
  collapsed by default

[ JP flag | XANAX          | foreign price (market value) | stock ]
  expanded Xanax body / graph

[ JP flag | Cherry Blossom | foreign price (market value) | stock ]
  collapsed by default
```

No secondary item should appear indented inside a Xanax card again.

## Expansion cap

`TravelAssistant.ini` now defines:

```text
MaxExpandedCards=2
```

`StateReader.lua` owns the interactive card state.

Rules:

- initial expanded cards are UK Xanax and Japan Xanax;
- every item header has an expand/collapse control;
- at most `MaxExpandedCards` visible cards may be expanded;
- opening a third card collapses another expanded card first;
- when expanding a secondary card, the same-country companion card is the preferred collapse target;
- collapsed cards retain their own independent border/header/stock/price state.

The cap is a presentation/resource limit only. It does not affect collection or history.

## Market value display

Every item header renders:

```text
foreign shop price (Torn Item Market reference)
```

The parenthesized market value is smaller and muted. The foreign price remains the primary profitability-colored value.

Missing market value remains unresolved/displayed as `-`; it is never treated as zero economics.

The broad resale queue still makes at most one bounded Torn Item Market request per normal update and prioritizes configured visible items before hidden catalog items.

## Secondary item graphs

`VisibleItems.ps1` remains local-only and now generates an item-specific graph image from retained `country + itemId` observations:

```text
uk-266-stock.png
jp-277-stock.png
```

Important evidence rule:

- graph generation may add the current `observedMarkets` provider snapshot at its real provider/source timestamp for display continuity;
- it does not write synthetic observations/cycles or turn predictions into history;
- it makes no network request.

The secondary graphs are present so a collapsed card can be expanded immediately without waiting for another provider request.

## Recommendation boundary

This UI correction does **not** promote Nessie/Cherry into the existing Xanax timing model.

Expanded secondary cards may show:

- current stock;
- foreign price;
- Torn market value;
- category-aware capacity/economics class;
- flight duration;
- retained item-specific stock graph.

Their decision text remains conservative, e.g.:

```text
Economics positive - timing model learning
Low margin - no departure recommendation
Unprofitable - no departure recommendation
Market value pending - no departure recommendation
```

No LEAVE NOW / safe-window timing should be generated for these secondary items yet.

## Runtime order remains

```text
UpdateTracker
ShadowCollector (fail-soft)
LocalCatalog (fail-soft / local-only)
FinalizeState
VisibleItems (local-only independent cards + secondary graphs)
visible heartbeat
ResaleQueue (fail-soft, max one request/run)
```

## Focused target-Windows validation

After pulling current `main`, run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-VisibleItems.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-VisibleItemsTests.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-RainmeterSkin.ps1
```

Then run one normal production pass:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\@Resources\Scripts\RunUpdate.ps1 -Action Update
```

Refresh Rainmeter and visually verify:

1. four independent card boundaries are visible;
2. UK/JP Xanax start expanded;
3. Nessie/Cherry start collapsed;
4. market value remains smaller in parentheses;
5. clicking Nessie expands its own graph and collapses UK Xanax when the two-card cap is already full;
6. clicking Cherry does the analogous Japan swap;
7. the panel height reflows rather than leaving a country-sized blank area;
8. out-of-stock header text still fits;
9. no secondary item receives actionable departure timing.

Do not call this corrected UI accepted until the user reports those Windows/Rainmeter checks.

## After acceptance

Next UI work can generalize the item-card list beyond the two proof items, then add country/category filters and travel-state destination filtering/countdown. `Optimal` remains later and must stay separate from collection/visibility.
