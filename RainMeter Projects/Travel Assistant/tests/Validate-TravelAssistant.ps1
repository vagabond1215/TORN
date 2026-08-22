$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

$required = @(
    'TravelAssistant.ini','AGENTS.md','Readme.md','Install.ps1',
    'config\countries.json','config\travel-modes.json','config\travel-perks.json','config\settings.example.json','config\settings.local.example.json',
    'data\seed\metadata.json','data\seed\observations.jsonl','data\seed\cycles.jsonl',
    '@Resources\Scripts\RunUpdate.ps1','@Resources\Scripts\ShadowCollector.ps1','@Resources\Scripts\TravelContext.ps1',
    '@Resources\Scripts\OptimalRoute.ps1','@Resources\Scripts\OpportunityState.ps1','@Resources\Scripts\FilterPreferences.ps1','@Resources\Scripts\FilterState.ps1',
    '@Resources\Scripts\StateReader.lua','@Resources\Scripts\LaunchItemViewer.ps1','@Resources\Scripts\OpenItemViewer.ps1','@Resources\Scripts\RenderInlineGraph.ps1',
    'tests\Validate-RainmeterSkin.ps1','tests\Validate-ItemViewer.ps1','tests\Run-OpportunityStateTests.ps1'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot $relative))) { Fail "Missing required file: $relative" }
}

foreach ($relative in @('config\countries.json','config\travel-modes.json','config\travel-perks.json','config\settings.example.json','config\settings.local.example.json','data\seed\metadata.json')) {
    $path = Join-Path $ProjectRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { continue }
    try {
        $obj = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if (-not $obj.PSObject.Properties['schemaVersion']) { Fail "$relative does not declare schemaVersion." }
    } catch { Fail "Invalid JSON in ${relative}: $($_.Exception.Message)" }
}

$countriesPath = Join-Path $ProjectRoot 'config\countries.json'
if (Test-Path -LiteralPath $countriesPath) {
    $countries = Get-Content -LiteralPath $countriesPath -Raw | ConvertFrom-Json
    $collect = @($countries.countries | Where-Object { $_.collect -eq $true })
    if ($collect.Count -ne 11) { Fail "Expected 11 collect=true destinations; found $($collect.Count)." }
    foreach ($country in $collect) {
        if ([string]$country.tripBand -notin @('short','medium','long')) { Fail "Country '$($country.id)' lacks valid tripBand." }
        foreach ($mode in @('standard','airstrip','wlt','business')) {
            if (-not $country.travelSeconds.PSObject.Properties[$mode] -or [long]$country.travelSeconds.$mode -le 0) { Fail "Country '$($country.id)' lacks positive $mode travelSeconds." }
        }
    }
}

$settingsPath = Join-Path $ProjectRoot 'config\settings.example.json'
if (Test-Path -LiteralPath $settingsPath) {
    $settings = Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    if ([int]$settings.graphWindowHours -ne 8) { Fail 'Visible stock history must remain eight hours.' }
    if ([int]$settings.highResolutionRetentionHours -lt 48) { Fail 'High-resolution retention must remain at least 48 hours.' }
    if ([int]$settings.cycleRetentionDays -lt 90) { Fail 'Completed-cycle retention must remain at least 90 days.' }
    if ([double]$settings.profitability.itemMarketFeePercent -ne 0) { Fail 'Default Item Market fee must remain zero.' }
}

$parsePaths = @(
    Get-ChildItem -LiteralPath (Join-Path $ProjectRoot '@Resources\Scripts') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'tests') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'tools') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
    Get-Item -LiteralPath (Join-Path $ProjectRoot 'Install.ps1') -ErrorAction SilentlyContinue
)
foreach ($file in $parsePaths) {
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in $($file.Name): $($parseError.Message)" }
}

$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
if (Test-Path -LiteralPath $wrapperPath) {
    $wrapper = Get-Content -LiteralPath $wrapperPath -Raw
    foreach ($token in @('ShadowCollector.ps1','TravelContext.ps1','OptimalRoute.ps1','OpportunityState.ps1','FilterState.ps1','ResaleQueue.ps1','Write-UpdateHeartbeat')) {
        if (-not $wrapper.Contains($token)) { Fail "RunUpdate.ps1 missing '$token'." }
    }
    if ($wrapper.Contains('VisibleItems.ps1')) { Fail 'Normal runtime must not regenerate retired default graphs.' }
}

