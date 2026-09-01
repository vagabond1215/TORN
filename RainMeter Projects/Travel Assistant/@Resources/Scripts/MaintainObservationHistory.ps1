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
$AtomicFileScript = Join-Path $PSScriptRoot 'AtomicFile.ps1'
if (-not (Test-Path -LiteralPath $AtomicFileScript)) { throw 'AtomicFile.ps1 is required for shared history maintenance IO.' }
. $AtomicFileScript

if ($Now -le 0) { $Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

function Read-HistoryJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Read-TravelAssistantSharedText -Path $Path
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-HistoryJsonAtomic {
    param([string]$Path,[object]$Value,[int]$Depth=24)
    Write-TravelAssistantAtomicJson -Path $Path -Value $Value -Depth $Depth
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

    # One-time migration from timestamp-noise history to transition-only evidence.
    # Read with delete sharing, write to a unique sibling, then atomically publish.
    $lastStockByKey = @{}
    $tmp = New-TravelAssistantAtomicTempPath -Path $ObservationFile
    $reader = $null
    $writer = $null
    $removed = 0
    try {
        $reader = Open-TravelAssistantSharedTextReader -Path $ObservationFile
        $writer = New-Object System.IO.StreamWriter($tmp,$false,[System.Text.UTF8Encoding]::new($false))
        while (($line = $reader.ReadLine()) -ne $null) {
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
                $removed++
            }
        }
    } finally {
        if ($null -ne $writer) { $writer.Dispose() }
        if ($null -ne $reader) { $reader.Dispose() }
    }
    try {
        Publish-TravelAssistantAtomicTempFile -TempPath $tmp -Path $ObservationFile
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
    [System.IO.File]::WriteAllText($SyntheticCleanupMarker,('removed_or_compacted=' + $removed),[System.Text.UTF8Encoding]::new($false))
    return $removed
}

function Write-BaselineAwareObservationPrune {
    param([long]$Cutoff)
    if (-not (Test-Path -LiteralPath $ObservationFile)) { return }

    $latestBefore = @{}
    $reader = $null
    try {
        $reader = Open-TravelAssistantSharedTextReader -Path $ObservationFile
        while (($line = $reader.ReadLine()) -ne $null) {
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
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
    }

    $tmp = New-TravelAssistantAtomicTempPath -Path $ObservationFile
    $writer = $null
    $reader = $null
    try {
        $writer = New-Object System.IO.StreamWriter($tmp,$false,[System.Text.UTF8Encoding]::new($false))
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

        $reader = Open-TravelAssistantSharedTextReader -Path $ObservationFile
        while (($line = $reader.ReadLine()) -ne $null) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row = $line | ConvertFrom-Json
                if (Test-IsSyntheticHistorySource $row) { continue }
                if ([long](Get-HistoryProperty $row 'timestamp') -ge $Cutoff) { $writer.WriteLine($line) }
            } catch { }
        }
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $writer) { $writer.Dispose() }
    }
    try {
        Publish-TravelAssistantAtomicTempFile -TempPath $tmp -Path $ObservationFile
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

function Write-CyclePrune {
    param([long]$Cutoff)
    if (-not (Test-Path -LiteralPath $CycleFile)) { return }

    $tmp = New-TravelAssistantAtomicTempPath -Path $CycleFile
    $reader = $null
    $writer = $null
    try {
        $reader = Open-TravelAssistantSharedTextReader -Path $CycleFile
        $writer = New-Object System.IO.StreamWriter($tmp,$false,[System.Text.UTF8Encoding]::new($false))
        while (($line = $reader.ReadLine()) -ne $null) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row = $line | ConvertFrom-Json
                if ([long](Get-HistoryProperty $row 'soldOutAt') -ge $Cutoff) { $writer.WriteLine($line) }
            } catch { }
        }
    } finally {
        if ($null -ne $writer) { $writer.Dispose() }
        if ($null -ne $reader) { $reader.Dispose() }
    }
    try {
        Publish-TravelAssistantAtomicTempFile -TempPath $tmp -Path $CycleFile
    } finally {
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
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
