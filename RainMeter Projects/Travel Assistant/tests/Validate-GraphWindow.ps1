$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$settingsPath = Join-Path $ProjectRoot 'config\settings.example.json'
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'

$failures = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:failures.Add($Message) }

$settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
if ([int]$settings.graphWindowHours -ne 12) { Fail 'Visible graph window must be 12 hours.' }
if ([int]$settings.highResolutionRetentionHours -lt [int]$settings.graphWindowHours) { Fail 'High-resolution retention must not be shorter than the visible graph window.' }
if ([int]$settings.highResolutionRetentionHours -ne 48) { Fail 'High-resolution learning retention should remain 48 hours.' }
if ([int]$settings.cycleRetentionDays -ne 90) { Fail 'Completed-cycle learning retention should remain 90 days.' }
if ([int]$settings.staleAfterSeconds -ne 300) { Fail 'Live-provider stale threshold should remain 300 seconds.' }

$ini = Get-Content -LiteralPath $iniPath -Raw
foreach ($sectionName in @('MeterUKHourGrid','MeterJPHourGrid')) {
    $pattern = '(?ms)^\[' + [regex]::Escape($sectionName) + '\]\s*(.*?)(?=^\[|\z)'
    $match = [regex]::Match($ini, $pattern)
    if (-not $match.Success) {
        Fail "Missing [$sectionName]."
        continue
    }
    $body = $match.Groups[1].Value
    $lineCount = @([regex]::Matches($body, '(?im)^Shape\d*=Line\s+')).Count
    if ($body -match '(?im)^Shape=Line\s+') { $lineCount++ }
    if ($lineCount -ne 11) { Fail "[$sectionName] must contain 11 internal hourly lines for 12 one-hour segments; found $lineCount." }
    if ($body -notmatch '60-minute intervals') { Fail "[$sectionName] should identify the grid as 60-minute intervals." }
}

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL $failure" -ForegroundColor Red }
    exit 1
}

Write-Host 'Graph window / retention validation passed.' -ForegroundColor Green
Write-Host 'Visible: 12h | raw learning retention: 48h | cycle retention: 90d | live stale guard: 5m' -ForegroundColor DarkGreen
exit 0
