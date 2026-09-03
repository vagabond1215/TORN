$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath=Join-Path $ProjectRoot '@Resources\Scripts\WindowPlanRefiner.ps1'
. $scriptPath -SkipMain

$failures=New-Object System.Collections.Generic.List[string]
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { $script:failures.Add($Message) } }
function Assert-Equal($Actual,$Expected,[string]$Message) { if ($Actual -ne $Expected) { $script:failures.Add("$Message Expected=$Expected Actual=$Actual") } }
function Assert-Near([double]$Actual,[double]$Expected,[double]$Tolerance,[string]$Message) { if ([Math]::Abs($Actual-$Expected) -gt $Tolerance) { $script:failures.Add("$Message Expected=$Expected Actual=$Actual") } }

$anchor=100000L

Assert-True (Test-WindowStaleSourceCanUseRecurringModel -LiveProjectionMode 'stale-source' -AnchorAt 90000L) 'A stale provider snapshot with a verified phase anchor should continue into recurring forecast geometry.'
Assert-True (-not (Test-WindowStaleSourceCanUseRecurringModel -LiveProjectionMode 'stale-source' -AnchorAt 0L)) 'A stale provider snapshot without any verified phase anchor must remain non-informative.'
Assert-True (-not (Test-WindowStaleSourceCanUseRecurringModel -LiveProjectionMode 'live-depletion' -AnchorAt 90000L)) 'The stale-source recurring fallback gate must not replace normal live-cycle authority.'

$cycles=@(
    [pscustomobject]@{restockDelaySeconds=3600L;availabilitySeconds=1800L;soldOutAt=10L}, # period 5400
    [pscustomobject]@{restockDelaySeconds=4200L;availabilitySeconds=1800L;soldOutAt=11L}, # period 6000
    [pscustomobject]@{restockDelaySeconds=4800L;availabilitySeconds=1800L;soldOutAt=12L}  # period 6600
)
$model=Get-StableRecurringScenarioModel -Cycles $cycles -AnchorAt $anchor -AnchorPhase sellout -NowEpoch $anchor -FutureHorizonSeconds 50000
Assert-Equal ([long]$model.medianPeriodSeconds) 6000L 'Stable recurring model should use the median complete-cycle period.'
$group0=@($model.groups | Where-Object { [int]$_.ordinal -eq 0 } | Select-Object -First 1)[0]
$group1=@($model.groups | Where-Object { [int]$_.ordinal -eq 1 } | Select-Object -First 1)[0]
Assert-Equal ([long]$group0.earlyRestockAt) ($anchor+3600L) 'First-cycle earliest restock should retain empirical minimum delay.'
Assert-Equal ([long]$group0.lateRestockAt) ($anchor+4800L) 'First-cycle latest restock should retain empirical maximum delay.'
Assert-Equal (([long]$group1.lateRestockAt-[long]$group1.earlyRestockAt)) 1200L 'Next-cycle restock uncertainty must not compound with ordinal.'
Assert-Equal ([long]$group1.earlyRestockAt) ($anchor+6000L+3600L) 'Immediate next group should advance by median period plus one-cycle delay variance.'

# A collector outage / missed transition may create one implausibly long apparent cycle.
# Keep it in analytics, but exclude it from the live forecast when a stable majority exists.
$outlierCycles=@(
    [pscustomobject]@{restockDelaySeconds=3500L;availabilitySeconds=1700L;soldOutAt=20L},
    [pscustomobject]@{restockDelaySeconds=3600L;availabilitySeconds=1800L;soldOutAt=21L},
    [pscustomobject]@{restockDelaySeconds=3700L;availabilitySeconds=1800L;soldOutAt=22L},
    [pscustomobject]@{restockDelaySeconds=3800L;availabilitySeconds=1700L;soldOutAt=23L},
    [pscustomobject]@{restockDelaySeconds=3900L;availabilitySeconds=1800L;soldOutAt=24L},
    [pscustomobject]@{restockDelaySeconds=72000L;availabilitySeconds=1800L;soldOutAt=25L}
)
$filtered=@(Get-StableWindowUsableCycles -Cycles $outlierCycles)
Assert-Equal $filtered.Count 5 'Stable forecast should discard a many-hour pseudo-cycle when five normal recent cycles agree.'
Assert-True (-not (@($filtered | Where-Object { [long]$_.restockDelaySeconds -gt 10000L }).Count -gt 0)) 'Outage-length restock delay must not remain in live forecast evidence.'

