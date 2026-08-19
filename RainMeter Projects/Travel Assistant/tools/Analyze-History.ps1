param(
    [string]$Country = '',
    [int]$ItemId = 0,

    [ValidateRange(1000, 500000)]
    [int]$PriceBucketSize = 25000,

    [ValidateRange(1, 100)]
    [int]$MinimumSamples = 3,

    [switch]$SaveJson
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$SeedCycles = Join-Path $ProjectRoot 'data\seed\cycles.jsonl'
$RuntimeCycles = Join-Path $ProjectRoot 'data\runtime\cycles.jsonl'
$AnalysisDir = Join-Path $ProjectRoot 'data\runtime\analysis'

function Read-Cycles {
    param([string[]]$Paths)
    $rows = New-Object System.Collections.Generic.List[object]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        $lineNumber = 0
        foreach ($line in Get-Content -LiteralPath $path) {
            $lineNumber++
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $row = $line | ConvertFrom-Json }
            catch { Write-Warning "Skipping invalid JSONL line $lineNumber in $path"; continue }
            if (-not $row.PSObject.Properties['country'] -or -not $row.PSObject.Properties['itemId']) { continue }
            if (-not [string]::IsNullOrWhiteSpace($Country) -and [string]$row.country -ne $Country) { continue }
            if ($ItemId -gt 0 -and [int]$row.itemId -ne $ItemId) { continue }
            if (-not $row.PSObject.Properties['restockAt'] -or -not $row.PSObject.Properties['soldOutAt']) { continue }
            $key = ('{0}|{1}|{2}|{3}|{4}' -f [string]$row.country, [int]$row.itemId, [long]$row.restockAt, [long]$row.soldOutAt, [long]$row.foreignPrice)
            if ($seen.Add($key)) { $rows.Add($row) }
        }
    }
    return @($rows)
}

function Get-Median {
    param([double[]]$Values)
    if ($null -eq $Values -or $Values.Count -eq 0) { return $null }
    $sorted = @($Values | Sort-Object)
    $mid = [int][Math]::Floor($sorted.Count / 2)
    if (($sorted.Count % 2) -eq 1) { return [double]$sorted[$mid] }
    return ([double]$sorted[$mid - 1] + [double]$sorted[$mid]) / 2.0
}

function New-Summary {
    param([object[]]$Rows)
    if ($Rows.Count -eq 0) { return $null }
    $availability = [double[]]@($Rows | Where-Object { [long]$_.availabilitySeconds -gt 0 } | ForEach-Object { [double]$_.availabilitySeconds })
    $restockDelay = [double[]]@($Rows | Where-Object { $_.PSObject.Properties['restockDelaySeconds'] -and [long]$_.restockDelaySeconds -gt 0 } | ForEach-Object { [double]$_.restockDelaySeconds })
    return [pscustomobject]@{
        samples = $Rows.Count
        medianAvailabilitySeconds = if ($availability.Count -gt 0) { [long][Math]::Round((Get-Median $availability)) } else { $null }
        fastestSelloutSeconds = if ($availability.Count -gt 0) { [long](($availability | Measure-Object -Minimum).Minimum) } else { $null }
        slowestSelloutSeconds = if ($availability.Count -gt 0) { [long](($availability | Measure-Object -Maximum).Maximum) } else { $null }
        medianRestockDelaySeconds = if ($restockDelay.Count -gt 0) { [long][Math]::Round((Get-Median $restockDelay)) } else { $null }
        minRestockDelaySeconds = if ($restockDelay.Count -gt 0) { [long](($restockDelay | Measure-Object -Minimum).Minimum) } else { $null }
        maxRestockDelaySeconds = if ($restockDelay.Count -gt 0) { [long](($restockDelay | Measure-Object -Maximum).Maximum) } else { $null }
    }
}

$cycles = @(Read-Cycles -Paths @($SeedCycles, $RuntimeCycles))
if ($cycles.Count -eq 0) {
    Write-Host 'No completed cycles are available yet.' -ForegroundColor Yellow
    exit 0
}

