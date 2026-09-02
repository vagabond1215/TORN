param(
    [Alias('SkipMain')]
    [switch]$ReplaySkipMain,
    [string]$CyclesPath='',
    [string]$OutputPath='',
    [ValidateRange(60,86400)]
    [int]$ArrivalOffsetSeconds=3600,
    [ValidateRange(16,2000)]
    [int]$SimulationCount=256,
    [int]$Seed=1701
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $ProjectRoot '@Resources\Scripts\StochasticForecast.ps1') -SkipMain

function Get-SFReplayAvailableAt {
    param([object]$Cycle)
    $at=[long](Get-SFProperty $Cycle 'soldOutUpperBoundAt')
    if ($at -le 0) { $at=[long](Get-SFProperty $Cycle 'soldOutAt') }
    return $at
}

function Get-SFReplayLabel {
    param([object]$Cycle,[long]$ArrivalAt)
    $restockLower=[long](Get-SFProperty $Cycle 'restockLowerBoundAt')
    $restockUpper=[long](Get-SFProperty $Cycle 'restockUpperBoundAt')
    $selloutLower=[long](Get-SFProperty $Cycle 'soldOutLowerBoundAt')
    $selloutUpper=[long](Get-SFProperty $Cycle 'soldOutUpperBoundAt')
    if ($restockLower -le 0 -or $restockUpper -lt $restockLower -or $selloutLower -lt $restockUpper -or $selloutUpper -lt $selloutLower) {
        return [pscustomobject]@{ scorable=$false; label=-1; reason='cycle event bounds are incomplete' }
    }
    if ($ArrivalAt -ge $restockUpper -and $ArrivalAt -lt $selloutLower) { return [pscustomobject]@{ scorable=$true; label=1; reason='arrival lies in confirmed in-stock interval' } }
    if ($ArrivalAt -lt $restockLower -or $ArrivalAt -ge $selloutUpper) { return [pscustomobject]@{ scorable=$true; label=0; reason='arrival lies outside the possible in-stock interval' } }
    return [pscustomobject]@{ scorable=$false; label=-1; reason='arrival intersects an interval-censored transition' }
}

function Get-SFReplayBaselineProbabilities {
    param([object[]]$Training,[long]$ArrivalAge)
    $delays=New-Object System.Collections.Generic.List[long]
    $available=New-Object System.Collections.Generic.List[long]
    $hits=0
    foreach ($cycle in @($Training)) {
        $delayBounds=Get-SFBoundedLong -Object $cycle -MinimumName 'restockDelayMinimumSeconds' -MaximumName 'restockDelayMaximumSeconds' -FallbackName 'restockDelaySeconds' -Floor 1
        $availableBounds=Get-SFBoundedLong -Object $cycle -MinimumName 'availabilityMinimumSeconds' -MaximumName 'availabilityMaximumSeconds' -FallbackName 'availabilitySeconds' -Floor 1
        $delay=[long][Math]::Round(([double]$delayBounds.minimum+[double]$delayBounds.maximum)/2.0)
        $duration=[long][Math]::Round(([double]$availableBounds.minimum+[double]$availableBounds.maximum)/2.0)
        $delays.Add($delay); $available.Add($duration)
        if ($ArrivalAge -ge $delay -and $ArrivalAge -lt ($delay+$duration)) { $hits++ }
    }
    if ($delays.Count -eq 0) { return $null }
    $meanDelay=[double]($delays | Measure-Object -Average).Average
    $meanAvailable=[double]($available | Measure-Object -Average).Average
    $medianDelay=[long](@($delays.ToArray() | Sort-Object)[[int][Math]::Floor(($delays.Count-1)/2.0)])
    $medianAvailable=[long](@($available.ToArray() | Sort-Object)[[int][Math]::Floor(($available.Count-1)/2.0)])
    $empirical=$hits/[double]$delays.Count
    return [ordered]@{
        current_safe=$(if($hits -eq $delays.Count){1.0}else{0.0})
        current_best=$empirical
        mean_cycle=$(if($ArrivalAge -ge $meanDelay -and $ArrivalAge -lt ($meanDelay+$meanAvailable)){1.0}else{0.0})
        median_cycle=$(if($ArrivalAge -ge $medianDelay -and $ArrivalAge -lt ($medianDelay+$medianAvailable)){1.0}else{0.0})
        expected_restock_minus_flight=$(if($ArrivalAge -ge $meanDelay -and $ArrivalAge -lt ($meanDelay+$meanAvailable)){1.0}else{0.0})
    }
}