$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
if (Test-Path -LiteralPath $iniPath) {
    $ini = Get-Content -LiteralPath $iniPath -Raw
    if ($ini -notmatch '(?m)^Version=0\.6\.0\s*$') { Fail 'Rainmeter skin must report version 0.6.0.' }
    foreach ($section in @('[MeasureUpdate]','[MeasureState]','[MeasureItemViewer]','[MeterViewer]','[MeterOpportunity1Card]','[MeterOpportunity1Rank]','[MeterOpportunity1Graph]')) {
        if (-not $ini.Contains($section)) { Fail "Rainmeter skin missing compatibility section $section" }
    }
    foreach ($retired in @('[MeterRouteCard]','[MeterUKCard]','[MeterJPCard]','MaxExpandedCards=')) {
        if ($ini.Contains($retired)) { Fail "Rainmeter skin contains retired primary-view contract '$retired'." }
    }
}

$opportunityPath = Join-Path $ProjectRoot '@Resources\Scripts\OpportunityState.ps1'
if (Test-Path -LiteralPath $opportunityPath) {
    $opportunity = Get-Content -LiteralPath $opportunityPath -Raw
    foreach ($token in @('grossProfit','profitPerHour','Get-OpportunityNextWindow',"sortMode -eq 'name'","sortMode -eq 'gross'","sortMode -eq 'profit_per_hour'",'probabilityKnown',"'LEARNING'",'$availableQuantity = $stock')) {
        if (-not $opportunity.Contains($token)) { Fail "Opportunity model missing '$token'." }
    }
    if ($opportunity -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'Opportunity projection must remain local-only.' }
}

$readerPath = Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
if (Test-Path -LiteralPath $readerPath) {
    $reader = Get-Content -LiteralPath $readerPath -Raw
    foreach ($token in @(
        "'NAME'","'UPCOMING'","'GROSS PROFIT'","'PROFIT/HR'",
        'ToggleInlineGraph','applyFlagForRow','graphExtra','runViewerMeasure',
        "SKIN:Bang('!UpdateMeasure', 'MeasureItemViewer')","runViewerMeasure('inline_' .. key)",
        "setShape(meter,15,'Line 103.5,76,103.5,150","setShape(meter,21,'Line 460.5,76,460.5,150",
        "SKIN:Bang('!SetOption', p .. 'Rank', 'Text', safeText(data[prefix .. 'TimeText'], ''))",
        "SKIN:Bang('!SetOption', p .. 'Optimal', 'Text', '0')","SKIN:Bang('!SetOption', p .. 'Time', 'Text', '-8h')"
    )) {
        if (-not $reader.Contains($token)) { Fail "StateReader compact-card/chart contract missing '$token'." }
    }
    foreach ($retired in @('Loading 8-hour stock history','Fill Color 248,248,248,255',"'Text', 'now'")) {
        if ($reader.Contains($retired)) { Fail "StateReader retains retired chart/flag behavior '$retired'." }
    }
}

$rendererPath = Join-Path $ProjectRoot '@Resources\Scripts\RenderInlineGraph.ps1'
if (Test-Path -LiteralPath $rendererPath) {
    $renderer = Get-Content -LiteralPath $rendererPath -Raw
    foreach ($token in @('GraphPath','MaxStock','RuntimeObservationFile','SeedObservationFile','inline-graph-','display_carry','[System.IO.File]::ReadLines')) {
        if (-not $renderer.Contains($token)) { Fail "Inline renderer missing '$token'." }
    }
    foreach ($retired in @('PointCount','ChangeCount','retained point(s)','change(s)')) {
        if ($renderer.Contains($retired)) { Fail "Inline renderer retains retired visible summary '$retired'." }
    }
    if ($renderer -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'Inline renderer must remain local-only.' }
}

$git = Get-Command git -ErrorAction SilentlyContinue
if ($null -ne $git) {
    Push-Location $ProjectRoot
    try {
        foreach ($relative in @('data/runtime/probe.tmp','@Resources/Generated/probe.tmp','config/settings.local.json')) {
            $ignored = & git check-ignore $relative 2>$null
            if ([string]::IsNullOrWhiteSpace(($ignored | Out-String))) { Fail "$relative is not ignored by Git." }
        }
    } finally { Pop-Location }
}

if ($errors.Count -gt 0) {
    foreach ($err in $errors) { Write-Host "FAIL: $err" -ForegroundColor Red }
    Write-Host "Validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Travel Assistant 0.6 static architecture validation passed.' -ForegroundColor Green
Write-Host 'Compact flag cards, direct inline-only eight-hour history, hourly grid, sparse axis labels, separate Viewer, transparent sorting, and in-stock learning visibility contracts are present.'
exit 0
