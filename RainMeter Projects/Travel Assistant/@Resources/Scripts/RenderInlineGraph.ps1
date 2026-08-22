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
$HistoryMaintenanceScript = Join-Path $PSScriptRoot 'MaintainObservationHistory.ps1'

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
    [System.IO.File]::WriteAllLines($tmp,[string[]]$lines,(New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Read-MarketHistory {
    param([string]$Path,[string]$Country,[int]$ItemId)
    $rows = @()
    if (-not (Test-Path -LiteralPath $Path)) { return $rows }
    $countryNeedle = '"country":"' + $Country + '"'
    $itemPattern = '"itemId"\s*:\s*' + [regex]::Escape([string]$ItemId) + '(?=\s*[,}])'
    foreach ($line in [System.IO.File]::ReadLines($Path)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.IndexOf($countryNeedle,[System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
        if ($line -notmatch $itemPattern) { continue }
        try {
            $row = $line | ConvertFrom-Json
            $timestamp = [long](Get-InlineProperty $row 'timestamp')
            if ($timestamp -le 0) { continue }
            $rows += [pscustomobject]@{
                timestamp = $timestamp
                stock = [long](Get-InlineProperty $row 'stock')
                source = [string](Get-InlineProperty $row 'source')
            }
        } catch { }
    }
    return $rows
}

if (Test-Path -LiteralPath $HistoryMaintenanceScript) {
    try { & $HistoryMaintenanceScript -Phase PostUpdate | Out-Null } catch { }
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

# Runtime observations are the shared high-resolution collector database and are
# authoritative for the inline graph. Seed evidence is used only when this market
# has no retained runtime rows at all.
$allRows = @(Read-MarketHistory -Path $RuntimeObservationFile -Country $country -ItemId $itemId)
$historySource = 'runtime_observations'
if ($allRows.Count -eq 0) {
    $allRows = @(Read-MarketHistory -Path $SeedObservationFile -Country $country -ItemId $itemId)
    $historySource = 'seed_fallback'
}
$allRows = @($allRows | Sort-Object timestamp)

$rows = @()
$predecessor = @($allRows | Where-Object { [long]$_.timestamp -lt $cutoff } | Select-Object -Last 1)
if ($predecessor.Count -gt 0) {
    $rows += [pscustomobject]@{ timestamp=$cutoff; stock=[long]$predecessor[0].stock; source='carry_forward' }
}
$rows += @($allRows | Where-Object { [long]$_.timestamp -ge $cutoff -and [long]$_.timestamp -le ($now+60) })

# If old retention damage left no predecessor, carry an unchanged synthetic
# baseline only when the retained history does not contain a real transition.
if ($predecessor.Count -eq 0 -and $rows.Count -le 1) {
    $firstSeenAt = [long](Get-InlineProperty $market 'firstSeenAt')
    if ($firstSeenAt -gt 0 -and $firstSeenAt -lt $now) {
        $baselineAt = [Math]::Max($cutoff,$firstSeenAt)
        $baselineStock = [long](Get-InlineProperty $market 'lastStock')
        if ($rows.Count -eq 1) { $baselineStock = [long]$rows[0].stock }
        $rows = @([pscustomobject]@{ timestamp=$baselineAt; stock=$baselineStock; source='display_carry' }) + $rows
    }
}

# Always close the series with the same current market snapshot used by the card.
$currentStock = [long](Get-InlineProperty $market 'lastStock')
$currentTimestamp = [long](Get-InlineProperty $market 'sourceTimestamp')
if ($currentTimestamp -le 0) { $currentTimestamp = [long](Get-InlineProperty $market 'lastSeenAt') }
if ($currentTimestamp -le 0 -or $currentTimestamp -lt $cutoff -or $currentTimestamp -gt ($now+60)) { $currentTimestamp = $now }
$rows += [pscustomobject]@{ timestamp=$currentTimestamp; stock=$currentStock; source='current_snapshot' }

$dedupe = @{}
$normalized = @()
foreach ($row in @($rows | Sort-Object timestamp)) {
    $key = ('{0}|{1}' -f [long]$row.timestamp,[long]$row.stock)
    if ($dedupe.ContainsKey($key)) { continue }
    $dedupe[$key] = $true
    $normalized += $row
}
$rows = @($normalized | Sort-Object timestamp)

$maxStock = 0L
if ($rows.Count -gt 0) {
    $measure = $rows | Measure-Object stock -Maximum
    if ($null -ne $measure.Maximum) { $maxStock = [long]$measure.Maximum }
}
$scaleMax = if ($maxStock -gt 0) { [double]$maxStock } else { 1.0 }

Add-Type -AssemblyName System.Drawing
$width = 470
$height = 100
$plotLeft = 34.0
$plotRight = 464.0
$plotTop = 8.0
$plotBottom = 80.0
$plotWidth = $plotRight - $plotLeft
$plotHeight = $plotBottom - $plotTop

$bitmap = New-Object System.Drawing.Bitmap($width,$height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$graphics.Clear([System.Drawing.Color]::FromArgb(20,23,27))

$gridMajor = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(72,78,88),1)
$gridMinor = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(48,53,61),1)
$stockPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(82,174,255),2)
$restockPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(86,190,116),1)
$selloutPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(224,90,90),1)
$labelBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(170,178,190))
$labelFont = New-Object System.Drawing.Font('Segoe UI',7,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Point)

