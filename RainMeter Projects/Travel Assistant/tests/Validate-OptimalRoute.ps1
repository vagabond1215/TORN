$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$optimizerPath = Join-Path $ProjectRoot '@Resources\Scripts\OptimalRoute.ps1'
$opportunityPath = Join-Path $ProjectRoot '@Resources\Scripts\OpportunityState.ps1'
$settingsPath = Join-Path $ProjectRoot '@Resources\Scripts\OpenOptimizerSettings.ps1'
$preferencesPath = Join-Path $ProjectRoot '@Resources\Scripts\FilterPreferences.ps1'
$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$resalePriorityPath = Join-Path $ProjectRoot '@Resources\Scripts\ResalePriority.ps1'
$countriesPath = Join-Path $ProjectRoot 'config\countries.json'
$baseSettingsPath = Join-Path $ProjectRoot 'config\settings.example.json'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($optimizerPath,$opportunityPath,$settingsPath,$preferencesPath,$wrapperPath,$resalePriorityPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing $(Split-Path $path -Leaf)."; continue }
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in $(Split-Path $path -Leaf): $($parseError.Message)" }
}

if (Test-Path -LiteralPath $optimizerPath) {
    $text=Get-Content -LiteralPath $optimizerPath -Raw
    foreach ($fn in @('Get-OptimalBarWaste','Test-OptimalWastePolicy','Get-OptimalArrivalForecast','Get-OptimalResaleSnapshot','Get-OptimalCountryPlan')) {
        if ($text -notmatch ('(?m)^function\s+'+[regex]::Escape($fn)+'\s*\{')) { Fail "OptimalRoute.ps1 missing $fn." }
    }
    if ($text -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'OptimalRoute.ps1 must remain local-only.' }
    if ($text -match '(?m)^function\s+Write-OptimalProjection\s*\{' -or $text.Contains("`$State['OptimalVisible']") -or $text.Contains('OptimalItemCount')) {
        Fail 'OptimalRoute.ps1 must not retain the retired standalone OPTIMAL UI projection.'
    }
    if ($text.Contains('$state = Read-OptimalStateKv $StateKvFile')) { Fail 'OptimalRoute.ps1 must not retain a standalone state-writing main path.' }
    foreach ($token in @(
        "PSObject.Properties['average']",'marketValue = $marketValue','EnergyStackBypass','ShowProfitableOnly',
        'Test-OptimalMarketFilters','Get-OptimalMarketMetadata','availabilitySeconds','restockDelaySeconds','expectedTripProfit'
    )) {
        if (-not $text.Contains($token)) { Fail "Optimal route contract missing '$token'." }
    }
    foreach ($forbidden in @('itemMarketFeePercent','minimumProfitPerItem','minimumMarginPercent','LOW_MARGIN','UNPROFITABLE')) {
        if ($text.Contains($forbidden)) { Fail "Optimal route must not gate on legacy profitability token '$forbidden'." }
    }
}

if (Test-Path -LiteralPath $opportunityPath) {
    $text=Get-Content -LiteralPath $opportunityPath -Raw
    foreach ($token in @(
        'grossProfit','profitPerHour','quantity','elapsedSeconds','Get-OpportunityNextWindow','Get-OpportunityProbabilityAtAge',
        'Get-OpportunityResaleUse','resaleFallbackMaxAgeSeconds','marketValueFresh',' STALE','OpportunityStaleMvCount','OpportunityCountry_',
        'Write-OpportunityProjection',"sortMode -eq 'name'","sortMode -eq 'gross'","sortMode -eq 'profit_per_hour'",'GrossValue','ProfitHourValue','WindowStartAt',
        'ResalePricingPriorityItemIds','pricingPriorityIds.Add($itemId)'
    )) {
        if (-not $text.Contains($token)) { Fail "Opportunity ranking contract missing '$token'." }
    }
    foreach ($retired in @('expectedGross=','optimalScore=')) {
        if ($text.Contains($retired)) { Fail "Opportunity presentation must not retain hidden weighting token '$retired'." }
    }
    if ($text -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'OpportunityState.ps1 must remain local-only.' }
}

if (Test-Path -LiteralPath $resalePriorityPath) {
    $text=Get-Content -LiteralPath $resalePriorityPath -Raw
    foreach ($token in @('ResalePricingPriorityItemIds','Read-PriorityStateKv','$projection.ContainsKey(''ResalePricingPriorityItemIds'')')) {
        if (-not $text.Contains($token)) { Fail "Resale priority projection contract missing '$token'." }
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
    foreach ($token in @('schemaVersion = 8','displayTripBands','energyWastePolicy','maxEnergyLoss','nerveWastePolicy','maxNerveLoss',"sortMode = 'upcoming'","@('upcoming','gross','profit_per_hour')")) {
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
    if ($settings.profitability.PSObject.Properties['itemMarketFeePercent']) { Fail 'Legacy profitability.itemMarketFeePercent must remain removed; UI preferences are the sole tax-rate authority.' }
    if ([double]$settings.profitability.minimumProfitPerItem -ne 0 -or [double]$settings.profitability.minimumMarginPercent -ne 0 -or [double]$settings.profitability.minimumTotalTripProfit -ne 0) { Fail 'Default legacy profit gates must all be zero.' }
    if ([int]$settings.profitability.resaleStaleAfterSeconds -ne 21600) { Fail 'Fresh resale MV window must remain six hours.' }
    if ([int]$settings.profitability.resaleFallbackMaxAgeSeconds -ne 604800) { Fail 'Opportunity display stale-MV fallback must be bounded to seven days.' }
    if ($settings.optimizer.allowNegativeValueCandidates -ne $true) { Fail 'Negative-value candidates must remain allowed by default.' }
}

if (Test-Path -LiteralPath $wrapperPath) {
    $wrapper=Get-Content -LiteralPath $wrapperPath -Raw
    $finalizer=$wrapper.IndexOf('& $Finalizer')
    $travel=$wrapper.IndexOf('Invoke-FailSoftScript -Path $TravelContext')
    $opportunity=$wrapper.IndexOf('Invoke-FailSoftScript -Path $OpportunityState')
    $filter=$wrapper.IndexOf('& $FilterState')
    $heartbeat=$wrapper.LastIndexOf('Write-UpdateHeartbeat')
    $resale=$wrapper.IndexOf('& $ResaleQueue')
    if (@($finalizer,$travel,$opportunity,$filter,$heartbeat,$resale) -contains -1 -or -not ($finalizer -lt $travel -and $travel -lt $opportunity -and $opportunity -lt $filter -and $filter -lt $heartbeat -and $heartbeat -lt $resale)) {
        Fail 'Runtime order must remain FinalizeState -> TravelContext -> OpportunityState -> FilterState -> heartbeat -> ResaleQueue.'
    }
    if ($wrapper.Contains('Invoke-FailSoftScript -Path $OptimalRoute') -or $wrapper.Contains('$OptimalRouteErrorFile')) {
        Fail 'The retired standalone OptimalRoute stage must not run on the normal one-minute updater path.'
    }
    if ($wrapper.Contains('VisibleItems.ps1')) { Fail 'Normal runtime must not regenerate old embedded card graphs through VisibleItems.ps1.' }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Optimizer/opportunity validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Retired standalone route stage, shared opportunity economics, and resale-priority projection validation passed.' -ForegroundColor Green
Write-Host 'Visible ordering is UPCOMING, GROSS PROFIT, or PROFIT/HR; Name is fallback-only, stale MV is bounded/explicit, and hit likelihood remains separate.'
exit 0
