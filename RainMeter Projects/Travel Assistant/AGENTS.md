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

## Connector-first execution

- Prefer the connected GitHub connector for repository inspection, edits, tests/contracts, and commits.
- Use the target Windows host only for actual Rainmeter rendering, Windows PowerShell behavior, local provider/API behavior, and resource checks that cannot be proven through repository inspection.
- Never claim Windows/Rainmeter/live-provider validation that did not run.
- Work only inside this subtree unless explicitly asked otherwise.
- Direct `main` edits are allowed while the project remains isolated/pre-use. Never force-push or rewrite unrelated work.

## Product direction

Travel Assistant is expanding from the UK/Japan Xanax proof into a generic Torn foreign-market assistant.

Keep these populations distinct:

```text
COLLECTED provider rows
        !=
ACTIVE market candidates
        !=
VISIBLE opportunities
        !=
OPTIMIZER candidates
```

### Collection

- Observe every valid foreign-shop row returned by live providers for every configured foreign country, irrespective of UI filters.
- Market identity is always `country + itemId`.
- Provider presence is evidence about the provider dataset, not proof that the relationship is still purchasable.
- Verified inactive/legacy markets remain observable for provenance but must not receive new learning/history/resale/display/optimizer work.
- UI filters, pinning, profitable-only, Ignore List, and current travel destination must not erase retained history.
- Shared country-level Prometheus/YATA collection remains broad even for ignored items because individual item suppression does not reduce those provider requests.

### Visibility

Accepted independent proof cards:

```text
United Kingdom + 206 Xanax
United Kingdom + 266 Nessie Plushie
Japan          + 206 Xanax
Japan          + 277 Cherry Blossom
```

Each visible opportunity is its own card. Never render Nessie/Cherry as subordinate rows inside a Xanax country card again.

Nessie/Cherry remain presentation-only until deliberately promoted:

```text
visible=true
enabled=false
optimizerEligible=false
```

They may show stock, foreign price, resale reference, category-aware economics, flight duration, and their own graph, but they must not inherit Xanax actionable departure timing.

### Current 0.4.0 presentation candidate

The filter bar sits below the update/source line:

```text
ITEM  All ▾   TRIP SHORT MED LONG ▾   CAT All ▾   RESET
```

Persistent UI state lives in ignored `data/runtime/preferences.json`.

Current fields:

```text
travelMode
pinnedMarket
itemFilterAll
selectedItemIds
selectedTripBands
selectedCountryIds
categoryFilterAll
selectedCategories
showProfitableOnly
ignoredItemIds
```

Settings Save must merge owned fields; it must never replace this preference object with a narrow travel-mode-only object.

Current Item/Category selectors expose only items/categories the four-card renderer can actually display. Generalize the renderer before exposing the full catalog through those selectors.

Trip bands are presentation taxonomy only:

```text
Short:  Mexico, Cayman Islands, Canada
Medium: Hawaii, United Kingdom, Argentina, Switzerland
Long:   Japan, China, UAE, South Africa
```

Do not use this taxonomy as travel-time/economics authority.

### Pin/favorite

- Only one `country:itemId` may be pinned.
- Right-click item title/expand glyph toggles the pin.
- Pinned card displays `★`, stays expanded, sorts first, and consumes one `MaxExpandedCards` slot.
- Automatic collapse must never collapse the pin.
- Pin overrides ordinary Item/Trip/Country/Category/profitable-only filters at home.
- Travel destination relevance and Ignore List override pin.
- Pin is persisted directly in `preferences.json`; do not mirror it through `state.kv` in a way that can overwrite a just-clicked pin with stale state.

Visibility precedence:

```text
travel destination relevance
        >
Ignore List
        >
pin
        >
ordinary presentation filters
```

### Ignore List

- Ignore popup should enumerate the complete local metadata catalog.
- Ignored items are hidden and excluded from broad per-item Torn Item Market pricing.
- Ignored items remain part of shared foreign-stock observation/history unless a future provider architecture can actually save a request by excluding them.
- Unignore must make the item eligible for resale work again without deleting prior evidence.

### Optimizer

`Optimal` remains a future scheduling layer, not a sort by profit/item or profit/trip.

Do not make a market optimizer-eligible until economics, capacity semantics, availability, current market validity, and evidence quality are adequate.

Eventually compare repeated short trips, fewer longer trips, and mixed-country sequences over a bounded planning horizon.

## Non-negotiable data/recommendation invariants

1. Prefer no recommendation over weak/unsafe advice.
2. `0 -> positive` is an observed restock; `positive -> 0` is an observed sellout. Forecasts never become history.
3. Keep history/model state isolated by `country + itemId`.
4. Foreign price is first-class evidence; radically different price regimes are not equivalent.
5. Current depletion may shorten safety but never expand conservative support beyond history.
6. `BEST_ODDS` is not `SAFE_WINDOW`.
7. Profitability gates timing, not learning.
8. Unknown economics are not zero economics.
9. Provider provenance is retained at normalization boundaries.
10. Collection/enrichment/presentation failures must fail gracefully and must not break the accepted Xanax path.
11. Runtime observations, cycles, caches, generated state/graphs, local preferences/settings, credentials, and errors stay ignored/local.
12. Storage/compute remain bounded. The one-second Rainmeter loop performs only local state/string/countdown/visibility/reflow work.
13. Verified inactive market overrides supersede provider presence for new learning/display/resale/optimizer work while preserving provenance/history.
14. Broad resale population must never create an API burst; missing/no-price responses remain unresolved.
15. Market/resale reference is distinct from foreign shop price. Display them distinctly and never overwrite one with the other.
16. UI filters never become collection filters.
17. Ignore List may suppress per-item resale API work but must not silently delete history or claim to save shared provider requests it cannot save.
18. Travel destination filtering may narrow presentation, never background learning.

