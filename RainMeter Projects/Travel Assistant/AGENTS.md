# Travel Assistant Agent Instructions

These instructions apply to the entire `RainMeter Projects/Travel Assistant/` subtree.

## Read order

Before changing code or data, read:

1. `AGENTS.md`
2. `docs/README.md`
3. `docs/NEXT_CODEX_RUN.md`
4. `docs/ARCHITECTURE.md`
5. `docs/IMPLEMENTATION_STATUS.md`
6. `Readme.md`

If older plans conflict with an **ACTIVE** `NEXT_CODEX_RUN.md`, follow the active run while preserving every invariant here.

## Execution

- Prefer the connected GitHub connector for repository inspection/edits/contracts/commits.
- Use the target Windows host only for real Rainmeter, Windows PowerShell, and live provider/Torn validation.
- Never claim Windows/live validation that did not run.
- Work only inside this subtree unless explicitly broadened.
- Direct `main` edits are allowed; never force-push or rewrite unrelated work.
- Never expose/request an API key or full local settings file.

## Core population split

Never conflate:

```text
COLLECTED provider rows
        !=
ACTIVE market relationships
        !=
OPTIMIZER candidates
        !=
CURRENT recommended purchase rows
```

- Collection remains broad across every valid provider row and all 11 foreign countries.
- Market identity is `country + itemId`.
- Provider presence is evidence about a feed, not proof a shop relationship is still active.
- Verified legacy relationships remain observable for provenance but receive no new history/resale/optimizer work.
- UI filters, Ignore List, profitability display, and travel destination never delete retained history.

## Current product: 0.5 minimalist next-trip optimizer

The rejected 0.4 four-card/graph layout is **not** the active product surface.

Main Rainmeter UI is intentionally compact:

```text
Travel                                      SETTINGS >
Updated ...

ITEM All ▾   TRIP SHORT MED LONG ▾   CAT All ▾   RESET

OPTIMAL • <country>                    <expected value>
<arrival/out> • <capacity> • <hit chance> • <Energy loss> • <Nerve loss>
<item>             xN   <foreign price> (<Torn MV>)   <arrival chance>
[additional purchase rows only if the selected route needs them]
```

Rules:

- Show only the item(s) the selected next trip should purchase.
- Do not restore destination card stacks or default graphs without an explicit product-direction change.
- Item names share one left-aligned column with consistent typography/padding.
- Foreign shop price is primary; Torn MV appears immediately after it in parentheses, smaller and muted.
- The one-second Lua loop is local-only and may update countdowns/reflow strings but never poll APIs.

The 0.5 optimizer is a **next-trip planner**, not yet the final multi-trip sequence scheduler. Future work may compare repeated short trips, fewer long trips, and mixed-country sequences over a bounded horizon; do not overclaim the current single-route scorer as that final scheduler.

## Filters

Persistent local filter/preferences state lives in ignored `data/runtime/preferences.json`.

Current schema includes:

```text
travelMode
pinnedMarket                 # legacy/migration compatibility; no active card UI
itemFilterAll
selectedItemIds
selectedTripBands
selectedCountryIds
categoryFilterAll
selectedCategories
showProfitableOnly
ignoredItemIds
use95PercentMarketValue
energyWastePolicy
maxEnergyLoss
nerveWastePolicy
maxNerveLoss
```

Item and Category popups use the active local catalog, not only old proof-card seeds.

Trip bands are presentation/filter taxonomy only:

```text
Short:  Mexico, Cayman Islands, Canada
Medium: Hawaii, United Kingdom, Argentina, Switzerland
Long:   Japan, China, UAE, South Africa
```

Never use these labels as travel-time/economics authority.

### Ignore List

- Enumerates the complete local metadata catalog when available.
- Ignored items are excluded from optimizer eligibility and broad per-item Torn MV requests.
- Shared country-level Prometheus/YATA stock collection remains broad because suppressing one item does not save that provider request.
- Ignore/unignore never deletes historical evidence.

## Value/profitability semantics

Profitability is ranking/context, **not permission to learn and not a timing-window gate**.

Default route value basis:

```text
sell basis = 100% Torn MV (itemmarket.item.average_price)
Item Market fee deduction = 0
minimum profit gate = 0
minimum margin gate = 0
```

Optional preference:

```text
Use 95% MV profit calculation = OFF by default
```

Price color is deliberately simple:

```text
foreign price <= selected MV basis  -> green
foreign price >  selected MV basis  -> red
```

No LOW_MARGIN yellow blocker in the minimalist optimizer.

Negative-value items remain legal optimizer candidates unless `Show profitable items only` is explicitly enabled. Profit/value details belong in tooltip/context; they must not erase stock timing/evidence.

Legacy `FinalizeState.ps1` economics are informational only and must not rewrite timing status or clear timing fields.

## Availability/evidence semantics

1. Prefer no recommendation over invented confidence.
2. `0 -> positive` is an observed restock; `positive -> 0` is an observed sellout.
3. Forecasts never become history.
4. History is isolated by `country + itemId`.
5. Foreign price is first-class evidence.
6. Current depletion may shorten support, never expand conservative historical support.
7. In-stock markets from Torn/home or in-flight require enough completed availability evidence to produce a modeled arrival probability.
8. If already at the destination, fresh current stock is direct current-state evidence.
9. Sold-out arrival forecasts require completed sellout→restock plus availability evidence; estimated restock quantity may use observed 0→positive quantities.
10. Stale provider markets are not optimizer candidates.

