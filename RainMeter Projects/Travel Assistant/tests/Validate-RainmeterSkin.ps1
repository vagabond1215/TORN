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
        if ($body -notmatch '(?im)^Parameter=.*LaunchSettings\.ps1') { Fail '[MeasureSettings] must route through the detached LaunchSettings.ps1 wrapper.' }
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
if ($ini -match '(?m)^\[MeasureCycleMode\]') { Fail 'Main skin should not expose the slow CycleTravelMode RunCommand measure.' }
if ($ini -notmatch '(?m)^MaxExpandedCards=2\s*$') { Fail 'Default independent-card expansion cap must be two.' }

$titleMatch = [regex]::Match($ini, '(?ms)^\[MeterTitle\]\s*(.*?)(?=^\[|\z)')
if (-not $titleMatch.Success) { Fail 'Missing [MeterTitle].' }
else {
    $titleBody = $titleMatch.Groups[1].Value
    if ($titleBody -notmatch '(?im)^Text=Travel\s*$') { Fail 'Main header must display Travel.' }
    if ($titleBody -notmatch '(?im)^LeftMouseUpAction=\["https://www\.torn\.com/page\.php\?sid=travel"\]\s*$') { Fail 'Travel header must open the Torn travel page.' }
}

foreach ($sectionName in @(
    'MeterUKCard','MeterUKSecondaryCard','MeterJPCard','MeterJPSecondaryCard',
    'MeterUKFlag','MeterUKSecondaryFlag','MeterJPFlag','MeterJPSecondaryFlag',
    'MeterUKGraph','MeterUKSecondaryGraph','MeterJPGraph','MeterJPSecondaryGraph',
    'MeterUKExpand','MeterUKSecondaryExpand','MeterJPExpand','MeterJPSecondaryExpand'
)) {
    if ($ini -notmatch ('(?m)^\[' + [regex]::Escape($sectionName) + '\]\s*$')) { Fail "Missing independent card section [$sectionName]." }
}