# Current live geometry should prefer a sufficiently populated recent regime over an
# older cycle whose total period looks normal but whose OOS/stock split is very different.
# This models the Japan Xanax failure mode: the old full-period filter could preserve a
# short-delay/long-availability cycle and pull Early Restock far earlier than the recent data.
$regimeAnchor=3000000L
$regimeLatest=2000000L
$regimeCycles=@(
    [pscustomobject]@{restockDelaySeconds=6576L;availabilitySeconds=1650L;soldOutAt=$regimeLatest},
    [pscustomobject]@{restockDelaySeconds=6792L;availabilitySeconds=1600L;soldOutAt=($regimeLatest-7200L)},
    [pscustomobject]@{restockDelaySeconds=6882L;availabilitySeconds=1700L;soldOutAt=($regimeLatest-14400L)},
    [pscustomobject]@{restockDelaySeconds=7362L;availabilitySeconds=1550L;soldOutAt=($regimeLatest-21600L)},
    # Older than 12h, but deliberately similar total period so period-only filtering would keep it.
    [pscustomobject]@{restockDelaySeconds=1800L;availabilitySeconds=6600L;soldOutAt=($regimeLatest-54000L)}
)
$regimeFiltered=@(Get-StableWindowUsableCycles -Cycles $regimeCycles)
Assert-Equal $regimeFiltered.Count 4 'Four completed cycles in the latest 12-hour regime should define live window geometry.'
Assert-True (-not (@($regimeFiltered | Where-Object { [long]$_.restockDelaySeconds -eq 1800L }).Count -gt 0)) 'Older same-period short-delay cycle must not widen current-regime restock bounds.'
$regimeModel=Get-StableRecurringScenarioModel -Cycles $regimeCycles -AnchorAt $regimeAnchor -AnchorPhase sellout -NowEpoch $regimeAnchor -FutureHorizonSeconds 50000
$regimeGroup0=@($regimeModel.groups | Where-Object { [int]$_.ordinal -eq 0 } | Select-Object -First 1)[0]
Assert-Equal ([long]$regimeGroup0.earlyRestockAt) ($regimeAnchor+6576L) 'Recent-regime earliest restock should use recent minimum OOS delay.'
Assert-Equal ([long]$regimeGroup0.lateRestockAt) ($regimeAnchor+7362L) 'Recent-regime latest restock should use recent maximum OOS delay.'

# Forecast eligibility follows each market's cadence without deleting retained history.
$fastCadenceCycles=@(
    [pscustomobject]@{restockDelaySeconds=7000L;availabilitySeconds=1400L;soldOutAt=101L},
    [pscustomobject]@{restockDelaySeconds=7200L;availabilitySeconds=1200L;soldOutAt=102L},
    [pscustomobject]@{restockDelaySeconds=7400L;availabilitySeconds=1000L;soldOutAt=103L},
    [pscustomobject]@{restockDelaySeconds=6900L;availabilitySeconds=1500L;soldOutAt=104L},
    [pscustomobject]@{restockDelaySeconds=7100L;availabilitySeconds=1300L;soldOutAt=105L},
    [pscustomobject]@{restockDelaySeconds=6959L;availabilitySeconds=424027L;soldOutAt=106L},
    [pscustomobject]@{restockDelaySeconds=229L;availabilitySeconds=36L;soldOutAt=107L}
)
$fastFiltered=@(Select-CadenceAwareForecastCycles -Cycles $fastCadenceCycles)
Assert-Equal $fastFiltered.Count 5 'Fast-market forecasts should reject multi-day capture gaps and implausibly short pseudo-cycles.'
Assert-True (@($fastCadenceCycles).Count -eq 7) 'Cadence filtering must not mutate retained history.'

