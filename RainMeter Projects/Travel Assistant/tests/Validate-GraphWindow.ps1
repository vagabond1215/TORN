$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$settingsPath = Join-Path $ProjectRoot 'config\settings.example.json'
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$rendererPath = Join-Path $ProjectRoot '@Resources\Scripts\RenderInlineGraph.ps1'
$stateReaderPath = Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
$hitboxPath = Join-Path $ProjectRoot '@Resources\Includes\InlineGraphHitboxes.inc'
$settingsWindowPath = Join-Path $ProjectRoot '@Resources\Scripts\OpenSettings.ps1'
$graphVisualPreferencePath = Join-Path $ProjectRoot '@Resources\Scripts\GraphVisualPreferences.ps1'

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
    foreach($name in @('showGrid','showTransitions','showRestockWindowBounds','showChance','showHindsightWindows','showAccuracyMarkers','showTooltips')){
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
    'FromArgb(145,132,165,190),1',
    'FromArgb(255,117,24),1',
    'FromArgb(105,200,235),1.5',
    'FromArgb(32,165,165,235)',
    'FromArgb(155,165,165,235),1',
    'Get-RealizedDepartureWindows',
    '$graphics.FillRectangle($hindsightBandBrush',
    'HindsightWindowCount',
    'HoverCount',
    'Get-FlightShiftedRealizedHistory',
    '$realizedThrough=$now-$flightSeconds',
    'Read-MarketResolvedArrivalHistory',
    'Get-InlineDisplayAccuracyMarkers',
    '[int]$BucketSeconds=900',
    '$displayAccuracyRows=@(Get-InlineDisplayAccuracyMarkers -Rows $resolvedRows -BucketSeconds 900)',
    'DisplayedAccuracyMarkerCount',
    '$sampleCount=[int]$row.sampleCount',
    '$sampleText=if($sampleCount -gt 1)',
    "text=('Forecast '+([Math]::Round(100.0*`$predicted,1))+'% avg | Actual '",
    'Read-InlineMarketCycles',
    'Get-InlineRestockWindowSummary',
    'Get-InlineRestockTransitions',
    '$oosTransitions=@($stockTransitions|Where-Object{[string]$_.kind -eq ''oos''}',
    'Get-CycleForecastRobustSigma -Values $delays',
    '$centerAt=[long]$oosAt+$averageDelaySeconds',
    '$openAt=$centerAt-$varianceSeconds',
    '$closeAt=$centerAt+$varianceSeconds',
    'if($openAt -ge $cutoff -and $openAt -le $now)',
    'if($closeAt -ge $cutoff -and $closeAt -le $now)',
    '$graphics.DrawLine($errorPen,$x,$predictedY,$x,$actualY)',
    "Get-InlineSettingBool -Base `$settings -Local `$localSettings -Name 'showGrid'",
    "Get-InlineSettingBool -Base `$settings -Local `$localSettings -Name 'showTransitions'",
    "Get-InlineSettingBool -Base `$settings -Local `$localSettings -Name 'showRestockWindowBounds'",
    "Get-InlineSettingBool -Base `$settings -Local `$localSettings -Name 'showChance'",
    "Get-InlineSettingBool -Base `$settings -Local `$localSettings -Name 'showHindsightWindows'",
    "Get-InlineSettingBool -Base `$settings -Local `$localSettings -Name 'showAccuracyMarkers'",
    "Get-InlineSettingBool -Base `$settings -Local `$localSettings -Name 'showTooltips'",
    'ChancePointCount',
    'RealizedHitProxyPointCount',
    'ResolvedForecastPointCount',
    'ResolvedBrierScore',
    '$markerTop=[single]($plotBottom+2)',
    '$markerBottom=[single]($plotBottom+8)',
    '$forecastMarkerTop=[single]($plotBottom+3)',
    '$forecastMarkerBottom=[single]($plotBottom+6)',
    'RestockWindowVarianceSeconds',
    'Get-InlineInfoTimeline',
    '[int]$MaximumCycles=4',
    'Sort-Object timestamp -Descending',
    "'8h cycle summary'",
    "'Avg restock delay: '",
    "'Avg in-stock time: '",
    "'Avg open variance: +/-'",
    "'Midpoint after OoS: '",
    "'Leave after OoS for midpoint: '",
    "'Timeline - newest first (max 4 cycles)'",
    "-Label 'Restock window open'",
    "-Label 'Restock window closed'",
    '[long]$AverageDelaySeconds',
    "-Label 'Actual window open'",
    "-Label 'Actual window closed'",
    'Format-InlineClockTime',
    '$graphics.DrawEllipse($infoPen',
    'InfoEnabled',
    'InfoLineCount',
    'InfoTimelineCycleCount',
    'chronological info tooltip owns event-history detail',
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
    '$graphics.DrawLine($selloutPen,$x,[single]$plotTop,$x,[single]$plotBottom)',
    '$openAt=[long]$oosAt+$earlyDelay',
    '$closeAt=[long]$oosAt+$lateDelay',
    '$openAt=[long]$restockAt-$varianceSeconds',
    '$closeAt=[long]$restockAt+$varianceSeconds',
    'Get-InlineOosTransitions',
    "text=('Restocked: '",
    "text=('OoS: '",
    "text=('Restock variance opens: '",
    "text=('Restock variance closes: '",
    "text=('Hindsight departure window: '",
    "text=('Actual hindsight window opened: '",
    "text=('Actual hindsight window closed: '",
    '$transitionHoverRegions',
    '$forecastHoverRegions',
    'foreach($row in $resolvedRows){'
)){
    if($renderer.Contains($forbidden)){Fail "Retired/deduplicated graph interaction primitive is still present: $forbidden"}
}

