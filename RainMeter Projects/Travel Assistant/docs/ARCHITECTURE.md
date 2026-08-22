# Travel Assistant Architecture

## Purpose

Travel Assistant is a lightweight Rainmeter-facing Torn foreign-market decision system. It separates broad observation from current market validity, presentation, and eventual route optimization.

```text
COLLECTED provider rows
        !=
ACTIVE market candidates
        !=
VISIBLE opportunities
        !=
OPTIMIZER candidates
```

The accepted visible proof now consists of four independent item cards: UK Xanax, UK Nessie Plushie, Japan Xanax, and Japan Cherry Blossom. The current `0.4.0` candidate adds persistent presentation filters, one pinned market, travel-destination suppression, profitable-only view, and a full-catalog Ignore List.

## Layering

```text
Live foreign-stock providers
        ↓
provider normalization
        ↓
provider-observed country + itemId rows
        ↓
verified market-validity overrides
        ↓
active-market bounded history / cycle detection
        ↓
local offline item metadata catalog
        ↓
bounded/staggered resale cache
        ↓
category-aware capacity/economics
        ↓
primary recommendation state
        ↓
travel context
        ↓
local visible-item enrichment
        ↓
local preference/filter projection
        ↓
Rainmeter item-card presentation
        ↓
future generalized card enumeration / optimizer
```

Settings and local preferences are side inputs. They never rewrite observed history.

## Market identity and validity

Market identity is always:

```text
country + itemId
```

Provider presence is evidence about the provider dataset, not proof that a foreign shop still sells the item. Verified exceptions in `config/foreign-market-overrides.json` supersede provider presence for new learning/display/resale/optimizer work while preserving provenance/history.

Accepted live baseline:

```text
provider:                    prometheus
countries:                   11
provider country-item rows:  232
verified legacy rows:          5
active markets:              227
provider names:              232 / 232
item IDs:                    202
categories resolved:         202 / 202
```

These counts are observations, not timeless constants.

Observed truth remains:

```text
0 -> positive = observed restock
positive -> 0 = observed sellout
```

Predictions never become historical truth.

## Collection

`UpdateTracker.ps1` retains the established UK/Japan Xanax model path.

`ShadowCollector.ps1` observes all 11 foreign countries at a default 120-second cadence and protects current primary markets from duplicate history writes.

Presentation filters, pinning, travel destination, profitable-only, and Ignore List do **not** stop shared provider observation. Collection stays broader than visibility.

Default retention:

- raw observations: ~48h;
- completed cycles: ~90d;
- visible graphs: 8h.

The live stale threshold is a recommendation-safety guard, not retention.

## Offline catalog

Runtime Torn item-catalog metadata calls are prohibited from the heartbeat after repeated target-host timeouts.

`LocalCatalog.ps1` is local-only. Current precedence:

```text
richer manual Torn metadata
        >
config/items.json seed
        >
verified item override
        >
offline YATA-derived category snapshot
        >
provider name + Unknown
```

Committed references:

```text
config/foreign-item-categories.json
config/foreign-market-overrides.json
```

The current 202 observed item IDs resolve locally. Newly observed unknown IDs remain unresolved until verified; names are not used to guess categories.

## Resale-price architecture

The primary Xanax updater keeps its independent/fresher Torn Item Market path.

`ResaleQueue.ps1` fills shared `resaleCache` for active distinct items with at most one bounded Torn Item Market request per normal update.

Defaults:

```text
minimum attempt interval:       60s
broad freshness target:          6h
hidden/general failure backoff:  1h
request timeout:                 6s
requests per run path:           1
```

`ResalePriority.ps1` is a local-only policy step immediately before the queue. It:

- prioritizes configured visible and pinned item IDs;
- allows failed visible/pinned items back into the existing queue after 5 minutes;
- parks ignored item IDs outside the queue horizon;
- releases an ignored hold immediately after unignore;
- never performs a network request.

Therefore visible-item urgency changes ordering/backoff only, never the global request cap.

Successful cache row:

```text
price
lowest
average
fetchedAt
source=torn_itemmarket
```

Missing/zero price remains unresolved.

## Capacity/economics authority

General capacity prefers current `/user/perks` plus travel-mode base:

```text
Standard: 10
Airstrip/WLT/qualified Business: 15
```

A synced current-capacity bonus is authoritative for general/Xanax capacity.

Accepted example:

```text
Airstrip general/Xanax = 18
Standard general/Xanax = 13
```

Category-specific company effects excluded from the general number are applied only to matching items:

```text
Flower Shop 7★ -> +5 Flower
Toy Shop    7★ -> +5 Plushie
```

