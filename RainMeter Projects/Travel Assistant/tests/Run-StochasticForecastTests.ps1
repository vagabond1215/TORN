$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$modelPath=Join-Path $ProjectRoot '@Resources\Scripts\StochasticForecast.ps1'
$replayPath=Join-Path $ProjectRoot 'tools\Invoke-StochasticReplay.ps1'
. $modelPath -SkipMain
. $replayPath -SkipMain

$failures=New-Object System.Collections.Generic.List[string]
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { $script:failures.Add($Message) } }
function Assert-Equal($Actual,$Expected,[string]$Message) { if ($Actual -ne $Expected) { $script:failures.Add("$Message Expected=$Expected Actual=$Actual") } }
function Assert-Near([double]$Actual,[double]$Expected,[double]$Tolerance,[string]$Message) { if ([Math]::Abs($Actual-$Expected) -gt $Tolerance) { $script:failures.Add("$Message Expected=$Expected Actual=$Actual") } }

function New-TestCycles {
    param([int]$Count=6,[long]$DelayMin=100,[long]$DelayMax=100,[long]$AvailableMin=100,[long]$AvailableMax=100,[long]$Quantity=20,[long]$Price=50,[long]$BaseAt=100)
    $cycles=New-Object System.Collections.Generic.List[object]
    for ($i=1; $i -le $Count; $i++) {
        $at=$BaseAt+($i*10)
        $cycles.Add([pscustomobject]@{
            schemaVersion=2;country='test_country';itemId=1;foreignPrice=$Price;restockQuantity=$Quantity
            restockAt=$at-100;restockLowerBoundAt=$at-101;restockUpperBoundAt=$at-100;restockBoundaryQuality='observed'
            soldOutAt=$at;soldOutLowerBoundAt=$at-1;soldOutUpperBoundAt=$at;soldOutBoundaryQuality='observed'
            previousSoldOutAt=$at-200;previousSoldOutLowerBoundAt=$at-201;previousSoldOutUpperBoundAt=$at-200;previousSellOutBoundaryQuality='observed'
            restockDelaySeconds=$DelayMin;restockDelayMinimumSeconds=$DelayMin;restockDelayMaximumSeconds=$DelayMax;restockDelayEligible=$true
            availabilitySeconds=$AvailableMin;availabilityMinimumSeconds=$AvailableMin;availabilityMaximumSeconds=$AvailableMax;availabilityEligible=$true
            forecastEligible=$true;trendEligible=$true;evidenceQuality='bounded_fresh'
        })
    }
    return $cycles.ToArray()
}

$now=1000L
$cycles=New-TestCycles
$oosMarket=[pscustomobject]@{lastStock=0;lastForeignPrice=50;sourceTimestamp=$now}
$oosDestination=[pscustomobject]@{lastSellOutAt=$now;lastSellOutLowerBoundAt=($now-1);lastSellOutUpperBoundAt=$now}

# Broad restock uncertainty plus a very short in-stock period must not collapse to
# a deterministic Safe window.
$broad=New-TestCycles -DelayMin 100 -DelayMax 1000 -AvailableMin 20 -AvailableMax 20
$singleTravel=[pscustomobject]@{feasible=$true;mode='home';reason='test';candidates=@([pscustomobject]@{departureAt=$now;arrivalAt=1300L})}
$broadForecast=Invoke-SFMarketForecast -MarketKey 'test_country:1' -Cycles $broad -Market $oosMarket -Destination $oosDestination -Travel $singleTravel -NowEpoch $now -ScenarioCount 512 -TargetQuantity 5 -MarketValue 100 -MarketFeePercent 0 -OneWaySeconds 300 -RandomSeed 22
Assert-True ([double]$broadForecast.arrivals[0].pAnyStock -lt 0.20) 'Broad timing uncertainty with short availability should have low maximum success, not a fake Safe window.'

