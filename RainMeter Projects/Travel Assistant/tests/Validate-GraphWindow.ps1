$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$settingsPath = Join-Path $ProjectRoot 'config\settings.example.json'
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$rendererPath = Join-Path $ProjectRoot '@Resources\Scripts\RenderInlineGraph.ps1'

$failures = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:failures.Add($Message) }

$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
if ([int]$settings.graphWindowHours -ne 8) { Fail 'Visible graph window must be 8 hours.' }
if ([int]$settings.highResolutionRetentionHours -lt [int]$settings.graphWindowHours) { Fail 'High-resolution retention must not be shorter than the visible graph window.' }
if ([int]$settings.highResolutionRetentionHours -ne 48) { Fail 'High-resolution learning retention should remain 48 hours.' }
if ([int]$settings.cycleRetentionDays -ne 90) { Fail 'Completed-cycle learning retention should remain 90 days.' }
if ([int]$settings.staleAfterSeconds -ne 300) { Fail 'Live-provider stale threshold should remain 300 seconds.' }

$renderer = Get-Content -LiteralPath $rendererPath -Raw
if(-not$renderer.Contains('return [single]($plotBottom - ($p * $plotHeight))')){Fail 'Chance and realized-hit overlays must use an independent fixed 0..100% vertical scale.'}
if($renderer -match '(?i)Chance.*DrawString|DrawString.*Chance'){Fail 'Chance overlay must not add a second labeled Y axis.'}
foreach($token in @(
    '$graphics.Clear([System.Drawing.Color]::FromArgb(0,0,0))',
    'FromArgb(126,190,73),2',
    'FromArgb(0,71,171),1',
    'FromArgb(255,117,24),1',
    'FromArgb(105,200,235),1.5',
    'Get-FlightShiftedRealizedHistory',
    '$realizedPen.DashStyle=[System.Drawing.Drawing2D.DashStyle]::Dot',
    'Read-MarketResolvedArrivalHistory',
    '$graphics.DrawLine($errorPen,$x,$predictedY,$x,$actualY)',
    'ChancePointCount',
    'RealizedHitProxyPointCount',
    'ResolvedForecastPointCount',
    'ResolvedBrierScore',
    '$markerTop=[single]($plotBottom+2)',
    '$markerBottom=[single]($plotBottom+8)',
    '$graphics.DrawString((''-{0}h'' -f $windowHours),$labelFont,$labelBrush,[single]($plotLeft-8),110)',
    '$graphics.DrawString(''now'',$labelFont,$labelBrush,[single]($plotRight-18),110)'
)){
    if(-not$renderer.Contains($token)){Fail "Inline graph palette missing '$token'."}
}

foreach($forbidden in @(
    '$graphics.DrawLine($restockPen,$x,[single]$plotTop,$x,[single]$plotBottom)',
    '$graphics.DrawLine($selloutPen,$x,[single]$plotTop,$x,[single]$plotBottom)'
)){
    if($renderer.Contains($forbidden)){Fail "Transition markers must stay below the X axis; found retired full-plot marker '$forbidden'."}
}

$ini = Get-Content -LiteralPath $iniPath -Raw
foreach ($token in @('[MeasureInlineGraph]','RenderInlineGraph.ps1','-MarketKey "#InlineGraphMarketKey#"')) {
    if (-not $ini.Contains($token)) { Fail "TravelAssistant.ini missing inline graph contract '$token'." }
}
$rowsPath = Join-Path $ProjectRoot '@Resources\Includes\OpportunityRows.inc'
$rows = Get-Content -LiteralPath $rowsPath -Raw
if (-not $rows.Contains('[MeterOpportunity1InlineGraph]')) { Fail 'Opportunity rows must expose the generated inline graph image meter.' }

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'Graph window / retention validation passed.' -ForegroundColor Green
Write-Host 'Visible: 8h | black graph | lime stock | cobalt/pumpkin transition ticks below X axis | raw learning retention: 48h' -ForegroundColor DarkGreen
exit 0
