$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $ProjectRoot '@Resources\Scripts\WindowTooltipTweaks.lua'
$includePath = Join-Path $ProjectRoot '@Resources\Includes\OpportunityInfo.inc'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($scriptPath,$includePath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing window-tooltip asset: $path" }
}

if ($errors.Count -eq 0) {
    $script = Get-Content -LiteralPath $scriptPath -Raw
    $include = Get-Content -LiteralPath $includePath -Raw

    foreach ($token in @(
        'parseWindowPlan',
        'medianAvailableSeconds',
        'nextCycleGroup(row)',
        'number(group.ordinal)==ordinal',
        "'Next Restock Only'",
        "'No farther cycle is selected while in Torn'",
        "'Estimated Arrival in '..arrival",
        "'Early Restock: '..formatMoment(group.earlyRestock,now)",
        "'Late Restock: '..formatMoment(group.lateRestock,now)",
        "'Safe Window: '..safe",
        'currentCycleReachable=number(state[prefix..''CurrentCycleReachable''])>0',
        'activeSelloutEstimateAt=number(state[prefix..''ActiveSelloutEstimateAt''])',
        'currentCycleLeaveDeadlineAt=number(state[prefix..''CurrentCycleLeaveDeadlineAt''])',
        'currentCycleSafetyMarginSeconds=number(state[prefix..''CurrentCycleSafetyMarginSeconds''])',
        'nextCycleOrdinal=math.floor(number(state[prefix..''NextCycleOrdinal'']))',
        'windowDataQuality=trim(state[prefix..''WindowDataQuality'']):lower()',
        'windowDataQualityReason=trim(state[prefix..''WindowDataQualityReason''])',
        "'Collecting Data'",
        "'Stale/frozen intervals are excluded from forecast timing.'",
        "'See Weav3r for the current travel-stock snapshot.'",
        "'Current Cycle Sellout: '..formatMoment(row.activeSelloutEstimateAt,now)",
        "'Leave Before: '..formatMoment(row.currentCycleLeaveDeadlineAt,now)",
        "'5% Sellout Safety: '..formatDuration(row.currentCycleSafetyMarginSeconds)",
        'liveCycleProjectionMode=trim(state[prefix..''LiveCycleProjectionMode''])',
        "'active restock + median completed-cycle stock duration'",
        "'live depletion of current observed stock'",
        "'Basis: '..basis",
        "if travelState=='traveling' or travelState=='returning' or travelState=='abroad' or travelState=='foreign' then",
        "setOption(prefix..'Chance','Text','')",
        "setOption(prefix..'Leave','ToolTipText',tooltip)",
        "setOption(prefix..'Info','ToolTipText',tooltip)",
        "CardPresenter owns the home-state probability text"
    )) {
        if (-not $script.Contains($token)) { Fail "WindowTooltipTweaks.lua missing '$token'." }
    }

    foreach ($forbidden in @(
        "meterOption(prefix..'Leave','ToolTipText')",
        "meterOption(prefix..'Info','ToolTipText')",
        'existingTooltip',
        'tooltipLine(existingTooltip',
        'groupDepartureTimes'
    )) {
        if ($script.Contains($forbidden)) { Fail "Home tooltip must track raw market windows without prior tooltip/departure-cutoff coupling; found '$forbidden'." }
    }

    if ($script -match "(?ms)applyTooltip\(prefix,buildHomeTooltip\(row,travelText,now\)\).*?setOption\(prefix\.\.'Chance','Text',''\)") {
        Fail 'Home tooltip refinement must preserve CardPresenter probability text.'
    }

    if ($script -match '(?i)https?://|Invoke-RestMethod|curl|RunCommand') {
        Fail 'WindowTooltipTweaks.lua must remain local presentation only.'
    }

    foreach ($token in @(
        '[MeasureWindowTooltipTweaks]',
        'ScriptFile=#@#Scripts\WindowTooltipTweaks.lua',
        'StateFile=#@#Generated\ui-state.kv',
        'UpdateDivider=1'
    )) {
        if (-not $include.Contains($token)) { Fail "OpportunityInfo.inc missing '$token'." }
    }

    $freshAt = $include.IndexOf('[MeasureFreshnessGuard]',[System.StringComparison]::Ordinal)
    $travelAt = $include.IndexOf('[MeasureTravelStateWindowTweaks]',[System.StringComparison]::Ordinal)
    $tooltipAt = $include.IndexOf('[MeasureWindowTooltipTweaks]',[System.StringComparison]::Ordinal)
    if ($freshAt -lt 0 -or $travelAt -lt 0 -or $tooltipAt -le $travelAt -or $tooltipAt -le $freshAt) {
        Fail 'Home window tooltip refinement must run after freshness and travel-state presentation passes.'
    }
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host "FAIL: $validationError" -ForegroundColor Red }
    Write-Host "Window tooltip validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Current/next-cycle and collecting-data home tooltip validation passed.' -ForegroundColor Green
Write-Host 'Reachable current stock shows sellout plus 5% safety deadline; otherwise the tooltip is pinned to the immediate next restock and never a farther cycle.'
exit 0