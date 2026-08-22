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

function Write-BaselineAwareObservationPrune {
    param([long]$Cutoff)
    if (-not (Test-Path -LiteralPath $ObservationFile)) { return }

    # Change-only history needs one predecessor per market. Without it, an item
    # that remains unchanged longer than the retention period becomes impossible
    # to draw even though its state is known continuously.
    $latestBefore = @{}
    foreach ($line in Get-Content -LiteralPath $ObservationFile) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $row = $line | ConvertFrom-Json
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

function Add-MissingMarketBaselines {
    param([object]$EngineState,[long]$RetentionCutoff)
    if ($null -eq $EngineState -or -not $EngineState.PSObject.Properties['observedMarkets']) { return 0 }

    $seen = @{}
    if (Test-Path -LiteralPath $ObservationFile) {
        foreach ($line in Get-Content -LiteralPath $ObservationFile) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row = $line | ConvertFrom-Json
                $key = Get-HistoryMarketKey $row
                if (-not [string]::IsNullOrWhiteSpace($key)) { $seen[$key] = $true }
            } catch { }
        }
    }

    New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
    $written = 0
    foreach ($property in @($EngineState.observedMarkets.PSObject.Properties)) {
        $market = $property.Value
        if ($null -eq $market) { continue }
        if (($market.PSObject.Properties['catalogActive'] -and $market.catalogActive -eq $false) -or ($market.PSObject.Properties['catalogStatus'] -and [string]$market.catalogStatus -eq 'legacy_removed')) { continue }

        $country = ([string](Get-HistoryProperty $market 'country')).Trim().ToLowerInvariant()
        $itemId = [int](Get-HistoryProperty $market 'itemId')
        if ([string]::IsNullOrWhiteSpace($country) -or $itemId -le 0) { continue }
        $key = $country + ':' + [string]$itemId
        if ($seen.ContainsKey($key)) { continue }

        # A market with zero retained rows but a known firstSeenAt is a migration/
        # retention hole in a change-only series. If any recorded stock/price change
        # had occurred since firstSeenAt, a row would still exist. Therefore the
        # current state is also the carried state from max(firstSeenAt, cutoff).
        $firstSeenAt = [long](Get-HistoryProperty $market 'firstSeenAt')
        $timestamp = 0L
        $rowSource = 'history_bootstrap'
        $rowSourceTimestamp = [long](Get-HistoryProperty $market 'sourceTimestamp')
        if ($firstSeenAt -gt 0) {
            $timestamp = [Math]::Max($RetentionCutoff,$firstSeenAt)
            $rowSource = 'history_repair_baseline'
            $rowSourceTimestamp = $timestamp
        } else {
            $timestamp = [long](Get-HistoryProperty $market 'sourceTimestamp')
            if ($timestamp -le 0) { $timestamp = [long](Get-HistoryProperty $market 'lastSeenAt') }
            if ($timestamp -le 0) { $timestamp = $Now }
        }

        $row = [ordered]@{
            schemaVersion = 1
            timestamp = [long]$timestamp
            country = $country
            itemId = $itemId
            stock = [int](Get-HistoryProperty $market 'lastStock')
            foreignPrice = [long](Get-HistoryProperty $market 'lastForeignPrice')
            source = $rowSource
            sourceTimestamp = [long]$rowSourceTimestamp
        }
        $providerName = [string](Get-HistoryProperty $market 'providerName')
        if (-not [string]::IsNullOrWhiteSpace($providerName)) { $row['itemName'] = $providerName }
        Add-Content -LiteralPath $ObservationFile -Value (ConvertTo-HistoryLine ([pscustomobject]$row)) -Encoding UTF8
        $seen[$key] = $true
        $written++
    }
    return $written
}

$settings = Read-HistoryJson $SettingsFile
$engine = Read-HistoryJson $EngineStateFile
if ($null -eq $settings -or $null -eq $engine) { return }

$retentionHours = [Math]::Max(1,[int]$settings.highResolutionRetentionHours)
$cycleDays = [Math]::Max(1,[int]$settings.cycleRetentionDays)
$retentionCutoff = $Now-([long]$retentionHours*3600)

if ($Phase -eq 'PreUpdate') {
    $lastPruneAt = 0L
    if ($engine.PSObject.Properties['lastPruneAt']) { $lastPruneAt = [long]$engine.lastPruneAt }
    if (($Now-$lastPruneAt) -lt 3600) { return }

    Write-BaselineAwareObservationPrune -Cutoff $retentionCutoff
    Write-CyclePrune -Cutoff ($Now-([long]$cycleDays*86400))
    if ($engine.PSObject.Properties['lastPruneAt']) { $engine.lastPruneAt = $Now }
    else { $engine | Add-Member NoteProperty lastPruneAt $Now }
    Write-HistoryJsonAtomic -Path $EngineStateFile -Value $engine
    return
}

[void](Add-MissingMarketBaselines -EngineState $engine -RetentionCutoff $retentionCutoff)