# A short deterministic burst can live entirely between two 15-minute coarse
# arrival points. The adaptive pass must discover that hidden support without
# changing the configured coarse horizon or scoring on its discovery worlds.
$burstCycles=New-TestCycles -DelayMin 450 -DelayMax 450 -AvailableMin 60 -AvailableMax 60 -Quantity 20
$burstTravel=Get-SFTravelCandidates -TravelState home -MarketCountry test_country -TravelDestinationCountry '' -TravelTimeLeft 0 -OneWaySeconds 100 -NowEpoch $now -StepSeconds 900 -SearchSeconds 900
$burstCoarse=Invoke-SFMarketForecast -MarketKey 'test_country:1' -Cycles $burstCycles -Market $oosMarket -Destination $oosDestination -Travel $burstTravel -NowEpoch $now -ScenarioCount 128 -TargetQuantity 5 -MarketValue 100 -MarketFeePercent 0 -OneWaySeconds 100 -RandomSeed 77 -EnableAdaptiveGrid $false -CoarseGridSeconds 900
Assert-Equal @($burstCoarse.arrivals).Count 2 'Disabled adaptive search should retain only the two coarse test arrivals.'
Assert-Near ([double](@($burstCoarse.arrivals | Measure-Object pAnyStock -Maximum).Maximum)) 0.0 0.000001 'The coarse 15-minute grid should miss the synthetic 60-second burst entirely.'

$burstAdaptive=Invoke-SFMarketForecast -MarketKey 'test_country:1' -Cycles $burstCycles -Market $oosMarket -Destination $oosDestination -Travel $burstTravel -NowEpoch $now -ScenarioCount 128 -TargetQuantity 5 -MarketValue 100 -MarketFeePercent 0 -OneWaySeconds 100 -RandomSeed 77 -EnableAdaptiveGrid $true -CoarseGridSeconds 900
Assert-True ([bool]$burstAdaptive.adaptiveGrid.enabled) 'Short-duration evidence should enable bounded adaptive search.'
Assert-Equal ([long]$burstAdaptive.adaptiveGrid.referenceAvailabilitySeconds) 60L 'Adaptive planning should preserve the short empirical availability reference.'
Assert-True ([int]$burstAdaptive.adaptiveGrid.additionalCandidateCount -gt 0) 'Hidden support should add sub-grid arrival candidates.'
Assert-True (@($burstAdaptive.arrivals).Count -gt @($burstCoarse.arrivals).Count) 'Adaptive forecast should retain coarse arrivals and add bounded fine arrivals.'
Assert-True ([double](@($burstAdaptive.arrivals | Measure-Object pAnyStock -Maximum).Maximum) -gt 0.90) 'Adaptive search should recover the deterministic short stock burst missed by the coarse grid.'
Assert-True (@($burstAdaptive.arrivals | Where-Object {[bool]$_.adaptivePoint}).Count -gt 0) 'Refined arrival rows should identify adaptive candidate provenance.'

$longGridCycles=New-TestCycles -DelayMin 450 -DelayMax 450 -AvailableMin 1800 -AvailableMax 1800 -Quantity 20
$longEvidence=@(Select-SFJointCycleEvidence -Cycles $longGridCycles -AsOf $now)
$longPlan=Get-SFAdaptiveGridPlan -Evidence $longEvidence -Travel $burstTravel -CoarseStepSeconds 900 -Enabled $true
Assert-True (-not [bool]$longPlan.enabled) 'Stock durations longer than the coarse grid should not pay for adaptive refinement.'

$fullLoadPlan=Get-SFAdaptiveGridPlan -Evidence $longEvidence -Travel $burstTravel -TargetQuantity 20 -CoarseStepSeconds 900 -Enabled $true
Assert-True ([bool]$fullLoadPlan.enabled) 'A long-lived market should still refine when the full-load quantity window is much shorter than the coarse step.'
Assert-True ([long]$fullLoadPlan.referenceUsefulQuantityWindowSeconds -lt 900L) 'Required-quantity window diagnostic should expose the narrow full-load interval.'

