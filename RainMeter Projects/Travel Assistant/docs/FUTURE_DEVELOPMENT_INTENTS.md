# Future Development Intents

This file records non-active architectural directions that may become future implementation work. It is **not** part of the current acceptance scope and does not override `AGENTS.md`, `NEXT_CODEX_RUN.md`, or the existing local-first runtime.

## Centralized / shared Travel Assistant backend

### Intent

Migrate the project over time from every Rainmeter client independently collecting, retaining, processing, simulating, and calibrating the same foreign-market data toward a **hub-and-spoke architecture** with shared evidence and eventually shared model computation.

The intended end state is:

```text
client collectors
      |
      v
central ingestion API
      |
      v
submitted observations
      |
      v
dedupe / conflict resolution / trust checks
      |
      v
canonical observations
      |
      +--> completed-cycle extraction
      |
      +--> current-stock safety
      |
      +--> stochastic forecasting
      |
      +--> calibration / replay
      |
      +--> shared current-state snapshot
      |
      v
Rainmeter clients
```

A ChatGPT Site may later serve as a human-facing dashboard/control surface, but the production ingestion/forecasting backend should not depend on Sites until its hosting/runtime capabilities are proven suitable for continuous external data ingestion and scheduled/background model processing.

### Why this is desirable

Central aggregation can:

- reduce duplicated CPU/disk work across clients;
- preserve evidence when any one client is offline;
- combine staggered client uptime into much better 24-hour market coverage;
- materially improve observation density for short-cycle items;
- create a much larger population of forecast -> arrival -> resolved-truth pairs for calibration;
- support statistically defensible testing of time-of-day, price, phase-locking, and regime effects;
- allow a thin Rainmeter client to become mostly fetch/cache/render rather than full model execution.

The primary value is not only lower client load. A shared evidence pool can improve model quality because multiple independent observers can collectively cover market transitions that one machine would miss.

### Migration phases

#### Phase 1 - central observation storage only

Keep current local computation authoritative.

Clients asynchronously batch and upload change-only observations to a central API. The service stores submissions and deduplicates them. No visible client behavior changes.

#### Phase 2 - shared evidence shadow mode

Clients may download merged canonical observations and compare local-only forecasts against shared-evidence forecasts in shadow mode.

Do not promote shared evidence until conflict resolution, provenance, freshness, and client trust behavior are validated.

#### Phase 3 - central cycle extraction

Move completed-cycle derivation to the service and publish canonical cycles.

Clients retain local fallback capability.

#### Phase 4 - central stochastic forecasts and calibration

The service publishes market forecast/state snapshots containing fields such as:

```text
marketKey
generatedAt
modelVersion
pAnyStock
pTargetQty
expectedQty
expectedProfit
action
evidence quality
```

Rainmeter consumes these as a cached remote authority while preserving a bounded local fallback.

#### Phase 5 - thin client

Target architecture:

```text
central service = evidence/model authority
Rainmeter        = cache/render/local fallback
ChatGPT Site     = dashboard/admin/analytics surface
```

### Storage / service direction

Operational telemetry should **not** be stored through Git commits.

GitHub remains the authority for:

- source code;
- schemas;
- committed seed/bootstrap data;
- model versions;
- tests;
- documentation.

Live evidence belongs in a database/object store.

A small serverless stack is sufficient for the expected workload. Candidate technologies include:

- Cloudflare Workers + D1 (+ R2 if archival blobs are useful);
- Supabase/Postgres;
- small VPS + Postgres/SQLite;
- equivalent serverless database/API stacks.

The workload is mostly small JSON ingestion, deduplicated writes, periodic aggregation/model computation, and compact JSON reads.

### Canonical evidence model

Do not merge client submissions directly into canonical history.

Keep explicit layers:

```text
submitted_observations
        !=
canonical_observations
        !=
completed_cycles
        !=
forecasts
        !=
resolved_forecast_truth
```

A submitted observation should retain at least:

