$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$luaPath = Join-Path $ProjectRoot '@Resources\Scripts\TravelStateWindowTweaks.lua'
$infoPath = Join-Path $ProjectRoot '@Resources\Includes\OpportunityInfo.inc'
$cardPath = Join-Path $ProjectRoot '@Resources\Scripts\CardPresenter.lua'
$tooltipPath = Join-Path $ProjectRoot '@Resources\Scripts\WindowTooltipTweaks.lua'
$travelPath = Join-Path $ProjectRoot '@Resources\Scripts\TravelContext.ps1'
$anchorPath = Join-Path $ProjectRoot '@Resources\Scripts\CycleAnchorReconciler.ps1'

$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $errors.Add($Message) }

foreach ($path in @($luaPath,$infoPath,$cardPath,$tooltipPath,$travelPath,$anchorPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail ("Missing required file: {0}" -f $path) }
}

if ($errors.Count -eq 0) {
    $lua = Get-Content -LiteralPath $luaPath -Raw
    foreach ($token in @(
        "travelState=='returning'",
        "'ARRIVE IN TORN: '",
        "plan.anchorPhase=='S'",
        'averageRestockDelay(plan)',
        'local restockAt=plan.anchorAt+delay',
        'local outOfStockFor=math.max(0,now-plan.anchorAt)',
        "'OoS: '",
        "'. Restock: '",
        "' overdue'",
        "travelState~='traveling' and travelState~='abroad' and travelState~='foreign'",
        "countryId~=destinationId",
        'averageAvailability(plan)',
        "'UPCOMING - SELLOUT IN '"
    )) {
        if (-not $lua.Contains($token)) { Fail ("TravelStateWindowTweaks.lua missing contract token '{0}'." -f $token) }
    }

    $travel = Get-Content -LiteralPath $travelPath -Raw
    foreach ($token in @(
        "if (`$destLower -in @('torn','torn city','home'))",
        "`$state = 'returning'",
        "`$state['TravelArrivalAt']",
        "`$state['TravelTimeLeft']"
    )) {
        if (-not $travel.Contains($token)) { Fail ("TravelContext.ps1 missing returning-flight contract '{0}'." -f $token) }
    }

    $anchor = Get-Content -LiteralPath $anchorPath -Raw
    foreach ($token in @(
        '[long]$previousStock -gt 0 -and $stock -le 0',
        '$lastSellOutAt = $timestamp',
        "Set-AnchorProperty -Object `$destination -Name 'lastSellOutAt'",
        "anchorSource' -Value 'observations'"
    )) {
        if (-not $anchor.Contains($token)) { Fail ("CycleAnchorReconciler.ps1 missing real sellout-anchor contract '{0}'." -f $token) }
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
Write-Host 'Returning is detected explicitly; OOS timing is latest real sellout plus average retained restock delay; outbound/abroad remain destination-specific.' -ForegroundColor Green
exit 0
