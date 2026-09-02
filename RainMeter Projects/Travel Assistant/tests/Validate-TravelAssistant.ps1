$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

$required = @(
    'TravelAssistant.ini','AGENTS.md','Readme.md','Install.ps1',
    'config\countries.json','config\travel-modes.json','config\travel-perks.json','config\settings.example.json','config\settings.local.example.json',
    'data\seed\metadata.json','data\seed\observations.jsonl','data\seed\cycles.jsonl',
    '@Resources\Includes\OpportunityRows.inc',
    '@Resources\Scripts\RunUpdate.ps1','@Resources\Scripts\ShadowCollector.ps1','@Resources\Scripts\UpdateTracker.ps1','@Resources\Scripts\ProjectCollectedState.ps1','@Resources\Scripts\MaintainObservationHistory.ps1','@Resources\Scripts\TravelContext.ps1',
    '@Resources\Scripts\OptimalRoute.ps1','@Resources\Scripts\OpportunityState.ps1','@Resources\Scripts\FilterPreferences.ps1','@Resources\Scripts\FilterState.ps1','@Resources\Scripts\StochasticForecast.ps1','@Resources\Scripts\StochasticCalibration.ps1','@Resources\Scripts\MultiCycleChanceBridge.ps1',
    '@Resources\Scripts\StateReader.lua','@Resources\Scripts\RenderInlineGraph.ps1','@Resources\Scripts\EnsureItemImages.ps1',
    '@Resources\Images\Flags\LICENSE-FlagKit.txt','@Resources\Images\UI\flag-mask-both.png','@Resources\Images\UI\flag-mask-top.png','@Resources\Images\UI\flag-mask-bottom.png',
    'tests\Validate-RainmeterSkin.ps1','tests\Run-OpportunityStateTests.ps1','tests\Run-StochasticForecastTests.ps1','tests\Run-StochasticCalibrationTests.ps1','tests\Run-MultiCycleChanceBridgeTests.ps1','tools\Invoke-StochasticReplay.ps1'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot $relative))) { Fail "Missing required file: $relative" }
}

# These belonged to retired independent-card / pin surfaces and should not be
# shipped or reintroduced by packaging.
foreach ($relative in @(
    '@Resources\Scripts\CardPreference.ps1',
    '@Resources\Scripts\VisibleItems.ps1',
    '@Resources\Scripts\GraphHover.lua',
    '@Resources\Scripts\BuildGraphHoverData.ps1',
    '@Resources\Scripts\WindowTooltipTweaks.lua',
    '@Resources\Scripts\EnsureUiAssets.ps1',
    '@Resources\Includes\GraphHover.inc',
    'tests\Validate-GraphHover.ps1',
    'tests\Validate-WindowTooltipTweaks.ps1',
    'tests\Run-VisibleItemsTests.ps1',
    'tests\Validate-VisibleItems.ps1'
)) {
    if (Test-Path -LiteralPath (Join-Path $ProjectRoot $relative)) { Fail "Retired file returned: $relative" }
}

foreach ($relative in @('config\countries.json','config\travel-modes.json','config\travel-perks.json','config\settings.example.json','config\settings.local.example.json','data\seed\metadata.json')) {
    $path=Join-Path $ProjectRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { continue }
    try {
        $obj=Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        if (-not $obj.PSObject.Properties['schemaVersion']) { Fail "$relative does not declare schemaVersion." }
    } catch { Fail "Invalid JSON in ${relative}: $($_.Exception.Message)" }
}

$countriesPath=Join-Path $ProjectRoot 'config\countries.json'
if (Test-Path -LiteralPath $countriesPath) {
    $countries=Get-Content -LiteralPath $countriesPath -Raw | ConvertFrom-Json
    $collect=@($countries.countries | Where-Object { $_.collect -eq $true })
    if ($collect.Count -ne 11) { Fail "Expected 11 collect=true destinations; found $($collect.Count)." }
    foreach($country in $collect) {
        if ([string]$country.tripBand -notin @('short','medium','long')) { Fail "Country '$($country.id)' lacks valid tripBand." }
    }
}

$settingsPath=Join-Path $ProjectRoot 'config\settings.example.json'
if (Test-Path -LiteralPath $settingsPath) {
    $settings=Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json
    if ([int]$settings.graphWindowHours -ne 8) { Fail 'Visible stock history must remain eight hours.' }
    if ([int]$settings.highResolutionRetentionHours -ne 48) { Fail 'High-resolution retention must remain 48 hours.' }
    if ([int]$settings.cycleRetentionDays -ne 90) { Fail 'Completed-cycle retention must remain 90 days.' }
}

