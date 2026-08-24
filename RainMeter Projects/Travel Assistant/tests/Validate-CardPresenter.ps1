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

    foreach ($token in @('[MeasureCardPresenter]','CardPresenter.lua','StateFile=#@#Generated\state.kv')) {
        if (-not $ini.Contains($token)) { Fail "TravelAssistant.ini missing compact-card token '$token'." }
    }
    $stateAt = $ini.IndexOf('[MeasureState]',[System.StringComparison]::Ordinal)
    $presenterAt = $ini.IndexOf('[MeasureCardPresenter]',[System.StringComparison]::Ordinal)
    if ($stateAt -lt 0 -or $presenterAt -le $stateAt) { Fail 'MeasureCardPresenter must update after MeasureState.' }

    foreach ($token in @(
        'removeCountrySuffix','rowCountryAndTravel','liveTravelRemainingSeconds','TravelDestinationCountryId','TravelArrivalAt','TravelTimeLeft','TravelContextLastSuccessAt','os.time()',
        'parseWindowPlan','probabilityAt','staysAboveThresholdUntil','groupMode','liveWindowAction','nextBetterBestBefore',
        'WP2:','group.safeEnd-group.safeStart>=60','group.bestProbability>0.5','currentProbability>0.5',
        "'SAFE - LEAVE '","'SAFE - LEAVE BEFORE '","'BEST - LEAVE NOW'", "'BEST - LEAVE '",
        'Safe formula: max(restock starts) -> min(sellout ends)','Best formula: completed-cycle overlap / usable cycle count',
        'Early Restock: ','Late Restock: ','Safe Window: ','Best Hit Window: ',
        'quantityFromTooltip','buyPriceFromVisibleText','math.ceil(buyPrice*quantity*1.05)',
        "'Take: '..formatMoney(take)",'Purchase cash required plus a 5% buffer',
        'statusText(fallbackWindow,fallbackLeave)'
    )) {
        if (-not $presenter.Contains($token)) { Fail "CardPresenter.lua missing '$token'." }
    }
    if ($presenter -match '(?i)https?://|Invoke-RestMethod|curl|RunCommand|LaunchItemViewer') { Fail 'CardPresenter.lua must remain presentation-only and local.' }

    foreach ($token in @(
        'Get-RecurringScenarioModel','safeStartAt = $lateRestockAt','safeEndAt = $earlySelloutAt','MinimumSafeWindowSeconds = 60L',
        'bestProbability','Convert-WindowPlanMachineText','Select-WindowPlanGroup','WP2:',
        '$RuntimeCycleFile','$SeedCycleFile','MaximumSamples = 48','$cycleParts','$phaseCode','restockDelaySeconds','availabilitySeconds'
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
    if ($opportunityAt -lt 0 -or $windowAt -le $opportunityAt -or $filterAt -le $windowAt) { Fail 'RunUpdate must project WindowPlan after OpportunityState and before FilterState/heartbeat.' }

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
Write-Host 'Safe windows use full empirical overlap with no confidence label; Best Hit uses live >50% support and advances after the opportunity is missed.'
exit 0