## Current collection/catalog baseline

Accepted target-Windows baseline on 2026-08-21:

```text
Prometheus
11 countries
232 observed country-item provider rows
232 / 232 rows with provider names
202 distinct item IDs
202 / 202 categories resolved
5 verified legacy rows
227 active country-item markets
```

Current verified legacy rows:

```text
mexico:21
mexico:232
mexico:327
united_arab_emirates:383
united_arab_emirates:440
```

Do not hard-code these live counts as timeless constants.

## Item metadata contract

Catalog metadata network maintenance must not run inside the Rainmeter heartbeat.

Target-host attempts timed out for:

```text
v2 specific-items | 150 IDs | 20s
v2 specific-items |  40 IDs | 30s
classic torn/items bulk      | 12s
```

Therefore:

- `RunUpdate.ps1` must not invoke `ItemMetadata.ps1`;
- `ItemMetadata.ps1` remains explicit/manual maintenance only;
- do not keep increasing metadata timeout/batch size;
- normal catalog authority is committed/offline references plus provider names/verified overrides.

Current local precedence:

```text
richer manual Torn metadata
    > explicit config seed
    > verified item override
    > offline YATA-derived category snapshot
    > provider name + Unknown
```

## Broad resale contract

`ResaleQueue.ps1` must:

- run only for normal `Update` actions;
- run after the visible heartbeat;
- derive distinct items from active observed markets only;
- defensively skip legacy/inactive relationships;
- make at most one Torn Item Market request per run path;
- default to 60s attempt cadence, 6h broad freshness, 1h general failure backoff, 6s request timeout;
- use bounded `curl.exe --config -` with the API key only in stdin Authorization header;
- preserve successful cache rows across later failures;
- keep missing/zero outcomes unresolved.

`ResalePriority.ps1` runs locally before the queue and may:

- prioritize visible/pinned items;
- shorten failed visible/pinned retry eligibility to 5 minutes;
- park ignored IDs outside the queue horizon;
- release holds when unignored.

It must never make its own market request or increase the one-request cap.

## Capacity authority

Prefer current `/user/perks` for carrying capacity.

Mode base:

```text
Standard: 10
Airstrip/WLT/qualified Business: 15
```

A synced current-capacity bonus is authoritative for general/Xanax capacity and replaces legacy inferred general additions.

Category-specific effects excluded from general capacity remain isolated:

- Flower Shop 7★: +5 Flower only;
- Toy Shop 7★: +5 Plushie only;
- neither increases Xanax.

Accepted example:

```text
Airstrip general/Xanax = 18
Standard general/Xanax = 13
qualifying Airstrip Flower/Plushie = 23
qualifying Standard Flower/Plushie = 18
```

Positive explicit `profitability.capacityOverride` remains authoritative where supported.

## Travel context

`TravelContext.ps1` may make one small bounded fail-soft Torn user request per normal update to resolve travel/basic state.

Projected fields:

```text
TravelState
TravelDestination
TravelDestinationCountryId
TravelFilterActive
TravelMethod
TravelDepartedAt
TravelArrivalAt
TravelTimeLeft
```

Current use is presentation relevance. While traveling/abroad to a recognized destination, show only that country’s renderable cards even if another card is pinned.

On transient failure preserve the last successful foreign restriction.

Future arrival countdown must tick locally from stored timestamps; do not poll Torn every second.

## Runtime order

Current production order:

```text
UpdateTracker
ShadowCollector
LocalCatalog
FinalizeState
TravelContext
VisibleItems
FilterState
heartbeat
ResalePriority
ResaleQueue
```

Network catalog metadata remains outside this order.

## API keys / secrets

- API keys remain local and ignored; never commit them.
- Settings masks the key by default.
- Never ask the user to paste a full key into chat.
- Do not broaden permissions for convenience.
- Never put a key in process arguments or request URLs when stdin/header transport is available.

## Performance budget

- one-second Rainmeter work: local only;
- main serialized updater: about once/minute;
- shadow collection: no more often than ~120s unless revalidated;
- travel context: one bounded user request per normal update;
- broad resale: at most one lower-priority market request per normal update after heartbeat;
- item metadata network maintenance: manual-only;
- no permanent background PowerShell/browser processes.

## Distribution

The `.rmskin` builder is whitelist-based. It must include runtime scripts/config/catalog references and exclude:

```text
config/settings.local.json
API key
runtime preferences/history/state
cache/errors
generated graphs/state
```

Recipient-local preferences survive upgrades because runtime state is not packaged.

## Current validation boundary

Independent cards are visually accepted. Current `0.4.0` filter/pin/settings/travel-context candidate still requires target-Windows focused tests and Rainmeter interaction acceptance.

See `docs/NEXT_CODEX_RUN.md` for the exact commands and visual checks.
