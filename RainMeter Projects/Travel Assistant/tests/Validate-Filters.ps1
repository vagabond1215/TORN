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
    Priority = Join-Path $ProjectRoot '@Resources\Scripts\ResalePriority.ps1'
    StateReader = Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
    Settings = Join-Path $ProjectRoot '@Resources\Scripts\OpenSettings.ps1'
    Ini = Join-Path $ProjectRoot 'TravelAssistant.ini'
    Countries = Join-Path $ProjectRoot 'config\countries.json'
}

foreach ($entry in $files.GetEnumerator()) {
    if (-not (Test-Path -LiteralPath $entry.Value)) { Fail "Missing $($entry.Key) file: $($entry.Value)" }
}

foreach ($path in @($files.Preferences,$files.Popup,$files.Launcher,$files.State,$files.Priority,$files.Settings)) {
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in $(Split-Path $path -Leaf): $($parseError.Message)" }
}

if (Test-Path -LiteralPath $files.Preferences) {
    $text = Get-Content -LiteralPath $files.Preferences -Raw
    foreach ($token in @('itemFilterAll','selectedItemIds','selectedTripBands','selectedCountryIds','categoryFilterAll','selectedCategories','showProfitableOnly','ignoredItemIds','pinnedMarket','Reset-UiFilterPreferences','Toggle-TripBandPreference')) {
        if (-not $text.Contains($token)) { Fail "FilterPreferences.ps1 missing '$token'." }
    }
}

if (Test-Path -LiteralPath $files.Popup) {
    $text = Get-Content -LiteralPath $files.Popup -Raw
    foreach ($filter in @("'Item'","'Country'","'Category'","'Ignore'")) { if (-not $text.Contains($filter)) { Fail "OpenFilterPopup.ps1 missing filter $filter." } }
    if (-not $text.Contains('itemMetadata')) { Fail 'Ignore List must enumerate the full local metadata catalog when available.' }
    if (-not $text.Contains('FilterState.ps1')) { Fail 'Popup saves must project updated filter state immediately.' }
    if ($text -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'Filter popup must remain local-only.' }
}

if (Test-Path -LiteralPath $files.Launcher) {
    $text = Get-Content -LiteralPath $files.Launcher -Raw
    if (-not $text.Contains('Start-Process')) { Fail 'Filter popup launcher must detach from Rainmeter RunCommand.' }
    if (-not $text.Contains('OpenFilterPopup.ps1')) { Fail 'Filter popup launcher must start OpenFilterPopup.ps1.' }
}

if (Test-Path -LiteralPath $files.State) {
    $text = Get-Content -LiteralPath $files.State -Raw
    foreach ($key in @('UIItemFilterAll','UISelectedItemIds','UISelectedTripBands','UISelectedCountryIds','UICategoryFilterAll','UISelectedCategories','UIShowProfitableOnly','UIIgnoredItemIds','UIPinnedMarket')) {
        if (-not $text.Contains($key)) { Fail "FilterState.ps1 missing state key $key." }
    }
    if ($text -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'FilterState.ps1 must remain local-only.' }
}

if (Test-Path -LiteralPath $files.Priority) {
    $text = Get-Content -LiteralPath $files.Priority -Raw
    foreach ($token in @('ignoredItemIds','ignored_by_user','PriorityBackoffSeconds = 300','pinnedMarket')) {
        if (-not $text.Contains($token)) { Fail "ResalePriority.ps1 missing '$token'." }
    }
    if ($text -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'ResalePriority.ps1 must not perform network work.' }
}

if (Test-Path -LiteralPath $files.StateReader) {
    $text = Get-Content -LiteralPath $files.StateReader -Raw
    foreach ($token in @(
        "cardMarket = { UKPrimary='united_kingdom:206'",
        "travelFilterCountryId~='' and cardCountry[cardKey]~=travelFilterCountryId",
        'ignoredItems[cardItemId[cardKey]]',
        'if pinKey==cardKey then return true end',
        'showProfitableOnly and not cardProfitable[cardKey]',
        'function TogglePin(cardKey)',
        'function OpenFilter(filterName)',
        'function ToggleTripBand(band)',
        'function ResetFilters()',
        "return '★'",
        'local top=88'
    )) {
        if (-not $text.Contains($token)) { Fail "StateReader.lua missing filter/pin contract: $token" }
    }
}

if (Test-Path -LiteralPath $files.Settings) {
    $text = Get-Content -LiteralPath $files.Settings -Raw
    foreach ($token in @('Show profitable items only','Ignore List...','Read-UiPreferences','Save-UiPreferences','showProfitableOnly','LaunchFilterPopup.ps1')) {
        if (-not $text.Contains($token)) { Fail "OpenSettings.ps1 missing '$token'." }
    }
    if ($text -match 'Write-JsonAtomic\s+-Path\s+\$PreferencePath\s+-Value\s+\(\[pscustomobject\]') { Fail 'Settings must not replace preferences.json with a narrow object and erase pin/filter/ignore state.' }
}

if (Test-Path -LiteralPath $files.Ini) {
    $ini = Get-Content -LiteralPath $files.Ini -Raw
    if ($ini -notmatch '(?m)^Version=0\.4\.0\s*$') { Fail 'Filter-bar candidate must report version 0.4.0.' }
    foreach ($section in @('MeasureFilterPopup','MeasurePreferenceAction','MeterFilterTopLine','MeterItemFilter','MeterTripShort','MeterTripMedium','MeterTripLong','MeterTripExpand','MeterCategoryFilter','MeterFilterReset','MeterFilterBottomLine')) {
        if ($ini -notmatch ('(?m)^\['+[regex]::Escape($section)+'\]\s*$')) { Fail "TravelAssistant.ini missing [$section]." }
    }
    if ($ini -notmatch '(?m)^PreferencesFile=#CURRENTPATH#data\\runtime\\preferences\.json\s*$') { Fail 'StateReader must receive the ignored local preferences path.' }
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
    Write-Host "Filter/pin validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Filter, pin, Settings, and ignore-list configuration validation passed.' -ForegroundColor Green
Write-Host 'Presentation filters remain local/persistent; Ignore List suppresses broad per-item market pricing without stopping shared foreign-stock collection.'
exit 0
