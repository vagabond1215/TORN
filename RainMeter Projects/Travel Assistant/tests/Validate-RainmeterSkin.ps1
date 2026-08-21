$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
if (-not (Test-Path -LiteralPath $iniPath)) {
    Write-Host 'FAIL: TravelAssistant.ini is missing.' -ForegroundColor Red
    exit 1
}

$ini = Get-Content -LiteralPath $iniPath -Raw
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

if ($ini -match '(?im)^Measure=RunCommand\s*$') { Fail 'RunCommand must be declared as Measure=Plugin plus Plugin=RunCommand.' }

foreach ($sectionName in @('MeasureUpdate','MeasureSettings')) {
    $pattern = '(?ms)^\[' + [regex]::Escape($sectionName) + '\]\s*(.*?)(?=^\[|\z)'
    $match = [regex]::Match($ini, $pattern)
    if (-not $match.Success) { Fail "Missing Rainmeter section [$sectionName]."; continue }
    $body = $match.Groups[1].Value
    if ($body -notmatch '(?im)^Measure=Plugin\s*$') { Fail "[$sectionName] must declare Measure=Plugin." }
    if ($body -notmatch '(?im)^Plugin=RunCommand\s*$') { Fail "[$sectionName] must declare Plugin=RunCommand." }
    if ($body -notmatch '(?im)^Program=powershell\.exe\s*$') { Fail "[$sectionName] must execute powershell.exe." }
    if ($sectionName -eq 'MeasureUpdate' -and $body -notmatch '(?im)^Parameter=.*RunUpdate\.ps1') { Fail '[MeasureUpdate] must route through RunUpdate.ps1.' }
    if ($sectionName -eq 'MeasureSettings') {
        if ($body -notmatch '(?im)^Parameter=.*LaunchSettings\.ps1') { Fail '[MeasureSettings] must route through the short-lived LaunchSettings.ps1 wrapper.' }
        if ($body -match '(?im)^Timeout=-1\s*$') { Fail '[MeasureSettings] must not remain owned by RunCommand for the lifetime of the Settings dialog.' }
    }
}

