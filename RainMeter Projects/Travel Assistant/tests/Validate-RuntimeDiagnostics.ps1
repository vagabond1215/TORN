$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Scripts = Join-Path $ProjectRoot '@Resources\Scripts'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

$required = @(
    'RuntimeLog.ps1','PopupHost.ps1','LaunchOptimizerSettings.ps1','LaunchFilterPopup.ps1','LaunchItemViewer.ps1','LaunchSettings.ps1','LaunchUpdate.ps1',
    'OpenOptimizerSettings.ps1','OpenFilterPopup.ps1','OpenSettings.ps1','FilterPreferences.ps1','OpportunityState.ps1','RunUpdate.ps1','EnsureEngineStateSchema.ps1'
)
foreach ($name in $required) {
    $path = Join-Path $Scripts $name
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing runtime diagnostic asset $name."; continue }
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in ${name}: $($parseError.Message)" }
}

$logPath = Join-Path $Scripts 'RuntimeLog.ps1'
if (Test-Path -LiteralPath $logPath) {
    $text = Get-Content -LiteralPath $logPath -Raw
    foreach ($token in @(
        'data\runtime\logs',
        'travel-assistant.log',
        'TravelAssistantLogRetentionDays = 7',
        'TravelAssistantLogMaxBytes = 262144',
        'Read-TravelAssistantLogTailText',
        '[System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete',
        'Protect-TravelAssistantLogText',
        'Write-TravelAssistantLog',
        'Clear-TravelAssistantLatestError',
        '<redacted>'
    )) { if (-not $text.Contains($token)) { Fail "RuntimeLog.ps1 missing '$token'." } }
    if ($text.Contains('Get-Content -LiteralPath $TravelAssistantLogFile -Tail')) { Fail 'RuntimeLog.ps1 must not scan oversized logs by line from the end.' }
    if ($text.TrimEnd().EndsWith('Invoke-TravelAssistantLogMaintenance')) { Fail 'Importing RuntimeLog.ps1 must not eagerly rotate logs on launcher startup.' }
}

$hostPath = Join-Path $Scripts 'PopupHost.ps1'
if (Test-Path -LiteralPath $hostPath) {
    $text = Get-Content -LiteralPath $hostPath -Raw
    foreach ($token in @('RuntimeLog.ps1','OpenFilterPopup.ps1','OpenOptimizerSettings.ps1','OpenItemViewer.ps1','Write-TravelAssistantLog','MessageBox','Clear-TravelAssistantLatestError')) {
        if (-not $text.Contains($token)) { Fail "PopupHost.ps1 missing '$token'." }
    }
}

foreach ($launcher in @('LaunchOptimizerSettings.ps1','LaunchFilterPopup.ps1','LaunchItemViewer.ps1')) {
    $path = Join-Path $Scripts $launcher
    if (-not (Test-Path -LiteralPath $path)) { continue }
    $text = Get-Content -LiteralPath $path -Raw
    foreach ($token in @('PopupHost.ps1','RuntimeLog.ps1','-WindowStyle Hidden','-STA','System.Diagnostics.ProcessStartInfo','[System.Diagnostics.Process]::Start($psi)','UseShellExecute = $false','CreateNoWindow = $true','return','Format-TravelAssistantErrorRecord')) {
        if (-not $text.Contains($token)) { Fail "$launcher missing reusable hidden-host contract '$token'." }
    }
    if ($text.Contains('Start-Process')) { Fail "$launcher must use the detached .NET process API rather than Start-Process." }
    if ($text.Contains('exit 0')) { Fail "$launcher must return after spawning so nested Settings calls cannot terminate their parent host." }
    if ($text.Contains('-WindowStyle Normal')) { Fail "$launcher must not expose a PowerShell console window." }
}

$profileLauncherPath = Join-Path $Scripts 'LaunchSettings.ps1'
if (Test-Path -LiteralPath $profileLauncherPath) {
    $text = Get-Content -LiteralPath $profileLauncherPath -Raw
    foreach ($token in @('OpenSettings.ps1','RuntimeLog.ps1','-WindowStyle Hidden','-STA','System.Diagnostics.ProcessStartInfo','[System.Diagnostics.Process]::Start($psi)','UseShellExecute = $false','CreateNoWindow = $true','return','Format-TravelAssistantErrorRecord')) {
        if (-not $text.Contains($token)) { Fail "LaunchSettings.ps1 missing reusable Profile/API launcher contract '$token'." }
    }
    if ($text.Contains('Start-Process')) { Fail 'LaunchSettings.ps1 must use the detached .NET process API rather than Start-Process.' }
    if ($text.Contains('exit 0')) { Fail 'LaunchSettings.ps1 must return so Optimizer Settings stays open when Profile/API is launched.' }
}

