$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$presenterPath = Join-Path $ProjectRoot '@Resources\Scripts\CardPresenter.lua'
$opportunityPath = Join-Path $ProjectRoot '@Resources\Scripts\OpportunityState.ps1'
$windowPlanPath = Join-Path $ProjectRoot '@Resources\Scripts\WindowPlan.ps1'
$windowRefinerPath = Join-Path $ProjectRoot '@Resources\Scripts\WindowPlanRefiner.ps1'
$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($iniPath,$presenterPath,$opportunityPath,$windowPlanPath,$windowRefinerPath,$wrapperPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing compact-card/window file: $path" }
}
if ($errors.Count -eq 0) {
    $ini = Get-Content -LiteralPath $iniPath -Raw
    $presenter = Get-Content -LiteralPath $presenterPath -Raw
    $opportunity = Get-Content -LiteralPath $opportunityPath -Raw
    $windowPlan = Get-Content -LiteralPath $windowPlanPath -Raw
    $windowRefiner = Get-Content -LiteralPath $windowRefinerPath -Raw
    $wrapper = Get-Content -LiteralPath $wrapperPath -Raw

    foreach ($token in @('[MeasureCardPresenter]','CardPresenter.lua','StateFile=#@#Generated\ui-state.kv')) {
        if (-not $ini.Contains($token)) { Fail "TravelAssistant.ini missing compact-card token '$token'." }
    }
    $stateAt = $ini.IndexOf('[MeasureState]',[System.StringComparison]::Ordinal)
    $presenterAt = $ini.IndexOf('[MeasureCardPresenter]',[System.StringComparison]::Ordinal)
    if ($stateAt -lt 0 -or $presenterAt -le $stateAt) { Fail 'MeasureCardPresenter must update after MeasureState.' }

    # Keep this PowerShell validator ASCII-only for Windows PowerShell 5.1.
    foreach ($token in @(
        'removeCountrySuffix','rowCountryAndTravel','liveTravelRemainingSeconds','TravelDestinationCountryId','TravelArrivalAt','TravelTimeLeft','TravelContextLastSuccessAt','os.time()',
        'parseWindowPlan','parsePriceVarianceEnvelope','probabilityAt','staysAboveThresholdUntil','groupMode','liveWindowAction','nextBetterBestBefore',
        'WP2:','PV([01])','group.safeEnd-group.safeStart>=60','group.bestProbability>0.5','currentProbability>0.5',
        'formatCountdown',"string.format('%02d:%02d:%02d',hours,minutes,secs)",
        'formatBestCountdown','return formatCountdown(seconds)',
        "'Leave before: '..formatCountdown","'Window opens: '..formatCountdown",
        "'Window Open. Optimal Departure: '..formatCountdown","'. Safe Departure: '..formatCountdown",
        "'Guaranteed Hit for: '..formatCountdown","'. Closes: '..formatCountdown",
        'Safe formula: max(restock starts) -> min(sellout ends)','Best formula: completed-cycle overlap / usable cycle count',
        'Early Restock: ','Late Restock: ','Safe Window: ','Best Hit Window: ',
        'configureWindowTooltipMeter','ToolTipTitle','ToolTipWidth','SolidColor','Empty ToolTipText disables the tooltip naturally',
        'quantityFromProjectedState','buyPriceFromProjectedState','projectedPrefix=opportunityStatePrefix(state,country,itemName)',
        "state[projectedPrefix..'TakeValue']","state[projectedPrefix..'MakeValue']",
        "state[projectedPrefix..'MarketValueValue']","state[projectedPrefix..'ProfitEachValue']",
        "state[projectedPrefix..'GrossSaleValue']","state[projectedPrefix..'GrossProfitHourValue']","state[projectedPrefix..'MarketTaxValue']",
        "local face='Nirmala UI Semilight'",
        "setOption(prefix..'Name','Text',itemName)","setOption(prefix..'Name','ToolTipText','Item name')","setOption(prefix..'Name','FontColor','0,0,0,0')",
        "unitCostText=unitCost>0 and formatMoney(unitCost) or '?'",
        "setOption(prefix..'Price','Text',itemName..' | '..unitCostText)",
        "setOption(prefix..'Price','InlinePattern','\\|')","setOption(prefix..'Price','InlineSetting','Color | #Muted#')",
        "state[projectedPrefix..'PriceColor']","setOption(prefix..'Price','InlinePattern2','(?<=\\| )-?\\$[0-9,]+')","setOption(prefix..'Price','InlineSetting2','Color | '..priceColor)",
        "setOption(prefix..'Take','Text','Take: '..takeText)","setOption(prefix..'Take','FontColor','#Text#')",
        "setOption(prefix..'Make','Text','Make: '..formatMoney(make))","setOption(prefix..'Make','FontColor','#Text#')",
        "'MV:'..formatMoney(mv)","'  Each:'..formatMoney(each)","'  Gross:'..formatMoney(grossSale)",
        "'  Per Hour:'..formatMoney(grossProfitHour)","'  Tax:'..formatMoney(marketTax)",
        "setOption(prefix..'Gross','FontColor','255,255,255,255')",
        "setOption(prefix..'Gross','InlinePattern','(?<=MV:)-?\\$[0-9,]+')","setOption(prefix..'Gross','InlineSetting','Color | 218,178,69,255')",
        "setOption(prefix..'Gross','InlinePattern2','(?<=Each:)-?\\$[0-9,]+')","setOption(prefix..'Gross','InlineSetting2','Color | 255,255,255,255')",
        "setOption(prefix..'Gross','InlinePattern3','(?<=Gross:)-?\\$[0-9,]+')","setOption(prefix..'Gross','InlineSetting3','Color | 255,255,255,255')",
        "setOption(prefix..'Gross','InlinePattern4','(?<=Per Hour:)-?\\$[0-9,]+')","setOption(prefix..'Gross','InlineSetting4','Color | 255,255,255,255')",
        "taxColor=marketTax>0 and '244,138,138,255' or '145,152,164,255'",
        "setOption(prefix..'Gross','InlinePattern5','(?<=Tax:)-?\\$[0-9,]+')","setOption(prefix..'Gross','InlineSetting5','Color | '..taxColor)",
        "setOption(prefix..'Window','Text','')","setOption(prefix..'Chance','Text','')",
        "if certainty~='' then actionText=actionText..' '..certainty end",
        'bufferRate=priceVaries and 0.05 or 0.0','math.ceil(fallbackPrice*quantity*(1.0+bufferRate))',
        'statusText(fallbackWindow,fallbackLeave)',
        'CurrentCycleReachable','CurrentCycleLeaveDeadlineAt','CurrentCycleSafetyMarginSeconds','NextCycleOrdinal','formatCurrentCycleTooltip','opportunityStatePrefix',
        'homeNextCycleAction','groupByOrdinal','bestNextRestockArrival','highest-overlap interval',
        "math.floor((number(group.bestStart)+number(group.bestEnd))/2)",'group.lateSellout','Window opens:',
        'formatSleepingRestockTooltip',"'Restocks in ~'",
        "'Collecting Data: See Weav3r'",
        'WindowDataQuality','WindowDataQualityReason','formatCollectingTooltip',"'Collecting Data: See Weav3r'"
    )) {
        if (-not $presenter.Contains($token)) { Fail "CardPresenter.lua missing '$token'." }
    }
    foreach ($forbidden in @(
        "' ['..chancePercent",
        "' ['..string.format('%.0f%%'",
        "'SAFE - EN ROUTE'",
        "'BEST - EN ROUTE'",
        "'NEXT RESTOCK WITHIN FLIGHT'",
        "'Safe Hit Window Open'",
        "'Safe window closed'",
        "'Leave Now to hit.'",
        "local quantity=quantityFromTooltip(humanTooltip)",
        "/ea x",
        "setOption(prefix..'Chance','Text',certainty)"
    )) {
        if ($presenter.Contains($forbidden)) { Fail "CardPresenter.lua retains obsolete/cluttered status token '$forbidden'." }
    }
    if ($presenter.Contains("setOption(name,'ToolTipHidden'")) { Fail 'CardPresenter.lua must not dynamically mutate ToolTipHidden; empty tooltip text owns visibility on the target host.' }
    if ($presenter -match '(?i)https?://|Invoke-RestMethod|curl|RunCommand|LaunchItemViewer') { Fail 'CardPresenter.lua must remain presentation-only and local.' }
    foreach ($token in @(
        'Get-CurrentCycleDeparturePlan',
        'CurrentCycleReachable',
        'CurrentCycleLeaveDeadlineAt',
        'CurrentCycleSafetyMarginSeconds',
        'NextCycleOrdinal',
        '-ActiveSelloutEstimateAt ([long]$liveProjection.activeSelloutEstimateAt)',
        '-SafetyMarginFraction 0.05',
        '$medianAvailable = Get-StableWindowMedian',
        'Test-WindowBoundaryQuality','WindowDataQuality','Collecting Data: See Weav3r',
        "'sleeping_oos'",'Do not read cycle evidence or build recurring probability geometry',
        'MaximumOrdinal = 1','immediately next cycle',
        'Scenario 1 is fully resolved from the direct current cycle','Only an unreachable current cycle or an OOS market needs next-restock'
    )) {
        if (-not $windowRefiner.Contains($token)) { Fail "WindowPlanRefiner.ps1 missing current-cycle deadline token '$token'." }
    }

    foreach ($token in @(
        'Get-RecurringScenarioModel','safeStartAt = $lateRestockAt','safeEndAt = $earlySelloutAt','MinimumSafeWindowSeconds = 60L',
        'bestProbability','Convert-WindowPlanMachineText','Select-WindowPlanGroup','WP2:',
        '$RuntimeCycleFile','$SeedCycleFile','MaximumSamples = 48','$cycleParts','$phaseCode','restockDelaySeconds','availabilitySeconds',
        'MaximumOrdinal = 1',"'sleeping_oos'",'Do not deserialize cycle rows or build WP2 probability geometry',
        'Get-WindowCycleLineKey','Do not build fallback recurring geometry for live stock',
        'Test-WindowPriceVaries','cycleAnalytics','foreignPrice','currentForeignPrice','lastForeignPrice','priceEvents','PV1#','PV0#'
    )) {
        if (-not $windowPlan.Contains($token)) { Fail "WindowPlan.ps1 missing '$token'." }
    }
    if ($windowPlan.Contains('WP1:')) { Fail 'WindowPlan.ps1 retains retired WP1 timeline format.' }
    if ($windowPlan -match '(?i)https?://|Invoke-RestMethod|Invoke-WebRequest|curl\.exe') { Fail 'WindowPlan.ps1 must remain local-only.' }
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($windowPlanPath,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "WindowPlan.ps1 parse error: $($parseError.Message)" }

    $opportunityAt=$wrapper.IndexOf('Invoke-FailSoftScript -Path $OpportunityState',[System.StringComparison]::Ordinal)
    $windowAt=$wrapper.IndexOf('Invoke-FailSoftScript -Path $WindowPlan',[System.StringComparison]::Ordinal)
    $filterAt=$wrapper.IndexOf('if (Test-Path -LiteralPath $FilterState)',[System.StringComparison]::Ordinal)
    if ($opportunityAt -lt 0 -or $windowAt -le $opportunityAt -or $filterAt -le $windowAt) { Fail 'RunUpdate must project WindowPlan after OpportunityState and before FilterState/final UI publication/heartbeat.' }

    foreach ($token in @(
        "if (`$null -ne `$travelContext -and [bool](Get-OptimalProperty `$travelContext 'filterActive')) { `$fixedCountry = [string](Get-OptimalProperty `$travelContext 'destinationCountryId') }",
        "if (-not [string]::IsNullOrWhiteSpace(`$fixedCountry) -and `$countryId -ne `$fixedCountry) { continue }",
        'Get-OpportunityEligibleEvidenceKeys',
        'Get-OptimalEvidence -WantedKeys $eligibleEvidenceKeys -SkipObservations',
        'displayTripBands',
        'showProfitableOnly',
        'Get-OpportunityRestockSummary',
        "forecastMode='sleeping_oos'",
        '$wakeAt=$earlyRestockAt-600L',
        '$focusMarker=Read-OpportunityFocusMarker'
    )) {
        if (-not $opportunity.Contains($token)) { Fail "OpportunityState outbound destination filter missing '$token'." }
    }
}

if ($errors.Count -gt 0) {
    foreach ($error in $errors) { Write-Host "FAIL: $error" -ForegroundColor Red }
    Write-Host "Compact trade-card validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Compact trade-card current/next-cycle and collecting-data validation passed.' -ForegroundColor Green
Write-Host 'In Torn, current stock uses a 5% sellout safety deadline; otherwise only the immediate next restock exposes Window Open/Best/Closes or Safe Hit state.'
exit 0
