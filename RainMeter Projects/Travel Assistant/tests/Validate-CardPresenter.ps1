$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$presenterPath = Join-Path $ProjectRoot '@Resources\Scripts\CardPresenter.lua'
$opportunityPath = Join-Path $ProjectRoot '@Resources\Scripts\OpportunityState.ps1'
$windowPlanPath = Join-Path $ProjectRoot '@Resources\Scripts\WindowPlan.ps1'
$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($iniPath,$presenterPath,$opportunityPath,$windowPlanPath,$wrapperPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing compact-card/window file: $path" }
}
if ($errors.Count -eq 0) {
    $ini = Get-Content -LiteralPath $iniPath -Raw
    $presenter = Get-Content -LiteralPath $presenterPath -Raw
    $opportunity = Get-Content -LiteralPath $opportunityPath -Raw
    $windowPlan = Get-Content -LiteralPath $windowPlanPath -Raw
    $wrapper = Get-Content -LiteralPath $wrapperPath -Raw

    foreach ($token in @('[MeasureCardPresenter]','CardPresenter.lua','StateFile=#@#Generated\ui-state.kv')) {
        if (-not $ini.Contains($token)) { Fail "TravelAssistant.ini missing compact-card token '$token'." }
    }
    $stateAt = $ini.IndexOf('[MeasureState]',[System.StringComparison]::Ordinal)
    $presenterAt = $ini.IndexOf('[MeasureCardPresenter]',[System.StringComparison]::Ordinal)
    if ($stateAt -lt 0 -or $presenterAt -le $stateAt) { Fail 'MeasureCardPresenter must update after MeasureState.' }

    # Keep this PowerShell validator ASCII-only for Windows PowerShell 5.1. The
    # Unicode info glyph is validated indirectly through safeInfo + tooltip behavior.
    foreach ($token in @(
        'removeCountrySuffix','rowCountryAndTravel','liveTravelRemainingSeconds','TravelDestinationCountryId','TravelArrivalAt','TravelTimeLeft','TravelContextLastSuccessAt','os.time()',
        'parseWindowPlan','parsePriceVarianceEnvelope','probabilityAt','staysAboveThresholdUntil','groupMode','liveWindowAction','nextBetterBestBefore',
        'WP2:','PV([01])','group.safeEnd-group.safeStart>=60','group.bestProbability>0.5','currentProbability>0.5',
        "'SAFE - LEAVE '","'SAFE - LEAVE BEFORE '","'BEST - LEAVE NOW'", "'BEST - LEAVE '",
        'Safe formula: max(restock starts) -> min(sellout ends)','Best formula: completed-cycle overlap / usable cycle count',
        'Early Restock: ','Late Restock: ','Safe Window: ','Best Hit Window: ',
        'configureWindowTooltipMeter','ToolTipHidden','ToolTipTitle','ToolTipWidth','SolidColor','safeInfo',
        "'InlinePattern'", "'InlinePattern2'", '/ea x[0-9]+ =', 'Color | 255,255,255,255',
        'quantityFromTooltip','buyPriceFromVisibleText','bufferRate=priceVaries and 0.05 or 0.0','math.ceil(buyPrice*quantity*(1.0+bufferRate))',
        "'Take: '..formatMoney(take)",'Purchase cash required plus a 5% buffer because retained foreign price has varied','Exact purchase cash; retained foreign price has not varied',
        'statusText(fallbackWindow,fallbackLeave)'
    )) {
        if (-not $presenter.Contains($token)) { Fail "CardPresenter.lua missing '$token'." }
    }
    if ($presenter -match '(?i)https?://|Invoke-RestMethod|curl|RunCommand|LaunchItemViewer') { Fail 'CardPresenter.lua must remain presentation-only and local.' }

    foreach ($token in @(
        'Get-RecurringScenarioModel','safeStartAt = $lateRestockAt','safeEndAt = $earlySelloutAt','MinimumSafeWindowSeconds = 60L',
        'bestProbability','Convert-WindowPlanMachineText','Select-WindowPlanGroup','WP2:',
        '$RuntimeCycleFile','$SeedCycleFile','MaximumSamples = 48','$cycleParts','$phaseCode','restockDelaySeconds','availabilitySeconds',
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
        "if (-not [string]::IsNullOrWhiteSpace(`$fixedCountry) -and `$countryId -ne `$fixedCountry) { continue }"
    )) {
        if (-not $opportunity.Contains($token)) { Fail "OpportunityState outbound destination filter missing '$token'." }
    }
}

if ($errors.Count -gt 0) {
    foreach ($error in $errors) { Write-Host "FAIL: $error" -ForegroundColor Red }
    Write-Host "Compact trade-card validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Compact trade-card safe/best window validation passed.' -ForegroundColor Green
Write-Host 'Departure text has a persistent tooltip hitbox; Safe rows expose an info anchor, profit equation punctuation is white, and fixed-price items use exact Take cash.'
exit 0