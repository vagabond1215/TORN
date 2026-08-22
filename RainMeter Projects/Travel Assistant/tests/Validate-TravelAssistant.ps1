$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$errors = New-Object System.Collections.Generic.List[string]
$notes = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }
function Note([string]$Message) { $script:notes.Add($Message) }

$required = @(
    'TravelAssistant.ini','AGENTS.md','Readme.md','Install.ps1',
    'config\items.json','config\countries.json','config\travel-modes.json','config\travel-perks.json',
    'config\settings.example.json','config\settings.local.example.json','config\providers.json',
    'config\foreign-item-categories.json','config\foreign-market-overrides.json',
    'data\seed\metadata.json','data\seed\observations.jsonl','data\seed\cycles.jsonl',
    '@Resources\Scripts\RunUpdate.ps1','@Resources\Scripts\UpdateTracker.ps1','@Resources\Scripts\FinalizeState.ps1',
    '@Resources\Scripts\ShadowCollector.ps1','@Resources\Scripts\LocalCatalog.ps1','@Resources\Scripts\TravelContext.ps1',
    '@Resources\Scripts\OptimalRoute.ps1','@Resources\Scripts\OpportunityState.ps1','@Resources\Scripts\FilterPreferences.ps1','@Resources\Scripts\FilterState.ps1',
    '@Resources\Scripts\ResalePriority.ps1','@Resources\Scripts\ResaleQueue.ps1',
    '@Resources\Scripts\LaunchOptimizerSettings.ps1','@Resources\Scripts\OpenOptimizerSettings.ps1',
    '@Resources\Scripts\LaunchSettings.ps1','@Resources\Scripts\OpenSettings.ps1','@Resources\Scripts\StateReader.lua',
    '@Resources\Scripts\LaunchItemViewer.ps1','@Resources\Scripts\OpenItemViewer.ps1','@Resources\Scripts\RenderInlineGraph.ps1',
    'tests\Validate-OptimalRoute.ps1','tests\Run-OptimalRouteTests.ps1','tests\Validate-RainmeterSkin.ps1','tests\Validate-ItemViewer.ps1'
)
foreach ($relative in $required) {
    if (-not (Test-Path -LiteralPath (Join-Path $ProjectRoot $relative))) { Fail "Missing required file: $relative" }
}

$configFiles = @(
    'config\items.json','config\countries.json','config\travel-modes.json','config\travel-perks.json',
    'config\settings.example.json','config\settings.local.example.json','config\providers.json',
    'config\foreign-item-categories.json','config\foreign-market-overrides.json','data\seed\metadata.json'
)
$config = @{}
foreach ($relative in $configFiles) {
    $path = Join-Path $ProjectRoot $relative
    if (-not (Test-Path -LiteralPath $path)) { continue }
    try {
        $obj = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json
        $config[$relative] = $obj
        if (-not $obj.PSObject.Properties['schemaVersion']) { Fail "$relative does not declare schemaVersion." }
    } catch { Fail "Invalid JSON in ${relative}: $($_.Exception.Message)" }
}

$settings = $config['config\settings.example.json']
if ($null -ne $settings) {
    if (-not $settings.PSObject.Properties['travelProfile']) { Fail 'settings.example.json must contain travelProfile.' }
    if (-not $settings.PSObject.Properties['profitability']) { Fail 'settings.example.json must contain profitability.' }
    if (-not $settings.PSObject.Properties['optimizer']) { Fail 'settings.example.json must contain optimizer.' }
    if ($settings.PSObject.Properties['profitability']) {
        if ([double]$settings.profitability.itemMarketFeePercent -ne 0) { Fail 'Default Item Market fee must be zero under MV valuation.' }
        if ([double]$settings.profitability.minimumProfitPerItem -ne 0 -or [double]$settings.profitability.minimumMarginPercent -ne 0 -or [double]$settings.profitability.minimumTotalTripProfit -ne 0) { Fail 'Legacy minimum-profit gates must default to zero and must not control opportunity timing.' }
        if ([long]$settings.profitability.resaleStaleAfterSeconds -lt 3600) { Fail 'MV cache freshness must be at least one hour.' }
    }
    if ($settings.PSObject.Properties['optimizer']) {
        foreach ($field in @('enabled','marketValueBasisPercent','minimumAvailabilitySamples','purchaseBufferSeconds','maxPlanItems','allowNegativeValueCandidates')) {
            if (-not $settings.optimizer.PSObject.Properties[$field]) { Fail "optimizer is missing '$field'." }
        }
        if ([int]$settings.optimizer.marketValueBasisPercent -ne 100) { Fail 'Default optimizer basis must be 100%.' }
        if ($settings.optimizer.allowNegativeValueCandidates -ne $true) { Fail 'Negative-value candidates must be allowed by default.' }
    }
}