$settingsUiPath = Join-Path $Scripts 'OpenOptimizerSettings.ps1'
if (Test-Path -LiteralPath $settingsUiPath) {
    $text = Get-Content -LiteralPath $settingsUiPath -Raw
    if ($text.Contains('-WindowStyle Normal')) { Fail 'OpenOptimizerSettings.ps1 must not spawn visible PowerShell consoles.' }
    foreach ($token in @('RuntimeLog.ps1','Write-TravelAssistantLog','LaunchUpdate.ps1','& $UpdateLauncher -Action Update')) {
        if (-not $text.Contains($token)) { Fail "OpenOptimizerSettings.ps1 missing '$token'." }
    }
    if ($text.Contains("Join-Path `$PSScriptRoot 'RunUpdate.ps1'") -or $text.Contains("Start-Process -FilePath 'powershell.exe'")) {
        Fail 'OpenOptimizerSettings.ps1 must refresh through LaunchUpdate.ps1 rather than start RunUpdate directly under Windows PowerShell.'
    }
}

$profileUiPath = Join-Path $Scripts 'OpenSettings.ps1'
if (Test-Path -LiteralPath $profileUiPath) {
    $text = Get-Content -LiteralPath $profileUiPath -Raw
    foreach ($token in @('LaunchUpdate.ps1','Start-BackgroundUpdate','& $UpdateLauncherPath -Action Update')) {
        if (-not $text.Contains($token)) { Fail "OpenSettings.ps1 missing updater-launcher contract '$token'." }
    }
    if ($text.Contains("Join-Path `$PSScriptRoot 'RunUpdate.ps1'") -or $text.Contains("Start-Process -FilePath 'powershell.exe' -ArgumentList `$arguments")) {
        Fail 'OpenSettings.ps1 must refresh through LaunchUpdate.ps1 rather than start RunUpdate directly under Windows PowerShell.'
    }
}

$filterUiPath = Join-Path $Scripts 'OpenFilterPopup.ps1'
if (Test-Path -LiteralPath $filterUiPath) {
    $text = Get-Content -LiteralPath $filterUiPath -Raw
    foreach ($token in @('RuntimeLog.ps1','Write-TravelAssistantLog','Read-OptionalPopupJson','Start-FilterProjectionRefresh','$prefs.displayTripBands')) {
        if (-not $text.Contains($token)) { Fail "OpenFilterPopup.ps1 missing '$token'." }
    }
    if ($text.Contains('$bands=New-StringSet @($prefs.selectedTripBands)')) { Fail 'Country popup must use displayTripBands, not the always-on candidate trip-band scope.' }
    $legacyPartial = "foreach(`$scriptName in @('OptimalRoute.ps1','OpportunityState.ps1','FilterState.ps1'))"
    if ($text.Contains($legacyPartial)) { Fail 'Filter popups must not run an ad-hoc partial projection chain.' }
}

$filterPrefsPath = Join-Path $Scripts 'FilterPreferences.ps1'
if (Test-Path -LiteralPath $filterPrefsPath) {
    $text = Get-Content -LiteralPath $filterPrefsPath -Raw
    if (-not $text.Contains("[Alias('SkipMain')]")) { Fail 'FilterPreferences.ps1 must preserve -SkipMain compatibility through an alias.' }
    if (-not $text.Contains('$FilterPreferencesSkipMain')) { Fail 'FilterPreferences.ps1 must use a helper-specific SkipMain variable.' }
    if ($text.Contains('if ($SkipMain)')) { Fail 'FilterPreferences.ps1 must not gate main execution on a caller-colliding $SkipMain variable.' }
}

$opportunityPath = Join-Path $Scripts 'OpportunityState.ps1'
if (Test-Path -LiteralPath $opportunityPath) {
    $text = Get-Content -LiteralPath $opportunityPath -Raw
    if (-not $text.Contains("[Alias('SkipMain')]")) { Fail 'OpportunityState.ps1 must preserve -SkipMain compatibility through an alias.' }
    if (-not $text.Contains('$OpportunityStateSkipMain')) { Fail 'OpportunityState.ps1 must use its own SkipMain variable.' }
    if ($text.Contains('if ($SkipMain)')) { Fail 'OpportunityState.ps1 must not return because a dot-sourced helper overwrote $SkipMain.' }
    foreach ($token in @('Opportunity prerequisites missing or invalid:','-SkipMain -Now $requestedNow')) {
        if (-not $text.Contains($token)) { Fail "OpportunityState.ps1 missing entrypoint diagnostic '$token'." }
    }
}