$parsePaths=@(
    Get-ChildItem -LiteralPath (Join-Path $ProjectRoot '@Resources\Scripts') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'tests') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
    Get-ChildItem -LiteralPath (Join-Path $ProjectRoot 'tools') -Filter '*.ps1' -File -ErrorAction SilentlyContinue
    Get-Item -LiteralPath (Join-Path $ProjectRoot 'Install.ps1') -ErrorAction SilentlyContinue
)
foreach($file in $parsePaths) {
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($file.FullName,[ref]$tokens,[ref]$parseErrors)
    foreach($parseError in @($parseErrors)){ Fail "PowerShell parse error in $($file.Name): $($parseError.Message)" }
}

$iniPath=Join-Path $ProjectRoot 'TravelAssistant.ini'
if (Test-Path -LiteralPath $iniPath) {
    $ini=Get-Content -LiteralPath $iniPath -Raw
    foreach($token in @('@IncludeRows=#@#Includes\OpportunityRows.inc','[MeasureInlineGraph]','[MeasureItemImages]','VisibleItemImageIds=','[MeterSortUpcoming]','[MeterSortGross]','[MeterSortProfitHour]')) {
        if (-not $ini.Contains($token)) { Fail "Rainmeter skin missing '$token'." }
    }
    if ($ini.Contains('@Include=#@#Includes\OpportunityRows.inc')) { Fail 'Opportunity rows must not be included before MeterBackground.' }
    foreach($retired in @('[MeterRouteCard]','[MeterUKCard]','[MeterJPCard]','[MeterSortName]','[MeterSortNameButton]','[MeterViewer]','[MeasureItemViewer]','[MeterSortOptimal]','[MeterOpportunity1Rank]','[MeasureWindowTooltipTweaks]','[MeasureGraphHover]','[MeasureGraphHoverData]')) {
        if ($ini.Contains($retired)) { Fail "Rainmeter skin contains retired UI token '$retired'." }
    }
}

$wrapperPath=Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
if (Test-Path -LiteralPath $wrapperPath) {
    $wrapper=Get-Content -LiteralPath $wrapperPath -Raw
    foreach($token in @('ProjectCollectedState.ps1','$CollectedState',"if (`$Action -eq 'Update')",'ShadowCollector is the sole live foreign-stock request','UpdateTracker returned failure.')) {
        if (-not $wrapper.Contains($token)) { Fail "RunUpdate single-owner collection contract missing '$token'." }
    }
    $normalBlock=[regex]::Match($wrapper,'(?ms)if \(\$Action -eq ''Update''\) \{(.*?)\} else \{').Groups[1].Value
    if ([string]::IsNullOrWhiteSpace($normalBlock)) { Fail 'Could not identify normal Update block in RunUpdate.ps1.' }
    elseif ($normalBlock -match '&\s*\$Updater') { Fail 'Normal Update must not invoke UpdateTracker; it would duplicate provider requests/history writes.' }
}

$collectorPath=Join-Path $ProjectRoot '@Resources\Scripts\ShadowCollector.ps1'
if (Test-Path -LiteralPath $collectorPath) {
    $collector=Get-Content -LiteralPath $collectorPath -Raw
    foreach($token in @(
        '[int]$MinimumPollIntervalSeconds = 60',
        'function Test-ObservationChanged',
        'return ([int]$DestState.lastStock -ne [int]$Observation.stock)',
        'Append-JsonLine -Path $ObservationFile -Value $observation',
        'Update-CycleState -DestState $destState -Observation $observation',
        'Append-JsonLine -Path $CycleFile -Value $completed',
        'previousSellOutBoundaryQuality = $previousSelloutQuality'
    )) {
        if (-not $collector.Contains($token)) { Fail "ShadowCollector authoritative-history contract missing '$token'." }
    }
    foreach($retired in @('Test-IsPrimaryMarket','primaryItemIds','primaryCountryIds')) {
        if ($collector.Contains($retired)) { Fail "ShadowCollector retains split-history ownership token '$retired'." }
    }
}

$projectorPath=Join-Path $ProjectRoot '@Resources\Scripts\ProjectCollectedState.ps1'
if (Test-Path -LiteralPath $projectorPath) {
    $projector=Get-Content -LiteralPath $projectorPath -Raw
    foreach($token in @('observedMarkets','TravelMode','TravelSeconds','LiveProvider','shadowCollection','Write-ProjectionKvAtomic')) {
        if (-not $projector.Contains($token)) { Fail "ProjectCollectedState.ps1 missing '$token'." }
    }
    if ($projector -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'ProjectCollectedState.ps1 must remain local-only.' }
}

