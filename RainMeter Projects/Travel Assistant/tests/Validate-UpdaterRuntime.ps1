$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$launcherPath = Join-Path $ProjectRoot '@Resources\Scripts\LaunchUpdate.ps1'
$settingsPopupPath = Join-Path $ProjectRoot '@Resources\Scripts\OpenOptimizerSettings.ps1'
$filterPreferencesPath = Join-Path $ProjectRoot '@Resources\Scripts\FilterPreferences.ps1'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

if (-not (Test-Path -LiteralPath $iniPath)) {
    Fail "Missing TravelAssistant.ini: $iniPath"
} else {
    $ini = Get-Content -LiteralPath $iniPath -Raw

    function Get-SectionBody([string]$Name) {
        return [regex]::Match(
            $ini,
            ('(?ms)^\[' + [regex]::Escape($Name) + '\]\s*(.*?)(?=^\[|\z)')
        ).Groups[1].Value
    }

    $updateBody = Get-SectionBody 'MeasureUpdate'
    if ([string]::IsNullOrWhiteSpace($updateBody)) {
        Fail 'Missing [MeasureUpdate] body.'
    } else {
        if ($updateBody -notmatch '(?im)^Program=pwsh\.exe\s*$') {
            Fail 'MeasureUpdate must launch PowerShell 7 via Program=pwsh.exe.'
        }
        if ($updateBody -match '(?im)^Program=powershell\.exe\s*$') {
            Fail 'MeasureUpdate must not launch Windows PowerShell 5.1.'
        }
        $expectedParameter = 'Parameter=-NoProfile -ExecutionPolicy Bypass -File "#@#Scripts\LaunchUpdate.ps1" -Action Update'
        if (-not $updateBody.Contains($expectedParameter)) {
            Fail 'MeasureUpdate must launch the detached PS7 update launcher.'
        }
        if ($updateBody -match '(?im)^Parameter=.*RunUpdate\.ps1') {
            Fail 'Rainmeter must not own the long-running RunUpdate.ps1 worker directly.'
        }
    }

    $stateBody = Get-SectionBody 'MeasureState'
    if ([string]::IsNullOrWhiteSpace($stateBody)) {
        Fail 'Missing [MeasureState] body.'
    } else {
        if ($stateBody -notmatch '(?im)^PollInterval=60\s*$') { Fail 'MeasureState normal poll interval must remain 60 seconds.' }
        if ($stateBody -notmatch '(?im)^FailureRetryInterval=60\s*$') { Fail 'Update failures must use the normal 60-second poll cadence during target-host crash isolation.' }
        if ($stateBody -match '(?im)^FailureRetryInterval=15\s*$') { Fail 'The accelerated 15-second failure retry must not return.' }
    }

    $pwshCount = ([regex]::Matches($ini, '(?im)^Program=pwsh\.exe\s*$')).Count
    if ($pwshCount -ne 1) {
        Fail "Exactly one Rainmeter RunCommand measure should use pwsh.exe during this controlled migration; found $pwshCount."
    }

    foreach ($section in @(
        'MeasureSettings',
        'MeasureFilterPopup',
        'MeasureInlineGraph',
        'MeasurePreferenceAction'
    )) {
        $body = Get-SectionBody $section
        if ([string]::IsNullOrWhiteSpace($body)) {
            Fail "Missing [$section] body."
            continue
        }
        if ($body -notmatch '(?im)^Program=powershell\.exe\s*$') {
            Fail "$section must remain on Windows PowerShell during the updater-only runtime migration."
        }
        if ($body -match '(?im)^Program=pwsh\.exe\s*$') {
            Fail "$section was migrated to pwsh.exe prematurely; only MeasureUpdate is in scope."
        }
    }
}

if (-not (Test-Path -LiteralPath $launcherPath)) {
    Fail 'Missing LaunchUpdate.ps1.'
} else {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($launcherPath,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail ('LaunchUpdate.ps1 parse error: ' + $parseError.Message) }
    $launcher = Get-Content -LiteralPath $launcherPath -Raw
    foreach ($token in @('RunUpdate.ps1','Get-Command pwsh.exe','System.Diagnostics.ProcessStartInfo','[System.Diagnostics.Process]::Start($psi)','UseShellExecute = $false','CreateNoWindow = $true','[ValidateRange(0,300)]','[int]$MutexWaitSeconds = 0','-Action {1} -MutexWaitSeconds {2}',"[ValidateSet('Update','RefreshFilters','CycleTravelMode')]",'return')) {
        if (-not $launcher.Contains($token)) { Fail "LaunchUpdate.ps1 missing '$token'." }
    }
    if ($launcher.Contains('exit 0')) {
        Fail 'LaunchUpdate.ps1 must return after spawning so Settings can reuse it without terminating the popup host.'
    }
    foreach ($forbidden in @('FilterPreferences.ps1','Read-UiPreferences','Save-UiPreferences','Write-TravelAssistantAtomicText','Invoke-RestMethod')) {
        if ($launcher.Contains($forbidden)) { Fail "LaunchUpdate.ps1 must remain spawn-only and must not contain '$forbidden'." }
    }
}

if (-not (Test-Path -LiteralPath $settingsPopupPath)) {
    Fail 'Missing OpenOptimizerSettings.ps1.'
} else {
    $settingsPopup = Get-Content -LiteralPath $settingsPopupPath -Raw
    foreach ($token in @(
        'Set-FilterProperty $current ''itemMarketFeePercent'' $marketTaxPercent',
        '[void](Save-UiPreferences $current)',
        'Start-FilterProjectionRefresh -Action RefreshFilters'
    )) {
        if (-not $settingsPopup.Contains($token)) { Fail "Settings tax persistence/refresh contract missing '$token'." }
    }
}

if (-not (Test-Path -LiteralPath $filterPreferencesPath)) {
    Fail 'Missing FilterPreferences.ps1.'
} else {
    $filterPreferences = Get-Content -LiteralPath $filterPreferencesPath -Raw
    foreach ($token in @('RefreshFilters','-Action {1} -MutexWaitSeconds 120','Start-FilterProjectionRefresh -Action RefreshFilters')) {
        if (-not $filterPreferences.Contains($token)) {
            Fail "Preference-triggered filter refresh contract missing '$token'."
        }
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) {
        Write-Host "FAIL: $message" -ForegroundColor Red
    }
    Write-Host "Updater runtime validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Rainmeter updater runtime contract passed.' -ForegroundColor Green
Write-Host 'MeasureUpdate uses a reusable spawn-only PS7 launcher; Settings and filters queue RefreshFilters behind an active poll so committed local projection changes cannot be stranded.' -ForegroundColor Green
exit 0
