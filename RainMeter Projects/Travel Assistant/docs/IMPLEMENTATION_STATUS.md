# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-21

**Active run:** 0.5.0 minimalist next-trip optimizer. See `docs/NEXT_CODEX_RUN.md`.

## Accepted data foundation

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

- provider-name enrichment on every observed market;
- offline category/catalog authority;
- bounded one-request-at-a-time Torn Item Market pricing;
- `/user/perks` general capacity behavior;
- Flower/Toy category-capacity isolation;
- Airstrip general/Xanax 18 and Standard 13 on the target profile.

The 0.4 independent-card/graph surface was an intermediate proof and is no longer the active product direction.

## 0.5 minimalist UI — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

Main skin now shows one compact selected next trip and only its purchase rows.

```text
Travel                                      SETTINGS >
Updated ...
ITEM All ▾   TRIP SHORT MED LONG ▾   CAT All ▾   RESET

OPTIMAL • destination                 expected value
arrival/out • slots • hit chance • Energy loss • Nerve loss
item      xN    foreign price (Torn MV)    modeled arrival chance
```

- no default UK/JP card stack;
- no default stock graphs;
- item names use one left-aligned column and consistent typography;
- parenthesized MV is smaller/muted;
- route body and learning/no-route message never overlap.

## Next-trip optimizer — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

`OptimalRoute.ps1` is local-only and consumes:

- active observed foreign markets;
- canonical local item metadata;
- Torn MV cache (`average_price`);
- current foreign price/stock;
- retained restock/sellout cycles;
- travel time/cost;
- general/category carrying capacity;
- current destination and Energy/Nerve bars;
- persistent filters and Ignore List.

It produces one best **next-trip** plan. This is not yet the eventual multi-trip sequence scheduler.

Availability behavior:

- trained in-stock market: probability stock survives until arrival from completed availability durations;
- at destination: fresh current stock is direct evidence;
- sold out: requires completed restock-delay + availability evidence;
- insufficient history: learning, not fake confidence;
- stale provider market: excluded.

Route scoring currently uses expected trip value normalized by trip duration.

## Value semantics — IMPLEMENTED

Default optimizer basis:

```text
100% Torn MV
0% Item Market fee deduction
0 minimum profit gate
0 minimum margin gate
negative-value candidates allowed
```

Optional setting uses 95% MV.

Price color:

```text
foreign <= chosen MV basis -> green
foreign > chosen MV basis  -> red
```

`Show profitable items only` explicitly removes non-positive item spreads. Without it, negative-value purchases remain legal candidates.

Legacy `FinalizeState.ps1` was changed so economics are informational only and do not rewrite/clear timing state.

## Energy / Nerve constraints — IMPLEMENTED

Preferences/UI support independently:

```text
Energy Waste: Allowed / Forbidden / Limited
Max Energy Loss
Nerve Waste:  Allowed / Forbidden / Limited
Max Nerve Loss
```

`TravelContext.ps1` now requests `travel,basic,bars` in the same bounded user call and normalizes Energy/Nerve bar values.

Special rule:

- Energy current > natural maximum => bypass Energy waste restriction.
- Nerve receives no equivalent bypass.
- unknown bars fail safe for non-Allowed policies.

## Filters / Ignore List — IMPLEMENTED

The horizontal Item / Trip / Country / Category controls remain persistent/local.

Item/Category popups use the active local catalog instead of the old four-card set.

Ignore List:

- complete local metadata catalog;
- excluded from optimizer;
- excluded from broad per-item MV requests;
- shared provider stock/history still collected.

Trip bands remain presentation taxonomy only.

## Broad resale priority — IMPLEMENTED

Still one Torn Item Market request maximum per normal update.

Priority now includes optimizer MV blockers (`engine.optimizer.pricingPriorityItemIds`).

```text
optimizer/configured priority failure retry: 5m
unrelated/general failure backoff:             1h
ignored item:                                  parked
broad MV freshness:                            6h
request timeout:                               6s
```

`ResalePriority.ps1` remains local-only and never makes a request.

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

`VisibleItems.ps1` is retired from production runtime. `ItemMetadata.ps1` remains manual-only.

## Settings surface

Main Settings now opens a lightweight optimizer dialog:

```text
Show profitable items only
Use 95% MV profit calculation
Energy Waste + Max Energy Loss
Nerve Waste + Max Nerve Loss
Ignore List...
Profile / API...
```

The existing detailed settings editor remains behind `Profile / API...` for API key, profile, current capacity and company/travel-mode controls.

## Validation status

The user-reported 0.4 validator defects were fixed in the 0.5 validators:

- stale travel-context exact-string check removed/replaced;
- invalid `$launcherName:` strict parser interpolation fixed with safe literal handling.

0.5 still requires target-Windows validation. Do not mark accepted until the focused tests, one normal production update, and a Rainmeter screenshot pass.

See `docs/NEXT_CODEX_RUN.md` for exact commands.

## After 0.5 acceptance

1. let broad MV coverage improve without increasing API rate;
2. calibrate availability probabilities as cycles accumulate;
3. validate real mixed general/category capacity plans;
4. keep default UI minimal while improving tooltips/diagnostics;
5. later build the bounded multi-trip sequence scheduler comparing repeated short, long and mixed-country route sequences.