$items = $config['config\items.json']
if ($null -ne $items) {
    if (@($items.items | Where-Object { [int]$_.itemId -eq 206 -and $_.enabled -eq $true }).Count -ne 1) { Fail 'Primary Xanax itemId 206 seed must remain enabled for compatibility collection.' }
}

$modes = $config['config\travel-modes.json']
$countries = $config['config\countries.json']
if ($null -ne $modes -and $null -ne $countries) {
    $modeIds = @($modes.modes | ForEach-Object { [string]$_.id })
    foreach ($requiredMode in @('standard','airstrip','wlt','business')) { if ($modeIds -notcontains $requiredMode) { Fail "Missing travel mode '$requiredMode'." } }
    $collect = @($countries.countries | Where-Object { $_.collect -eq $true })
    if ($collect.Count -ne 11) { Fail "Expected 11 collect=true foreign destinations; found $($collect.Count)." }
    foreach ($country in $collect) {
        if ([string]$country.tripBand -notin @('short','medium','long')) { Fail "Country '$($country.id)' lacks valid tripBand." }
        foreach ($mode in @('standard','airstrip','wlt','business')) {
            $time = $country.travelSeconds.PSObject.Properties[$mode]
            $capacity = $country.baseTravelCapacity.PSObject.Properties[$mode]
            $cost = $country.travelCosts.PSObject.Properties[$mode]
            if ($null -eq $time -or [long]$time.Value -le 0) { Fail "Country '$($country.id)' lacks positive $mode travelSeconds." }
            if ($null -eq $capacity -or [int]$capacity.Value -le 0) { Fail "Country '$($country.id)' lacks positive $mode base capacity." }
            if ($null -eq $cost) { Fail "Country '$($country.id)' lacks explicit $mode travel-cost field." }
        }
        if ([long]$country.travelCosts.airstrip -ne 0 -or [long]$country.travelCosts.wlt -ne 0) { Fail "Country '$($country.id)' must model Airstrip/WLT as zero travel cost." }
    }
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
    foreach ($token in @('ShadowCollector.ps1','LocalCatalog.ps1','FinalizeState.ps1','TravelContext.ps1','OptimalRoute.ps1','OpportunityState.ps1','FilterState.ps1','ResalePriority.ps1','ResaleQueue.ps1','Write-UpdateHeartbeat')) {
        if (-not $wrapper.Contains($token)) { Fail "RunUpdate.ps1 missing '$token'." }
    }
    if ($wrapper.Contains('VisibleItems.ps1')) { Fail 'Normal runtime must not regenerate old embedded card graphs through VisibleItems.ps1.' }
    if ($wrapper.Contains('ItemMetadata.ps1')) { Fail 'Network catalog metadata must remain outside the Rainmeter heartbeat.' }
}

$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
if (Test-Path -LiteralPath $iniPath) {
    $ini = Get-Content -LiteralPath $iniPath -Raw
    if ($ini -notmatch '(?m)^Version=0\.6\.0\s*$') { Fail 'Rainmeter skin must report version 0.6.0.' }
    foreach ($section in @('[Rainmeter]','[MeasureUpdate]','[MeasureState]','[MeasureItemViewer]','[MeterSettings]','[MeterFilterTopLine]','[MeterSortOptimal]','[MeterSortUpcoming]','[MeterSortProfit]','[MeterSortTime]','[MeterViewer]','[MeterOpportunity1Card]','[MeterOpportunity1Name]','[MeterOpportunity1Price]','[MeterOpportunity1Graph]')) {
        if (-not $ini.Contains($section)) { Fail "Rainmeter skin missing opportunity/viewer compatibility section $section" }
    }
    foreach ($retired in @('[MeterRouteCard]','[MeterOptimalItem1Name]','[MeterUKCard]','[MeterJPCard]','[MeterUKGraph]','[MeterJPGraph]','MaxExpandedCards=')) {
        if ($ini.Contains($retired)) { Fail "Opportunity skin still contains retired primary-view contract '$retired'." }
    }
    if (-not $ini.Contains('LaunchOptimizerSettings.ps1')) { Fail 'Main Settings action must open optimizer settings.' }
    if (-not $ini.Contains('LaunchItemViewer.ps1')) { Fail 'Main skin must expose the detached on-demand item viewer and inline history transport.' }
}

