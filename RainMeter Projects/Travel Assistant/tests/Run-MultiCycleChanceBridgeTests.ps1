$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$bridgePath=Join-Path $ProjectRoot '@Resources\Scripts\MultiCycleChanceBridge.ps1'
. $bridgePath -SkipMain

$failures=New-Object System.Collections.Generic.List[string]
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { $script:failures.Add($Message) } }
function Assert-Equal($Actual,$Expected,[string]$Message) { if ($Actual -ne $Expected) { $script:failures.Add("$Message Expected=$Expected Actual=$Actual") } }
function Assert-Near([double]$Actual,[double]$Expected,[double]$Tolerance,[string]$Message) {
    if ([Math]::Abs($Actual-$Expected) -gt $Tolerance) { $script:failures.Add("$Message Expected=$Expected Actual=$Actual") }
}

function New-MCTestCycles {
    param(
        [int]$Count=6,
        [long]$Delay=100L,
        [long]$Availability=100L,
        [long]$Quantity=20L,
        [long]$Price=50L,
        [long]$BaseAt=100L
    )
    $rows=New-Object System.Collections.Generic.List[object]
    for($i=1;$i -le $Count;$i++){
        $soldOut=$BaseAt+($i*10)
        $rows.Add([pscustomobject]@{
            schemaVersion=2;country='test_country';itemId=1;foreignPrice=$Price;restockQuantity=$Quantity
            restockAt=$soldOut-$Availability;restockLowerBoundAt=$soldOut-$Availability;restockUpperBoundAt=$soldOut-$Availability;restockBoundaryQuality='observed'
            soldOutAt=$soldOut;soldOutLowerBoundAt=$soldOut;soldOutUpperBoundAt=$soldOut;soldOutBoundaryQuality='observed'
            previousSoldOutAt=$soldOut-$Availability-$Delay;previousSoldOutLowerBoundAt=$soldOut-$Availability-$Delay;previousSoldOutUpperBoundAt=$soldOut-$Availability-$Delay;previousSellOutBoundaryQuality='observed'
            restockDelaySeconds=$Delay;restockDelayMinimumSeconds=$Delay;restockDelayMaximumSeconds=$Delay;restockDelayEligible=$true
            availabilitySeconds=$Availability;availabilityMinimumSeconds=$Availability;availabilityMaximumSeconds=$Availability;availabilityEligible=$true
            forecastEligible=$true;trendEligible=$true;evidenceQuality='bounded_fresh'
        })
    }
    return $rows.ToArray()
}

# Weighted timing diagnostics are a baseline/interpretability layer, not a second
# probability model. A deterministic 100s OOS + 100s in-stock cycle is 50% occupied.
$now=1000L
$cycles=New-MCTestCycles
$evidence=@(Select-SFJointCycleEvidence -Cycles $cycles -AsOf $now)
$timing=Get-MCWeightedTimingDiagnostics -Evidence $evidence -ArrivalHorizonSeconds 750L
Assert-Equal ([int]$timing.sampleCount) 6 'All valid fixture cycles should contribute to multi-cycle timing diagnostics.'
Assert-Near ([double]$timing.meanCycleSeconds) 200.0 0.0001 'Mean full-cycle duration should equal OOS plus in-stock duration.'
Assert-Near ([double]$timing.meanInStockSeconds) 100.0 0.0001 'Mean in-stock duration should remain separate from full-cycle duration.'
Assert-Near ([double]$timing.dutyCycleProbability) 0.5 0.000001 'Long-run in-stock occupancy baseline should be E[in-stock]/E[cycle].'
Assert-Near ([double]$timing.arrivalCycleRatio) 3.75 0.000001 'Arrival/cycle ratio should express how many mean cycles fit before landing.'
Assert-Equal ([int]$timing.expectedFullCycles) 3 'Full-cycle count should floor the continuous flight/cycle ratio.'
Assert-Near ([double]$timing.cycleStdDevSeconds) 0.0 0.000001 'Deterministic cycle fixture should have zero timing variance.'
Assert-Near ([double]$timing.phaseStdDevSeconds) 0.0 0.000001 'Zero cycle variance should produce zero accumulated phase variance.'