$slowCadenceCycles=@(
    [pscustomobject]@{restockDelaySeconds=90000L;availabilitySeconds=18000L;soldOutAt=201L},
    [pscustomobject]@{restockDelaySeconds=100000L;availabilitySeconds=15000L;soldOutAt=202L},
    [pscustomobject]@{restockDelaySeconds=110000L;availabilitySeconds=12000L;soldOutAt=203L},
    [pscustomobject]@{restockDelaySeconds=120000L;availabilitySeconds=20000L;soldOutAt=204L},
    [pscustomobject]@{restockDelaySeconds=300000L;availabilitySeconds=40000L;soldOutAt=205L}
)
$slowFiltered=@(Select-CadenceAwareForecastCycles -Cycles $slowCadenceCycles)
Assert-Equal $slowFiltered.Count 5 'Once-daily or slower markets should retain a wider cadence-relative forecast history.'

$boundaryCycles=@(
    [pscustomobject]@{restockDelaySeconds=6000L;availabilitySeconds=900L;soldOutAt=401L},
    [pscustomobject]@{restockDelaySeconds=6060L;availabilitySeconds=960L;soldOutAt=402L},
    [pscustomobject]@{restockDelaySeconds=6120L;availabilitySeconds=1020L;soldOutAt=403L},
    [pscustomobject]@{restockDelaySeconds=6180L;availabilitySeconds=1080L;soldOutAt=404L},
    [pscustomobject]@{restockDelaySeconds=6240L;availabilitySeconds=1140L;soldOutAt=405L}
)
$boundaryPolicy=Get-CycleBoundaryPolicy -Cycles $boundaryCycles -ExpectedPollIntervalSeconds 60
Assert-Equal ([long]$boundaryPolicy.selloutSafeGapSeconds) 180L 'Safe boundary gap should never be less than three expected polls.'
Assert-Equal ([long]$boundaryPolicy.selloutHardGapSeconds) 1020L 'Sellout hard gap should be capped by normal availability duration.'
Assert-Equal (Get-CycleBoundaryQuality -GapSeconds 180 -Policy $boundaryPolicy -Phase sellout) 'bounded' 'A short gap within half-variance/poll tolerance should remain bounded evidence.'
Assert-Equal (Get-CycleBoundaryQuality -GapSeconds 1020 -Policy $boundaryPolicy -Phase sellout) 'unknown_gap' 'A phase-length gap must not fabricate an exact sellout boundary.'

$eligibilityCycles=@(
    [pscustomobject]@{restockDelaySeconds=6000L;availabilitySeconds=900L;soldOutAt=501L;availabilityEligible=$true;restockDelayEligible=$true;trendEligible=$true},
    [pscustomobject]@{restockDelaySeconds=6060L;availabilitySeconds=960L;soldOutAt=502L;availabilityEligible=$true;restockDelayEligible=$true;trendEligible=$false},
    [pscustomobject]@{restockDelaySeconds=6120L;availabilitySeconds=1020L;soldOutAt=503L;availabilityEligible=$false;restockDelayEligible=$true;trendEligible=$false}
)
Assert-Equal (@(Select-CadenceAwareForecastCycles -Cycles $eligibilityCycles -Purpose Forecast).Count) 2 'Forecast selection should exclude cycles with an unknown required boundary.'
Assert-Equal (@(Select-CadenceAwareForecastCycles -Cycles $eligibilityCycles -Purpose Trend).Count) 1 'Trend selection should also exclude uncertain bounded cycles.'

