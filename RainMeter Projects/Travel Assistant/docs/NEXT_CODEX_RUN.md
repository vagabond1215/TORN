# Next Codex Run: Minimalist Optimal Next-Trip View

**Status: ACTIVE — PENDING TARGET-WINDOWS / RAINMETER ACCEPTANCE**

## Accepted baseline before this candidate

Already accepted on the target Windows machine:

```text
11-country shadow collection
232 provider country-item rows
232/232 provider names
202 distinct item IDs
202/202 categories resolved
5 verified legacy rows
227 active country-item markets
bounded one-request broad Torn Item Market queue
category-aware capacity
Airstrip general/Xanax capacity 18
Standard general/Xanax capacity 13
```

The earlier multi-card UI is no longer the target product.

## Current candidate: 0.5.0

Main UI is now one minimalist next-trip recommendation:

```text
Travel                                      SETTINGS >
Updated ...

ITEM All ▾   TRIP SHORT MED LONG ▾   CAT All ▾   RESET

OPTIMAL • <destination>              <expected value>
<arrival/out time> • <used/capacity> • <hit chance> • E loss • N loss
<item>          xN   <foreign price> (<Torn MV>)   <arrival probability>
[additional purchase rows only if required]
```

No UK/JP default card stack and no default stock graphs.

### Value basis

Default:

```text
100% Torn MV = itemmarket.item.average_price
no Item Market fee deduction
no minimum-profit timing gate
no minimum-margin timing gate
```

Optional Settings toggle:

```text
Use 95% MV profit calculation
```

It is OFF by default.

Price color:

```text
foreign <= selected MV basis -> green
foreign >  selected MV basis -> red
```

Negative-value items remain legal unless `Show profitable items only` is enabled.

Legacy `FinalizeState` economics are informational only and must not rewrite timing status or clear timing fields.

### Optimizer scope

Current implementation selects the best **next trip**, not a full multi-trip sequence.

It compares destination plans using:

- current active foreign markets;
- current foreign shop price;
- cached Torn MV;
- general/category capacity;
- travel method/time/cost;
- observed availability and restock history;
- modeled chance stock is available on arrival;
- Energy/Nerve waste policy;
- Item/Trip/Country/Category filters;
- Ignore List.

Route score is expected trip value normalized by trip duration. Full future optimization across repeated short trips, fewer long trips, and mixed-country sequences remains later work.

### Availability confidence

- From Torn/home or while outbound, a currently stocked item is actionable only after enough completed availability cycles exist to estimate arrival survival.
- If already abroad at the destination, fresh current stock is direct current-state evidence.
- Sold-out forecasting requires completed restock-delay + availability evidence.
- Forecasts never become history.
- Stale provider rows are excluded.

### Capacity

General capacity fills first. Matching category-only slots may then be used, e.g. qualifying Flower/Toy company bonuses.

### Energy / Nerve

Settings:

```text
Energy Waste  Allowed | Forbidden | Limited
Max Energy Loss

Nerve Waste   Allowed | Forbidden | Limited
Max Nerve Loss
```

Rules:

- If Energy current is already above natural maximum, Energy restriction is bypassed.
- Nerve never receives that stacking bypass.
- Unknown bars fail safe under Forbidden/Limited.
- Once already committed to a foreign destination, these constraints do not make destination purchase guidance disappear.

`TravelContext.ps1` obtains destination plus bars in one bounded request:

```text
/v2/user?selections=travel,basic,bars
```

### Filters / Ignore List

The bar remains:

```text
ITEM All ▾   TRIP SHORT MED LONG ▾   CAT All ▾   RESET
```

Item/Category popups now enumerate the active local catalog rather than the retired four-card proof set.

Trip taxonomy remains presentation-only:

```text
Short:  Mexico, Cayman Islands, Canada
Medium: Hawaii, United Kingdom, Argentina, Switzerland
Long:   Japan, China, UAE, South Africa
```

Ignore List uses the complete local metadata catalog. Ignored items are excluded from optimizer candidates and broad per-item MV requests but remain in shared provider stock/history collection.

