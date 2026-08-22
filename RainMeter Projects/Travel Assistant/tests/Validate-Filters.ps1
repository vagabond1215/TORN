$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

$files = @{
    Preferences = Join-Path $ProjectRoot '@Resources\Scripts\FilterPreferences.ps1'
    Popup = Join-Path $ProjectRoot '@Resources\Scripts\OpenFilterPopup.ps1'
    Launcher = Join-Path $ProjectRoot '@Resources\Scripts\LaunchFilterPopup.ps1'
    State = Join-Path $ProjectRoot '@Resources\Scripts\FilterState.ps1'
    Opportunities = Join-Path $ProjectRoot '@Resources\Scripts\OpportunityState.ps1'
    Settings = Join-Path $ProjectRoot '@Resources\Scripts\OpenOptimizerSettings.ps1'
    SettingsLauncher = Join-Path $ProjectRoot '@Resources\Scripts\LaunchOptimizerSettings.ps1'
    StateReader = Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
    Ini = Join-Path $ProjectRoot 'TravelAssistant.ini'
    Countries = Join-Path $ProjectRoot 'config\countries.json'
}

foreach ($entry in $files.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) { Fail "Missing $($entry.Key) file: $($entry.Value)" }
}

foreach ($path in @($files.Preferences,$files.Popup,$files.Launcher,$files.State,$files.Opportunities,$files.Settings,$files.SettingsLauncher)) {
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in $(Split-Path $path -Leaf): $($parseError.Message)" }
}

if (Test-Path -LiteralPath $files.Preferences) {
    $text = Get-Content -LiteralPath $files.Preferences -Raw
    foreach ($token in @(
        'schemaVersion = 5','itemFilterAll','selectedItemIds','selectedTripBands','selectedCountryIds',
        'categoryFilterAll','selectedCategories','showProfitableOnly','ignoredItemIds',
        'use95PercentMarketValue','energyWastePolicy','maxEnergyLoss','nerveWastePolicy','maxNerveLoss',
        "sortMode = 'upcoming'",'Normalize-SortMode',"@('name','upcoming','gross','profit_per_hour')",'SetSortMode',
        "if (`$mode -eq 'optimal') { return 'profit_per_hour' }",
        "if (`$mode -eq 'profit') { return 'gross' }",
        "if (`$mode -eq 'time') { return 'upcoming' }",
        'Set-FilterStateKvValueAtomic','OpportunitySortMode',
        "if (`$changed -and `$Action -ne 'SetSortMode')",'preference-action'
    )) {
        if (-not $text.Contains($token)) { Fail "FilterPreferences.ps1 missing '$token'." }
    }
}

if (Test-Path -LiteralPath $files.Popup) {
    $text = Get-Content -LiteralPath $files.Popup -Raw
    foreach ($filter in @("'Item'","'Country'","'Category'","'Ignore'")) {
        if (-not $text.Contains($filter)) { Fail "OpenFilterPopup.ps1 missing filter $filter." }
    }
    foreach ($token in @('Get-ActiveCatalogRows','observedMarkets','itemMetadata','OptimalRoute.ps1','OpportunityState.ps1','ignoredItemIds','Persistent opportunity filter','RuntimeLog.ps1','Write-TravelAssistantLog')) {
        if (-not $text.Contains($token)) { Fail "Filter popup missing '$token'." }
    }
    if ($text -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'Filter popup must remain local-only.' }
}

if (Test-Path -LiteralPath $files.Launcher) {
    $text = Get-Content -LiteralPath $files.Launcher -Raw
    foreach($token in @('Start-Process','PopupHost.ps1','-Popup Filter','-WindowStyle Hidden','-STA','$arguments')) {
        if(-not $text.Contains($token)){Fail "Filter popup launcher missing '$token'."}
    }
    if($text.Contains('-WindowStyle Normal')){Fail 'Filter popup launcher must not expose a PowerShell console.'}
}

if (Test-Path -LiteralPath $files.State) {
    $text = Get-Content -LiteralPath $files.State -Raw
    foreach ($key in @('UIItemFilterAll','UISelectedItemIds','UISelectedTripBands','UISelectedCountryIds','UICategoryFilterAll','UISelectedCategories','UIShowProfitableOnly','UIIgnoredItemIds','UIOldestMarketSourceTimestamp')) {
        if (-not $text.Contains($key)) { Fail "FilterState.ps1 missing state key $key." }
    }
    foreach ($token in @('Get-OldestActiveMarketSourceTimestamp','observedMarkets','catalogActive','legacy_removed','sourceTimestamp')) {
        if (-not $text.Contains($token)) { Fail "FilterState.ps1 missing all-market freshness token '$token'." }
    }
    if ($text -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'FilterState.ps1 must remain local-only.' }
}