$opportunityPath = Join-Path $ProjectRoot '@Resources\Scripts\OpportunityState.ps1'
if (Test-Path -LiteralPath $opportunityPath) {
    $opportunity = Get-Content -LiteralPath $opportunityPath -Raw
    foreach ($token in @('grossProfit','profitPerHour','quantity','elapsedSeconds','Get-OpportunityNextWindow','Write-OpportunityProjection',"sortMode -eq 'name'","sortMode -eq 'gross'","sortMode -eq 'profit_per_hour'",'probabilityKnown',"'LEARNING'",'$availableQuantity = $stock')) {
        if (-not $opportunity.Contains($token)) { Fail "Opportunity model missing '$token'." }
    }
    foreach ($retired in @('expectedGross=','optimalScore=')) { if ($opportunity.Contains($retired)) { Fail "Opportunity model retains hidden weighting token '$retired'." } }
    if ($opportunity -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'Opportunity projection must remain local-only.' }
}

$stateReaderPath = Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
if (Test-Path -LiteralPath $stateReaderPath) {
    $reader = Get-Content -LiteralPath $stateReaderPath -Raw
    foreach ($token in @(
        "'NAME'","'UPCOMING'","'GROSS PROFIT'","'PROFIT/HR'","SetSortMode('profit_per_hour')",
        'configureInteractiveMeters','lastProjectionData = copyProjectionFields(initial)','ToggleInlineGraph','applyFlagForRow','graphExtra',
        "setVariable('ViewerMarketKey', 'inline_' .. key)","SKIN:Bang('!SetOption', 'MeterOpportunity' .. index .. 'Gross', 'Text', grossText)"
    )) {
        if (-not $reader.Contains($token)) { Fail "StateReader compact-card/inline-graph contract missing '$token'." }
    }
}

$inlineRendererPath = Join-Path $ProjectRoot '@Resources\Scripts\RenderInlineGraph.ps1'
if (Test-Path -LiteralPath $inlineRendererPath) {
    $renderer = Get-Content -LiteralPath $inlineRendererPath -Raw
    foreach ($token in @('GraphPath','RuntimeObservationFile','SeedObservationFile','inline-graph-','display_carry')) { if (-not $renderer.Contains($token)) { Fail "Inline renderer missing '$token'." } }
    if ($renderer -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'Inline graph renderer must remain local-only.' }
}

$preferencesPath = Join-Path $ProjectRoot '@Resources\Scripts\FilterPreferences.ps1'
if (Test-Path -LiteralPath $preferencesPath) {
    $prefs = Get-Content -LiteralPath $preferencesPath -Raw
    foreach ($token in @('schemaVersion = 5',"sortMode = 'upcoming'",'profit_per_hour')) { if (-not $prefs.Contains($token)) { Fail "Preference migration contract missing '$token'." } }
}

$optimizerSettingsPath = Join-Path $ProjectRoot '@Resources\Scripts\OpenOptimizerSettings.ps1'
if (Test-Path -LiteralPath $optimizerSettingsPath) {
    $ui = Get-Content -LiteralPath $optimizerSettingsPath -Raw
    foreach ($token in @('Show profitable items only','Use 95% MV profit calculation','Energy Waste','Max Energy Loss','Nerve Waste','Max Nerve Loss','Profile / API...','Ignore List...')) { if (-not $ui.Contains($token)) { Fail "Optimizer Settings missing '$token'." } }
}

$profileSettingsPath = Join-Path $ProjectRoot '@Resources\Scripts\OpenSettings.ps1'
if (Test-Path -LiteralPath $profileSettingsPath) {
    $profileUi = Get-Content -LiteralPath $profileSettingsPath -Raw
    if (-not $profileUi.Contains('Current Xanax capacity')) { Fail 'Profile/API settings must retain current capacity controls.' }
    if (-not $profileUi.Contains('/v2/user/perks')) { Fail 'Capacity sync must continue using /user/perks.' }
    if ($profileUi.Contains('/v2/faction/upgrades')) { Fail 'Profile sync must not require faction-upgrades access.' }
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
} else { Note 'Git executable unavailable; ignore checks skipped.' }

foreach ($note in $notes) { Write-Host "NOTE: $note" -ForegroundColor Yellow }
if ($errors.Count -gt 0) {
    foreach ($err in $errors) { Write-Host "FAIL: $err" -ForegroundColor Red }
    Write-Host "Validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Travel Assistant 0.6 static architecture validation passed.' -ForegroundColor Green
Write-Host 'Compact flag-rail opportunity cards, one-at-a-time inline 8-hour history, separate standalone Viewer, transparent sorting, and visible in-stock learning likelihood contracts are present.'
exit 0
