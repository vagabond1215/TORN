$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath=Join-Path $ProjectRoot '@Resources\Scripts\StochasticCalibration.ps1'
. $scriptPath -SkipMain

$failures=New-Object System.Collections.Generic.List[string]
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { $script:failures.Add($Message) } }
function Assert-Equal($Actual,$Expected,[string]$Message) { if ($Actual -ne $Expected) { $script:failures.Add("$Message Expected=$Expected Actual=$Actual") } }
function Assert-Near([double]$Actual,[double]$Expected,[double]$Tolerance,[string]$Message) {
    if ([Math]::Abs($Actual-$Expected) -gt $Tolerance) { $script:failures.Add("$Message Expected=$Expected Actual=$Actual") }
}

function New-CalCycle {
    param(
        [long]$RestockLower,
        [long]$RestockUpper,
        [long]$SelloutLower,
        [long]$SelloutUpper,
        [long]$PreviousSelloutUpper=0L,
        [string]$PreviousQuality='unknown'
    )
    return [pscustomobject]@{
        schemaVersion=2
        country='test_country'
        itemId=1
        restockAt=$RestockUpper
        restockLowerBoundAt=$RestockLower
        restockUpperBoundAt=$RestockUpper
        restockBoundaryQuality='observed'
        soldOutAt=$SelloutUpper
        soldOutLowerBoundAt=$SelloutLower
        soldOutUpperBoundAt=$SelloutUpper
        soldOutBoundaryQuality='observed'
        previousSoldOutAt=$PreviousSelloutUpper
        previousSoldOutLowerBoundAt=$PreviousSelloutUpper
        previousSoldOutUpperBoundAt=$PreviousSelloutUpper
        previousSellOutBoundaryQuality=$PreviousQuality
    }
}

# Exact provider evidence is the strongest possible label and can score any-stock,
# required quantity, and uncapped quantity simultaneously.
$exactObservations=@(
    [pscustomobject]@{
        schemaVersion=2;timestamp=150L;sourceTimestamp=150L;country='test_country';itemId=1
        stock=25;foreignPrice=50L;source='fixture'
    }
)
$exact=Get-SCConfirmedOutcome -ArrivalAt 150L -TargetQuantity 20 -Observations $exactObservations -Cycles @() -AsOf 200L
Assert-True ([bool]$exact.anyScorable) 'Exact provider snapshot must score any-stock.'
Assert-Equal ([int]$exact.anyStock) 1 'Positive exact provider snapshot must label stock present.'
Assert-True ([bool]$exact.targetScorable) 'Exact provider snapshot must score target quantity.'
Assert-Equal ([int]$exact.targetSuccess) 1 'Exact quantity above required load must be a target-quantity success.'
Assert-True ([bool]$exact.quantityScorable) 'Non-conflicting exact provider snapshot must score available quantity.'
Assert-Equal ([long]$exact.actualQuantity) 25L 'Exact provider stock must be preserved as quantity ground truth.'

# Completed-cycle censor bounds confirm stock only inside the intersection that is
# unambiguously in stock.
$cycleA=New-CalCycle -RestockLower 100L -RestockUpper 110L -SelloutLower 190L -SelloutUpper 200L
$inside=Get-SCConfirmedOutcome -ArrivalAt 150L -TargetQuantity 20 -Observations @() -Cycles @($cycleA) -AsOf 200L
Assert-True ([bool]$inside.anyScorable) 'Arrival inside confirmed completed-cycle stock interval must be scorable.'
Assert-Equal ([int]$inside.anyStock) 1 'Confirmed completed-cycle stock interval must label success.'
Assert-True (-not [bool]$inside.targetScorable) 'Cycle phase alone must not invent required-quantity ground truth.'

# OOS requires explicit continuity from the later cycle back to the earlier
# sellout. Adjacency in the retained file is not enough.
$cycleB=New-CalCycle -RestockLower 300L -RestockUpper 310L -SelloutLower 390L -SelloutUpper 400L -PreviousSelloutUpper 200L -PreviousQuality observed
$oos=Get-SCConfirmedOutcome -ArrivalAt 250L -TargetQuantity 20 -Observations @() -Cycles @($cycleA,$cycleB) -AsOf 400L
Assert-True ([bool]$oos.anyScorable) 'Continuity-linked between-cycle OOS interval must be scorable.'
Assert-Equal ([int]$oos.anyStock) 0 'Continuity-linked between-cycle OOS interval must label failure.'

