$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runUpdatePath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$capacityPath = Join-Path $ProjectRoot '@Resources\Scripts\CurrentCapacityRefresh.ps1'
$anchorPath = Join-Path $ProjectRoot '@Resources\Scripts\CycleAnchorReconciler.ps1'
$graphPath = Join-Path $ProjectRoot '@Resources\Scripts\RenderInlineGraph.ps1'
$tweaksPath = Join-Path $ProjectRoot '@Resources\Scripts\CardTweaks.lua'
$infoPath = Join-Path $ProjectRoot '@Resources\Includes\OpportunityInfo.inc'
$assetPath = Join-Path $ProjectRoot '@Resources\Scripts\EnsureUiAssets.ps1'
$refinerPath = Join-Path $ProjectRoot '@Resources\Scripts\WindowPlanRefiner.ps1'
$filterStatePath = Join-Path $ProjectRoot '@Resources\Scripts\FilterState.ps1'
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($runUpdatePath,$capacityPath,$anchorPath,$graphPath,$tweaksPath,$infoPath,$assetPath,$refinerPath,$filterStatePath,$iniPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing current-tweak asset: $path" }
}

if ($errors.Count -eq 0) {
    foreach ($path in @($runUpdatePath,$capacityPath,$anchorPath,$graphPath,$assetPath,$refinerPath,$filterStatePath)) {
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
    $asset = Get-Content -LiteralPath $assetPath -Raw
    $refiner = Get-Content -LiteralPath $refinerPath -Raw
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
        "'anchorSource' -Value 'observations'"
    )) {
        if (-not $anchor.Contains($token)) { Fail "CycleAnchorReconciler.ps1 missing '$token'." }
    }
    if ($anchor -match '(?i)https?://|Invoke-RestMethod|Invoke-WebRequest|curl\.exe') { Fail 'Cycle anchor reconciliation must remain local-only.' }

    foreach ($token in @(
        'Get-StableWindowMedian','Get-StableWindowUsableCycles','Get-StableRecurringScenarioModel',
        '$medianPeriod','(($ordinal-1) * $medianPeriod) + $period','($ordinal * $medianPeriod) + $delay',
        'Collector outages can turn one apparent out-of-stock span','Select-StableWindowPlanGroup',
        "'PriceVaries'","'MinObservedPrice'","'MaxObservedPrice'"
    )) {
        if (-not $refiner.Contains($token)) { Fail "WindowPlanRefiner.ps1 missing '$token'." }
    }
    if ($refiner -match '(?i)https?://|Invoke-RestMethod|Invoke-WebRequest|curl\.exe') { Fail 'WindowPlanRefiner.ps1 must remain local-only.' }
    foreach ($token in @('WindowPlanRefiner.ps1','EnsureUiAssets.ps1','& $WindowPlanRefiner','& $EnsureUiAssets')) {
        if (-not $filterState.Contains($token)) { Fail "FilterState.ps1 missing post-window refinement token '$token'." }
    }

    $travelAt = $runUpdate.IndexOf('Invoke-FailSoftScript -Path $TravelContext',[System.StringComparison]::Ordinal)
    $capacityAt = $runUpdate.IndexOf('Invoke-FailSoftScript -Path $CurrentCapacityRefresh',[System.StringComparison]::Ordinal)
    $anchorAt = $runUpdate.IndexOf('Invoke-FailSoftScript -Path $CycleAnchorReconciler',[System.StringComparison]::Ordinal)
    $optimalAt = $runUpdate.IndexOf('Invoke-FailSoftScript -Path $OptimalRoute',[System.StringComparison]::Ordinal)
    $opportunityAt = $runUpdate.IndexOf('Invoke-FailSoftScript -Path $OpportunityState',[System.StringComparison]::Ordinal)
    $windowAt = $runUpdate.IndexOf('Invoke-FailSoftScript -Path $WindowPlan',[System.StringComparison]::Ordinal)
    if (@($travelAt,$capacityAt,$anchorAt,$optimalAt,$opportunityAt,$windowAt) -contains -1 -or -not ($travelAt -lt $capacityAt -and $capacityAt -lt $anchorAt -and $anchorAt -lt $optimalAt -and $optimalAt -lt $opportunityAt -and $opportunityAt -lt $windowAt)) {
        Fail 'Runtime order must be TravelContext -> current capacity -> observation anchor -> optimizer -> opportunity -> window plan.'
    }

    foreach ($token in @('$width = 528','$height = 125','$plotRight = 522.0','$plotBottom = 98.0')) {
        if (-not $graph.Contains($token)) { Fail "RenderInlineGraph.ps1 missing expanded graph token '$token'." }
    }

    foreach ($token in @(
        'info-icon.png','[System.Drawing.Bitmap]::new(64,64','FillEllipse','FillRectangle','ImageFormat]::Png'
    )) {
        if (-not $asset.Contains($token)) { Fail "EnsureUiAssets.ps1 missing '$token'." }
    }

    # Keep this validator source ASCII-only for Windows PowerShell 5.1.
    foreach ($token in @(
        'stripDebugQuantity',
        "local header=cost..'   MV:'..mv..' | '..formatMoney(unitProfit)",
        "setOption(prefix..'Gross','X',235)",
        "setOption(prefix..'Gross','StringAlign','Left')",
        'local function costColor(row)',
        'redThreshold=mv/1.05',
        'minObservedPrice',
        "return '255,255,255,255'",
        "setOption(prefix..'Gross','InlineSetting2','Color | 86,190,116,255')",
        'local function relevantArrivalText',
        'TravelArrivalAt','TravelTimeLeft','TravelContextLastSuccessAt',
        'local function medianAvailableSeconds',
        "'Estimated Arrival in '",
        "'Estimated In Stock Duration '",
        "'Early Restock: '",
        "'Late Restock: '",
        "'Guaranteed Window: '",
        "setOption(prefix..'Window','Text','')",
        "setOption(prefix..'Window','W',1)",
        "setOption(prefix..'Leave','X',78)",
        "if show then SKIN:Bang('!ShowMeter',info) else SKIN:Bang('!HideMeter',info) end",
        "setOption(info,'ToolTipTitle','Window estimate')",
        "setOption(info,'ToolTipText',text)",
        "setOption(leave,'ToolTipText',text)",
        "meterOption(leave,'Text'):match('^SAFE')",
        "setOption(graph,'W',528)",
        "setOption(graph,'H',125)",
        "setOption(card,'H',183)",
        "panel+25"
    )) {
        if (-not $tweaks.Contains($token)) { Fail "CardTweaks.lua missing '$token'." }
    }
    foreach ($forbidden in @(
        "setOption(info,'ToolTipHidden'",
        "setOption(leave,'ToolTipHidden'",
        "setOption(info,'ImageAlpha',show and 255 or 0)",
        "setOption(prefix..'Window','W',0)"
    )) {
        if ($tweaks.Contains($forbidden)) { Fail "CardTweaks.lua restores target-host unsafe visibility bang '$forbidden'." }
    }
    if ($tweaks.Contains("title=title..'  '..tostring(quantity)..' qty'")) { Fail 'CardTweaks.lua must not print quantity in the title.' }
    if ($tweaks.Contains("local header='Cost '")) { Fail 'CardTweaks.lua must not print the Cost label.' }
    if ($tweaks.Contains('/ea x')) { Fail 'CardTweaks.lua must not restore the retired /ea x qty = header.' }
    if ($tweaks.Contains('Safe formula:') -or $tweaks.Contains('Best formula:')) { Fail 'Final card tooltip layer must not expose implementation formulas.' }
    if ($tweaks -match '(?i)https?://|Invoke-RestMethod|curl|RunCommand') { Fail 'CardTweaks.lua must remain local presentation only.' }

    foreach ($index in 1..8) {
        $section = [regex]::Match($info,'(?ms)^\[MeterOpportunity'+$index+'Info\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if ([string]::IsNullOrWhiteSpace($section)) { Fail "OpportunityInfo.inc missing row $index info meter."; continue }
        foreach ($token in @('Meter=Image','W=12','H=12','PreserveAspectRatio=1','ImageName=#@#Generated\info-icon.png','ToolTipWidth=420')) {
            if (-not $section.Contains($token)) { Fail "OpportunityInfo row $index missing image-anchor token '$token'." }
        }
        if ($section.Contains('Meter=String')) { Fail "OpportunityInfo row $index must not use a Unicode String meter." }
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

Write-Host 'Stable-window refiner, tooltip-only travel timing, card economics colors, bang-safe image info anchor, and expanded graph validation passed.' -ForegroundColor Green
Write-Host 'Expected live result: no flight duration on the card; hover shows pertinent arrival time, median in-stock duration, early/late restock, and guaranteed overlap; economics colors and stable window timing remain intact.'
exit 0