# Cycle timing variance accumulates approximately with sqrt(N) for the diagnostic
# independence baseline. The actual forecast remains empirical renewal simulation.
$variableEvidence=@(
    [pscustomobject]@{weight=1.0;delayMinimum=90L;delayMaximum=90L;availabilityMinimum=100L;availabilityMaximum=100L},
    [pscustomobject]@{weight=1.0;delayMinimum=100L;delayMaximum=100L;availabilityMinimum=100L;availabilityMaximum=100L},
    [pscustomobject]@{weight=1.0;delayMinimum=110L;delayMaximum=110L;availabilityMinimum=100L;availabilityMaximum=100L}
)
$variableTiming=Get-MCWeightedTimingDiagnostics -Evidence $variableEvidence -ArrivalHorizonSeconds 800L
Assert-Near ([double]$variableTiming.meanCycleSeconds) 200.0 0.0001 'Variable fixture should retain its 200-second mean period.'
Assert-Near ([double]$variableTiming.arrivalCycleRatio) 4.0 0.0001 '800-second arrival horizon should span four mean cycles.'
Assert-True ([double]$variableTiming.cycleStdDevSeconds -gt 8.0) 'Cycle timing standard deviation should reflect empirical period spread.'
Assert-Near ([double]$variableTiming.phaseStdDevSeconds) (2.0*[double]$variableTiming.cycleStdDevSeconds) 0.01 'Four-cycle independence diagnostic should scale phase SD by sqrt(4).'

# The bridge evaluates exactly one earliest-feasible arrival. For an OOS anchor at
# 1000 with deterministic 100/100 cycles, arrival 1750 lands in cycle ordinal 3.
$oosMarket=[pscustomobject]@{lastStock=0;lastForeignPrice=50;sourceTimestamp=$now}
$oosDestination=[pscustomobject]@{lastSellOutAt=$now;lastSellOutLowerBoundAt=$now;lastSellOutUpperBoundAt=$now}
$travel=Get-MCArrivalCandidate -TravelState home -MarketCountry test_country -TravelDestinationCountry '' -TravelTimeLeft 0 -OneWaySeconds 750 -NowEpoch $now
Assert-True ([bool]$travel.feasible) 'Home market should have one feasible leave-now arrival candidate.'
Assert-Equal @($travel.candidates).Count 1 'Bridge must evaluate only one arrival rather than a departure search grid.'
Assert-Equal ([long]$travel.candidates[0].arrivalAt) 1750L 'Home bridge arrival should equal Now plus one-way flight time.'

$multi=Get-MCMultiCycleChance -MarketKey 'test_country:1' -Cycles $cycles -Observations @() -Market $oosMarket -Destination $oosDestination -Travel $travel -NowEpoch $now -ScenarioCount 64 -TargetQuantity 5 -MarketValue 100 -MarketFeePercent 0 -OneWaySeconds 750 -MinimumRatio 2.0 -MinimumSamples 3 -RandomSeed 19
Assert-True ([bool]$multi.eligible) 'Flight spanning 3.75 mean cycles should qualify for the multi-cycle fallback.'
Assert-Near ([double]$multi.arrival.pAnyStock) 1.0 0.000001 'Deterministic arrival inside the fourth stock interval should have certain simulated stock.'
Assert-Equal ([int]$multi.arrival.maximumCycleOrdinal) 3 'Bridge must continue through multiple complete cycles rather than stopping at immediate-next.'

$shortTravel=Get-MCArrivalCandidate -TravelState home -MarketCountry test_country -TravelDestinationCountry '' -TravelTimeLeft 0 -OneWaySeconds 300 -NowEpoch $now
$short=Get-MCMultiCycleChance -MarketKey 'test_country:1' -Cycles $cycles -Observations @() -Market $oosMarket -Destination $oosDestination -Travel $shortTravel -NowEpoch $now -ScenarioCount 64 -TargetQuantity 5 -MarketValue 100 -MarketFeePercent 0 -OneWaySeconds 300 -MinimumRatio 2.0 -MinimumSamples 3 -RandomSeed 19
Assert-True (-not [bool]$short.eligible) 'Flight spanning only 1.5 cycles must remain on legacy current/next-cycle guidance.'
Assert-Near ([double]$short.timing.arrivalCycleRatio) 1.5 0.000001 'Ineligible short-flight diagnostic should still report its measured cycle ratio.'