if(-not(Test-Path -LiteralPath $settingsWindowPath)){
    Fail 'OpenSettings.ps1 is required for graph visual toggles.'
}else{
    $settingsWindow=Get-Content -LiteralPath $settingsWindowPath -Raw
    foreach($token in @(
        "'CHART VISUALS'",
        "'Grid' -SettingName 'showGrid'",
        "'Restock / OoS markers' -SettingName 'showTransitions'",
        "'Restock window bounds' -SettingName 'showRestockWindowBounds'",
        "'Live Chance to Hit' -SettingName 'showChance'",
        "'Hindsight departure windows' -SettingName 'showHindsightWindows'",
        "'Forecast accuracy markers' -SettingName 'showAccuracyMarkers'",
        "'Graph tooltips' -SettingName 'showTooltips'",
        'Set-ObjectProperty -Object $local -Name ''graphVisuals''',
        "GraphVisualPreferences.ps1'",
        '& $graphVisualPreferenceScript -Action Read -Value Hindsight'
    )){
        if(-not$settingsWindow.Contains($token)){Fail "Settings chart visual contract missing '$token'."}
    }
}

$ini = Get-Content -LiteralPath $iniPath -Raw
foreach($token in @(
    '[MeasureInlineGraph]',
    'RenderInlineGraph.ps1',
    '-MarketKey "#InlineGraphMarketKey#"',
    '[MeasureGraphVisualAction]',
    'GraphVisualPreferences.ps1',
    'GraphVisualAction=Read',
    'GraphVisualValue=Hindsight',
    '[MeterGraphHindsightButton]',
    '[MeterGraphChanceButton]',
    '[MeterGraphWindowButton]',
    '[MeterGraphStockButton]',
    'ToggleGraphVisual(''Hindsight'')',
    'ToggleGraphVisual(''Chance'')',
    'ToggleGraphVisual(''Window'')',
    'ToggleGraphVisual(''Stock'')',
    'Text=H',
    'Text=%',
    'Text=W',
    'Text=S',
    '@IncludeGraphHitboxes=#@#Includes\InlineGraphHitboxes.inc'
)){
    if(-not$ini.Contains($token)){Fail "TravelAssistant.ini missing inline graph contract '$token'."}
}