# Eight one-hour segments: seven internal vertical separators plus both boundaries.
for ($i=0; $i -le 8; $i++) {
    $x = [single]($plotLeft + ($plotWidth * $i / 8.0))
    $graphics.DrawLine($(if ($i -eq 0 -or $i -eq 8) { $gridMajor } else { $gridMinor }),$x,[single]$plotTop,$x,[single]$plotBottom)
}
for ($i=0; $i -le 3; $i++) {
    $y = [single]($plotTop + ($plotHeight * $i / 3.0))
    $graphics.DrawLine($(if ($i -eq 0 -or $i -eq 3) { $gridMajor } else { $gridMinor }),[single]$plotLeft,$y,[single]$plotRight,$y)
}

function Get-InlineX([long]$Timestamp) {
    $clamped = [Math]::Max($cutoff,[Math]::Min($now,$Timestamp))
    return [single]($plotLeft + ((($clamped-$cutoff) / [double]($windowHours*3600L)) * $plotWidth))
}
function Get-InlineY([long]$Stock) {
    if ($maxStock -le 0) { return [single]$plotBottom }
    return [single]($plotBottom - (($Stock / $scaleMax) * $plotHeight))
}

$previous = $null
foreach ($row in $rows) {
    $x = Get-InlineX ([long]$row.timestamp)
    $y = Get-InlineY ([long]$row.stock)
    if ($null -ne $previous) {
        $graphics.DrawLine($stockPen,[single]$previous.x,[single]$previous.y,$x,[single]$previous.y)
        $graphics.DrawLine($stockPen,$x,[single]$previous.y,$x,$y)
        if ([long]$previous.stock -eq 0 -and [long]$row.stock -gt 0) { $graphics.DrawLine($restockPen,$x,[single]$plotTop,$x,[single]$plotBottom) }
        if ([long]$previous.stock -gt 0 -and [long]$row.stock -eq 0) { $graphics.DrawLine($selloutPen,$x,[single]$plotTop,$x,[single]$plotBottom) }
    }
    $previous = [pscustomobject]@{ x=$x; y=$y; stock=[long]$row.stock }
}
if ($null -ne $previous -and [single]$previous.x -lt [single]$plotRight) {
    $graphics.DrawLine($stockPen,[single]$previous.x,[single]$previous.y,[single]$plotRight,[single]$previous.y)
}

$maxLabel = if ($maxStock -gt 0) { ('{0:N0}' -f $maxStock) } else { '0' }
$graphics.DrawString($maxLabel,$labelFont,$labelBrush,0,0)
$graphics.DrawString('0',$labelFont,$labelBrush,18,70)
$graphics.DrawString(('-{0}h' -f $windowHours),$labelFont,$labelBrush,[single]($plotLeft-8),82)
$graphics.DrawString('now',$labelFont,$labelBrush,[single]($plotRight-18),82)

$safeName = ($MarketKey -replace '[^a-zA-Z0-9_-]','_')
$imageFile = ('inline-graph-{0}-{1}.png' -f $safeName,$now)
$imagePath = Join-Path $GeneratedDir $imageFile
$tmpImage = $imagePath + '.tmp'
$bitmap.Save($tmpImage,[System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
$gridMajor.Dispose(); $gridMinor.Dispose(); $stockPen.Dispose(); $restockPen.Dispose(); $selloutPen.Dispose(); $labelBrush.Dispose(); $labelFont.Dispose()
Move-Item -LiteralPath $tmpImage -Destination $imagePath -Force

$changes = 0
for ($i=1; $i -lt $rows.Count; $i++) {
    if ([long]$rows[$i].stock -ne [long]$rows[$i-1].stock) { $changes++ }
}

$specPath = Join-Path $GeneratedDir ('inline-graph-' + $safeName + '.kv')
Write-InlineKvAtomic -Path $specPath -Values @{
    MarketKey = $MarketKey
    UpdatedAt = $now
    ImageFile = $imageFile
    HistorySource = $historySource
    MaxStock = $maxStock
    CurrentStock = $currentStock
    PointCount = $rows.Count
    ChangeCount = $changes
}

Get-ChildItem -LiteralPath $GeneratedDir -Filter 'inline-graph-*.png' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 24 |
    Remove-Item -Force -ErrorAction SilentlyContinue

exit 0
