$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$settingsPath = Join-Path $ProjectRoot 'config\settings.example.json'
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$rendererPath = Join-Path $ProjectRoot '@Resources\Scripts\RenderInlineGraph.ps1'
$stateReaderPath = Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
$hitboxPath = Join-Path $ProjectRoot '@Resources\Includes\InlineGraphHitboxes.inc'
$settingsWindowPath = Join-Path $ProjectRoot '@Resources\Scripts\OpenSettings.ps1'

$failures = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:failures.Add($Message) }

$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
if ([int]$settings.graphWindowHours -ne 8) { Fail 'Visible graph window must be 8 hours.' }
if ([int]$settings.highResolutionRetentionHours -lt [int]$settings.graphWindowHours) { Fail 'High-resolution retention must not be shorter than the visible graph window.' }
if ([int]$settings.highResolutionRetentionHours -ne 48) { Fail 'High-resolution learning retention should remain 48 hours.' }
if ([int]$settings.cycleRetentionDays -ne 90) { Fail 'Completed-cycle learning retention should remain 90 days.' }
if ([int]$settings.staleAfterSeconds -ne 300) { Fail 'Live-provider stale threshold should remain 300 seconds.' }
if($null -eq $settings.PSObject.Properties['graphVisuals']){
    Fail 'settings.example.json must define graphVisuals defaults.'
}else{
    foreach($name in @('showGrid','showTransitions','showChance','showHindsightWindows','showAccuracyMarkers','showTooltips')){
        if($null -eq $settings.graphVisuals.PSObject.Properties[$name]){Fail "Graph visual default missing '$name'."}
    }
}

$renderer = Get-Content -LiteralPath $rendererPath -Raw
if(-not$renderer.Contains('return [single]($plotBottom - ($p * $plotHeight))')){Fail 'Chance/validation overlays must use an independent fixed 0..100% vertical scale.'}
if($renderer -match '(?i)Chance.*DrawString|DrawString.*Chance'){Fail 'Chance overlay must not add a second labeled Y axis.'}

foreach($token in @(
    '$graphics.Clear([System.Drawing.Color]::FromArgb(0,0,0))',
    'FromArgb(126,190,73),2',
    'FromArgb(0,71,171),1',
    'FromArgb(255,117,24),1',
    'FromArgb(105,200,235),1.5',
    'FromArgb(32,165,165,235)',
    'FromArgb(155,165,165,235),1',
    'Get-RealizedDepartureWindows',
    '$graphics.FillRectangle($hindsightBandBrush',
    'HindsightWindowCount',
    'HoverCount',
    "text=('Restocked: '",
    "text=('OoS: '",
    "text=('Hindsight departure window: '",
    "text=('Actual hindsight window opened: '",
    "text=('Actual hindsight window closed: '",
    'Get-FlightShiftedRealizedHistory',
    '$realizedThrough=$now-$flightSeconds',
    'Read-MarketResolvedArrivalHistory',
    '$graphics.DrawLine($errorPen,$x,$predictedY,$x,$actualY)',
    "text=('Forecast '+([Math]::Round(100.0*$predicted,1))+'% | Actual '",
    "Get-InlineSettingBool -Base $settings -Local $localSettings -Name 'showGrid'",
    "Get-InlineSettingBool -Base $settings -Local $localSettings -Name 'showTransitions'",
    "Get-InlineSettingBool -Base $settings -Local $localSettings -Name 'showChance'",
    "Get-InlineSettingBool -Base $settings -Local $localSettings -Name 'showHindsightWindows'",
    "Get-InlineSettingBool -Base $settings -Local $localSettings -Name 'showAccuracyMarkers'",
    "Get-InlineSettingBool -Base $settings -Local $localSettings -Name 'showTooltips'",
    'ChancePointCount',
    'RealizedHitProxyPointCount',
    'ResolvedForecastPointCount',
    'ResolvedBrierScore',
    '$markerTop=[single]($plotBottom+2)',
    '$markerBottom=[single]($plotBottom+8)',
    '$graphics.DrawString((''-{0}h'' -f $windowHours),$labelFont,$labelBrush,[single]($plotLeft-8),110)',
    '$graphics.DrawString(''now'',$labelFont,$labelBrush,[single]($plotRight-18),110)'
)){
    if(-not$renderer.Contains($token)){Fail "Inline graph palette/interaction contract missing '$token'."}
}

