# TEMPORARY — Deep Research Forecasting Report Ingestion

> **Temporary artifact. Delete after full consumption.**  
> This file captures the Deep Research forecasting study supplied during development. Its recommendations are being distilled into maintained project documentation, tests, and code. The durable empirical decisions live in `FORECASTING_FINDINGS.md`.
>
> The original research was conducted before the real runtime archive was supplied, so it correctly did **not** claim empirical superiority for a model. Subsequent empirical results are intentionally kept separate.

## Executive conclusion from the research

The schema-only CSV contained no empirical rows and therefore could not support fitted production coefficients, accuracy claims, or statistical significance. The research selected a **candidate architecture and validation protocol**, not a proven winner.

The provisional model family proposed for empirical testing was:

> a partially pooled, robust, regularized linear model on log-duration targets, with recency/regime handling and empirically calibrated residual intervals.

The reason was the combination of:

- many related country:item time series;
- short per-market histories;
- likely correlated lag/rolling/price features;
- occasional bad or extreme observations;
- possible market/regime changes;
- a production runtime restricted to Windows PowerShell 5.1.

Offline training may be sophisticated, but production inference should reduce to simple persisted arithmetic.

## Data interpretation

The regression dataset should be cycle `t` -> cycle `t+1`.

Valid predictor families include only values known by the end of cycle `t`, such as:

- current restock delay and availability duration;
- lagged cycle values;
- robust rolling statistics reconstructed from earlier history;
- volatility/trend features built only from past rows;
- foreign price known at prediction time;
- market value and price/MV only when the historical MV timestamp proves it was known then;
- restock quantity when actually observed;
- calendar features derived from the forecast origin;
- country:item market identity for pooled/partial-pooling models;
- regime indicators derived only from prior history.

Never use as predictors:

- `target_next_*`;
- future event timestamps or stock/price;
- future provider health;
- post-target quality labels;
- a market value backfilled from the future;
- predicted/generated restock or sellout times;
- synthetic fixtures;
- graph interpolation or display-repaired history.

Precomputed lags/rolling values in an exported CSV should be recomputed inside each chronological fold to prevent accidental leakage.

## Candidate model ladder

Every complex model must compete against simple baselines rather than only against the current OLS implementation.

Mandatory baselines:

1. last observed cycle;
2. rolling median 3;
3. rolling median 5;
4. rolling median 8;
5. current bounded OLS trend model.

Candidate families to test:

- exponentially weighted recent estimate;
- pooled Ridge regression;
- Elastic Net;
- Huber / robust regression, preferably with regularization;
- quantile regression for conditional bounds;
- mixed-effects / hierarchical regression;
- penalized/shrunk country:item market offsets as a deployment-friendly approximation to partial pooling;
- GAM only if nonlinear diagnostics justify it;
- shallow gradient boosting as a benchmark, not an automatic deployment choice;
- interval-censored accelerated-failure-time / survival models as a statistically appropriate benchmark for event timing observed only through polling.

If a complex model gains only marginal accuracy, prefer the simpler model that can be audited and executed reliably in PowerShell.

## Separate timing targets

The research recommends initially modeling next restock delay and next availability duration separately.

They represent different processes:

```text
previous sellout -> next restock = restock delay
next restock -> next sellout      = availability duration
```

A joint multi-output model should only replace separate models if chronological empirical testing proves it improves point accuracy or probability calibration.

Paired residual behavior should still be retained so restock and availability errors are not assumed independent when calculating probability that stock remains at arrival.

## Foreign price

Do not assume every market's foreign price behaves continuously.

First classify price behavior:

- fixed / overwhelmingly stable price;
- genuinely variable price;
- piecewise price regime;
- anomalous one-poll price that immediately reverts.

For fixed-price markets, persistence is the natural baseline. A regression model must beat it rather than inventing variation.

Price or price/MV should only remain in timing models if feature ablation proves they improve unseen-cycle forecasts.

## Data-quality firewall

Data quality must be resolved before training.

Classify observations and cycles as:

```text
ACCEPT
ACCEPT_WITH_CAUTION
QUARANTINE
REJECT
```

### Stale source data

Freshness must be based primarily on the upstream/provider timestamp, not on when the local collector happened to ingest the response.

Flag/reject:

- old provider timestamps;
- repeated polls carrying the same upstream timestamp;
- observations spanning provider outages or long gaps;
- locally fresh ingestion of an upstream-stale snapshot.

### Duplicate / carry-forward data

Repeated polling of the same upstream snapshot is one statistical observation, not many.

A repeated tuple such as:

```text
market key
provider
provider source timestamp
stock
foreign price
```

must not receive repeated training weight.

### Spurious transitions

