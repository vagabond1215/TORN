$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$builderPath=Join-Path $ProjectRoot '@Resources\Scripts\BuildGraphHoverData.ps1'
$luaPath=Join-Path $ProjectRoot '@Resources\Scripts\GraphHover.lua'
$includePath=Join-Path $ProjectRoot '@Resources\Includes\GraphHover.inc'
$infoPath=Join-Path $ProjectRoot '@Resources\Includes\OpportunityInfo.inc'

$errors=New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $errors.Add($Message) }

foreach ($path in @($builderPath,$luaPath,$includePath,$infoPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail ("Missing graph-hover asset: {0}" -f $path) }
}

if ($errors.Count -eq 0) {
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($builderPath,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail ("PowerShell parse error in BuildGraphHoverData.ps1: {0}" -f $parseError.Message) }

    $builder=Get-Content -LiteralPath $builderPath -Raw
    foreach ($token in @(
        '$BandCount=48',
        "'WindowStartTimestamp'",
        "'CurrentStock'",
        "'LatestTimestamp'",
        "'history_bootstrap','history_repair_baseline'",
        "`$spec['HoverCount']=`$BandCount",
        "'Hover{0:D2}'",
        'Get-HoverStockAt'
    )) {
        if (-not $builder.Contains($token)) { Fail ("BuildGraphHoverData.ps1 missing contract '{0}'." -f $token) }
    }
    foreach ($network in @('Invoke-RestMethod','Invoke-WebRequest','http://','https://')) {
        if ($builder.Contains($network)) { Fail ("Graph hover lookup must remain local-only; found '{0}'." -f $network) }
    }

    $lua=Get-Content -LiteralPath $luaPath -Raw
    foreach ($token in @(
        'local bandCount=48',
        "SKIN:GetVariable('InlineGraphMarketKey'",
        "'MeasureGraphHoverData'",
        'local plotX=graphX+34',
        'local plotY=graphY+8',
        'local plotW=488',
        'local plotH=90',
        "'Time: '",
        "'#CRLF#Stock: '"
    )) {
        if (-not $lua.Contains($token)) { Fail ("GraphHover.lua missing contract '{0}'." -f $token) }
    }

    $include=Get-Content -LiteralPath $includePath -Raw
    $meterCount=([regex]::Matches($include,'(?m)^\[MeterGraphHover\d{2}\]$')).Count
    if ($meterCount -ne 48) { Fail ("GraphHover.inc should define 48 hover bands; found {0}." -f $meterCount) }
    foreach ($token in @('[GraphHoverStyle]','MeterStyle=GraphHoverStyle','Fill Color 0,0,0,1','ToolTipTitle=Stock history')) {
        if (-not $include.Contains($token)) { Fail ("GraphHover.inc missing contract '{0}'." -f $token) }
    }

    $info=Get-Content -LiteralPath $infoPath -Raw
    foreach ($token in @('[MeasureGraphHoverData]','BuildGraphHoverData.ps1','[MeasureGraphHover]','GraphHover.lua','@IncludeGraphHover=#@#Includes\GraphHover.inc')) {
        if (-not $info.Contains($token)) { Fail ("OpportunityInfo.inc missing graph-hover wiring '{0}'." -f $token) }
    }
}

if ($errors.Count -gt 0) {
    foreach ($error in $errors) { Write-Host ("FAIL: {0}" -f $error) -ForegroundColor Red }
    Write-Host ("Inline graph hover validation failed with {0} error(s)." -f $errors.Count) -ForegroundColor Red
    exit 1
}

Write-Host 'Inline graph hover telemetry validation passed.' -ForegroundColor Green
Write-Host 'The expanded graph exposes local time and retained stock values in 48 transparent hover bands without network access.' -ForegroundColor Green
exit 0
