$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$optimizerPath = Join-Path $ProjectRoot '@Resources\Scripts\OptimalRoute.ps1'
$settingsPath = Join-Path $ProjectRoot '@Resources\Scripts\OpenOptimizerSettings.ps1'
$preferencesPath = Join-Path $ProjectRoot '@Resources\Scripts\FilterPreferences.ps1'
$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$countriesPath = Join-Path $ProjectRoot 'config\countries.json'
$baseSettingsPath = Join-Path $ProjectRoot 'config\settings.example.json'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($optimizerPath,$settingsPath,$preferencesPath,$wrapperPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing $(Split-Path $path -Leaf)."; continue }
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in $(Split-Path $path -Leaf): $($parseError.Message)" }
}

if (Test-Path -LiteralPath $optimizerPath) {
    $text=Get-Content -LiteralPath $optimizerPath -Raw
    foreach ($fn in @('Get-OptimalBarWaste','Test-OptimalWastePolicy','Get-OptimalArrivalForecast','Get-OptimalResaleSnapshot','Get-OptimalCountryPlan','Write-OptimalProjection')) {
        if ($text -notmatch ('(?m)^function\s+'+[regex]::Escape($fn)+'\s*\{')) { Fail "OptimalRoute.ps1 missing $fn." }
    }
    if ($text -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'OptimalRoute.ps1 must remain local-only.' }
    foreach ($token in @(
        "PSObject.Properties['average']",
        'marketValue=$mv',
        'use95PercentMarketValue',
        '-EnergyStackBypass',
        'energyWastePolicy',
        'nerveWastePolicy',
        'showProfitableOnly',
        'catalogActive',
        'legacy_removed',
        'availabilitySeconds',
        'restockDelaySeconds',
        'expectedTripProfit',
        "if (`$foreignPrice -le `$sellBasis) { '86,190,116,255' }",
        'pricingPriorityItemIds'
    )) {
        if (-not $text.Contains($token)) { Fail "Optimal route contract missing '$token'." }
    }
    foreach ($forbidden in @('itemMarketFeePercent','minimumProfitPerItem','minimumMarginPercent','LOW_MARGIN','UNPROFITABLE')) {
        if ($text.Contains($forbidden)) { Fail "Optimal route must not gate on legacy profitability token '$forbidden'." }
    }
}

if (Test-Path -LiteralPath $settingsPath) {
    $text=Get-Content -LiteralPath $settingsPath -Raw
    foreach ($token in @('Show profitable items only','Use 95% MV profit calculation','Energy Waste','Max Energy Loss','Nerve Waste','Max Nerve Loss','Allowed','Forbidden','Limited','Profile / API...','Ignore List...')) {
        if (-not $text.Contains($token)) { Fail "Optimizer settings UI missing '$token'." }
    }
    if (-not $text.Contains('energy is already above its natural maximum')) { Fail 'Settings must explain stacked Energy bypass.' }
    if (-not $text.Contains('Nerve restrictions remain active')) { Fail 'Settings must explain stacked Nerve does not bypass its policy.' }
}

if (Test-Path -LiteralPath $preferencesPath) {
    $text=Get-Content -LiteralPath $preferencesPath -Raw
    foreach ($token in @('schemaVersion = 3','use95PercentMarketValue','energyWastePolicy','maxEnergyLoss','nerveWastePolicy','maxNerveLoss')) {
        if (-not $text.Contains($token)) { Fail "Preference schema missing '$token'." }
    }
}

if (Test-Path -LiteralPath $countriesPath) {
    $countries=Get-Content -LiteralPath $countriesPath -Raw | ConvertFrom-Json
    $collect=@($countries.countries | Where-Object { $_.collect -eq $true })
    if ($collect.Count -ne 11) { Fail "Expected 11 collected destinations; found $($collect.Count)." }
    foreach ($country in $collect) {
        foreach ($mode in @('standard','airstrip','wlt','business')) {
            $timeProp=$country.travelSeconds.PSObject.Properties[$mode]
            $capacityProp=$country.baseTravelCapacity.PSObject.Properties[$mode]
            if ($null -eq $timeProp -or [long]$timeProp.Value -le 0) { Fail "Country '$($country.id)' lacks $mode travel time." }
            if ($null -eq $capacityProp -or [int]$capacityProp.Value -le 0) { Fail "Country '$($country.id)' lacks $mode capacity." }
        }
        if (-not $country.travelCosts.PSObject.Properties['standard']) { Fail "Country '$($country.id)' lacks Standard travel cost." }
        if ([long]$country.baseTravelCapacity.standard -ne 10 -or [long]$country.baseTravelCapacity.airstrip -ne 15) { Fail "Country '$($country.id)' has unexpected base capacity contract." }
    }
}

if (Test-Path -LiteralPath $baseSettingsPath) {
    $settings=Get-Content -LiteralPath $baseSettingsPath -Raw | ConvertFrom-Json
    if ([double]$settings.profitability.itemMarketFeePercent -ne 0) { Fail 'Default legacy fee must be zero for MV valuation.' }
    if ([double]$settings.profitability.minimumProfitPerItem -ne 0 -or [double]$settings.profitability.minimumMarginPercent -ne 0 -or [double]$settings.profitability.minimumTotalTripProfit -ne 0) { Fail 'Default legacy profit gates must all be zero.' }
    if ([int]$settings.optimizer.marketValueBasisPercent -ne 100) { Fail 'Optimizer default MV basis must be 100%.' }
    if ($settings.optimizer.allowNegativeValueCandidates -ne $true) { Fail 'Negative-value candidates must remain allowed by default.' }
}

if (Test-Path -LiteralPath $wrapperPath) {
    $wrapper=Get-Content -LiteralPath $wrapperPath -Raw
    $finalizer=$wrapper.IndexOf('& $Finalizer')
    $travel=$wrapper.IndexOf('Invoke-FailSoftScript -Path $TravelContext')
    $optimal=$wrapper.IndexOf('Invoke-FailSoftScript -Path $OptimalRoute')
    $filter=$wrapper.IndexOf('& $FilterState')
    $heartbeat=$wrapper.LastIndexOf('Write-UpdateHeartbeat')
    $resale=$wrapper.IndexOf('& $ResaleQueue')
    if (@($finalizer,$travel,$optimal,$filter,$heartbeat,$resale) -contains -1 -or -not ($finalizer -lt $travel -and $travel -lt $optimal -and $optimal -lt $filter -and $filter -lt $heartbeat -and $heartbeat -lt $resale)) {
        Fail 'Runtime order must remain FinalizeState -> TravelContext -> OptimalRoute -> FilterState -> heartbeat -> ResaleQueue.'
    }
    if ($wrapper.Contains('VisibleItems.ps1')) { Fail 'Minimal runtime must not invoke retired graph/card enrichment.' }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Optimal-route validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Optimal-route configuration validation passed.' -ForegroundColor Green
Write-Host 'Route selection is local-only, MV-based, capacity-aware, evidence-aware, and independently constrained by Energy/Nerve waste policy.'
exit 0