# Retained intermediate stock observations should preserve an empirical depletion
# trajectory jointly with the sampled cycle. The linear model remains an explicit
# fallback when no informative intermediate observations exist.
$shapeCycles=New-Object System.Collections.Generic.List[object]
$shapeObservations=New-Object System.Collections.Generic.List[object]
foreach($spec in @(
    [pscustomobject]@{restock=100L;sellout=200L;previous=50L},
    [pscustomobject]@{restock=400L;sellout=500L;previous=350L},
    [pscustomobject]@{restock=700L;sellout=800L;previous=650L}
)){
    $shapeCycles.Add([pscustomobject]@{
        schemaVersion=2;country='test_country';itemId=1;foreignPrice=50L;restockQuantity=100
        restockAt=$spec.restock;restockLowerBoundAt=$spec.restock;restockUpperBoundAt=$spec.restock;restockBoundaryQuality='observed'
        soldOutAt=$spec.sellout;soldOutLowerBoundAt=$spec.sellout;soldOutUpperBoundAt=$spec.sellout;soldOutBoundaryQuality='observed'
        previousSoldOutAt=$spec.previous;previousSoldOutLowerBoundAt=$spec.previous;previousSoldOutUpperBoundAt=$spec.previous;previousSellOutBoundaryQuality='observed'
        restockDelaySeconds=50L;restockDelayMinimumSeconds=50L;restockDelayMaximumSeconds=50L;restockDelayEligible=$true
        availabilitySeconds=100L;availabilityMinimumSeconds=100L;availabilityMaximumSeconds=100L;availabilityEligible=$true
        forecastEligible=$true;trendEligible=$true;evidenceQuality='bounded_fresh'
    })
    foreach($point in @(
        [pscustomobject]@{offset=0L;stock=100},
        [pscustomobject]@{offset=50L;stock=80},
        [pscustomobject]@{offset=75L;stock=20},
        [pscustomobject]@{offset=100L;stock=0}
    )){
        $ts=[long]$spec.restock+[long]$point.offset
        $shapeObservations.Add([pscustomobject]@{
            schemaVersion=2;timestamp=$ts;sourceTimestamp=$ts;country='test_country';itemId=1
            stock=[int]$point.stock;foreignPrice=50L;source='shape-fixture'
        })
    }
}
$shapeEvidence=@(Select-SFJointCycleEvidence -Cycles $shapeCycles.ToArray() -AsOf $now -Observations $shapeObservations.ToArray())
Assert-Equal $shapeEvidence.Count 3 'All shape fixtures should remain usable joint-cycle evidence.'
Assert-True (@($shapeEvidence | Where-Object {$null -ne $_.depletionShape}).Count -eq 3) 'Each shape fixture should retain an empirical depletion trajectory.'
Assert-True ([int]$shapeEvidence[0].depletionShape.pointCount -ge 4) 'Empirical trajectory should include structural endpoints plus informative intermediate stock points.'

Assert-Near ([double]$shapeEvidence[0].depletionShape.boundaryUncertaintyRatio) 0.0 0.000001 'Exact fixture boundaries should preserve a zero censor-width ratio.'

$wideCycle=($shapeCycles[0] | ConvertTo-Json -Depth 8 | ConvertFrom-Json)
$wideCycle.restockLowerBoundAt=[long]$wideCycle.restockUpperBoundAt-30L
$wideCycle.soldOutLowerBoundAt=[long]$wideCycle.soldOutUpperBoundAt-30L
$wideShape=Get-SFCycleDepletionShape -Cycle $wideCycle -Observations $shapeObservations.ToArray()
Assert-True ($null -eq $wideShape) 'Depletion shape must fail back to linear when transition-censor width dominates the cycle.'

$shapeInterval=New-SFStockInterval -StartAt 1000L -EndAt 1100L -Quantity 100L -ForeignPrice 50L -Ordinal 1 -DepletionShape $shapeEvidence[0].depletionShape
$linearInterval=New-SFStockInterval -StartAt 1000L -EndAt 1100L -Quantity 100L -ForeignPrice 50L -Ordinal 1
Assert-Equal (Get-SFIntervalQuantity -Interval $shapeInterval -ArrivalAt 1050L) 80L 'Empirical piecewise shape should preserve 80% stock at the historical halfway point.'
Assert-Equal (Get-SFIntervalQuantity -Interval $linearInterval -ArrivalAt 1050L) 50L 'Missing shape evidence should retain the legacy linear fallback.'

