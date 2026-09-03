$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$chanceScript=Join-Path $ProjectRoot '@Resources\Scripts\ChanceHistory.ps1'
$resolveScript=Join-Path $ProjectRoot '@Resources\Scripts\ResolveChanceHistory.ps1'
. $chanceScript -SkipMain
. $resolveScript -SkipMain

$failures=New-Object System.Collections.Generic.List[string]
function Assert-True([bool]$Condition,[string]$Message){if(-not$Condition){$script:failures.Add($Message)}}
function Assert-Equal($Actual,$Expected,[string]$Message){if($Actual -ne $Expected){$script:failures.Add("$Message Expected=$Expected Actual=$Actual")}}
function Assert-Near([double]$Actual,[double]$Expected,[double]$Tolerance,[string]$Message){if([Math]::Abs($Actual-$Expected) -gt $Tolerance){$script:failures.Add("$Message Expected=$Expected Actual=$Actual")}}

# Travel alignment uses the same country-specific one-way duration semantics as the
# production stochastic bridge.
$state=@{
    TravelState='home'
    TravelDestinationCountryId=''
    TravelTimeLeft='0'
    ARGENTINATravelSeconds='6660'
}
Assert-Equal (Get-CHTravelSeconds -State $state -Country 'argentina') 6660L 'Chance journal must use configured country one-way travel seconds.'
$home=Get-CHArrivalPlan -State $state -Country 'argentina' -NowEpoch 10000L -OneWaySeconds 6660L
Assert-True ([bool]$home.feasible) 'Home departure should be prospectively scorable.'
Assert-Equal ([long]$home.departureAt) 10000L 'Home departure should align with forecast time.'
Assert-Equal ([long]$home.arrivalAt) 16660L 'Home arrival should equal forecast time plus one-way flight.'

$returnState=@{
    TravelState='returning'
    TravelDestinationCountryId='argentina'
    TravelTimeLeft='300'
}
$returning=Get-CHArrivalPlan -State $returnState -Country 'argentina' -NowEpoch 10000L -OneWaySeconds 6660L
Assert-Equal ([long]$returning.departureAt) 10300L 'Returning forecast cannot depart Torn before the return completes.'
Assert-Equal ([long]$returning.arrivalAt) 16960L 'Returning arrival must include return time plus outbound flight.'

$outboundState=@{
    TravelState='traveling'
    TravelDestinationCountryId='argentina'
    TravelTimeLeft='420'
}
$outbound=Get-CHArrivalPlan -State $outboundState -Country 'argentina' -NowEpoch 10000L -OneWaySeconds 6660L
Assert-True ([bool]$outbound.feasible) 'Already outbound to the target remains prospectively scorable.'
Assert-Equal ([long]$outbound.arrivalAt) 10420L 'Committed forecast should score the actual remaining flight horizon.'

$elsewhereState=@{
    TravelState='traveling'
    TravelDestinationCountryId='canada'
    TravelTimeLeft='420'
}
$elsewhere=Get-CHArrivalPlan -State $elsewhereState -Country 'argentina' -NowEpoch 10000L -OneWaySeconds 6660L
Assert-True (-not [bool]$elsewhere.feasible) 'Traveling elsewhere must not fabricate a target-country prospective arrival.'

# One probability sample per market/minute is retained. A later write in the same
# minute replaces the earlier one rather than inflating history density.
$tempHistory=[System.IO.Path]::GetTempFileName()
try{
    Remove-Item -LiteralPath $tempHistory -Force -ErrorAction SilentlyContinue
    $rows=@(
        [pscustomobject]@{schemaVersion=1;timestamp=1000L;forecastAt=1000L;marketKey='test_country:1';probability=0.4},
        [pscustomobject]@{schemaVersion=1;timestamp=1010L;forecastAt=1010L;marketKey='test_country:1';probability=0.6}
    )
    Write-CHHistory -Path $tempHistory -CurrentRows $rows -Cutoff 0L -MaximumTimestamp 2000L -BucketSeconds 60
    $saved=@(Get-Content -LiteralPath $tempHistory | ForEach-Object {$_|ConvertFrom-Json})
    Assert-Equal $saved.Count 1 'Chance history must retain one row per market/minute bucket.'
    Assert-Near ([double]$saved[0].probability) 0.6 0.000001 'Newest probability in a minute bucket should win.'
}finally{
    Remove-Item -LiteralPath $tempHistory -Force -ErrorAction SilentlyContinue
}