foreach($retired in @(
    '$chanceBandThreshold=0.50',
    'Get-ChanceWindows',
    'Get-ChanceThresholdCrossing',
    'ChanceWindowThreshold',
    '$chanceBandBrush',
    '$chanceBoundaryPen',
    '$realizedPen.DashStyle'
)){
    if($renderer.Contains($retired)){Fail "Retired 50%-threshold/dotted hindsight graph primitive is still present: $retired"}
}
if(-not$renderer.Contains('# Periwinkle is hindsight truth, not another forecast encoding.')){
    Fail 'Periwinkle must represent flight-shifted realized departure windows, never a thresholded copy of cyan.'
}
if(-not$renderer.Contains('# No 50% display suppression is permitted; missing evidence remains a gap.')){
    Fail 'Cyan chance history must remain continuous across all recorded probabilities without a 50% display threshold.'
}

foreach($forbidden in @(
    '$graphics.DrawLine($restockPen,$x,[single]$plotTop,$x,[single]$plotBottom)',
    '$graphics.DrawLine($selloutPen,$x,[single]$plotTop,$x,[single]$plotBottom)'
)){
    if($renderer.Contains($forbidden)){Fail "Transition markers must stay below the X axis; found retired full-plot marker '$forbidden'."}
}

if(-not(Test-Path -LiteralPath $settingsWindowPath)){
    Fail 'OpenSettings.ps1 is required for graph visual toggles.'
}else{
    $settingsWindow=Get-Content -LiteralPath $settingsWindowPath -Raw
    foreach($token in @(
        "'CHART VISUALS'",
        "'Grid' -SettingName 'showGrid'",
        "'Restock / OoS markers' -SettingName 'showTransitions'",
        "'Live Chance to Hit' -SettingName 'showChance'",
        "'Hindsight departure windows' -SettingName 'showHindsightWindows'",
        "'Forecast accuracy markers' -SettingName 'showAccuracyMarkers'",
        "'Graph tooltips' -SettingName 'showTooltips'",
        'Set-ObjectProperty -Object $local -Name ''graphVisuals'''
    )){
        if(-not$settingsWindow.Contains($token)){Fail "Settings chart visual contract missing '$token'."}
    }
}

$ini = Get-Content -LiteralPath $iniPath -Raw
foreach($token in @(
    '[MeasureInlineGraph]',
    'RenderInlineGraph.ps1',
    '-MarketKey "#InlineGraphMarketKey#"',
    '@IncludeGraphHitboxes=#@#Includes\InlineGraphHitboxes.inc'
)){
    if(-not$ini.Contains($token)){Fail "TravelAssistant.ini missing inline graph contract '$token'."}
}

$rowsPath = Join-Path $ProjectRoot '@Resources\Includes\OpportunityRows.inc'
$rows = Get-Content -LiteralPath $rowsPath -Raw
if(-not$rows.Contains('[MeterOpportunity1InlineGraph]')){Fail 'Opportunity rows must expose the generated inline graph image meter.'}

if(-not(Test-Path -LiteralPath $hitboxPath)){
    Fail 'InlineGraphHitboxes.inc is required for marker/window tooltips.'
}else{
    $hitboxes=Get-Content -LiteralPath $hitboxPath -Raw
    $count=[regex]::Matches($hitboxes,'(?m)^\[MeterInlineGraphHitbox\d+\]\s*$').Count
    if($count -ne 48){Fail "Inline graph tooltip pool must remain bounded at 48 reusable hitboxes; found $count."}
    foreach($token in @(
        '[MeterInlineGraphHitbox1]',
        '[MeterInlineGraphHitbox48]',
        'Group=InlineGraphHitboxes',
        'Fill Color 0,0,0,1',
        'ToolTipWidth=280'
    )){
        if(-not$hitboxes.Contains($token)){Fail "Inline graph hitbox contract missing '$token'."}
    }
}

if(-not(Test-Path -LiteralPath $stateReaderPath)){
    Fail 'StateReader.lua is required for inline graph tooltip placement.'
}else{
    $reader=Get-Content -LiteralPath $stateReaderPath -Raw
    foreach($token in @(
        'local maxGraphHoverRegions = 48',
        'hideGraphHoverRegions',
        'updateGraphHoverRegions',
        "'MeterInlineGraphHitbox' .. i",
        'graphMeter:GetX()',
        'graphMeter:GetY()',
        "'ToolTipText', tooltip",
        'spec.HoverCount'
    )){
        if(-not$reader.Contains($token)){Fail "StateReader graph hitbox contract missing '$token'."}
    }
}

if($failures.Count -gt 0){
    foreach($failure in $failures){Write-Host "FAIL: $failure" -ForegroundColor Red}
    Write-Host "Graph window / interaction validation failed with $($failures.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Graph window / retention / interaction validation passed.' -ForegroundColor Green
Write-Host 'Visible: 8h | mandatory lime stock | continuous cyan forecast | periwinkle hindsight departure windows | optional validation/event overlays | raw learning retention: 48h' -ForegroundColor DarkGreen
exit 0
