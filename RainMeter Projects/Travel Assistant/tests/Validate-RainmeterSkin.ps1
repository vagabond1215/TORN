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

foreach ($sectionName in @('MeasureUpdate','MeasureSettings')) {
    $pattern = '(?ms)^\[' + [regex]::Escape($sectionName) + '\]\s*(.*?)(?=^\[|\z)'
    $match = [regex]::Match($ini, $pattern)
    if (-not $match.Success) {
        Fail "Missing Rainmeter section [$sectionName]."
        continue
    }

    $body = $match.Groups[1].Value
    if ($body -notmatch '(?im)^Measure=Plugin\s*$') { Fail "[$sectionName] must declare Measure=Plugin." }
    if ($body -notmatch '(?im)^Plugin=RunCommand\s*$') { Fail "[$sectionName] must declare Plugin=RunCommand." }
    if ($body -notmatch '(?im)^Program=powershell\.exe\s*$') { Fail "[$sectionName] must execute powershell.exe." }

    if ($sectionName -eq 'MeasureUpdate' -and $body -notmatch '(?im)^Parameter=.*RunUpdate\.ps1') {
        Fail '[MeasureUpdate] must route through RunUpdate.ps1.'
    }
    if ($sectionName -eq 'MeasureSettings') {
        if ($body -notmatch '(?im)^Parameter=.*LaunchSettings\.ps1') {
            Fail '[MeasureSettings] must route through the short-lived LaunchSettings.ps1 wrapper.'
        }
        if ($body -match '(?im)^Timeout=-1\s*$') {
            Fail '[MeasureSettings] must not remain owned by RunCommand for the lifetime of the Settings dialog.'
        }
    }
}

$launcherPath = Join-Path $ProjectRoot '@Resources\Scripts\LaunchSettings.ps1'
if (-not (Test-Path -LiteralPath $launcherPath)) {
    Fail 'Missing @Resources\Scripts\LaunchSettings.ps1.'
} else {
    $launcher = Get-Content -LiteralPath $launcherPath -Raw
    if ($launcher -notmatch 'OpenSettings\.ps1') { Fail 'LaunchSettings.ps1 must start OpenSettings.ps1.' }
    if ($launcher -notmatch 'Start-Process') { Fail 'LaunchSettings.ps1 must detach the Settings dialog process.' }
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($launcherPath, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in LaunchSettings.ps1: $($parseError.Message)" }
}

if ($ini -notmatch '(?m)^OnRefreshAction=\[!CommandMeasure MeasureUpdate "Run"\]\s*$') {
    Fail 'OnRefreshAction must trigger MeasureUpdate Run.'
}
if ($ini -notmatch '(?ms)^\[MeterSettings\].*?Text=SETTINGS\s+>') {
    Fail 'Top-right Settings meter is missing.'
}
if ($ini -notmatch '(?m)^LeftMouseUpAction=\[!CommandMeasure MeasureSettings "Run"\]\s*$') {
    Fail 'Settings meter must trigger the MeasureSettings RunCommand measure.'
}
if ($ini -match '(?m)^\[MeasureCycleMode\]') {
    Fail 'Main skin should no longer expose the slow CycleTravelMode RunCommand measure.'
}

$titleMatch = [regex]::Match($ini, '(?ms)^\[MeterTitle\]\s*(.*?)(?=^\[|\z)')
if (-not $titleMatch.Success) {
    Fail 'Missing [MeterTitle].'
} else {
    $titleBody = $titleMatch.Groups[1].Value
    if ($titleBody -notmatch '(?im)^Text=Travel\s*$') { Fail 'Main header must display Travel.' }
    if ($titleBody -notmatch '(?im)^LeftMouseUpAction=\["https://www\.torn\.com/page\.php\?sid=travel"\]\s*$') {
        Fail 'Travel header must open the Torn travel page.'
    }
}

foreach ($flagSection in @('MeterUKFlag','MeterJPFlag')) {
    if ($ini -notmatch ('(?m)^\[' + [regex]::Escape($flagSection) + '\]\s*$')) {
        Fail "Missing [$flagSection] country flag meter."
    }
}
if ($ini -match '(?m)^\[MeterUKStatus\]\s*$' -or $ini -match '(?m)^\[MeterJPStatus\]\s*$') {
    Fail 'Redundant destination status footer meters must be removed.'
}
if ($ini -match '(?i)click timing/status to verify on Weav3r') {
    Fail 'Redundant timing/status verification footer text is still present.'
}
if ($ini -match '(?im)^Text=UNITED KINGDOM - XANAX\s*$' -or $ini -match '(?im)^Text=JAPAN - XANAX\s*$') {
    Fail 'Destination headings must use flag icons rather than country-name text.'
}

if ($errors.Count -gt 0) {
    foreach ($errorMessage in $errors) { Write-Host "FAIL: $errorMessage" -ForegroundColor Red }
    Write-Host "Rainmeter skin validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Rainmeter skin static validation passed.' -ForegroundColor Green
exit 0