$sparse=Get-MCMultiCycleChance -MarketKey 'test_country:1' -Cycles @($cycles[0],$cycles[1]) -Observations @() -Market $oosMarket -Destination $oosDestination -Travel $travel -NowEpoch $now -ScenarioCount 64 -TargetQuantity 5 -MarketValue 100 -MarketFeePercent 0 -OneWaySeconds 750 -MinimumRatio 2.0 -MinimumSamples 3 -RandomSeed 19
Assert-True (-not [bool]$sparse.eligible) 'Fewer than three completed usable cycles must not fabricate a displayed percentage.'

$returning=Get-MCArrivalCandidate -TravelState returning -MarketCountry test_country -TravelDestinationCountry '' -TravelTimeLeft 300 -OneWaySeconds 750 -NowEpoch $now
Assert-Equal ([long]$returning.arrivalHorizonSeconds) 1050L 'Returning bridge horizon must include remaining return time plus the outbound flight.'
Assert-Equal ([long]$returning.candidates[0].departureAt) 1300L 'Returning player must not receive an impossible departure before reaching Torn.'

$elsewhere=Get-MCArrivalCandidate -TravelState traveling -MarketCountry test_country -TravelDestinationCountry other_country -TravelTimeLeft 300 -OneWaySeconds 750 -NowEpoch $now
Assert-True (-not [bool]$elsewhere.feasible) 'Traveling to another country must remain physically infeasible for this market.'

$bridgeText=Get-Content -Raw -LiteralPath $bridgePath
foreach($token in @('Invoke-RestMethod','Invoke-WebRequest','curl.exe','System.Net.WebClient')){
    Assert-True (-not $bridgeText.Contains($token)) ("MultiCycleChanceBridge must remain network-free; found "+$token)
}
Assert-True ($bridgeText.Contains('. $StochasticScript -SkipMain')) 'Bridge must reuse stochastic-v1.1 functions rather than implement a second cycle simulator.'
Assert-True ($bridgeText.Contains('-EnableAdaptiveGrid $false')) 'Single-arrival production fallback must not pay for a departure-grid adaptive search.'
Assert-True ($bridgeText.Contains("[double]$MinimumFlightCycleRatio = 2.0")) 'Production eligibility threshold should remain explicit at two mean cycles.'

$runUpdate=Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1')
$windowIndex=$runUpdate.IndexOf('Invoke-FailSoftScript -Path $WindowPlan')
$bridgeIndex=$runUpdate.IndexOf('Invoke-FailSoftScript -Path $MultiCycleChanceBridge')
$priceIndex=$runUpdate.IndexOf('Invoke-FailSoftScript -Path $PriceVariationRefiner')
Assert-True ($windowIndex -ge 0 -and $bridgeIndex -gt $windowIndex -and $priceIndex -gt $bridgeIndex) 'Bridge must run after legacy WindowPlan and before final price/filter publication.'
Assert-True ($runUpdate.Contains('multi-cycle-chance-bridge-error.txt')) 'Bridge must retain a dedicated fail-soft error channel.'

$presenter=Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot '@Resources\Scripts\CardPresenter.lua')
Assert-True ($presenter.Contains("return 'Chance to hit:',chancePercent(probability)")) 'Card fallback should render the requested Chance to hit percentage.'
Assert-True ($presenter.Contains("'This is a modeled arrival probability, not a Safe/Best departure-window guarantee.'")) 'Tooltip must distinguish multi-cycle probability from Safe/Best guarantees.'
$currentReachableIndex=$presenter.IndexOf("if currentStock>0 and reachable")
$legacyFallbackIndex=$presenter.IndexOf("local legacyAction,legacyChance,legacyTooltip=homeNextCycleAction")
Assert-True ($currentReachableIndex -ge 0 -and $legacyFallbackIndex -gt $currentReachableIndex) 'Current-cycle reachability must retain precedence over multi-cycle fallback.'
Assert-True ($presenter.Contains("if multiAction~=nil then return multiAction,multiChance,multiTooltip end")) 'Legacy failure states should be able to consume the production bridge.'

if($failures.Count -gt 0){
    foreach($failure in $failures){Write-Host "FAIL: $failure" -ForegroundColor Red}
    Write-Host "Multi-cycle chance bridge tests failed with $($failures.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Multi-cycle timing, renewal-arrival, travel-feasibility, precedence, and fail-soft tests passed.' -ForegroundColor Green
exit 0
