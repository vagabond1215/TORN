$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$stateReaderPath = Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

if (-not (Test-Path -LiteralPath $iniPath)) { Write-Host 'FAIL: TravelAssistant.ini is missing.' -ForegroundColor Red; exit 1 }
$ini = Get-Content -LiteralPath $iniPath -Raw

if ($ini -match '(?im)^Measure=RunCommand\s*$') { Fail 'RunCommand measures must use Measure=Plugin plus Plugin=RunCommand.' }
if ($ini -notmatch '(?m)^Version=0\.4\.0\s*$') { Fail 'Current skin candidate must report version 0.4.0.' }
if ($ini -notmatch '(?m)^MaxExpandedCards=2\s*$') { Fail 'Default expansion cap must remain two.' }
if ($ini -notmatch '(?m)^OnRefreshAction=\[!CommandMeasure MeasureUpdate "Run"\]\s*$') { Fail 'OnRefreshAction must trigger MeasureUpdate.' }

foreach ($sectionName in @('MeasureUpdate','MeasureSettings','MeasureFilterPopup','MeasurePreferenceAction')) {
    $match = [regex]::Match($ini,'(?ms)^\['+[regex]::Escape($sectionName)+'\]\s*(.*?)(?=^\[|\z)')
    if (-not $match.Success) { Fail "Missing Rainmeter section [$sectionName]."; continue }
    $body = $match.Groups[1].Value
    if ($body -notmatch '(?im)^Measure=Plugin\s*$' -or $body -notmatch '(?im)^Plugin=RunCommand\s*$' -or $body -notmatch '(?im)^Program=powershell\.exe\s*$') {
        Fail "[$sectionName] must be a powershell RunCommand plugin measure."
    }
}

