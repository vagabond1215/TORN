param(
    [Parameter(Mandatory=$true)]
    [string]$MarketKey
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

if ($MarketKey -notmatch '^[a-z0-9_]+:[1-9][0-9]*$') { throw 'MarketKey must be country:itemId.' }

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$SeedDir = Join-Path $ProjectRoot 'data\seed'
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$RuntimeObservationFile = Join-Path $RuntimeDir 'observations.jsonl'
$SeedObservationFile = Join-Path $SeedDir 'observations.jsonl'
$SettingsFile = Join-Path $ConfigDir 'settings.example.json'

function Read-InlineJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Get-InlineProperty {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Write-InlineKvAtomic {
    param([string]$Path,[hashtable]$Values)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $tmp = $Path + '.tmp'
    $lines = @()
    foreach ($key in @($Values.Keys | Sort-Object)) {
        $value = ([string]$Values[$key]).Replace("`r",' ').Replace("`n",' ')
        $lines += ($key + '=' + $value)
    }
    [System.IO.File]::WriteAllLines($tmp,[string[]]$lines,[System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

$settings = Read-InlineJson $SettingsFile
$engine = Read-InlineJson $EngineStateFile
if ($null -eq $engine -or -not $engine.PSObject.Properties['observedMarkets']) { throw 'No observed market state is available.' }

$windowHours = 8
if ($null -ne $settings -and $settings.PSObject.Properties['graphWindowHours']) { $windowHours = [int]$settings.graphWindowHours }
$windowHours = [Math]::Max(1,[Math]::Min(24,$windowHours))

$parts = $MarketKey.Split(':')
$country = [string]$parts[0]
$itemId = [int]$parts[1]
$market = Get-InlineProperty $engine.observedMarkets $MarketKey
if ($null -eq $market) { throw ('Market not found in observedMarkets: ' + $MarketKey) }

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$cutoff = $now - ([long]$windowHours * 3600L)
$allRows = @()

foreach ($path in @($SeedObservationFile,$RuntimeObservationFile)) {
    if (-not (Test-Path -LiteralPath $path)) { continue }
    foreach ($line in [System.IO.File]::ReadLines($path)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $row = $line | ConvertFrom-Json
            if ([string](Get-InlineProperty $row 'country') -ne $country) { continue }
            if ([int](Get-InlineProperty $row 'itemId') -ne $itemId) { continue }
            $timestamp = [long](Get-InlineProperty $row 'timestamp')
            if ($timestamp -le 0) { continue }
            $allRows += [pscustomobject]@{
                timestamp = $timestamp
                stock = [long](Get-InlineProperty $row 'stock')
                source = [string](Get-InlineProperty $row 'source')
            }
        } catch { }
    }
}

$allRows = @($allRows | Sort-Object timestamp)
$rows = @()
$predecessor = @($allRows | Where-Object { [long]$_.timestamp -lt $cutoff } | Select-Object -Last 1)
if ($predecessor.Count -gt 0) {
    $rows += [pscustomobject]@{ timestamp=$cutoff; stock=[long]$predecessor[0].stock; source='carry_forward' }
}
$rows += @($allRows | Where-Object { [long]$_.timestamp -ge $cutoff })

# Repair the old bootstrap-only migration hole without inventing a transition.
if ($predecessor.Count -eq 0) {
    $syntheticOnly = $false
    if ($rows.Count -le 1) {
        $source = if ($rows.Count -eq 1) { [string]$rows[0].source } else { '' }
        if ($rows.Count -eq 0 -or $source -in @('history_bootstrap','history_repair_baseline','retention_baseline')) { $syntheticOnly = $true }
    }
    if ($syntheticOnly) {
        $firstSeenAt = [long](Get-InlineProperty $market 'firstSeenAt')
        if ($firstSeenAt -gt 0 -and $firstSeenAt -lt $now) {
            $baselineAt = [Math]::Max($cutoff,$firstSeenAt)
            $baselineStock = [long](Get-InlineProperty $market 'lastStock')
            if ($rows.Count -eq 1) { $baselineStock = [long]$rows[0].stock }
            $rows = @([pscustomobject]@{ timestamp=$baselineAt; stock=$baselineStock; source='display_carry' }) + $rows
        }
    }
}

$currentStock = [long](Get-InlineProperty $market 'lastStock')
$currentTimestamp = [long](Get-InlineProperty $market 'sourceTimestamp')
if ($currentTimestamp -le 0) { $currentTimestamp = [long](Get-InlineProperty $market 'lastSeenAt') }
if ($currentTimestamp -le 0) { $currentTimestamp = $now }
if ($currentTimestamp -lt $cutoff) { $currentTimestamp = $now }
$rows += [pscustomobject]@{ timestamp=$currentTimestamp; stock=$currentStock; source='current_snapshot' }

$dedupe = @{}
$normalized = @()
foreach ($row in @($rows | Sort-Object timestamp)) {
    $key = ('{0}|{1}' -f [long]$row.timestamp,[long]$row.stock)
    if ($dedupe.ContainsKey($key)) { continue }
    $dedupe[$key] = $true
    $normalized += $row
}
$rows = $normalized

$plotLeft = 44.0
$plotRight = 520.0
$plotTop = 76.0
$plotBottom = 150.0
$plotWidth = $plotRight - $plotLeft
$plotHeight = $plotBottom - $plotTop
$maxStock = 0L
if ($rows.Count -gt 0) {
    $measure = $rows | Measure-Object stock -Maximum
    if ($null -ne $measure.Maximum) { $maxStock = [long]$measure.Maximum }
}

# Literal Y-axis: the top axis value is the actual retained maximum.
$scaleMax = [double]$maxStock

function Get-InlineX([long]$Timestamp) {
    $clamped = [Math]::Max($cutoff,[Math]::Min($now,$Timestamp))
    return $plotLeft + ((($clamped-$cutoff) / [double]($windowHours*3600L)) * $plotWidth)
}
function Get-InlineY([long]$Stock) {
    if ($scaleMax -le 0) { return $plotBottom }
    return $plotBottom - (($Stock / $scaleMax) * $plotHeight)
}

$pathParts = @()
$previous = $null
foreach ($row in $rows) {
    $x = Get-InlineX ([long]$row.timestamp)
    $y = Get-InlineY ([long]$row.stock)
    if ($null -eq $previous) {
        $pathParts += ('{0:0.0},{1:0.0}' -f $x,$y)
    } else {
        $pathParts += ('LineTo {0:0.0},{1:0.0}' -f $x,[double]$previous.y)
        $pathParts += ('LineTo {0:0.0},{1:0.0}' -f $x,$y)
    }
    $previous = [pscustomobject]@{ x=$x; y=$y; stock=[long]$row.stock }
}
if ($null -ne $previous -and [double]$previous.x -lt $plotRight) {
    $pathParts += ('LineTo {0:0.0},{1:0.0}' -f $plotRight,[double]$previous.y)
}
if ($pathParts.Count -eq 0) {
    $pathParts = @(
        ('{0:0.0},{1:0.0}' -f $plotLeft,$plotBottom),
        ('LineTo {0:0.0},{1:0.0}' -f $plotRight,$plotBottom)
    )
}

$safeName = ($MarketKey -replace '[^a-zA-Z0-9_-]','_')
$output = Join-Path $GeneratedDir ('inline-graph-' + $safeName + '.kv')
Write-InlineKvAtomic -Path $output -Values @{
    MarketKey = $MarketKey
    UpdatedAt = $now
    GraphPath = ($pathParts -join ' | ')
    MaxStock = $maxStock
}

# Keep generated inline graph specs bounded.
Get-ChildItem -LiteralPath $GeneratedDir -Filter 'inline-graph-*.kv' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 16 |
    Remove-Item -Force -ErrorAction SilentlyContinue

exit 0