$updatePath = Join-Path $Scripts 'RunUpdate.ps1'
if (Test-Path -LiteralPath $updatePath) {
    $text = Get-Content -LiteralPath $updatePath -Raw
    foreach ($token in @(
        'RuntimeLog.ps1','Write-TravelAssistantLog','Clear-TravelAssistantLatestError','filter-state-error.txt','run-update',
        'UpdatePerformanceRows','System.Diagnostics.Stopwatch','TotalProcessorTime','New-UpdateStageTimer','Complete-UpdateStageTimer',
        'Write-UpdatePerformanceSummary','Write-UpdatePerformanceRecord','update-performance.log','update-performance-error.txt',
        '[System.IO.File]::AppendAllText(','Performance telemetry record was not created:',
        "Write-TravelAssistantLog -Level WARN -Component 'performance'",
        "-Component 'performance'",'total_cpu_ms=','total_wall_ms=','stages=',
        "'publish-ui'","'publish-heartbeat'","'generation-cleanup'"
    )) {
        if (-not $text.Contains($token)) {
            Fail "RunUpdate.ps1 missing centralized diagnostic/performance token '$token'."
        }
    }

    if ($text.Contains("Invoke-HistoryMaintenance -Phase 'PostUpdate'")) {
        Fail 'RunUpdate.ps1 must not pay for the retired no-op PostUpdate history pass on every heartbeat.'
    }
    if ($text.Contains('foreach ($row in @($script:UpdatePerformanceRows))')) {
        Fail 'RunUpdate.ps1 must iterate the generic performance row list directly; PowerShell array coercion can throw PSToObjectArrayBinder ArgumentException.'
    }
    if (-not $text.Contains('foreach ($row in $script:UpdatePerformanceRows)')) {
        Fail 'RunUpdate.ps1 must directly enumerate UpdatePerformanceRows.'
    }
    if (-not $text.Contains('$stageParts.ToArray()')) {
        Fail 'RunUpdate.ps1 must join a concrete stage string array without generic-list coercion.'
    }


    $successExitWindows = "`$UpdatePerformanceOutcome = 'success'`r`n    exit 0"
    $successExitUnix = "`$UpdatePerformanceOutcome = 'success'`n    exit 0"
    if ($text.Contains($successExitWindows) -or $text.Contains($successExitUnix)) {
        Fail 'RunUpdate.ps1 must fall through after success so finally always writes performance telemetry and releases the updater mutex.'
    }
}

foreach ($childName in @('ProjectCollectedState.ps1','CurrentCapacityRefresh.ps1','CycleAnchorReconciler.ps1')) {
    $childPath = Join-Path $Scripts $childName
    if (-not (Test-Path -LiteralPath $childPath)) {
        Fail "Missing in-process updater child $childName."
        continue
    }

    $childText = Get-Content -LiteralPath $childPath -Raw
    if ($childText -match '(?m)^\s*exit\s+0\s*$') {
        Fail "$childName must return to RunUpdate.ps1 rather than terminate the hosting PowerShell process with exit 0."
    }
}

$analyzerPath = Join-Path $ProjectRoot 'tools\Analyze-UpdatePerformance.ps1'
if (-not (Test-Path -LiteralPath $analyzerPath)) {
    Fail 'Missing tools\Analyze-UpdatePerformance.ps1.'
} else {
    $analyzerText = Get-Content -LiteralPath $analyzerPath -Raw
    foreach ($token in @(
        'update-performance.log',
        'AtomicFile.ps1',
        'Open-TravelAssistantSharedTextReader -Path $sourcePath',
        'No updater performance samples are present yet.'
    )) {
        if (-not $analyzerText.Contains($token)) {
            Fail "Analyze-UpdatePerformance.ps1 missing durable telemetry token '$token'."
        }
    }
}

$schemaPath = Join-Path $Scripts 'EnsureEngineStateSchema.ps1'
if (Test-Path -LiteralPath $schemaPath) {
    $schemaText = Get-Content -LiteralPath $schemaPath -Raw
    foreach ($token in @(
        'activeCycleRepairKeys',
        '$activeCycleRepairKeys.Count -gt 0',
        'Open-TravelAssistantSharedTextReader -Path $ObservationFile',
        '$activeCycleRepairKeys.Contains($key)',
        'exceptional',
        'steady-state updater never scans'
    )) {
        if (-not $schemaText.Contains($token)) {
            Fail "EnsureEngineStateSchema.ps1 missing CPU-efficiency token '$token'."
        }
    }

    if ($schemaText.Contains('foreach ($line in Get-Content -LiteralPath $ObservationFile)')) {
        Fail 'EnsureEngineStateSchema.ps1 must use the delete-sharing reader and only enter the repair scan when candidates exist.'
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) {
        Write-Host "FAIL: $message" -ForegroundColor Red
    }
    Write-Host "Runtime diagnostics validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Reusable detached popup hosts, PS7 settings refresh routing, bounded runtime logging, and updater CPU profiling/steady-state scan guards validation passed.' -ForegroundColor Green
Write-Host 'Runtime log: data\runtime\logs\travel-assistant.log (7-day / 256 KiB bounded, local and Git-ignored).'
exit 0