$reports = New-Object System.Collections.Generic.List[object]
foreach ($identity in ($cycles | Group-Object { ('{0}|{1}' -f [string]$_.country, [int]$_.itemId) })) {
    $rows = @($identity.Group | Sort-Object soldOutAt)
    $parts = $identity.Name.Split('|')

    $priceGroups = New-Object System.Collections.Generic.List[object]
    foreach ($priceGroup in ($rows | Group-Object {
        $bucket = [long]([Math]::Floor(([double]$_.foreignPrice) / $PriceBucketSize) * $PriceBucketSize)
        [string]$bucket
    } | Sort-Object { [long]$_.Name })) {
        if ($priceGroup.Count -lt $MinimumSamples) { continue }
        $bucketStart = [long]$priceGroup.Name
        $priceGroups.Add([pscustomobject]@{
            priceMin = $bucketStart
            priceMaxExclusive = $bucketStart + $PriceBucketSize
            summary = New-Summary -Rows @($priceGroup.Group)
        })
    }

    $hourGroups = New-Object System.Collections.Generic.List[object]
    foreach ($hourGroup in ($rows | Group-Object {
        [DateTimeOffset]::FromUnixTimeSeconds([long]$_.restockAt).UtcDateTime.Hour
    } | Sort-Object { [int]$_.Name })) {
        if ($hourGroup.Count -lt $MinimumSamples) { continue }
        $hourGroups.Add([pscustomobject]@{
            utcHour = [int]$hourGroup.Name
            summary = New-Summary -Rows @($hourGroup.Group)
        })
    }

    $reports.Add([pscustomobject]@{
        country = $parts[0]
        itemId = [int]$parts[1]
        overall = New-Summary -Rows $rows
        priceBuckets = @($priceGroups)
        restockUtcHours = @($hourGroups)
        newestSoldOutAt = [long](($rows | Measure-Object soldOutAt -Maximum).Maximum)
        oldestSoldOutAt = [long](($rows | Measure-Object soldOutAt -Minimum).Minimum)
    })
}

$report = [pscustomobject]@{
    schemaVersion = 1
    generatedAt = [DateTimeOffset]::UtcNow.ToString('o')
    priceBucketSize = $PriceBucketSize
    minimumSamples = $MinimumSamples
    cycleCount = $cycles.Count
    reports = @($reports)
}

foreach ($entry in $reports) {
    Write-Host ''
    Write-Host ("{0} / item {1} — {2} cycle(s)" -f $entry.country, $entry.itemId, $entry.overall.samples) -ForegroundColor Cyan
    Write-Host ("  availability median {0}s; range {1}s–{2}s" -f $entry.overall.medianAvailabilitySeconds, $entry.overall.fastestSelloutSeconds, $entry.overall.slowestSelloutSeconds)
    if ($null -ne $entry.overall.medianRestockDelaySeconds) {
        Write-Host ("  restock delay median {0}s; range {1}s–{2}s" -f $entry.overall.medianRestockDelaySeconds, $entry.overall.minRestockDelaySeconds, $entry.overall.maxRestockDelaySeconds)
    }
    if (@($entry.priceBuckets).Count -gt 0) {
        Write-Host '  trained price buckets:'
        foreach ($bucket in @($entry.priceBuckets)) {
            Write-Host ('    {0:C0}–{1:C0}: n={2}, median availability={3}s' -f $bucket.priceMin, ($bucket.priceMaxExclusive - 1), $bucket.summary.samples, $bucket.summary.medianAvailabilitySeconds)
        }
    }
    if (@($entry.restockUtcHours).Count -gt 0) {
        Write-Host '  UTC restock hours with enough samples:'
        foreach ($hour in @($entry.restockUtcHours)) {
            Write-Host ("    {0:00}:00: n={1}, median availability={2}s" -f $hour.utcHour, $hour.summary.samples, $hour.summary.medianAvailabilitySeconds)
        }
    }
}

if ($SaveJson) {
    New-Item -ItemType Directory -Force -Path $AnalysisDir | Out-Null
    $path = Join-Path $AnalysisDir ('history-' + [DateTimeOffset]::UtcNow.ToString('yyyyMMdd-HHmmss') + '.json')
    $json = $report | ConvertTo-Json -Depth 20
    [System.IO.File]::WriteAllText($path, $json + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    Write-Host ''
    Write-Host ("Saved runtime-only analysis: {0}" -f $path) -ForegroundColor Green
}

Write-Host ''
Write-Host 'Analysis is descriptive evidence only; small cohorts are not automatically promoted into recommendation rules.' -ForegroundColor Yellow
exit 0
