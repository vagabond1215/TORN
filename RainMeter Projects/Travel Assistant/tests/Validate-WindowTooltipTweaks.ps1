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
        'parseSafeWindows',
        'findMatchingSafeWindow',
        "os.date('%H:%M',window.startAt)",
        "relative='starts in '..formatDuration(window.startAt-now)",
        "relative='closes in '..formatDuration(window.endAt-now)",
        "selected=tostring(existingTooltip or ''):match('Best Hit Window:",
        "fallback..' chance to hit'",
        "chance..' chance to hit'",
        "tooltipLine(existingTooltip,'Guaranteed Window')",
        "'Estimated Arrival in '..arrival",
        "'Estimated In Stock Duration '..stocked",
        "'Early Restock: '..early",
        "'Late Restock: '..late",
        "if travelState=='traveling' or travelState=='abroad' or travelState=='foreign' then",
        "if travelState=='returning' then",
        "local tooltip='Home in: '..formatDuration(remaining)",
        "setOption(prefix..'Chance','Text','')",
        "setOption(prefix..'Leave','ToolTipText',tooltip)",
        "setOption(prefix..'Info','ToolTipText',tooltip)"
    )) {
        if (-not $script.Contains($token)) { Fail "WindowTooltipTweaks.lua missing '$token'." }
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

Write-Host 'Home window tooltip and isolated return-tooltip validation passed.' -ForegroundColor Green
Write-Host 'Home keeps arrival, stock duration, early/late restock and Guaranteed-or-Best confidence; returning shows only the live home delay; outbound/foreign remain travel-state owned.'
exit 0
