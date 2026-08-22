param(
    [ValidateSet('PreUpdate','PostUpdate')]
    [string]$Phase = 'PostUpdate',
    [long]$Now = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$ObservationFile = Join-Path $RuntimeDir 'observations.jsonl'
$CycleFile = Join-Path $RuntimeDir 'cycles.jsonl'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$SettingsFile = Join-Path $ConfigDir 'settings.example.json'
$SyntheticCleanupMarker = Join-Path $RuntimeDir 'synthetic-history-cleanup-v1.done'

if ($Now -le 0) { $Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

function Read-HistoryJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-HistoryJsonAtomic {
    param([string]$Path,[object]$Value,[int]$Depth=24)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $tmp = $Path + '.tmp'
    $json = $Value | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($tmp,$json,[System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-HistoryProperty {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-HistoryMarketKey {
    param([object]$Row)
    $country = ([string](Get-HistoryProperty $Row 'country')).Trim().ToLowerInvariant()
    $itemId = [int](Get-HistoryProperty $Row 'itemId')
    if ([string]::IsNullOrWhiteSpace($country) -or $itemId -le 0) { return '' }
    return ($country + ':' + [string]$itemId)
}

function ConvertTo-HistoryLine {
    param([object]$Value)
    return ($Value | ConvertTo-Json -Compress -Depth 10)
}

function Test-IsSyntheticHistorySource {
    param([object]$Row)
    $source = [string](Get-HistoryProperty $Row 'source')
    return ($source -in @('history_bootstrap','history_repair_baseline'))
}

function Remove-SyntheticObservationArtifacts {
    if (Test-Path -LiteralPath $SyntheticCleanupMarker) { return 0 }
    if (-not (Test-Path -LiteralPath $ObservationFile)) {
        New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
        [System.IO.File]::WriteAllText($SyntheticCleanupMarker,'no observation file',[System.Text.UTF8Encoding]::new($false))
        return 0
    }

    # This is also the one-time migration from the legacy updater's every-source-
    # timestamp rows to the current transition-only database. For each market keep
    # the first retained state and every subsequent stock change; foreign-price-only
    # or timestamp-only repeats are discarded.
    $lastStockByKey = @{}
    $tmp = $ObservationFile + '.cleanup.tmp'
    $writer = New-Object System.IO.StreamWriter($tmp,$false,[System.Text.UTF8Encoding]::new($false))
    $removed = 0
    try {
        foreach ($line in Get-Content -LiteralPath $ObservationFile) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row = $line | ConvertFrom-Json
                if (Test-IsSyntheticHistorySource $row) { $removed++; continue }
                $key = Get-HistoryMarketKey $row
                if ([string]::IsNullOrWhiteSpace($key)) { $removed++; continue }
                $stock = [long](Get-HistoryProperty $row 'stock')
                if ($lastStockByKey.ContainsKey($key) -and [long]$lastStockByKey[$key] -eq $stock) {
                    $removed++
                    continue
                }
                $writer.WriteLine($line)
                $lastStockByKey[$key] = $stock
            } catch {
                # Invalid JSON is not useful evidence; omit it during the same migration cleanup.
                $removed++
            }
        }
    } finally { $writer.Dispose() }
    Move-Item -LiteralPath $tmp -Destination $ObservationFile -Force
    [System.IO.File]::WriteAllText($SyntheticCleanupMarker,('removed_or_compacted=' + $removed),[System.Text.UTF8Encoding]::new($false))
    return $removed
}

function Write-BaselineAwareObservationPrune {
    param([long]$Cutoff)
    if (-not (Test-Path -LiteralPath $ObservationFile)) { return }

    # A retention baseline is safe only when it comes from a real observation
    # immediately before the cutoff. It carries an actually observed state across
    # the boundary; it never backfills from current engine state.
    $latestBefore = @{}
    foreach ($line in Get-Content -LiteralPath $ObservationFile) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $row = $line | ConvertFrom-Json
            if (Test-IsSyntheticHistorySource $row) { continue }
            $key = Get-HistoryMarketKey $row
            if ([string]::IsNullOrWhiteSpace($key)) { continue }
            $timestamp = [long](Get-HistoryProperty $row 'timestamp')
            if ($timestamp -ge $Cutoff) { continue }
            if (-not $latestBefore.ContainsKey($key) -or [long](Get-HistoryProperty $latestBefore[$key] 'timestamp') -lt $timestamp) {
                $latestBefore[$key] = $row
            }
        } catch { }
    }

    $tmp = $ObservationFile + '.history.tmp'
    $writer = New-Object System.IO.StreamWriter($tmp,$false,[System.Text.UTF8Encoding]::new($false))
    try {
        foreach ($key in @($latestBefore.Keys | Sort-Object)) {
            $row = $latestBefore[$key]
            $baseline = [ordered]@{
                schemaVersion = 1
                timestamp = [long]$Cutoff
                country = [string](Get-HistoryProperty $row 'country')
                itemId = [int](Get-HistoryProperty $row 'itemId')
                stock = [int](Get-HistoryProperty $row 'stock')
                foreignPrice = [long](Get-HistoryProperty $row 'foreignPrice')
                source = 'retention_baseline'
                sourceTimestamp = [long](Get-HistoryProperty $row 'sourceTimestamp')
            }
            $itemName = [string](Get-HistoryProperty $row 'itemName')
            if (-not [string]::IsNullOrWhiteSpace($itemName)) { $baseline['itemName'] = $itemName }
            $writer.WriteLine((ConvertTo-HistoryLine ([pscustomobject]$baseline)))
        }

        foreach ($line in Get-Content -LiteralPath $ObservationFile) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row = $line | ConvertFrom-Json
                if (Test-IsSyntheticHistorySource $row) { continue }
                if ([long](Get-HistoryProperty $row 'timestamp') -ge $Cutoff) { $writer.WriteLine($line) }
            } catch { }
        }
    } finally { $writer.Dispose() }
    Move-Item -LiteralPath $tmp -Destination $ObservationFile -Force
}

