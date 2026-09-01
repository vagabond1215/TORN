param(
    [ValidateRange(0,8)]
    [int]$Row = 0,
    [string]$MarketKey = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$SeedDir = Join-Path $ProjectRoot 'data\seed'
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$PreferenceFile = Join-Path $RuntimeDir 'preferences.json'
$StateKvFile = Join-Path $GeneratedDir 'state.kv'
$RuntimeObservationFile = Join-Path $RuntimeDir 'observations.jsonl'
$SeedObservationFile = Join-Path $SeedDir 'observations.jsonl'
$FocusMarketFile = Join-Path $RuntimeDir 'focus-market.kv'
$HistoryMaintenanceScript = Join-Path $PSScriptRoot 'MaintainObservationHistory.ps1'
$AtomicFileScript = Join-Path $PSScriptRoot 'AtomicFile.ps1'
if (-not (Test-Path -LiteralPath $AtomicFileScript)) { throw 'AtomicFile.ps1 is required for shared viewer reads.' }
. $AtomicFileScript

if (-not [string]::IsNullOrWhiteSpace($MarketKey) -and $MarketKey -notmatch '^[a-z0-9_]+:[1-9][0-9]*$') { throw 'MarketKey must be country:itemId.' }

function Write-ViewerFocusMarker {
    param([string]$Key)
    $normalized=([string]$Key).Trim().ToLowerInvariant()
    if ($normalized -notmatch '^[a-z0-9_]+:[1-9][0-9]*$') { return }
    $updatedAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $text=('MarketKey={0}{1}UpdatedAt={2}{1}' -f $normalized,[Environment]::NewLine,$updatedAt)
    Write-TravelAssistantAtomicText -Path $FocusMarketFile -Text $text
}

function Read-ViewerJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Read-TravelAssistantSharedText -Path $Path
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Read-ViewerStateKv {
    param([string]$Path)
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    $reader=$null
    try {
        $reader=Open-TravelAssistantSharedTextReader -Path $Path
        while (($line=$reader.ReadLine()) -ne $null) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $index = $line.IndexOf('=')
            if ($index -lt 1) { continue }
            $key = $line.Substring(0,$index).Trim([char]0xFEFF).Trim()
            $values[$key] = $line.Substring($index+1).Trim()
        }
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
    }
    return $values
}