function Get-SFReplayMetrics {
    param([object[]]$Rows,[string]$PredictionName)
    $scored=@($Rows | Where-Object { [bool]$_.scorable })
    if ($scored.Count -eq 0) { return [pscustomobject]@{ count=0; brierScore=0.0; logLoss=0.0; calibrationBuckets=@() } }
    $brier=0.0; $log=0.0
    $buckets=@{}
    foreach ($row in $scored) {
        $p=[double](Get-SFProperty $row.predictions $PredictionName)
        $p=[Math]::Max(0.000001,[Math]::Min(0.999999,$p))
        $y=[int]$row.label
        $brier+=[Math]::Pow($p-$y,2)
        $log+=-($y*[Math]::Log($p)+(1-$y)*[Math]::Log(1-$p))
        $bucket=[int][Math]::Min(9,[Math]::Floor($p*10.0))
        if (-not $buckets.ContainsKey($bucket)) { $buckets[$bucket]=[pscustomobject]@{ bucket=$bucket; count=0; probabilitySum=0.0; outcomeSum=0.0 } }
        $buckets[$bucket].count++
        $buckets[$bucket].probabilitySum+=$p
        $buckets[$bucket].outcomeSum+=$y
    }
    $calibration=@($buckets.Keys | Sort-Object | ForEach-Object {
        $entry=$buckets[$_]
        [pscustomobject]@{ bucket=$entry.bucket; count=$entry.count; meanProbability=[Math]::Round($entry.probabilitySum/$entry.count,4); observedRate=[Math]::Round($entry.outcomeSum/$entry.count,4) }
    })
    return [pscustomobject]@{ count=$scored.Count; brierScore=[Math]::Round($brier/$scored.Count,6); logLoss=[Math]::Round($log/$scored.Count,6); calibrationBuckets=$calibration }
}

