$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runUpdatePath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$capacityPath = Join-Path $ProjectRoot '@Resources\Scripts\CurrentCapacityRefresh.ps1'
$anchorPath = Join-Path $ProjectRoot '@Resources\Scripts\CycleAnchorReconciler.ps1'
$graphPath = Join-Path $ProjectRoot '@Resources\Scripts\RenderInlineGraph.ps1'
$tweaksPath = Join-Path $ProjectRoot '@Resources\Scripts\CardTweaks.lua'
$infoPath = Join-Path $ProjectRoot '@Resources\Includes\OpportunityInfo.inc'
$refinerPath = Join-Path $ProjectRoot '@Resources\Scripts\WindowPlanRefiner.ps1'
$cycleFilterPath = Join-Path $ProjectRoot '@Resources\Scripts\CycleForecastFilter.ps1'
$filterStatePath = Join-Path $ProjectRoot '@Resources\Scripts\FilterState.ps1'
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($runUpdatePath,$capacityPath,$anchorPath,$graphPath,$tweaksPath,$infoPath,$refinerPath,$cycleFilterPath,$filterStatePath,$iniPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing current-tweak asset: $path" }
}

if ($errors.Count -eq 0) {
    foreach ($path in @($runUpdatePath,$capacityPath,$anchorPath,$graphPath,$refinerPath,$cycleFilterPath,$filterStatePath)) {
        $tokens=$null; $parseErrors=$null
        [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
        foreach ($parseError in @($parseErrors)) { Fail "$([System.IO.Path]::GetFileName($path)) parse error: $($parseError.Message)" }
    }

    $runUpdate = Get-Content -LiteralPath $runUpdatePath -Raw
    $capacity = Get-Content -LiteralPath $capacityPath -Raw
    $anchor = Get-Content -LiteralPath $anchorPath -Raw
    $graph = Get-Content -LiteralPath $graphPath -Raw
    $tweaks = Get-Content -LiteralPath $tweaksPath -Raw
    $info = Get-Content -LiteralPath $infoPath -Raw
    $refiner = Get-Content -LiteralPath $refinerPath -Raw
    $cycleFilter = Get-Content -LiteralPath $cycleFilterPath -Raw
    $filterState = Get-Content -LiteralPath $filterStatePath -Raw
    $ini = Get-Content -LiteralPath $iniPath -Raw

    foreach ($token in @(
        'https://api.torn.com/v2/user/perks?comment=TravelAssistantHeartbeat',
        'Get-TornEffectiveXanaxCapacity',
        "'currentCapacityKnown'",
        "'currentCapacityMode'",
        "'currentCapacity'",
        "'currentCapacityBonus'",
        "'currentCapacitySyncedAt'",
        '[int]$result.SuitcaseBonus + [int]$result.ActivePerkBonus'
    )) {
        if (-not $capacity.Contains($token)) { Fail "CurrentCapacityRefresh.ps1 missing '$token'." }
    }
    if ($capacity -match '(?i)[?&](key|api_key|apikey)=') { Fail 'Current capacity refresh must not place the Torn API key in the URL.' }

    foreach ($token in @(
        'observations.jsonl','history_bootstrap','history_repair_baseline',
        'Runtime observations are authoritative','lastRestockAt','lastSellOutAt',
        "'anchorSource' -Value 'observations'",'continuityInvalidatedAt',
        'transitionGapSeconds','transitionBoundaryQuality','Test-AnchorBoundaryQuality'
    )) {
        if (-not $anchor.Contains($token)) { Fail "CycleAnchorReconciler.ps1 missing '$token'." }
    }
    if ($anchor -match '(?i)https?://|Invoke-RestMethod|Invoke-WebRequest|curl\.exe') { Fail 'Cycle anchor reconciliation must remain local-only.' }

    foreach ($token in @(
        'Get-StableWindowMedian','Get-StableWindowUsableCycles','Get-StableRecurringScenarioModel',
        '$medianPeriod','(($ordinal-1) * $medianPeriod) + $period','($ordinal * $medianPeriod) + $delay',
        'Collector outages can turn one apparent out-of-stock span','Select-StableWindowPlanGroup',
        'Get-CurrentCycleDeparturePlan','SafetyMarginFraction = 0.05','NextCycleOrdinal',
        'Test-WindowBoundaryQuality','WindowDataQuality','Collecting Data: See Weav3r',
        "'sleeping_oos'",'Do not read cycle evidence or build recurring probability geometry',
        'MaximumOrdinal = 1','immediately next cycle',
        "'PriceVaries'","'MinObservedPrice'","'MaxObservedPrice'"
    )) {
        if (-not $refiner.Contains($token)) { Fail "WindowPlanRefiner.ps1 missing '$token'." }
    }
    if ($refiner -match '(?i)https?://|Invoke-RestMethod|Invoke-WebRequest|curl\.exe') { Fail 'WindowPlanRefiner.ps1 must remain local-only.' }
    foreach ($token in @('Select-CadenceAwareForecastCycles','Test-CycleForecastBoundaryEvidence','Get-CycleBoundaryPolicy','Get-CycleBoundaryQuality','forecastEligible','availabilityEligible','restockDelayEligible','trendEligible','schemaVersion','recovered','$medianPeriod -le 10800L','$maximumPeriod = 86400L','$maximumPeriod = 172800L','604800L')) {
        if (-not $cycleFilter.Contains($token)) { Fail "CycleForecastFilter.ps1 missing cadence-aware contract '$token'." }
    }
    if ($cycleFilter -match '(?i)https?://|Invoke-RestMethod|Invoke-WebRequest|curl\.exe') { Fail 'Cadence-aware cycle filtering must remain local-only.' }
    foreach ($token in @('WindowPlanRefiner.ps1','& $WindowPlanRefiner')) {
        if (-not $filterState.Contains($token)) { Fail "FilterState.ps1 missing post-window refinement token '$token'." }
    }

    $travelAt = $runUpdate.IndexOf('Invoke-FailSoftScript -Path $TravelContext',[System.StringComparison]::Ordinal)
    $capacityAt = $runUpdate.IndexOf('Invoke-FailSoftScript -Path $CurrentCapacityRefresh',[System.StringComparison]::Ordinal)
    $anchorAt = $runUpdate.IndexOf('Invoke-FailSoftScript -Path $CycleAnchorReconciler',[System.StringComparison]::Ordinal)
    $opportunityAt = $runUpdate.IndexOf('Invoke-FailSoftScript -Path $OpportunityState',[System.StringComparison]::Ordinal)
    $windowAt = $runUpdate.IndexOf('Invoke-FailSoftScript -Path $WindowPlan',[System.StringComparison]::Ordinal)
    if (@($travelAt,$capacityAt,$anchorAt,$opportunityAt,$windowAt) -contains -1 -or -not ($travelAt -lt $capacityAt -and $capacityAt -lt $anchorAt -and $anchorAt -lt $opportunityAt -and $opportunityAt -lt $windowAt)) {
        Fail 'Runtime order must be TravelContext -> current capacity -> observation anchor -> opportunity -> window plan.'
    }
    if ($runUpdate.Contains('Invoke-FailSoftScript -Path $OptimalRoute')) {
        Fail 'Retired standalone optimizer must not return to the one-minute updater path.'
    }

    foreach ($token in @('$width = 528','$height = 125','$plotRight = 522.0','$plotBottom = 98.0','focus-market.kv','Write-TravelAssistantAtomicText -Path $FocusMarketFile')) {
        if (-not $graph.Contains($token)) { Fail "RenderInlineGraph.ps1 missing expanded graph token '$token'." }
    }

    # CardTweaks is now a defensive compatibility pass only. It must never
    # compete with StateReader geometry or CardPresenter text ownership.
    foreach ($token in @(
        'local function hideRetiredCardMeters()',
        'StateReader owns geometry; CardPresenter owns visible text/tooltips.',
        "SKIN:Bang('!HideMeter','MeterOpportunity'..i..'Window')",
        "SKIN:Bang('!HideMeter','MeterOpportunity'..i..'Chance')",
        'function Initialize()',
        'function Update()'
    )) {
        if (-not $tweaks.Contains($token)) { Fail "CardTweaks.lua missing compact-card compatibility token '$token'." }
    }
    foreach ($retired in @(
        'applyHeader','applySecondLine','applyExpandedGraphGeometry','applyGraphSize',
        'configureInfo','costColor','shiftMeterY','panel+25',"setOption(card,'H',183)"
    )) {
        if ($tweaks.Contains($retired)) { Fail "CardTweaks.lua retains retired layout/header owner '$retired'." }
    }
    if ($tweaks -match '(?i)https?://|Invoke-RestMethod|curl|RunCommand') { Fail 'CardTweaks.lua must remain local presentation only.' }

    if($info -match '(?m)^\[MeterOpportunity\d+Info\]\s*    foreach ($token in @('[MeasureCardTweaks]','CardTweaks.lua','@IncludeInfo=#@#Includes\OpportunityInfo.inc')) {
        if (-not $ini.Contains($token)) { Fail "TravelAssistant.ini missing '$token'." }
    }
    $presenterAt = $ini.IndexOf('[MeasureCardPresenter]',[System.StringComparison]::Ordinal)
    $tweaksAt = $ini.IndexOf('[MeasureCardTweaks]',[System.StringComparison]::Ordinal)
    if ($presenterAt -lt 0 -or $tweaksAt -le $presenterAt) { Fail 'MeasureCardTweaks must update after MeasureCardPresenter.' }
}

if ($errors.Count -gt 0) {
    foreach ($error in $errors) { Write-Host "FAIL: $error" -ForegroundColor Red }
    Write-Host "Current tweak validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Stable-window refiner, single-owner card geometry, defensive legacy visibility, and expanded graph validation passed.' -ForegroundColor Green
Write-Host 'Expected live result: no flight duration on the card; only flag/window text expose tooltips; economics colors and stable window timing remain intact.'
exit 0
){
        Fail 'Retired invisible Info tooltip meters must remain removed.'
    }
    if($filterState.Contains('EnsureUiAssets.ps1') -or $filterState.Contains('$EnsureUiAssets')){
        Fail 'FilterState.ps1 must not invoke the retired info-icon generator.'
    }

    foreach ($token in @('[MeasureCardTweaks]','CardTweaks.lua','@IncludeInfo=#@#Includes\OpportunityInfo.inc')) {
        if (-not $ini.Contains($token)) { Fail "TravelAssistant.ini missing '$token'." }
    }
    $presenterAt = $ini.IndexOf('[MeasureCardPresenter]',[System.StringComparison]::Ordinal)
    $tweaksAt = $ini.IndexOf('[MeasureCardTweaks]',[System.StringComparison]::Ordinal)
    if ($presenterAt -lt 0 -or $tweaksAt -le $presenterAt) { Fail 'MeasureCardTweaks must update after MeasureCardPresenter.' }
}

if ($errors.Count -gt 0) {
    foreach ($error in $errors) { Write-Host "FAIL: $error" -ForegroundColor Red }
    Write-Host "Current tweak validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Stable-window refiner, single-owner card geometry, defensive legacy visibility, and expanded graph validation passed.' -ForegroundColor Green
Write-Host 'Expected live result: no flight duration on the card; hover shows pertinent arrival time, median in-stock duration, early/late restock, and guaranteed overlap; economics colors and stable window timing remain intact.'
exit 0