$shapeTravel=[pscustomobject]@{feasible=$true;mode='home';reason='shape';candidates=@([pscustomobject]@{departureAt=$now;arrivalAt=1100L})}
$shapeDestination=[pscustomobject]@{lastSellOutAt=$now;lastSellOutLowerBoundAt=$now;lastSellOutUpperBoundAt=$now}
$shapeForecast=Invoke-SFMarketForecast -MarketKey 'test_country:1' -Cycles $shapeCycles.ToArray() -Observations $shapeObservations.ToArray() -Market $oosMarket -Destination $shapeDestination -Travel $shapeTravel -NowEpoch $now -ScenarioCount 64 -TargetQuantity 100 -MarketValue 100 -MarketFeePercent 0 -OneWaySeconds 100 -RandomSeed 55 -EnableAdaptiveGrid $false
$linearForecast=Invoke-SFMarketForecast -MarketKey 'test_country:1' -Cycles $shapeCycles.ToArray() -Market $oosMarket -Destination $shapeDestination -Travel $shapeTravel -NowEpoch $now -ScenarioCount 64 -TargetQuantity 100 -MarketValue 100 -MarketFeePercent 0 -OneWaySeconds 100 -RandomSeed 55 -EnableAdaptiveGrid $false
Assert-Equal ([string]$shapeForecast.depletionModel) 'empirical_piecewise_with_linear_fallback' 'Forecast diagnostics should identify empirical piecewise depletion when shape evidence exists.'
Assert-Equal ([int]$shapeForecast.depletionShapeEvidenceCount) 3 'Forecast diagnostics should count shaped cycle evidence.'
Assert-Equal ([string]$linearForecast.depletionModel) 'linear_fallback' 'Forecast diagnostics should expose linear fallback when intermediate observations are absent.'
Assert-True ([double]$shapeForecast.arrivals[0].expectedQty -gt ([double]$linearForecast.arrivals[0].expectedQty+20.0)) 'Empirical depletion shape should materially change expected arrival quantity versus the linear fallback.'

# Fresh current stock that cannot survive the flight still permits a later cycle.
$shortCurrent=New-TestCycles -DelayMin 100 -DelayMax 100 -AvailableMin 100 -AvailableMax 100
$currentMarket=[pscustomobject]@{lastStock=10;lastForeignPrice=50;sourceTimestamp=$now}
$currentDestination=[pscustomobject]@{activeCycle=[pscustomobject]@{restockAt=900;restockLowerBoundAt=900;restockUpperBoundAt=900}}
$laterTravel=[pscustomobject]@{feasible=$true;mode='home';reason='test';candidates=@([pscustomobject]@{departureAt=$now;arrivalAt=1150L})}
$laterForecast=Invoke-SFMarketForecast -MarketKey 'test_country:1' -Cycles $shortCurrent -Market $currentMarket -Destination $currentDestination -Travel $laterTravel -NowEpoch $now -ScenarioCount 64 -TargetQuantity 5 -MarketValue 100 -MarketFeePercent 0 -OneWaySeconds 150 -RandomSeed 5
Assert-True ([double]$laterForecast.arrivals[0].pAnyStock -gt 0.9) 'Later cycle should be evaluated when current stock cannot survive the flight.'
Assert-True ([int]$laterForecast.arrivals[0].maximumCycleOrdinal -ge 1) 'Arrival success should identify a post-current cycle.'