## Energy / Nerve constraints

Travel context obtains bars in the existing bounded user request (`travel,basic,bars`).

Policies are independent:

```text
Energy Waste: Allowed | Forbidden | Limited
Max Energy Loss: N     # used when Limited

Nerve Waste:  Allowed | Forbidden | Limited
Max Nerve Loss: N      # used when Limited
```

- Loss is modeled natural regeneration that would be wasted during the planned trip horizon.
- If `energy.current > energy.maximum`, Energy waste policy is bypassed (stacking for war/happy-jump use cases).
- Nerve does **not** receive that bypass even if current nerve is above maximum.
- Unknown bar data fails safe for any non-Allowed policy.
- After travel is already committed to a destination, waste constraints must not make destination purchase guidance disappear.

## Capacity authority

Prefer current `/user/perks` sync for carrying capacity.

Mode base:

```text
Standard: 10
Airstrip/WLT/qualified Business: 15
```

Accepted synced example:

```text
Airstrip general/Xanax = 18
Standard general/Xanax = 13
```

Category-only company effects remain isolated:

- Flower Shop 7★: +5 Flower only.
- Toy Shop 7★: +5 Plushie only.
- Neither increases Xanax/general capacity.

An optimizer route fills general slots first, then may use valid category-only slots on matching item categories. Positive explicit `profitability.capacityOverride` remains authoritative where supported.

## Travel context

`TravelContext.ps1` may make one bounded fail-soft Torn user request per normal update:

```text
/v2/user?selections=travel,basic,bars
```

It retains destination/travel timestamps plus Energy/Nerve bar fields. On transient failure preserve the last successful foreign restriction and bar context rather than releasing safety constraints because a request failed.

While outbound/abroad to a recognized destination, optimizer candidates are restricted to that destination. On the return leg, the next outbound route is deferred until arrival. Arrival countdown ticks locally from stored timestamps.

## Catalog baseline

Accepted target-Windows baseline on 2026-08-21:

```text
Prometheus
11 countries
232 observed country-item provider rows
232/232 provider names
202 distinct item IDs
202/202 categories resolved
5 verified legacy rows
227 active country-item markets
```

Verified legacy rows:

```text
mexico:21
mexico:232
mexico:327
united_arab_emirates:383
united_arab_emirates:440
```

Do not hard-code these live counts as timeless constants.

Catalog network maintenance remains manual-only because target-host Torn metadata requests repeatedly timed out. `RunUpdate.ps1` must not invoke `ItemMetadata.ps1`.

Local metadata precedence:

```text
richer manual Torn metadata
    > explicit config seed
    > verified item override
    > offline category snapshot
    > provider name + Unknown
```

## Broad resale/MV queue

`ResaleQueue.ps1`:

- runs after visible heartbeat;
- active relationships only;
- at most one Torn Item Market request per update;
- default cadence 60s, freshness 6h, general failure backoff 1h, timeout 6s;
- key only via stdin curl config + Authorization header;
- successful cache survives later failures;
- missing/zero price remains unresolved.

`ResalePriority.ps1` is local-only and may:

- prioritize `engine.optimizer.pricingPriorityItemIds`;
- retain compatibility priority for configured visible/pinned items;
- shorten failed priority-item retry eligibility to 5 minutes;
- park ignored IDs outside the queue;
- release synthetic holds immediately on unignore.

It must never make its own request or increase the one-request cap.

## Runtime order

Current production order:

```text
UpdateTracker
ShadowCollector
LocalCatalog
FinalizeState           # compatibility economics are informational only
TravelContext           # one bounded user/bars request on Update
OptimalRoute            # local-only
FilterState             # local-only
heartbeat
ResalePriority          # local-only
ResaleQueue             # <= 1 market request
```

`VisibleItems.ps1`/card-graph enrichment is no longer part of production runtime. Item metadata network maintenance remains outside runtime.

## Secrets / local files

- API key and `config/settings.local.json` stay local/ignored.
- Runtime observations, cycles, caches, preferences, state, errors, and generated artifacts stay ignored/local.
- Never put the key in URL/process arguments when stdin/header transport is available.
- Do not broaden API permissions for convenience.

## Performance budget

- one-second Rainmeter loop: local only;
- serialized updater: roughly once/minute;
- shadow collection: no more often than ~120s unless revalidated;
- travel/bars: one bounded request per normal update;
- broad MV queue: at most one lower-priority request after heartbeat;
- no permanent background PowerShell/browser process.

## Distribution

`.rmskin` packaging is whitelist-based. It must include runtime scripts/config/catalog references and exclude:

```text
config/settings.local.json
API key
runtime preferences/history/state
cache/errors
generated state/graphs
```

## Current validation boundary

The 0.5 minimalist optimizer implementation is **pending target-Windows validation**. Do not call it accepted until the focused parser/deterministic tests, one production update, and a Rainmeter screenshot pass.

See `docs/NEXT_CODEX_RUN.md` for the current exact acceptance commands.