$updateBody=[regex]::Match($ini,'(?ms)^\[MeasureUpdate\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if ($updateBody -notmatch '(?im)^Parameter=.*RunUpdate\.ps1') { Fail 'MeasureUpdate must route through RunUpdate.ps1.' }
$settingsBody=[regex]::Match($ini,'(?ms)^\[MeasureSettings\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if ($settingsBody -notmatch '(?im)^Parameter=.*LaunchSettings\.ps1') { Fail 'MeasureSettings must use detached LaunchSettings.ps1.' }
$popupBody=[regex]::Match($ini,'(?ms)^\[MeasureFilterPopup\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if ($popupBody -notmatch '(?im)^Parameter=.*LaunchFilterPopup\.ps1.*#FilterRequest#') { Fail 'MeasureFilterPopup must use detached popup launcher and dynamic filter request.' }
$prefBody=[regex]::Match($ini,'(?ms)^\[MeasurePreferenceAction\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if ($prefBody -notmatch '(?im)^Parameter=.*FilterPreferences\.ps1.*#PreferenceAction#.*#PreferenceValue#') { Fail 'MeasurePreferenceAction must route quick filters through FilterPreferences.ps1.' }

foreach ($launcherName in @('LaunchSettings.ps1','LaunchFilterPopup.ps1')) {
    $path=Join-Path $ProjectRoot ('@Resources\Scripts\'+$launcherName)
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing $launcherName."; continue }
    $text=Get-Content -LiteralPath $path -Raw
    if (-not $text.Contains('Start-Process')) { Fail "$launcherName must detach its long-lived UI process." }
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in $launcherName: $($parseError.Message)" }
}

$title=[regex]::Match($ini,'(?ms)^\[MeterTitle\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if ($title -notmatch '(?im)^Text=Travel\s*$') { Fail 'Main header must display Travel.' }
if ($title -notmatch '(?im)^LeftMouseUpAction=\["https://www\.torn\.com/page\.php\?sid=travel"\]\s*$') { Fail 'Travel header must open Torn travel.' }

foreach ($section in @(
    'MeterFilterTopLine','MeterItemFilter','MeterTripShort','MeterTripMedium','MeterTripLong','MeterTripExpand','MeterCategoryFilter','MeterFilterReset','MeterFilterBottomLine',
    'MeterUKCard','MeterUKSecondaryCard','MeterJPCard','MeterJPSecondaryCard',
    'MeterUKFlag','MeterUKSecondaryFlag','MeterJPFlag','MeterJPSecondaryFlag',
    'MeterUKGraph','MeterUKSecondaryGraph','MeterJPGraph','MeterJPSecondaryGraph',
    'MeterUKExpand','MeterUKSecondaryExpand','MeterJPExpand','MeterJPSecondaryExpand'
)) {
    if ($ini -notmatch ('(?m)^\['+[regex]::Escape($section)+'\]\s*$')) { Fail "Missing [$section]." }
}

foreach ($action in @("OpenFilter('Item')","OpenFilter('Country')","OpenFilter('Category')","ToggleTripBand('short')","ToggleTripBand('medium')","ToggleTripBand('long')","ResetFilters()")) {
    if (-not $ini.Contains($action)) { Fail "Filter data bar is missing action $action." }
}

foreach ($prefix in @('UK','JP')) {
    foreach ($priceSection in @("Meter${prefix}Price","Meter${prefix}SecondaryPrice")) {
        $body=[regex]::Match($ini,'(?ms)^\['+[regex]::Escape($priceSection)+'\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if ($body -notmatch '(?im)^InlineSetting=Size\s*\|\s*(8|9)\s*$') { Fail "$priceSection must render market value smaller." }
        if ($body -notmatch '(?im)^InlineSetting2=Color\s*\|\s*#Muted#\s*$') { Fail "$priceSection must render market value muted." }
    }
    $primary=[regex]::Match($ini,'(?ms)^\[Meter'+$prefix+'Price\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if ($primary -notmatch ('(?im)^Text=#'+$prefix+'PriceText# \(#'+$prefix+'MarketValueText#\)\s*$')) { Fail "Primary $prefix price must show foreign price plus market value." }
    $secondary=[regex]::Match($ini,'(?ms)^\[Meter'+$prefix+'SecondaryPrice\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if ($secondary -notmatch ('(?im)^Text=#'+$prefix+'SecondaryPriceText# \(#'+$prefix+'SecondaryMarketValueText#\)\s*$')) { Fail "Secondary $prefix price must show foreign price plus market value." }

    foreach ($stockSection in @("Meter${prefix}StockHeader","Meter${prefix}SecondaryStockHeader")) {
        $body=[regex]::Match($ini,'(?ms)^\['+[regex]::Escape($stockSection)+'\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if ($body -notmatch '(?im)^InlineSetting=Color\s*\|\s*#Bad#\s*$' -or $body -notmatch '(?im)^InlinePattern=Out of Stock\s*$') { Fail "$stockSection must color only literal Out of Stock red." }
    }

    $secondaryGraph=[regex]::Match($ini,'(?ms)^\[Meter'+$prefix+'SecondaryGraph\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if ($secondaryGraph -notmatch ('(?im)^ImageName=#@#Generated\\#'+$prefix+'SecondaryGraphName#\s*$')) { Fail "$prefix secondary graph must use its item-specific image." }
}

foreach ($group in @('UKPrimaryBody','UKSecondaryHeader','UKSecondaryBody','JPPrimaryBody','JPSecondaryHeader','JPSecondaryBody')) {
    if ($ini -notmatch ('(?m)^Group='+[regex]::Escape($group)+'\s*$')) { Fail "Missing meter group '$group'." }
}

if ($ini -match '(?m)^\[MeasureCycleMode\]') { Fail 'Main skin must not expose slow CycleTravelMode measure.' }
if ($ini -match '(?m)^\[MeterUKStock\]\s*$' -or $ini -match '(?m)^\[MeterJPStock\]\s*$') { Fail 'Legacy body stock meters must remain removed.' }
if ($ini -match '(?im)^Text=Last Sold Out:') { Fail 'Last Sold Out must not occupy a body row.' }

if (-not (Test-Path -LiteralPath $stateReaderPath)) {
    Fail 'Missing StateReader.lua.'
} else {
    $stateReader=Get-Content -LiteralPath $stateReaderPath -Raw
    foreach ($token in @(
        'local function formatHoursMinutes(seconds)',
        "'Out of Stock for '..formatHoursMinutes(now-lastSoldOutAt)..' since '..os.date('%H:%M',lastSoldOutAt)",
        'restockEta>travelSeconds',
        "'Departure/window timing uses retained availability and depletion history'",
        'local function applyCardLayout()',
        'function ToggleCard(cardKey)',
        'function TogglePin(cardKey)',
        'function OpenFilter(filterName)',
        'function ToggleTripBand(band)',
        'function ResetFilters()',
        'showProfitableOnly and not cardProfitable[cardKey]',
        'ignoredItems[cardItemId[cardKey]]',
        "return '★'",
        'local top=88'
    )) {
        if (-not $stateReader.Contains($token)) { Fail "StateReader.lua missing required contract: $token" }
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Rainmeter skin validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Rainmeter skin static validation passed.' -ForegroundColor Green
exit 0