$verifiedBoundaryCycles=@(
    [pscustomobject]@{schemaVersion=1;restockDelaySeconds=6000L;availabilitySeconds=900L;soldOutAt=601L},
    [pscustomobject]@{schemaVersion=2;restockDelaySeconds=6060L;availabilitySeconds=960L;soldOutAt=602L;forecastEligible=$false;availabilityEligible=$false;restockDelayEligible=$true;restockBoundaryQuality='bounded';soldOutBoundaryQuality='unknown_gap';previousSellOutBoundaryQuality='bounded'},
    [pscustomobject]@{schemaVersion=2;restockDelaySeconds=6120L;availabilitySeconds=1020L;soldOutAt=603L;forecastEligible=$true;availabilityEligible=$true;restockDelayEligible=$true;trendEligible=$true;restockBoundaryQuality='bounded';soldOutBoundaryQuality='observed';previousSellOutBoundaryQuality='recovered'}
)
$verifiedFiltered=@(Select-CadenceAwareForecastCycles -Cycles $verifiedBoundaryCycles -Purpose Forecast)
Assert-Equal $verifiedFiltered.Count 1 'Runtime legacy and missing-boundary cycles must not teach the forecast.'
Assert-Equal ([long]$verifiedFiltered[0].soldOutAt) 603L 'Observed/bounded/recovered boundary evidence remains forecast-eligible.'

$projectionCycles=@(
    [pscustomobject]@{restockDelaySeconds=6900L;availabilitySeconds=1200L;soldOutAt=301L},
    [pscustomobject]@{restockDelaySeconds=7200L;availabilitySeconds=1300L;soldOutAt=302L},
    [pscustomobject]@{restockDelaySeconds=7500L;availabilitySeconds=1400L;soldOutAt=303L}
)
$projectionState=[pscustomobject]@{lastSellOutAt=5000L;activeCycle=[pscustomobject]@{restockAt=6000L;restockQuantity=2400L}}
$projection=Get-LiveCycleProjection -CurrentStock 600L -SourceTimestamp 10000L -DestinationState $projectionState -Cycles $projectionCycles -NowEpoch 10000L
Assert-Equal ([string]$projection.mode) 'live-depletion' 'Fresh positive stock should use a live depletion projection before recurring windows.'
Assert-Equal ([long]$projection.activeSelloutEstimateAt) 11334L 'Live sellout should project remaining stock from observed cycle depletion.'
Assert-Equal ([long]$projection.medianRestockDelaySeconds) 7200L 'Next restock should use the cleaned median OOS delay.'
Assert-Equal ([long]$projection.nextRestockEstimateAt) 18534L 'Restock projection must begin after the projected sellout.'


$phaseEngine=[pscustomobject]@{observedMarkets=[pscustomobject]@{};destinations=[pscustomobject]@{}}
$phaseEngine.observedMarkets|Add-Member NoteProperty 'japan:123' ([pscustomobject]@{lastStock=5000L;sourceTimestamp=1300L})
$phaseEngine.destinations|Add-Member NoteProperty 'japan:123' ([pscustomobject]@{
    lastSellOutAt=1000L
    lastSellOutBoundaryQuality='observed'
    activeCycle=[pscustomobject]@{restockAt=1200L;restockQuantity=5000L}
})
$restockedPhase=Get-WindowObservedPhase -Engine $phaseEngine -Key 'japan:123'
Assert-True (-not[bool]$restockedPhase.unresolvedOos) 'A later observed/reconciled restock must invalidate the preceding OoS phase even if the stock source later becomes stale.'
Assert-Equal ([long]$restockedPhase.activeRestockAt) 1200L 'Observed-phase helper should retain the later restock anchor.'

$phaseEngine.observedMarkets.PSObject.Properties['japan:123'].Value=[pscustomobject]@{lastStock=0L;sourceTimestamp=1300L}
$phaseEngine.destinations.PSObject.Properties['japan:123'].Value=[pscustomobject]@{
    lastSellOutAt=1250L
    lastSellOutBoundaryQuality='observed'
    activeCycle=[pscustomobject]@{restockAt=1200L;restockQuantity=5000L}
}
$oosPhase=Get-WindowObservedPhase -Engine $phaseEngine -Key 'japan:123'
Assert-True ([bool]$oosPhase.unresolvedOos) 'A later verified sellout with zero stock should remain an unresolved OoS phase.'

