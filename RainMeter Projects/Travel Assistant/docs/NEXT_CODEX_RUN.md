# Next Codex Run: Persistent Filters, Pinning, and Ignore List

**Status: ACTIVE — PENDING TARGET-WINDOWS / RAINMETER ACCEPTANCE**

## Expansion rule

```text
collect broadly
show narrowly
optimize only after evidence/economics are ready
```

## Accepted baseline

The target Windows machine has already accepted:

- 11-country shadow collection;
- 232 provider country-item rows / 227 active markets at the last live check;
- 202 locally resolved item metadata rows;
- five verified legacy markets suppressed from new learning/resale/display work;
- bounded one-request-at-a-time broad Torn Item Market pricing;
- category-aware carrying capacity;
- four **independent** item cards:
  - UK Xanax;
  - UK Nessie Plushie;
  - Japan Xanax;
  - Japan Cherry Blossom;
- a global two-expanded-card cap;
- item-specific secondary graphs;
- foreign shop price followed by a smaller muted parenthesized Torn market reference.

The earlier subordinate-row composition is rejected and must not return.

## Current 0.4.0 candidate

### Horizontal filter bar

Immediately below the update/source line:

```text
ITEM  All ▾   TRIP SHORT MED LONG ▾   CAT All ▾   RESET
```

Two thin horizontal separators bound the bar.

The filter bar is presentation state only. It must never stop broad stock/history collection.

### Item filter

Clicking `ITEM` opens a detached checkbox popup.

Current UI limitation:

- the popup lists only items that the committed card renderer can currently display;
- this prevents users selecting one of the ~202 catalog items and seeing no card because generalized card enumeration is not implemented yet.

State persists in ignored `data/runtime/preferences.json` until reset.

### Trip bands

The 11 destinations currently use a presentation taxonomy:

```text
Short:
  Mexico
  Cayman Islands
  Canada

Medium:
  Hawaii
  United Kingdom
  Argentina
  Switzerland

Long:
  Japan
  China
  United Arab Emirates
  South Africa
```

These bands are filter labels only. Existing country travel-time/economics data remains authoritative.

`SHORT`, `MED`, and `LONG` are independent toggles. The adjacent `▾` opens a detached country popup for individual country exceptions inside enabled bands.

### Category filter

`CAT` opens a detached checkbox popup using categories represented by currently renderable cards.

Like Item selection, this is already stored generically so later generalized card enumeration can widen the available choices without changing the preference schema.

### Reset

`RESET` restores:

- Item = All;
- Short/Medium/Long = all enabled;
- all countries enabled;
- Category = All;
- profitable-only = off.

Reset deliberately preserves:

- pinned market;
- Ignore List;
- travel mode.

## Pin / favorite behavior

Presentation identity remains:

```text
country + itemId
```

Only one market may be pinned.

Current interaction:

- left-click item title / chevron: expand or collapse;
- right-click item title / chevron: pin or unpin;
- pinned card displays `★`;
- pinned card stays expanded;
- pinned card sorts to the top;
- pinned card consumes one of `MaxExpandedCards=2` slots;
- automatic collapse must never collapse the pinned card.

Pin overrides ordinary Item / Trip / Category / profitable-only presentation filters at home.

Priority rules:

```text
travel destination relevance
        >
Ignore List
        >
pin
        >
ordinary presentation filters
```

Therefore a pinned UK item must disappear while the user is traveling/abroad in Japan. The stored preference remains available for the next home/unfiltered view.

Pin state is persisted directly in ignored `preferences.json`. It is intentionally **not mirrored through `state.kv`**, because an older projected value could overwrite a just-clicked pin on the next one-second Lua update.

## Travel-context boundary

`TravelContext.ps1` now performs one bounded fail-soft Torn user request:

```text
/user?selections=travel,basic
```

It normalizes and projects:

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

Current use is destination-card filtering only.

Not yet implemented in this release:

- replacing static outbound flight duration with local arrival countdown;
- generalizing actionable timing while already traveling;
- broad all-country card rendering.

A transient travel-context failure preserves the last successful foreign filter rather than suddenly revealing irrelevant pinned cards.

## Settings additions

Top of Settings now includes:

```text
[ ] Show profitable items only
[ Ignore List... ]
```

Settings Save must merge the fields it owns into the existing preference object. It must never replace `preferences.json` with a narrow travel-mode-only object and erase pin/filter/ignore state.

### Profitable-only

For current primary Xanax cards, positive modeled trip profit gates visibility.

For current secondary Nessie/Cherry cards, profitability requires a fresh usable broad resale reference plus positive trip profit. Unknown/stale economics do not become profitable by assumption.

### Ignore List

Ignore List popup enumerates the complete local metadata catalog (currently 202 rows at the accepted baseline).

Ignored items:

- are hidden from the card view;
- cannot use pin to force display;
- are parked outside broad per-item Torn Item Market requests;
- become queue-eligible immediately after being unignored.

Ignore List does **not** suppress shared country-level Prometheus/YATA stock payloads. Those calls already return many items together, so filtering one item would not reduce provider requests and would destroy useful observation history.

## Resale priority / pending market values

Broad pricing remains:

```text
max requests per normal update: 1
broad freshness target:          6h
hidden/general failure backoff:  1h
visible/pinned failure retry:    5m
request timeout:                 6s
```

`ResalePriority.ps1` is local-only policy and runs immediately before the established `ResaleQueue.ps1`. It never makes a request itself.

This shorter visible-item retry addresses the observed Nessie `(-)` condition after Cherry successfully populated. It does not increase the global request rate.

## Runtime order

```text
UpdateTracker
ShadowCollector                 # fail-soft
LocalCatalog                    # local-only / fail-soft
FinalizeState
TravelContext                   # bounded / fail-soft, Update only
VisibleItems                    # local-only
FilterState                     # local-only preference projection
visible heartbeat
ResalePriority                  # local-only queue policy
ResaleQueue                     # fail-soft; max one request / Update
```

`ItemMetadata.ps1` remains manual-only and outside the heartbeat.

## Focused target-Windows acceptance

After pulling current `main`, run from the Travel Assistant project directory:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-Filters.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-FilterPreferenceTests.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-TravelContext.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Run-TravelContextTests.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-VisibleItems.ps1

powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\tests\Validate-RainmeterSkin.ps1
```

Then run one normal update before interacting with the new bar:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
  -File .\@Resources\Scripts\RunUpdate.ps1 -Action Update
```

Refresh Rainmeter and verify:

1. filter bar appears between Updated and the first card;
2. Item popup opens detached and persists selection;
3. Short/Med/Long toggles update immediately;
4. country popup respects enabled trip bands and persists individual selections;
5. Category popup persists selection;
6. Reset restores presentation filters while keeping pin / Ignore List;
7. right-clicking a card title or chevron shows `★`, pins it expanded, and moves it to the top;
8. expanding another card never auto-collapses the pinned card;
9. Settings shows profitable-only and Ignore List;
10. ignoring a visible item hides it and prevents broad resale work for it;
11. current destination filtering hides a pinned card from the wrong country when Torn reports traveling/abroad;
12. existing market-value typography, OOS text, graphs, and Xanax recommendations remain intact.

Do not call 0.4.0 accepted until those Windows/Rainmeter interactions are reported.

## Next after acceptance

1. generalize card enumeration beyond the four proof markets;
2. make Item/Category selectors expose the full filtered catalog once those cards can render;
3. replace outbound static flight duration with a locally ticking arrival countdown;
4. generalize per-item timing where evidence is sufficient;
5. build the broader opportunity matrix;
6. implement `Optimal` later as a bounded route scheduler, never as a simple profit sort.
