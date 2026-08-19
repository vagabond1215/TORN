# Travel Assistant Architecture

## Purpose

Travel Assistant is a lightweight Rainmeter-facing decision system for Torn foreign-market travel opportunities.

Version 1 presents **Xanax in the United Kingdom and Japan**, but the architecture treats country, item, provider, price, stock, and travel mode as data so later expansion does not require a rewrite.

The engine should answer two separate questions:

1. **Availability:** when would a departure be likely to arrive while stock is available?
2. **Economics:** is the opportunity profitable enough to justify recommending that departure?

Only after both pass should the UI show departure advice.

---

## Layering

```text
Provider adapters
      ↓
Normalized observations
      ↓
History / cycle detection
      ↓
Restock + depletion analytics
      ↓
Travel / profitability / opportunity engine
      ↓
Compact computed state
      ↓
Rainmeter presentation
```

### Provider adapters

Responsibilities:

- retrieve current/historical source data;
- respect provider rate/usage limits;
- normalize timestamps, country/item identifiers, stock, foreign price, and provenance;
- return provider errors/freshness explicitly;
- contain all provider-specific response parsing.

Provider-specific data shapes must not propagate into the history or recommendation engine.

Possible adapters may include Weav3r, a suitable historical travel-stock API, and Torn endpoints where useful. Provider availability is not assumed permanent.

### History / cycle engine

Responsibilities:

- append normalized observations;
- detect meaningful stock transitions;
- identify restocks;
- identify actual sellouts;
- build completed cycle summaries;
- maintain bounded high-resolution history;
- compact/prune old runtime observations;
- maintain provenance and schema versioning.

### Analytics engine

Responsibilities:

- restock interval distributions;
- robust restock variance;
- price-conditioned availability/depletion behavior;
- recent-vs-historical drift detection;
- current-cycle depletion estimation;
- comparable-cycle selection / weighting;
- safe-overlap calculations;
- best-odds departure calculations;
- confidence scoring.

Heavyweight ML is not required. Prefer transparent, testable statistical logic that can run cheaply on a desktop.

### Profitability engine

Responsibilities:

- foreign purchase price;
- current resale reference;
- minimum absolute profit per item;
- minimum percentage margin;
- later: carrying capacity, total-trip profit, travel/other costs, multiple resale references.

Profitability is a gate on recommendations, not on data collection.

### Rainmeter presentation

Responsibilities:

- display the latest computed state;
- update relative countdown strings cheaply;
- render/cycle travel mode selection;
- open external verification links when requested;
- show vertically aligned graphs/panels;
- expose stale/low-confidence/unprofitable states clearly.

Rainmeter should not perform the statistical model itself.

---

## Core normalized observation

Conceptual schema:

```json
{
  "schemaVersion": 1,
  "timestamp": 1787168400,
  "country": "united_kingdom",
  "itemId": 206,
  "stock": 1438,
  "foreignPrice": 742000,
  "source": "provider-name",
  "sourceTimestamp": 1787168372,
  "quality": "observed"
}
```

Required principles:

- canonical country/item identifiers must be stable;
- timestamps must have documented semantics and normalized timezone handling;
- foreign price belongs on the observation/cycle rather than being assumed from a static item table;
- source/provenance must survive normalization;
- additional provider metadata can be retained only when useful and bounded.

---

## Completed cycle record

Conceptual schema:

```json
{
  "schemaVersion": 1,
  "country": "united_kingdom",
  "itemId": 206,
  "foreignPrice": 728000,
  "restockAt": 1787168400,
  "restockQuantity": 2630,
  "soldOutAt": 1787168765,
  "availabilitySeconds": 365,
  "source": "provider-name"
}
```

A completed cycle is the durable compact training unit. It may also carry bounded summary information about the within-cycle depletion curve, confidence/quality, price changes, and source agreement.

Do not preserve all minute-level observations forever merely to retain a cycle.

---

## Restock timing model

For each `country + item`, derive restock timing from actual historical transitions.

Useful statistics may include:

- median interval from prior sellout to next restock;
- robust spread / percentile range;
- minimum/maximum only when sample quality warrants using them;
- recent-window behavior versus longer history;
- time-of-day/day-of-week segmentation only when enough data exists to support it.

Pattern detection must not create false precision from tiny samples. If a proposed cohort has inadequate support, fall back to a broader cohort and reduce confidence.

---

## Price-conditioned depletion model

Foreign price can materially change demand and stock duration, so radically different prices must not be pooled indiscriminately.

For a current cycle, evidence priority is:

1. **Current observed depletion** — strongest once enough samples exist in the live cycle.
2. **Comparable historical price cycles** — highest historical weight.
3. **Nearby-price cycles** — lower weight as price distance grows.
4. **Broad destination/item history** — fallback only, with lower confidence.

The implementation may use adaptive price neighborhoods or bands internally, but should avoid brittle hard-coded assumptions such as “UK Xanax always sells out in N minutes.”

If current price is outside the meaningful historical range, return `PRICE_REGIME_UNVERIFIED` or otherwise reduce recommendation confidence.

---

## Departure simulation

For a selected travel mode and candidate departure offset:

```text
arrival = departure + travelTime(country, travelMode)
```

Evaluate whether that arrival would fall inside the availability interval of qualifying historical cycles.

This creates an empirical mapping:

```text
departure offset → historical success rate
```

The model should use comparable cycles, not every cycle equally.

### Conservative safe window

A safe window exists only when qualifying comparable cycles support a meaningful overlapping departure interval after travel-time conversion.