# Positive stock must still get a current-cycle sellout estimate when there is not
# enough quantity-change evidence for live depletion. This is the Whale Meat case:
# current stock exists and completed cycles provide a stable in-stock duration.
$fallbackState=[pscustomobject]@{lastSellOutAt=5000L;activeCycle=[pscustomobject]@{restockAt=6000L;restockQuantity=600L}}
$fallbackProjection=Get-LiveCycleProjection -CurrentStock 600L -SourceTimestamp 6500L -DestinationState $fallbackState -Cycles $projectionCycles -NowEpoch 6500L
Assert-Equal ([string]$fallbackProjection.mode) 'historical-duration' 'Positive stock without depletion-rate evidence should fall back to cleaned historical availability duration.'
Assert-Equal ([long]$fallbackProjection.activeSelloutEstimateAt) 7300L 'Historical current-cycle sellout should equal active restock plus median 1300-second availability.'

# A live current cycle that survives travel plus purchase buffer must be used before
# any later recurring Safe/Best window.
$currentDeparture=Get-CurrentCycleDeparturePlan -CurrentStock 600L -ActiveSelloutEstimateAt 20000L -FlightSeconds 7200L -EarliestDepartureAt 10000L -NowEpoch 10000L -SafetyMarginFraction 0.05
Assert-True ([bool]$currentDeparture.reachable) 'Current stock should remain actionable when projected sellout is later than travel plus buffer.'
Assert-Equal ([long]$currentDeparture.leaveDeadlineAt) 12300L 'Leave-before deadline must equal projected sellout minus flight minus a 5% haircut of remaining sellout time.'
Assert-Equal ([long]$currentDeparture.safetyMarginSeconds) 500L 'Ten-thousand seconds remaining should reserve a 500-second 5% sellout safety margin.'

$missedCurrent=Get-CurrentCycleDeparturePlan -CurrentStock 600L -ActiveSelloutEstimateAt 16000L -FlightSeconds 7200L -EarliestDepartureAt 10000L -NowEpoch 10000L -SafetyMarginFraction 0.05
Assert-True (-not [bool]$missedCurrent.reachable) 'Current cycle must fall back to a later recurring window once travel plus buffer cannot beat projected sellout.'

$currentProbability=Get-StableCurrentCycleArrivalProbability -Cycles $projectionCycles -ActiveRestockAt 10000L -ArrivalAt 11250L
Assert-Near ([double]$currentProbability) (2.0/3.0) 0.0001 'Current-cycle arrival confidence at cycle start should retain the completed-cycle survival fraction.'

$conditionedProbability=Get-StableCurrentCycleArrivalProbability -Cycles $projectionCycles -ActiveRestockAt 10000L -ObservationAt 11250L -ArrivalAt 11350L
Assert-Near ([double]$conditionedProbability) 0.5 0.0001 'Current-cycle survival must condition on the fact that stock is still positive at the latest observation.'

$outlivedHistoryProbability=Get-StableCurrentCycleArrivalProbability -Cycles $projectionCycles -ActiveRestockAt 10000L -ObservationAt 11500L -ArrivalAt 11600L
Assert-Near ([double]$outlivedHistoryProbability) -1.0 0.0001 'A live cycle that outlives every historical duration is unknown from historical survival, not a fabricated 0%.'


