$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$luaPath = Join-Path $ProjectRoot '@Resources\Scripts\TravelStateWindowTweaks.lua'
$infoPath = Join-Path $ProjectRoot '@Resources\Includes\OpportunityInfo.inc'
$cardPath = Join-Path $ProjectRoot '@Resources\Scripts\CardPresenter.lua'
$tooltipPath = Join-Path $ProjectRoot '@Resources\Scripts\WindowTooltipTweaks.lua'

$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $errors.Add($Message) }

foreach ($path in @($luaPath,$infoPath,$cardPath,$tooltipPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail ("Missing required file: {0}" -f $path) }
}

if ($errors.Count -eq 0) {
    $lua = Get-Content -LiteralPath $luaPath -Raw
    foreach ($token in @(
        "travelState=='traveling'",
        "travelState=='abroad' or travelState=='foreign'",
        "countryId~=destinationId",
        'findUpcomingGroup(plan,now)',
        "'UPCOMING - RESTOCK IN '",
        "'UPCOMING - SELLOUT IN '",
        "'RESTOCK IN '",
        "'IN STOCK FOR '",
        'medianAvailability(plan)',
        'sellout>now'
    )) {
        if (-not $lua.Contains($token)) { Fail ("TravelStateWindowTweaks.lua missing contract token '{0}'." -f $token) }
    }
    if ($lua.Contains('TravelArrivalAt') -or $lua.Contains('TravelTimeLeft')) {
        Fail 'Outbound informational cycle selection must not filter by landing feasibility.'
    }

    $info = Get-Content -LiteralPath $infoPath -Raw
    $travelMeasure = $info.IndexOf('[MeasureTravelStateWindowTweaks]')
    $tooltipMeasure = $info.IndexOf('[MeasureWindowTooltipTweaks]')
    $polishMeasure = $info.IndexOf('[MeasureFinalCardPolish]')
    if ($travelMeasure -lt 0) { Fail 'OpportunityInfo.inc missing MeasureTravelStateWindowTweaks.' }
    if ($travelMeasure -ge 0 -and $tooltipMeasure -ge 0 -and $travelMeasure -gt $tooltipMeasure) { Fail 'Travel-state window pass must run before tooltip finalization.' }
    if ($travelMeasure -ge 0 -and $polishMeasure -ge 0 -and $travelMeasure -gt $polishMeasure) { Fail 'Travel-state window pass must run before final card polish.' }

    $card = Get-Content -LiteralPath $cardPath -Raw
    foreach ($token in @(
        "if travelState=='returning' then availableAt=now+liveTravelRemainingSeconds(state,now) end",
        'findPreferredGroup(plan,effectiveFlightSeconds,availableAt,now)'
    )) {
        if (-not $card.Contains($token)) { Fail ("CardPresenter.lua missing return/home availability contract '{0}'." -f $token) }
    }

    $tooltip = Get-Content -LiteralPath $tooltipPath -Raw
    if (-not $tooltip.Contains("selected=tostring(existingTooltip or ''):match('Best Hit Window:")) {
        Fail 'WindowTooltipTweaks.lua must prefer confidence from the travel-state-selected cycle.'
    }
}

if ($errors.Count -gt 0) {
    foreach ($error in $errors) { Write-Host ("FAIL: {0}" -f $error) -ForegroundColor Red }
    Write-Host ("Travel-state window validation failed with {0} error(s)." -f $errors.Count) -ForegroundColor Red
    exit 1
}

Write-Host 'Travel-state window presentation validation passed.' -ForegroundColor Green
Write-Host 'Outbound shows the nearest physical cycle even when landing misses it; abroad uses stock/restock countdowns; returning continues to skip windows before Torn availability.' -ForegroundColor Green
exit 0