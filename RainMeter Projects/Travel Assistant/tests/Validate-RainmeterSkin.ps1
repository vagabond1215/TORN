$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$stateReaderPath = Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

if (-not (Test-Path -LiteralPath $iniPath)) {
    Write-Host 'FAIL: TravelAssistant.ini is missing.' -ForegroundColor Red
    exit 1
}
$ini = Get-Content -LiteralPath $iniPath -Raw

if ($ini -match '(?im)^Measure=RunCommand\s*$') { Fail 'RunCommand measures must use Measure=Plugin plus Plugin=RunCommand.' }
if ($ini -notmatch '(?m)^Version=0\.5\.0\s*$') { Fail 'Minimal optimizer skin must report version 0.5.0.' }
if ($ini -notmatch '(?m)^OnRefreshAction=\[!CommandMeasure MeasureUpdate "Run"\]\s*$') { Fail 'OnRefreshAction must trigger MeasureUpdate.' }

foreach ($sectionName in @('MeasureUpdate','MeasureSettings','MeasureFilterPopup','MeasurePreferenceAction')) {
    $match = [regex]::Match($ini, '(?ms)^\[' + [regex]::Escape($sectionName) + '\]\s*(.*?)(?=^\[|\z)')
    if (-not $match.Success) { Fail "Missing Rainmeter section [$sectionName]."; continue }
    $body = $match.Groups[1].Value
    if ($body -notmatch '(?im)^Measure=Plugin\s*$' -or $body -notmatch '(?im)^Plugin=RunCommand\s*$' -or $body -notmatch '(?im)^Program=powershell\.exe\s*$') {
        Fail "[$sectionName] must be a PowerShell RunCommand plugin measure."
    }
}

$updateBody = [regex]::Match($ini, '(?ms)^\[MeasureUpdate\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if ($updateBody -notmatch '(?im)^Parameter=.*RunUpdate\.ps1') { Fail 'MeasureUpdate must route through RunUpdate.ps1.' }
$settingsBody = [regex]::Match($ini, '(?ms)^\[MeasureSettings\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if ($settingsBody -notmatch '(?im)^Parameter=.*LaunchOptimizerSettings\.ps1') { Fail 'Main Settings action must open the minimalist optimizer settings popup.' }
$popupBody = [regex]::Match($ini, '(?ms)^\[MeasureFilterPopup\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if ($popupBody -notmatch '(?im)^Parameter=.*LaunchFilterPopup\.ps1.*#FilterRequest#') { Fail 'Filter popup must use its detached launcher and dynamic request.' }
$prefBody = [regex]::Match($ini, '(?ms)^\[MeasurePreferenceAction\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if ($prefBody -notmatch '(?im)^Parameter=.*FilterPreferences\.ps1.*#PreferenceAction#.*#PreferenceValue#') { Fail 'Quick filter actions must route through FilterPreferences.ps1.' }

foreach ($launcherName in @('LaunchOptimizerSettings.ps1','LaunchFilterPopup.ps1')) {
    $path = Join-Path $ProjectRoot ('@Resources\Scripts\' + $launcherName)
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing $launcherName."; continue }
    $text = Get-Content -LiteralPath $path -Raw
    if (-not $text.Contains('Start-Process')) { Fail "$launcherName must detach its long-lived UI process." }
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) {
        Fail "PowerShell parse error in ${launcherName}: $($parseError.Message)"
    }
}

$title = [regex]::Match($ini, '(?ms)^\[MeterTitle\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if ($title -notmatch '(?im)^Text=Travel\s*$') { Fail 'Main header must display Travel.' }
if ($title -notmatch '(?im)^LeftMouseUpAction=\["https://www\.torn\.com/page\.php\?sid=travel"\]\s*$') { Fail 'Travel header must open Torn travel.' }

foreach ($section in @(
    'MeterFilterTopLine','MeterItemFilter','MeterTripShort','MeterTripMedium','MeterTripLong','MeterTripExpand','MeterCategoryFilter','MeterFilterReset','MeterFilterBottomLine',
    'MeterRouteCard','MeterRouteTitle','MeterRouteValue','MeterRouteMeta','MeterRouteMessage'
)) {
    if ($ini -notmatch ('(?m)^\[' + [regex]::Escape($section) + '\]\s*$')) { Fail "Missing [$section]." }
}

foreach ($action in @("OpenFilter('Item')","OpenFilter('Country')","OpenFilter('Category')","ToggleTripBand('short')","ToggleTripBand('medium')","ToggleTripBand('long')","ResetFilters()")) {
    if (-not $ini.Contains($action)) { Fail "Filter data bar is missing action $action." }
}

for ($i = 1; $i -le 8; $i++) {
    foreach ($suffix in @('Name','Qty','Price','Chance')) {
        $section = 'MeterOptimalItem' + $i + $suffix
        if ($ini -notmatch ('(?m)^\[' + [regex]::Escape($section) + '\]\s*$')) { Fail "Missing aligned optimizer row meter [$section]." }
    }
    $nameBody = [regex]::Match($ini, '(?ms)^\[MeterOptimalItem' + $i + 'Name\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if ($nameBody -notmatch '(?im)^X=24\s*$' -or $nameBody -notmatch '(?im)^FontSize=10\s*$') { Fail "Optimizer item $i name must use the common left-aligned name column and font size." }
    $priceBody = [regex]::Match($ini, '(?ms)^\[MeterOptimalItem' + $i + 'Price\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if ($priceBody -notmatch '(?im)^InlineSetting=Size\s*\|\s*8\s*$' -or $priceBody -notmatch '(?im)^InlineSetting2=Color\s*\|\s*#Muted#\s*$') { Fail "Optimizer item $i must render parenthesized MV smaller and muted." }
    if ($priceBody -notmatch ('(?im)^Text=#OptimalItem' + $i + 'PriceText# \(#OptimalItem' + $i + 'MarketValueText#\)\s*$')) { Fail "Optimizer item $i price must show foreign value followed by MV in parentheses." }
}

foreach ($legacySection in @('MeterUKCard','MeterJPCard','MeterUKSecondaryCard','MeterJPSecondaryCard','MeterUKGraph','MeterJPGraph','MeterUKSecondaryGraph','MeterJPSecondaryGraph')) {
    if ($ini -match ('(?m)^\[' + [regex]::Escape($legacySection) + '\]\s*$')) { Fail "Minimalist main view must not contain legacy card/graph meter [$legacySection]." }
}

if (-not (Test-Path -LiteralPath $stateReaderPath)) {
    Fail 'Missing StateReader.lua.'
} else {
    $stateReader = Get-Content -LiteralPath $stateReaderPath -Raw
    foreach ($token in @(
        'local function updateOptimal(data, now)',
        "setGroupVisible('OptimalItemRow' .. i, i <= itemCount)",
        "safeText(data.OptimalCountryName, 'Route')",
        "arrivalAt - now",
        'function OpenFilter(filterName)',
        'function ToggleTripBand(band)',
        'function ResetFilters()',
        "setVariable('PanelHeight'"
    )) {
        if (-not $stateReader.Contains($token)) { Fail "StateReader.lua missing minimalist optimizer contract: $token" }
    }
    foreach ($legacyToken in @('ToggleCard(','TogglePin(','cardExpanded','UKSecondary')) {
        if ($stateReader.Contains($legacyToken)) { Fail "Minimalist StateReader.lua must not retain card-stack behavior '$legacyToken'." }
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Rainmeter skin validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Rainmeter minimalist optimizer static validation passed.' -ForegroundColor Green
exit 0
