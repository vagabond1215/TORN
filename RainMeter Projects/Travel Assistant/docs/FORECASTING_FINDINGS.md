# Travel Assistant Forecasting Findings

**Status:** empirical findings for near-term implementation and shadow testing  
**Recorded:** 2026-08-25  
**Primary empirical source:** local `data/runtime/` archive supplied during development  
**Research source:** temporary Deep Research report stored separately in this repository

## Decision

**Forecasting decision: READY FOR SHADOW TESTING, not ready to replace all live timing logic.**

The empirical runtime history materially changes the earlier methodological-only conclusion. The strongest result is not "replace OLS with one larger regression." The evidence supports a split architecture:

- **next restock delay:** robust market-specific recent history, especially rolling median, is currently stronger and more stable than the tested regression families;
- **availability / sellout duration:** pooled robust regression and a simple median/Ridge hybrid are credible challengers and should run in shadow mode;
- **data-quality gating is mandatory:** stale, duplicate, synthetic, retained-baseline, or otherwise suspect evidence must not be treated as clean event truth;
- **confidence must depend on clean market history count** rather than presenting every numerical forecast with equal confidence.

## Empirical dataset audit

The supplied runtime archive contained:

- **34,704 observations**;
- **2,896 completed-cycle records**;
- **232 observed country:item markets**;
- **163 markets with completed cycles**.

The initial empirical audit used real observation history to cross-check cycle evidence rather than trusting every cycle record equally.

Important exclusions / caveats:

- `retention_baseline` observations are display/history continuity evidence, not live event observations and should not become training truth;
- initial/incomplete cycles with no meaningful prior sellout do not provide a valid restock-delay target;
- provider/source timestamp is the relevant freshness clock, not local collection time alone;
- predicted/restored/generated timestamps must never be promoted into completed-cycle ground truth.

## Walk-forward benchmark findings

The tests were chronological next-cycle tests: information from cycle `t` was used to predict cycle `t+1`.

### Restock delay

Representative late-holdout ordering from the empirical run:

| Model | Restock-delay result |
|---|---|
| Rolling median 8 | strongest tested primary-MAE baseline |
| Robust Huber + pooled correction | close but did not beat median-8 |
| Gradient boosting benchmark | worse than median-8 |
| Ridge / Elastic Net | worse than median-8 |
| Current bounded OLS | materially worse than median-8 on primary MAE |
| Last-cycle persistence | substantially worse on primary MAE |

**Production implication:** do not replace restock-delay prediction with pooled regression based on the current evidence. Promote a robust recent-market estimator as the primary challenger to the current bounded OLS logic.

### Availability duration

Availability behaved differently. In the empirical late holdout:

- robust Huber + shrunk market correction improved primary MAE materially versus rolling median-8;
- a simple **median/Ridge ensemble** also produced a meaningful improvement and is attractive because inference is trivial to implement in PowerShell 5.1;
- the magnitude of improvement reduced when restricted to the strictest raw-audited mature subset, so this remains a **shadow candidate**, not yet a production replacement;
- availability prediction intervals were under-covered and need calibration before they can safely drive `Guaranteed Window` semantics.

## Reliability versus clean-history count

The clearest operational relationship in the empirical run was forecast reliability versus the number of prior clean cycles for the same market.

Use the following as the immediate confidence-policy candidate:

| Prior clean cycles | Recommended state |
|---:|---|
| 0-1 | no actionable timing claim; learn / abstain |
| 2-3 | very low confidence; pooled/robust fallback only |
| 4-7 | forecast allowed but visibly degraded |
| 8+ | mature actionable forecast candidate |
| 10+ | mature; eligible for market-specific residual calibration when enough frozen errors exist |

The thresholds must continue to be scored prospectively, but the current empirical data strongly supports making **8 clean cycles** a meaningful maturity boundary.

## Xanax cross-market stress test

Xanax (`itemId=206`) demonstrates why `itemId` alone is not a sufficient behavioral identity.

The runtime history contained real Xanax cycles for multiple countries with:

