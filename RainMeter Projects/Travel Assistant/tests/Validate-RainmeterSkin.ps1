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
if ($ini -notmatch '(?m)^Version=0\.6\.0\s*$') { Fail 'Opportunity-list skin must report version 0.6.0.' }
if ($ini -notmatch '(?m)^OnRefreshAction=\[!CommandMeasure MeasureUpdate "Run"\]\s*$') { Fail 'OnRefreshAction must trigger MeasureUpdate.' }

foreach ($sectionName in @('MeasureUpdate','MeasureSettings','MeasureFilterPopup','MeasureItemViewer','MeasurePreferenceAction')) {
    $match=[regex]::Match($ini,'(?ms)^\['+[regex]::Escape($sectionName)+'\]\s*(.*?)(?=^\[|\z)')
    if (-not $match.Success) { Fail "Missing Rainmeter section [$sectionName]."; continue }
    $body=$match.Groups[1].Value
    if ($body -notmatch '(?im)^Measure=Plugin\s*$' -or $body -notmatch '(?im)^Plugin=RunCommand\s*$' -or $body -notmatch '(?im)^Program=powershell\.exe\s*$') { Fail "[$sectionName] must be a PowerShell RunCommand plugin measure." }
}

$updateBody=[regex]::Match($ini,'(?ms)^\[MeasureUpdate\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if ($updateBody -notmatch '(?im)^Parameter=.*RunUpdate\.ps1') { Fail 'MeasureUpdate must route through RunUpdate.ps1.' }
$settingsBody=[regex]::Match($ini,'(?ms)^\[MeasureSettings\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if ($settingsBody -notmatch '(?im)^Parameter=.*LaunchOptimizerSettings\.ps1') { Fail 'Main Settings action must open opportunity settings.' }
$popupBody=[regex]::Match($ini,'(?ms)^\[MeasureFilterPopup\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if ($popupBody -notmatch '(?im)^Parameter=.*LaunchFilterPopup\.ps1.*#FilterRequest#') { Fail 'Filter popup must use its detached launcher and dynamic request.' }
$viewerBody=[regex]::Match($ini,'(?ms)^\[MeasureItemViewer\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if ($viewerBody -notmatch '(?im)^Parameter=.*LaunchItemViewer\.ps1.*-MarketKey.*#ViewerMarketKey#') { Fail 'Item viewer must route through its stable market-key launcher.' }
$prefBody=[regex]::Match($ini,'(?ms)^\[MeasurePreferenceAction\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if ($prefBody -notmatch '(?im)^Parameter=.*FilterPreferences\.ps1.*#PreferenceAction#.*#PreferenceValue#') { Fail 'Quick actions must route through FilterPreferences.ps1.' }

$popupHostPath=Join-Path $ProjectRoot '@Resources\Scripts\PopupHost.ps1'
if (-not (Test-Path -LiteralPath $popupHostPath)) { Fail 'Missing PopupHost.ps1.' }
else {
    $hostText=Get-Content -LiteralPath $popupHostPath -Raw
    foreach($token in @('OpenOptimizerSettings.ps1','OpenFilterPopup.ps1','OpenItemViewer.ps1','RuntimeLog.ps1')) {
        if(-not $hostText.Contains($token)){Fail "PopupHost.ps1 missing '$token'."}
    }
}

foreach ($launcherName in @('LaunchOptimizerSettings.ps1','LaunchFilterPopup.ps1','LaunchItemViewer.ps1')) {
    $path=Join-Path $ProjectRoot ('@Resources\Scripts\'+$launcherName)
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing $launcherName."; continue }
    $text=Get-Content -LiteralPath $path -Raw
    foreach($token in @('PopupHost.ps1','Start-Process','-WindowStyle Hidden','-STA','$arguments','exit 0')) {
        if (-not $text.Contains($token)) { Fail "$launcherName missing hidden popup-host contract '$token'." }
    }
    if ($text.Contains('-WindowStyle Normal')) { Fail "$launcherName must not leave a visible PowerShell console." }
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in ${launcherName}: $($parseError.Message)" }
}

$title=[regex]::Match($ini,'(?ms)^\[MeterTitle\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if ($title -notmatch '(?im)^Text=Travel\s*$') { Fail 'Main header must display Travel.' }
if ($title -notmatch '(?im)^LeftMouseUpAction=\["https://www\.torn\.com/page\.php\?sid=travel"\]\s*$') { Fail 'Travel header must open Torn travel.' }

foreach ($section in @(
    'MeterFilterTopLine','MeterItemFilter','MeterTripShort','MeterTripMedium','MeterTripLong','MeterTripExpand','MeterCategoryFilter','MeterFilterReset','MeterFilterBottomLine',
    'MeterSortLabel','MeterSortOptimal','MeterSortUpcoming','MeterSortProfit','MeterSortTime','MeterViewer','MeterSortBottomLine','MeterOpportunityMessage'
)) {
    if ($ini -notmatch ('(?m)^\['+[regex]::Escape($section)+'\]\s*$')) { Fail "Missing internal compatibility section [$section]." }
}

foreach ($action in @(
    "OpenFilter('Item')","OpenFilter('Country')","OpenFilter('Category')","ToggleTripBand('short')","ToggleTripBand('medium')","ToggleTripBand('long')","ResetFilters()","OpenViewer('')"
)) {
    if (-not $ini.Contains($action)) { Fail "Opportunity surface is missing action $action." }
}

for ($i=1; $i -le 8; $i++) {
    foreach ($suffix in @('Card','Rank','Optimal','Name','Country','Gross','Window','Leave','Chance','Time','Price','Graph')) {
        $section='MeterOpportunity'+$i+$suffix
        if ($ini -notmatch ('(?m)^\['+[regex]::Escape($section)+'\]\s*$')) { Fail "Missing opportunity row compatibility meter [$section]." }
    }
    $priceBody=[regex]::Match($ini,'(?ms)^\[MeterOpportunity'+$i+'Price\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if ($priceBody -notmatch '(?im)^InlineSetting=Size\s*\|\s*7\s*$' -or $priceBody -notmatch '(?im)^InlineSetting2=Color\s*\|\s*#Muted#\s*$') { Fail "Opportunity $i must render parenthesized MV smaller and muted." }
    if ($priceBody -notmatch ('(?im)^Text=#Opportunity'+$i+'PriceText# \(#Opportunity'+$i+'MarketValueText#\)\s*$')) { Fail "Opportunity $i price must show foreign value followed by MV in parentheses." }
    $graphBody=[regex]::Match($ini,'(?ms)^\[MeterOpportunity'+$i+'Graph\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if ($graphBody -notmatch '(?im)^Text=GRAPH\s*$' -or -not $graphBody.Contains("OpenViewer('#Opportunity${i}Key#')")) { Fail "Opportunity $i GRAPH control must open its stable market-key viewer." }
}

foreach ($retiredSection in @('MeterRouteCard','MeterRouteTitle','MeterRouteValue','MeterRouteMeta','MeterRouteMessage','MeterOptimalItem1Name','MeterUKCard','MeterJPCard')) {
    if ($ini -match ('(?m)^\['+[regex]::Escape($retiredSection)+'\]\s*$')) { Fail "Primary opportunity view must not contain retired single-route/card meter [$retiredSection]." }
}

if (-not (Test-Path -LiteralPath $stateReaderPath)) {
    Fail 'Missing StateReader.lua.'
} else {
    $stateReader=Get-Content -LiteralPath $stateReaderPath -Raw
    foreach ($token in @(
        'local function stabilizeProjection(data)',
        'lastProjectionData = copyProjectionFields(initial)',
        'local function configureInteractiveMeters()',
        "'NAME'","'UPCOMING'","'GROSS PROFIT'","'PROFIT/HR'","SetSortMode('name')","SetSortMode('profit_per_hour')",
        "SKIN:Bang('!HideMeter', 'MeterSortTime')",
        "SKIN:Bang('!HideMeter', 'MeterOpportunity' .. i .. 'Optimal')",
        "SKIN:Bang('!SetOption', 'MeterOpportunity' .. i .. 'Name', 'X', '48')",
        "'SolidColor', '0,0,0,1'",
        'local function currentOpportunityRows(data)',
        'local function sortOpportunityRows(rows, mode)',
        'local function locallySortedProjection(data, mode)',
        'local function updateSort(mode)',
        'pendingSortMode = mode',
        'local function updateOpportunities(data)',
        'local function updateOpportunityGrossMeter(data, prefix, index)',
        "display = display .. ' gross'",
        'QuantityText','ProfitHourText','GrossValue','ProfitHourValue','WindowStartAt',
        "setGroupVisible('OpportunityRow' .. i, i <= count)",
        'function SetSortMode(mode)',
        'function OpenViewer(marketKey)',
        'function OpenFilter(filterName)',
        'function ToggleTripBand(band)',
        'function ResetFilters()',
        'local function deferPolling(seconds)',
        "setVariable('PanelHeight'"
    )) {
        if (-not $stateReader.Contains($token)) { Fail "StateReader.lua missing opportunity-list contract: $token" }
    }
    foreach ($retiredToken in @('updateOptimal(data, now)','OptimalItemRow','MeterRouteMessage','ToggleCard(','cardExpanded')) {
        if ($stateReader.Contains($retiredToken)) { Fail "StateReader.lua must not retain retired primary-view token '$retiredToken'." }
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Rainmeter opportunity skin validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Rainmeter opportunity surface + immediate four-sort controls + refresh-stable projection + responsive hitboxes + hidden popup host validation passed.' -ForegroundColor Green
exit 0