foreach ($prefix in @('UK','JP')) {
    foreach ($priceSection in @("Meter${prefix}Price", "Meter${prefix}SecondaryPrice")) {
        $match = [regex]::Match($ini, '(?ms)^\[' + [regex]::Escape($priceSection) + '\]\s*(.*?)(?=^\[|\z)')
        if (-not $match.Success) { Fail "Missing [$priceSection]."; continue }
        $body = $match.Groups[1].Value
        if ($body -notmatch '(?im)^InlineSetting=Size\s*\|\s*(8|9)\s*$') { Fail "$priceSection must render the parenthesized market value smaller." }
        if ($body -notmatch '(?im)^InlineSetting2=Color\s*\|\s*#Muted#\s*$') { Fail "$priceSection must render market value in muted text." }
    }

    $primaryPrice = [regex]::Match($ini, '(?ms)^\[Meter' + $prefix + 'Price\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if ($primaryPrice -notmatch ('(?im)^Text=#' + $prefix + 'PriceText# \(#' + $prefix + 'MarketValueText#\)\s*$')) { Fail "Meter${prefix}Price must show foreign price followed by parenthesized market value." }
    if ($primaryPrice -notmatch ('(?im)^FontColor=#' + $prefix + 'PriceColor#\s*$')) { Fail "Meter${prefix}Price must use dynamic profitability color." }

    $secondaryPrice = [regex]::Match($ini, '(?ms)^\[Meter' + $prefix + 'SecondaryPrice\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if ($secondaryPrice -notmatch ('(?im)^Text=#' + $prefix + 'SecondaryPriceText# \(#' + $prefix + 'SecondaryMarketValueText#\)\s*$')) { Fail "Meter${prefix}SecondaryPrice must show foreign price followed by parenthesized market value." }

    foreach ($stockSection in @("Meter${prefix}StockHeader", "Meter${prefix}SecondaryStockHeader")) {
        $stockMatch = [regex]::Match($ini, '(?ms)^\[' + [regex]::Escape($stockSection) + '\]\s*(.*?)(?=^\[|\z)')
        if (-not $stockMatch.Success) { Fail "Missing [$stockSection]."; continue }
        $stockBody = $stockMatch.Groups[1].Value
        if ($stockBody -notmatch '(?im)^InlineSetting=Color\s*\|\s*#Bad#\s*$') { Fail "$stockSection must color the out-of-stock warning with #Bad#." }
        if ($stockBody -notmatch '(?im)^InlinePattern=Out of Stock\s*$') { Fail "$stockSection must apply warning color only to the words Out of Stock." }
    }

    $restockIcon = [regex]::Match($ini, '(?ms)^\[Meter' + $prefix + 'RestockIcon\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if ($restockIcon -notmatch '(?im)^Shape=Rectangle\s+1,3,10,7,1') { Fail "Meter${prefix}RestockIcon should render the delivery-truck cargo body." }
    if ($restockIcon -notmatch '(?im)^Shape5=Ellipse\s+5,12,2,2') { Fail "Meter${prefix}RestockIcon should render delivery-truck wheels." }
    if ($restockIcon -notmatch '(?im)^Hidden=1\s*$') { Fail "Meter${prefix}RestockIcon should default hidden." }

    $decision = [regex]::Match($ini, '(?ms)^\[Meter' + $prefix + 'Decision\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if ($decision -notmatch ('(?im)^ToolTipText=#' + $prefix + 'DecisionTooltipText#\s*$')) { Fail "Meter${prefix}Decision must expose timing context in its tooltip." }

    $secondaryGraph = [regex]::Match($ini, '(?ms)^\[Meter' + $prefix + 'SecondaryGraph\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if ($secondaryGraph -notmatch ('(?im)^ImageName=#@#Generated\\#' + $prefix + 'SecondaryGraphName#\s*$')) { Fail "Meter${prefix}SecondaryGraph must use the item's own generated graph." }
}

foreach ($group in @('UKPrimaryBody','UKSecondaryHeader','UKSecondaryBody','JPPrimaryBody','JPSecondaryHeader','JPSecondaryBody')) {
    if ($ini -notmatch ('(?m)^Group=' + [regex]::Escape($group) + '\s*$')) { Fail "Missing independent meter group '$group'." }
}
if ($ini -notmatch "ToggleCard\('UKPrimary'\)" -or $ini -notmatch "ToggleCard\('UKSecondary'\)" -or $ini -notmatch "ToggleCard\('JPPrimary'\)" -or $ini -notmatch "ToggleCard\('JPSecondary'\)") {
    Fail 'Every item card header must expose expand/collapse behavior.'
}

if ($ini -match '(?im)^Text=Travel:\s*#(?:UK|JP)TravelText#\s*$') { Fail 'Travel label should be replaced by the plane icon.' }
if ($ini -match '(?im)^Text=Restock:\s*#(?:UK|JP)RestockText#\s*$') { Fail 'Restock label should be replaced by the delivery-truck icon.' }
if ($ini -match '(?m)^\[MeterUKStock\]\s*$' -or $ini -match '(?m)^\[MeterJPStock\]\s*$') { Fail 'Legacy body stock meters must remain removed.' }
if ($ini -match '(?im)^Text=Last Sold Out:') { Fail 'Last Sold Out must not occupy a body row.' }

$stateReaderPath = Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
if (-not (Test-Path -LiteralPath $stateReaderPath)) { Fail 'Missing StateReader.lua.' }
else {
    $stateReader = Get-Content -LiteralPath $stateReaderPath -Raw
    foreach ($token in @(
        'local function formatHoursMinutes(seconds)',
        "'Out of Stock for ' .. formatHoursMinutes(now - lastSoldOutAt) .. ' since '",
        "os.date('%H:%M', lastSoldOutAt)",
        'restockEta > travelSeconds',
        "setRestockVisibility('UK', cardExpanded.UKPrimary and restockWanted.UK)",
        "'Departure/window timing uses retained availability and depletion history'",
        "setVariable(prefix .. 'MarketValueText', formatMoney(marketValue))",
        'local function updateSecondaryItem(data, prefix)',
        "setVariable(prefix .. 'SecondaryMarketValueText', formatMoney(marketValue))",
        'local function applyCardLayout()',
        'function ToggleCard(cardKey)',
        'countExpandedCards() >= maxExpandedCards'
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
