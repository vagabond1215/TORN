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

$elsewhere=Get-SFTravelCandidates -TravelState traveling -MarketCountry test_country -TravelDestinationCountry other_country -TravelTimeLeft 400 -OneWaySeconds 100 -NowEpoch $now
$elsewhereForecast=Invoke-SFMarketForecast -MarketKey 'test_country:1' -Cycles $cycles -Market $oosMarket -Destination $oosDestination -Travel $elsewhere -NowEpoch $now -ScenarioCount 64 -TargetQuantity 5 -MarketValue 100 -MarketFeePercent 0 -OneWaySeconds 100 -RandomSeed 2
Assert-True (-not [bool]$elsewhere.feasible) 'Traveling elsewhere must make a new Torn departure physically infeasible.'
Assert-Equal ([string]$elsewhereForecast.decision.state) 'NO_ACTIONABLE_TRIP' 'Traveling elsewhere must not emit impossible departure guidance.'

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
for($i=0;$i -lt 7;$i++){
    $row=(New-TestCycles -Count 1 -BaseAt (100+($i*300)))[0]
    $row.country='replay';$row.itemId=9
    $row.previousSoldOutAt=([long]$row.soldOutAt-200)
    $replayCycles.Add($row)
}
$replay=Invoke-SFReplay -Cycles $replayCycles.ToArray() -ArrivalOffsetSeconds 50 -ScenarioCount 32 -RandomSeed 44
foreach($row in @($replay.rows)){
    Assert-True ([long]$row.trainingLatestAvailableAt -le [long]$row.decisionAt) 'Replay training must enforce availableAt <= historical decision time.'
    Assert-True ([long]$row.targetAvailableAt -gt [long]$row.decisionAt) 'Replay target must not leak into training.'
}
Assert-True ($replay.PSObject.Properties['forecastMetrics'] -ne $null) 'Replay scaffold must expose forecast metrics.'
Assert-True ($replay.PSObject.Properties['decisionMetrics'] -ne $null) 'Replay scaffold must expose decision metrics.'

$stableSeedA=Get-SFStableSeed -MarketKey 'test_country:1' -BaseSeed 42
$stableSeedB=Get-SFStableSeed -MarketKey 'test_country:1' -BaseSeed 42
Assert-Equal $stableSeedA $stableSeedB 'Market seed must remain stable across repeated minute updates when evidence is unchanged.'

$modelText=Get-Content -Raw -LiteralPath $modelPath
Assert-True (-not $modelText.Contains('Floor($Now/60.0)')) 'Runtime stochastic seed must not rotate every minute and inject Monte Carlo noise into unchanged evidence.'
foreach($networkToken in @('Invoke-RestMethod','Invoke-WebRequest','curl.exe','System.Net.WebClient')){
    Assert-True (-not $modelText.Contains($networkToken)) ("StochasticForecast must remain network-free; found "+$networkToken)
}
$runUpdate=Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1')
$publishIndex=$runUpdate.IndexOf('try { Publish-UpdateUiState }')
$stochasticIndex=$runUpdate.IndexOf('Invoke-FailSoftScript -Path $StochasticForecast')
Assert-True ($publishIndex -ge 0 -and $stochasticIndex -gt $publishIndex) 'Shadow stochastic failure must occur only after valid legacy UI publication.'

if($failures.Count -gt 0){foreach($failure in $failures){Write-Host "FAIL: $failure" -ForegroundColor Red};Write-Host "Stochastic tests failed with $($failures.Count) error(s)." -ForegroundColor Red;exit 1}
Write-Host 'Stochastic-v1 multi-cycle, travel, economics, determinism, replay, and fail-soft tests passed.' -ForegroundColor Green
exit 0
