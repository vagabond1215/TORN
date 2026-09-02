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
$FocusMarketFile = Join-Path $RuntimeDir 'focus-market.kv'
$SettingsFile = Join-Path $ConfigDir 'settings.example.json'
$AtomicFileScript = Join-Path $PSScriptRoot 'AtomicFile.ps1'
if (-not (Test-Path -LiteralPath $AtomicFileScript)) { throw 'AtomicFile.ps1 is required for shared graph history reads.' }
. $AtomicFileScript

$focusUpdatedAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$focusText=('MarketKey={0}{1}UpdatedAt={2}{1}' -f $MarketKey,[Environment]::NewLine,$focusUpdatedAt)
Write-TravelAssistantAtomicText -Path $FocusMarketFile -Text $focusText

function Read-InlineJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Read-TravelAssistantSharedText -Path $Path
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
    $reader = $null
    try {
        $reader = Open-TravelAssistantSharedTextReader -Path $Path
        while (($line = $reader.ReadLine()) -ne $null) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line.IndexOf($countryNeedle,[System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            if ($line -notmatch $itemPattern) { continue }
            try {
                $row = $line | ConvertFrom-Json
                $timestamp = [long](Get-InlineProperty $row 'timestamp')
                if ($timestamp -le 0) { continue }
                $source = [string](Get-InlineProperty $row 'source')
                # Older migration builds wrote current stock backward through time as
                # history_bootstrap/history_repair_baseline. Those are not observations
                # and must never be rendered as historical truth.
                if ($source -in @('history_bootstrap','history_repair_baseline')) { continue }
                $rows += [pscustomobject]@{
                    timestamp = $timestamp
                    stock = [long](Get-InlineProperty $row 'stock')
                    source = $source
                }
            } catch { }
        }
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
    }
    return $rows
}

function Compress-StockHistory {
    param([object[]]$Rows)
    $compressed = @()
    $previousStock = $null
    foreach ($row in @($Rows | Sort-Object timestamp)) {
        $stock = [long]$row.stock
        if ($null -eq $previousStock -or [long]$previousStock -ne $stock) {
            $compressed += $row
            $previousStock = $stock
        }
    }
    return @($compressed)
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

# Runtime observations are the shared high-resolution ShadowCollector database and
# are authoritative. Seed evidence is used only if this market has no real retained
# runtime rows after synthetic migration rows are excluded.
$allRows = @(Read-MarketHistory -Path $RuntimeObservationFile -Country $country -ItemId $itemId)
$historySource = 'runtime_observations'
if ($allRows.Count -eq 0) {
    $allRows = @(Read-MarketHistory -Path $SeedObservationFile -Country $country -ItemId $itemId)
    $historySource = 'seed_fallback'
}
$allRows = @(Compress-StockHistory -Rows $allRows)

$rows = @()
$predecessor = @($allRows | Where-Object { [long]$_.timestamp -lt $cutoff } | Select-Object -Last 1)
if ($predecessor.Count -gt 0) {
    $rows += [pscustomobject]@{ timestamp=$cutoff; stock=[long]$predecessor[0].stock; source='carry_forward' }
}
$rows += @($allRows | Where-Object { [long]$_.timestamp -ge $cutoff -and [long]$_.timestamp -le ($now+60) })
$rows = @(Compress-StockHistory -Rows $rows)

# Never paint current stock backward through an interval with no retained sample.
# If there is no predecessor, the left side of the graph remains genuinely unknown.
$currentStock = [long](Get-InlineProperty $market 'lastStock')
$currentTimestamp = [long](Get-InlineProperty $market 'sourceTimestamp')
if ($currentTimestamp -le 0) { $currentTimestamp = [long](Get-InlineProperty $market 'lastSeenAt') }
if ($currentTimestamp -le 0 -or $currentTimestamp -lt $cutoff -or $currentTimestamp -gt ($now+60)) { $currentTimestamp = $now }
$rows += [pscustomobject]@{ timestamp=$currentTimestamp; stock=$currentStock; source='current_snapshot' }
$rows = @(Compress-StockHistory -Rows $rows)

$maxStock = 0L
if ($rows.Count -gt 0) {
    $measure = $rows | Measure-Object stock -Maximum
    if ($null -ne $measure.Maximum) { $maxStock = [long]$measure.Maximum }
}
$scaleMax = if ($maxStock -gt 0) { [double]$maxStock } else { 1.0 }

Add-Type -AssemblyName System.Drawing
# The image now nearly fills the 536px card width and is exactly 25% taller than
# the previous 100px renderer. CardTweaks reserves the matching 125px display area.
$width = 528
$height = 125
$plotLeft = 34.0
$plotRight = 522.0
$plotTop = 8.0
$plotBottom = 98.0
$plotWidth = $plotRight - $plotLeft
$plotHeight = $plotBottom - $plotTop

$bitmap = New-Object System.Drawing.Bitmap($width,$height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$graphics.Clear([System.Drawing.Color]::FromArgb(0,0,0))

$gridMajor = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(72,78,88),1)
$gridMinor = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(48,53,61),1)
$stockPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(126,190,73),2)
$restockPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0,71,171),1)
$selloutPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,117,24),1)
$labelBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(170,178,190))
$labelFont = New-Object System.Drawing.Font('Segoe UI',7,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Point)

