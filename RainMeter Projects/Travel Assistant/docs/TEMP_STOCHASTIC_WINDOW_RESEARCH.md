# TEMPORARY: Stochastic Window Research

> **Status:** Temporary implementation handoff artifact.
>
> **Purpose:** Preserve the deep-research conclusions and migration target for a Codex implementation in case the originating conversation context is lost.
>
> **Do not treat this file as permanent product documentation.** Delete or replace it after the stochastic-window migration has been implemented, validated, and documented in the normal architecture docs.

## Executive recommendation

The forecasting primitive should **not** be a deterministic restock/sellout "window."

The primary object should be a posterior predictive distribution over future inventory state, from which the system derives continuous curves over candidate arrival/departure times:

- probability any stock exists,
- probability useful quantity exists,
- expected quantity,
- expected after-tax profit,
- expected profit per occupied travel hour,
- downside/failure probability,
- decision utility.

A user-facing "window" should be a **presentation derived from those curves**, not the underlying model.

For candidate departure time \(t\):

\[
A(t) = \text{feasible arrival time}
\]

\[
P_q(t)=P(Q(A(t))\ge q_{min}\mid \mathcal D_t)
\]

where:

- \(Q(a)\) = quantity available at arrival time \(a\),
- \(q_{min}\) = useful-quantity threshold,
- \(\mathcal D_t\) = all information available at decision time.

This architecture directly handles cases where:

- stock lasts far less than travel time,
- restock-time uncertainty exceeds stock duration,
- multiple full cycles may occur during travel,
- current visible stock is mathematically unreachable,
- price and demand are variable,
- event boundaries are only known between polls.

The recommended production path is:

> **censor-aware cycle evidence + adaptive empirical/survival models + Monte Carlo integration + travel feasibility transform + one authoritative decision object**

Do **not** begin with a full POMDP, Hawkes model, or particle-filter reconstruction. Those are later options if backtesting proves the simpler model insufficient.

---

## 1. Formal problem

For item \(i\), cycle \(k\):

\[
R_{ik}=\text{restock time}
\]

\[
D_{ik}=\text{useful stock duration}
\]

\[
S_{ik}=R_{ik}+D_{ik}
\]

\[
Q_i(a)=\text{available quantity at time }a
\]

\[
C_i(a)=\text{foreign purchase price}
\]

\[
V_i(a)=\text{domestic resale value}
\]

\[
Z_i(a)=\text{latent market regime/demand state}
\]

Binary availability is only a special case:

\[
I_i(a)=1\{R_{ik}\le a<S_{ik}\}
\]

The more useful event is:

\[
I_{iq}(a)=1\{Q_i(a)\ge q_{min}\}
\]

Per-world after-tax profit can be modeled as:

\[
\Pi_i(a)
=
\min(K,Q_i(a))
\left[
V_i(a)(1-f)-C_i(a)
\right]
\]

where:

- \(K\) = player carrying capacity,
- \(f\) = configured trader/tax fee.

Primary forecasts:

\[
P_q(t)=P(Q_i(A(t))\ge q_{min}\mid\mathcal D)
\]

\[
E_Q(t)=E[\min(K,Q_i(A(t)))\mid\mathcal D]
\]

\[
E_\Pi(t)=E[\Pi_i(A(t))\mid\mathcal D]
\]

Decision utility:

\[
U_i(t)=E_\Pi(t)-C_{trip}-C_{opportunity}(t)-C_{risk}(t)
\]

The optimizer selects:

\[
(i^*,t^*)=\arg\max_{i,t\in\mathcal F_i} U_i(t)
\]

where \(\mathcal F_i\) is constrained by the player's travel state.

---

## 2. Why deterministic windows are inadequate

The current style of logic assumes an actionable interval can be formed from historical restock and sellout bounds.

That breaks down when:

1. **restock timing uncertainty is large relative to stock duration**,
2. **travel exceeds stock duration**,
3. **travel exceeds a full cycle**,
4. **demand/depletion is nonstationary**,
5. **price and profitability alter demand**,
6. **polling misses exact event boundaries**,
7. **visible current stock will certainly sell out before arrival**,
8. **the best arrival corresponds to the second, third, or later future cycle**.

For one uncertain restock with fixed duration \(d\):

\[
P_{stock}(A)=P(A-d<R\le A)=F_R(A)-F_R(A-d)
\]

If restock uncertainty is broad and stock life is very short, this produces a narrow low-probability peak, not a meaningful deterministic "safe window."

Example:

- restock standard deviation: 20 minutes,
- useful stock duration: 90 seconds.

Near the mode of a normal restock distribution, maximum single-cycle success can be only a few percent.

The correct result may therefore be:

- mathematically optimal departure exists,
- but maximum achievable success is poor,
- so recommendation is **NO ACTIONABLE TRIP**.

