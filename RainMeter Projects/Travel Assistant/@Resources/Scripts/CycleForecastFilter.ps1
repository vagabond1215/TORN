$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Get-CycleForecastMedian {
    param([long[]]$Values)
    $sorted = [long[]]@($Values | Where-Object { $_ -gt 0 } | Sort-Object)
    if ($sorted.Count -eq 0) { return 0L }
    $middle = [int][Math]::Floor($sorted.Count / 2.0)
    if (($sorted.Count % 2) -eq 1) { return [long]$sorted[$middle] }
    return [long][Math]::Round(([double]$sorted[$middle-1] + [double]$sorted[$middle]) / 2.0)
}

function Get-CycleForecastRobustSigma {
    param([long[]]$Values)
    $positive = [long[]]@($Values | Where-Object { $_ -gt 0 })
    if ($positive.Count -lt 3) { return 0L }
    $median = Get-CycleForecastMedian -Values $positive
    $deviations = [long[]]@($positive | ForEach-Object { [long][Math]::Abs([double]$_ - [double]$median) })
    $mad = Get-CycleForecastMedian -Values $deviations
    return [long][Math]::Round([double]$mad * 1.4826)
}

$script:CycleSpuriousRegistryLoaded = $false
$script:CycleSpuriousRegistry = $null
$script:CycleSpuriousRegistryPath = Join-Path ((Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path) 'data\runtime\spurious-transitions.json'

function Get-CycleFilterProperty {
    param([object]$Object,[string]$Name)
    if($null -eq $Object){return $null}
    $property=$Object.PSObject.Properties[$Name]
    if($null -eq $property){return $null}
    return $property.Value
}

function Set-CycleFilterProperty {
    param([object]$Object,[string]$Name,[object]$Value)
    if($null -eq $Object){return}
    $property=$Object.PSObject.Properties[$Name]
    if($null -eq $property){$Object|Add-Member NoteProperty $Name $Value}
    else{$property.Value=$Value}
}

function Get-StockObservationEvidenceAt {
    param([object]$Row)
    $at=[long](Get-CycleFilterProperty $Row 'sourceTimestamp')
    if($at -le 0){$at=[long](Get-CycleFilterProperty $Row 'timestamp')}
    return $at
}

function Test-RecoveredStockObservation {
    param([object]$Row)
    $source=([string](Get-CycleFilterProperty $Row 'source')).Trim().ToLowerInvariant()
    $quality=([string](Get-CycleFilterProperty $Row 'transitionBoundaryQuality')).Trim().ToLowerInvariant()
    return ($quality -eq 'recovered' -or $source -in @('torn_intel_history_recovery','history_recovery_live_bridge'))
}

function Resolve-StockObservationPlausibility {
    param(
        [object[]]$Rows,
        [int]$ExpectedPollIntervalSeconds=60,
        [double]$ContinuationToleranceFraction=0.05,
        [double]$TinyRestockFraction=0.25,
        [long]$AbsoluteTinyRestockUnits=10L
    )

    $poll=[Math]::Max(15,$ExpectedPollIntervalSeconds)
    $maximumTransientSeconds=[long][Math]::Max(150,(2*$poll)+30)
    $ordered=@($Rows|Where-Object{$null -ne $_}|Sort-Object @{Expression={Get-StockObservationEvidenceAt $_}})
    if($ordered.Count -eq 0){return @()}

    # Collapse duplicate timestamp/stock rows for plausibility classification only.
    $deduped=New-Object System.Collections.Generic.List[object]
    $seen=@{}
    foreach($row in $ordered){
        $at=Get-StockObservationEvidenceAt $row
        $stock=[long](Get-CycleFilterProperty $row 'stock')
        if($at -le 0 -or $stock -lt 0){continue}
        $identity=([string]$at+':'+[string]$stock)
        if($seen.ContainsKey($identity)){continue}
        $seen[$identity]=$true
        Set-CycleFilterProperty -Object $row -Name 'calculationEligible' -Value $true
        Set-CycleFilterProperty -Object $row -Name 'transitionCalculationEligible' -Value $true
        Set-CycleFilterProperty -Object $row -Name 'transitionPlausibility' -Value 'normal'
        $deduped.Add($row)
    }
    $ordered=@($deduped.ToArray())
    if($ordered.Count -lt 3){return $ordered}

    # Estimate a normal restock quantity only from obvious zero -> positive jumps.
    $candidateRestocks=New-Object System.Collections.Generic.List[long]
    for($i=1;$i -lt $ordered.Count;$i++){
        $prevStock=[long](Get-CycleFilterProperty $ordered[$i-1] 'stock')
        $stock=[long](Get-CycleFilterProperty $ordered[$i] 'stock')
        if($prevStock -eq 0 -and $stock -gt 0 -and -not(Test-RecoveredStockObservation $ordered[$i])){
            $candidateRestocks.Add($stock)
        }
    }
    $medianRestock=if($candidateRestocks.Count -ge 2){Get-CycleForecastMedian -Values ([long[]]$candidateRestocks.ToArray())}else{0L}
    $tinyThreshold=if($medianRestock -gt 0){
        [long][Math]::Max($AbsoluteTinyRestockUnits,[Math]::Floor($medianRestock*[Math]::Max(0.05,[Math]::Min(0.5,$TinyRestockFraction))))
    }else{$AbsoluteTinyRestockUnits}

    for($i=1;$i -lt ($ordered.Count-1);$i++){
        $prev=$ordered[$i-1];$cur=$ordered[$i];$next=$ordered[$i+1]
        $prevAt=Get-StockObservationEvidenceAt $prev
        $curAt=Get-StockObservationEvidenceAt $cur
        $nextAt=Get-StockObservationEvidenceAt $next
        $prevStock=[long](Get-CycleFilterProperty $prev 'stock')
        $curStock=[long](Get-CycleFilterProperty $cur 'stock')
        $nextStock=[long](Get-CycleFilterProperty $next 'stock')
        if($prevAt -le 0 -or $curAt -le $prevAt -or $nextAt -le $curAt){continue}
        if(($nextAt-$curAt) -gt $maximumTransientSeconds){continue}
        if((Test-RecoveredStockObservation $cur) -or (Test-RecoveredStockObservation $next)){continue}

        # Positive -> isolated zero -> positive is a provider dropout when the
        # returning positive quantity continues the old depletion trajectory rather
        # than jumping upward like a real replenishment.
        if($prevStock -gt 0 -and $curStock -eq 0 -and $nextStock -gt 0){
            $tolerance=[long][Math]::Max(5,[Math]::Ceiling($prevStock*[Math]::Max(0.0,$ContinuationToleranceFraction)))
            if($nextStock -le ($prevStock+$tolerance)){
                Set-CycleFilterProperty -Object $cur -Name 'calculationEligible' -Value $false
                Set-CycleFilterProperty -Object $cur -Name 'transitionCalculationEligible' -Value $false
                Set-CycleFilterProperty -Object $cur -Name 'transitionPlausibility' -Value 'spurious_zero'
                Set-CycleFilterProperty -Object $next -Name 'transitionCalculationEligible' -Value $false
                Set-CycleFilterProperty -Object $next -Name 'transitionPlausibility' -Value 'spurious_zero_partner'
                continue
            }
        }

        # Zero -> tiny positive -> zero is not promoted to a real micro-cycle when
        # the temporary quantity is far below the market's normal replenishment.
        # With no normal-restock baseline, only an absolute <=10 unit blip qualifies.
        if($prevStock -eq 0 -and $curStock -gt 0 -and $nextStock -eq 0 -and $curStock -le $tinyThreshold){
            Set-CycleFilterProperty -Object $cur -Name 'calculationEligible' -Value $false
            Set-CycleFilterProperty -Object $cur -Name 'transitionCalculationEligible' -Value $false
            Set-CycleFilterProperty -Object $cur -Name 'transitionPlausibility' -Value 'spurious_restock'
            Set-CycleFilterProperty -Object $next -Name 'transitionCalculationEligible' -Value $false
            Set-CycleFilterProperty -Object $next -Name 'transitionPlausibility' -Value 'spurious_restock_partner'
        }
    }
    return $ordered
}

function Get-PlausibilityFilteredStockObservations {
    param([object[]]$Rows,[int]$ExpectedPollIntervalSeconds=60)
    $classified=@(Resolve-StockObservationPlausibility -Rows $Rows -ExpectedPollIntervalSeconds $ExpectedPollIntervalSeconds)
    return @($classified|Where-Object{[bool](Get-CycleFilterProperty $_ 'calculationEligible')})
}

function Get-CycleSpuriousTransitionRegistry {
    if($script:CycleSpuriousRegistryLoaded){return $script:CycleSpuriousRegistry}
    $script:CycleSpuriousRegistryLoaded=$true
    if(-not(Test-Path -LiteralPath $script:CycleSpuriousRegistryPath)){return $null}
    try{
        $raw=[System.IO.File]::ReadAllText($script:CycleSpuriousRegistryPath)
        if(-not[string]::IsNullOrWhiteSpace($raw)){$script:CycleSpuriousRegistry=$raw|ConvertFrom-Json}
    }catch{$script:CycleSpuriousRegistry=$null}
    return $script:CycleSpuriousRegistry
}

function Test-CycleSuppressedByObservationPlausibility {
    param([object]$Cycle)
    if($null -eq $Cycle){return $false}
    $source=([string](Get-CycleFilterProperty $Cycle 'source')).Trim().ToLowerInvariant()
    if($source -eq 'torn_intel_history_recovery'){return $false}
    $country=([string](Get-CycleFilterProperty $Cycle 'country')).Trim().ToLowerInvariant()
    $itemId=[int](Get-CycleFilterProperty $Cycle 'itemId')
    if([string]::IsNullOrWhiteSpace($country) -or $itemId -le 0){return $false}
    $registry=Get-CycleSpuriousTransitionRegistry
    if($null -eq $registry -or -not$registry.PSObject.Properties['markets']){return $false}
    $marketKey=$country+':'+[string]$itemId
    $updatedAt=[long](Get-CycleFilterProperty $registry 'updatedAt')
    $now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    if($updatedAt -gt 0 -and ($now-$updatedAt) -gt 600L){return $false}
    $marketProperty=$registry.markets.PSObject.Properties[$marketKey]
    if($null -eq $marketProperty -or $null -eq $marketProperty.Value){return $false}
    $suppressed=@{}
    foreach($at in @((Get-CycleFilterProperty $marketProperty.Value 'transitionTimestamps'))){
        $value=[long]$at
        if($value -gt 0){$suppressed[[string]$value]=$true}
    }
    if($suppressed.Count -eq 0){return $false}
    foreach($name in @('restockAt','soldOutAt','previousSoldOutAt')){
        $at=[long](Get-CycleFilterProperty $Cycle $name)
        if($at -gt 0 -and $suppressed.ContainsKey([string]$at)){return $true}
    }
    return $false
}

function Get-CycleBoundaryPolicy {
    param([object[]]$Cycles,[int]$ExpectedPollIntervalSeconds = 60)

    $poll = [Math]::Max(15,[int]$ExpectedPollIntervalSeconds)
    $usable = @(Select-CadenceAwareForecastCycles -Cycles $Cycles -MaximumSamples 48 -Purpose Forecast)
    $availability = [long[]]@($usable | ForEach-Object { [long]$_.availabilitySeconds })
    $delays = [long[]]@($usable | ForEach-Object { [long]$_.restockDelaySeconds })
    $periods = [long[]]@($usable | ForEach-Object { [long]$_.availabilitySeconds + [long]$_.restockDelaySeconds })

    $availabilityMedian = Get-CycleForecastMedian -Values $availability
    $delayMedian = Get-CycleForecastMedian -Values $delays
    $periodMedian = Get-CycleForecastMedian -Values $periods
    $availabilitySigma = Get-CycleForecastRobustSigma -Values $availability
    $delaySigma = Get-CycleForecastRobustSigma -Values $delays

    $selloutSafe = [Math]::Max([long](3 * $poll),[long][Math]::Round($availabilitySigma * 0.5))
    $restockSafe = [Math]::Max([long](3 * $poll),[long][Math]::Round($delaySigma * 0.5))
    $fallbackHard = [Math]::Max(1800L,[long](10 * $poll))
    $halfPeriod = if ($periodMedian -gt 0) { [long][Math]::Round($periodMedian * 0.5) } else { 0L }
    $selloutHardCandidates = [long[]]@($availabilityMedian,$halfPeriod | Where-Object { $_ -gt 0 })
    $restockHardCandidates = [long[]]@($delayMedian,$halfPeriod | Where-Object { $_ -gt 0 })
    $selloutHard = if ($selloutHardCandidates.Count -gt 0) { [long]($selloutHardCandidates | Measure-Object -Minimum).Minimum } else { $fallbackHard }
    $restockHard = if ($restockHardCandidates.Count -gt 0) { [long]($restockHardCandidates | Measure-Object -Minimum).Minimum } else { $fallbackHard }
    $selloutHard = [Math]::Max($selloutHard,[long]($selloutSafe + $poll))
    $restockHard = [Math]::Max($restockHard,[long]($restockSafe + $poll))

    return [pscustomobject]@{
        expectedPollSeconds = $poll
        sampleCount = $usable.Count
        selloutSafeGapSeconds = $selloutSafe
        restockSafeGapSeconds = $restockSafe
        selloutHardGapSeconds = $selloutHard
        restockHardGapSeconds = $restockHard
    }
}

function Get-CycleBoundaryQuality {
    param([long]$GapSeconds,[object]$Policy,[ValidateSet('sellout','restock')][string]$Phase)
    $poll = [long]$Policy.expectedPollSeconds
    $safe = if ($Phase -eq 'sellout') { [long]$Policy.selloutSafeGapSeconds } else { [long]$Policy.restockSafeGapSeconds }
    $hard = if ($Phase -eq 'sellout') { [long]$Policy.selloutHardGapSeconds } else { [long]$Policy.restockHardGapSeconds }
    if ($GapSeconds -le [Math]::Max($poll,1L)) { return 'observed' }
    if ($GapSeconds -le $safe) { return 'bounded' }
    if ($GapSeconds -lt $hard) { return 'uncertain' }
    return 'unknown_gap'
}

function Test-CycleForecastBoundaryEvidence {
    param([object]$Cycle,[ValidateSet('Forecast','Trend')][string]$Purpose='Forecast')
    if ($null -eq $Cycle) { return $false }

    # Runtime schema-v1 cycles predate boundary observability metadata. Retain them
    # for audit/history, but never let them teach the forecast: a collector outage
    # could have been misread as hours of stock or OOS time.
    if ($Cycle.PSObject.Properties['schemaVersion'] -and [int]$Cycle.schemaVersion -lt 2) {
        return $false
    }

    if (Test-CycleSuppressedByObservationPlausibility -Cycle $Cycle) { return $false }
    if ($Cycle.PSObject.Properties['forecastEligible'] -and -not [bool]$Cycle.forecastEligible) { return $false }
    if ($Cycle.PSObject.Properties['availabilityEligible'] -and -not [bool]$Cycle.availabilityEligible) { return $false }
    if ($Cycle.PSObject.Properties['restockDelayEligible'] -and -not [bool]$Cycle.restockDelayEligible) { return $false }
    if ($Purpose -eq 'Trend' -and $Cycle.PSObject.Properties['trendEligible'] -and -not [bool]$Cycle.trendEligible) { return $false }

    foreach ($qualityName in @('restockBoundaryQuality','soldOutBoundaryQuality','previousSellOutBoundaryQuality')) {
        if (-not $Cycle.PSObject.Properties[$qualityName]) { continue }
        $quality=([string]$Cycle.$qualityName).Trim().ToLowerInvariant()
        if ([string]::IsNullOrWhiteSpace($quality)) { continue }
        if ($quality -notin @('observed','bounded','recovered')) { return $false }
    }
    return $true
}

function Select-CadenceAwareForecastCycles {
    param(
        [object[]]$Cycles,
        [int]$MaximumSamples = 48,
        [ValidateSet('Forecast','Trend')][string]$Purpose = 'Forecast'
    )

    $usable = @($Cycles | Where-Object {
        $null -ne $_ -and
        $_.PSObject.Properties['restockDelaySeconds'] -and [long]$_.restockDelaySeconds -gt 0 -and
        $_.PSObject.Properties['availabilitySeconds'] -and [long]$_.availabilitySeconds -gt 0 -and
        (Test-CycleForecastBoundaryEvidence -Cycle $_ -Purpose $Purpose)
    } | Sort-Object @{Expression={ if ($_.PSObject.Properties['soldOutAt']) { [long]$_.soldOutAt } else { 0L } };Descending=$true})
    if ($MaximumSamples -gt 0 -and $usable.Count -gt $MaximumSamples) { $usable = @($usable | Select-Object -First $MaximumSamples) }
    if ($usable.Count -lt 5) { return $usable }

    $periods = [long[]]@($usable | ForEach-Object { [long]$_.restockDelaySeconds + [long]$_.availabilitySeconds })
    $medianPeriod = Get-CycleForecastMedian -Values $periods
    if ($medianPeriod -le 0) { return $usable }

    # Retain every real row for audit/history, but exclude capture-gap pseudo-cycles
    # from forecasts. Fast markets (normally >=8 cycles/day) get a 24-hour ceiling;
    # other multi-cycle/day markets get 48 hours. Once-daily or slower markets keep
    # a much wider cadence-relative history window.
    $maximumPeriod = 0L
    if ($medianPeriod -le 10800L) { $maximumPeriod = 86400L }
    elseif ($medianPeriod -lt 86400L) { $maximumPeriod = 172800L }
    else { $maximumPeriod = [Math]::Max(604800L,[long][Math]::Ceiling($medianPeriod * 4.0)) }
    $minimumPeriod = [Math]::Max(60L,[long][Math]::Floor($medianPeriod * 0.25))

    $filtered = @($usable | Where-Object {
        $period = [long]$_.restockDelaySeconds + [long]$_.availabilitySeconds
        $period -ge $minimumPeriod -and $period -le $maximumPeriod
    })
    $minimumKeep = [Math]::Max(3,[int][Math]::Ceiling($usable.Count * 0.5))
    if ($filtered.Count -ge $minimumKeep) { return $filtered }
    return $usable
}
