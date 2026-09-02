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
$ChanceHistoryFile = Join-Path $RuntimeDir 'chance-history.jsonl'
$ResolvedArrivalHistoryFile = Join-Path $RuntimeDir 'resolved-arrival-history.jsonl'
$StateKvFile = Join-Path $GeneratedDir 'state.kv'
$FocusMarketFile = Join-Path $RuntimeDir 'focus-market.kv'
$SettingsFile = Join-Path $ConfigDir 'settings.example.json'
$AtomicFileScript = Join-Path $PSScriptRoot 'AtomicFile.ps1'
if (-not (Test-Path -LiteralPath $AtomicFileScript)) { throw 'AtomicFile.ps1 is required for shared graph history reads.' }
. $AtomicFileScript

$focusUpdatedAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$focusText=('MarketKey={0}{1}UpdatedAt={2}{1}' -f $MarketKey,[Environment]::NewLine,$focusUpdatedAt)
Write-TravelAssistantAtomicText -Path $FocusMarketFile -Text $focusText

function Read-InlineKv {
    param([string]$Path)
    $values=@{}
    if(-not(Test-Path -LiteralPath $Path)){return $values}
    $reader=$null
    try{
        $reader=Open-TravelAssistantSharedTextReader -Path $Path
        while(($line=$reader.ReadLine()) -ne $null){
            if([string]::IsNullOrWhiteSpace($line)){continue}
            $eq=$line.IndexOf('=')
            if($eq -lt 1){continue}
            $values[$line.Substring(0,$eq).Trim([char]0xFEFF).Trim()]=$line.Substring($eq+1).Trim()
        }
    }finally{
        if($null -ne $reader){$reader.Dispose()}
    }
    return $values
}

function Get-InlineTravelSeconds {
    param([hashtable]$State,[string]$Country)
    $countryId=([string]$Country).Trim().ToLowerInvariant()
    $key=if($countryId -eq 'united_kingdom'){'UKTravelSeconds'}elseif($countryId -eq 'japan'){'JPTravelSeconds'}else{$countryId.ToUpperInvariant()+'TravelSeconds'}
    $value=0L
    if($State.ContainsKey($key)){[void][long]::TryParse([string]$State[$key],[ref]$value)}
    return [Math]::Max(0L,$value)
}

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