Optimization does not imply recommendation.

---

## 3. Four diagnostic ratios

Compute these for each item:

\[
\kappa_R=
\frac{\text{restock timing uncertainty}}
{\text{median useful stock duration}}
\]

\[
\kappa_F=
\frac{\text{flight duration}}
{\text{median useful stock duration}}
\]

\[
\kappa_C=
\frac{\text{flight duration}}
{\text{median complete cycle duration}}
\]

\[
\kappa_P=
\frac{\text{poll interval}}
{\text{median useful stock duration}}
\]

Interpretation:

| Regime | Meaning | Consequence |
|---|---|---|
| \(\kappa_R\ll1\) | restock timing precise vs stock life | broad probability plateau may resemble a traditional window |
| \(\kappa_R\approx1\) | uncertainty comparable to stock life | probability curve matters more than interval boundaries |
| \(\kappa_R\gg1\) | uncertainty dwarfs stock life | deterministic "safe" interval is usually meaningless |
| \(\kappa_F\ll1\) | flight short vs stock life | current live stock can matter |
| \(\kappa_F\gg1\) | flight long vs stock life | must forecast future cycles before departure |
| \(\kappa_C>1\) | one or more cycles fit inside flight | "next cycle only" is structurally wrong |
| \(\kappa_P\gtrsim1\) | polling slower than stock life | many events are never directly observed |

These are application-specific engineering diagnostics, not standard named statistics.

---

## 4. Event boundaries must be stored as intervals

If observations are:

```text
12:00 stock = 0
12:01 stock = 500
```

the evidence is:

\[
R\in(12{:}00,12{:}01]
\]

not:

\[
R=12{:}01
\]

Likewise:

```text
12:15 stock = 73
12:16 stock = 0
```

means:

\[
S\in(12{:}15,12{:}16]
\]

Store:

```text
restockLowerAt
restockUpperAt
selloutLowerAt
selloutUpperAt
boundaryQuality
sourceFreshness
collectionGapSeconds
```

Do not collapse these intervals to midpoints as the only persistent truth.

Midpoints can be used for display, never as the sole statistical record.

---

## 5. Censored demand

When inventory reaches zero, sales observations no longer reveal true demand.

If stock falls from 20 to 0 during a poll interval, underlying demand may have been 20, 50, or 500.

Therefore:

- depletion while endpoint remains >0 can support an observed sales-rate estimate,
- depletion ending at zero only establishes a **lower bound** on demand.

Do not fit demand as:

```text
(stock_old - stock_new) / elapsed
```

without distinguishing zero-ending intervals.

This is a classic lost-sales / censored-demand problem.

---

## 6. Recommended v1 depletion representation

Test simple baselines, but production v1 should prefer empirical whole-cycle resampling.

Candidate hierarchy:

1. linear extrapolation — baseline only,
2. exponential decay — baseline only,
3. piecewise-linear empirical trajectories — useful,
4. **empirical resampling of normalized historical cycle shapes — recommended v1**,
5. useful-stock-duration survival model — recommended companion,
6. explicit Poisson/NHPP demand — later if identifiable,
7. Hawkes demand — research-only unless purchase clustering can actually be inferred,
8. particle-filter latent demand — later.

Normalize historical trajectories:

\[
u=\frac{a-R_k}{D_k}
\]

\[
q^*(u)=\frac{Q_k(a)}{Q_{0k}}
\]

Resample **joint cycle records**, not independent variables, preserving dependencies among:

- OOS duration,
- restock timing,
- initial stock,
- stock duration,
- depletion shape,
- foreign price,
- domestic value/margin,
- hour/day context.

This naturally keeps empirical relationships such as "large restocks tend to last longer" if they exist.

---

## 7. Restocks as recurrent stochastic events

A foreign-item market resembles an alternating renewal process:

```text
OOS -> stocked -> OOS -> stocked -> ...
```

But IID cycle durations are only a baseline.

Production should allow:

\[
R_{k+1}-R_k \sim F_R(\cdot\mid x_k,z_k)
\]

Potential covariates:

- hour-of-day,
- weekday,
- prior OOS duration,
- prior stock duration,
- initial/restock quantity,
- foreign price,
- domestic MV,
- expected margin,
- recent depletion velocity,
- evidence quality,
- detected regime.

Do not force Cox/parametric models immediately. Add covariates only when held-out backtesting proves they improve forecasts.

---

## 8. Nonstationarity and regime changes

Old cycles should not have permanent equal weight.

Use two mechanisms:

### Gradual forgetting

\[
w(age)=\exp(-\lambda age)
\]

Tune effective memory by rolling-origin validation.

### Abrupt-change detection

Use a lightweight change detector such as Bayesian online change-point logic or a simpler validated approximation.

When a change is detected:

- widen uncertainty,
- reduce effective weight of old cycles,
- increase recent-data influence,
- do not instantly discard history based on one anomalous cycle.

Later, if useful, add hidden regime states such as:

- normal demand,
- high demand,
- event demand,
- price-driven demand.

---

## 9. Probability curve is the correct primitive

For candidate departure \(t\):

\[
A(t)=t+T_{effective}(t)
\]

Then:

\[
P_q(t)=P(Q(A(t))\ge q_{min}\mid\mathcal D)
\]

Monte Carlo estimate:

\[
\hat P_q(t)=
\frac1M
\sum_{m=1}^M
1\{Q^{(m)}(A(t))\ge q_{min}\}
\]

The same future worlds produce:

\[
\hat E_Q(t)=
\frac1M
\sum_m \min(K,Q^{(m)}(A(t)))
\]

\[
\hat E_\Pi(t)=
\frac1M
\sum_m \Pi^{(m)}(A(t))
\]

This is why Monte Carlo is recommended as the **integration layer** even if some component distributions are analytic.

---

## 10. Multiple cycles during travel

If:

\[
T_{flight}>T_{cycle}
\]

do not ask whether current or immediate-next stock survives.

The event becomes:

\[
\exists k: R_k\le A<R_k+D_k
\]

or:

\[
P_{stock}(A)=
P\left(
\bigcup_k
\{R_k\le A<R_k+D_k\}
\right)
\]

The simulator must generate future cycles until it passes the **latest feasible arrival time** being evaluated.

If flight spans several cycles, the fourth or fifth future cycle may be the relevant one.

For approximately regular cycles, travel may create phase alignment. But uncertainty accumulates with cycle count; phase targeting should weaken as horizon increases.

---

## 11. Travel feasibility must be separate from market forecasting

Do not let the market model decide whether a departure is physically possible.

Use a separate travel-state transform.

### HOME IN TORN

\[
A(t)=t+T_{flight}
\]

### RETURNING TO TORN

\[
t\ge t_{returnLanding}
\]

Only departures after landing are feasible.

### OUTBOUND TO TARGET

Departure optimization is over.

Evaluate the committed landing time directly:

\[
P_q(A_{committed})
\]

### ABROAD AT TARGET

Arrival delay is effectively zero.

Decision becomes BUY NOW / WAIT / insufficient quantity.

### OUTBOUND TO OTHER COUNTRY / ABROAD ELSEWHERE

If direct foreign-to-foreign routing is not supported by actual game mechanics or project design, do not invent it.

Compute the earliest legal new departure from Torn and restrict the optimization domain.

This prevents cards from saying LEAVE IN 10m when the player physically cannot be back in Torn by then.

---

## 12. Economics and utility

Raw probability should not determine action by itself.

A useful baseline:

\[
E_\Pi(t)
=
E[
\min(K,Q(A))
\max(0,V(A)(1-f)-C(A))
]
\]

If purchase is optional after arrival, negative-margin worlds should permit "do not buy."

Decision utility:

\[
U(t)
=
E_\Pi(t)
-
C_{trip}
-
C_{opportunity}(t)
-
\lambda R(t)
\]

Initial user-facing metrics should remain simple:

- probability useful quantity exists,
- expected quantity,
- expected after-tax profit,
- expected after-tax profit/hr.

Profit/hr for uncertain travel should be:

\[
\text{expected profit/hr}
=
\frac{E[\Pi]}
{T_{occupied}}
\]

not successful-trip profit multiplied later by probability in a way that can double-count or misstate risk.

---

## 13. Value of waiting

Waiting can be a rational action because a near-future poll may reveal valuable information.

Approximate:

\[
VOI_\Delta
=
E_Y[
\max_a E[U(a)\mid\mathcal D,Y]
]
-
\max_a E[U(a)\mid\mathcal D]
-
C_{delay}(\Delta)
\]

Do not implement a full nested POMDP initially.

A practical one-step approximation can enumerate likely next-poll outcomes:

- still OOS,
- newly restocked,
- still stocked,
- quantity lower,
- sold out,
- provider missing.

If the expected information gain exceeds the cost of delay, recommendation can be WAIT even when leaving immediately has positive EV.

---

## 14. Recommended model architectures

| Architecture | Accuracy potential | Sparse data | Censoring | Regime change | Runtime | Interpretability | Recommendation |
|---|---:|---:|---:|---:|---:|---:|---|
| Empirical cycles + Monte Carlo | high with sufficient history | moderate | good if interval bounds retained | moderate | low | excellent | strong baseline |
| Bayesian renewal + survival/depletion | high | good | excellent | good | moderate | high | recommended core direction |
| State-space + particle filter | potentially very high | good | good | excellent | moderate/high | moderate | later upgrade |
| Full POMDP | conceptually complete | model-dependent | excellent | excellent | very high | low | conceptual only |