# One and several complete cycles may pass before arrival.
$oneCycleTravel=[pscustomobject]@{feasible=$true;mode='home';reason='test';candidates=@([pscustomobject]@{departureAt=$now;arrivalAt=1350L})}
$oneCycle=Invoke-SFMarketForecast -MarketKey 'test_country:1' -Cycles $cycles -Market $oosMarket -Destination $oosDestination -Travel $oneCycleTravel -NowEpoch $now -ScenarioCount 64 -TargetQuantity 5 -MarketValue 100 -MarketFeePercent 0 -OneWaySeconds 350 -RandomSeed 7
Assert-Equal ([int]$oneCycle.arrivals[0].maximumCycleOrdinal) 1 'Flight longer than one complete cycle should land in cycle ordinal 1.'
$manyTravel=[pscustomobject]@{feasible=$true;mode='home';reason='test';candidates=@([pscustomobject]@{departureAt=$now;arrivalAt=1750L})}
$many=Invoke-SFMarketForecast -MarketKey 'test_country:1' -Cycles $cycles -Market $oosMarket -Destination $oosDestination -Travel $manyTravel -NowEpoch $now -ScenarioCount 64 -TargetQuantity 5 -MarketValue 100 -MarketFeePercent 0 -OneWaySeconds 750 -RandomSeed 7
Assert-Equal ([int]$many.arrivals[0].maximumCycleOrdinal) 3 'Simulator must continue through several cycles to the evaluated arrival.'

$returning=Get-SFTravelCandidates -TravelState returning -MarketCountry test_country -TravelDestinationCountry '' -TravelTimeLeft 600 -OneWaySeconds 100 -NowEpoch $now -StepSeconds 300 -SearchSeconds 900
Assert-True (@($returning.candidates | Where-Object {[long]$_.departureAt -lt 1600L}).Count -eq 0) 'Returning player must not receive a departure before return landing.'

$missingTravel=Get-SFTravelCandidates -TravelState home -MarketCountry test_country -TravelDestinationCountry '' -TravelTimeLeft 0 -OneWaySeconds 0 -NowEpoch $now
Assert-True (-not [bool]$missingTravel.feasible) 'Missing one-way travel time must fail closed rather than treat arrival as immediate.'
Assert-Equal ([string]$missingTravel.mode) 'missing_travel_time' 'Missing travel time should expose an explicit shadow diagnostic mode.'

$committed=Get-SFTravelCandidates -TravelState traveling -MarketCountry test_country -TravelDestinationCountry test_country -TravelTimeLeft 350 -OneWaySeconds 100 -NowEpoch $now
$committedForecast=Invoke-SFMarketForecast -MarketKey 'test_country:1' -Cycles $cycles -Market $oosMarket -Destination $oosDestination -Travel $committed -NowEpoch $now -ScenarioCount 64 -TargetQuantity 5 -MarketValue 100 -MarketFeePercent 0 -OneWaySeconds 100 -RandomSeed 9
Assert-Equal ([string]$committedForecast.decision.state) 'COMMITTED' 'Already outbound to target must produce COMMITTED shadow state.'
Assert-Equal ([long]$committed.candidates[0].arrivalAt) 1350L 'Committed evaluation must use landing time rather than a new departure.'

$abroad=Get-SFTravelCandidates -TravelState abroad -MarketCountry test_country -TravelDestinationCountry test_country -TravelTimeLeft 0 -OneWaySeconds 100 -NowEpoch $now
$abroadMarket=[pscustomobject]@{lastStock=8;lastForeignPrice=50;sourceTimestamp=$now}
$abroadForecast=Invoke-SFMarketForecast -MarketKey 'test_country:1' -Cycles @() -Market $abroadMarket -Destination ([pscustomobject]@{}) -Travel $abroad -NowEpoch $now -ScenarioCount 64 -TargetQuantity 5 -MarketValue 100 -MarketFeePercent 0 -OneWaySeconds 100 -RandomSeed 3
Assert-Equal ([string]$abroadForecast.decision.state) 'BUY_NOW' 'Abroad at target should use immediate fresh stock evidence.'
Assert-Near ([double]$abroadForecast.arrivals[0].pAnyStock) 1.0 0.000001 'Immediate observed stock has certain current availability, not a forecast claim.'

