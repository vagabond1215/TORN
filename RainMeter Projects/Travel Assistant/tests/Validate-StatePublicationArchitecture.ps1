$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$infoPath = Join-Path $ProjectRoot '@Resources\Includes\OpportunityInfo.inc'
$runUpdatePath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$atomicPath = Join-Path $ProjectRoot '@Resources\Scripts\AtomicFile.ps1'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($iniPath,$infoPath,$runUpdatePath,$atomicPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing publication architecture file: $path" }
}

if ($errors.Count -eq 0) {
    $ini = Get-Content -LiteralPath $iniPath -Raw
    $info = Get-Content -LiteralPath $infoPath -Raw
    $runUpdate = Get-Content -LiteralPath $runUpdatePath -Raw
    $atomic = Get-Content -LiteralPath $atomicPath -Raw

    $uiStateToken = 'StateFile=#@#Generated\ui-state.kv'
    $mainReaderCount = ([regex]::Matches($ini,[regex]::Escape($uiStateToken))).Count
    if ($mainReaderCount -ne 3) {
        Fail "MeasureState, MeasureCardPresenter, and MeasureCardTweaks must all read finalized ui-state.kv; found $mainReaderCount matching main StateFile entries."
    }
    $infoReaderCount = ([regex]::Matches($info,[regex]::Escape($uiStateToken))).Count
    if ($infoReaderCount -ne 3) {
        Fail "FreshnessGuard, TravelStateWindowTweaks, and WindowTooltipTweaks must all read finalized ui-state.kv; found $infoReaderCount matching included StateFile entries."
    }
    foreach ($surface in @($ini,$info)) {
        if ($surface -match '(?m)^StateFile=#@#Generated\\state\.kv\s*$') {
            Fail 'A live Rainmeter measure still reads the intermediate build state.kv directly.'
        }
    }

    foreach ($token in @(
        "`$StateKvFile = Join-Path `$GeneratedDir 'state.kv'",
        "`$UiStateKvFile = Join-Path `$GeneratedDir 'ui-state.kv'",
        'function Publish-UpdateUiState',
        'Write-TravelAssistantAtomicText -Path $UiStateKvFile -Text $text',
        'Build state.kv is incomplete after FilterState; refusing UI publication.',
        'Publish-UpdateUiState',
        'Write-UpdateHeartbeat'
    )) {
        if (-not $runUpdate.Contains($token)) { Fail "RunUpdate.ps1 missing publication contract '$token'." }
    }

    $filterAt = $runUpdate.IndexOf('if (Test-Path -LiteralPath $FilterState)',[System.StringComparison]::Ordinal)
    $publishCallAt = $runUpdate.LastIndexOf('Publish-UpdateUiState',[System.StringComparison]::Ordinal)
    $heartbeatCallAt = $runUpdate.LastIndexOf('Write-UpdateHeartbeat',[System.StringComparison]::Ordinal)
    if ($filterAt -lt 0 -or $publishCallAt -lt 0 -or $heartbeatCallAt -lt 0) {
        Fail 'Could not locate FilterState -> UI publish -> heartbeat ordering.'
    } elseif (-not ($filterAt -lt $publishCallAt -and $publishCallAt -lt $heartbeatCallAt)) {
        Fail 'RunUpdate must complete FilterState, publish exactly one finalized UI state, then write the heartbeat.'
    }

    $publishInvocationCount = ([regex]::Matches($runUpdate,'(?m)^\s*Publish-UpdateUiState\s*$')).Count
    if ($publishInvocationCount -ne 1) {
        Fail "RunUpdate must invoke final UI publication exactly once; found $publishInvocationCount invocations."
    }

    if (-not $atomic.Contains('function Get-TravelAssistantStateFilePath')) {
        Fail 'AtomicFile.ps1 must retain the build-state path helper for controlled private-state routing.'
    }
    if (-not $atomic.Contains('$env:TORN_TRAVEL_STATE_KV')) {
        Fail 'AtomicFile.ps1 must retain the optional private-state override contract.'
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "State publication architecture validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Single-final-publication architecture validation passed.' -ForegroundColor Green
Write-Host 'Intermediate stages mutate state.kv; all live Rainmeter state readers use ui-state.kv; heartbeat follows the one final UI publication.' -ForegroundColor Green
exit 0