### Recommended implementation target

Start with:

> **recency-weighted empirical joint-cycle resampling + interval-censored boundary representation + survival-style useful-duration summaries + Monte Carlo forward simulation**

This is simpler, testable, interpretable, and directly addresses the largest conceptual errors.

---

## 15. Recommended production pipeline

```text
RAW MARKET SNAPSHOTS
        |
        v
EVIDENCE / CENSORING EXTRACTOR
        |
        +-- restock interval bounds
        +-- sellout interval bounds
        +-- quantity trajectory
        +-- price/MV context
        +-- quality/freshness metadata
        |
        v
CYCLE HISTORY
        |
        v
ADAPTIVE MODEL
        |
        +-- weighted empirical cycles
        +-- OOS/restock duration model
        +-- useful-stock duration model
        +-- regime/change detector
        |
        v
POSTERIOR-PREDICTIVE SIMULATOR
        |
        +-- simulate enough future cycles
        +-- sample stock trajectories
        +-- sample price/value uncertainty where useful
        |
        v
ARRIVAL CURVES
        |
        +-- pAnyStock
        +-- pTargetQty
        +-- expectedQty
        +-- expectedProfit
        +-- downside
        |
        v
TRAVEL FEASIBILITY TRANSFORM
        |
        v
DEPARTURE CURVES
        |
        v
DECISION OPTIMIZER
        |
        v
ONE AUTHORITATIVE DECISION OBJECT
        |
        v
RAINMETER/LUA PRESENTATION
```

Heavy statistical work should not run inside Rainmeter/Lua.

Rainmeter should consume cached forecast/decision artifacts.

---

## 16. Raw-data schema

Persist immutable raw observations where feasible:

```text
timestamp
itemId
countryId
reportedQuantity
foreignPrice
domesticMarketValue
source
sourceTimestamp
collectionTimestamp
freshness
requestStatus
```

Derived cycle records:

```text
cycleId
itemId
countryId

restockLowerAt
restockUpperAt
selloutLowerAt
selloutUpperAt

initialQuantityLower
initialQuantityUpper

completeCycle
rightCensored
leftCensored
boundaryQuality
collectionGapSeconds

foreignPriceAtRestock
domesticMvAtRestock
marginAtRestock

hourOfDay
weekday

modelEligible
```

Do not delete incomplete/right-censored cycles solely because endpoints are missing.

---

## 17. Forecast artifact

The heavy process can publish something like:

```text
itemId
generatedAt
modelVersion
horizonStart
horizonEnd
gridSeconds

arrivalTime[]
pAnyStock[]
pTargetQty[]
expectedQty[]
expectedProfit[]
expectedProfitPerHour[]
profitP10[]
profitP50[]
profitP90[]

bestArrivalAt
bestDepartureAt
lastActionableDepartureAt
nextActionableDepartureAt

bestUtility
effectiveSampleSize
changeProbability
dataQuality
```

A compacted representation is acceptable if raw arrays are too expensive, but the stochastic model should conceptually generate these curves.

---

## 18. Simulation strategy

For each item:

1. identify current partially observed state,
2. sample next restock conditional on history,
3. sample joint restock state:
   - quantity,
   - foreign price,
   - contextual variables,
4. sample a historical/empirical depletion trajectory or useful-stock duration,
5. simulate sellout/useful-stock threshold,
6. sample next OOS duration,
7. repeat until beyond latest relevant arrival,
8. evaluate all candidate arrivals,
9. aggregate outcomes across worlds.

Do not rerun thousands of simulations every Rainmeter frame.

Recompute when:

- new stock observation arrives,
- price/MV materially changes,
- player travel state changes,
- a forecast boundary passes,
- change/regime probability changes materially,
- cache becomes stale.

UI countdowns can update every second against cached timestamps.

---

## 19. Adaptive grid resolution

One-minute grids are fine for normal items but may be too coarse for very short stock bursts.

Use adaptive resolution around narrow peaks.

Engineering heuristic to test:

\[
\Delta t_{grid}
\le
\frac15
\min(
\text{median useful stock duration},
\text{relevant probability peak width}
)
\]

This is a proposed implementation heuristic, not a theoretical requirement.

---

## 20. One authoritative action state

Presentation must not infer OPEN/CLOSED/SAFE independently.

Use one mutually exclusive action:

```text
INSUFFICIENT_DATA
NO_ACTIONABLE_TRIP
WAIT
LEAVE_IN
LEAVE_NOW
LEAVE_BEFORE
COMMITTED
BUY_NOW
MISSED_TARGET
```

Attach attributes:

```text
reason
successProbability
targetQuantityProbability
expectedQuantity
expectedProfit
expectedProfitPerHour
confidenceTier

bestDepartureAt
bestArrivalAt
lastGoodDepartureAt
nextGoodDepartureAt

effectiveSampleSize
dataQuality
marketDataAgeSeconds
changeProbability
```

