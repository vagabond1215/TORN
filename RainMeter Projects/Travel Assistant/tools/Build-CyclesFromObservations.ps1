param(
    [Parameter(Mandatory = $true)]
    [string]$InputPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$CycleFilterScript = Join-Path $ProjectRoot '@Resources\Scripts\CycleForecastFilter.ps1'
if (-not (Test-Path -LiteralPath $CycleFilterScript)) { throw 'CycleForecastFilter.ps1 is required for censor-aware cycle construction.' }
. $CycleFilterScript

function Get-ObservationEventAt {
    param([object]$Row)
    $sourceAt = if ($Row.PSObject.Properties['sourceTimestamp']) { [long]$Row.sourceTimestamp } else { 0L }
    if ($sourceAt -gt 0) { return $sourceAt }
    return [long]$Row.timestamp
}

function Read-ObservationJsonl {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { throw "Input file not found: $Path" }

    $rows = New-Object System.Collections.Generic.List[object]
    $lineNumber = 0
    foreach ($line in Get-Content -LiteralPath $Path) {
        $lineNumber++
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $row = $line | ConvertFrom-Json }
        catch { throw ("Invalid JSON at line " + $lineNumber + ": " + $_.Exception.Message) }

        foreach ($name in @('schemaVersion','timestamp','country','itemId','stock','foreignPrice','source','sourceTimestamp')) {
            if (-not $row.PSObject.Properties[$name]) { throw ("Observation line " + $lineNumber + " is missing '" + $name + "'.") }
        }
        $schema = [int]$row.schemaVersion
        if ($schema -notin @(1,2)) { throw ("Observation line " + $lineNumber + " has unsupported schemaVersion '" + $schema + "'.") }
        if ([long]$row.timestamp -le 0) { throw ("Observation line " + $lineNumber + " has invalid timestamp.") }
        if ([long]$row.sourceTimestamp -lt 0) { throw ("Observation line " + $lineNumber + " has invalid sourceTimestamp.") }
        if ((Get-ObservationEventAt $row) -le 0) { throw ("Observation line " + $lineNumber + " has no usable evidence timestamp.") }
        if ([int]$row.itemId -le 0) { throw ("Observation line " + $lineNumber + " has invalid itemId.") }
        if ([int]$row.stock -lt 0) { throw ("Observation line " + $lineNumber + " has negative stock.") }
        if ([long]$row.foreignPrice -lt 0) { throw ("Observation line " + $lineNumber + " has negative foreignPrice.") }
        if ([string]::IsNullOrWhiteSpace([string]$row.country)) { throw ("Observation line " + $lineNumber + " has empty country.") }
        if ([string]::IsNullOrWhiteSpace([string]$row.source)) { throw ("Observation line " + $lineNumber + " has empty source.") }
        $rows.Add($row)
    }
    return $rows.ToArray()
}