Thus a qualifying Airstrip Flower/Plushie capacity can be 23 while Xanax remains 18. A positive explicit `profitability.capacityOverride` remains authoritative.

## Independent card presentation

Current renderable market identities:

```text
united_kingdom:206  Xanax
united_kingdom:266  Nessie Plushie
japan:206           Xanax
japan:277           Cherry Blossom
```

Every card owns:

- its own border/background;
- country flag;
- item name;
- foreign shop price;
- smaller muted parenthesized Torn Item Market reference;
- stock/OOS header;
- expand/collapse state.

The global default is:

```text
MaxExpandedCards=2
```

Secondary graphs are generated locally from retained `country + itemId` observations. Nessie/Cherry remain presentation-only and do not inherit actionable Xanax departure timing.

## Local preference architecture

Persistent UI state lives only in ignored:

```text
data/runtime/preferences.json
```

Current schema fields:

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

Settings must merge owned fields into this object; it must never overwrite the object with only travel mode.

### Filter bar

The current bar is:

```text
ITEM  All ▾   TRIP SHORT MED LONG ▾   CAT All ▾   RESET
```

Item and Category selectors currently enumerate only renderable card items/categories. The preference schema is generic and should widen when generalized card enumeration exists.

Trip bands are presentation taxonomy only:

```text
Short:  Mexico, Cayman Islands, Canada
Medium: Hawaii, United Kingdom, Argentina, Switzerland
Long:   Japan, China, United Arab Emirates, South Africa
```

They never replace country travel-time/economics authority.

Filter popups are detached WinForms processes. Popup work is local-only.

### Filter precedence

Visibility precedence:

```text
travel destination relevance
        >
Ignore List
        >
pin
        >
Item / Trip / Country / Category / profitable-only filters
```

A pin therefore keeps one card at the top/expanded at home but cannot force a wrong-destination or ignored card into view.

### Pin state

One market identity may be pinned. Right-clicking an item title/chevron toggles the pin. A pin displays `★`, remains expanded, sorts first, and consumes an expanded-card slot.

Pin state is persisted directly to `preferences.json` and intentionally not mirrored through `state.kv`; stale projected pin state must never overwrite a just-clicked pin.

### Ignore List

Ignore List enumerates the full local metadata catalog.

Ignored items:

- are hidden;
- cannot be forced visible by pin;
- are excluded from broad per-item Torn market-price work.

Ignore List does not suppress shared country-level Prometheus/YATA payloads because doing so would not reduce those provider requests and would unnecessarily stop learning.

## Travel context

`TravelContext.ps1` uses one bounded fail-soft Torn request to `/user?selections=travel,basic` and projects:

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

Current use: force visible cards to the active foreign destination while traveling/abroad.

On transient failure, preserve the last successful foreign context rather than revealing irrelevant cards.

Future presentation work may locally tick an arrival countdown from `arrivalAt/timeLeft`; it must not add per-second API polling.

## Runtime order

```text
UpdateTracker
      ↓
ShadowCollector              # fail-soft
      ↓
LocalCatalog                 # local-only / fail-soft
      ↓
FinalizeState
      ↓
TravelContext                # bounded / fail-soft, Update only
      ↓
VisibleItems                 # local-only
      ↓
FilterState                  # local-only state.kv projection
      ↓
visible heartbeat
      ↓
ResalePriority               # local-only policy
      ↓
ResaleQueue                  # max one request, Update only
```

`ItemMetadata.ps1` remains explicit/manual maintenance only.

## Performance

- one-second Rainmeter work: local state/string/countdown/visibility/reflow only;
- serialized main update: about once/minute;
- shadow provider observation: no more often than ~120s unless revalidated;
- visible-item/filter enrichment: local-only;
- travel context: one bounded call per normal main update;
- broad resale: max one bounded Torn market request per normal update after heartbeat;
- no permanent background PowerShell/browser processes.

## Distribution

The whitelist `.rmskin` builder includes runtime scripts and committed config/catalog references while excluding:

- API key / `settings.local.json`;
- `data/runtime/preferences.json` and all runtime state/history;
- generated graphs/state;
- local caches/errors.

Recipients therefore start with default filters/pin/ignore state and provide their own API key.

## Future `Optimal`

`Optimal` is a scheduling layer above per-opportunity modeling. It must compare repeated short trips, longer trips, and mixed-country sequences over a bounded horizon using market validity, economics, capacity, travel cost/time, availability evidence, confidence/freshness, and opportunity cost.

Never implement it as a simple profit-per-item or profit-per-trip sort.