Both card and tooltip consume this same object.

This makes contradictions such as:

```text
OPEN NOW
Window Closed
```

impossible by construction.

### Suggested semantics

**INSUFFICIENT_DATA**
- posterior dominated by stale/weak evidence,
- too few informative cycles,
- show COLLECTING DATA.

**NO_ACTIONABLE_TRIP**
- future opportunities exist, but none meet utility/risk threshold,
- show best achievable probability/EV.

**WAIT**
- another observation or later departure dominates leaving now.

**LEAVE_IN**
- best departure materially later than now.

**LEAVE_NOW**
- now is near-optimal by utility and passes minimum action thresholds.

**LEAVE_BEFORE**
- leaving now remains good but delay eventually causes material degradation.

**COMMITTED**
- already outbound to destination; report landing success distribution.

**BUY_NOW**
- already abroad at target and sufficient live/predicted quantity exists.

**MISSED_TARGET**
- a named target peak has passed; does not imply no future cycles exist.

Secondary confidence labels can be HIGH / MODERATE / SPECULATIVE, but they must be empirically calibrated.

Retire "GUARANTEED" unless calibration can truly justify it.

---

## 21. Edge-case behavior matrix

| Scenario | Model emphasis | UI behavior |
|---|---|---|
| Flight << stock duration | live survival/current cycle | LEAVE NOW / BEFORE if stock likely survives |
| Flight ~= stock duration | joint timing-duration uncertainty | probability/EV-driven |
| Flight >> stock duration | future-cycle simulation | target future peak or NO TRIP |
| Flight << OOS delay | restock-time distribution | usually WAIT |
| Flight ~= OOS delay | arrival probability curve | target departure |
| Flight >> OOS delay | later cycles | choose nth future cycle |
| Flight < full cycle | current/next cycle can dominate | normal optimizer |
| Flight ~= full cycle | renewal phase relevant | phase-aware optimization |
| Flight > one cycle | multi-cycle mandatory | do not reference only current/next |
| Flight > several cycles | renewal simulation | later-cycle peak may dominate |
| Restock variance << stock life | broad high-probability region possible | LEAVE BEFORE |
| Restock variance ~= stock life | probabilistic peak/window | LEAVE IN/NOW |
| Restock variance >> stock life | low narrow peak | SPECULATIVE or NO TRIP |
| Extremely short burst | high-resolution grid | target peak only if EV justifies |
| Nearly permanent stock | current survival dominates | LEAVE NOW |
| Demand accelerates | recency/change detection | confidence drops rapidly |
| Demand collapses | recency/change detection | cautiously extend survival |
| Price materially changes | economics + possible demand covariate | rerank immediately |
| Restock schedule changes | change detector | widen forecast / possibly WAIT |
| Missing observations | censor/gap-aware | lower confidence |
| Poll interval > stock life | heavy interval censoring | often speculative |
| Returning player | departure feasibility | no departure before landing |
| Outbound to target | committed landing | COMMITTED |
| Abroad at target | near-zero travel delay | BUY NOW / WAIT |
| Traveling elsewhere | legal-feasibility constraint | no false LEAVE NOW |
| Current stock cannot survive | ignore current-stock branch | evaluate future cycles |
| Current stock probably survives | live survival | LEAVE NOW / BEFORE |
| Quantity below carrying capacity | quantity distribution | partial-purchase EV |
| Several cycles before arrival | multi-renewal simulation | select best future peak |
| Sparse/contradictory history | broad prior/uncertainty | INSUFFICIENT or SPECULATIVE |

---

## 22. Validation and calibration

Use strict rolling-origin replay.

At historical time \(t_j\):

1. load only data known at \(t_j\),
2. fit/update exactly as production would,
3. generate probability/utility curves,
4. save recommendation,
5. advance,
6. score against later observations.

Never train on future cycles and "predict" the past.

### Forecast metrics

- Brier score for any stock,
- Brier score for useful quantity threshold,
- log loss,
- reliability/calibration diagrams,
- CRPS for full distributions where practical,
- restock interval coverage,
- sellout interval coverage,
- quantity MAE/RMSE where state is actually observed.

### Decision metrics

- successful-trip rate,
- realized profit,
- realized profit/hr,
- failed-trip rate,
- arrival-before-restock rate,
- arrival-after-useful-stock rate,
- missed-opportunity rate,
- false "safe" / overconfident recommendation rate,
- regret vs hindsight-optimal feasible action.

### Required baselines

Compare against:

1. mean restock,
2. median cycle,
3. current Safe logic,
4. current Best-Hit logic,
5. expected restock minus travel time,
6. first candidate where modeled success >50%,
7. empirical Monte Carlo with no covariates.

Do not ship added complexity unless it improves forward decision outcomes.

