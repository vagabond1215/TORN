$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $ProjectRoot '@Resources\Scripts\FinalCardPolish.lua'
$includePath = Join-Path $ProjectRoot '@Resources\Includes\OpportunityInfo.inc'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

if (-not (Test-Path -LiteralPath $scriptPath)) { Fail 'Missing FinalCardPolish.lua.' }
if (-not (Test-Path -LiteralPath $includePath)) { Fail 'Missing OpportunityInfo.inc.' }

if ($errors.Count -eq 0) {
    $scriptText = Get-Content -LiteralPath $scriptPath -Raw
    $includeText = Get-Content -LiteralPath $includePath -Raw

    foreach ($token in @(
        'CardPresenter emits the final card contract',
        'StateReader owns all geometry',
        'non-destructive compatibility point',
        'function Update()',
        'return 0'
    )) {
        if (-not $scriptText.Contains($token)) { Fail "FinalCardPolish.lua missing non-destructive contract '$token'." }
    }

    foreach ($retired in @(
        'polishHeader','polishWindowStatus','!SetOption','!ShowMeter','!HideMeter',
        "prefix..'Gross'","prefix..'Chance'","prefix..'Name'"
    )) {
        if ($scriptText.Contains($retired)) { Fail "FinalCardPolish.lua must not mutate compact-card presentation; found '$retired'." }
    }

    foreach ($token in @('[MeasureFinalCardPolish]','FinalCardPolish.lua')) {
        if (-not $includeText.Contains($token)) { Fail "OpportunityInfo.inc missing '$token'." }
    }
    $tooltipAt = $includeText.IndexOf('[MeasureWindowTooltipTweaks]',[System.StringComparison]::Ordinal)
    $polishAt = $includeText.IndexOf('[MeasureFinalCardPolish]',[System.StringComparison]::Ordinal)
    if ($tooltipAt -lt 0 -or $polishAt -le $tooltipAt) { Fail 'Final compatibility pass must remain after the window tooltip pass.' }

    if ($scriptText -match '(?i)https?://|Invoke-RestMethod|curl|RunCommand') { Fail 'FinalCardPolish.lua must remain presentation-only and local.' }
}

if ($errors.Count -gt 0) {
    foreach ($error in $errors) { Write-Host "FAIL: $error" -ForegroundColor Red }
    Write-Host "Final card polish validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Final card compatibility validation passed.' -ForegroundColor Green
Write-Host 'FinalCardPolish remains in the refresh chain but cannot override CardPresenter text or StateReader geometry.'
exit 0