$historyPath=Join-Path $ProjectRoot '@Resources\Scripts\MaintainObservationHistory.ps1'
if (Test-Path -LiteralPath $historyPath) {
    $history=Get-Content -LiteralPath $historyPath -Raw
    foreach($token in @(
        'Write-BaselineAwareObservationPrune','latestBefore','retention_baseline','Test-IsSyntheticHistorySource',
        'Remove-SyntheticObservationArtifacts',"@('history_bootstrap','history_repair_baseline')",'[void](Remove-SyntheticObservationArtifacts)',
        "if (`$Phase -eq 'PostUpdate') { return }"
    )) {
        if (-not $history.Contains($token)) { Fail "History maintenance missing '$token'." }
    }
    if ($history.Contains('Add-MissingMarketBaselines')) { Fail 'History maintenance must not recreate migration-era synthetic baselines.' }
}

$opportunityPath=Join-Path $ProjectRoot '@Resources\Scripts\OpportunityState.ps1'
if (Test-Path -LiteralPath $opportunityPath) {
    $opportunity=Get-Content -LiteralPath $opportunityPath -Raw
    foreach($token in @('grossProfit','make','profitPerHour','Get-OpportunityRoundTripProfitPerHour','Get-OpportunityNextWindow','hasKnownSortData','effectiveSortMode','$effectiveSortMode -eq ''gross''','$effectiveSortMode -eq ''profit_per_hour''','probabilityKnown',"'LEARNING'",'$availableQuantity = $stock',"PSObject.Properties['make']",'Descending=$true')) {
        if (-not $opportunity.Contains($token)) { Fail "Opportunity model missing '$token'." }
    }
    if ($opportunity -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'Opportunity projection must remain local-only.' }
}

$readerPath=Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
if (Test-Path -LiteralPath $readerPath) {
    $reader=Get-Content -LiteralPath $readerPath -Raw
    foreach($token in @('flagCodes','@3x.png','flagMaskImagePath','flag-mask-both.png','flag-mask-top.png','flag-mask-bottom.png','applyItemImageForRow','requestItemImages','MeasureItemImages','VisibleItemImageIds','collapseInlineGraph','MeasureInlineGraph','effectiveSortMode','OpportunitySortEffectiveMode','displayProfit = number(data[prefix .. ''MakeValue''])','if a.displayProfit ~= b.displayProfit then return a.displayProfit > b.displayProfit end','safeLeaveText',"return 'WAIT DATA'","return 'NO HIT'")) {
        if (-not $reader.Contains($token)) { Fail "StateReader missing '$token'." }
    }
    foreach($retired in @('OpenViewer','ViewerMarketKey','MeasureItemViewer')) { if($reader.Contains($retired)){ Fail "StateReader retains retired Viewer token '$retired'." } }
}

$itemImagePath=Join-Path $ProjectRoot '@Resources\Scripts\EnsureItemImages.ps1'
if (Test-Path -LiteralPath $itemImagePath) {
    $itemImages=Get-Content -LiteralPath $itemImagePath -Raw
    foreach($token in @('https://www.torn.com/images/items/{0}/large.png','System.Net.Http.HttpClient','@Resources\Generated','Items')){
        if(-not$itemImages.Contains($token)){Fail "Item-image cache helper missing '$token'."}
    }
}

$rendererPath=Join-Path $ProjectRoot '@Resources\Scripts\RenderInlineGraph.ps1'
if (Test-Path -LiteralPath $rendererPath) {
    $renderer=Get-Content -LiteralPath $rendererPath -Raw
    foreach($token in @('RuntimeObservationFile','$historySource = ''runtime_observations''','Compress-StockHistory','history_bootstrap','history_repair_baseline','current_snapshot','UnknownBeforeTimestamp','Add-Type -AssemblyName System.Drawing','stableImagePath','$graphics.Clear([System.Drawing.Color]::FromArgb(0,0,0))','FromArgb(126,190,73),2','FromArgb(0,71,171),1','FromArgb(255,117,24),1')) {
        if (-not $renderer.Contains($token)) { Fail "Inline renderer missing '$token'." }
    }
    if ($renderer.Contains('display_carry')) { Fail 'Inline renderer must not paint current state backward through unknown history.' }
    if ($renderer -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'Inline renderer must remain local-only.' }
}

$git=Get-Command git -ErrorAction SilentlyContinue
if ($null -ne $git) {
    Push-Location $ProjectRoot
    try {
        foreach($relative in @('data/runtime/probe.tmp','@Resources/Generated/probe.tmp','config/settings.local.json')) {
            $ignored=& git check-ignore $relative 2>$null
            if ([string]::IsNullOrWhiteSpace(($ignored | Out-String))) { Fail "$relative is not ignored by Git." }
        }
    } finally { Pop-Location }
}

if ($errors.Count -gt 0) {
    foreach($err in $errors){Write-Host "FAIL: $err" -ForegroundColor Red}
    Write-Host "Validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Travel Assistant 0.6 static architecture validation passed.' -ForegroundColor Green
Write-Host 'Single-owner foreign-stock collection, transition-only history, synthetic-artifact cleanup, correct card layering, and observed-only graph contracts are present.'
exit 0