# A left-censored current restock can still be obviously safe from direct depletion.
# Use only uncensored positive-stock intervals from the current run and pessimistically
# floor the guarded rate at one unit/minute.
$slowObservations=@(
    [pscustomobject]@{timestamp=9000L;sourceTimestamp=9000L;stock=606L;depletionEvidence='observed_nonzero';depletionCensored=$false;depletionIntervalSeconds=300L;depletionUnits=2L;transitionGapSeconds=300L},
    [pscustomobject]@{timestamp=9300L;sourceTimestamp=9300L;stock=604L;depletionEvidence='observed_nonzero';depletionCensored=$false;depletionIntervalSeconds=300L;depletionUnits=2L;transitionGapSeconds=300L},
    [pscustomobject]@{timestamp=9600L;sourceTimestamp=9600L;stock=602L;depletionEvidence='observed_nonzero';depletionCensored=$false;depletionIntervalSeconds=300L;depletionUnits=2L;transitionGapSeconds=300L}
)
$slowLiveProbability=Get-LiveDepletionArrivalProbability -CurrentStock 600L -SourceTimestamp 10000L -Observations $slowObservations -ArrivalAt 17200L -NowEpoch 10000L
Assert-True ([bool]$slowLiveProbability.eligible) 'Three clean current-run depletion samples should support a live current-cycle arrival probability.'
Assert-Near ([double]$slowLiveProbability.probability) 1.0 0.0001 'When every observed current depletion rate leaves more runway than the flight horizon, live Chance to Hit should be 100%, not historical 0%.'
Assert-True ([long]$slowLiveProbability.medianRunwaySeconds -gt 7200L) 'Live probability diagnostics should expose a median runway longer than the evaluated arrival horizon.'

$slowSafety=Get-CurrentStockSafetyProjection -CurrentStock 600L -SourceTimestamp 10000L -Observations $slowObservations -EarliestArrivalAt 17200L -NowEpoch 10000L
Assert-True ([bool]$slowSafety.eligible) 'Slow uncensored depletion should allow the current-stock Safe Window Open fallback even when the restock boundary is unknown.'
Assert-Equal ([int]$slowSafety.sampleCount) 3 'Safety fallback must require the configured three observed depletion samples.'
Assert-True ([long]$slowSafety.evidenceSpanSeconds -ge 600L) 'Safety fallback must require a meaningful current-run evidence span.'
Assert-Near ([double]$slowSafety.guardedUnitsPerHour) 60.0 0.001 'Slow markets should still use the conservative one-unit-per-minute guarded floor.'
Assert-True ([long]$slowSafety.runwaySeconds -ge 36000L) '600 units at the guarded floor should imply at least ten hours of conservative runway.'
Assert-True ([long]$slowSafety.arrivalMarginSeconds -gt 0L) 'Obvious safety must retain a positive margin beyond arrival.'

$fastObservations=@(
    [pscustomobject]@{timestamp=9000L;sourceTimestamp=9000L;stock=660L;depletionEvidence='observed_nonzero';depletionCensored=$false;depletionIntervalSeconds=300L;depletionUnits=20L;transitionGapSeconds=300L},
    [pscustomobject]@{timestamp=9300L;sourceTimestamp=9300L;stock=640L;depletionEvidence='observed_nonzero';depletionCensored=$false;depletionIntervalSeconds=300L;depletionUnits=20L;transitionGapSeconds=300L},
    [pscustomobject]@{timestamp=9600L;sourceTimestamp=9600L;stock=620L;depletionEvidence='observed_nonzero';depletionCensored=$false;depletionIntervalSeconds=300L;depletionUnits=20L;transitionGapSeconds=300L}
)
$fastSafety=Get-CurrentStockSafetyProjection -CurrentStock 600L -SourceTimestamp 10000L -Observations $fastObservations -EarliestArrivalAt 17200L -NowEpoch 10000L
Assert-True (-not [bool]$fastSafety.eligible) 'Fast depletion must not be mislabeled Safe Window Open merely because current stock is positive.'
Assert-True ([double]$fastSafety.guardedUnitsPerHour -ge 360.0) 'Guard multiplier must pessimistically increase an observed 240-unit/hour depletion regime.'

$tooSparse=Get-CurrentStockSafetyProjection -CurrentStock 600L -SourceTimestamp 10000L -Observations @($slowObservations[0],$slowObservations[1]) -EarliestArrivalAt 17200L -NowEpoch 10000L
Assert-True (-not [bool]$tooSparse.eligible) 'Two depletion samples are insufficient for the safe-window fallback.'