function Read-MarketChanceHistory {
    param([string]$Path,[string]$Key,[long]$Cutoff,[long]$MaximumTimestamp)
    $rows=@()
    if (-not (Test-Path -LiteralPath $Path)) { return $rows }
    $needle='"marketKey":"'+$Key+'"'
    $reader=$null
    try {
        $reader=Open-TravelAssistantSharedTextReader -Path $Path
        while (($line=$reader.ReadLine()) -ne $null) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line.IndexOf($needle,[System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            try { $row=$line | ConvertFrom-Json } catch { continue }
            $timestamp=[long](Get-InlineProperty $row 'timestamp')
            $probability=[double](Get-InlineProperty $row 'probability')
            if ($timestamp -lt $Cutoff -or $timestamp -gt $MaximumTimestamp) { continue }
            if ($probability -lt 0.0 -or $probability -gt 1.0) { continue }
            $rows += [pscustomobject]@{
                timestamp=$timestamp
                probability=$probability
                source=[string](Get-InlineProperty $row 'source')
            }
        }
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
    }
    return @($rows | Sort-Object timestamp)
}

function Read-MarketResolvedArrivalHistory {
    param([string]$Path,[string]$Key,[long]$Cutoff,[long]$MaximumForecastAt)
    $rows=@()
    if(-not(Test-Path -LiteralPath $Path)){return $rows}
    $needle='"marketKey":"'+$Key+'"'
    $reader=$null
    try{
        $reader=Open-TravelAssistantSharedTextReader -Path $Path
        while(($line=$reader.ReadLine()) -ne $null){
            if([string]::IsNullOrWhiteSpace($line)){continue}
            if($line.IndexOf($needle,[System.StringComparison]::OrdinalIgnoreCase) -lt 0){continue}
            try{$row=$line|ConvertFrom-Json}catch{continue}
            $forecastAt=[long](Get-InlineProperty $row 'forecastAt')
            $probability=[double](Get-InlineProperty $row 'predictedProbability')
            $actual=[int](Get-InlineProperty $row 'actualAnyStock')
            if($forecastAt -lt $Cutoff -or $forecastAt -gt $MaximumForecastAt){continue}
            if($probability -lt 0.0 -or $probability -gt 1.0 -or $actual -notin @(0,1)){continue}
            $rows += [pscustomobject]@{
                forecastAt=$forecastAt
                predictedProbability=$probability
                actualAnyStock=$actual
                brier=[double](Get-InlineProperty $row 'brier')
                source=[string](Get-InlineProperty $row 'source')
            }
        }
    }finally{
        if($null -ne $reader){$reader.Dispose()}
    }
    return @($rows|Sort-Object forecastAt)
}

function Get-FlightShiftedRealizedHistory {
    param([object[]]$StockRows,[long]$FlightSeconds,[long]$Cutoff,[long]$NowEpoch)
    if($FlightSeconds -le 0){return @()}
    $actualStart=$Cutoff+$FlightSeconds
    $actualEnd=$NowEpoch
    if($actualStart -gt $actualEnd){return @()}

    $ordered=@($StockRows|Sort-Object timestamp)
    $result=New-Object System.Collections.Generic.List[object]
    $predecessor=@($ordered|Where-Object{[long]$_.timestamp -lt $actualStart}|Select-Object -Last 1)
    if($predecessor.Count -gt 0){
        $result.Add([pscustomobject]@{
            timestamp=[long]$Cutoff
            actualAnyStock=$(if([long]$predecessor[0].stock -gt 0){1}else{0})
            source='flight_shifted_observed_stock'
        })
    }
    foreach($row in @($ordered|Where-Object{[long]$_.timestamp -ge $actualStart -and [long]$_.timestamp -le $actualEnd})){
        $departureAt=[long]$row.timestamp-$FlightSeconds
        if($departureAt -lt $Cutoff -or $departureAt -gt $NowEpoch){continue}
        $result.Add([pscustomobject]@{
            timestamp=$departureAt
            actualAnyStock=$(if([long]$row.stock -gt 0){1}else{0})
            source='flight_shifted_observed_stock'
        })
    }
    $compressed=New-Object System.Collections.Generic.List[object]
    $previous=$null
    foreach($row in @($result.ToArray()|Sort-Object timestamp)){
        $actual=[int]$row.actualAnyStock
        if($null -eq $previous -or [int]$previous -ne $actual){
            $compressed.Add($row)
            $previous=$actual
        }
    }
    return $compressed.ToArray()
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
$state = Read-InlineKv $StateKvFile
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

# Chance history is forecast-only and intentionally separate from retained stock
# observations. It is sampled by the normal updater and rendered on an independent
# fixed 0..100% scale.
$chanceRows=@(Read-MarketChanceHistory -Path $ChanceHistoryFile -Key $MarketKey -Cutoff $cutoff -MaximumTimestamp ($now+60L))
$resolvedRows=@(Read-MarketResolvedArrivalHistory -Path $ResolvedArrivalHistoryFile -Key $MarketKey -Cutoff $cutoff -MaximumForecastAt $now)
$flightSeconds=Get-InlineTravelSeconds -State $state -Country $country
$realizedRows=@(Get-FlightShiftedRealizedHistory -StockRows $allRows -FlightSeconds $flightSeconds -Cutoff $cutoff -NowEpoch $now)

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
$chancePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(105,200,235),1.5)
$realizedPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(90,205,205,205),1)
$realizedPen.DashStyle=[System.Drawing.Drawing2D.DashStyle]::Dot
$errorPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(85,225,225,225),1)
$hitBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(115,190,230,95))
$missBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140,255,117,24))
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
function Get-ChanceY([double]$Probability) {
    $p=[Math]::Max(0.0,[Math]::Min(1.0,$Probability))
    return [single]($plotBottom - ($p * $plotHeight))
}

$previous = $null
foreach ($row in $rows) {
    $x = Get-InlineX ([long]$row.timestamp)
    $y = Get-InlineY ([long]$row.stock)
    if ($null -ne $previous) {
        $graphics.DrawLine($stockPen,[single]$previous.x,[single]$previous.y,$x,[single]$previous.y)
        $graphics.DrawLine($stockPen,$x,[single]$previous.y,$x,$y)
        # Restock/sellout transitions are event ticks, not stock magnitude. Draw
        # them in the gutter below the X axis so they never obscure the stock trace.
        $markerTop=[single]($plotBottom+2)
        $markerBottom=[single]($plotBottom+8)
        if ([long]$previous.stock -eq 0 -and [long]$row.stock -gt 0) { $graphics.DrawLine($restockPen,$x,$markerTop,$x,$markerBottom) }
        if ([long]$previous.stock -gt 0 -and [long]$row.stock -eq 0) { $graphics.DrawLine($selloutPen,$x,$markerTop,$x,$markerBottom) }
    }
    $previous = [pscustomobject]@{ x=$x; y=$y; stock=[long]$row.stock }
}
if ($null -ne $previous -and [single]$previous.x -lt [single]$plotRight) {
    $graphics.DrawLine($stockPen,[single]$previous.x,[single]$previous.y,[single]$plotRight,[single]$previous.y)
}