function Get-ViewerProperty {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Format-ViewerMoney {
    param([long]$Value,[switch]$Signed)
    if ($Signed -and $Value -gt 0) { return ('+${0:N0}' -f $Value) }
    if ($Value -lt 0) { return ('-${0:N0}' -f [Math]::Abs($Value)) }
    return ('${0:N0}' -f $Value)
}

function Format-ViewerAge {
    param([long]$Seconds)
    if ($Seconds -lt 0) { $Seconds = 0 }
    if ($Seconds -lt 60) { return ('{0}s' -f $Seconds) }
    if ($Seconds -lt 3600) { return ('{0}m' -f [Math]::Floor($Seconds/60)) }
    return ('{0}h {1}m' -f [Math]::Floor($Seconds/3600),[Math]::Floor(($Seconds%3600)/60))
}

function Get-ViewerNiceAxisMax {
    param([double]$Maximum)
    if ($Maximum -le 0) { return 0.0 }
    $target = [Math]::Max(1.0,$Maximum*1.05)
    $power = [Math]::Floor([Math]::Log10($target))
    $magnitude = [Math]::Pow(10.0,$power)
    $normalized = $target/$magnitude
    $nice = if ($normalized -le 1.0) { 1.0 } elseif ($normalized -le 2.0) { 2.0 } elseif ($normalized -le 2.5) { 2.5 } elseif ($normalized -le 5.0) { 5.0 } else { 10.0 }
    return $nice*$magnitude
}

$settings = Read-ViewerJson (Join-Path $ConfigDir 'settings.example.json')
$engine = Read-ViewerJson $EngineStateFile
$countries = Read-ViewerJson (Join-Path $ConfigDir 'countries.json')
$preferences = Read-ViewerJson $PreferenceFile
$state = Read-ViewerStateKv $StateKvFile

if ($null -eq $engine -or -not $engine.PSObject.Properties['observedMarkets']) {
    [System.Windows.Forms.MessageBox]::Show('No collected foreign-market state is available yet. Run one normal Travel Assistant update first.','Travel Assistant - Item Viewer','OK','Information') | Out-Null
    exit 0
}

$windowHours = 8
$staleAfterSeconds = 300L
if ($null -ne $settings) {
    if ($settings.PSObject.Properties['graphWindowHours']) { $windowHours = [int]$settings.graphWindowHours }
    if ($settings.PSObject.Properties['staleAfterSeconds']) { $staleAfterSeconds = [long]$settings.staleAfterSeconds }
}
if ($windowHours -lt 1) { $windowHours = 1 }
if ($windowHours -gt 24) { $windowHours = 24 }
if ($staleAfterSeconds -lt 60) { $staleAfterSeconds = 60 }

$basisPercent = 100
if ($null -ne $preferences -and $preferences.PSObject.Properties['use95PercentMarketValue'] -and [bool]$preferences.use95PercentMarketValue) { $basisPercent = 95 }
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$cutoff = $now - ([long]$windowHours * 3600)

# Viewer opening is local-only, so it may safely repair migration/retention baselines
# before reading history. This never polls Prometheus/YATA/Torn and never invents
# an observed transition.
if (Test-Path -LiteralPath $HistoryMaintenanceScript) {
    try { & $HistoryMaintenanceScript -Phase PostUpdate -Now $now } catch { }
}

$countryNames = @{}
if ($null -ne $countries -and $countries.PSObject.Properties['countries']) {
    foreach ($country in @($countries.countries)) { $countryNames[[string]$country.id] = [string]$country.name }
}

function Get-ViewerItemName {
    param([int]$ItemId,[object]$Market)
    if ($engine.PSObject.Properties['itemMetadata']) {
        $metadata = Get-ViewerProperty $engine.itemMetadata ([string]$ItemId)
        if ($null -ne $metadata -and $metadata.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$metadata.name)) { return [string]$metadata.name }
    }
    if ($null -ne $Market -and $Market.PSObject.Properties['providerName'] -and -not [string]::IsNullOrWhiteSpace([string]$Market.providerName)) { return [string]$Market.providerName }
    return ('Item {0}' -f $ItemId)
}

function Get-ViewerCategory {
    param([int]$ItemId)
    if ($engine.PSObject.Properties['itemMetadata']) {
        $metadata = Get-ViewerProperty $engine.itemMetadata ([string]$ItemId)
        if ($null -ne $metadata -and $metadata.PSObject.Properties['category']) { return [string]$metadata.category }
    }
    return 'Unknown'
}

function Get-ViewerMarketValue {
    param([int]$ItemId)
    if (-not $engine.PSObject.Properties['resaleCache']) { return 0L }
    $cache = Get-ViewerProperty $engine.resaleCache ([string]$ItemId)
    if ($null -eq $cache) { return 0L }
    if ($cache.PSObject.Properties['average']) { return [long]$cache.average }
    return 0L
}

