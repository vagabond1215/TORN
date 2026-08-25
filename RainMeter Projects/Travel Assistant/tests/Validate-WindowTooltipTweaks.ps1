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
        "fallback..' chance to hit'",
        "chance..' chance to hit'",
        "tooltipLine(existingTooltip,'Guaranteed Window')",
        "Best Hit Window:%s*.-%[(%d+%%)%]",
        "setOption(chance,'Text','')",
        "setOption(leave,'ToolTipText',tooltip)",
        "setOption(info,'ToolTipText',tooltip)"
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
    $tooltipAt = $include.IndexOf('[MeasureWindowTooltipTweaks]',[System.StringComparison]::Ordinal)
    if ($freshAt -lt 0 -or $tooltipAt -le $freshAt) {
        Fail 'Window tooltip refinement must run after the final freshness guard/presentation stack.'
    }
}

if ($errors.Count -gt 0) {
    foreach ($error in $errors) { Write-Host "FAIL: $error" -ForegroundColor Red }
    Write-Host "Window tooltip validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Relative guaranteed-window and tooltip-only Best Hit confidence validation passed.' -ForegroundColor Green
Write-Host 'Safe tooltips switch from starts-in to closes-in timing; non-overlap rows show chance-to-hit in the tooltip and no confidence percentage on the card.'
exit 0