- a shared Torn resale-market identity;
- materially different foreign purchase-price regimes;
- broadly similar central restock cadence in several markets;
- sharply different availability/sellout durations.

Therefore the forecasting hierarchy should treat `country:itemId` as the behavioral market key and only pool above that level with shrinkage/regularization.

Recommended hierarchy:

```text
global behavior
    -> item/category behavior
        -> country:item market correction
            -> current detected regime
```

### Price signal conclusion

Foreign price is worth retaining as a candidate/regime feature, but the empirical ablation did **not** show a strong enough universal timing improvement to make price a dominant predictor.

Observed Xanax price/availability relationships differed by country and were not consistently monotonic. A pooled rule such as "higher foreign price means longer/shorter availability" is not supported.

Historical `priceToMvRatio` could not be tested leakage-safely unless the Torn market value known **at the forecast origin** is persisted. Current MV must not be backfilled retrospectively into old cycles.

## Point forecasts and intervals are separate promotion gates

A point predictor can improve MAE while still producing unsafe window bounds.

The empirical work indicated:

- restock residual intervals were reasonably close to nominal coverage in the tested sample;
- availability intervals were too narrow / under-covered;
- therefore availability point-model improvement alone is insufficient to promote `Guaranteed Window` bounds.

For live window guidance, continue to require calibrated residual or quantile coverage and distinguish:

- early restock;
- late restock;
- early sellout;
- late sellout;
- safe/guaranteed overlap;
- best-hit probability.

## Immediate shadow-model plan

Persist a frozen prediction record before each target cycle occurs. At minimum record:

```text
prediction id / model version
prediction timestamp
market key
source/provider and source timestamp
evidence state: live / forecast-only / unusable
quality class
prior clean cycle count
foreign price
market value known at prediction time (if available)
current production forecast
rolling-median forecast
Huber/pooled availability forecast
median/Ridge availability forecast
point restock and availability predictions
80 / 90 / 95 percent bounds
feature snapshot
abstention/fallback reason
```

When the cycle completes, score the immutable prediction. Never regenerate a historical "prediction" after seeing the target.

## Promotion criteria

Do not force a winner. A challenger should only replace a production component when prospective evidence shows:

- approximately 10% or greater practically meaningful improvement on its primary target, or another clearly material operational gain;
- improvement across markets rather than only one high-volume market;
- no material degradation in median per-market performance;
- acceptable signed bias;
- interval calibration near nominal coverage;
- stability across multiple chronological periods;
- robustness after stale/spurious/caution evidence is removed;
- enough frozen shadow predictions to make the result credible.

## Data-quality policy for model truth

Classify incoming evidence as:

```text
ACCEPT
ACCEPT_WITH_CAUTION
QUARANTINE
REJECT
```

Reject or quarantine at minimum:

- stale upstream timestamps masquerading as fresh local polls;
- duplicate/carry-forward upstream snapshots;
- timestamp reversal;
- invalid event ordering;
- impossible/nonpositive durations;
- provider-switch transitions with contradictory stock state;
- one-poll stock or price anomalies that immediately revert;
- long gaps where an apparent event cannot be located closely enough;
- synthetic fixtures, predictions, graph interpolation, and generated repair points as target truth.

## Near-term engineering direction

1. Fix live collection/projection reliability before changing the production forecasting algorithm.
2. Preserve complete clean cycles and source-quality metadata.
3. Add prospective shadow records.
4. Prefer robust median-style restock prediction over aggressive short-window trend extrapolation unless future shadow results reverse the finding.
5. Shadow-test robust pooled and median/Ridge availability models.
6. Persist MV-at-forecast-time so price/MV can eventually be tested honestly.
7. Recalibrate availability intervals before they are allowed to define a guaranteed travel window.

## Temporary research source

The full methodological Deep Research output is stored temporarily as:

`docs/TEMP_DEEP_RESEARCH_FORECASTING_REPORT.md`

That file is an ingestion artifact and should be deleted after all durable requirements, citations worth retaining, and implementation decisions have been incorporated into maintained project documentation/tests.
