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
ELIGIBLE opportunity candidates
        !=
VISIBLE ranked opportunities
```

- Collection remains broad across every valid provider row and all 11 foreign countries.
- Market identity is `country + itemId`.
- Provider presence is evidence about a feed, not proof a shop relationship is still active.
- Verified legacy relationships remain observable for provenance but receive no new history/resale/opportunity work.
- UI filters, Ignore List, sorting, profitability display, and travel destination never delete retained history.

## Current product: 0.6 ranked opportunity surface

The rejected 0.5 single `OPTIMAL` route card is **not** the active product surface. The later probability-weighted `OPTIMAL` presentation mode was also removed. Do not restore either concept to the user-facing UI.

Main Rainmeter UI:

```text
Travel                                      SETTINGS >
Updated ...

ITEM All v   TRIP SHORT MED LONG v   CAT All v   RESET
NAME   UPCOMING   GROSS PROFIT   PROFIT/HR          VIEWER >

#1  <item>   <country>                     <trip gross> <qty>
    <window>  <leave>  <hit likelihood>  <elapsed>  <foreign> (<MV>)  GRAPH
#2  <item>   <country>                     <trip gross> <qty>
    ...
```

Rules:

- Show a ranked list of evidence-backed `country:itemId` trade opportunities; do not collapse the primary UI to one recommended route.
- Visible ordering is selectable and persistent:
  - `NAME`: alphabetical item name, then destination.
  - `UPCOMING`: soonest modeled/current stock window first.
  - `GROSS PROFIT`: highest total trip gross first.
  - `PROFIT/HR`: gross trip profit divided by total elapsed hours.
- Modeled hit likelihood remains visible as a separate percentage. It is **not** folded into any hidden user-facing sort score.
- There is no `OPTIMAL`, Chance, or shortest-Time sort in the user-facing surface.
- Gross profit means `(selected MV basis - foreign price) × modeled purchasable quantity`; it intentionally does not subtract travel cost. Quantity must remain explicit enough that gross arithmetic is inspectable.
- Total elapsed time includes any required wait, outbound travel, return travel, and purchase buffer. If returning to Torn, remaining return time precedes the next outbound opportunity.
- While outbound/abroad to a recognized destination, visible opportunities are restricted to that destination.
- `traveling_unknown` / unresolved foreign destination must fail closed in the primary opportunity projection rather than suggesting an unrelated new outbound trip.
- Each visible row has an on-demand `GRAPH` action keyed by stable `country:itemId` identity.
- `VIEWER >` opens the broader market browser.
- Stock graphs use an 8-hour display with hourly markers. The last retained observation before the display cutoff is carried into the left edge so change-only history does not create a false blank plateau.
- Viewer work is local-only and never performs provider/Torn requests. It may repair a synthetic carried baseline for migration/retention continuity, but it must never invent a restock/sellout transition or turn a forecast into observed history.
- The one-second Lua loop is local-only and may update visibility/reflow/sorting but never poll APIs.
- The last complete opportunity/UI projection must remain visible during intermediate minute-update writes. Do not let the skin flash back to `Learning opportunities...` simply because `UpdateTracker` is still running.
- Sort controls must reorder the already-projected rows immediately in Lua. Persist the sort choice with a tiny local write; do not run the full opportunity evidence pass on every sort click.
- Keep stable rectangular hitboxes on text controls.

`OptimalRoute.ps1` remains a background compatibility/pricing-priority route model. Its name is not permission to reintroduce an `OPTIMAL` UI mode. `OpportunityState.ps1` is the primary presentation/ranking projection.

## Filters and ordering

Persistent local UI state lives in ignored `data/runtime/preferences.json`.

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
sortMode                     # name | upcoming | gross | profit_per_hour
```

Legacy sort migration:

