$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$presenterPath = Join-Path $ProjectRoot '@Resources\Scripts\CardPresenter.lua'
$opportunityPath = Join-Path $ProjectRoot '@Resources\Scripts\OpportunityState.ps1'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($iniPath,$presenterPath,$opportunityPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing compact-card file: $path" }
}
if ($errors.Count -eq 0) {
    $ini = Get-Content -LiteralPath $iniPath -Raw
    $presenter = Get-Content -LiteralPath $presenterPath -Raw
    $opportunity = Get-Content -LiteralPath $opportunityPath -Raw

    foreach ($token in @('[MeasureCardPresenter]','CardPresenter.lua','StateFile=#@#Generated\state.kv')) {
        if (-not $ini.Contains($token)) { Fail "TravelAssistant.ini missing compact-card token '$token'." }
    }
    $stateAt = $ini.IndexOf('[MeasureState]',[System.StringComparison]::Ordinal)
    $presenterAt = $ini.IndexOf('[MeasureCardPresenter]',[System.StringComparison]::Ordinal)
    if ($stateAt -lt 0 -or $presenterAt -le $stateAt) { Fail 'MeasureCardPresenter must update after MeasureState so it formats the already sorted/filtered visible rows.' }

    foreach ($token in @(
        'removeCountrySuffix','rowCountryAndTravel','liveTravelRemainingSeconds','TravelDestinationCountryId','TravelArrivalAt','TravelTimeLeft','TravelContextLastSuccessAt','os.time()',
        "travelState == 'traveling'","destinationId == countryId","return formatDuration(remaining) .. ' left'",
        "setOption(prefix..'Window','FontColor','#Muted#')",
        'isDurationOnly','if isDurationOnly(window) then window = '''' end',
        'quantityFromTooltip','buyPriceFromVisibleText','math.ceil(buyPrice * quantity * 1.05)',
        "equation = equation .. ' x'", "' = ' .. formatMoney(totalProfit)",
        "'Take: '..formatMoney(take)",'Purchase cash required plus a 5% buffer',
        'statusText(window,leave)','setOption(prefix..''Name'',''ToolTipText'','''')'
    )) {
        if (-not $presenter.Contains($token)) { Fail "CardPresenter.lua missing '$token'." }
    }
    if ($presenter -match '(?i)https?://|Invoke-RestMethod|curl|RunCommand|LaunchItemViewer') { Fail 'CardPresenter.lua must remain presentation-only and local.' }

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
Write-Host 'Compact trade-card presentation validation passed.' -ForegroundColor Green
Write-Host 'Flight/countdown time occupies the muted left slot only; bare duration WindowText is suppressed from the actionable status field.'
exit 0
