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

foreach ($sectionName in @('MeasureUpdate','MeasureCycleMode')) {
    $pattern = '(?ms)^\[' + [regex]::Escape($sectionName) + '\]\s*(.*?)(?=^\[|\z)'
    $match = [regex]::Match($ini, $pattern)
    if (-not $match.Success) {
        Fail "Missing Rainmeter section [$sectionName]."
        continue
    }

    $body = $match.Groups[1].Value
    if ($body -notmatch '(?im)^Measure=Plugin\s*$') {
        Fail "[$sectionName] must declare Measure=Plugin."
    }
    if ($body -notmatch '(?im)^Plugin=RunCommand\s*$') {
        Fail "[$sectionName] must declare Plugin=RunCommand."
    }
    if ($body -notmatch '(?im)^Program=powershell\.exe\s*$') {
        Fail "[$sectionName] must execute powershell.exe."
    }
    if ($body -notmatch '(?im)^Parameter=.*RunUpdate\.ps1') {
        Fail "[$sectionName] must route through RunUpdate.ps1."
    }
}

if ($ini -notmatch '(?m)^OnRefreshAction=\[!CommandMeasure MeasureUpdate "Run"\]\s*$') {
    Fail 'OnRefreshAction must trigger MeasureUpdate Run.'
}

if ($errors.Count -gt 0) {
    foreach ($errorMessage in $errors) {
        Write-Host "FAIL: $errorMessage" -ForegroundColor Red
    }
    Write-Host "Rainmeter skin validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Rainmeter skin static validation passed.' -ForegroundColor Green
exit 0
