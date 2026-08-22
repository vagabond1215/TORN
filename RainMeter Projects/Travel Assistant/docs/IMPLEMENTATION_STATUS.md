# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-21

**Active run:** 0.4.0 persistent filters, pinning, travel relevance, profitable-only, and Ignore List. See `docs/NEXT_CODEX_RUN.md`.

## Accepted foundation

Target-Windows evidence already covers:

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

- established UK/Japan Xanax collection/history/model path;
- current `/user/perks` general capacity behavior;
- Flower/Toy category-capacity isolation;
- one-request-at-a-time broad Torn Item Market transport;
- independent UK Xanax / Nessie and Japan Xanax / Cherry cards;
- global two-expanded-card cap;
- item-specific secondary graphs;
- parenthesized smaller/muted Torn market references.

The old subordinate Nessie/Cherry rows inside Xanax country cards are rejected and must not return.

## Current visible cards

```text
United Kingdom + Xanax
United Kingdom + Nessie Plushie
Japan          + Xanax
Japan          + Cherry Blossom
```

Nessie/Cherry remain:

```text
visible=true
enabled=false
optimizerEligible=false
```

They show live provider stock, foreign value, broad resale reference, category-aware economics, flight duration, and their own stock graphs. They still do not emit actionable Xanax-style departure timing.

## 0.4.0 filter bar — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

A horizontal data bar now sits below the update/source line:

```text
ITEM  All ▾   TRIP SHORT MED LONG ▾   CAT All ▾   RESET
```

Implemented controls:

- Item popup with All / individual renderable-item checkboxes;
- independent Short / Medium / Long trip-band toggles;
- country popup for individual destinations inside enabled trip bands;
- Category popup with All / individual renderable categories;
- Reset that restores presentation defaults but preserves pin, Ignore List, and travel mode.

All filter/preferences state is ignored/local in:

```text
data/runtime/preferences.json
```

No presentation filter changes background collection or retained history.

## Pin / favorite — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

Right-click an item title or expand glyph to toggle one pinned `country:itemId` market.

A pin:

- displays `★`;
- remains expanded;
- sorts first;
- consumes one of the two expanded-card slots;
- cannot be auto-collapsed.

Ordinary filters do not hide a pin at home, but travel destination and Ignore List do.

Pin state is persisted directly to `preferences.json` and is intentionally removed from the `state.kv` projection to prevent a one-second stale state refresh from undoing a just-clicked pin.

## Travel context — IMPLEMENTED, PENDING LIVE/RAINMETER ACCEPTANCE

`TravelContext.ps1` performs a bounded fail-soft Torn request to obtain travel/basic state and projects:

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

Current effect: while traveling/abroad to a recognized foreign destination, wrong-country cards—including a pinned card—are hidden.

A transient failure keeps the previous successful foreign restriction.

Not yet implemented:

- outbound arrival countdown in place of static flight duration;
- full all-country card rendering;
- travel-aware per-item timing recommendations.

## Settings additions — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

Settings now includes at the top:

```text
[ ] Show profitable items only
[ Ignore List... ]
```

Settings Save now merges preference-owned fields rather than replacing `preferences.json` with only travel mode.

### Profitable-only

Current primary cards require positive modeled trip profit. Current secondary cards require usable/fresh broad resale economics plus positive trip profit.

Unknown economics are not treated as profitable.

### Ignore List

Ignore popup uses the complete local item metadata table, currently 202 rows at the accepted baseline.

Ignored items are:

- hidden from view;
- unable to force display through pin;
- parked outside broad per-item Torn Item Market requests.

Shared Prometheus/YATA country-stock collection continues because individual item suppression would not reduce those shared provider calls.

## Broad resale retry improvement

A target-Windows screenshot showed Cherry successfully populated while Nessie remained `(-)`. This is consistent with Nessie entering the normal one-hour failure backoff.

`ResalePriority.ps1` now applies:

```text
visible/pinned failed item:    5-minute retry eligibility
hidden/general failed item:   60-minute backoff
ignored item:                 parked outside queue
```

The queue still performs at most one Torn Item Market request per normal update.

## Runtime order

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

Important boundaries:

- `VisibleItems`, `FilterState`, and `ResalePriority` are local-only;
- `TravelContext` is bounded/fail-soft;
- broad resale remains one-request-at-a-time after heartbeat;
- `ItemMetadata.ps1` remains outside normal Rainmeter polling.

## Current validation boundary

Connector-authored code and focused tests are committed. The new 0.4.0 UI has **not** yet been accepted on the target Windows/Rainmeter host.

Required focused checks:

```text
Validate-Filters.ps1
Run-FilterPreferenceTests.ps1
Validate-TravelContext.ps1
Run-TravelContextTests.ps1
Validate-VisibleItems.ps1
Validate-RainmeterSkin.ps1
```

Then run one normal `RunUpdate.ps1 -Action Update`, refresh Rainmeter, and exercise the Item/Trip/Country/Category/Reset/pin/Settings/Ignore interactions.

Do not claim 0.4.0 accepted until the user reports those checks.

## Next after acceptance

1. generalize independent card enumeration beyond the four proof markets;
2. expose the full relevant catalog through Item/Category filters once cards can render it;
3. add locally ticking outbound arrival countdown;
4. generalize timing/economics per item as evidence allows;
5. build full-country opportunity presentation;
6. implement `Optimal` later as a bounded route scheduler, not a simple sort.