$marketRows = @()
foreach ($property in $engine.observedMarkets.PSObject.Properties) {
    $market = $property.Value
    if ($null -eq $market) { continue }
    if (($market.PSObject.Properties['catalogActive'] -and $market.catalogActive -eq $false) -or ($market.PSObject.Properties['catalogStatus'] -and [string]$market.catalogStatus -eq 'legacy_removed')) { continue }
    $countryId = [string](Get-ViewerProperty $market 'country')
    $itemId = [int](Get-ViewerProperty $market 'itemId')
    if ([string]::IsNullOrWhiteSpace($countryId) -or $itemId -le 0) { continue }
    $foreignPrice = [long](Get-ViewerProperty $market 'lastForeignPrice')
    $stock = [long](Get-ViewerProperty $market 'lastStock')
    $sourceTimestamp = [long](Get-ViewerProperty $market 'sourceTimestamp')
    $marketValue = Get-ViewerMarketValue -ItemId $itemId
    $sellBasis = 0L
    $profitKnown = $false
    $profitPerItem = 0L
    if ($marketValue -gt 0) {
        $sellBasis = [long][Math]::Floor($marketValue * ($basisPercent / 100.0))
        if ($foreignPrice -gt 0) {
            $profitPerItem = $sellBasis - $foreignPrice
            $profitKnown = $true
        }
    }
    $countryName = $countryId
    if ($countryNames.ContainsKey($countryId)) { $countryName = [string]$countryNames[$countryId] }
    $name = Get-ViewerItemName -ItemId $itemId -Market $market
    $category = Get-ViewerCategory -ItemId $itemId
    $marketRows += [pscustomobject]@{
        key = ($countryId + ':' + [string]$itemId)
        countryId = $countryId
        countryName = $countryName
        itemId = $itemId
        name = $name
        category = $category
        stock = $stock
        foreignPrice = $foreignPrice
        marketValue = $marketValue
        sellBasis = $sellBasis
        profitKnown = $profitKnown
        profitPerItem = $profitPerItem
        sourceTimestamp = $sourceTimestamp
        source = [string](Get-ViewerProperty $market 'source')
        market = $market
    }
}

$sortedRows = @($marketRows | Sort-Object @{Expression={ if ($_.profitKnown) { 0 } else { 1 } };Ascending=$true}, @{Expression='profitPerItem';Descending=$true}, name, countryName)
if ($sortedRows.Count -eq 0) {
    [System.Windows.Forms.MessageBox]::Show('No active foreign markets are available in the local catalog.','Travel Assistant - Item Viewer','OK','Information') | Out-Null
    exit 0
}

$history = @{}
$baseline = @{}
foreach ($path in @($SeedObservationFile,$RuntimeObservationFile)) {
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $reader=$null
    try {
        $reader=Open-TravelAssistantSharedTextReader -Path $path
        while (($line=$reader.ReadLine()) -ne $null) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row = $line | ConvertFrom-Json
                $timestamp = [long](Get-ViewerProperty $row 'timestamp')
                $country = [string](Get-ViewerProperty $row 'country')
                $itemId = [int](Get-ViewerProperty $row 'itemId')
                if ([string]::IsNullOrWhiteSpace($country) -or $itemId -le 0) { continue }
                $key = $country + ':' + [string]$itemId
                if ($timestamp -lt $cutoff) {
                    if (-not $baseline.ContainsKey($key) -or [long](Get-ViewerProperty $baseline[$key] 'timestamp') -lt $timestamp) { $baseline[$key] = $row }
                    continue
                }
                if (-not $history.ContainsKey($key)) { $history[$key] = @() }
                $history[$key] = @($history[$key] + $row)
            } catch { }
        }
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
    }
}

