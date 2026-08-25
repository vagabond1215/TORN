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
        'groupMode',
        'groupDepartureTimes',
        'findPreferredGroup',
        "if mode=='safe' and closeAt>now then return group,mode end",
        "relative='starts in '..formatDuration(group.safeStart-now)",
        "relative='closes in '..formatDuration(group.safeEnd-now)",
        "'Estimated Arrival in '..arrival",
        "'Estimated In Stock Duration '..stockedText",
        "'Early Restock: '..formatMoment(group.earlyRestock,now)",
        "'Late Restock: '..formatMoment(group.lateRestock,now)",
        "'Guaranteed Window: '..startClock..' to '..endClock",
        "'Best Hit Window: '..formatMoment(target,now)..' ['..chance..']'",
        "if travelState=='traveling' or travelState=='returning' or travelState=='abroad' or travelState=='foreign' then",
        "setOption(prefix..'Chance','Text','')",
        "setOption(prefix..'Leave','ToolTipText',tooltip)",
        "setOption(prefix..'Info','ToolTipText',tooltip)"
    )) {
        if (-not $script.Contains($token)) { Fail "WindowTooltipTweaks.lua missing '$token'." }
    }

    foreach ($forbidden in @(
        "meterOption(prefix..'Leave','ToolTipText')",
        "meterOption(prefix..'Info','ToolTipText')",
        'existingTooltip',
        'tooltipLine(existingTooltip'
    )) {
        if ($script.Contains($forbidden)) { Fail "Home tooltip must be rebuilt from raw state, not prior rendered tooltip text; found '$forbidden'." }
    }

    if ($script -match '(?i)https?://|Invoke-RestMethod|curl|RunCommand') {
        Fail 'WindowTooltipTweaks.lua must remain local presentation only.'
    }

    foreach ($token in @(
        '[MeasureWindowTooltipTweaks]',
        'ScriptFile=#@#Scripts\WindowTooltipTweaks.lua',
        'StateFile=#@#Generated\state.kv',
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

Write-Host 'Raw five-line home window tooltip validation passed.' -ForegroundColor Green
Write-Host 'Home shows arrival, stock duration, early/late restock, and one Guaranteed-or-Best line; Safe timing advances from starts-in to closes-in and then to the next actionable group.'
exit 0