Quarantine or reject suspicious patterns such as:

- positive -> zero -> positive across only one or two snapshots;
- one-poll huge stock jumps that immediately revert;
- provider-switch transitions with contradictory availability state;
- event detection across a long data gap;
- backward timestamps;
- invalid restock/sellout ordering;
- zero or impossible duration;
- sudden price changes that immediately revert without adjacent confirmation.

Where possible quarantine only the questionable feature. A timing cycle may remain useful even when its price evidence is unreliable.

### Provider disagreement

When multiple providers disagree on zero versus positive stock, do not average that into false certainty. Quantify provider lag and conflict first. Unresolved state disagreement should be quarantined.

## Interval censoring

Polling does not reveal the exact event time.

If the last zero-stock observation occurs at time A and the first positive observation at B, the factual restock time is within `(A, B]`. Likewise sellout lies between the last positive snapshot and first zero snapshot.

Recommended cycle evidence therefore stores event brackets:

```text
previous_sellout_lower / upper
restock_lower / upper
sellout_lower / upper
```

and derives lower/upper bounds for restock delay and availability.

Simple regressions may use interval midpoints only as an explicitly approximate response and must be sensitivity-tested against lower/upper alternatives. Interval-censored AFT models should be benchmarked directly using event bounds.

## Regime handling

Short OLS slopes can react too strongly to a few observations. Test robust change detection, for example:

- rolling history caps;
- exponentially decayed weights;
- robust recent-vs-prior median shifts scaled by MAD;
- CUSUM/change-point style flags;
- price regimes where empirical evidence supports them.

When a regime shift is detected, uncertainty should widen and the model may abstain until enough post-shift evidence exists.

## Evidence states at inference time

The production system should distinguish:

### LIVE EVIDENCE

Source timestamps are sufficiently recent to support claims about current stock.

### FORECAST-ONLY EVIDENCE

Historical cycles may still be useful for future timing, but the old `lastStock` value must not be asserted as current.

### UNUSABLE EVIDENCE

The cycle phase or source state is too old, inconsistent, or unsupported to drive an actionable forecast.

A stale last-stock quantity must never be silently promoted to current stock.

## Chronological validation

Random train/test splits are prohibited.

Use expanding or rolling walk-forward validation. At each forecast origin:

1. include only observations/cycles that were actually available at that time;
2. rerun quality classification from that historical subset;
3. reconstruct lags, rolling features, regime flags, scaling, and imputation from history only;
4. fit/tune only on earlier data;
5. produce and freeze the next-cycle prediction;
6. reveal the actual outcome only after completion;
7. score the frozen forecast and advance.

For pooled models the chronological cutoff applies globally across all markets, not independently per market.

Nested chronological tuning should be used for penalties / robust thresholds / history caps.

Suggested conservative grids from the research:

```text
Ridge lambda: 0.01, 0.1, 1, 10, 100
Elastic Net L1 ratio: 0.1, 0.5, 0.9
Huber epsilon: 1.2, 1.35, 1.5, 2.0
Huber/Ridge penalty: 0.01, 0.1, 1, 10
EW half-life: 2, 4, 8 cycles
history caps: 5, 8, 12, 20 cycles
```

## Required scorecard

For both next restock delay and next availability duration report:

- MAE;
- median absolute error;
- RMSE;
- signed bias;
- 80%, 90%, 95% interval coverage;
- average interval width;
- interval score;
- pinball loss for quantile models;
- number of predictions;
- number of markets;
- per-market and macro-market metrics.

For probability that stock remains at arrival also use:

- Brier score;
- calibration/reliability curves;
- sharpness;
- abstention rate.

Report both micro and macro MAE so high-volume markets cannot hide poor sparse-market behavior.

## Robustness experiments

Repeat the full model comparison under:

### Dataset A — strict clean

`ACCEPT` only.

### Dataset B — operational plausible

`ACCEPT + ACCEPT_WITH_CAUTION`.

### Dataset C — broad empirical

All plausible empirical rows except hard-invalid, synthetic, and predicted/imputed targets.

Then stress-test by:

- removing the highest-volume market;
- leave-one-market-out where feasible;
- varying history length;
- varying stale thresholds;
- varying regime thresholds;
- excluding provider-conflict periods;
- excluding very wide censor intervals.

If a model advantage disappears under reasonable cleaning choices, it is not robust enough for production.

## Promotion gate

Do not force a model winner.

A production challenger should generally require:

- about 10% or greater meaningful MAE improvement over the strongest baseline, or another clearly material operational gain;
- no material deterioration on the other primary timing target;
- median per-market results favoring the challenger;
- improvement that survives removal of the largest market;
- acceptable bias;
- calibrated intervals that do not become uselessly wide;
- stable performance across chronological periods;
- robustness to data cleaning;
- successful prospective shadow results.

