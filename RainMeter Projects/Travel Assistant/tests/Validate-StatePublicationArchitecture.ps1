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

    # The configured path is the direct-snapshot fallback for a numeric legacy
    # heartbeat; production readers resolve immutable generations through the manifest.
    $uiStateToken = 'StateFile=#@#Generated\ui-state.kv'
    $mainReaderCount = ([regex]::Matches($ini,[regex]::Escape($uiStateToken))).Count
    if ($mainReaderCount -ne 3) {
        Fail "MeasureState, MeasureCardPresenter, and MeasureCardTweaks must all read finalized ui-state.kv; found $mainReaderCount matching main StateFile entries."
    }
    $infoReaderCount = ([regex]::Matches($info,[regex]::Escape($uiStateToken))).Count
    if ($infoReaderCount -ne 2) {
        Fail "FreshnessGuard and TravelStateWindowTweaks must both read finalized ui-state.kv; found $infoReaderCount matching included StateFile entries."
    }
    foreach ($surface in @($ini,$info)) {
        if ($surface -match '(?m)^StateFile=#@#Generated\\state\.kv\s*$') {
            Fail 'A live Rainmeter measure still reads the intermediate build state.kv directly.'
        }
    }

    foreach ($token in @(
        "`$StateKvFile = Join-Path `$GeneratedDir 'state.kv'",
        "'ui-state-{0}-{1}.kv'",
        'function Publish-UpdateUiState',
        'Write-TravelAssistantAtomicText -Path (Join-Path $GeneratedDir $name) -Text $text',
        'UIGeneration=',
        'Build state.kv is incomplete after FilterState; refusing UI publication.',
        'Publish-UpdateUiState',
        'Write-UpdateHeartbeat',
        'Remove-OldUiStateGenerations'
    )) {
        if (-not $runUpdate.Contains($token)) { Fail "RunUpdate.ps1 missing publication contract '$token'." }
    }
    if ($runUpdate.Contains('Write-TravelAssistantAtomicText -Path $UiStateKvFile')) { Fail 'RunUpdate must not replace the Rainmeter-read snapshot directly.' }

    $filterAt = $runUpdate.IndexOf('if (Test-Path -LiteralPath $FilterState)',[System.StringComparison]::Ordinal)
    $publishCallAt = $runUpdate.LastIndexOf('Publish-UpdateUiState',[System.StringComparison]::Ordinal)
    $heartbeatCallAt = $runUpdate.LastIndexOf('Write-UpdateHeartbeat',[System.StringComparison]::Ordinal)
    if ($filterAt -lt 0 -or $publishCallAt -lt 0 -or $heartbeatCallAt -lt 0) {
        Fail 'Could not locate FilterState -> UI publish -> heartbeat ordering.'
    } elseif (-not ($filterAt -lt $publishCallAt -and $publishCallAt -lt $heartbeatCallAt)) {
        Fail 'RunUpdate must complete FilterState, publish exactly one finalized UI state, then write the heartbeat.'
    }

    $tokens=$null; $parseErrors=$null
    $runUpdateAst=[System.Management.Automation.Language.Parser]::ParseFile($runUpdatePath,[ref]$tokens,[ref]$parseErrors)
    foreach($parseError in @($parseErrors)) {
        Fail ("PowerShell parse error in RunUpdate.ps1 while validating publication architecture: " + $parseError.Message)
    }
    $publishInvocationCount=@($runUpdateAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
        $node.GetCommandName() -eq 'Publish-UpdateUiState'
    },$true)).Count
    if ($publishInvocationCount -ne 1) {
        Fail "RunUpdate must invoke final UI publication exactly once; found $publishInvocationCount invocations."
    }

    if (-not $atomic.Contains('function Get-TravelAssistantStateFilePath')) {
        Fail 'AtomicFile.ps1 must retain the build-state path helper for controlled private-state routing.'
    }
    if (-not $atomic.Contains('$env:TORN_TRAVEL_STATE_KV')) {
        Fail 'AtomicFile.ps1 must retain the optional private-state override contract.'
    }

    foreach ($token in @('function module.configure','function module.read','function module.epoch','cachedData','UIGeneration','ui%-state%-%d+%-%x+%.kv','return copyData()')) {
        if (-not $compat.Contains($token)) { Fail "PublishedState.lua immutable-reader contract missing '$token'." }
    }

    foreach ($luaName in @('StateReader.lua','CardPresenter.lua','CardTweaks.lua','FreshnessGuard.lua','TravelStateWindowTweaks.lua')) {
        $luaText = Get-Content -LiteralPath (Join-Path $ProjectRoot ('@Resources\Scripts\' + $luaName)) -Raw
        foreach ($token in @('last-update.txt','ui%-state%-%d+%-%x+%.kv')) {
            if (-not $luaText.Contains($token)) {
                Fail "$luaName must resolve immutable finalized state from the generation manifest; missing '$token'."
            }
        }
        if ($luaText.Contains('dofile(')) {
            Fail "$luaName must not depend on a secondary Lua module during Rainmeter initialization."
        }
    }

    $stateReader = Get-Content -LiteralPath (Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua') -Raw
    if (-not $stateReader.Contains('if path==statePath then')) {
        Fail 'StateReader.lua must only apply generation-manifest resolution to the main state path, not graph-spec reads.'
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "State publication architecture validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Immutable single-final-publication architecture validation passed.' -ForegroundColor Green
Write-Host 'Intermediate stages mutate private state.kv; a complete immutable generation is written after FilterState, then the small manifest advances.' -ForegroundColor Green
exit 0