# Hindsight truth uses the same implicit 0..100% scale but is not a forecast.
# Shift the retained stock waveform left by one configured flight duration:
# a top segment means a departure at that X-time actually would have hit stock;
# a bottom segment means it would have missed. Polling uncertainty remains the
# same as in the source stock graph, so this is a realized observation proxy.
$previousRealized=$null
foreach($row in $realizedRows){
    $x=Get-InlineX ([long]$row.timestamp)
    $y=Get-ChanceY ([double][int]$row.actualAnyStock)
    if($null -ne $previousRealized){
        $graphics.DrawLine($realizedPen,[single]$previousRealized.x,[single]$previousRealized.y,$x,[single]$previousRealized.y)
        $graphics.DrawLine($realizedPen,$x,[single]$previousRealized.y,$x,$y)
    }
    $previousRealized=[pscustomobject]@{x=$x;y=$y;actual=[int]$row.actualAnyStock;timestamp=[long]$row.timestamp}
}
$realizedThrough=$now-$flightSeconds
if($null -ne $previousRealized -and $realizedThrough -ge $cutoff){
    $endX=Get-InlineX ([Math]::Min($now,$realizedThrough))
    if($endX -gt [single]$previousRealized.x){
        $graphics.DrawLine($realizedPen,[single]$previousRealized.x,[single]$previousRealized.y,$endX,[single]$previousRealized.y)
    }
}

# Strictly resolved forecasts use confirmed calibration truth. Draw a faint error
# whisker from the frozen probability to the binary outcome and a small endpoint.
foreach($row in $resolvedRows){
    $x=Get-InlineX ([long]$row.forecastAt)
    $predictedY=Get-ChanceY ([double]$row.predictedProbability)
    $actualY=Get-ChanceY ([double][int]$row.actualAnyStock)
    $graphics.DrawLine($errorPen,$x,$predictedY,$x,$actualY)
    $brush=if([int]$row.actualAnyStock -eq 1){$hitBrush}else{$missBrush}
    $graphics.FillEllipse($brush,[single]($x-1.75),[single]($actualY-1.75),[single]3.5,[single]3.5)
}

# Draw live hit probability independently of stock scale: 0% sits on the stock
# X-axis and 100% sits at the plot top. Do not bridge missing forecast intervals.
$previousChance=$null
foreach ($row in $chanceRows) {
    $x=Get-InlineX ([long]$row.timestamp)
    $y=Get-ChanceY ([double]$row.probability)
    if ($null -ne $previousChance) {
        $gap=[long]$row.timestamp-[long]$previousChance.timestamp
        if ($gap -gt 0 -and $gap -le 300L) {
            $graphics.DrawLine($chancePen,[single]$previousChance.x,[single]$previousChance.y,$x,$y)
        }
    }
    $previousChance=[pscustomobject]@{x=$x;y=$y;timestamp=[long]$row.timestamp;probability=[double]$row.probability}
}
if ($null -ne $previousChance -and ($now-[long]$previousChance.timestamp) -le 180L -and [single]$previousChance.x -lt [single]$plotRight) {
    $graphics.DrawLine($chancePen,[single]$previousChance.x,[single]$previousChance.y,[single]$plotRight,[single]$previousChance.y)
}

$maxLabel = if ($maxStock -gt 0) { ('{0:N0}' -f $maxStock) } else { '0' }
$graphics.DrawString($maxLabel,$labelFont,$labelBrush,0,0)
$graphics.DrawString('0',$labelFont,$labelBrush,18,88)
$graphics.DrawString(('-{0}h' -f $windowHours),$labelFont,$labelBrush,[single]($plotLeft-8),110)
$graphics.DrawString('now',$labelFont,$labelBrush,[single]($plotRight-18),110)

$safeName = ($MarketKey -replace '[^a-zA-Z0-9_-]','_')
$imageFile = ('inline-graph-{0}-{1}.png' -f $safeName,$now)
$imagePath = Join-Path $GeneratedDir $imageFile
$stableImagePath = Join-Path $GeneratedDir ('inline-graph-' + $safeName + '.png')
$tmpImage = $imagePath + '.tmp'
$bitmap.Save($tmpImage,[System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
$gridMajor.Dispose(); $gridMinor.Dispose(); $stockPen.Dispose(); $chancePen.Dispose(); $realizedPen.Dispose(); $errorPen.Dispose(); $hitBrush.Dispose(); $missBrush.Dispose(); $restockPen.Dispose(); $selloutPen.Dispose(); $labelBrush.Dispose(); $labelFont.Dispose()
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
    ChancePointCount = $chanceRows.Count
    CurrentChancePercent = $(if($chanceRows.Count -gt 0){[Math]::Round(100.0*[double]$chanceRows[$chanceRows.Count-1].probability,1)}else{-1})
    FlightSeconds = $flightSeconds
    RealizedHitProxyPointCount = $realizedRows.Count
    ResolvedForecastPointCount = $resolvedRows.Count
    ResolvedBrierScore = $(if($resolvedRows.Count -gt 0){[Math]::Round((($resolvedRows|Measure-Object brier -Average).Average),4)}else{-1})
    ResolvedObservedHitRate = $(if($resolvedRows.Count -gt 0){[Math]::Round((($resolvedRows|Measure-Object actualAnyStock -Average).Average),4)}else{-1})
    ResolvedMeanPredictedChance = $(if($resolvedRows.Count -gt 0){[Math]::Round((($resolvedRows|Measure-Object predictedProbability -Average).Average),4)}else{-1})
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