$unlinkedB=New-CalCycle -RestockLower 300L -RestockUpper 310L -SelloutLower 390L -SelloutUpper 400L -PreviousSelloutUpper 0L -PreviousQuality unknown_gap
$unlinked=Get-SCConfirmedOutcome -ArrivalAt 250L -TargetQuantity 20 -Observations @() -Cycles @($cycleA,$unlinkedB) -AsOf 400L
Assert-True (-not [bool]$unlinked.anyScorable) 'Unlinked retained cycles must not fabricate an OOS label across a possible collection gap.'

$futureEvidence=Get-SCConfirmedOutcome -ArrivalAt 250L -TargetQuantity 20 -Observations @() -Cycles @($cycleA,$cycleB) -AsOf 350L
Assert-True (-not [bool]$futureEvidence.anyScorable) 'Outcome scorer must not use a cycle whose completion evidence was unavailable at the scoring time.'

# Freeze one prospective best-arrival forecast per model/market/hour. Re-evaluating
# the same hour cannot silently replace the already-frozen prediction.
$state=New-SCCalibrationState
$artifact=[pscustomobject]@{
    schemaVersion=1
    modelVersion='stochastic-v1.1'
    generatedAt=1000L
    markets=@(
        [pscustomobject]@{
            marketKey='test_country:1';countryId='test_country';itemId=1
            sampleCount=12;effectiveSampleSize=9.5;evidenceQuality='bounded_fresh'
            targetQuantity=20;bestDepartureAt=1200L;bestArrivalAt=1500L
            depletionModel='empirical_piecewise_with_linear_fallback'
            decision=[pscustomobject]@{state='LEAVE_IN'}
            diagnostics=[pscustomobject]@{travelMode='home'}
            arrivals=@(
                [pscustomobject]@{
                    departureAt=1200L;arrivalAt=1500L;pAnyStock=0.7;pTargetQty=0.4
                    expectedQty=14.0;expectedAvailableQty=18.0;expectedProfit=100000.0;expectedProfitPerHour=50000.0
                    adaptivePoint=$true;adaptiveSource='uniform_refinement'
                }
            )
        }
    )
}
$firstFreeze=@(Get-SCFreezeRows -Artifact $artifact -State $state -NowEpoch 1010L -IntervalSeconds 3600)
Assert-Equal $firstFreeze.Count 1 'Fresh stochastic artifact should freeze one prospective best-arrival row.'
Assert-Equal ([string]$firstFreeze[0].modelVersion) 'stochastic-v1.1' 'Frozen forecast must preserve model-version isolation.'
Assert-Near ([double]$firstFreeze[0].pAnyStock) 0.7 0.000001 'Frozen forecast must preserve the pre-outcome probability.'
Assert-Equal ([long]$firstFreeze[0].arrivalAt) 1500L 'Frozen forecast must preserve the selected future arrival.'

$repeatFreeze=@(Get-SCFreezeRows -Artifact $artifact -State $state -NowEpoch 1020L -IntervalSeconds 3600)
Assert-Equal $repeatFreeze.Count 0 'Same model/market/hour must not overwrite its first prospective forecast.'

$staleFreeze=@(Get-SCFreezeRows -Artifact $artifact -State (New-SCCalibrationState) -NowEpoch 1401L -IntervalSeconds 3600)
Assert-Equal $staleFreeze.Count 0 'Artifact older than five minutes must not be frozen as a new prospective prediction.'

$zeroHorizonArtifact=($artifact | ConvertTo-Json -Depth 12 | ConvertFrom-Json)
$zeroHorizonArtifact.generatedAt=1000L
$zeroHorizonArtifact.markets[0].bestArrivalAt=1000L
$zeroHorizonArtifact.markets[0].bestDepartureAt=0L
$zeroHorizonArtifact.markets[0].arrivals[0].arrivalAt=1000L
$zeroHorizonArtifact.markets[0].arrivals[0].departureAt=0L
$zeroHorizonFreeze=@(Get-SCFreezeRows -Artifact $zeroHorizonArtifact -State (New-SCCalibrationState) -NowEpoch 1010L -IntervalSeconds 3600)
Assert-Equal $zeroHorizonFreeze.Count 0 'Current-state / BUY_NOW style zero-horizon evaluations must not enter prospective calibration.'


# Resolve a genuinely frozen prediction and verify incremental reliability metrics.
$scoreState=New-SCCalibrationState
$scoreState.pending=@($firstFreeze[0])
$cycleForArrival=New-CalCycle -RestockLower 1400L -RestockUpper 1410L -SelloutLower 1590L -SelloutUpper 1600L
$cycleMap=@{'test_country:1'=(New-Object System.Collections.Generic.List[object])}
$cycleMap['test_country:1'].Add($cycleForArrival)
$observationMap=@{}
$resolved=@(Invoke-SCResolvePending -State $scoreState -ObservationMap $observationMap -CycleMap $cycleMap -NowEpoch 1700L -GraceSeconds 0 -MaximumWaitSeconds 604800 -ScoreLimit 2000)
Assert-Equal $resolved.Count 1 'Confirmed post-arrival cycle evidence should resolve the pending forecast.'
Assert-Equal @($scoreState.pending).Count 0 'Resolved forecast must leave the pending queue exactly once.'
Assert-Equal ([string]$resolved[0].status) 'scored' 'Resolved forecast must be retained as a scored prospective record.'
Assert-Equal ([int]$resolved[0].anyStock) 1 'Confirmed in-stock arrival must score success.'