function Get-ViewerGraphRows {
    param([object]$Selection)
    $graphRows = @()
    $seen = New-Object 'System.Collections.Generic.HashSet[string]'
    $selectionKey = [string]$Selection.key
    if ($baseline.ContainsKey($selectionKey)) {
        $base = $baseline[$selectionKey]
        $graphRows += [pscustomobject]@{
            timestamp = $cutoff
            stock = [long](Get-ViewerProperty $base 'stock')
            foreignPrice = [long](Get-ViewerProperty $base 'foreignPrice')
            source = 'carry_forward'
        }
    }
    if ($history.ContainsKey($selectionKey)) {
        foreach ($row in @($history[$selectionKey] | Sort-Object timestamp)) {
            $key = ('{0}|{1}|{2}|{3}' -f [long](Get-ViewerProperty $row 'timestamp'),[long](Get-ViewerProperty $row 'stock'),[long](Get-ViewerProperty $row 'foreignPrice'),[string](Get-ViewerProperty $row 'source'))
            if ($seen.Add($key)) { $graphRows += $row }
        }
    }
    $snapshotTs = [long]$Selection.sourceTimestamp
    if ($snapshotTs -le 0 -and $Selection.market.PSObject.Properties['lastSeenAt']) { $snapshotTs = [long]$Selection.market.lastSeenAt }
    if ($snapshotTs -ge $cutoff) {
        $snapshotKey = ('{0}|{1}|{2}|{3}' -f $snapshotTs,[long]$Selection.stock,[long]$Selection.foreignPrice,[string]$Selection.source)
        if ($seen.Add($snapshotKey)) {
            $graphRows += [pscustomobject]@{ timestamp=$snapshotTs; stock=[long]$Selection.stock; foreignPrice=[long]$Selection.foreignPrice; source=[string]$Selection.source }
        }
    }
    return @($graphRows | Sort-Object timestamp)
}