### Calibration

A displayed 70% should resolve near 70% over repeated comparable cases.

Possible calibration layers after model selection:

- isotonic regression,
- beta calibration,
- logistic/Platt-style calibration where appropriate.

Calibration must use held-out predictions.

---

## 23. Evidence quality model

Differentiate:

1. trustworthy exact upstream boundary,
2. adjacent fresh polls bracketing transition,
3. wide interval across collection gap,
4. stale inferred boundary,
5. provider unavailable,
6. frozen snapshot,
7. incomplete cycle,
8. full verified cycle,
9. left-censored cycle,
10. right-censored cycle.

Quality should affect:

- event likelihood,
- sample weight,
- model confidence,
- whether probability is displayed prominently.

Do not convert missing data into OOS.

---

## 24. Migration strategy from current Safe/Best logic

Do not replace the visible system immediately.

### Phase 1 — evidence foundation

- preserve raw snapshots,
- add interval-censored restock/sellout bounds,
- preserve incomplete cycles,
- formalize travel feasibility,
- consolidate duplicate/competing window pipelines.

### Phase 2 — stochastic v1 in shadow mode

Implement:

> recency-weighted empirical joint-cycle resampling + Monte Carlo

Produce forecast artifacts alongside current Safe/Best output.

Do not change visible primary UI yet.

### Phase 3 — decision engine

Create one authoritative decision contract.

The old presentation remains active, but stochastic decisions are persisted for comparison.

### Phase 4 — backtesting/live scoring

Score old and new systems.

### Phase 5 — promote stochastic system

Only after calibration and decision metrics are satisfactory:

- make stochastic decision object primary,
- derive all UI text from it,
- retire Safe/Best as forecasting primitives,
- keep legacy metrics only as debug/baseline if useful.

### Phase 6 — optional adaptive sophistication

Only after evidence supports it:

- learned recency weighting,
- time-of-day effects,
- price/margin covariates,
- hierarchical pooling,
- explicit survival/hazard regression,
- latent demand filtering,
- more advanced value-of-information logic.

---

## 25. Assumptions the implementation must reject

Do not assume:

- next restock time is deterministic,
- stock duration is deterministic,
- the mean represents a skewed/multimodal distribution,
- restock and sellout are independent,
- price and demand are independent,
- depletion is linear,
- zero stock reveals exact demand,
- poll timestamp equals event timestamp,
- all historical cycles deserve equal weight,
- current stock matters for long flights,
- immediate next cycle is always the target,
- historical 100% overlap means future certainty,
- stale/missing data means OOS,
- all items need the same model,
- probability alone determines action,
- every positive-EV trip means leave now,
- presentation should infer OPEN/CLOSED independently.

---

## 26. Production pseudocode

### Model update

```text
function UpdateMarketModel(item, observations, now):

    freshObs = ValidateAndClassifyObservations(observations)

    boundaries = ExtractCensoredBoundaries(
        freshObs,
        preserveIntervals = true,
        neverMidpointImputeAsTruth = true
    )

    cycles = BuildCycles(
        restockIntervals = boundaries.restocks,
        selloutIntervals = boundaries.sellouts,
        quantitySnapshots = freshObs.quantity,
        priceSnapshots = freshObs.price
    )

    changePosterior = UpdateChangePointModel(
        recentCycleFeatures(cycles)
    )

    recencyWeights = ComputeAdaptiveWeights(
        cycles,
        changePosterior
    )

    restockModel = FitOrUpdateRestockModel(
        cycles,
        intervalCensoring = true,
        weights = recencyWeights
    )

    usefulDurationModel = FitOrUpdateUsefulStockSurvival(
        cycles,
        intervalCensoring = true,
        weights = recencyWeights
    )

    depletionModel = UpdateEmpiricalTrajectoryModel(
        cycles,
        preserveJointCycleSamples = true,
        censoredSellouts = true
    )

    economicsModel = UpdatePriceAndValueModel(
        foreignPrice,
        domesticValue,
        configuredFeeRate
    )

    return ModelBundle(...)
```

### Forecast

```text
function ForecastItem(model, playerState, item, now):

    feasibleDepartures =
        GetFeasibleDepartureTimes(
            playerState,
            item.country,
            now
        )

    if playerState == OUTBOUND_TO_ITEM_COUNTRY:
        feasibleArrivals = [playerState.landingTime]
    else:
        feasibleArrivals =
            MapDeparturesToArrivals(
                feasibleDepartures,
                item.country.travelTime
            )

    horizon = max(feasibleArrivals) + safetyMargin

    for simulation in 1..M:

        world = InitializeCurrentLatentMarketState(model)

        while world.time < horizon:

            restock =
                SampleNextRestockConditionalOnHistory(model)

            initialStock, foreignPrice, context =
                SampleJointRestockState(model, restock)

            depletionTrajectory =
                SampleDepletionTrajectory(
                    model,
                    initialStock,
                    foreignPrice,
                    context
                )

            sellout =
                DetermineUsefulStockExit(
                    depletionTrajectory,
                    thresholds
                )

            AppendCycle(world, restock, depletionTrajectory, sellout)

        worlds.append(world)
```