```text
clientId
clientVersion
schemaVersion
marketKey
observedAt
sourceTimestamp
stock
foreignPrice
provider/source status
```

Canonicalization should consider:

- source timestamp;
- market identity;
- duplicate stock/price observations;
- stale evidence;
- client clock skew;
- collection gaps;
- impossible transitions;
- client-version/schema mismatch;
- conflicting simultaneous observations.

Potential canonical identity/deduplication keys may include:

```text
marketKey + sourceTimestamp + stock + foreignPrice
```

but the final reconciliation strategy must preserve provenance and should be tested against contradictory client evidence.

### Client trust / health

A multi-client backend must not blindly trust every client.

Maintain client health/reliability signals based on:

- freshness;
- clock alignment;
- agreement with other observers;
- malformed or stale submissions;
- impossible transition frequency;
- schema/client version.

Bad or stale contributors must not poison canonical cycle history.

### Forecast/calibration opportunity

Central resolved forecast history can support much stronger out-of-sample model comparison.

For each historical forecast retain:

```text
marketKey
forecastAt
departureAt
arrivalAt
flightSeconds
modelVersion
predictedAnyStock
predictedTargetQty
actualAnyStock
actualTargetQty
Brier
logLoss
hourOfDay
foreignPrice
cycle/phase diagnostics
```

This can be used to compare, without future leakage:

- baseline joint-cycle stochastic model;
- time-of-day-conditioned model;
- current-price-conditioned model;
- phase-locking / flight-to-cycle-ratio models;
- regime-conditioned variants.

Only features that improve walk-forward/prospective calibration should be promoted.

### Offline / outage behavior

Do not make Rainmeter depend on one remote point of failure.

Preferred fallback policy:

```text
fresh central result
    -> use central result

brief central outage
    -> use cached central result

prolonged outage
    -> local collection/model fallback
```

The current local architecture therefore remains valuable even after centralization begins.

### ChatGPT Sites role

If used, Sites is best treated initially as a dashboard/control plane for:

- live market overview;
- chance-to-hit graphs;
- calibration;
- client health;
- observation coverage;
- model comparison;
- administrative tools.

Do not make Sites the sole production market-processing authority until continuous ingestion, external connectivity, scheduled/background processing, storage durability, and operational limits have been validated against the project's runtime requirements.

## Future current-cycle probability refinement

Production current-cycle Chance to Hit now uses uncensored live current-run depletion rates when at least three clean samples span at least ten minutes. Each observed rate is converted into a remaining-stock runway and the arrival probability is the empirical fraction of those live rates whose runway exceeds the physical arrival horizon.

When that live evidence is not yet sufficient, `Get-StableCurrentCycleArrivalProbability` falls back to completed-cycle survival **conditioned on the fact that the current cycle is still in stock at the latest observation**. If the live cycle has already outlived every usable historical duration, historical survival returns unknown rather than a fabricated 0%.

Future challengers can still test richer conditioning such as stock fraction, depletion shape, projected sellout margin, price/regime features, and calibrated shrinkage between live and historical evidence. Promotion should continue to be judged by frozen forecast -> later truth Brier/log-loss/calibration.

## Future graph forecast-domain overlay

The current graph renders small restock-window brackets from the observed preceding OoS anchor: `OoS + average restock delay +/- learned restock-delay variance`. The later observed restock tick is truth for calibration and may fall early, inside, or late relative to that forecast interval. Only boundaries that have entered the past-only 8-hour domain are drawn.

A true future forecast-domain overlay remains deferred. It could add forward-looking early/late restock and sellout markers once the graph gains a legitimate future-time region or a separate forecast gutter capable of showing:

- future projected early restock;
- future projected late restock;
- future projected early OoS/sellout;
- future projected late OoS/sellout;

with styling and tooltips clearly distinct from vivid observed Restock/OoS markers and the already-implemented past-domain restock-window ticks.

## Status

**Future intent only. No current implementation commitment.**

The current priority remains target-host acceptance, live probability/calibration accumulation, and model correctness under the existing local-first architecture.