$agedAbroadMarket=[pscustomobject]@{lastStock=8;lastForeignPrice=50;sourceTimestamp=($now-60)}
$agedAbroadForecast=Invoke-SFMarketForecast -MarketKey 'test_country:1' -Cycles @() -Market $agedAbroadMarket -Destination ([pscustomobject]@{}) -Travel $abroad -NowEpoch $now -ScenarioCount 64 -TargetQuantity 5 -MarketValue 100 -MarketFeePercent 0 -OneWaySeconds 100 -RandomSeed 3
Assert-Equal ([string]$agedAbroadForecast.decision.state) 'INSUFFICIENT_DATA' 'An aged positive snapshot must not become a fabricated 100% current-stock claim without survival evidence.'
Assert-Equal @($agedAbroadForecast.arrivals).Count 0 'Aged direct stock with insufficient cycles should remain probabilistically unknown.'

$agedActive=[pscustomobject]@{activeCycle=[pscustomobject]@{restockAt=($now-70);restockLowerBoundAt=($now-70);restockUpperBoundAt=($now-70)}}
$shortSurvivalCycles=New-TestCycles -DelayMin 100 -DelayMax 100 -AvailableMin 30 -AvailableMax 30
$shortAgedForecast=Invoke-SFMarketForecast -MarketKey 'test_country:1' -Cycles $shortSurvivalCycles -Market $agedAbroadMarket -Destination $agedActive -Travel $abroad -NowEpoch $now -ScenarioCount 64 -TargetQuantity 5 -MarketValue 100 -MarketFeePercent 0 -OneWaySeconds 100 -RandomSeed 31
Assert-Near ([double]$shortAgedForecast.arrivals[0].pAnyStock) 0.0 0.000001 'A positive snapshot from one minute ago must be allowed to sell out before Now when learned duration is short.'

$longSurvivalCycles=New-TestCycles -DelayMin 100 -DelayMax 100 -AvailableMin 120 -AvailableMax 120
$longAgedForecast=Invoke-SFMarketForecast -MarketKey 'test_country:1' -Cycles $longSurvivalCycles -Market $agedAbroadMarket -Destination $agedActive -Travel $abroad -NowEpoch $now -ScenarioCount 64 -TargetQuantity 5 -MarketValue 100 -MarketFeePercent 0 -OneWaySeconds 100 -RandomSeed 31
Assert-Near ([double]$longAgedForecast.arrivals[0].pAnyStock) 1.0 0.000001 'Aged positive evidence may still survive to Now when empirical duration supports it.'
Assert-True ([double]$longAgedForecast.arrivals[0].expectedQty -le 5.0) 'Current-stock quantity must deplete forward from the provider observation rather than restart at Now.'

$elsewhere=Get-SFTravelCandidates -TravelState traveling -MarketCountry test_country -TravelDestinationCountry other_country -TravelTimeLeft 400 -OneWaySeconds 100 -NowEpoch $now
$elsewhereForecast=Invoke-SFMarketForecast -MarketKey 'test_country:1' -Cycles $cycles -Market $oosMarket -Destination $oosDestination -Travel $elsewhere -NowEpoch $now -ScenarioCount 64 -TargetQuantity 5 -MarketValue 100 -MarketFeePercent 0 -OneWaySeconds 100 -RandomSeed 2
Assert-True (-not [bool]$elsewhere.feasible) 'Traveling elsewhere must make a new Torn departure physically infeasible.'
Assert-Equal ([string]$elsewhereForecast.decision.state) 'NO_ACTIONABLE_TRIP' 'Traveling elsewhere must not emit impossible departure guidance.'

$lossTravel=[pscustomobject]@{feasible=$true;mode='home';reason='test';candidates=@([pscustomobject]@{departureAt=$now;arrivalAt=1150L})}
$lossForecast=Invoke-SFMarketForecast -MarketKey 'test_country:1' -Cycles $shortCurrent -Market $oosMarket -Destination $oosDestination -Travel $lossTravel -NowEpoch $now -ScenarioCount 64 -TargetQuantity 5 -MarketValue 10 -MarketFeePercent 0 -OneWaySeconds 150 -RandomSeed 19
Assert-Equal ([string]$lossForecast.decision.state) 'NO_ACTIONABLE_TRIP' 'A grid with no positive expected-profit arrival is not a WAIT recommendation; WAIT remains reserved for a modeled delay/information decision.'

