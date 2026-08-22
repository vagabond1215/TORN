# Travel Assistant Implementation Status

**Checkpoint:** 2026-08-22

**Active run:** 0.6.0 compact opportunity surface. See `docs/NEXT_CODEX_RUN.md`.

## Accepted data foundation

Previously target-Windows validated foundation:

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

- provider-name enrichment;
- offline category/catalog authority;
- bounded one-request Torn Item Market pricing;
- `/user/perks` general capacity behavior;
- Flower/Toy category-capacity isolation;
- Airstrip general/Xanax 18 and Standard 13 on the target profile.

## 0.6 compact opportunity UI — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

Primary controls:

```text
ITEM All v   TRIP SHORT MED LONG v   CAT All v   RESET
NAME   UPCOMING   GROSS PROFIT   PROFIT/HR          VIEWER >
```

Visible rows are now designed as:

```text
[FLAG]  item                                    $gross   v
[time]  current/window   leave   chance/LEARNING   foreign (MV)
```

Changes implemented:

- retired visible row rank numbers;
- retired country code/name from the row body;
- retired duplicate center elapsed-time text;
- moved elapsed/time text to a white strip under a vector destination flag;
- removed visible `gross` and `xN` suffixes from the gross dollar field;
- retained quantity internally and in tooltips for economic inspection;
- replaced `GRAPH` word with a compact `v`/`^` expansion control.

Flags are Rainmeter Shape approximations for all 11 destinations and require no binary image assets.

## Inline card graph — IMPLEMENTED, PENDING WINDOWS ACCEPTANCE

`RenderInlineGraph.ps1` renders retained 8-hour stock history to a small generated Rainmeter Shape-path spec.

`StateReader.lua`:

- expands the selected card in-place;
- shifts lower rows down and grows panel height;
- allows only one expanded graph at a time;
- collapses the current graph when another card opens;
- tracks the expanded market by stable `country:itemId` through sorting;
- refreshes the open graph locally around once per minute.

The existing Viewer launcher distinguishes:

```text
inline_<country:itemId> -> RenderInlineGraph.ps1, no popup
ordinary/empty key      -> standalone Item Viewer popup
```

Inline graph viewing makes no network request and does not write observation/cycle history.

## Standalone Viewer — RETAINED

`VIEWER >` is still a separate WinForms market browser with:

- broad market dropdown;
- full 8-hour graph;
- hourly markers;
- restock/sellout diagnostics;
- truthful zero-stock axis;
- retained baseline repair.

The standalone Viewer is not replaced by card expansion.

## Current in-stock learning semantics — IMPLEMENTED

Fresh observed stock is now allowed to remain visible before arrival-survival evidence is trained.

For current in-stock markets:

- known likelihood -> percentage;
- unknown likelihood -> `LEARNING`;
- unknown likelihood no longer causes the row to be dropped.

Gross and profit/hour still derive from current stock/capacity, foreign price and cached MV. This does not relax future sold-out forecasting: sold-out future windows still need completed-cycle evidence.

## Transparent ordering — IMPLEMENTED

- `NAME`: alphabetical item/destination.
- `UPCOMING`: earliest current/modeled window.
- `GROSS PROFIT`: trip gross descending.
- `PROFIT/HR`: trip gross / total elapsed hours descending.

Hit likelihood remains separate and is not probability-weighted into any visible sort.

Sorts reorder already-projected rows immediately in Lua; the PowerShell preference action persists the mode without gating visual response.

## Economics

```text
gross = (selected MV basis - foreign price) × purchasable quantity
profit/hr = gross / total elapsed hours
```

Gross excludes travel cost. Quantity is no longer printed beside the row gross but remains projected for tooltips/debugging.

Default basis remains:

```text
100% Torn MV
0% Item Market fee deduction
0 minimum profit gate
0 minimum margin gate
negative-value candidates allowed
```

Optional 95% MV and profitable-only settings remain.

## Projection / interaction stability

The Lua reader retains the last complete opportunity/UI projection while intermediate minute-update writes are occurring. A transient learning-only zero pass does not erase previously valid visible rows.

Text controls have explicit hitboxes. Sort and inline expansion are local UI operations rather than network-update operations.

## Graph/history retention

- visible graph horizon: 8h;
- high-resolution observation retention: 48h;
- completed cycle retention: 90d;
- change-only pruning preserves a predecessor/baseline;
- bootstrap-only historical migration can be repaired as a carried unchanged baseline without inventing a transition.

## Popups / runtime diagnostics

Detached Settings/filter/standalone Viewer paths use hidden STA PowerShell. Failures are written to:

```text
data/runtime/logs/travel-assistant.log
```

Windows PowerShell 5.1 generic collection compatibility fixes remain in place.

## Background optimizer — RETAINED

`OptimalRoute.ps1` remains a background compatibility/diagnostics/MV-priority model only. It does not define the user-facing UI.

## Runtime order

```text
UpdateTracker
ShadowCollector
LocalCatalog
FinalizeState
TravelContext
OptimalRoute
OpportunityState
FilterState
heartbeat
ResalePriority
ResaleQueue
```

## Validation status

Current validators cover:

- four transparent sort modes;
- local immediate sorting fields;
- fresh current in-stock `LEARNING` likelihood projection;
- no visible place-number projection;
- separate inline vs standalone graph routing;
- inline renderer parse/local-only contract;
- flag rail / white time strip / chevron expansion contract;
- exclusive expanded graph state;
- stable projection through polling;
- retained-history repair and zero-stock graph truthfulness;
- Windows PowerShell 5.1 compatibility;
- Energy/Nerve integration;
- popup/logging contract.

This visual candidate still requires target-Windows/Rainmeter acceptance. Do not mark 0.6 accepted until the focused suite, one production update, compact collapsed cards, one expanded inline graph, sorting, popups and standalone Viewer are visibly validated.

## After 0.6 acceptance

1. refine vector flag and inline graph proportions from the real render;
2. continue probability calibration as cycles accumulate;
3. add optional Chrome/browser notifications consuming accepted opportunity timing state;
4. evaluate bounded multi-trip sequence scheduling separately.
