$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$Scripts = Join-Path $ProjectRoot '@Resources\Scripts'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

$required = @(
    'RuntimeLog.ps1','PopupHost.ps1','LaunchOptimizerSettings.ps1','LaunchFilterPopup.ps1','LaunchItemViewer.ps1',
    'OpenOptimizerSettings.ps1','OpenFilterPopup.ps1','FilterPreferences.ps1','OpportunityState.ps1','RunUpdate.ps1'
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
        "data\\runtime\\logs",
        'travel-assistant.log',
        'TravelAssistantLogRetentionDays = 7',
        'TravelAssistantLogMaxBytes = 262144',
        'Protect-TravelAssistantLogText',
        'Write-TravelAssistantLog',
        'Clear-TravelAssistantLatestError',
        '<redacted>'
    )) { if (-not $text.Contains($token)) { Fail "RuntimeLog.ps1 missing '$token'." } }
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
    foreach ($token in @('PopupHost.ps1','Start-Process','-WindowStyle Hidden','-STA','exit 0')) {
        if (-not $text.Contains($token)) { Fail "$launcher missing hidden-host contract '$token'." }
    }
    if ($text.Contains('-WindowStyle Normal')) { Fail "$launcher must not expose a PowerShell console window." }
}

$settingsUiPath = Join-Path $Scripts 'OpenOptimizerSettings.ps1'
if (Test-Path -LiteralPath $settingsUiPath) {
    $text = Get-Content -LiteralPath $settingsUiPath -Raw
    if ($text.Contains('-WindowStyle Normal')) { Fail 'OpenOptimizerSettings.ps1 must not spawn visible PowerShell consoles.' }
    foreach ($token in @('RuntimeLog.ps1','Write-TravelAssistantLog','-WindowStyle Hidden')) {
        if (-not $text.Contains($token)) { Fail "OpenOptimizerSettings.ps1 missing '$token'." }
    }
}

$filterUiPath = Join-Path $Scripts 'OpenFilterPopup.ps1'
if (Test-Path -LiteralPath $filterUiPath) {
    $text = Get-Content -LiteralPath $filterUiPath -Raw
    foreach ($token in @('RuntimeLog.ps1','Write-TravelAssistantLog','OptimalRoute.ps1','OpportunityState.ps1','FilterState.ps1')) {
        if (-not $text.Contains($token)) { Fail "OpenFilterPopup.ps1 missing '$token'." }
    }
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
    foreach ($token in @('RuntimeLog.ps1','Write-TravelAssistantLog','Clear-TravelAssistantLatestError','filter-state-error.txt','run-update')) {
        if (-not $text.Contains($token)) { Fail "RunUpdate.ps1 missing centralized diagnostic token '$token'." }
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Runtime diagnostics validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Hidden popup host, scope-safe entrypoints, and bounded runtime logging validation passed.' -ForegroundColor Green
Write-Host 'Runtime log: data\runtime\logs\travel-assistant.log (7-day / 256 KiB bounded, local and Git-ignored).'
exit 0