$flatObservations=@(
    [pscustomobject]@{timestamp=8500L;sourceTimestamp=8500L;stock=975L;depletionEvidence='observed_zero';depletionCensored=$false;depletionIntervalSeconds=300L;depletionUnits=0L;transitionGapSeconds=300L},
    [pscustomobject]@{timestamp=8800L;sourceTimestamp=8800L;stock=975L;depletionEvidence='observed_zero';depletionCensored=$false;depletionIntervalSeconds=300L;depletionUnits=0L;transitionGapSeconds=300L},
    [pscustomobject]@{timestamp=9100L;sourceTimestamp=9100L;stock=975L;depletionEvidence='observed_zero';depletionCensored=$false;depletionIntervalSeconds=300L;depletionUnits=0L;transitionGapSeconds=300L},
    [pscustomobject]@{timestamp=9400L;sourceTimestamp=9400L;stock=975L;depletionEvidence='observed_zero';depletionCensored=$false;depletionIntervalSeconds=300L;depletionUnits=0L;transitionGapSeconds=300L}
)
$flatSafety=Get-CurrentStockSafetyProjection -CurrentStock 975L -SourceTimestamp 10000L -Observations $flatObservations -EarliestArrivalAt 17200L -NowEpoch 10000L
Assert-True ([bool]$flatSafety.eligible) 'Verified flat positive stock spanning 15 minutes should support the low-depletion holding fallback when stress runway is very long.'
Assert-Equal ([string]$flatSafety.mode) 'low-depletion-hold' 'Flat-stock fallback must be explicitly lower-authority low-depletion evidence.'
Assert-True ([long]$flatSafety.minimumHoldHorizonSeconds -ge 21600L) 'Low-depletion fallback must require at least a six-hour adaptive hold horizon.'
Assert-Near ([double]$flatSafety.guardedUnitsPerHour) 60.0 0.001 'Flat-stock fallback must stress at no less than the one-unit-per-minute floor.'
Assert-True ([long]$flatSafety.runwaySeconds -ge 57600L) '975 units at the guarded floor should retain more than sixteen hours of stress runway.'
Assert-Equal ([long]$flatSafety.selloutEstimateAt) 0L 'Flat-stock fallback must not fabricate a precise OoS timestamp when the slope is effectively unmeasurable.'

$farSelloutSafety=Get-CurrentStockSafetyProjection -CurrentStock 975L -SourceTimestamp 10000L -Observations @() -EarliestArrivalAt 17200L -NowEpoch 10000L -KnownSelloutEstimateAt 40000L
Assert-True ([bool]$farSelloutSafety.eligible) 'A verified sellout estimate more than six hours out should support low-authority holding guidance even without a local depletion slope.'
Assert-Equal ([string]$farSelloutSafety.mode) 'far-sellout' 'Far-sellout fallback must identify its evidence mode.'
Assert-Equal ([long]$farSelloutSafety.selloutEstimateAt) 40000L 'Far-sellout fallback should retain the verified projected sellout timestamp.'

$longFlightFarGate=Get-CurrentStockSafetyProjection -CurrentStock 975L -SourceTimestamp 10000L -Observations @() -EarliestArrivalAt 24400L -NowEpoch 10000L -KnownSelloutEstimateAt 35200L
Assert-True (-not [bool]$longFlightFarGate.eligible) 'For a four-hour arrival horizon, a seven-hour sellout estimate must not pass the adaptive 2x-flight eight-hour hold gate.'
Assert-True ([long]$longFlightFarGate.minimumHoldHorizonSeconds -ge 28800L) 'Adaptive holding gate must scale to at least twice a long arrival horizon.'

