$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$presenterPath = Join-Path $ProjectRoot '@Resources\Scripts\CardPresenter.lua'
$opportunityPath = Join-Path $ProjectRoot '@Resources\Scripts\OpportunityState.ps1'
$windowPlanPath = Join-Path $ProjectRoot '@Resources\Scripts\WindowPlan.ps1'
$windowRefinerPath = Join-Path $ProjectRoot '@Resources\Scripts\WindowPlanRefiner.ps1'
$multiCycleBridgePath = Join-Path $ProjectRoot '@Resources\Scripts\MultiCycleChanceBridge.ps1'
$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($iniPath,$presenterPath,$opportunityPath,$windowPlanPath,$windowRefinerPath,$multiCycleBridgePath,$wrapperPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing compact-card/window file: $path" }
}
if ($errors.Count -eq 0) {
    $ini = Get-Content -LiteralPath $iniPath -Raw
    $presenter = Get-Content -LiteralPath $presenterPath -Raw
    $opportunity = Get-Content -LiteralPath $opportunityPath -Raw
    $windowPlan = Get-Content -LiteralPath $windowPlanPath -Raw
    $windowRefiner = Get-Content -LiteralPath $windowRefinerPath -Raw
    $multiCycleBridge = Get-Content -LiteralPath $multiCycleBridgePath -Raw
    $wrapper = Get-Content -LiteralPath $wrapperPath -Raw

    foreach ($token in @('[MeasureCardPresenter]','CardPresenter.lua','StateFile=#@#Generated\ui-state.kv')) {
        if (-not $ini.Contains($token)) { Fail "TravelAssistant.ini missing compact-card token '$token'." }
    }
    $stateAt = $ini.IndexOf('[MeasureState]',[System.StringComparison]::Ordinal)
    $presenterAt = $ini.IndexOf('[MeasureCardPresenter]',[System.StringComparison]::Ordinal)
    if ($stateAt -lt 0 -or $presenterAt -le $stateAt) { Fail 'MeasureCardPresenter must update after MeasureState.' }

    # Keep this PowerShell validator ASCII-only for Windows PowerShell 5.1.
    foreach ($token in @(
        'removeCountrySuffix','rowCountryAndTravel','countryTravelSeconds','liveTravelRemainingSeconds','TravelDestinationCountryId','TravelArrivalAt','TravelTimeLeft','TravelContextLastSuccessAt','os.time()',
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
        "state[projectedPrefix..'TotalCostValue']","state[projectedPrefix..'MakeValue']",
        "state[projectedPrefix..'MarketValueValue']","state[projectedPrefix..'ProfitEachValue']",
        "state[projectedPrefix..'GrossSaleValue']","state[projectedPrefix..'MarketTaxValue']","state[projectedPrefix..'MarketFeePercent']",
        "local face='Nirmala UI Semilight'",
        "setOption(prefix..'Name','X',123)","setOption(prefix..'Name','FontSize',12)",
        "setOption(prefix..'Price','X',123)","setOption(prefix..'Price','W',230)","setOption(prefix..'Price','FontSize',12)",
        "setOption(prefix..'Make','W',142)","setOption(prefix..'Make','FontSize',14)",
        "setOption(prefix..'Leave','X',123)","setOption(prefix..'Leave','W',263)","setOption(prefix..'Leave','FontSize',9)",
        "setOption(prefix..'Name','Text',itemName)","setOption(prefix..'Name','ToolTipText','')","setOption(prefix..'Name','FontColor','0,0,0,0')",
        "unitCostText=unitCost>0 and formatMoney(unitCost) or '?'",
        "setOption(prefix..'Price','Text',itemName)",
        "setOption(prefix..'Price','InlinePattern','')","setOption(prefix..'Price','InlinePattern2','')","setOption(prefix..'Price','InlinePattern3','')",
        "state[projectedPrefix..'PriceColor']",
        "setOption(prefix..'Take','Text','')","setOption(prefix..'Take','FontColor','0,0,0,0')",
        "setOption(prefix..'Price','ToolTipText','')","setOption(prefix..'Take','ToolTipText','')","setOption(prefix..'Make','ToolTipText','')",
        "setOption(prefix..'Make','Text',primaryMetricKnown and (formatSignedMoney(primaryMetric)..(primaryUsesHour and '/hr' or '')) or '?/hr')",
        "setOption(prefix..'Make','FontColor',primaryMetricKnown and profitColor(primaryMetric) or '#Muted#')",
        "SKIN:GetVariable('OpportunityRenderMode',trim(state.OpportunitySortMode))","local primaryUsesHour=(renderMode=='profit_per_hour')",
        "formatSignedMoney","profitColor",
        "setOption(prefix..'DetailEachLabel','Text','Each')","setOption(prefix..'DetailEachLabel','SolidColor','#Border#')",
        "setOption(prefix..'Gross','Text','MV')","setOption(prefix..'DetailEachGrossValue','Text',formatMoney(mv))",
        "setOption(prefix..'DetailEachNet','Text',primaryUsesHour and 'Net' or '$/hr')","setOption(prefix..'DetailEachNetValue','Text',alternateKnown and formatSignedMoney(eachAlternate) or '?')",
        "setOption(prefix..'DetailEachTax','Text',marketTaxRate>0 and (tostring(marketTaxRate)..'% Tax') or '')","setOption(prefix..'DetailEachTaxValue','Text',marketTaxRate>0 and formatMoney(taxEach) or '')",
        "local flightSeconds=countryTravelSeconds(state,country,travel)","local roundTripHours=(flightSeconds>0) and ((flightSeconds*2)/3600.0) or 0",
        "local eachFlightProfitHour=(roundTripHours>0) and (each/roundTripHours) or 0","local totalFlightProfitHour=(roundTripHours>0) and (make/roundTripHours) or 0",
        "setOption(prefix..'DetailEachProfitHour','Text','Price')","setOption(prefix..'DetailEachPriceValue','Text',unitCostText)",
        "setOption(prefix..'DetailTotalLabel','Text','Total')","setOption(prefix..'DetailTotalLabel','SolidColor','#Border#')",
        "setOption(prefix..'DetailTotal','Text','MV')","setOption(prefix..'DetailTotalGrossValue','Text',formatMoney(grossSale))",
        "setOption(prefix..'DetailTotalNet','Text',primaryUsesHour and 'Net' or '$/hr')","setOption(prefix..'DetailTotalNetValue','Text',alternateKnown and formatSignedMoney(totalAlternate) or '?')",
        "setOption(prefix..'DetailTotalTax','Text',marketTaxRate>0 and (tostring(marketTaxRate)..'% Tax') or '')","setOption(prefix..'DetailTotalTaxValue','Text',marketTaxRate>0 and formatMoney(marketTax) or '')",
        "setOption(prefix..'DetailTotalProfitHour','Text','Price')","setOption(prefix..'DetailTotalPriceValue','Text',totalCostText)",
        "setOption(prefix..'DetailEachNetValue','FontColor',eachAlternateColor)","setOption(prefix..'DetailTotalNetValue','FontColor',totalAlternateColor)",
        "setOption(prefix..'DetailEachPriceValue','FontColor',priceColor)","setOption(prefix..'DetailTotalPriceValue','FontColor','#ToggleIdle#')",
        "setOption(prefix..'DetailEachTaxValue','FontColor',taxColor)","setOption(prefix..'DetailTotalTaxValue','FontColor',taxColor)",
        "setOption(prefix..'DetailEachNet','StringAlign','LeftCenter')","setOption(prefix..'DetailTotalNet','StringAlign','LeftCenter')","setOption(prefix..'DetailEachNetValue','StringAlign','RightCenter')","setOption(prefix..'DetailTotalNetValue','StringAlign','RightCenter')",
        "setOption(prefix..'DetailEachProfitHour','StringAlign','LeftCenter')","setOption(prefix..'DetailTotalProfitHour','StringAlign','LeftCenter')",
        "setOption(prefix..'DetailEachProfitHour','FontSize',9)","setOption(prefix..'DetailTotalProfitHour','FontSize',9)","setOption(prefix..'DetailEachGrossValue','FontSize',9)","setOption(prefix..'DetailTotalGrossValue','FontSize',9)",
        "setOption(prefix..'DetailEachTax','StringAlign','LeftCenter')","setOption(prefix..'DetailTotalTax','StringAlign','LeftCenter')","setOption(prefix..'DetailEachTaxValue','StringAlign','RightCenter')","setOption(prefix..'DetailTotalTaxValue','StringAlign','RightCenter')",
        "local detailLabelHeight=32",
        "setOption(prefix..'DetailToggle','W',24)","setOption(prefix..'DetailToggle','H',23)",
        "setOption(prefix..'Graph','X',519)","setOption(prefix..'Graph','W',24)","setOption(prefix..'Graph','H',23)",
        "setOption(prefix..'Window','Text','')","setOption(prefix..'Chance','Text','')",
        "local function setCenteredChance(prefix,value)",
        "setOption(prefix..'Chance','X',276)",
        "setOption(prefix..'Chance','W',72)",
        "setOption(prefix..'Chance','StringAlign','CenterTop')",
        "setOption(prefix..'Leave','W',122)",
        "SKIN:Bang('!ShowMeter',prefix..'Chance')",
        "setCenteredChance(prefix,certainty)",
        "totalCost=(fallbackPrice>0 and quantity>0) and (fallbackPrice*quantity) or 0",
        'statusText(fallbackWindow,fallbackLeave)',
        "window:lower():find('collecting data',1,true)~=nil then return window",
        'CurrentCycleReachable','CurrentCycleLeaveDeadlineAt','CurrentCycleSafetyMarginSeconds','NextCycleOrdinal','formatCurrentCycleTooltip','opportunityStatePrefix',
        'homeNextCycleAction','groupByOrdinal','bestNextRestockArrival','highest-overlap interval',
        "math.floor((number(group.bestStart)+number(group.bestEnd))/2)",'group.lateSellout','Window opens:',
        "'Departure Window: OPEN NOW'","'Safe Departure Window: closed'","'Safe Departure Window: NOW -> '","'Window Closes: '",
        'if earliestDeparture>now then','if bestDeparture>now then','if lateRestockDeparture>now then',
        'formatSleepingRestockTooltip',"'Restocks in ~'",
        "'Collecting Data: See Weav3r'",
        'WindowDataQuality','WindowDataQualityReason','formatCollectingTooltip',"'Collecting Data: See Weav3r'",
        'currentStockSafetyAction',"'CurrentStockSafetyEligible'","'CurrentStockSafetyMode'","'CurrentStockSafetyMinimumHoldHorizonSeconds'",
        "'CurrentStockSafetyRunwaySeconds'","'CurrentStockSafetyMarginSeconds'","'Verified-stock holding fallback'",
        "holding and 'STOCK HOLDING' or 'Safe Window Open'","'This fallback is used only when the primary window guidance is non-informative.'",
        "'No hit percentage is fabricated; current-cycle, Safe/Best, and multi-cycle evidence retain priority.'",
        'multiCycleChanceAction',"'MultiCycleChanceEligible'","'MultiCycleChanceProbability'","'MultiCycleTargetProbability'",
        "'MultiCycleDutyCycleProbability'","'MultiCycleArrivalCycleRatio'","'MultiCycleExpectedFullCycles'","'MultiCyclePhaseStdDevSeconds'",
        "'Multi-cycle arrival forecast'","'Modeled Chance to Hit: '","return 'Chance to hit:',chancePercent(probability)",
        "'This is a modeled arrival probability, not a Safe/Best departure-window guarantee.'",
        'averageOosFallbackAction',"state[statePrefix..'LastObservedOosAt']","state[statePrefix..'RestockAverageDelaySeconds']",
        "state[statePrefix..'RestockLifetimeLongestDelaySeconds']","state[statePrefix..'RestockSampleCount']",
        'samples<2',"local averageRestockAt=lastOosAt+averageDelay","local averageLeaveAt=averageRestockAt-flightSeconds",
        "'AVG LEAVE IN '","'AVG LEAVE NOW'","'AVG RESTOCK LATE'","return 'WAIT DATA',''",
        "'Average-only OoS timing fallback'","'No Chance to Hit percentage is assigned to this rough timing fallback.'",
        "'Live/current-cycle, Safe/Best, or multi-cycle guidance automatically replaces it.'"
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
        "setOption(prefix..'Chance','Text',certainty)",
        "setOption(prefix..'Take','Text','Take: ",
        "setOption(prefix..'Make','Text','Make: ",
        "bufferRate=priceVaries",
        "Each | MV:","Total | MV:",
        "Each | Gross:","Total | Gross:","setOption(prefix..'Take','Text','| '..totalCostText)",
        "setOption(prefix..'Name','ToolTipText','Item name')",
        "setOption(prefix..'Price','ToolTipText','Item | foreign unit cost | full-load purchase cost')",
        "setOption(prefix..'Make','ToolTipText','After-tax total net profit for the full load.')",
        "setOption(prefix..'Gross','ToolTipText','Per item: declared MV | selected tax | after-tax net profit')",
        "setOption(prefix..'DetailTotal','ToolTipText','Full load: total declared MV | selected tax | after-tax net profit')"
    )) {
        if ($presenter.Contains($forbidden)) { Fail "CardPresenter.lua retains obsolete/cluttered status token '$forbidden'." }
    }
    if ($presenter.Contains("setOption(name,'ToolTipHidden'")) { Fail 'CardPresenter.lua must not dynamically mutate ToolTipHidden; empty tooltip text owns visibility on the target host.' }
    foreach($token in @(
        "if window:lower()=='in stock' then window='In stock' end",
        "if leave:lower()=='in stock' then leave='In stock' end",
        "if leave:lower()=='en route' then leave='' end",
        "local function projectedArrivalCertainty(state,statePrefix)",
        "ImmediateArrivalProbabilityValue",
        "MultiCycleChanceProbability",
        "only show a probability aligned to actual",
        "certainty=projectedArrivalCertainty(state,projectedPrefix)",
        "local sleepingOosValid=(",
        "lastObservedOosAt>0",
        "(activeRestockAt<=0 or activeRestockAt<=lastObservedOosAt)",
        "A later observed restock permanently supersedes",
        "if sleepingOosValid then"
    )){
        if(-not$presenter.Contains($token)){Fail "CardPresenter latest-phase OoS gate missing '$token'."}
    }
    if ($presenter -match '(?i)https?://|Invoke-RestMethod|curl|RunCommand|LaunchItemViewer') { Fail 'CardPresenter.lua must remain presentation-only and local.' }
    if ($presenter.Contains("state[projectedPrefix..'ElapsedSeconds']") -and $presenter.Contains('FlightProfitHour')) { Fail 'Expanded flight $/hr must use round-trip flight duration, not opportunity elapsed/wait time.' }
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
        'Get-StableRecurringProbabilityAt','ImmediateArrivalAt','ImmediateArrivalProbabilityValue','ImmediateArrivalProbabilitySource',
        'Get-StableCurrentCycleArrivalProbability','-ObservationAt $sourceTimestamp',
        'Get-LiveDepletionArrivalProbability','CurrentCycleLiveProbability','current_cycle_live_depletion','current_cycle_conditional_survival',
        'Get-CurrentStockSafetyProjection','CurrentStockSafetyEligible','CurrentStockSafetyMode','CurrentStockSafetyMinimumHoldHorizonSeconds','CurrentStockSafetyGuardedUnitsPerHour',
        '-KnownSelloutEstimateAt ([long]$liveProjection.activeSelloutEstimateAt)',
        '[long]$MinimumFarHorizonSeconds=21600L','[double]$FarHorizonArrivalMultiplier=2.0',
        '[long]$MinimumLowDepletionEvidenceSpanSeconds=900L',"'low-depletion-hold'","'far-sellout'",
        "'current_stock_safe'","'STOCK HOLDING'","'ProbabilityValue']='-1'",
        "'sleeping_oos'",'Get-WindowObservedPhase','phaseInfo.unresolvedOos',
        'Test-WindowStaleSourceCanUseRecurringModel',
        'Staleness invalidates current-stock claims, not previously verified phase',
        'no verified phase anchor is available for forecast-only geometry',
        'Sleeping OoS is only a performance hint','phase_invalidated',
        'MaximumOrdinal = 1','immediately next cycle',
        'Scenario 1 is fully resolved from the direct current cycle','Only an unreachable current cycle or an OOS market needs next-restock',
        "'LastObservedOosAt'",'LastObservedOosAt is the unresolved current OoS phase',
        'preceding OoS timing is suppressed',
        "'WP2:'","'PV1#'","'PV0#'"
    )) {
        if (-not $windowRefiner.Contains($token)) { Fail "WindowPlanRefiner.ps1 missing current-cycle deadline token '$token'." }
    }

    $safeFallbackAt=$presenter.IndexOf("if dataQuality=='current_stock_safe' then",[System.StringComparison]::Ordinal)
    $collectingAt=$presenter.IndexOf("if dataQuality=='collecting' then",[System.StringComparison]::Ordinal)
    if($safeFallbackAt -lt 0 -or $collectingAt -le $safeFallbackAt){
        Fail 'Current-stock fallback presentation must sit immediately before the remaining Collecting Data branch.'
    }
    $collectingMultiAt=$presenter.IndexOf("local multiAction,multiChance,multiTooltip=multiCycleChanceAction(state,statePrefix,flightSeconds,now)",$collectingAt,[System.StringComparison]::Ordinal)
    $collectingStockAt=$presenter.IndexOf("local stockAction,stockChance,stockTooltip=currentStockSafetyAction(state,statePrefix,now)",$collectingMultiAt,[System.StringComparison]::Ordinal)
    $collectingAvgAt=$presenter.IndexOf("local avgAction,avgChance,avgTooltip=averageOosFallbackAction(state,statePrefix,currentStock,flightSeconds,now)",$collectingStockAt,[System.StringComparison]::Ordinal)
    if($collectingMultiAt -lt 0 -or $collectingStockAt -le $collectingMultiAt -or $collectingAvgAt -le $collectingStockAt){
        Fail 'Collecting-state fallback authority must remain multi-cycle -> verified-stock holding -> average-OoS timing.'
    }
    foreach($snippet in @(
        "local multiAction,multiChance,multiTooltip=multiCycleChanceAction(state,statePrefix,flightSeconds,now)",
        "local avgAction,avgChance,avgTooltip=averageOosFallbackAction(state,statePrefix,currentStock,flightSeconds,now)",
        "lowerLegacy=='next cycle unavailable'",
        "if avgAction~=nil then return avgAction,avgChance,avgTooltip end"
    )){
        if(-not$presenter.Contains($snippet)){Fail "Average OoS fallback authority contract missing '$snippet'."}
    }
    $firstMulti=$presenter.IndexOf("local multiAction,multiChance,multiTooltip=multiCycleChanceAction(state,statePrefix,flightSeconds,now)",[System.StringComparison]::Ordinal)
    $firstAvg=$presenter.IndexOf("local avgAction,avgChance,avgTooltip=averageOosFallbackAction(state,statePrefix,currentStock,flightSeconds,now)",[System.StringComparison]::Ordinal)
    if($firstMulti -lt 0 -or $firstAvg -le $firstMulti){Fail 'Average OoS fallback must remain below the multi-cycle forecast authority.'}
    foreach($token in @(
        '$PendingCycleFile = Join-Path $RuntimeDir ''cycles.pending.jsonl''',
        '$PendingObservationFile = Join-Path $RuntimeDir ''observations.pending.jsonl''',
        'Read-WindowCyclesForKeys -Paths @($SeedCycleFile,$RuntimeCycleFile,$PendingCycleFile)',
        '$pendingObservationMap=Read-WindowObservationsForKeys -Path $PendingObservationFile',
        'raw cycles {0}, eligible {1}',
        'Compute direct current-stock fallback telemetry for every fresh positive-stock',
        'Only an already-non-informative producer state may be replaced directly here.',
        '[string]$state[$prefix+''WindowDataQuality''] -eq ''collecting''',
        '[bool](Get-WindowProperty $safety ''eligible'')',
        '$state[$prefix+''WindowDataQuality'']=''current_stock_safe''',
        '$state[$prefix+''WindowText'']=''STOCK HOLDING''',
        '$state[$prefix+''ProbabilityValue'']=''-1''',
        'continue'
    )){
        if(-not$windowRefiner.Contains($token)){
            Fail "Stock-holding fallback must remain producer-gated from non-informative state without a fabricated probability; missing '$token'."
        }
    }

    foreach ($token in @(
        '. $StochasticScript -SkipMain',
        'Get-MCWeightedTimingDiagnostics',
        'Get-MCArrivalCandidate',
        'Get-MCMultiCycleChance',
        '[double]$MinimumFlightCycleRatio = 2.0',
        '[int]$SimulationCount = 256',
        '-EnableAdaptiveGrid $false',
        "'MultiCycleChanceEligible'",
        "'MultiCycleChanceProbability'",
        "'MultiCycleDutyCycleProbability'",
        "'MultiCycleArrivalCycleRatio'",
        "'MultiCyclePhaseStdDevSeconds'"
    )) {
        if (-not $multiCycleBridge.Contains($token)) { Fail "MultiCycleChanceBridge.ps1 missing production fallback token '$token'." }
    }
    if ($multiCycleBridge -match '(?i)https?://|Invoke-RestMethod|Invoke-WebRequest|curl\.exe') { Fail 'MultiCycleChanceBridge.ps1 must remain local-only/network-free.' }

    foreach ($token in @(
        'Get-RecurringScenarioModel','safeStartAt = $lateRestockAt','safeEndAt = $earlySelloutAt','MinimumSafeWindowSeconds = 60L',
        'bestProbability','Convert-WindowPlanMachineText','Select-WindowPlanGroup',
        '$RuntimeCycleFile','$SeedCycleFile','MaximumSamples = 48','$cycleParts','$phaseCode','restockDelaySeconds','availabilitySeconds',
        'MaximumOrdinal = 1','Get-WindowCycleLineKey','Test-WindowPriceVaries','cycleAnalytics','foreignPrice',
        'currentForeignPrice','lastForeignPrice','priceEvents',
        "& (Join-Path `$PSScriptRoot 'WindowPlanRefiner.ps1') -Now `$Now"
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
    $bridgeAt=$wrapper.IndexOf('Invoke-FailSoftScript -Path $MultiCycleChanceBridge',[System.StringComparison]::Ordinal)
    $filterAt=$wrapper.IndexOf('if (Test-Path -LiteralPath $FilterState)',[System.StringComparison]::Ordinal)
    if ($opportunityAt -lt 0 -or $windowAt -le $opportunityAt -or $bridgeAt -le $windowAt -or $filterAt -le $bridgeAt) { Fail 'RunUpdate must project WindowPlan then MultiCycleChanceBridge after OpportunityState and before FilterState/final UI publication/heartbeat.' }

    foreach ($token in @(
        "if (`$null -ne `$travelContext -and [bool](Get-OptimalProperty `$travelContext 'filterActive')) { `$fixedCountry = [string](Get-OptimalProperty `$travelContext 'destinationCountryId') }",
        "if (-not [string]::IsNullOrWhiteSpace(`$fixedCountry) -and `$countryId -ne `$fixedCountry) { continue }",
        'Get-OpportunityEligibleEvidenceKeys',
        'Get-OptimalEvidence -WantedKeys $eligibleEvidenceKeys -SkipObservations',
        'displayTripBands',
        'showProfitableOnly',
        'Get-OpportunityRestockSummary',
        '$windowText = ''Opens in ''+(Format-OpportunityDuration ($windowStartAt-$Now))',
        'if ($travelState -eq ''traveling'' -and $outboundSeconds -gt 0) { $leaveText = '''' }',
        'Test-OpportunityUnresolvedOosPhase',
        '$unresolvedOos=Test-OpportunityUnresolvedOosPhase',
        'A later observed restock supersedes the preceding OoS',
        "forecastMode='sleeping_oos'",
        'Do not fall back to a preceding OoS anchor after any later restock',
        '$wakeAt=$earlyRestockAt-600L',
        "'LastObservedOosAt'"
    )) {
        if (-not $opportunity.Contains($token)) { Fail "OpportunityState outbound destination filter missing '$token'." }
    }
    foreach($retired in @(
        '$windowText = ''WINDOW ''+',
        '$windowText = ''WINDOW NOW''',
        '$leaveText = ''EN ROUTE'''
    )){
        if($opportunity.Contains($retired)){Fail "OpportunityState retains ambiguous/redundant card wording '$retired'."}
    }
}

if ($errors.Count -gt 0) {
    foreach ($failureItem in $errors) { Write-Host "FAIL: $failureItem" -ForegroundColor Red }
    Write-Host "Compact trade-card validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Compact trade-card current/next-cycle and collecting-data validation passed.' -ForegroundColor Green
Write-Host 'In Torn, current stock uses a 5% sellout safety deadline; otherwise only the immediate next restock exposes Window Open/Best/Closes or Safe Hit state.'
exit 0

