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
        (-not $_.PSObject.Properties['availabilityEligible'] -or [bool]$_.availabilityEligible) -and
        (-not $_.PSObject.Properties['restockDelayEligible'] -or [bool]$_.restockDelayEligible) -and
        ($Purpose -ne 'Trend' -or -not $_.PSObject.Properties['trendEligible'] -or [bool]$_.trendEligible)
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
