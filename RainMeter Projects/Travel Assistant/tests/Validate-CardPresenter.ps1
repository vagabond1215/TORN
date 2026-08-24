$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$presenterPath = Join-Path $ProjectRoot '@Resources\Scripts\CardPresenter.lua'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($iniPath,$presenterPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing compact-card file: $path" }
}
if ($errors.Count -eq 0) {
    $ini = Get-Content -LiteralPath $iniPath -Raw
    $presenter = Get-Content -LiteralPath $presenterPath -Raw

    foreach ($token in @('[MeasureCardPresenter]','CardPresenter.lua','StateFile=#@#Generated\state.kv')) {
        if (-not $ini.Contains($token)) { Fail "TravelAssistant.ini missing compact-card token '$token'." }
    }
    $stateAt = $ini.IndexOf('[MeasureState]',[System.StringComparison]::Ordinal)
    $presenterAt = $ini.IndexOf('[MeasureCardPresenter]',[System.StringComparison]::Ordinal)
    if ($stateAt -lt 0 -or $presenterAt -le $stateAt) { Fail 'MeasureCardPresenter must update after MeasureState so it formats the already sorted/filtered visible rows.' }

    foreach ($token in @(
        'removeCountrySuffix','rowCountryAndTravel','TravelDestinationCountryId','TravelTimeLeft',
        'quantityFromTooltip','buyPriceFromVisibleText','math.ceil(buyPrice * quantity * 1.05)',
        "equation = equation .. ' x'", "' = ' .. formatMoney(totalProfit)",
        "'Take: '..formatMoney(take)",'Purchase cash required plus a 5% buffer',
        'statusText(window,leave)','setOption(prefix..''Name'',''ToolTipText'','''')'
    )) {
        if (-not $presenter.Contains($token)) { Fail "CardPresenter.lua missing '$token'." }
    }
    if ($presenter -match '(?i)https?://|Invoke-RestMethod|curl|RunCommand|LaunchItemViewer') { Fail 'CardPresenter.lua must remain presentation-only and local.' }
}

if ($errors.Count -gt 0) {
    foreach ($error in $errors) { Write-Host "FAIL: $error" -ForegroundColor Red }
    Write-Host "Compact trade-card validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Compact trade-card presentation validation passed.' -ForegroundColor Green
Write-Host 'Country stays on the flag tooltip; cards show item, per-item net x quantity = total net, flight/remaining time, window/leave state, certainty, and Take cash +5%.'
exit 0