Formal equal-forecast tests may be used secondarily, but effect size and chronological robustness matter more than one p-value in a short dependent dataset.

## Abstention / fallback

The model must be allowed to say:

```text
insufficient data
stale data
provider conflict
regime uncertain
unreliable forecast
```

Suggested fallback hierarchy:

```text
calibrated market-specific model
    -> pooled robust model
        -> robust rolling median
            -> conservative historical interval
                -> no actionable forecast
```

## Candidate deployable model

The provisional research candidate predicts positive duration using a log transform:

```text
z = log(1 + duration)
```

and back-transforms with:

```text
duration = exp(z_hat) - 1
```

A compact initial feature family to test includes:

- log current restock delay;
- log current availability duration;
- recent median of the target;
- exponentially weighted target estimate;
- recent MAD/volatility;
- one-cycle target delta;
- foreign-price deviation from recent market median;
- price/MV deviation from recent median when historically valid;
- log restock quantity + missingness flag;
- cyclic hour/day features;
- regime-shift flag and post-regime sample count.

A pooled robust linear equation can use global coefficients plus a shrunk `country:item` market offset. Sparse markets remain near the global prediction; mature markets receive more specific correction.

A simpler alternative is a global prediction plus a shrunk median recent residual correction:

```text
market prediction = global prediction + w * market residual correction
w = n_eff / (n_eff + kappa)
```

This approximates partial pooling and is very easy to deploy.

## Prediction intervals and travel probability

Maintain residual quantiles from **prequential frozen forecasts only**.

For a log residual distribution, add calibrated residual quantiles to the point prediction and back-transform to produce 80/90/95% intervals.

Market-specific interval corrections should be shrunk toward pooled residual quantiles when local error history is sparse.

For travel arrival probability, retain paired residual scenarios for restock and availability. For each scenario:

```text
restock = point restock + restock residual
sellout = restock + point availability + paired availability residual
```

Then estimate `P(in stock at arrival)` as the weighted fraction of scenarios where arrival is after restock and before sellout.

This avoids assuming restock and sellout errors are independent.

## PowerShell deployment constraint

Training can occur offline. The production artifact should contain only:

- model version;
- target;
- transform;
- feature names;
- centering/scaling vectors;
- coefficients;
- intercept;
- shrunk market offsets;
- residual quantiles/scenarios;
- validation metadata;
- minimum clean-cycle requirement;
- fallback policy;
- quality-policy version.

Runtime inference should be multiplication/addition plus `Exp`, lookup, clamping, and simple residual-scenario loops. No Python runtime is required in Rainmeter.

## Required prospective shadow test

Every next-cycle forecast must be written before the actual target is known and never modified retrospectively.

Store at least:

```text
predictionId
madeAtUtc
marketKey
targetCycleId
modelVersion
qualityPolicyVersion
evidenceState
qualityClass
featureSnapshot
point predictions
quantile/interval predictions
fallback/abstention state
```

Score it only after the real cycle completes.

The research suggested aiming for roughly 200 clean frozen shadow predictions across several markets before controlled production promotion, with meaningful representation of major active markets where volume permits.

## Research conclusion before empirical runtime data

The Deep Research report's correct formal decision was:

**INSUFFICIENT / LOW-QUALITY DATA** for model promotion, because the attached schema CSV had zero empirical observations.

It recommended collecting real observations and completed cycles, auditing them, running chronological comparisons, and then promoting only a model that survived the reliability gates above.

## Research basis retained for later citation cleanup

The report drew on established work in:

- Huber robust estimation;
- Hoerl & Kennard Ridge regression;
- Zou & Hastie Elastic Net;
- Koenker & Bassett quantile regression;
- mixed-effects / hierarchical modeling;
- global forecasting models across collections of time series;
- generalized additive models;
- Friedman gradient boosting;
- interval-censored event-time regression;
- CUSUM/change detection;
- rolling-origin/out-of-sample forecast evaluation;
- Diebold-Mariano predictive-accuracy comparison;
- proper scoring rules and forecast calibration;
- conformalized quantile ideas with explicit caution about time-series dependence assumptions.

Before deleting this temporary artifact, retain any bibliographic citations that become necessary for maintained technical documentation.

## Disposal condition

Delete this file when all of the following are true:

1. data-quality rules are represented in code/tests;
2. shadow forecast persistence is implemented;
3. model candidates and promotion criteria are represented in maintained docs/tests;
4. any useful literature citations have been migrated to durable documentation;
5. `FORECASTING_FINDINGS.md` has been updated with prospective shadow results.