### Aggregate arrivals

```text
for arrival in feasibleArrivals:

    quantities = []
    profits = []

    for world in worlds:

        q = QuantityAt(world, arrival)

        purchasable =
            min(
                q,
                player.capacity,
                configuredPurchaseTarget
            )

        unitProfit =
            AfterTaxResaleValue(world, arrival)
            - ForeignPrice(world, arrival)

        profit =
            max(0, unitProfit) * purchasable

        quantities.append(q)
        profits.append(profit)

    pAnyStock       = mean(quantities > 0)
    pTargetQty      = mean(quantities >= requiredQty)
    expectedQty     = mean(min(quantities, player.capacity))
    expectedProfit  = mean(profits)
    profitP10       = quantile(profits, 0.10)
    profitP50       = quantile(profits, 0.50)
    profitP90       = quantile(profits, 0.90)
```

### Optimize departures

```text
for departure in feasibleDepartures:

    arrival = ArrivalFor(departure)

    tripHours =
        OccupiedTravelDuration(
            playerState,
            departure,
            item.country
        )

    opportunityCost =
        EstimateOpportunityCost(...)

    riskPenalty =
        RiskPreferencePenalty(...)

    utility[departure] =
        forecast[arrival].expectedProfit
        - opportunityCost
        - riskPenalty

    expectedProfitPerHour[departure] =
        forecast[arrival].expectedProfit / tripHours
```

### Decide

```text
bestAction = argmax(utility)

waitValue =
    ApproximateNextPollValueOfInformation(...)

if evidenceTooWeak:
    action = INSUFFICIENT_DATA
else if maxUtility < configuredMinimum:
    action = NO_ACTIONABLE_TRIP
else if playerAlreadyOutboundToTarget:
    action = COMMITTED
else if playerAlreadyAbroadAtTarget:
    action = BUY_NOW or WAIT
else if waitValue > utility[bestAction] + tolerance:
    action = WAIT
else:
    action = ClassifyBestDeparture(
        now,
        bestAction,
        utilityCurve,
        probabilityCurve
    )
```

---

## 27. Synthetic worked-case conclusions

These examples are conceptual, not actual Torn estimates.

### A. Slow seller; flight shorter than stock duration

Probability rises into a broad plateau.

Expected behavior:
- WAIT while early,
- LEAVE IN near rising edge,
- LEAVE NOW / LEAVE BEFORE through near-optimal region.

### B. Stock duration roughly equal to flight

Timing sensitivity is high.

Use probability and utility rather than broad deterministic intervals.

### C. Fast seller; stock duration far shorter than flight

Current stock is irrelevant.

Target a future-cycle probability peak.

Peak may still be speculative.

### D. Stock duration shorter than restock uncertainty

A mathematically optimal departure can have very low success.

Correct UI may be NO ACTIONABLE TRIP despite a known best timestamp.

### E. Travel longer than one complete cycle

Immediate next restock is not enough.

Simulate later cycles and choose best arrival phase.

### F. Travel longer than several cycles

Current stock state is nearly irrelevant.

Nth future renewal can dominate.

### G. Visible current stock but mathematically unreachable

Discard current-stock branch for decision purposes.

Evaluate next/later cycles.

### H. Already outbound

No departure optimization remains.

Display committed landing success probability, expected quantity, and economics.

### I. Returning to Torn

Departure domain begins at return landing.

Never recommend a pre-landing departure.

### J. Demand suddenly accelerates

A regime-aware model should:
- widen uncertainty immediately,
- sharply reduce reliance on old long-stock cycles,
- move optimum earlier,
- downgrade confidence until new behavior stabilizes.

---

## 28. Key literature behind the design

These are the research anchors used for the conclusions above.

### Interval censoring / survival

- Turnbull, B. W. (1976), *The Empirical Distribution Function with Arbitrarily Grouped, Censored and Truncated Data*.
  - https://academic.oup.com/jrsssb/article/38/3/290/7027379
- Cox, D. R. (1972), *Regression Models and Life-Tables*.
  - https://rss.onlinelibrary.wiley.com/doi/10.1111/j.2517-6161.1972.tb00899.x
- Finkelstein, D. M. (1986), *A Proportional Hazards Model for Interval-Censored Failure Time Data*.
  - https://pubmed.ncbi.nlm.nih.gov/3814726/
