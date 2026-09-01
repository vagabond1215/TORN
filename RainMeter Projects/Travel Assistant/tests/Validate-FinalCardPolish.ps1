$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $ProjectRoot '@Resources\Scripts\FinalCardPolish.lua'
$includePath = Join-Path $ProjectRoot '@Resources\Includes\OpportunityInfo.inc'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

if (-not (Test-Path -LiteralPath $scriptPath)) { Fail 'Missing FinalCardPolish.lua.' }
if (-not (Test-Path -LiteralPath $includePath)) { Fail 'Missing OpportunityInfo.inc.' }

if ($errors.Count -eq 0) {
    $scriptText = Get-Content -LiteralPath $scriptPath -Raw
    $includeText = Get-Content -LiteralPath $includePath -Raw

    foreach ($token in @(
        'LEAVE IN = wait before departing; LEAVE BEFORE = latest departure deadline.',
        "header:match('^(.-)%s+MV:(.-)%s+|%s+(.+)$')",
        "name..' - '..cost..' ('..mv..')'",
        "setOption(prefix..'Gross','Text',profit)",
        "setOption(prefix..'Gross','StringAlign','Right')",
        "setOption(prefix..'Gross','FontColor','86,190,116,255')",
        "setOption(prefix..'Name','InlinePattern',moneyPattern(cost))",
        "setOption(prefix..'Name','InlineSetting',costColor)",
        'parenthesizedMoneyPattern',
        "setOption(prefix..'Name','InlinePattern2',parenthesizedMoneyPattern(mv))",
        "setOption(prefix..'Name','InlineSetting2','Color | #Muted#')"
    )) {
        if (-not $scriptText.Contains($token)) { Fail "FinalCardPolish.lua missing '$token'." }
    }

    foreach ($token in @('[MeasureFinalCardPolish]','FinalCardPolish.lua')) {
        if (-not $includeText.Contains($token)) { Fail "OpportunityInfo.inc missing '$token'." }
    }
    $tooltipAt = $includeText.IndexOf('[MeasureWindowTooltipTweaks]',[System.StringComparison]::Ordinal)
    $polishAt = $includeText.IndexOf('[MeasureFinalCardPolish]',[System.StringComparison]::Ordinal)
    if ($tooltipAt -lt 0 -or $polishAt -le $tooltipAt) { Fail 'Final card polish must run after the window tooltip pass.' }

    if ($scriptText.Contains('SAFE FOR ')) { Fail 'FinalCardPolish.lua must not collapse an explicit LEAVE BEFORE deadline into ambiguous SAFE FOR wording.' }
    if ($scriptText -match '(?i)https?://|Invoke-RestMethod|curl|RunCommand') { Fail 'FinalCardPolish.lua must remain presentation-only and local.' }
}

if ($errors.Count -gt 0) {
    foreach ($error in $errors) { Write-Host "FAIL: $error" -ForegroundColor Red }
    Write-Host "Final card polish validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Final card polish validation passed.' -ForegroundColor Green
Write-Host 'Departure wording preserves LEAVE IN versus LEAVE BEFORE; fixed foreign costs remain white, Torn MV muted gray, and profit/item green at far right.'
exit 0
