$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
if (-not (Test-Path -LiteralPath $iniPath)) {
    Write-Host 'FAIL: TravelAssistant.ini is missing.' -ForegroundColor Red
    exit 1
}

$ini = Get-Content -LiteralPath $iniPath -Raw
$errors = New-Object System.Collections.Generic.List[string]

function Fail([string]$Message) { $script:errors.Add($Message) }

if ($ini -match '(?im)^Measure=RunCommand\s*$') {
    Fail 'RunCommand must be declared as Measure=Plugin plus Plugin=RunCommand.'
}

$pattern = '(?ms)^\[MeasureUpdate\]\s*(.*?)(?=^\[|\z)'
$match = [regex]::Match($ini, $pattern)
if (-not $match.Success) {
    Fail 'Missing Rainmeter section [MeasureUpdate].'
} else {
    $body = $match.Groups[1].Value
    if ($body -notmatch '(?im)^Measure=Plugin\s*$') { Fail '[MeasureUpdate] must declare Measure=Plugin.' }
    if ($body -notmatch '(?im)^Plugin=RunCommand\s*$') { Fail '[MeasureUpdate] must declare Plugin=RunCommand.' }
    if ($body -notmatch '(?im)^Program=powershell\.exe\s*$') { Fail '[MeasureUpdate] must execute powershell.exe.' }
    if ($body -notmatch '(?im)^Parameter=.*RunUpdate\.ps1') { Fail '[MeasureUpdate] must route through RunUpdate.ps1.' }
}

if ($ini -notmatch '(?m)^OnRefreshAction=\[!CommandMeasure MeasureUpdate "Run"\]\s*$') {
    Fail 'OnRefreshAction must trigger MeasureUpdate Run.'
}
if ($ini -notmatch '(?ms)^\[MeterSettings\].*?Text=SETTINGS\s+>') {
    Fail 'Top-right Settings meter is missing.'
}
if ($ini -notmatch '(?m)^LeftMouseUpAction=.*OpenSettings\.ps1') {
    Fail 'Settings meter must launch OpenSettings.ps1.'
}
if ($ini -match '(?m)^\[MeasureCycleMode\]') {
    Fail 'Main skin should no longer expose the slow CycleTravelMode RunCommand measure.'
}

if ($errors.Count -gt 0) {
    foreach ($errorMessage in $errors) { Write-Host "FAIL: $errorMessage" -ForegroundColor Red }
    Write-Host "Rainmeter skin validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Rainmeter skin static validation passed.' -ForegroundColor Green
exit 0
