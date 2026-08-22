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
    Settings = Join-Path $ProjectRoot '@Resources\Scripts\OpenOptimizerSettings.ps1'
    SettingsLauncher = Join-Path $ProjectRoot '@Resources\Scripts\LaunchOptimizerSettings.ps1'
    StateReader = Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
    Ini = Join-Path $ProjectRoot 'TravelAssistant.ini'
    Countries = Join-Path $ProjectRoot 'config\countries.json'
}

foreach ($entry in $files.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) { Fail "Missing $($entry.Key) file: $($entry.Value)" }
}

foreach ($path in @($files.Preferences,$files.Popup,$files.Launcher,$files.State,$files.Settings,$files.SettingsLauncher)) {
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in $(Split-Path $path -Leaf): $($parseError.Message)" }
}

if (Test-Path -LiteralPath $files.Preferences) {
    $text = Get-Content -LiteralPath $files.Preferences -Raw
    foreach ($token in @(
        'schemaVersion = 3','itemFilterAll','selectedItemIds','selectedTripBands','selectedCountryIds',
        'categoryFilterAll','selectedCategories','showProfitableOnly','ignoredItemIds',
        'use95PercentMarketValue','energyWastePolicy','maxEnergyLoss','nerveWastePolicy','maxNerveLoss',
        'Reset-UiFilterPreferences','Toggle-TripBandPreference'
    )) {
        if (-not $text.Contains($token)) { Fail "FilterPreferences.ps1 missing '$token'." }
    }
}

if (Test-Path -LiteralPath $files.Popup) {
    $text = Get-Content -LiteralPath $files.Popup -Raw
    foreach ($filter in @("'Item'","'Country'","'Category'","'Ignore'")) {
        if (-not $text.Contains($filter)) { Fail "OpenFilterPopup.ps1 missing filter $filter." }
    }
    foreach ($token in @('Get-ActiveCatalogRows','observedMarkets','itemMetadata','OptimalRoute.ps1','ignoredItemIds')) {
        if (-not $text.Contains($token)) { Fail "Filter popup missing '$token'." }
    }
    if ($text -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'Filter popup must remain local-only.' }
}

if (Test-Path -LiteralPath $files.Launcher) {
    $text = Get-Content -LiteralPath $files.Launcher -Raw
    if (-not $text.Contains('Start-Process') -or -not $text.Contains('OpenFilterPopup.ps1')) { Fail 'Filter popup launcher must detach OpenFilterPopup.ps1.' }
}

if (Test-Path -LiteralPath $files.State) {
    $text = Get-Content -LiteralPath $files.State -Raw
    foreach ($key in @('UIItemFilterAll','UISelectedItemIds','UISelectedTripBands','UISelectedCountryIds','UICategoryFilterAll','UISelectedCategories','UIShowProfitableOnly','UIIgnoredItemIds','UIOldestMarketSourceTimestamp')) {
        if (-not $text.Contains($key)) { Fail "FilterState.ps1 missing state key $key." }
    }
    foreach ($token in @('Get-OldestActiveMarketSourceTimestamp','observedMarkets','catalogActive','legacy_removed','sourceTimestamp')) {
        if (-not $text.Contains($token)) { Fail "FilterState.ps1 missing optimizer-wide freshness token '$token'." }
    }
    if ($text -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'FilterState.ps1 must remain local-only.' }
}

if (Test-Path -LiteralPath $files.Settings) {
    $text = Get-Content -LiteralPath $files.Settings -Raw
    foreach ($token in @('Show profitable items only','Use 95% MV profit calculation','Energy Waste','Max Energy Loss','Nerve Waste','Max Nerve Loss','Ignore List...','Profile / API...')) {
        if (-not $text.Contains($token)) { Fail "OpenOptimizerSettings.ps1 missing '$token'." }
    }
}

if (Test-Path -LiteralPath $files.SettingsLauncher) {
    $text = Get-Content -LiteralPath $files.SettingsLauncher -Raw
    if (-not $text.Contains('Start-Process') -or -not $text.Contains('OpenOptimizerSettings.ps1')) { Fail 'Optimizer settings launcher must detach OpenOptimizerSettings.ps1.' }
}

if (Test-Path -LiteralPath $files.StateReader) {
    $text = Get-Content -LiteralPath $files.StateReader -Raw
    foreach ($token in @('function OpenFilter(filterName)','function ToggleTripBand(band)','function ResetFilters()','local function updateOptimal(data, now)','UIOldestMarketSourceTimestamp')) {
        if (-not $text.Contains($token)) { Fail "StateReader.lua missing '$token'." }
    }
    foreach ($legacy in @('TogglePin(','pinnedCardKey','cardExpanded')) {
        if ($text.Contains($legacy)) { Fail "Minimal optimizer StateReader.lua must not depend on legacy card/pin UI token '$legacy'." }
    }
}

if (Test-Path -LiteralPath $files.Ini) {
    $ini = Get-Content -LiteralPath $files.Ini -Raw
    if ($ini -notmatch '(?m)^Version=0\.5\.0\s*$') { Fail 'Minimal optimizer/filter candidate must report version 0.5.0.' }
    foreach ($section in @('MeasureFilterPopup','MeasurePreferenceAction','MeterFilterTopLine','MeterItemFilter','MeterTripShort','MeterTripMedium','MeterTripLong','MeterTripExpand','MeterCategoryFilter','MeterFilterReset','MeterFilterBottomLine')) {
        if ($ini -notmatch ('(?m)^\[' + [regex]::Escape($section) + '\]\s*$')) { Fail "TravelAssistant.ini missing [$section]." }
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
    Write-Host "Optimizer filter/settings validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Optimizer filters, settings, ignore-list, and all-market freshness validation passed.' -ForegroundColor Green
Write-Host 'Filters shape route candidates only; Ignore List suppresses broad per-item pricing without erasing shared stock/history collection.'
exit 0