function Write-CyclePrune {
    param([long]$Cutoff)
    if (-not (Test-Path -LiteralPath $CycleFile)) { return }
    $tmp = $CycleFile + '.history.tmp'
    $writer = New-Object System.IO.StreamWriter($tmp,$false,[System.Text.UTF8Encoding]::new($false))
    try {
        foreach ($line in Get-Content -LiteralPath $CycleFile) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row = $line | ConvertFrom-Json
                if ([long](Get-HistoryProperty $row 'soldOutAt') -ge $Cutoff) { $writer.WriteLine($line) }
            } catch { }
        }
    } finally { $writer.Dispose() }
    Move-Item -LiteralPath $tmp -Destination $CycleFile -Force
}

$settings = Read-HistoryJson $SettingsFile
$engine = Read-HistoryJson $EngineStateFile
if ($null -eq $settings -or $null -eq $engine) { return }

# One-time migration cleanup removes fabricated rows and compacts old same-stock
# polling noise. The marker prevents a full 48-hour JSONL rewrite every minute.
[void](Remove-SyntheticObservationArtifacts)

# PostUpdate performs migration cleanup only. If a market has no retained
# predecessor, that earlier interval remains unknown; no current-state baseline is fabricated.
if ($Phase -eq 'PostUpdate') { return }

$retentionHours = [Math]::Max(1,[int]$settings.highResolutionRetentionHours)
$cycleDays = [Math]::Max(1,[int]$settings.cycleRetentionDays)
$retentionCutoff = $Now-([long]$retentionHours*3600)

$lastPruneAt = 0L
if ($engine.PSObject.Properties['lastPruneAt']) { $lastPruneAt = [long]$engine.lastPruneAt }
if (($Now-$lastPruneAt) -lt 3600) { return }

Write-BaselineAwareObservationPrune -Cutoff $retentionCutoff
Write-CyclePrune -Cutoff ($Now-([long]$cycleDays*86400))
if ($engine.PSObject.Properties['lastPruneAt']) { $engine.lastPruneAt = $Now }
else { $engine | Add-Member NoteProperty lastPruneAt $Now }
Write-HistoryJsonAtomic -Path $EngineStateFile -Value $engine
return
