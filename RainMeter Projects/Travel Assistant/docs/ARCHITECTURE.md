# Travel Assistant Architecture

## Purpose

Travel Assistant is a lightweight Rainmeter-facing decision system for Torn foreign-market travel opportunities.

Version 1 presents **Xanax in the United Kingdom and Japan**, but country, item, provider, price, stock, travel mode, and travel economics are data so later expansion does not require a rewrite.

The engine answers two separate questions:

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

Current/candidate roles are kept in `config/providers.json`. A provider may be live, resale-only, bootstrap-only, cross-check-only, or external-verification-only without changing the core model.

### History / cycle engine

Responsibilities:

- append normalized observations;
- detect meaningful stock transitions;
- identify observed restocks;
- identify actual observed sellouts;
- build completed cycle summaries;
- maintain bounded high-resolution history;
- compact/prune old runtime observations;
- merge immutable seed history into reads without copying it into mutable runtime state;
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

### Profitability / travel-economics engine

Responsibilities:

- foreign purchase price;
- current resale reference;
- transaction/selling fee;
- minimum absolute profit per item;
- minimum percentage margin;
- travel-mode cost;
- conservative/default carrying capacity;
- later: user-specific capacity, minimum total-trip profit, free Business-Class perk, Business Class Ticket opportunity cost, and multiple resale targets.

Profitability is a gate on recommendations, not on data collection.

`config/countries.json` now stores the durable travel-economics inputs that are stable by destination/mode:

```text
travelSeconds
travelCosts
baseTravelCapacity
```

For v1:

- Standard has a destination-specific cash travel cost;
- Airstrip and WLT are explicitly zero-cost travel modes;
- Business travel time/base capacity is configured, but its cost is intentionally unresolved because it may consume a Business Class Ticket or be free with the relevant company perk.

Therefore Business remains configured but disabled in the runtime selector until that cost branch is represented safely. This follows the project invariant that **no recommendation is better than an economically misleading recommendation**.

The current production gate still evaluates per-item net margin; applying Standard travel cash cost and user-specific capacity to total-trip profit is the next profitability step.

### Rainmeter presentation

Responsibilities:

- display the latest computed state;
- update relative countdown strings cheaply;
- render/cycle enabled travel modes;
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
  "sourceTimestamp": 1787168372
}
```

Required principles:

- canonical country/item identifiers are stable;
- timestamps have documented semantics and normalized timezone handling;
- foreign price belongs on the observation/cycle rather than being assumed from a static item table;
- source/provenance survives normalization;
- provider forecasts are not stored as historical facts;
- additional provider metadata may be retained only when useful and bounded.

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
  "previousSoldOutAt": 1787161000,
  "restockDelaySeconds": 7400,
  "source": "provider-name"
}
```

A completed cycle is the durable compact training unit. It is derived from observed stock transitions, not from estimated restock/sellout timestamps.

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

Evidence priority is:

1. **Current observed depletion** — strongest once enough samples exist in the live cycle.
2. **Comparable historical price cycles** — highest historical weight.
3. **Nearby-price cycles** — lower weight as price distance grows.
4. **Broad destination/item history** — fallback only, with lower confidence.

The initial engine uses a bounded near-price cohort rather than a heavyweight regression. This is intentionally simple while real history accumulates.

If the current price lies outside useful historical support, return `PRICE_REGIME_UNVERIFIED` rather than extrapolating confidently.

---

## Departure simulation

For a selected enabled travel mode and candidate departure offset:

```text
arrival = departure + travelTime(country, travelMode)
```

Evaluate whether that arrival would fall inside the availability interval of qualifying historical cycles.

This creates an empirical mapping:

```text
departure offset → historical success rate
```

The model uses comparable cycles, not every cycle equally.

### Conservative safe window

A safe window exists only when qualifying comparable cycles support a meaningful overlapping departure interval after travel-time conversion.

User-facing semantics:

- `SAFE WINDOW OPENS IN ...`
- `SAFE WINDOW OPEN`
- `LEAVE BEFORE ...`

“Safe” means conservative against the selected/qualifying historical sample; it is not a guarantee of future Torn behavior.

When the current restock is live, current depletion may **shorten** the conservative close time; it may not extend the window beyond historical safety evidence.

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

Current production checks include:

- Item Market resale reference;
- configured Item Market fee;
- minimum net profit per item;
- minimum net percentage margin.

Travel-economics configuration now additionally records:

- Standard destination cash cost;
- Airstrip/WLT zero travel cost;
- base carrying capacity by mode;
- unresolved Business cost explicitly as `null`.

Next production step:

```text
tripNet = (netProfitPerItem × usableCapacity) - travelModeCost
```

with user-specific capacity overriding conservative base capacity when available.

Business must remain disabled until `travelModeCost` can be safely resolved as either:

- zero because the user explicitly has the free Business-Class company perk; or
- the current Business Class Ticket opportunity cost.

If any profitability gate fails:

- continue collecting stock/cycle data;
- show `LOW_MARGIN` or `UNPROFITABLE`;
- do not show a departure time/window.

---

## Confidence model

Confidence is explainable and considers at least:

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

## First-run / historical bootstrap

Preferred startup sequence:

1. load committed compact seed data if present;
2. begin local bounded observations immediately;
3. optionally add a bounded historical seed from a verified structured history endpoint;
4. normalize provider observations to the core schema;
5. derive cycles from observed transitions;
6. if timing looks potentially actionable but confidence is too low, show `CHECK_EXTERNAL` and expose Weav3r.

Historical bootstrap is an optimization, not a correctness requirement. If it is unreliable or unsuitable, start conservatively and learn locally.

### Seed-provider rules

A bootstrap source must provide enough historical truth to distinguish observations from forecasts.

Preferred inputs:

```text
timestamp
stock quantity
foreign purchase price
country
item
```

Travel Assistant currently contains two candidate discovery paths:

- DroqsDB metadata/current-endpoint probe, disabled until its live historical contract is verified;
- a preview-first adapter for a documented travel-planner-compatible `/api/history/:country/:itemId?hours=...` snapshot endpoint.

The compatible travel-planner adapter requests only UK/Japan Xanax, defaults to 168 hours, and caps a single requested window at 720 hours. It requires an explicit deployment base URL and does not assume that an arbitrary deployment permits external bootstrap use.

Provider safe-window/restock forecasts may be useful for later comparison, but must not populate `Last Sold Out` or completed-cycle truth records.

---

## Data retention

### Seed data — committed

```text
data/seed/
  observations.jsonl
  cycles.jsonl
  metadata.json
  README.md
```

Seed data remains compact, immutable during normal runtime, provenance-documented, and intentionally refreshed rather than continuously appended.

### Runtime data — local / ignored

```text
data/runtime/
  observations.jsonl
  cycles.jsonl
  engine-state.json
  preferences.json
  provider-probes/
  historical-imports/
```

Default targets:

- high-resolution observations: about 48 hours;
- completed cycle summaries: about 90 days initially;
- long-term learning: compact aggregates when introduced;
- probe/import previews: local and manually disposable;
- logs: rotated/pruned or intentionally tiny.

No unbounded raw HTTP response archive, screenshot archive, or browser cache.

---

## Resource model

### Every second

Allowed:

- read compact generated state;
- countdown arithmetic;
- text/status refresh;
- inexpensive UI state changes.

Avoid:

- HTTP requests;
- PowerShell process spawning;
- full history parsing;
- model retraining;
- graph regeneration.

### Approximately every 60–120 seconds

Subject to provider limits/usefulness:

- fetch current observations;
- normalize/append changed samples;
- detect price/stock/restock/sellout changes;
- update model state;
- regenerate the two compact graph images.

Updater executions are serialized so refresh and scheduled poll events cannot write concurrently.

### Low-frequency / event-triggered work

- prune/compact old runtime data;
- historical bootstrap/probe runs;
- migration/seed maintenance;
- future aggregate recalculation.

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
- runtime-selectable Standard/Airstrip/WLT now;
- Business configured but disabled until trip economics are safe;
- external verification action only when useful;
- no unsupported Clock-app alarm automation in v1.

---

## Expansion design

Future expansion remains configuration-driven:

```text
items.json
countries.json
travel-modes.json
providers.json
settings*.json
```

The core engine accepts generic `country + itemId + travelMode` combinations.

Do not create functions/data models named around fixed combinations such as `GetUKXanaxWindow`. Prefer generic operations such as:

- `GetObservations(provider, country, item)`
- `BuildCycles(observations)`
- `SelectComparableCycles(country, item, price, context)`
- `EvaluateDepartureWindow(...)`
- `EvaluateProfitability(...)`

Adding a new item/destination should primarily require configuration, provider coverage, sufficient history, economics metadata, and UI selection—not a rewrite of persistence or analytics.

---

## Versioning / migrations

Persistent data contracts are versioned from the beginning.

When a schema changes:

- preserve old seed/runtime data when reasonably possible;
- add an explicit migration/upgrade path or invalidate only the affected cache safely;
- do not silently reinterpret old fields with new semantics;
- update architecture, fixtures/tests, and validation rules in the same pass.