# Resolve a forecast only after its arrival using confirmed later evidence. The
# probability remains the pre-arrival value; future truth labels the outcome only.
$tempObs=[System.IO.Path]::GetTempFileName()
$tempCycles=[System.IO.Path]::GetTempFileName()
try{
    [System.IO.File]::WriteAllText($tempObs,'',[System.Text.UTF8Encoding]::new($false))
    $cycle=[pscustomobject]@{
        schemaVersion=2;country='test_country';itemId=1
        restockAt=1410L;restockLowerBoundAt=1400L;restockUpperBoundAt=1410L;restockBoundaryQuality='observed'
        soldOutAt=1600L;soldOutLowerBoundAt=1590L;soldOutUpperBoundAt=1600L;soldOutBoundaryQuality='observed'
        previousSoldOutAt=1300L;previousSoldOutLowerBoundAt=1300L;previousSoldOutUpperBoundAt=1300L;previousSellOutBoundaryQuality='observed'
    }
    [System.IO.File]::WriteAllText($tempCycles,(($cycle|ConvertTo-Json -Compress)+[Environment]::NewLine),[System.Text.UTF8Encoding]::new($false))

    $ObservationFile=$tempObs
    $CycleFile=$tempCycles
    $forecast=[pscustomobject]@{
        schemaVersion=1;timestamp=1000L;forecastAt=1000L;departureAt=1000L;arrivalAt=1500L
        flightSeconds=500L;travelMode='home';marketKey='test_country:1';country='test_country';itemId=1
        probability=0.7;source='multi_cycle_arrival';modelVersion='stochastic-v1.1';targetQuantity=20
    }
    $resolved=@(Resolve-RCHForecasts -ChanceRows @($forecast) -ExistingResolved @() -NowEpoch 1700L -GraceSeconds 0)
    Assert-Equal $resolved.Count 1 'Completed post-arrival cycle evidence should resolve the recorded forecast.'
    Assert-Equal ([int]$resolved[0].actualAnyStock) 1 'Arrival inside confirmed completed-cycle stock interval should be a hit.'
    Assert-Near ([double]$resolved[0].predictedProbability) 0.7 0.000001 'Resolution must preserve the probability frozen before arrival.'
    Assert-Near ([double]$resolved[0].brier) 0.09 0.000001 '0.7 probability followed by a hit has Brier error 0.09.'
    Assert-Near ([double]$resolved[0].probabilityError) -0.3 0.000001 'Signed probability error should be prediction minus realized binary outcome.'
    Assert-Equal ([int]$resolved[0].classificationCorrect) 1 '0.7 forecast followed by a hit is classification-correct at the 0.5 threshold.'

    $summary=New-RCHSummary -Rows $resolved -NowEpoch 1700L -WindowStart 0L
    Assert-Equal ([int]$summary.overall.count) 1 'Accuracy summary must count the resolved forecast exactly once.'
    Assert-Near ([double]$summary.overall.brierScore) 0.09 0.000001 'Summary Brier score must average strict resolved errors.'
    Assert-Near ([double]$summary.overall.observedHitRate) 1.0 0.000001 'One resolved hit should produce 100% observed hit rate.'
    Assert-Near ([double]$summary.overall.calibrationGap) -0.3 0.000001 'Calibration gap should be mean predicted probability minus observed hit rate.'

    $future=($forecast|ConvertTo-Json -Depth 6|ConvertFrom-Json)
    $future.forecastAt=1600L;$future.timestamp=1600L;$future.departureAt=1600L;$future.arrivalAt=2000L
    $futureResolved=@(Resolve-RCHForecasts -ChanceRows @($future) -ExistingResolved @() -NowEpoch 1700L -GraceSeconds 0)
    Assert-Equal $futureResolved.Count 0 'Forecast whose arrival is still in the future must never be scored.'
}finally{
    Remove-Item -LiteralPath $tempObs,$tempCycles -Force -ErrorAction SilentlyContinue
}

$chanceText=Get-Content -Raw -LiteralPath $chanceScript
$resolveText=Get-Content -Raw -LiteralPath $resolveScript
foreach($token in @('Invoke-RestMethod','Invoke-WebRequest','curl.exe','System.Net.WebClient')){
    Assert-True (-not $chanceText.Contains($token)) ("ChanceHistory must remain network-free; found "+$token)
    Assert-True (-not $resolveText.Contains($token)) ("ResolveChanceHistory must remain network-free; found "+$token)
}
Assert-True ($chanceText.Contains('[int]$RetentionHours = 8')) 'Chance journal default retention must remain eight hours.'
Assert-True ($chanceText.Contains('[int]$SampleBucketSeconds = 60')) 'Chance journal must remain synchronized to one-minute graph sampling.'
Assert-True ($resolveText.Contains('. $CalibrationScript -SkipMain')) 'Strict replay must reuse prospective calibration truth semantics.'
Assert-True ($resolveText.Contains("futureLeakage='future evidence is used only to label the later outcome, never to alter the frozen probability'")) 'Replay artifact must explicitly prohibit future leakage.'

if($failures.Count -gt 0){
    foreach($failure in $failures){Write-Host "FAIL: $failure" -ForegroundColor Red}
    Write-Host "Chance-history tests failed with $($failures.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Eight-hour chance journaling, flight alignment, strict outcome resolution, and accuracy metrics passed.' -ForegroundColor Green
exit 0