# Long but valid cycles must still construct the immediate next cycle even when the
# period exceeds the default 24-hour display horizon.
$longCycleAnchor=100000L
$longCycleNow=$longCycleAnchor+7200L
$longCycles=@(
    [pscustomobject]@{schemaVersion=2;restockDelaySeconds=54000L;availabilitySeconds=43200L;soldOutAt=70001L;forecastEligible=$true;availabilityEligible=$true;restockDelayEligible=$true;trendEligible=$true;restockBoundaryQuality='observed';soldOutBoundaryQuality='observed';previousSellOutBoundaryQuality='observed'},
    [pscustomobject]@{schemaVersion=2;restockDelaySeconds=55800L;availabilitySeconds=45000L;soldOutAt=70002L;forecastEligible=$true;availabilityEligible=$true;restockDelayEligible=$true;trendEligible=$true;restockBoundaryQuality='bounded';soldOutBoundaryQuality='observed';previousSellOutBoundaryQuality='bounded'},
    [pscustomobject]@{schemaVersion=2;restockDelaySeconds=57600L;availabilitySeconds=46800L;soldOutAt=70003L;forecastEligible=$true;availabilityEligible=$true;restockDelayEligible=$true;trendEligible=$true;restockBoundaryQuality='observed';soldOutBoundaryQuality='bounded';previousSellOutBoundaryQuality='observed'}
)
$longModel=Get-StableRecurringScenarioModel -Cycles $longCycles -AnchorAt $longCycleAnchor -AnchorPhase restock -NowEpoch $longCycleNow -FutureHorizonSeconds 86400L
Assert-True (@($longModel.groups | Where-Object { [int]$_.ordinal -eq 1 }).Count -eq 1) 'Immediate next cycle must exist even when its long period extends beyond the default 24-hour horizon.'
Assert-Equal (@($longModel.groups | Where-Object { [int]$_.ordinal -gt 1 }).Count) 0 'Current implementation must not spend CPU projecting cycle +2/+3.'

# Selection is chronological. A near-term >50% Best Hit should not be skipped just
# because some later cycle eventually has a Safe Window.
$selectionModel=[pscustomobject]@{ groups=@(
    [pscustomobject]@{ ordinal=0; earlyRestockAt=$anchor+1000; earlySelloutAt=$anchor+1400; lateRestockAt=$anchor+1200; lateSelloutAt=$anchor+1600; safeStartAt=0L; safeEndAt=0L; bestStartAt=$anchor+1100; bestEndAt=$anchor+1300; bestProbability=(2.0/3.0) },
    [pscustomobject]@{ ordinal=1; earlyRestockAt=$anchor+5000; earlySelloutAt=$anchor+5800; lateRestockAt=$anchor+5200; lateSelloutAt=$anchor+6000; safeStartAt=$anchor+5200; safeEndAt=$anchor+5800; bestStartAt=$anchor+5200; bestEndAt=$anchor+5800; bestProbability=1.0 }
) }
$selected=Select-StableWindowPlanGroup -Model $selectionModel -EarliestArrivalAt $anchor -MinimumBestProbability .5
Assert-Equal ([string]$selected.mode) 'best' 'Near-term Best Hit must beat a much later Safe Window in another cycle.'
Assert-Near ([double]$selected.probability) (2.0/3.0) 0.0001 'Chronological Best Hit selection should retain its empirical confidence.'


$immediateModel=[pscustomobject]@{
    sampleCount=4
    groups=@([pscustomobject]@{lateSelloutAt=2000L})
    segments=@(
        [pscustomobject]@{startAt=1200L;endAt=1300L;probability=0.75},
        [pscustomobject]@{startAt=1500L;endAt=1600L;probability=0.5}
    )
}
Assert-Near (Get-StableRecurringProbabilityAt -Model $immediateModel -ArrivalAt 1250L) 0.75 0.000001 'Immediate-arrival journal probability should use the overlap segment containing the actual flight-aligned arrival.'
Assert-Near (Get-StableRecurringProbabilityAt -Model $immediateModel -ArrivalAt 1400L) 0.0 0.000001 'Arrival between supported in-stock segments is a known legacy 0% within current/next-cycle support.'
Assert-Near (Get-StableRecurringProbabilityAt -Model $immediateModel -ArrivalAt 2500L) -1.0 0.000001 'Arrival beyond immediate-next legacy support must remain unknown for the multi-cycle model rather than becoming a fake 0%.'

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL: $failure" -ForegroundColor Red }
    Write-Host "Stable recurring-window tests failed with $($failures.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Stable recurring-window phase, live current-cycle deadlines, cadence-aware filtering, and chronological Safe/Best selection tests passed.' -ForegroundColor Green
exit 0
