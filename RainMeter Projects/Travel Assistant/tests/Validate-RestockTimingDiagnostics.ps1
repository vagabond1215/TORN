$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$travelPath = Join-Path $ProjectRoot '@Resources\Scripts\TravelStateWindowTweaks.lua'

$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $errors.Add($Message) }
function Assert-True([string]$Message,[bool]$Condition) { if (-not $Condition) { Fail $Message } }

if (-not (Test-Path -LiteralPath $travelPath)) { Fail ("Missing required file: {0}" -f $travelPath) }

if ($errors.Count -eq 0) {
    $travel = Get-Content -LiteralPath $travelPath -Raw

    Assert-True 'Travel rows must project the verified restock sample count.' $travel.Contains("restockSampleCount=number(state[prefix..'RestockSampleCount'])")
    Assert-True 'Travel rows must project the median restock delay.' $travel.Contains("medianRestockDelay=number(state[prefix..'MedianRestockDelaySeconds'])")
    Assert-True 'Travel rows must retain the window-model diagnostic reason.' $travel.Contains("windowDataQualityReason=trim(state[prefix..'WindowDataQualityReason'])")
    Assert-True 'A dedicated restock timing diagnostic helper must exist.' $travel.Contains('local function restockTimingDiagnostic(row)')

    Assert-True 'Missing current sellout anchors must be identified explicitly.' $travel.Contains("Restock unavailable - sellout anchor missing")
    Assert-True 'Zero verified restock cycles must be identified explicitly.' $travel.Contains("Restock unavailable - 0 verified cycles")
    Assert-True 'Verified history without a published delay must be identified explicitly.' $travel.Contains("Restock unavailable - no usable delay")
    Assert-True 'Timing inputs without a next-restock publication must be identified explicitly.' $travel.Contains("Restock unavailable - estimate not published")

    Assert-True 'The old generic Restock timing learning status must no longer be emitted.' (-not $travel.Contains("return 'Restock timing learning'"))
    Assert-True 'Arrival tooltips must include the diagnostic when a restock estimate is unavailable.' $travel.Contains("local _,diagnostic=restockTimingDiagnostic(row)")
    Assert-True 'Abroad OoS rows without usable plan geometry must use the diagnostic.' $travel.Contains('return restockTimingDiagnostic(row)')
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host ("FAIL: {0}" -f $validationError) -ForegroundColor Red }
    Write-Host ("Restock timing diagnostic validation failed with {0} error(s)." -f $errors.Count) -ForegroundColor Red
    exit 1
}

Write-Host 'Restock timing diagnostic validation passed.' -ForegroundColor Green
Write-Host 'Generic restock learning output is replaced with actionable anchor/sample/delay diagnostics.' -ForegroundColor Green
exit 0