if(-not(Test-Path -LiteralPath $graphVisualPreferencePath)){
    Fail 'GraphVisualPreferences.ps1 is required for immediate persisted header graph toggles.'
}else{
    $graphVisualPreferences=Get-Content -LiteralPath $graphVisualPreferencePath -Raw
    foreach($token in @(
        "[ValidateSet('Read','Toggle')]",
        "[ValidateSet('Hindsight','Chance','Window','Stock')]",
        "'showHindsightWindows'",
        "'showChance'",
        "'showRestockWindowBounds'",
        "'showTransitions'",
        'settings.local.json',
        'graph-visuals.kv',
        'Write-GraphVisualJsonAtomic -Path $LocalSettingsPath -Value $local',
        'Write-GraphVisualState -Base $base -Local $local'
    )){
        if(-not$graphVisualPreferences.Contains($token)){Fail "Graph visual preference contract missing '$token'."}
    }
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
    $infoCount=[regex]::Matches($hitboxes,'(?m)^\[MeterInlineGraphInfo\]\s*$').Count
    if($infoCount -ne 1){Fail "Expanded graph must expose exactly one dedicated info tooltip meter; found $infoCount."}
    foreach($token in @(
        '[MeterInlineGraphHitbox1]',
        '[MeterInlineGraphHitbox48]',
        '[MeterInlineGraphInfo]',
        'Group=InlineGraphHitboxes',
        'Fill Color 0,0,0,1',
        'ToolTipWidth=280',
        'ToolTipWidth=420'
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
        'local graphHoverSignatures = {}',
        'local graphInfoSignature = nil',
        'hideGraphInfoRegion',
        'updateGraphInfoRegion',
        'hideGraphHoverRegions',
        'updateGraphHoverRegions',
        'if graphHoverSignatures[i] ~= signature then',
        'for i = count + 1, maxGraphHoverRegions do',
        "'MeterInlineGraphHitbox' .. i",
        'graphMeter:GetX()',
        'graphMeter:GetY()',
        "'ToolTipText', tooltip",
        "'MeterInlineGraphInfo'",
        'spec.InfoLineCount',
        "table.concat(lines, '\n')",
        'updateGraphInfoRegion(spec, graphMeterName)',
        'spec.HoverCount',
        'local activeGraphVisuals = { hindsight=true, chance=true, window=true, stock=true }',
        'local function applyGraphVisualColors()',
        'local function syncGraphVisualPreferences(force)',
        "setVariable('GraphHindsightColor'",
        "setVariable('GraphChanceColor'",
        "setVariable('GraphWindowColor'",
        "setVariable('GraphStockColor'",
        'function ToggleGraphVisual(name)',
        'function GraphVisualPreferenceChanged()',
        "setVariable('GraphVisualAction', 'Toggle')",
        "SKIN:Bang('!CommandMeasure', 'MeasureGraphVisualAction', 'Run')",
        'if expandedKey ~= '''' then requestInlineGraph(expandedKey) end'
    )){
        if(-not$reader.Contains($token)){Fail "StateReader graph hitbox contract missing '$token'."}
    }
    if($reader -match 'local function updateGraphHoverRegions\([^\)]*\)\s*\r?\n\s*hideGraphHoverRegions\(\)'){
        Fail 'Graph tooltip refresh must not hide every hitbox before rebuilding; that causes hover blinking.'
    }
}

if($failures.Count -gt 0){
    foreach($failure in $failures){Write-Host "FAIL: $failure" -ForegroundColor Red}
    Write-Host "Graph window / interaction validation failed with $($failures.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Graph window / retention / interaction validation passed.' -ForegroundColor Green
Write-Host 'Visible: 8h | mandatory lime stock | continuous cyan forecast | periwinkle hindsight departure windows | sparse accuracy markers | centralized event timeline tooltip | raw learning retention: 48h' -ForegroundColor DarkGreen
exit 0
