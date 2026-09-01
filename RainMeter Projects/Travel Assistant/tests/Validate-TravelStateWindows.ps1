$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$luaPath = Join-Path $ProjectRoot '@Resources\Scripts\TravelStateWindowTweaks.lua'
$infoPath = Join-Path $ProjectRoot '@Resources\Includes\OpportunityInfo.inc'
$cardPath = Join-Path $ProjectRoot '@Resources\Scripts\CardPresenter.lua'
$tooltipPath = Join-Path $ProjectRoot '@Resources\Scripts\WindowTooltipTweaks.lua'
$travelPath = Join-Path $ProjectRoot '@Resources\Scripts\TravelContext.ps1'
$anchorPath = Join-Path $ProjectRoot '@Resources\Scripts\CycleAnchorReconciler.ps1'
$stateReaderPath = Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'

$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $errors.Add($Message) }

foreach ($path in @($luaPath,$infoPath,$cardPath,$tooltipPath,$travelPath,$anchorPath,$stateReaderPath,$iniPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail ("Missing required file: {0}" -f $path) }
}

if ($errors.Count -eq 0) {
    $lua = Get-Content -LiteralPath $luaPath -Raw
    foreach ($token in @(
        "travelState=='returning'",
        "Character travel status belongs in MeterTitle",
        "return 'MARKET DATA PENDING'",
        'averageRestockDelay(plan)',
        'averageAvailability(plan)',
        'landingRelevantGroup(plan,landingAt)',
        'number(group.lateSellout)>landingAt',
        "'Landing in '",
        "'Estimated Stock at arrival: '",
        'currentStock=number(state[prefix..''CurrentStock''])',
        'activeSelloutAt=number(state[prefix..''ActiveSelloutEstimateAt''])',
        "'Sellout in: '",
        "'UPCOMING - SELLOUT IN '",
        "'UPCOMING - RESTOCK IN '",
        "'Restock in: '",
        "'Sold out in: '",
        "'Arrival estimate'",
        "travelState=='traveling'",
        "travelState=='abroad' or travelState=='foreign'",
        "'Market estimate'",
        'syncPanelHeight()',
        "SKIN:Bang('!SetVariable','PanelHeight'"
    )) {
        if (-not $lua.Contains($token)) { Fail ("TravelStateWindowTweaks.lua missing contract token '{0}'." -f $token) }
    }
    foreach ($retired in @('Safe formula:','Best formula:')) {
        if ($lua.Contains($retired)) { Fail ("Travel-state tooltip must not contain generic home-window detail '{0}'." -f $retired) }
    }

    foreach ($forbidden in @(
        "setOption(prefix..'Leave','Text',returningStatus(state,now))",
        "applyTooltip(prefix,returningTooltip(state,now),'Return estimate')"
    )) {
        if ($lua.Contains($forbidden)) { Fail ("Character travel state must not overwrite item-card action text; found '{0}'." -f $forbidden) }
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
        '$lastSellOutAt=$timestamp',
        '$lastSellOutLowerBoundAt=$lower',
        'Test-AnchorBoundaryQuality -Quality $quality',
        "Set-AnchorProperty -Object `$destination -Name 'lastSellOutAt'",
        "Set-AnchorProperty -Object `$destination -Name 'lastSellOutBoundaryQuality'",
        "anchorSource' -Value 'observations'"
    )) {
        if (-not $anchor.Contains($token)) { Fail ("CycleAnchorReconciler.ps1 missing real sellout-anchor contract '{0}'." -f $token) }
    }

    $info = Get-Content -LiteralPath $infoPath -Raw
    $travelMeasure = $info.IndexOf('[MeasureTravelStateWindowTweaks]')
    $tooltipMeasure = $info.IndexOf('[MeasureWindowTooltipTweaks]')
    $polishMeasure = $info.IndexOf('[MeasureFinalCardPolish]')
    if ($travelMeasure -lt 0) { Fail 'OpportunityInfo.inc missing MeasureTravelStateWindowTweaks.' }
    if ($tooltipMeasure -lt 0) { Fail 'OpportunityInfo.inc missing MeasureWindowTooltipTweaks.' }
    if ($travelMeasure -ge 0 -and $tooltipMeasure -ge 0 -and $travelMeasure -gt $tooltipMeasure) { Fail 'Travel-state window pass must run before home tooltip finalization.' }
    if ($travelMeasure -ge 0 -and $polishMeasure -ge 0 -and $travelMeasure -gt $polishMeasure) { Fail 'Travel-state window pass must run before final card polish.' }

    $card = Get-Content -LiteralPath $cardPath -Raw
    foreach ($token in @(
        "if travelState=='returning' then availableAt=now+liveTravelRemainingSeconds(state,now) end",
        'findPreferredGroup(plan,effectiveFlightSeconds,availableAt,now)'
    )) {
        if (-not $card.Contains($token)) { Fail ("CardPresenter.lua missing return/home availability contract '{0}'." -f $token) }
    }

    foreach ($forbidden in @("return 'EN ROUTE'","return 'AT DEST.'")) {
        if ($card.Contains($forbidden)) { Fail ("CardPresenter.lua must not repeat character travel state on item cards; found '{0}'." -f $forbidden) }
    }

    $stateReader = Get-Content -LiteralPath $stateReaderPath -Raw
    foreach ($token in @(
        'travelHeaderText',
        'updateTravelHeader',
        "return 'In Torn'",
        "'In Flight to '",
        "'Landing in '",
        "'Abroad in '",
        "'MeterTitle'"
    )) {
        if (-not $stateReader.Contains($token)) { Fail ("StateReader.lua missing global travel-header token '{0}'." -f $token) }
    }

    $ini = Get-Content -LiteralPath $iniPath -Raw
    $titleSection=[regex]::Match($ini,'(?ms)^\[MeterTitle\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    foreach ($token in @('W=474','ClipString=1','LeftMouseUpAction=["https://www.torn.com/page.php?sid=travel"]')) {
        if (-not $titleSection.Contains($token)) { Fail ("MeterTitle missing dynamic travel-header layout token '{0}'." -f $token) }
    }

    $tooltip = Get-Content -LiteralPath $tooltipPath -Raw
    foreach ($token in @(
        "if travelState=='traveling' or travelState=='returning' or travelState=='abroad' or travelState=='foreign' then",
        'buildHomeTooltip',
        'nextCycleGroup',
        'windowDataQuality',
        "'Collecting Data'",
        "setOption(prefix..'Chance','Text','')",
        'return'
    )) {
        if (-not $tooltip.Contains($token)) { Fail ("WindowTooltipTweaks.lua missing home-only ownership contract '{0}'." -f $token) }
    }
    foreach ($forbidden in @('existingTooltip',"meterOption(prefix..'Leave','ToolTipText')", "meterOption(prefix..'Info','ToolTipText')")) {
        if ($tooltip.Contains($forbidden)) { Fail ("Home tooltip must not consume prior rendered tooltip text; found '{0}'." -f $forbidden) }
    }
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host ("FAIL: {0}" -f $validationError) -ForegroundColor Red }
    Write-Host ("Travel-state window validation failed with {0} error(s)." -f $errors.Count) -ForegroundColor Red
    exit 1
}

Write-Host 'Four-state window tooltip ownership validation passed.' -ForegroundColor Green
Write-Host 'Character travel state lives in the header; item cards retain only market/window actions. Home owns current/next-cycle and collecting-data state.' -ForegroundColor Green
exit 0