$overall=@($scoreState.aggregates | Where-Object {$_.modelVersion -eq 'stochastic-v1.1' -and $_.evidenceQuality -eq 'all'})
Assert-Equal $overall.Count 1 'Prospective resolution must maintain one all-evidence aggregate for the model version.'
Assert-Equal ([int]$overall[0].anyCount) 1 'Aggregate must count the prospective stock outcome once.'
Assert-Near ([double]$overall[0].anyBrierSum) 0.09 0.00001 'A 0.7 forecast followed by success has Brier contribution 0.09.'
Assert-Near ([double]$overall[0].anyOutcomeSum) 1.0 0.000001 'Aggregate observed-rate numerator must preserve the actual outcome.'

$summary=New-SCCalibrationSummary -State $scoreState -NowEpoch 1700L -CurrentModelVersion 'stochastic-v1.1' -FreezeSeconds 3600 -GraceSeconds 300 -MaximumWaitSeconds 604800
$summaryOverall=@($summary.models | Where-Object {$_.modelVersion -eq 'stochastic-v1.1' -and $_.evidenceQuality -eq 'all'})
Assert-Equal $summaryOverall.Count 1 'Calibration summary must expose the model-level aggregate.'
Assert-Near ([double]$summaryOverall[0].anyStock.brierScore) 0.09 0.00001 'Calibration summary must report mean Brier score.'
Assert-Near ([double]$summaryOverall[0].anyStock.observedRate) 1.0 0.000001 'Calibration summary must report empirical observed rate.'

# Unknown outcomes eventually expire without contaminating calibration metrics.
$expiredState=New-SCCalibrationState
$unknownPrediction=($firstFreeze[0] | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
$unknownPrediction.arrivalAt=100L
$expiredState.pending=@($unknownPrediction)
$expired=@(Invoke-SCResolvePending -State $expiredState -ObservationMap @{} -CycleMap @{} -NowEpoch 7200L -GraceSeconds 0 -MaximumWaitSeconds 3600 -ScoreLimit 2000)
Assert-Equal $expired.Count 1 'Long-unresolved forecast should eventually leave the pending queue.'
Assert-Equal ([string]$expired[0].status) 'expired_unscorable' 'Unresolved forecast must expire explicitly rather than receive a fabricated label.'
Assert-Equal @($expiredState.aggregates).Count 0 'Expired unscorable forecast must not affect calibration statistics.'

$scriptText=Get-Content -Raw -LiteralPath $scriptPath
foreach($networkToken in @('Invoke-RestMethod','Invoke-WebRequest','curl.exe','System.Net.WebClient')){
    Assert-True (-not $scriptText.Contains($networkToken)) ("StochasticCalibration must remain network-free; found "+$networkToken)
}
Assert-True ($scriptText.Contains("forecastSelection='one best-expected-profit arrival per market/model/hour bucket'")) 'Calibration methodology must make the freeze sampling rule explicit.'
Assert-True ($scriptText.Contains('selected arrival must be strictly after artifact generation')) 'Prospective calibration must explicitly exclude already-observable zero-horizon states.'
Assert-True ($scriptText.Contains("calibrationStatus='diagnostic only; no probability transformation is applied'")) 'Prospective scorer must not silently recalibrate user-facing probabilities.'

$runUpdate=Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1')
$forecastIndex=$runUpdate.IndexOf('Invoke-FailSoftScript -Path $StochasticForecast')
$calibrationIndex=$runUpdate.IndexOf('Invoke-FailSoftScript -Path $StochasticCalibration')
Assert-True ($forecastIndex -ge 0 -and $calibrationIndex -gt $forecastIndex) 'Prospective calibration must run after the current stochastic artifact is produced.'
Assert-True ($runUpdate.Contains("stochastic-calibration-error.txt")) 'Prospective calibration must retain a dedicated fail-soft error channel.'

if($failures.Count -gt 0){
    foreach($failure in $failures){Write-Host "FAIL: $failure" -ForegroundColor Red}
    Write-Host "Stochastic calibration tests failed with $($failures.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Prospective stochastic freeze, continuity-safe outcome, calibration, expiry, and fail-soft tests passed.' -ForegroundColor Green
exit 0