# Eight one-hour segments: seven internal vertical separators plus both boundaries.
for ($i=0; $i -le 8; $i++) {
    $x = [single]($plotLeft + ($plotWidth * $i / 8.0))
    $pen = if ($i -eq 0 -or $i -eq 8) { $gridMajor } else { $gridMinor }
    $graphics.DrawLine($pen,$x,[single]$plotTop,$x,[single]$plotBottom)
}
for ($i=0; $i -le 3; $i++) {
    $y = [single]($plotTop + ($plotHeight * $i / 3.0))
    $pen = if ($i -eq 0 -or $i -eq 3) { $gridMajor } else { $gridMinor }
    $graphics.DrawLine($pen,[single]$plotLeft,$y,[single]$plotRight,$y)
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
$graphics.DrawString('0',$labelFont,$labelBrush,18,88)
$graphics.DrawString(('-{0}h' -f $windowHours),$labelFont,$labelBrush,[single]($plotLeft-8),104)
$graphics.DrawString('now',$labelFont,$labelBrush,[single]($plotRight-18),104)

$safeName = ($MarketKey -replace '[^a-zA-Z0-9_-]','_')
$imageFile = ('inline-graph-{0}-{1}.png' -f $safeName,$now)
$imagePath = Join-Path $GeneratedDir $imageFile
$stableImagePath = Join-Path $GeneratedDir ('inline-graph-' + $safeName + '.png')
$tmpImage = $imagePath + '.tmp'
$bitmap.Save($tmpImage,[System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
$gridMajor.Dispose(); $gridMinor.Dispose(); $stockPen.Dispose(); $restockPen.Dispose(); $selloutPen.Dispose(); $labelBrush.Dispose(); $labelFont.Dispose()
Move-Item -LiteralPath $tmpImage -Destination $imagePath -Force
Copy-Item -LiteralPath $imagePath -Destination $stableImagePath -Force

$changes = 0
for ($i=1; $i -lt $rows.Count; $i++) {
    if ([long]$rows[$i].stock -ne [long]$rows[$i-1].stock) { $changes++ }
}
$earliestTimestamp = if ($rows.Count -gt 0) { [long]$rows[0].timestamp } else { 0L }
$latestTimestamp = if ($rows.Count -gt 0) { [long]$rows[$rows.Count-1].timestamp } else { 0L }
$unknownBefore = if ($predecessor.Count -gt 0) { 0L } else { $earliestTimestamp }

$specPath = Join-Path $GeneratedDir ('inline-graph-' + $safeName + '.kv')
Write-InlineKvAtomic -Path $specPath -Values @{
    MarketKey = $MarketKey
    UpdatedAt = $now
    ImageFile = $imageFile
    StableImageFile = ('inline-graph-' + $safeName + '.png')
    HistorySource = $historySource
    MaxStock = $maxStock
    CurrentStock = $currentStock
    PointCount = $rows.Count
    ChangeCount = $changes
    EarliestTimestamp = $earliestTimestamp
    LatestTimestamp = $latestTimestamp
    UnknownBeforeTimestamp = $unknownBefore
    WindowStartTimestamp = $cutoff
}

Get-ChildItem -LiteralPath $GeneratedDir -Filter 'inline-graph-*-*.png' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 24 |
    Remove-Item -Force -ErrorAction SilentlyContinue

exit 0