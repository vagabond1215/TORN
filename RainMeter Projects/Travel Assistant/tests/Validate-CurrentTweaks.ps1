$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runUpdatePath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$capacityPath = Join-Path $ProjectRoot '@Resources\Scripts\CurrentCapacityRefresh.ps1'
$anchorPath = Join-Path $ProjectRoot '@Resources\Scripts\CycleAnchorReconciler.ps1'
$graphPath = Join-Path $ProjectRoot '@Resources\Scripts\RenderInlineGraph.ps1'
$tweaksPath = Join-Path $ProjectRoot '@Resources\Scripts\CardTweaks.lua'
$infoPath = Join-Path $ProjectRoot '@Resources\Includes\OpportunityInfo.inc'
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($runUpdatePath,$capacityPath,$anchorPath,$graphPath,$tweaksPath,$infoPath,$iniPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing current-tweak asset: $path" }
}

if ($errors.Count -eq 0) {
    foreach ($path in @($runUpdatePath,$capacityPath,$anchorPath,$graphPath)) {
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
        "title=title..'  '..tostring(quantity)..' qty'",
        "local header='Cost '..cost..'   MV:'..mv..' | '..formatMoney(unitProfit)",
        "setOption(prefix..'Info','X',301)",
        "setOption(info,'Text',show and 'ⓘ' or '')",
        "setOption(leave,'ToolTipText',text)",
        "setOption(graph,'W',528)",
        "setOption(graph,'H',125)",
        "setOption(card,'H',183)",
        "panel+25"
    )) {
        if (-not $tweaks.Contains($token)) { Fail "CardTweaks.lua missing '$token'." }
    }
    if ($tweaks.Contains('/ea x')) { Fail 'CardTweaks.lua must not restore the retired /ea x qty = header.' }
    if ($tweaks -match '(?i)https?://|Invoke-RestMethod|curl|RunCommand') { Fail 'CardTweaks.lua must remain local presentation only.' }

    foreach ($index in 1..8) {
        foreach ($token in @("[MeterOpportunity${index}Info]","Group=OpportunityRow${index}",'ToolTipTitle=Window calculation','ToolTipWidth=420')) {
            if (-not $info.Contains($token)) { Fail "OpportunityInfo.inc missing row $index token '$token'." }
        }
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

Write-Host 'Current capacity, observation-anchor, card-header, info-anchor, and expanded-graph validation passed.' -ForegroundColor Green
Write-Host 'Expected live result: active perks refresh inventory capacity; Safe/Best phase follows retained real stock transitions; header shows qty + Cost + MV + profit/item; graph is 528x125; departure text and dedicated info glyph expose the calculation.'
exit 0