```text
optimal -> profit_per_hour
profit  -> gross
time    -> upcoming
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
- Ignored items are excluded from opportunity/optimizer eligibility and broad per-item Torn MV requests.
- Shared country-level Prometheus/YATA stock collection remains broad because suppressing one item does not save that provider request.
- Ignore/unignore never deletes historical evidence.

## Value/profitability semantics

Profitability is ranking/context, **not permission to learn and not a timing-window gate**.

Default value basis:

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

Price/economic color is deliberately simple:

```text
foreign price <= selected MV basis  -> green
foreign price >  selected MV basis  -> red
```

Negative-value items remain legal candidates unless `Show profitable items only` is explicitly enabled. Profit/value details belong in visible context/tooltips; they must not erase stock timing/evidence.

Legacy `FinalizeState.ps1` economics are informational only and must not rewrite timing status or clear timing fields.

## Availability/evidence semantics

1. Prefer no opportunity over invented confidence.
2. `0 -> positive` is an observed restock; `positive -> 0` is an observed sellout.
3. Forecasts never become history.
4. History is isolated by `country + itemId`.
5. Foreign price is first-class evidence.
6. Current depletion may shorten support, never expand conservative historical support.
7. In-stock markets from Torn/home or in-flight require enough completed availability evidence to produce a modeled arrival probability.
8. If already at the destination, fresh current stock is direct current-state evidence.
9. Sold-out opportunities require completed sellout→restock plus availability evidence. Upcoming windows are derived from the overlap of observed historical live intervals after sellout.
10. Estimated restock quantity may use observed `0 -> positive` quantities.
11. Stale provider markets are not visible opportunity candidates.
12. Forecasted windows and presentation sorting never write observation/cycle history.
13. Change-only observation pruning must preserve one predecessor/baseline per market across the high-resolution retention boundary.
14. A prior `history_bootstrap`-only migration hole may be repaired to a carried `history_repair_baseline` using the market's recorded first-seen/current unchanged state. Such repair is continuity metadata, not an observed market transition.

## Energy / Nerve constraints

Travel context obtains bars in the existing bounded user request (`travel,basic,bars`).

Policies are independent:

```text
Energy Waste: Allowed | Forbidden | Limited
Max Energy Loss: N

Nerve Waste:  Allowed | Forbidden | Limited
Max Nerve Loss: N
```

- Loss is modeled natural regeneration that would be wasted over the full opportunity horizon, including wait/travel where relevant.
- If `energy.current > energy.maximum`, Energy waste policy is bypassed.
- Nerve does **not** receive that bypass even if current nerve is above maximum.
- Unknown bar data fails safe for any non-Allowed policy.
- Waste constraints filter new outbound opportunities.
- After travel is already committed to a recognized destination, waste constraints must not make destination purchase guidance disappear.

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

Opportunity quantity may use valid category-aware capacity. Positive explicit `profitability.capacityOverride` remains authoritative where supported.

## Travel context

`TravelContext.ps1` may make one bounded fail-soft Torn user request per normal update:

```text
/v2/user?selections=travel,basic,bars
```

It retains destination/travel timestamps plus Energy/Nerve bar fields. On transient failure preserve the last successful foreign restriction and bar context rather than releasing safety constraints because a request failed. Its diagnostic file is child-owned and must survive internally caught request failures.

While outbound/abroad to a recognized destination, opportunity candidates are restricted to that destination. On the return leg, the next outbound opportunity may be ranked with the remaining return time included in total elapsed time.

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

- prioritize background optimizer MV blockers;
- retain compatibility priority for configured visible/pinned seeds;
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
FinalizeState           # compatibility economics informational only
TravelContext           # one bounded user/bars request on Update
OptimalRoute            # local-only background route / MV-priority model
OpportunityState        # local-only primary ranking projection
FilterState             # local-only UI/freshness projection
heartbeat
ResalePriority          # local-only policy
ResaleQueue             # <= 1 market request
```

`VisibleItems.ps1`/old embedded card-graph enrichment is not part of production runtime. On-demand graph viewing is handled separately by `OpenItemViewer.ps1`. Item metadata network maintenance remains outside runtime.

## Runtime diagnostics / popup process contract

- Repo-local rolling log: `data/runtime/logs/travel-assistant.log`.
- Runtime/popup failures should be logged there with component and source context.
- Stale compact error markers may be cleared after successful component runs.
- Popups launch through hidden STA PowerShell and no visible console should remain open.
- Runtime log/history/preferences/generated files remain ignored and local.

## Secrets / local files

- API key and `config/settings.local.json` stay local/ignored.
- Runtime observations, cycles, caches, preferences, state, errors, and generated artifacts stay ignored/local.
- Never put the key in URL/process arguments when stdin/header transport is available.
- Do not broaden API permissions for convenience.

## Performance budget

- one-second Rainmeter loop: local only;
- sorting already-projected rows in Lua is local and immediate;
- serialized updater: roughly once/minute;
- shadow collection: no more often than ~120s unless revalidated;
- travel/bars: one bounded request per normal update;
- broad MV queue: at most one lower-priority request after heartbeat;
- viewer/graphs: on demand and local-only;
- no permanent background PowerShell/browser process.

## Browser notifications

Browser/Chrome notifications are a future optional companion feature. Do not duplicate the availability model in a browser component. When implemented, notifications should consume the accepted local opportunity projection/timing state, remain opt-in, dedupe repeated polls, and add no provider/Torn request path.

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

The 0.6 ranked opportunity implementation is **pending target-Windows/Rainmeter acceptance**. Do not call it accepted until focused parser/deterministic tests, one production update, working popups/sort controls, stable poll rendering, repaired viewer continuity, and a Rainmeter screenshot pass.

See `docs/NEXT_CODEX_RUN.md` for the current exact acceptance commands.
