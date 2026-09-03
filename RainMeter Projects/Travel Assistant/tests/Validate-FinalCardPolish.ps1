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
        'CardPresenter / travel-state presentation own the action and Chance meters',
        'enforces one cross-field invariant only',
        'hasAuthoritativeChance',
        'isNonInformativeAction',
        "value=='wait data'",
        "value=='market data pending'",
        "value=='next cycle unavailable'",
        "value=='window closed.'",
        "value:find('collecting data',1,true)",
        "meterText(prefix..'Chance')",
        "meterText(prefix..'Leave')",
        "setText(prefix..'Leave','Chance to hit:')",
        'function Update()',
        'return 0'
    )) {
        if (-not $scriptText.Contains($token)) { Fail "FinalCardPolish.lua missing chance/action consistency contract '$token'." }
    }

    foreach ($retired in @(
        'polishHeader','polishWindowStatus','!ShowMeter','!HideMeter',
        "prefix..'Gross'","prefix..'Name'",
        "setText(prefix..'Chance'",
        "setOption(prefix..'Chance'"
    )) {
        if ($scriptText.Contains($retired)) { Fail "FinalCardPolish.lua exceeds its narrow action-consistency role; found '$retired'." }
    }

    foreach ($token in @('[MeasureFinalCardPolish]','FinalCardPolish.lua')) {
        if (-not $includeText.Contains($token)) { Fail "OpportunityInfo.inc missing '$token'." }
    }
    $travelAt = $includeText.IndexOf('[MeasureTravelStateWindowTweaks]',[System.StringComparison]::Ordinal)
    $polishAt = $includeText.IndexOf('[MeasureFinalCardPolish]',[System.StringComparison]::Ordinal)
    if ($travelAt -lt 0 -or $polishAt -le $travelAt) { Fail 'Final consistency pass must remain after the travel-state window pass.' }
    if ($includeText.Contains('[MeasureWindowTooltipTweaks]')) { Fail 'Retired WindowTooltipTweaks measure returned.' }

    if ($scriptText -match '(?i)https?://|Invoke-RestMethod|curl|RunCommand') { Fail 'FinalCardPolish.lua must remain presentation-only and local.' }
}

if ($errors.Count -gt 0) {
    foreach ($error in $errors) { Write-Host "FAIL: $error" -ForegroundColor Red }
    Write-Host "Final card polish validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Final card chance/action consistency validation passed.' -ForegroundColor Green
Write-Host 'FinalCardPolish changes only a contradictory non-informative action when a valid centered Chance percentage is already visible.'
exit 0
