$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$infoPath = Join-Path $ProjectRoot '@Resources\Includes\OpportunityInfo.inc'
$runUpdatePath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$atomicPath = Join-Path $ProjectRoot '@Resources\Scripts\AtomicFile.ps1'
$publishedStatePath = Join-Path $ProjectRoot '@Resources\Scripts\PublishedState.lua'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($iniPath,$infoPath,$runUpdatePath,$atomicPath,$publishedStatePath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing publication architecture file: $path" }
}

if ($errors.Count -eq 0) {
    $ini = Get-Content -LiteralPath $iniPath -Raw
    $info = Get-Content -LiteralPath $infoPath -Raw
    $runUpdate = Get-Content -LiteralPath $runUpdatePath -Raw
    $atomic = Get-Content -LiteralPath $atomicPath -Raw
    $compat = Get-Content -LiteralPath $publishedStatePath -Raw

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
    foreach ($forbidden in @('ui-state-{0}-{1}.kv','UIGeneration=','Remove-OldUiStateGenerations',"`$epoch + '|'")) {
        if ($runUpdate.Contains($forbidden)) { Fail "RunUpdate.ps1 must not restore the retired manifest-generation contract '$forbidden'." }
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

    # The compatibility module exists only so a partially updated Rainmeter process
    # cannot crash if an older loaded Lua chunk still calls PublishedState.lua.
    # Production readers must not depend on it and it must not reintroduce the
    # retired immutable-generation / manifest-selection behavior.
    foreach ($token in @('function module.configure','function module.read','function module.epoch','return readKv(statePath)','raw:match(''^(%d+)'')')) {
        if (-not $compat.Contains($token)) { Fail "PublishedState.lua compatibility shim missing '$token'." }
    }
    foreach ($forbidden in @('ui%-state%-%d+%-%x+%.kv','UIGeneration','cachedData','cachedKey','generatedDir')) {
        if ($compat.Contains($forbidden)) { Fail "PublishedState.lua compatibility shim must not restore manifest-generation behavior '$forbidden'." }
    }

    foreach ($luaName in @('StateReader.lua','CardPresenter.lua','CardTweaks.lua','FreshnessGuard.lua','TravelStateWindowTweaks.lua','WindowTooltipTweaks.lua')) {
        $luaText = Get-Content -LiteralPath (Join-Path $ProjectRoot ('@Resources\Scripts\' + $luaName)) -Raw
        if ($luaText.Contains('PublishedState.lua') -or $luaText.Contains('publishedState')) {
            Fail "$luaName must read finalized ui-state.kv directly; the compatibility shim is not a production dependency."
        }
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "State publication architecture validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Direct single-final-publication architecture validation passed.' -ForegroundColor Green
Write-Host 'Intermediate stages mutate private state.kv; one complete ui-state.kv is atomically published after FilterState, then the numeric heartbeat advances. PublishedState.lua is compatibility-only.' -ForegroundColor Green
exit 0