function Invoke-SFReplay {
    param([object[]]$Cycles,[int]$ArrivalOffsetSeconds=3600,[int]$ScenarioCount=256,[int]$RandomSeed=1701)
    $byMarket=@{}
    foreach ($cycle in @($Cycles)) {
        $country=[string](Get-SFProperty $cycle 'country'); $itemId=[int](Get-SFProperty $cycle 'itemId')
        if ([string]::IsNullOrWhiteSpace($country) -or $itemId -le 0) { continue }
        $key=($country+':'+$itemId).ToLowerInvariant()
        if (-not $byMarket.ContainsKey($key)) { $byMarket[$key]=New-Object System.Collections.Generic.List[object] }
        $byMarket[$key].Add($cycle)
    }
    $rows=New-Object System.Collections.Generic.List[object]
    foreach ($key in @($byMarket.Keys | Sort-Object)) {
        $ordered=@($byMarket[$key].ToArray() | Sort-Object @{Expression={Get-SFReplayAvailableAt $_}})
        for ($i=3; $i -lt $ordered.Count; $i++) {
            $target=$ordered[$i]
            $decisionAt=Get-SFReplayAvailableAt $ordered[$i-1]
            if ($decisionAt -le 0) { continue }
            # The global cutoff is applied before feature/sample construction. No
            # cycle whose completion became available after T can enter training.
            $training=@($ordered | Where-Object { (Get-SFReplayAvailableAt $_) -le $decisionAt })
            $selected=@(Select-SFJointCycleEvidence -Cycles $training -AsOf $decisionAt)
            if ($selected.Count -lt 3) { continue }
            $arrivalAt=$decisionAt+$ArrivalOffsetSeconds
            $market=[pscustomobject]@{lastStock=0;lastForeignPrice=[long](Get-SFProperty $ordered[$i-1] 'foreignPrice');sourceTimestamp=$decisionAt}
            $destination=[pscustomobject]@{
                lastSellOutAt=[long](Get-SFProperty $ordered[$i-1] 'soldOutAt')
                lastSellOutLowerBoundAt=[long](Get-SFProperty $ordered[$i-1] 'soldOutLowerBoundAt')
                lastSellOutUpperBoundAt=[long](Get-SFProperty $ordered[$i-1] 'soldOutUpperBoundAt')
            }
            $travel=[pscustomobject]@{feasible=$true;mode='home';reason='replay';candidates=@([pscustomobject]@{departureAt=$decisionAt;arrivalAt=$arrivalAt})}
            $forecast=Invoke-SFMarketForecast -MarketKey $key -Cycles $training -Market $market -Destination $destination -Travel $travel -NowEpoch $decisionAt -ScenarioCount $ScenarioCount -TargetQuantity 1 -MarketValue 1 -MarketFeePercent 0 -OneWaySeconds $ArrivalOffsetSeconds -RandomSeed ($RandomSeed+$i)
            if (@($forecast.arrivals).Count -eq 0) { continue }
            $label=Get-SFReplayLabel -Cycle $target -ArrivalAt $arrivalAt
            $baselines=Get-SFReplayBaselineProbabilities -Training @($selected | ForEach-Object {$_.cycle}) -ArrivalAge $ArrivalOffsetSeconds
            $predictions=[pscustomobject]@{
                current_safe=[double]$baselines.current_safe; current_best=[double]$baselines.current_best
                mean_cycle=[double]$baselines.mean_cycle; median_cycle=[double]$baselines.median_cycle
                expected_restock_minus_flight=[double]$baselines.expected_restock_minus_flight
                stochastic_v1=[double]$forecast.arrivals[0].pAnyStock
            }
            $rows.Add([pscustomobject]@{
                marketKey=$key; decisionAt=$decisionAt; arrivalAt=$arrivalAt
                trainingCount=$selected.Count; trainingLatestAvailableAt=[long](@($selected.availableAt | Measure-Object -Maximum).Maximum)
                targetAvailableAt=Get-SFReplayAvailableAt $target
                scorable=[bool]$label.scorable; label=[int]$label.label; scoringReason=[string]$label.reason
                predictions=$predictions
            })
        }
    }
    $rowArray=$rows.ToArray()
    $metricNames=@('current_safe','current_best','mean_cycle','median_cycle','expected_restock_minus_flight','stochastic_v1')
    $metrics=[ordered]@{}
    foreach ($name in $metricNames) { $metrics[$name]=Get-SFReplayMetrics -Rows $rowArray -PredictionName $name }
    $scorable=@($rowArray | Where-Object {$_.scorable})
    $uncertain=@($rowArray | Where-Object {-not $_.scorable})
    return [pscustomobject]@{
        schemaVersion=1; modelVersion='stochastic-v1'; noFutureLeakagePolicy='cycle availableAt <= decisionAt'
        forecastMetrics=[pscustomobject]$metrics
        intervalMetrics=[pscustomobject]@{ restockCoverageScorable=0; selloutCoverageScorable=0; quantityErrorScorable=0; note='extension points require frozen interval/quantity forecasts' }
        decisionMetrics=[pscustomobject]@{ scorableDecisions=$scorable.Count; censoredOrUnscorable=$uncertain.Count; arrivalSuccess=@($scorable | Where-Object {$_.label -eq 1}).Count; earlyArrival=0; lateArrival=0; profitScorable=0; regretScorable=0 }
        rows=$rowArray
    }
}

if ($ReplaySkipMain) { return }
if ([string]::IsNullOrWhiteSpace($CyclesPath)) { $CyclesPath=Join-Path $ProjectRoot 'data\runtime\cycles.jsonl' }
if (-not (Test-Path -LiteralPath $CyclesPath)) { throw ('Cycle history not found: '+$CyclesPath) }
$cycles=@(Get-Content -LiteralPath $CyclesPath | Where-Object {-not [string]::IsNullOrWhiteSpace($_)} | ForEach-Object { $_ | ConvertFrom-Json })
$result=Invoke-SFReplay -Cycles $cycles -ArrivalOffsetSeconds $ArrivalOffsetSeconds -ScenarioCount $SimulationCount -RandomSeed $Seed
if ([string]::IsNullOrWhiteSpace($OutputPath)) { $OutputPath=Join-Path $ProjectRoot 'data\runtime\stochastic-replay.json' }
Write-TravelAssistantAtomicJson -Path $OutputPath -Value $result -Depth 14
Write-Host ("Stochastic replay wrote {0} decision row(s) to {1}." -f @($result.rows).Count,$OutputPath) -ForegroundColor Green