### Settings popup

Main Settings opens the lightweight optimizer popup:

```text
[ ] Show profitable items only
[ ] Use 95% MV profit calculation
Energy Waste [Allowed/Forbidden/Limited]  Max Energy Loss
Nerve Waste  [Allowed/Forbidden/Limited]  Max Nerve Loss
[ Ignore List... ]  [ Profile / API... ]
```

`Profile / API...` opens the existing detailed capacity/company/API editor.

## Runtime order

```text
UpdateTracker
ShadowCollector
LocalCatalog
FinalizeState
TravelContext
OptimalRoute
FilterState
heartbeat
ResalePriority
ResaleQueue
```

Important:

- `OptimalRoute.ps1` is local-only.
- `VisibleItems.ps1` is not in production runtime.
- `ItemMetadata.ps1` remains manual-only.
- `ResalePriority.ps1` is local-only.
- `ResaleQueue.ps1` remains the sole broad Item Market request path, max one request/update.
- Optimizer MV blockers receive priority and a bounded five-minute failed-item retry policy; general catalog failures retain one-hour backoff.

## Target-Windows acceptance

From repository root:

```powershell
cd C:\Codex\TORN
git pull --ff-only origin main
git rev-parse --short HEAD

cd "C:\Codex\TORN\RainMeter Projects\Travel Assistant"
```

Run these focused static/deterministic checks:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-TravelAssistant.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-RainmeterSkin.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-Filters.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-TravelContext.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-TravelContextTests.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-OptimalRoute.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-OptimalRouteTests.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-ResaleQueue.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-ResalePriorityTests.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-FinalizeStateTests.ps1
```

Do not run the full aggregate suite unless one of these focused tests points to a broader compatibility regression.

Then run one production update:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\@Resources\Scripts\RunUpdate.ps1 -Action Update
```

Inspect only non-secret runtime summaries:

```powershell
$e = Get-Content .\data\runtime\engine-state.json -Raw | ConvertFrom-Json
$e.travelContext | Format-List state,destination,destinationCountryId,filterActive,lastSuccessAt,lastError
$e.optimizer | Format-List

Select-String .\@Resources\Generated\state.kv `
  -Pattern '^(Optimal|Travel|Energy|Nerve)'
```

Expected characteristics:

- no parser errors;
- `travelContext.lastError` empty after successful API call;
- Energy/Nerve fields are present when Torn supplies bars;
- optimizer records `lastRunAt`, MV basis, candidate route count, and either a selected country or learning reason;
- if many active items still lack fresh MV, `pricingPriorityItemIds` may be populated and the UI may say the MV queue is learning;
- this is normal and does not justify forcing hundreds of market requests.

Refresh Rainmeter and verify visually:

1. no four-card UK/Japan graph stack;
2. filter bar remains directly under Updated;
3. one compact Optimal route panel;
4. only purchase rows needed by the selected route are visible;
5. all item names share the same left alignment/font;
6. price format is `$foreign ($MV)` with parenthesized MV smaller/muted;
7. foreign price is green when <= selected MV basis, red otherwise;
8. no LOW_MARGIN warning blocks the recommendation;
9. Settings exposes Energy/Nerve policies, max loss controls, profitable-only, 95% MV, Ignore List, and Profile/API;
10. outbound travel shows a locally ticking arrival countdown;
11. while abroad, only the destination route is considered;
12. no route message overlaps a visible purchase row.

Send test output plus a screenshot before marking 0.5 accepted.

## Next after 0.5 acceptance

1. observe the broad MV queue until enough active catalog items have fresh MV to make all-country ranking useful;
2. refine availability probability/calibration from accumulating cycles;
3. validate category-capacity mixed-item plans on real Flower/Toy profiles if available;
4. add route diagnostics/tooltips only where they improve decisions without expanding the default surface;
5. later implement the true bounded multi-trip scheduler comparing repeated short, fewer long, and mixed-country sequences.