$tax3=Get-SFEconomics -Quantity 10 -MarketValue 100 -ForeignPrice 50 -MarketFeePercent 3 -OneWaySeconds 3600
$tax0=Get-SFEconomics -Quantity 10 -MarketValue 100 -ForeignPrice 50 -MarketFeePercent 0 -OneWaySeconds 3600
Assert-Equal ([long]$tax3.tax) 30 'Stochastic economics must honor a non-5% itemMarketFeePercent.'
Assert-Equal ([long]$tax3.profit) 470 'Tax is applied once to gross sale before expected after-tax profit.'
Assert-Equal ([long]$tax0.profit) 500 'Zero itemMarketFeePercent must not subtract tax.'
Assert-Near ([double]$tax3.profitPerHour) 235.0 0.0001 'Profit/hour uses configured round-trip flight hours.'

$detA=Invoke-SFMarketForecast -MarketKey 'test_country:1' -Cycles $broad -Market $oosMarket -Destination $oosDestination -Travel $singleTravel -NowEpoch $now -ScenarioCount 128 -TargetQuantity 5 -MarketValue 100 -MarketFeePercent 3 -OneWaySeconds 300 -RandomSeed 12345
$detB=Invoke-SFMarketForecast -MarketKey 'test_country:1' -Cycles $broad -Market $oosMarket -Destination $oosDestination -Travel $singleTravel -NowEpoch $now -ScenarioCount 128 -TargetQuantity 5 -MarketValue 100 -MarketFeePercent 3 -OneWaySeconds 300 -RandomSeed 12345
Assert-Equal ($detA | ConvertTo-Json -Depth 8 -Compress) ($detB | ConvertTo-Json -Depth 8 -Compress) 'Fixed seed and fixed evidence must produce stable output.'

$beforeCount=$cycles.Count
$selected=@(Select-SFJointCycleEvidence -Cycles $cycles -AsOf $now)
Assert-Equal $cycles.Count $beforeCount 'Forecast filtering must not delete learning history.'
Assert-Equal $selected.Count $beforeCount 'All valid fixture cycles should remain available to the empirical model.'

# Replay cutoff must precede every target and uncertain event brackets remain unscored.
$replayCycles=New-Object System.Collections.Generic.List[object]
$replayObservations=New-Object System.Collections.Generic.List[object]
for($i=0;$i -lt 7;$i++){
    $row=(New-TestCycles -Count 1 -BaseAt (100+($i*300)))[0]
    $row.country='replay';$row.itemId=9
    $row.previousSoldOutAt=([long]$row.soldOutAt-200)
    $replayCycles.Add($row)
    $restock=[long]$row.restockUpperBoundAt
    $sellout=[long]$row.soldOutUpperBoundAt
    foreach($point in @(
        [pscustomobject]@{at=$restock;stock=20},
        [pscustomobject]@{at=($restock+50);stock=16},
        [pscustomobject]@{at=$sellout;stock=0}
    )){
        $replayObservations.Add([pscustomobject]@{
            schemaVersion=2;timestamp=[long]$point.at;sourceTimestamp=[long]$point.at;country='replay';itemId=9
            stock=[int]$point.stock;foreignPrice=50L;source='replay-fixture'
        })
    }
}
$replay=Invoke-SFReplay -Cycles $replayCycles.ToArray() -Observations $replayObservations.ToArray() -ArrivalOffsetSeconds 50 -ScenarioCount 32 -RandomSeed 44
foreach($row in @($replay.rows)){
    Assert-True ([long]$row.trainingLatestAvailableAt -le [long]$row.decisionAt) 'Replay training must enforce availableAt <= historical decision time.'
    Assert-True ([long]$row.trainingLatestObservationAt -le [long]$row.decisionAt) 'Replay shape training must enforce observation sourceTimestamp <= historical decision time.'
    Assert-True ([long]$row.targetAvailableAt -gt [long]$row.decisionAt) 'Replay target must not leak into training.'
}
Assert-True ($replay.PSObject.Properties['forecastMetrics'] -ne $null) 'Replay scaffold must expose forecast metrics.'
Assert-True ($replay.PSObject.Properties['decisionMetrics'] -ne $null) 'Replay scaffold must expose decision metrics.'
Assert-Equal ([string]$replay.modelVersion) 'stochastic-v1.1' 'Replay output must version the materially changed stochastic challenger.'
Assert-True ($replay.forecastMetrics.PSObject.Properties['stochastic_v1_1'] -ne $null) 'Replay metrics must isolate stochastic-v1.1 from earlier challenger versions.'
Assert-True (@($replay.rows | Where-Object {[int]$_.depletionShapeEvidenceCount -gt 0}).Count -gt 0) 'Replay should feed only historically available intermediate observations into empirical depletion shapes.'

