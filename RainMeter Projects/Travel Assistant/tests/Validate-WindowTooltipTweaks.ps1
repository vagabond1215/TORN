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
        'medianAvailableSeconds',
        'parseSafeWindows',
        'findMatchingSafeWindow',
        "tooltipLine(rawPlan,'Early Restock')",
        "tooltipLine(rawPlan,'Late Restock')",
        "tooltipLine(rawPlan,'Safe Window')",
        "tooltipLine(rawPlan,'Best Hit Window')",
        "'Home in: '..formatDuration(remaining)",
        "'Restock: '..early..' - '..late",
        "'Typical stock duration: '..formatDuration(stocked)",
        "'Guaranteed: '..startClock..' to '..endClock..suffix",
        "'Best hit: '..clock..' ['..chance..']'",
        "return table.concat(lines,'#CRLF#')",
        "travelState~='home' and travelState~='returning'",
        "setOption(prefix..'Leave','ToolTipText',tooltip)",
        "setOption(prefix..'Info','ToolTipText',tooltip)",
        "setOption(prefix..'Chance','Text','')"
    )) {
        if (-not $script.Contains($token)) { Fail "WindowTooltipTweaks.lua missing '$token'." }
    }

    foreach ($forbidden in @(
        "meterOption(prefix..'Leave','ToolTipText')",
        "meterOption(prefix..'Info','ToolTipText')",
        'existingTooltip',
        'Estimated Arrival in',
        'Estimated In Stock Duration'
    )) {
        if ($script.Contains($forbidden)) { Fail "WindowTooltipTweaks.lua must not recursively rebuild from prior tooltip text; found '$forbidden'." }
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
        Fail 'Window tooltip refinement must run after freshness and travel-state presentation passes.'
    }
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host "FAIL: $validationError" -ForegroundColor Red }
    Write-Host "Window tooltip validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Concise idempotent window tooltip validation passed.' -ForegroundColor Green
Write-Host 'Home/return tooltips are rebuilt from raw window-plan state and contain only home timing when relevant, restock range, typical stock duration, and one Guaranteed-or-Best line.'
exit 0
