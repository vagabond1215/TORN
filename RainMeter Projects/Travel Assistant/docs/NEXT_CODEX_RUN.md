# Next Codex Run: First Visible Multi-Item Release

**Status: ACTIVE**

## Expansion rule

```text
collect broadly
show narrowly
optimize only after evidence/economics are ready
```

## Accepted prerequisites

Target Windows has accepted:

```text
11 foreign countries
232 provider country-item rows
5 verified legacy/inactive provider rows
227 active country-item markets
202 distinct observed item IDs
202 / 202 categories resolved
0 unresolved
0 name conflicts
```

Broad resale pricing is also accepted live:

```text
activeMarkets: 227
activeItems:   197
status: OK
one bounded Torn Item Market request succeeded
```

Category-aware carrying capacity passed target-Windows focused tests:

```text
synced Airstrip general/Xanax capacity = 18
synced Standard general/Xanax capacity = 13
Flower Shop 7★: Flower +5 only
Toy Shop 7★: Plushie +5 only
```

Therefore with current general `+3`:

```text
Airstrip Flower/Plushie with matching 7★ company = 23
Standard Flower/Plushie with matching 7★ company = 18
Xanax remains 18 Airstrip / 13 Standard
```

## Implemented UI release pending Windows acceptance

Skin version:

```text
0.3.0
```

Visible destination rows are now:

```text
United Kingdom
  Xanax
  Nessie Plushie

Japan
  Xanax
  Cherry Blossom
```

Nessie and Cherry are deliberately:

```text
visible=true
enabled=false
optimizerEligible=false
```

They therefore do not replace or broaden the established primary Xanax collector/model path.

### Price display

Every visible item row displays:

```text
FOREIGN SHOP PRICE (TORN ITEM MARKET REFERENCE)
```

The foreign shop price remains the primary value and keeps profitability coloring.
The parenthesized Torn market reference is muted and rendered slightly smaller.

Examples:

```text
XANAX          $830,000 ($842,500)
Nessie Plushie  $10,000  ($64,000)
```

Missing resale data displays as `(-)` until the bounded resale queue populates it. A stale broad-market reference may remain visible for context but does not drive green/yellow/red profitability classification.

### Resale priority

The broad queue remains bounded to **one request per normal update**. It now prioritizes configured `visible=true` items among otherwise eligible stale/unpriced items. This lets Nessie/Cherry receive market references before hidden catalog items without increasing request frequency.

Xanax continues to use its existing independent/fresher resale path.

## Presentation architecture

New local-only script:

```text
@Resources/Scripts/VisibleItems.ps1
```

Runtime order:

```text
UpdateTracker
ShadowCollector (fail-soft)
LocalCatalog (fail-soft / local-only)
FinalizeState
VisibleItems (fail-soft / local-only)
visible heartbeat
ResaleQueue (fail-soft / max one request)
```

`VisibleItems.ps1` performs **no network calls**. It consumes already-existing:

- `observedMarkets` stock/foreign price;
- market-validity flags;
- local canonical metadata;
- `resaleCache`;
- saved travel profile/company stars;
- category-aware capacity/economics.

A VisibleItems failure must leave the existing Xanax state intact.

## Current first-release limitations

This is intentionally a narrow UI proof:

- existing 8-hour graphs remain **Xanax graphs**;
- existing departure/restock recommendation row remains **Xanax timing**;
- secondary rows show current stock, foreign price, Torn market reference and profitability/capacity context via tooltip;
- Nessie/Cherry remain non-optimizer-eligible;
- no country/category filters yet.

Do not imply secondary rows have independent trained departure timing until that modeling/presentation layer is deliberately added.

## Focused Windows acceptance

Pull current `main`, then run:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-VisibleItems.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-VisibleItemsTests.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-ResaleQueue.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-ResaleQueueTests.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-RainmeterSkin.ps1
```

Then run one normal production pass:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\@Resources\Scripts\RunUpdate.ps1 -Action Update
```

Inspect generated state without exposing local settings/API key:

```powershell
$state = @{}
Get-Content .\@Resources\Generated\state.kv | ForEach-Object {
  $i = $_.IndexOf('=')
  if ($i -gt 0) { $state[$_.Substring(0,$i)] = $_.Substring($i + 1) }
}

@(
  'UKMarketValue',
  'UKSecondaryName','UKSecondaryForeignPrice','UKSecondaryMarketValue','UKSecondaryStock','UKSecondaryCapacity','UKSecondaryPriceClass',
  'JPMarketValue',
  'JPSecondaryName','JPSecondaryForeignPrice','JPSecondaryMarketValue','JPSecondaryStock','JPSecondaryCapacity','JPSecondaryPriceClass'
) | ForEach-Object { '{0}={1}' -f $_, $state[$_] }
```

Expected identities:

```text
UKSecondaryName=Nessie Plushie
JPSecondaryName=Cherry Blossom
```

Market values may initially be `0`/display `-` if those items have not yet reached the bounded resale queue. Do not force repeated API calls merely to fill the display; normal one-minute updates now prioritize visible missing/stale prices.

Finally refresh Rainmeter and visually verify:

- no price/stock overlap;
- long out-of-stock text remains uncut;
- parenthesized market reference is visibly smaller/muted;
- Nessie appears only under UK;
- Cherry appears only under Japan;
- existing Xanax timing/graphs remain intact.

A screenshot is useful for layout acceptance because static tests cannot prove Rainmeter text geometry.

## After acceptance

Next phases:

1. country/category presentation filters;
2. travel-state target-country filtering and arrival countdown;
3. broader per-item timing/economics presentation as evidence matures;
4. full-country opportunity matrix;
5. `Optimal` bounded route scheduler only after sufficient availability/economic evidence exists.
