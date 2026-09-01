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

function Select-CadenceAwareForecastCycles {
    param([object[]]$Cycles,[int]$MaximumSamples = 48)

    $usable = @($Cycles | Where-Object {
        $null -ne $_ -and
        $_.PSObject.Properties['restockDelaySeconds'] -and [long]$_.restockDelaySeconds -gt 0 -and
        $_.PSObject.Properties['availabilitySeconds'] -and [long]$_.availabilitySeconds -gt 0
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