if (Test-Path -LiteralPath $files.Opportunities) {
    $text = Get-Content -LiteralPath $files.Opportunities -Raw
    foreach ($token in @(
        'Get-OpportunityNextWindow','Get-OpportunityProbabilityAtAge','grossProfit','profitPerHour','quantity','elapsedSeconds','windowStartAt','Write-OpportunityProjection',
        'Get-OptimalBarWaste','Test-OptimalWastePolicy','energyWastePolicy','nerveWastePolicy','$constraintsApply = [string]::IsNullOrWhiteSpace($fixedCountry)','Get-OpportunityWasteText',
        "sortMode -eq 'name'","sortMode -eq 'gross'","sortMode -eq 'profit_per_hour'",'OpportunityBestKey',
        "Opportunity'+`$n+'QuantityText", "Opportunity'+`$n+'ProfitHourText", "Opportunity'+`$n+'GrossValue", "Opportunity'+`$n+'WindowStartAt"
    )) {
        if (-not $text.Contains($token)) { Fail "OpportunityState.ps1 missing '$token'." }
    }
    foreach ($retired in @('expectedGross=','optimalScore=','SortMode $sortMode -Message $message -BestKey')) {
        if ($text.Contains($retired)) { Fail "OpportunityState.ps1 retains retired hidden-ranking contract '$retired'." }
    }
    if ($text -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'OpportunityState.ps1 must remain local-only.' }
}

if (Test-Path -LiteralPath $files.Settings) {
    $text = Get-Content -LiteralPath $files.Settings -Raw
    foreach ($token in @('Show profitable items only','Use 95% MV profit calculation','Energy Waste','Max Energy Loss','Nerve Waste','Max Nerve Loss','Ignore List...','Profile / API...','RuntimeLog.ps1')) {
        if (-not $text.Contains($token)) { Fail "OpenOptimizerSettings.ps1 missing '$token'." }
    }
    if($text.Contains('-WindowStyle Normal')){Fail 'Optimizer Settings must not spawn visible PowerShell consoles.'}
}

if (Test-Path -LiteralPath $files.SettingsLauncher) {
    $text = Get-Content -LiteralPath $files.SettingsLauncher -Raw
    foreach($token in @('Start-Process','PopupHost.ps1','-Popup OptimizerSettings','-WindowStyle Hidden','-STA','$arguments')) {
        if(-not $text.Contains($token)){Fail "Optimizer settings launcher missing '$token'."}
    }
    if($text.Contains('-WindowStyle Normal')){Fail 'Optimizer settings launcher must not expose a PowerShell console.'}
}

if (Test-Path -LiteralPath $files.StateReader) {
    $text = Get-Content -LiteralPath $files.StateReader -Raw
    foreach ($token in @(
        'function OpenFilter(filterName)','function ToggleTripBand(band)','function ResetFilters()','function SetSortMode(mode)',
        'local function updateSort(mode)','local function updateOpportunities(data)','local function stabilizeProjection(data)','local function configureInteractiveMeters()',
        'local function currentOpportunityRows(data)','local function sortOpportunityRows(rows, mode)','local function locallySortedProjection(data, mode)',
        "'NAME'","'UPCOMING'","'GROSS PROFIT'","'PROFIT/HR'","SetSortMode('name')","SetSortMode('profit_per_hour')",
        'GrossValue','ProfitHourValue','WindowStartAt','ProbabilityValue','ElapsedSeconds','UIOldestMarketSourceTimestamp','SolidColor'
    )) {
        if (-not $text.Contains($token)) { Fail "StateReader.lua missing '$token'." }
    }
    foreach ($legacy in @('TogglePin(','pinnedCardKey','cardExpanded','updateOptimal(data, now)')) {
        if ($text.Contains($legacy)) { Fail "Opportunity StateReader.lua must not depend on retired primary-view token '$legacy'." }
    }
}

if (Test-Path -LiteralPath $files.Ini) {
    $ini = Get-Content -LiteralPath $files.Ini -Raw
    if ($ini -notmatch '(?m)^Version=0\.6\.0\s*$') { Fail 'Opportunity/filter candidate must report version 0.6.0.' }
    foreach ($section in @('MeasureFilterPopup','MeasurePreferenceAction','MeterFilterTopLine','MeterItemFilter','MeterTripShort','MeterTripMedium','MeterTripLong','MeterTripExpand','MeterCategoryFilter','MeterFilterReset','MeterFilterBottomLine','MeterSortLabel','MeterSortOptimal','MeterSortUpcoming','MeterSortProfit','MeterSortTime')) {
        if ($ini -notmatch ('(?m)^\[' + [regex]::Escape($section) + '\]\s*$')) { Fail "TravelAssistant.ini missing internal compatibility section [$section]." }
    }
    if ($ini -notmatch '(?im)^Parameter=.*LaunchOptimizerSettings\.ps1') { Fail 'Main Settings button must use optimizer settings launcher.' }
}

if (Test-Path -LiteralPath $files.Countries) {
    $countries = Get-Content -LiteralPath $files.Countries -Raw | ConvertFrom-Json
    $collect = @($countries.countries | Where-Object { $_.collect -eq $true })
    if ($collect.Count -ne 11) { Fail "Expected 11 collect=true destinations; found $($collect.Count)." }
    foreach ($country in $collect) {
        if (-not $country.PSObject.Properties['tripBand'] -or [string]$country.tripBand -notin @('short','medium','long')) { Fail "Country '$($country.id)' lacks a valid tripBand." }
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Opportunity filter/sort/settings validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Opportunity filters, four transparent sort modes, immediate local reordering, stable projection, responsive hitboxes, hidden popup host, waste policies, settings, ignore-list, and all-market freshness validation passed.' -ForegroundColor Green
Write-Host 'NAME, UPCOMING, GROSS PROFIT, and PROFIT/HR are explicit orderings; hit likelihood remains a separate displayed metric.'
exit 0
