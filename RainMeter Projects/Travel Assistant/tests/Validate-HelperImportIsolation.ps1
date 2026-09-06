$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$resolveChancePath = Join-Path $ProjectRoot '@Resources\Scripts\ResolveChanceHistory.ps1'
$multiCyclePath = Join-Path $ProjectRoot '@Resources\Scripts\MultiCycleChanceBridge.ps1'

$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $errors.Add($Message) }
function Assert-True([string]$Message,[bool]$Condition) { if (-not $Condition) { Fail $Message } }
function Assert-Equal([string]$Message,$Actual,$Expected) { if ($Actual -ne $Expected) { Fail ("{0}: expected '{1}', got '{2}'" -f $Message,$Expected,$Actual) } }

foreach ($path in @($resolveChancePath,$multiCyclePath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail ("Missing required file: {0}" -f $path) }
}

function Test-ResolveChanceImportIsolation {
    $expectedNow = 1700000123L
    $expectedGrace = 77
    . $resolveChancePath -SkipMain -Now $expectedNow -OutcomeGraceSeconds $expectedGrace

    Assert-Equal 'ResolveChanceHistory preserves explicit Now across calibration helper import' ([long]$Now) $expectedNow
    Assert-Equal 'ResolveChanceHistory preserves its outcome grace across calibration helper import' ([int]$OutcomeGraceSeconds) $expectedGrace
    Assert-Equal 'ResolveChanceHistory preserves its summary destination' ([System.IO.Path]::GetFileName([string]$SummaryFile)) 'chance-accuracy.json'
    Assert-True 'ResolveChanceHistory still imports confirmed-outcome helper functions' ($null -ne (Get-Command Get-SCConfirmedOutcome -CommandType Function -ErrorAction SilentlyContinue))
    Assert-True 'ResolveChanceHistory still imports shared evidence-map helper functions' ($null -ne (Get-Command Read-SCEvidenceMap -CommandType Function -ErrorAction SilentlyContinue))
}

function Test-MultiCycleImportIsolation {
    $expectedNow = 1700000456L
    $expectedSimulationCount = 333
    . $multiCyclePath -SkipMain -Now $expectedNow -SimulationCount $expectedSimulationCount

    Assert-Equal 'MultiCycleChanceBridge preserves explicit Now across stochastic helper import' ([long]$Now) $expectedNow
    Assert-Equal 'MultiCycleChanceBridge preserves its simulation count across stochastic helper import' ([int]$SimulationCount) $expectedSimulationCount
    Assert-True 'MultiCycleChanceBridge still imports stochastic property helpers' ($null -ne (Get-Command Get-SFProperty -CommandType Function -ErrorAction SilentlyContinue))
    Assert-True 'MultiCycleChanceBridge still imports the market forecast helper' ($null -ne (Get-Command Invoke-SFMarketForecast -CommandType Function -ErrorAction SilentlyContinue))
}

if ($errors.Count -eq 0) {
    Test-ResolveChanceImportIsolation
    Test-MultiCycleImportIsolation

    $resolveText = Get-Content -LiteralPath $resolveChancePath -Raw
    Assert-True 'ResolveChanceHistory explicitly restores its caller-owned summary path after helper loading.' $resolveText.Contains('$SummaryFile=$RCHImportSummaryFile')
    Assert-True 'ResolveChanceHistory explicitly restores its caller-owned grace after helper loading.' $resolveText.Contains('$OutcomeGraceSeconds=$RCHImportOutcomeGraceSeconds')

    $multiText = Get-Content -LiteralPath $multiCyclePath -Raw
    Assert-True 'MultiCycleChanceBridge explicitly restores its caller-owned simulation count after helper loading.' $multiText.Contains('$SimulationCount=$MCImportSimulationCount')
    Assert-True 'MultiCycleChanceBridge explicitly restores its caller-owned Now after helper loading.' $multiText.Contains('$Now=$MCImportNow')
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host ("FAIL: {0}" -f $validationError) -ForegroundColor Red }
    Write-Host ("Helper import isolation validation failed with {0} error(s)." -f $errors.Count) -ForegroundColor Red
    exit 1
}

Write-Host 'Helper import isolation validation passed.' -ForegroundColor Green
Write-Host 'Dot-sourced helper defaults no longer overwrite caller Now, grace, simulation count, or chance-summary destination.' -ForegroundColor Green
exit 0
