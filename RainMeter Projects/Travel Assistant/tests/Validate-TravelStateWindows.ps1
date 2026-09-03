$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$luaPath = Join-Path $ProjectRoot '@Resources\Scripts\TravelStateWindowTweaks.lua'
$infoPath = Join-Path $ProjectRoot '@Resources\Includes\OpportunityInfo.inc'
$cardPath = Join-Path $ProjectRoot '@Resources\Scripts\CardPresenter.lua'
$travelPath = Join-Path $ProjectRoot '@Resources\Scripts\TravelContext.ps1'
$anchorPath = Join-Path $ProjectRoot '@Resources\Scripts\CycleAnchorReconciler.ps1'
$stateReaderPath = Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'

$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $errors.Add($Message) }

foreach ($path in @($luaPath,$infoPath,$cardPath,$travelPath,$anchorPath,$stateReaderPath,$iniPath)) {
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
        'activeRestockAt=number(state[prefix..''ActiveRestockAt''])',
        'activeSelloutAt=number(state[prefix..''ActiveSelloutEstimateAt''])',
        'lastObservedOosAt=number(state[prefix..''LastObservedOosAt''])',
        'forecastMode=trim(state[prefix..''ForecastMode'']):lower()',
        'rowHasUnresolvedOos',
        'phaseSafePlan',
        "plan.anchorPhase=='S' and not rowHasUnresolvedOos(row)",
        "'Latest observed phase: restocked; current stock status is stale/unknown'",
        "'Stock status stale'",
        "'Stock status unknown'",
        "'Sellout in: '",
        "'Sells out in '",
        "'Restocks in '",
        'if rowHasUnresolvedOos(row) then',
        'A later observed restock supersedes the preceding OoS',
        "'Restock in: '",
        "'Sold out in: '",
        "'Arrival estimate'",
        "travelState=='traveling'",
        "travelState=='abroad' or travelState=='foreign'",
        "'Market estimate'",
        'syncPanelHeight()',
        'local footerExtra=28',
        "math.max(160,math.floor(bottom+footerExtra))",
        "SKIN:Bang('!SetVariable','PanelHeight'"
    )) {
        if (-not $lua.Contains($token)) { Fail ("TravelStateWindowTweaks.lua missing contract token '{0}'." -f $token) }
    }
    foreach ($retired in @('Safe formula:','Best formula:','UPCOMING - SELLOUT IN ','UPCOMING - RESTOCK IN ','UPCOMING - IN STOCK','UPCOMING - STOCK STATUS')) {
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
    $polishMeasure = $info.IndexOf('[MeasureFinalCardPolish]')
    if ($travelMeasure -lt 0) { Fail 'OpportunityInfo.inc missing MeasureTravelStateWindowTweaks.' }
    if ($travelMeasure -ge 0 -and $polishMeasure -ge 0 -and $travelMeasure -gt $polishMeasure) { Fail 'Travel-state window pass must run before final card polish.' }
    if ($info.Contains('[MeasureWindowTooltipTweaks]')) { Fail 'Retired WindowTooltipTweaks measure returned.' }
    if ($info -match '(?m)^\[MeterOpportunity\d+Info\]\s*$') { Fail 'Retired invisible Info tooltip meters returned.' }

    $card = Get-Content -LiteralPath $cardPath -Raw
    foreach ($token in @(
        "if travelState=='returning' then availableAt=now+liveTravelRemainingSeconds(state,now) end",
        'findPreferredGroup(plan,effectiveFlightSeconds,availableAt,now)',
        "'SAFE AT ARRIVAL'","'BEST AT ARRIVAL'","'MARKET DATA PENDING'"
    )) {
        if (-not $card.Contains($token)) { Fail ("CardPresenter.lua missing return/home availability contract '{0}'." -f $token) }
    }

    foreach ($forbidden in @("return 'EN ROUTE'")) {
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
    foreach ($token in @('Y=25','StringAlign=LeftCenter','FontSize=16','FontFace=Nirmala UI Semilight','W=474','ClipString=1','LeftMouseUpAction=["https://www.torn.com/page.php?sid=travel"]')) {
        if (-not $titleSection.Contains($token)) { Fail ("MeterTitle missing dynamic travel-header layout token '{0}'." -f $token) }
    }

    foreach ($token in @(
        "'Departure Window: OPEN NOW'",
        "'Safe Departure Window: closed'",
        "'Safe Departure Window: NOW -> '",
        "'Window Closes: '",
        "configureWindowTooltipMeter(prefix..'Leave'"
    )) {
        if (-not $card.Contains($token)) { Fail ("CardPresenter.lua missing current home window-tooltip contract '{0}'." -f $token) }
    }
    foreach ($forbidden in @(
        "setOption(prefix..'Info','ToolTipText'",
        "setOption(prefix..'Info','ToolTipTitle'"
    )) {
        if ($lua.Contains($forbidden) -or $card.Contains($forbidden)) { Fail ("Only the visible Leave/window meter may own the window tooltip; found '{0}'." -f $forbidden) }
    }
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host ("FAIL: {0}" -f $validationError) -ForegroundColor Red }
    Write-Host ("Travel-state window validation failed with {0} error(s)." -f $errors.Count) -ForegroundColor Red
    exit 1
}

Write-Host 'Four-state window tooltip ownership validation passed.' -ForegroundColor Green
Write-Host 'Character travel state lives in the header; CardPresenter owns the home Leave tooltip and TravelStateWindowTweaks owns the same visible Leave tooltip while away.' -ForegroundColor Green
exit 0