function Write-JsonLinesAtomic {
    param([string]$Path, [object[]]$Rows)
    $parent = Split-Path -Parent $Path
    if (-not [string]::IsNullOrWhiteSpace($parent)) { New-Item -ItemType Directory -Force -Path $parent | Out-Null }
    $tmp = $Path + '.tmp'
    $writer = New-Object System.IO.StreamWriter($tmp, $false, [System.Text.UTF8Encoding]::new($false))
    try {
        foreach ($row in $Rows) {
            $writer.WriteLine(($row | ConvertTo-Json -Compress -Depth 14))
        }
    } finally {
        $writer.Dispose()
    }
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-ExpectedPollSeconds {
    param([object[]]$Rows)
    $previous = 0L
    $gaps = New-Object System.Collections.Generic.List[long]
    foreach ($row in @($Rows)) {
        $at = Get-ObservationEventAt $row
        if ($previous -gt 0 -and $at -gt $previous) { $gaps.Add([long]($at-$previous)) }
        if ($at -gt $previous) { $previous = $at }
    }
    if ($gaps.Count -eq 0) { return 60 }
    $median = Get-CycleForecastMedian -Values $gaps.ToArray()
    return [int][Math]::Max(15L,[Math]::Min(3600L,$median))
}

function Test-BuilderForecastBoundary {
    param([string]$Quality)
    return (([string]$Quality).Trim().ToLowerInvariant() -in @('observed','bounded','recovered'))
}

function New-LeftCensoredCycle {
    param([object]$Row,[long]$At)
    return [pscustomobject]@{
        previousSoldOutAt = 0L
        previousSoldOutLowerBoundAt = 0L
        previousSoldOutUpperBoundAt = 0L
        previousSellOutBoundaryQuality = 'left_censored'
        restockAt = 0L
        restockLowerBoundAt = 0L
        restockUpperBoundAt = [long]$At
        restockBoundaryQuality = 'left_censored'
        restockQuantity = [int]$Row.stock
        foreignPrice = [long]$Row.foreignPrice
        minimumForeignPrice = [long]$Row.foreignPrice
        maximumForeignPrice = [long]$Row.foreignPrice
        source = [string]$Row.source
        evidenceQuality = 'left_censored'
    }
}

function Get-BuilderCycleEvidenceQuality {
    param([bool]$AvailabilityEligible,[bool]$RestockDelayEligible,[string[]]$BoundaryQualities,[bool]$LeftCensored)
    if ($LeftCensored) { return 'left_censored' }
    if (-not $AvailabilityEligible -or -not $RestockDelayEligible) { return 'incomplete' }
    $bad = @($BoundaryQualities | Where-Object {
        $q = ([string]$_).Trim().ToLowerInvariant()
        $q -notin @('observed','recovered')
    })
    if ($bad.Count -eq 0) { return 'bounded_fresh' }
    return 'bounded_gap'
}

$observations = @(Read-ObservationJsonl -Path $InputPath)
$cycles = New-Object System.Collections.Generic.List[object]

$groups = $observations | Group-Object { ('{0}|{1}' -f [string]$_.country, [int]$_.itemId) }
foreach ($group in $groups) {
    $rows = @($group.Group | Sort-Object @{ Expression = { Get-ObservationEventAt $_ } }, @{ Expression = { [long]$_.timestamp } })
    $expectedPoll = Get-ExpectedPollSeconds -Rows $rows
    $boundaryPolicy = Get-CycleBoundaryPolicy -Cycles @() -ExpectedPollIntervalSeconds $expectedPoll
    $fullCycleGap = [Math]::Max(
        [long](2 * [Math]::Max(1,[long]$boundaryPolicy.expectedPollSeconds)),
        [long]$boundaryPolicy.selloutHardGapSeconds + [long]$boundaryPolicy.restockHardGapSeconds
    )

    $previousStock = $null
    $previousAt = 0L
    $lastSoldOutAt = 0L
    $lastSoldOutLower = 0L
    $lastSoldOutUpper = 0L
    $lastSoldOutQuality = 'unknown'
    $active = $null

    foreach ($row in $rows) {
        $stock = [int]$row.stock
        $ts = Get-ObservationEventAt $row
        if ($previousAt -gt 0 -and $ts -lt $previousAt) { continue }

        if ($null -eq $previousStock) {
            if ($stock -gt 0) { $active = New-LeftCensoredCycle -Row $row -At $ts }
            $previousStock = $stock
            $previousAt = $ts
            continue
        }

        $gap = [Math]::Max(0L,$ts-$previousAt)
        $samePhase = (([int]$previousStock -gt 0 -and $stock -gt 0) -or ([int]$previousStock -eq 0 -and $stock -eq 0))
        if ($samePhase -and $gap -ge $fullCycleGap) {
            # A full sellout/restock cycle could have occurred while collection was
            # absent. Break phase continuity but retain the current positive state
            # as left-censored evidence.
            if ($stock -gt 0) {
                $active = New-LeftCensoredCycle -Row $row -At $ts
            } else {
                $active = $null
                $lastSoldOutAt = 0L
                $lastSoldOutLower = 0L
                $lastSoldOutUpper = 0L
                $lastSoldOutQuality = 'unknown_gap'
            }
        }

        if ([int]$previousStock -eq 0 -and $stock -gt 0) {
            $quality = Get-CycleBoundaryQuality -GapSeconds $gap -Policy $boundaryPolicy -Phase restock
            $known = Test-BuilderForecastBoundary -Quality $quality
            $active = [pscustomobject]@{
                previousSoldOutAt = $lastSoldOutAt
                previousSoldOutLowerBoundAt = $lastSoldOutLower
                previousSoldOutUpperBoundAt = $lastSoldOutUpper
                previousSellOutBoundaryQuality = $lastSoldOutQuality
                restockAt = $(if ($known) { $ts } else { 0L })
                restockLowerBoundAt = $previousAt
                restockUpperBoundAt = $ts
                restockBoundaryQuality = $quality
                restockQuantity = $stock
                foreignPrice = [long]$row.foreignPrice
                minimumForeignPrice = [long]$row.foreignPrice
                maximumForeignPrice = [long]$row.foreignPrice
                source = [string]$row.source
                evidenceQuality = 'right_censored'
            }
            if (-not $known) {
                $lastSoldOutAt = 0L
                $lastSoldOutLower = 0L
                $lastSoldOutUpper = 0L
                $lastSoldOutQuality = 'unknown_gap'
            }
        } elseif ([int]$previousStock -gt 0 -and $stock -eq 0) {
            $quality = Get-CycleBoundaryQuality -GapSeconds $gap -Policy $boundaryPolicy -Phase sellout
            $selloutKnown = Test-BuilderForecastBoundary -Quality $quality
            $selloutLower = $previousAt
            $selloutUpper = $ts
            $lastSoldOutAt = $(if ($selloutKnown) { $ts } else { 0L })
            $lastSoldOutLower = $selloutLower
            $lastSoldOutUpper = $selloutUpper
            $lastSoldOutQuality = $quality

            if ($null -ne $active) {
                $restockAt = [long]$active.restockAt
                $restockLower = [long]$active.restockLowerBoundAt
                $restockUpper = [long]$active.restockUpperBoundAt
                $previousSoldOutAt = [long]$active.previousSoldOutAt
                $previousSoldOutLower = [long]$active.previousSoldOutLowerBoundAt
                $previousSoldOutUpper = [long]$active.previousSoldOutUpperBoundAt
                $restockQuality = [string]$active.restockBoundaryQuality
                $previousSelloutQuality = [string]$active.previousSellOutBoundaryQuality

                $availabilityMinimum = if ($selloutKnown -and $restockUpper -gt 0) { [Math]::Max(0L,$selloutLower-$restockUpper) } else { 0L }
                $availabilityMaximum = if ($selloutKnown -and $restockLower -gt 0) { [Math]::Max(0L,$selloutUpper-$restockLower) } else { 0L }
                $delayMinimum = if ($restockLower -gt 0 -and $previousSoldOutUpper -gt 0) { [Math]::Max(0L,$restockLower-$previousSoldOutUpper) } else { 0L }
                $delayMaximum = if ($restockUpper -gt 0 -and $previousSoldOutLower -gt 0) { [Math]::Max(0L,$restockUpper-$previousSoldOutLower) } else { 0L }

                $availabilityEligible = ($selloutKnown -and $restockAt -gt 0 -and (Test-BuilderForecastBoundary -Quality $restockQuality) -and $availabilityMinimum -gt 0)
                $restockDelayEligible = ($restockAt -gt 0 -and $previousSoldOutAt -gt 0 -and (Test-BuilderForecastBoundary -Quality $previousSelloutQuality) -and $delayMaximum -gt 0)
                $leftCensored = ([string]$active.evidenceQuality -eq 'left_censored')
                $evidenceQuality = Get-BuilderCycleEvidenceQuality -AvailabilityEligible $availabilityEligible -RestockDelayEligible $restockDelayEligible -BoundaryQualities @($restockQuality,$quality,$previousSelloutQuality) -LeftCensored $leftCensored

                $cycles.Add([pscustomobject]@{
                    schemaVersion = 2
                    country = [string]$row.country
                    itemId = [int]$row.itemId
                    foreignPrice = [long]$active.foreignPrice
                    minimumForeignPrice = [long]$active.minimumForeignPrice
                    maximumForeignPrice = [long]$active.maximumForeignPrice
                    restockAt = $restockAt
                    restockLowerBoundAt = $restockLower
                    restockUpperBoundAt = $restockUpper
                    restockBoundaryQuality = $restockQuality
                    restockQuantity = [int]$active.restockQuantity
                    soldOutAt = $(if ($selloutKnown) { $ts } else { 0L })
                    soldOutLowerBoundAt = $selloutLower
                    soldOutUpperBoundAt = $selloutUpper
                    soldOutBoundaryQuality = $quality
                    availabilitySeconds = $availabilityMinimum
                    availabilityMinimumSeconds = $availabilityMinimum
                    availabilityMaximumSeconds = $availabilityMaximum
                    availabilityEligible = $availabilityEligible
                    previousSoldOutAt = $previousSoldOutAt
                    previousSoldOutLowerBoundAt = $previousSoldOutLower
                    previousSoldOutUpperBoundAt = $previousSoldOutUpper
                    previousSellOutBoundaryQuality = $previousSelloutQuality
                    restockDelaySeconds = $(if ($restockDelayEligible) { [Math]::Max(0L,$restockAt-$previousSoldOutAt) } else { 0L })
                    restockDelayMinimumSeconds = $delayMinimum
                    restockDelayMaximumSeconds = $delayMaximum
                    restockDelayEligible = $restockDelayEligible
                    trendEligible = ($availabilityEligible -and $restockDelayEligible)
                    forecastEligible = ($availabilityEligible -and $restockDelayEligible)
                    evidenceQuality = $evidenceQuality
                    isRightCensored = $false
                    selloutDepletionEvidence = 'sellout_censored'
                    selloutDemandLowerBoundUnits = [Math]::Max(0L,[long]$previousStock)
                    source = [string]$active.source
                })
            }
            $active = $null
        } elseif ($stock -gt 0 -and $null -ne $active) {
            $price = [long]$row.foreignPrice
            if ($price -gt 0) {
                if ([long]$active.minimumForeignPrice -le 0 -or $price -lt [long]$active.minimumForeignPrice) { $active.minimumForeignPrice = $price }
                if ([long]$active.maximumForeignPrice -le 0 -or $price -gt [long]$active.maximumForeignPrice) { $active.maximumForeignPrice = $price }
            }
        }

        $previousStock = $stock
        $previousAt = $ts
    }
}

$dedup = New-Object System.Collections.Generic.List[object]
$seen = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($cycle in @($cycles | Sort-Object country, itemId, restockUpperBoundAt, soldOutUpperBoundAt)) {
    $key = ('{0}|{1}|{2}|{3}|{4}' -f [string]$cycle.country, [int]$cycle.itemId, [long]$cycle.restockUpperBoundAt, [long]$cycle.soldOutUpperBoundAt, [long]$cycle.foreignPrice)
    if ($seen.Add($key)) { $dedup.Add($cycle) }
}

Write-JsonLinesAtomic -Path $OutputPath -Rows $dedup.ToArray()
Write-Host ("Built {0} censor-aware cycle record(s) from {1} observation(s)." -f $dedup.Count, $observations.Count) -ForegroundColor Green
Write-Host ("Output: {0}" -f (Resolve-Path -LiteralPath $OutputPath).Path)
exit 0