User-facing semantics:

- `SAFE_WINDOW OPENS IN ...`
- `SAFE_WINDOW OPEN`
- `LEAVE BEFORE ...`

“Safe” means conservative against the selected/qualifying historical sample; it is not a guarantee of future Torn behavior.

### Best-odds departure

If restock variance is wider than the reliable stock-availability period, there may be no conservative overlap.

Then compute the candidate departure point or narrow interval with the highest empirical success rate and use `BEST_ODDS` / `LEAVE IN`, not `SAFE_WINDOW`.

The UI may show a historical hit rate/confidence when useful.

---

## Profitability gate

The recommendation pipeline is:

```text
fresh data?
  ↓
profitable enough?
  ↓
comparable regime / sufficient confidence?
  ↓
safe window or best odds?
  ↓
display recommendation
```

Initial configurable thresholds should support:

- minimum profit per item;
- minimum percentage spread.

Future-compatible fields may include:

- carrying capacity;
- minimum total-trip profit;
- travel/transaction costs;
- preferred resale source.

If the profitability gate fails:

- continue collecting stock/cycle data;
- show `LOW_MARGIN` or `UNPROFITABLE`;
- do not show a departure time/window.

---

## Confidence model

Confidence should be explainable and should consider at least:

- data freshness;
- usable sample count;
- similarity of current foreign price to historical cycles;
- whether current depletion agrees with historical expectations;
- restock timing stability;
- source agreement/disagreement if multiple providers are used;
- whether the current model is extrapolating outside observed history.

Recommended coarse lifecycle states:

```text
UNVERIFIED / INSUFFICIENT_HISTORY
LEARNING
ESTABLISHED
```

Do not rely on a fixed cycle-count threshold alone. A small highly variable sample can remain low-confidence; a moderately sized stable sample can become useful sooner.

---

## First-run / bootstrap behavior

Preferred startup sequence:

1. load committed compact seed data if present;
2. optionally perform a bounded historical bootstrap from a suitable structured provider endpoint;
3. normalize and store only the useful derived seed/history;
4. begin local bounded observations;
5. if timing looks potentially actionable but confidence is too low, show `CHECK_EXTERNAL` and allow a clickable Weav3r travel-stock link.

Historical bootstrap is an optimization, not a correctness requirement. If it is unreliable or unsuitable, start conservatively and learn locally.

---

## Data retention

### Seed data — committed

Suggested contents:

```text
data/seed/
  observations.jsonl   # short bootstrap, e.g. 24–48h when useful
  cycles.jsonl         # compact recent historical cycles
  metadata.json        # provenance, generatedAt, scope, schemaVersion
```

Seed data should remain compact and intentionally refreshed, not continuously appended by runtime operation.

### Runtime data — local / ignored

Suggested contents:

```text
data/runtime/
  observations/
  cycles/
  state/
  cache/
```

Default targets:

- high-resolution observations: about 24–48 hours;
- completed cycle summaries: about 60–90 days initially;
- long-term learning: compact aggregates;
- logs: rotated/pruned or intentionally tiny.

No unbounded raw HTTP response archive, screenshot archive, or browser cache.

---

## Resource model

### Every second

Allowed:

- countdown arithmetic;
- text/status refresh;
- inexpensive UI state changes.

Avoid:

- HTTP requests;
- PowerShell process spawning;
- full history parsing;
- model retraining;
- graph regeneration if source data did not change.

### Approximately every 60–120 seconds

Subject to provider limits/usefulness:

- fetch current observations;
- normalize and append one sample;
- detect price/stock/restock/sellout changes;
- update graph data if needed.

### On meaningful event / low-frequency schedule

- recompute cycle summaries;
- recalculate restock/depletion statistics;
- prune/compact old runtime data;
- regenerate computed recommendation state.

---

## UI architecture

Version 1 layout is vertically stacked:

```text
UNITED KINGDOM
Travel | Leave / Window
Restock | Last Sold Out
Stock | Foreign Price
Graph
Recommendation state

JAPAN
Travel | Leave / Window
Restock | Last Sold Out
Stock | Foreign Price
Graph
Recommendation state
```

Design rules:

- same graph dimensions/alignment for both destinations;
- dark charcoal panel on a black desktop;
- strong but restrained contrast;
- relative countdowns preferred to absolute clocks;
- Airstrip default;
- runtime-selectable Standard/Airstrip/WLT/Business where practical;
- external verification action only when useful;
- no unsupported Clock-app alarm automation in v1.

---

## Expansion design

Future expansion should be configuration-driven:

```text
items.json
countries.json
travel-modes.json
settings.json
```

The core engine should accept generic `country + itemId + travelMode` combinations.

Do not create functions/data models named around fixed combinations such as `GetUKXanaxWindow`. Prefer generic operations such as:

- `GetObservations(provider, country, item)`
- `BuildCycles(observations)`
- `SelectComparableCycles(country, item, price, context)`
- `EvaluateDepartureWindow(...)`
- `EvaluateProfitability(...)`

Adding a new item or destination should primarily require configuration, provider coverage, sufficient history, and UI selection—not a rewrite of persistence or analytics.

---

## Versioning / migrations

Persistent data contracts must be versioned from the beginning.

When a schema changes:

- preserve old seed/runtime data when reasonably possible;
- add an explicit migration/upgrade path or invalidate only the affected cache safely;
- do not silently reinterpret old fields with new semantics;
- update this architecture document and fixtures/tests in the same pass.