$launcherPath = Join-Path $ProjectRoot '@Resources\Scripts\LaunchSettings.ps1'
if (-not (Test-Path -LiteralPath $launcherPath)) {
    Fail 'Missing @Resources\Scripts\LaunchSettings.ps1.'
} else {
    $launcher = Get-Content -LiteralPath $launcherPath -Raw
    if ($launcher -notmatch 'OpenSettings\.ps1') { Fail 'LaunchSettings.ps1 must start OpenSettings.ps1.' }
    if ($launcher -notmatch 'Start-Process') { Fail 'LaunchSettings.ps1 must detach the Settings dialog process.' }
    $tokens = $null; $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($launcherPath, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in LaunchSettings.ps1: $($parseError.Message)" }
}

if ($ini -notmatch '(?m)^OnRefreshAction=\[!CommandMeasure MeasureUpdate "Run"\]\s*$') { Fail 'OnRefreshAction must trigger MeasureUpdate Run.' }
if ($ini -notmatch '(?ms)^\[MeterSettings\].*?Text=SETTINGS\s+>') { Fail 'Top-right Settings meter is missing.' }
if ($ini -notmatch '(?m)^LeftMouseUpAction=\[!CommandMeasure MeasureSettings "Run"\]\s*$') { Fail 'Settings meter must trigger the MeasureSettings RunCommand measure.' }
if ($ini -match '(?m)^\[MeasureCycleMode\]') { Fail 'Main skin should no longer expose the slow CycleTravelMode RunCommand measure.' }

$titleMatch = [regex]::Match($ini, '(?ms)^\[MeterTitle\]\s*(.*?)(?=^\[|\z)')
if (-not $titleMatch.Success) { Fail 'Missing [MeterTitle].' }
else {
    $titleBody = $titleMatch.Groups[1].Value
    if ($titleBody -notmatch '(?im)^Text=Travel\s*$') { Fail 'Main header must display Travel.' }
    if ($titleBody -notmatch '(?im)^LeftMouseUpAction=\["https://www\.torn\.com/page\.php\?sid=travel"\]\s*$') { Fail 'Travel header must open the Torn travel page.' }
}

foreach ($flagSection in @('MeterUKFlag','MeterJPFlag')) {
    if ($ini -notmatch ('(?m)^\[' + [regex]::Escape($flagSection) + '\]\s*$')) { Fail "Missing [$flagSection] country flag meter." }
}
if ($ini -match '(?m)^\[MeterUKStatus\]\s*$' -or $ini -match '(?m)^\[MeterJPStatus\]\s*$') { Fail 'Redundant destination status footer meters must be removed.' }
if ($ini -match '(?i)click timing/status to verify on Weav3r') { Fail 'Redundant timing/status verification footer text is still present.' }
if ($ini -match '(?im)^Text=UNITED KINGDOM - XANAX\s*$' -or $ini -match '(?im)^Text=JAPAN - XANAX\s*$') { Fail 'Destination headings must use flag icons rather than country-name text.' }

foreach ($prefix in @('UK','JP')) {
    foreach ($sectionName in @("Meter${prefix}Plane", "Meter${prefix}RestockIcon", "Meter${prefix}Price", "Meter${prefix}StockHeader", "Meter${prefix}SecondaryTitle", "Meter${prefix}SecondaryPrice", "Meter${prefix}SecondaryStockHeader")) {
        if ($ini -notmatch ('(?m)^\[' + [regex]::Escape($sectionName) + '\]\s*$')) { Fail "Missing [$sectionName] compact card meter." }
    }

    $priceMatch = [regex]::Match($ini, '(?ms)^\[Meter' + $prefix + 'Price\]\s*(.*?)(?=^\[|\z)')
    if ($priceMatch.Success) {
        $priceBody = $priceMatch.Groups[1].Value
        if ($priceBody -notmatch ('(?im)^Text=#' + $prefix + 'PriceText# \(#' + $prefix + 'MarketValueText#\)\s*$')) { Fail "Meter${prefix}Price must show foreign price followed by parenthesized market value." }
        if ($priceBody -notmatch ('(?im)^FontColor=#' + $prefix + 'PriceColor#\s*$')) { Fail "Meter${prefix}Price must use dynamic profitability color." }
        if ($priceBody -notmatch '(?im)^InlineSetting=Size\s*\|\s*9\s*$') { Fail "Meter${prefix}Price must render parenthesized market value slightly smaller." }
        if ($priceBody -notmatch '(?im)^InlineSetting2=Color\s*\|\s*#Muted#\s*$') { Fail "Meter${prefix}Price market value must use muted text." }
    }

    $secondaryPriceMatch = [regex]::Match($ini, '(?ms)^\[Meter' + $prefix + 'SecondaryPrice\]\s*(.*?)(?=^\[|\z)')
    if ($secondaryPriceMatch.Success) {
        $secondaryBody = $secondaryPriceMatch.Groups[1].Value
        if ($secondaryBody -notmatch ('(?im)^Text=#' + $prefix + 'SecondaryPriceText# \(#' + $prefix + 'SecondaryMarketValueText#\)\s*$')) { Fail "Meter${prefix}SecondaryPrice must show foreign price followed by parenthesized market value." }
        if ($secondaryBody -notmatch '(?im)^InlineSetting=Size\s*\|\s*8\s*$') { Fail "Meter${prefix}SecondaryPrice must render parenthesized market value smaller than the foreign price." }
        if ($secondaryBody -notmatch '(?im)^Hidden=1\s*$') { Fail "Meter${prefix}SecondaryPrice should default hidden until state confirms a live active market." }
    }

    foreach ($stockSection in @("Meter${prefix}StockHeader", "Meter${prefix}SecondaryStockHeader")) {
        $stockMatch = [regex]::Match($ini, '(?ms)^\[' + [regex]::Escape($stockSection) + '\]\s*(.*?)(?=^\[|\z)')
        if (-not $stockMatch.Success) { Fail "Missing [$stockSection]." }
        else {
            $stockBody = $stockMatch.Groups[1].Value
            if ($stockBody -notmatch '(?im)^InlineSetting=Color\s*\|\s*#Bad#\s*$') { Fail "$stockSection must color the out-of-stock warning with #Bad#." }
            if ($stockBody -notmatch '(?im)^InlinePattern=Out of Stock\s*$') { Fail "$stockSection must apply warning color only to the words Out of Stock." }
        }
    }

    $restockIconMatch = [regex]::Match($ini, '(?ms)^\[Meter' + $prefix + 'RestockIcon\]\s*(.*?)(?=^\[|\z)')
    if (-not $restockIconMatch.Success) { Fail "Missing [Meter${prefix}RestockIcon]." }
    else {
        $iconBody = $restockIconMatch.Groups[1].Value
        if ($iconBody -notmatch '(?im)^Shape=Rectangle\s+1,3,10,7,1') { Fail "Meter${prefix}RestockIcon should render the delivery-truck cargo body." }
        if ($iconBody -notmatch '(?im)^Shape5=Ellipse\s+5,12,2,2') { Fail "Meter${prefix}RestockIcon should render delivery-truck wheels." }
        if ($iconBody -notmatch '(?im)^Hidden=1\s*$') { Fail "Meter${prefix}RestockIcon should default hidden until restock timing is actionable." }
    }

    $restockMatch = [regex]::Match($ini, '(?ms)^\[Meter' + $prefix + 'Restock\]\s*(.*?)(?=^\[|\z)')
    if (-not $restockMatch.Success) { Fail "Missing [Meter${prefix}Restock]." }
    else {
        $restockBody = $restockMatch.Groups[1].Value
        if ($restockBody -notmatch ('(?im)^Text=#' + $prefix + 'RestockText#\s*$')) { Fail "Meter${prefix}Restock must display only the restock value without a label." }
        if ($restockBody -notmatch '(?im)^X=146\s*$') { Fail "Meter${prefix}Restock must sit inline with the flight-time row at X=146." }
        if ($restockBody -notmatch '(?im)^Hidden=1\s*$') { Fail "Meter${prefix}Restock should default hidden until timing is actionable." }
    }

    $decisionMatch = [regex]::Match($ini, '(?ms)^\[Meter' + $prefix + 'Decision\]\s*(.*?)(?=^\[|\z)')
    if ($decisionMatch.Success -and $decisionMatch.Groups[1].Value -notmatch ('(?im)^ToolTipText=#' + $prefix + 'DecisionTooltipText#\s*$')) { Fail "Meter${prefix}Decision must expose timing context through the detailed tooltip variable." }
}

if ($ini -match '(?im)^Text=Travel:\s*#(?:UK|JP)TravelText#\s*$') { Fail 'Travel label should be replaced by the plane icon.' }
if ($ini -match '(?im)^Text=Restock:\s*#(?:UK|JP)RestockText#\s*$') { Fail 'Restock label should be replaced by the delivery-truck icon.' }
if ($ini -match '(?m)^\[MeterUKStock\]\s*$' -or $ini -match '(?m)^\[MeterJPStock\]\s*$') { Fail 'Legacy body stock meters must be removed; stock belongs in the item header.' }
if ($ini -match '(?im)^Text=Price:\s*#(?:UK|JP)PriceText#\s*$') { Fail 'Legacy labeled body price text must be removed; price belongs in the item header.' }
if ($ini -match '(?m)^\[MeterUKSoldOut\]\s*$' -or $ini -match '(?m)^\[MeterJPSoldOut\]\s*$' -or $ini -match '(?im)^Text=Last Sold Out:') { Fail 'Last Sold Out must not occupy a body row; sellout age/time belongs only in the out-of-stock header.' }

$stateReaderPath = Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
if (-not (Test-Path -LiteralPath $stateReaderPath)) { Fail 'Missing StateReader.lua.' }
else {
    $stateReader = Get-Content -LiteralPath $stateReaderPath -Raw
    foreach ($token in @(
        'local function formatHoursMinutes(seconds)',
        "'Out of Stock for ' .. formatHoursMinutes(now - lastSoldOutAt) .. ' since '",
        "os.date('%H:%M', lastSoldOutAt)",
        'restockEta > travelSeconds',
        'setRestockVisibility(prefix, showRestock)',
        "'Departure/window timing uses retained availability and depletion history'",
        "setVariable(prefix .. 'MarketValueText', formatMoney(marketValue))",
        'local function updateSecondaryItem(data, prefix)',
        "setVariable(prefix .. 'SecondaryMarketValueText', formatMoney(marketValue))"
    )) {
        if (-not $stateReader.Contains($token)) { Fail "StateReader.lua is missing required presentation contract: $token" }
    }
}

if ($errors.Count -gt 0) {
    foreach ($errorMessage in $errors) { Write-Host "FAIL: $errorMessage" -ForegroundColor Red }
    Write-Host "Rainmeter skin validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Rainmeter skin static validation passed.' -ForegroundColor Green
exit 0