Assert-True ($replay.forecastMetrics.PSObject.Properties['empirical_all_overlap'] -ne $null) 'Replay must label all-cycle coverage as an empirical overlap proxy, not exact production Safe replay.'
Assert-True ($replay.forecastMetrics.PSObject.Properties['empirical_overlap'] -ne $null) 'Replay must label fractional coverage as an empirical overlap proxy, not exact production Best replay.'
Assert-True ($replay.forecastMetrics.PSObject.Properties['current_safe'] -eq $null) 'Replay must not mislabel an empirical overlap proxy as the production Safe baseline.'
Assert-True ($replay.forecastMetrics.PSObject.Properties['current_best'] -eq $null) 'Replay must not mislabel an empirical overlap proxy as the production Best baseline.'

$stableSeedA=Get-SFStableSeed -MarketKey 'test_country:1' -BaseSeed 42
$stableSeedB=Get-SFStableSeed -MarketKey 'test_country:1' -BaseSeed 42
Assert-Equal $stableSeedA $stableSeedB 'Market seed must remain stable across repeated minute updates when evidence is unchanged.'

$modelText=Get-Content -Raw -LiteralPath $modelPath
Assert-True (-not $modelText.Contains('Floor($Now/60.0)')) 'Runtime stochastic seed must not rotate every minute and inject Monte Carlo noise into unchanged evidence.'
Assert-True ($modelText.Contains('Read-SFObservationsForKeys')) 'Stochastic runtime must load retained observations for empirical depletion shapes.'
Assert-True ($modelText.Contains('Get-SFIntervalQuantity')) 'All stochastic quantity scoring should route through the shared shape-aware interval quantity helper.'
foreach($networkToken in @('Invoke-RestMethod','Invoke-WebRequest','curl.exe','System.Net.WebClient')){
    Assert-True (-not $modelText.Contains($networkToken)) ("StochasticForecast must remain network-free; found "+$networkToken)
}
$runUpdate=Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1')
$publishIndex=$runUpdate.IndexOf('try { Publish-UpdateUiState }')
$stochasticIndex=$runUpdate.IndexOf('Invoke-FailSoftScript -Path $StochasticForecast')
$resaleIndex=$runUpdate.IndexOf('& $ResaleQueue')
Assert-True ($publishIndex -ge 0 -and $stochasticIndex -gt $publishIndex) 'Shadow stochastic failure must occur only after valid legacy UI publication.'
Assert-True ($resaleIndex -ge 0 -and $stochasticIndex -gt $resaleIndex) 'Shadow stochastic work must remain lower priority than the production resale/MV queue.'

if($failures.Count -gt 0){foreach($failure in $failures){Write-Host "FAIL: $failure" -ForegroundColor Red};Write-Host "Stochastic tests failed with $($failures.Count) error(s)." -ForegroundColor Red;exit 1}
Write-Host 'Stochastic-v1 adaptive-grid, empirical-depletion, multi-cycle, travel, economics, determinism, replay, and fail-soft tests passed.' -ForegroundColor Green
exit 0