- Andersen, P. K. & Gill, R. D. (1982), *Cox's Regression Model for Counting Processes: A Large Sample Study*.
  - https://projecteuclid.org/journals/annals-of-statistics/volume-10/issue-4/Coxs-Regression-Model-for-Counting-Processes--A-Large-Sample/10.1214/aos/1176345976.short

### Recurrent / renewal processes

- Alternating renewal process background:
  - https://stats.libretexts.org/Bookshelves/Probability_Theory/Probability_Mathematical_Statistics_and_Stochastic_Processes_%28Siegrist%29/15%3A_Renewal_Processes/15.05%3A_Alternating_Renewal_Processes
- Renewal-reward background:
  - https://arxiv.org/abs/1404.5601

### Lost sales / censored demand

- Nahmias, S. (1994), *Demand Estimation in Lost Sales Inventory Systems*.
  - https://ideas.repec.org/a/wly/navres/v41y1994i6p739-757.html
- Lariviere, M. A. & Porteus, E. L. (1999), *Stalking Information: Bayesian Inventory Management with Unobserved Lost Sales*.
  - https://ideas.repec.org/a/inm/ormnsc/v45y1999i3p346-363.html
- Chen, Chao & Shi (2021), nonparametric learning for pricing/inventory under lost sales and censored demand.
  - https://pubsonline.informs.org/doi/10.1287/moor.2020.1084

### Regime change / online adaptation

- Hamilton, J. D. (1989), Markov regime switching.
  - https://www.jstor.org/stable/1912559
- Adams & MacKay (2007), *Bayesian Online Changepoint Detection*.
  - https://arxiv.org/abs/0710.3742

### Particle filtering / state estimation

- Gordon, Salmond & Smith (1993), nonlinear/non-Gaussian Bayesian state estimation.
  - https://digital-library.theiet.org/doi/10.1049/ip-f-2.1993.0015

### POMDP framing

- Kaelbling, Littman & Cassandra (1998), *Planning and Acting in Partially Observable Stochastic Domains*.
  - https://www.sciencedirect.com/science/article/pii/S000437029800023X

### Value of information

- Frazier, Powell & Dayanik, Knowledge Gradient.
  - https://people.orie.cornell.edu/pfrazier/pub/2007_FrazierPowellDayanik.pdf

### Forecast scoring/calibration

- Brier, G. W. (1950), probability forecast verification.
  - https://journals.ametsoc.org/view/journals/mwre/78/1/1520-0493_1950_078_0001_vofeit_2_0_co_2.xml
- Gneiting & Raftery (2007), *Strictly Proper Scoring Rules, Prediction, and Estimation*.
  - https://www.tandfonline.com/doi/abs/10.1198/016214506000001437
- Kull, Silva Filho & Flach (2017), beta calibration.
  - https://proceedings.mlr.press/v54/kull17a.html

---

## 29. Immediate implementation recommendation

The next coding run should **not** attempt the entire research stack.

Implement only the foundation plus stochastic-v1 shadow mode:

1. inspect current collection/history schemas,
2. preserve/derive interval-censored restock and sellout bounds,
3. retain incomplete/right-censored cycles,
4. formalize travel-feasible departure/arrival mapping,
5. resolve the existing authoritative-window pipeline split,
6. implement a simple recency-weighted empirical cycle simulator,
7. simulate multiple future cycles through the latest relevant arrival,
8. publish a stochastic forecast artifact,
9. do **not** replace current visible Safe/Best UI yet,
10. add deterministic tests and a replay/backtest scaffold,
11. document limitations and migration path.

The stochastic artifact should at minimum contain:

```text
pAnyStock
pTargetQty
expectedQty
expectedProfit
expectedProfitPerHour
bestDepartureAt
bestArrivalAt
lastActionableDepartureAt
bestUtility
effectiveSampleSize
dataQuality
modelVersion
```

The visible UI should remain unchanged until the new system can be compared against legacy outputs.

---

## 30. Context for the current repository

Recent inspection found that the repository currently contains both:

- `WindowPlan.ps1`
- `WindowPlanRefiner.ps1`

and presentation code that expects richer fields associated with the refiner, while the normal update path has historically invoked `WindowPlan.ps1`.

Before promoting a new stochastic model, establish **one authoritative forecasting pipeline** and prevent stale fields from older generations from surviving into presentation.

Also preserve the existing requirement that economics use the configured upstream tax/trader rate and that profit/hr uses the project's round-trip convention unless deliberately revised.

---

## 31. Definition of done for the temporary research handoff

This file has served its purpose once the repository contains:

- a durable architecture document for the stochastic model,
- tests validating interval-censored evidence,
- stochastic forecast artifacts,
- shadow-mode legacy-vs-new comparison,
- a backtest/replay harness,
- one authoritative decision contract,
- no independent contradictory window-state rendering,
- a documented plan for retiring legacy Safe/Best logic.

At that point, delete this TEMP file.