function New-ViewerGraphBitmap {
    param([object]$Selection,[object[]]$Rows)
    $width = 780
    $height = 300
    $left = 52
    $right = 18
    $top = 22
    $bottom = 42
    $plotW = $width - $left - $right
    $plotH = $height - $top - $bottom
    $plotTop = $top + 2
    $plotBottom = $top + $plotH - 2
    $effectiveH = $plotBottom - $plotTop
    $windowStart = $now - ([long]$windowHours * 3600)

    $bitmap = New-Object System.Drawing.Bitmap($width,$height)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::FromArgb(24,27,31))

    $gridPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(58,64,73),1)
    $hourPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(82,88,98),1)
    $linePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(82,174,255),2)
    $restockPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(86,190,116),1)
    $selloutPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(224,90,90),1)
    $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(145,152,164))
    $emptyBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(222,226,232))
    $font = New-Object System.Drawing.Font('Segoe UI',8)
    $smallFont = New-Object System.Drawing.Font('Segoe UI',7)

    try {
        $hasRows = ($null -ne $Rows -and $Rows.Count -gt 0)
        $maxStock = 0.0
        if ($hasRows) { $maxStock = [double](($Rows | Measure-Object stock -Maximum).Maximum) }
        $axisMax = Get-ViewerNiceAxisMax $maxStock

        for ($i=0; $i -le 4; $i++) {
            $y = [single]($top + ($plotH * $i / 4.0))
            $g.DrawLine($gridPen,$left,$y,$left+$plotW,$y)
            if ($axisMax -gt 0) {
                $tickValue = [long][Math]::Round($axisMax * (1.0-($i/4.0)))
                $label = ('{0:N0}' -f $tickValue)
                $size = $g.MeasureString($label,$smallFont)
                $g.DrawString($label,$smallFont,$textBrush,[single]($left-$size.Width-6),[single]($y-7))
            }
        }
        if ($axisMax -le 0) {
            $g.DrawString('0',$smallFont,$textBrush,34,[single]($plotBottom-7))
        }

        $firstHour = [long]([Math]::Ceiling($windowStart / 3600.0) * 3600)
        for ($timestamp=$firstHour; $timestamp -le $now; $timestamp += 3600) {
            $x = [single]($left + (($timestamp-$windowStart) / [double]($windowHours*3600)) * $plotW)
            $g.DrawLine($hourPen,$x,$top,$x,$top+$plotH)
            $label = [DateTimeOffset]::FromUnixTimeSeconds($timestamp).ToLocalTime().ToString('HH:mm')
            $size = $g.MeasureString($label,$smallFont)
            $g.DrawString($label,$smallFont,$textBrush,[single]($x-($size.Width/2)),[single]($top+$plotH+8))
        }

        if (-not $hasRows) {
            $message = 'No retained observations inside this display window.'
            $size = $g.MeasureString($message,$font)
            $g.DrawString($message,$font,$emptyBrush,[single]($left+(($plotW-$size.Width)/2)),[single]($top+(($plotH-$size.Height)/2)))
            return $bitmap
        }

        $previous = $null
        foreach ($row in $Rows) {
            $timestamp = [long](Get-ViewerProperty $row 'timestamp')
            $stock = [long](Get-ViewerProperty $row 'stock')
            $x = [single]($left + (($timestamp-$windowStart) / [double]($windowHours*3600)) * $plotW)
            if ($x -lt $left) { $x = $left }
            if ($x -gt ($left+$plotW)) { $x = $left+$plotW }
            $y = if ($axisMax -gt 0) {
                [single]($plotBottom - (($stock/$axisMax)*$effectiveH))
            } else {
                [single]$plotBottom
            }
            if ($null -ne $previous) {
                $g.DrawLine($linePen,[single]$previous.x,[single]$previous.y,$x,[single]$previous.y)
                $g.DrawLine($linePen,$x,[single]$previous.y,$x,$y)
                if ([long]$previous.stock -eq 0 -and $stock -gt 0) { $g.DrawLine($restockPen,$x,$top,$x,$top+$plotH) }
                if ([long]$previous.stock -gt 0 -and $stock -eq 0) { $g.DrawLine($selloutPen,$x,$top,$x,$top+$plotH) }
            } else {
                $g.DrawEllipse($linePen,[single]($x-1),[single]($y-1),2,2)
            }
            $previous = [pscustomobject]@{x=$x;y=$y;stock=$stock}
        }
        if ($null -ne $previous -and [single]$previous.x -lt ($left+$plotW)) {
            $g.DrawLine($linePen,[single]$previous.x,[single]$previous.y,[single]($left+$plotW),[single]$previous.y)
        }

        if ($axisMax -le 0 -and $Rows.Count -ge 2) {
            $message = 'SOLD OUT THROUGHOUT VISIBLE RETAINED HISTORY'
            $size = $g.MeasureString($message,$font)
            $g.DrawString($message,$font,$textBrush,[single]($left+(($plotW-$size.Width)/2)),[single]($top+8))
        } elseif ($Rows.Count -eq 1) {
            $message = 'Only one retained observation; no earlier baseline is available.'
            $size = $g.MeasureString($message,$font)
            $g.DrawString($message,$font,$textBrush,[single]($left+(($plotW-$size.Width)/2)),[single]($top+8))
        }
        return $bitmap
    } finally {
        $gridPen.Dispose(); $hourPen.Dispose(); $linePen.Dispose(); $restockPen.Dispose(); $selloutPen.Dispose()
        $textBrush.Dispose(); $emptyBrush.Dispose(); $font.Dispose(); $smallFont.Dispose(); $g.Dispose()
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Travel Assistant - Item Viewer'
$form.Size = New-Object System.Drawing.Size(830,535)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(31,35,40)
$form.ForeColor = [System.Drawing.Color]::FromArgb(222,226,232)
$form.Font = New-Object System.Drawing.Font('Segoe UI',9)

$title = New-Object System.Windows.Forms.Label
$title.Text = '8-HOUR STOCK HISTORY'
$title.Location = New-Object System.Drawing.Point(16,12)
$title.Size = New-Object System.Drawing.Size(300,24)
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold',12)
$form.Controls.Add($title)

$viewerNote = New-Object System.Windows.Forms.Label
$viewerNote.Text = ('Display only: {0}h sliding window with 60-minute markers. Learning retention remains independent.' -f $windowHours)
$viewerNote.Location = New-Object System.Drawing.Point(326,15)
$viewerNote.Size = New-Object System.Drawing.Size(475,22)
$viewerNote.TextAlign = 'MiddleRight'
$viewerNote.ForeColor = [System.Drawing.Color]::FromArgb(145,152,164)
$form.Controls.Add($viewerNote)

$selector = New-Object System.Windows.Forms.ComboBox
$selector.Location = New-Object System.Drawing.Point(16,44)
$selector.Size = New-Object System.Drawing.Size(785,28)
$selector.DropDownStyle = 'DropDownList'
$form.Controls.Add($selector)

$metric = New-Object System.Windows.Forms.Label
$metric.Location = New-Object System.Drawing.Point(16,80)
$metric.Size = New-Object System.Drawing.Size(785,42)
$metric.Font = New-Object System.Drawing.Font('Segoe UI Semibold',9)
$form.Controls.Add($metric)

$subMetric = New-Object System.Windows.Forms.Label
$subMetric.Location = New-Object System.Drawing.Point(16,106)
$subMetric.Size = New-Object System.Drawing.Size(785,28)
$subMetric.ForeColor = [System.Drawing.Color]::FromArgb(145,152,164)
$form.Controls.Add($subMetric)

$picture = New-Object System.Windows.Forms.PictureBox
$picture.Location = New-Object System.Drawing.Point(16,138)
$picture.Size = New-Object System.Drawing.Size(780,300)
$picture.BackColor = [System.Drawing.Color]::FromArgb(24,27,31)
$picture.SizeMode = 'Normal'
$form.Controls.Add($picture)

$legend = New-Object System.Windows.Forms.Label
$legend.Text = 'Blue: stock level    Green: observed restock    Red: observed sellout    Dropdown is sorted by known profit/item.'
$legend.Location = New-Object System.Drawing.Point(16,447)
$legend.Size = New-Object System.Drawing.Size(785,24)
$legend.ForeColor = [System.Drawing.Color]::FromArgb(145,152,164)
$form.Controls.Add($legend)

$close = New-Object System.Windows.Forms.Button
$close.Text = 'Close'
$close.Location = New-Object System.Drawing.Point(716,465)
$close.Size = New-Object System.Drawing.Size(80,28)
$form.Controls.Add($close)
$close.Add_Click({ $form.Close() })

foreach ($entry in $sortedRows) {
    $profitText = 'MV learning'
    if ([bool]$entry.profitKnown) { $profitText = (Format-ViewerMoney -Value ([long]$entry.profitPerItem) -Signed) + '/ea' }
    $selector.Items.Add(('{0}  -  {1}  |  {2}  |  stock {3}' -f [string]$entry.name,[string]$entry.countryName,$profitText,[long]$entry.stock)) | Out-Null
}

$initialIndex = 0
if (-not [string]::IsNullOrWhiteSpace($MarketKey)) {
    for ($i=0; $i -lt $sortedRows.Count; $i++) {
        if ([string]$sortedRows[$i].key -eq $MarketKey) { $initialIndex = $i; break }
    }
} elseif ($Row -ge 1 -and $Row -le 8) {
    $opportunityKey = 'Opportunity' + $Row + 'Key'
    if ($state.ContainsKey($opportunityKey) -and -not [string]::IsNullOrWhiteSpace([string]$state[$opportunityKey])) {
        $wantedKey = [string]$state[$opportunityKey]
        for ($i=0; $i -lt $sortedRows.Count; $i++) {
            if ([string]$sortedRows[$i].key -eq $wantedKey) { $initialIndex = $i; break }
        }
    } else {
        $wantedName = ''
        $stateKey = 'OptimalItem' + $Row + 'Name'
        if ($state.ContainsKey($stateKey)) { $wantedName = [string]$state[$stateKey] }
        $wantedCountry = ''
        if ($engine.PSObject.Properties['optimizer'] -and $engine.optimizer.PSObject.Properties['selectedCountryId']) { $wantedCountry = [string]$engine.optimizer.selectedCountryId }
        if (-not [string]::IsNullOrWhiteSpace($wantedName)) {
            for ($i=0; $i -lt $sortedRows.Count; $i++) {
                if ([string]$sortedRows[$i].name -eq $wantedName -and ([string]::IsNullOrWhiteSpace($wantedCountry) -or [string]$sortedRows[$i].countryId -eq $wantedCountry)) { $initialIndex = $i; break }
            }
        }
    }
}

function Update-ViewerSelection {
    $index = $selector.SelectedIndex
    if ($index -lt 0 -or $index -ge $sortedRows.Count) { return }
    $selection = $sortedRows[$index]
    Write-ViewerFocusMarker -Key ([string]$selection.key)
    $rows = @(Get-ViewerGraphRows -Selection $selection)
    $profit = 'MV learning'
    if ([bool]$selection.profitKnown) { $profit = (Format-ViewerMoney -Value ([long]$selection.profitPerItem) -Signed) + '/ea @ ' + [string]$basisPercent + '% MV' }
    $mv = if ([long]$selection.marketValue -gt 0) { Format-ViewerMoney ([long]$selection.marketValue) } else { '-' }
    $foreign = if ([long]$selection.foreignPrice -gt 0) { Format-ViewerMoney ([long]$selection.foreignPrice) } else { '-' }
    $metric.Text = ('{0}  -  {1}    Stock: {2}    Foreign: {3}    MV: {4}    Spread: {5}' -f [string]$selection.name,[string]$selection.countryName,[long]$selection.stock,$foreign,$mv,$profit)
    $ageText = 'source age unknown'
    if ([long]$selection.sourceTimestamp -gt 0) {
        $age = [Math]::Max(0L,$now-[long]$selection.sourceTimestamp)
        $ageText = 'source ' + (Format-ViewerAge $age) + ' old'
        if ($age -gt $staleAfterSeconds) { $ageText += ' (STALE)' }
    }

    $changeCount = 0
    for ($i=1; $i -lt $rows.Count; $i++) {
        if ([long](Get-ViewerProperty $rows[$i-1] 'stock') -ne [long](Get-ViewerProperty $rows[$i] 'stock')) { $changeCount++ }
    }
    $spanText = 'no retained span'
    if ($rows.Count -gt 0) {
        $firstAt = [long](Get-ViewerProperty $rows[0] 'timestamp')
        $lastAt = [long](Get-ViewerProperty $rows[$rows.Count-1] 'timestamp')
        $spanText = ([DateTimeOffset]::FromUnixTimeSeconds($firstAt).ToLocalTime().ToString('HH:mm') + ' -> ' + [DateTimeOffset]::FromUnixTimeSeconds($lastAt).ToLocalTime().ToString('HH:mm'))
    }
    $subMetric.Text = ('{0} | {1} | {2} plotted point(s), {3} stock change(s) | {4}' -f [string]$selection.category,$ageText,$rows.Count,$changeCount,$spanText)

    $old = $picture.Image
    $picture.Image = New-ViewerGraphBitmap -Selection $selection -Rows $rows
    if ($null -ne $old) { $old.Dispose() }
}

$selector.Add_SelectedIndexChanged({ Update-ViewerSelection })
$selector.SelectedIndex = $initialIndex

# Keep detailed forecasting awake for the selected market while this viewer is
# actually open. The marker remains short-lived, so a closed viewer naturally
# returns the market to sleeping OOS mode without a separate cleanup race.
$focusTimer = New-Object System.Windows.Forms.Timer
$focusTimer.Interval = 60000
$focusTimer.Add_Tick({
    $index=$selector.SelectedIndex
    if ($index -ge 0 -and $index -lt $sortedRows.Count) {
        Write-ViewerFocusMarker -Key ([string]$sortedRows[$index].key)
    }
})
$focusTimer.Start()

$form.Add_FormClosed({
    $focusTimer.Stop()
    $focusTimer.Dispose()
    if ($null -ne $picture.Image) { $picture.Image.Dispose(); $picture.Image = $null }
})
$form.AcceptButton = $close
$form.CancelButton = $close
[void]$form.ShowDialog()
