$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $ProjectRoot '@Resources\Scripts\HistoryRecovery.ps1'
$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$settingsPath = Join-Path $ProjectRoot 'config\settings.local.example.json'
$countriesPath = Join-Path $ProjectRoot 'config\countries.json'
$settingsUiPath = Join-Path $ProjectRoot '@Resources\Scripts\OpenSettings.ps1'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($scriptPath,$wrapperPath,$settingsPath,$countriesPath,$settingsUiPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing history-recovery contract file: $path" }
}

if ($errors.Count -eq 0) {
    $scriptText = Get-Content -LiteralPath $scriptPath -Raw
    $wrapper = Get-Content -LiteralPath $wrapperPath -Raw
    $settings = Get-Content -LiteralPath $settingsPath -Raw
    $countries = Get-Content -LiteralPath $countriesPath -Raw
    $settingsUi = Get-Content -LiteralPath $settingsUiPath -Raw

    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($scriptPath,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail ('HistoryRecovery.ps1 parse error: ' + $parseError.Message) }

    foreach ($token in @(
        'tornIntelClientKey',
        'TORN_INTEL_CLIENT_KEY',
        'https://torn-intel.com/api/v1/public/foreign-stock/history',
        'X-Torn-Intel-Key',
        '[int]$MinimumAttemptIntervalSeconds = 60',
        'if($MinimumAttemptIntervalSeconds -lt 60){$MinimumAttemptIntervalSeconds=60}',
        '$windowClose=$lastOos+[long]$summary.averageDelaySeconds+[long]$summary.varianceSeconds',
        '$now -lt ($windowClose+60L)',
        '[int]$summary.sampleCount -lt 2',
        'Get-RecoveryProperty $market ''lastStock''',
        'Sort-Object windowCloseAt,marketKey|Select-Object -First 1',
        'Scan retained evidence only for the one request we are actually about to make.',
        "source='torn_intel_history_recovery'",
        "source='history_recovery_live_bridge'",
        "transitionBoundaryQuality='recovered'",
        "evidenceQuality='bounded_fresh'",
        'Append-RecoveryCycle -Cycle $recoveredCycle',
        "restockBoundaryQuality='recovered'",
        "soldOutBoundaryQuality='recovered'",
        "status='NO_MISSED_TRANSITION'",
        "status='RECOVERED'"
    )) {
        if (-not $scriptText.Contains($token)) { Fail "History recovery contract missing '$token'." }
    }

    foreach ($forbidden in @(
        'tornApiKey',
        'Sec-Fetch-',
        'Mozilla/',
        "transitionBoundaryQuality='observed'"
    )) {
        if ($scriptText.Contains($forbidden)) { Fail "History recovery must not contain unsafe/incorrect token '$forbidden'." }
    }

    $publishAt = $wrapper.IndexOf('try { Publish-UpdateUiState }',[System.StringComparison]::Ordinal)
    $recoveryAt = $wrapper.IndexOf('Invoke-FailSoftScript -Path $HistoryRecovery -ErrorPath $HistoryRecoveryErrorFile',[System.StringComparison]::Ordinal)
    if ($publishAt -lt 0 -or $recoveryAt -le $publishAt) { Fail 'History recovery must execute only after immutable UI publication.' }

    if (-not $settings.Contains('"tornIntelClientKey": ""')) { Fail 'settings.local.example.json must expose an empty optional Torn Intel client key.' }
    foreach ($token in @(
        'Torn Intel recovery key',
        'tornIntelClientKey',
        '$historyKeyBox.UseSystemPasswordChar = $true',
        'missed-transition history recovery after a restock window closes'
    )) {
        if (-not $settingsUi.Contains($token)) { Fail "Settings UI history-recovery contract missing '$token'." }
    }

    try {
        $countryJson = $countries | ConvertFrom-Json
        foreach ($country in @($countryJson.countries | Where-Object { $_.collect -eq $true })) {
            if (-not $country.PSObject.Properties['providerCodes'] -or
                -not $country.providerCodes.PSObject.Properties['tornIntel'] -or
                [string]::IsNullOrWhiteSpace([string]$country.providerCodes.tornIntel)) {
                Fail ("Collected country {0} is missing a Torn Intel history code." -f [string]$country.id)
            }
        }
    } catch {
        Fail ('countries.json failed history-recovery validation: ' + $_.Exception.Message)
    }
}

if ($errors.Count -gt 0) {
    foreach ($failure in $errors) { Write-Host "FAIL: $failure" -ForegroundColor Red }
    Write-Host "History recovery validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Missed restock history recovery contract validation passed.' -ForegroundColor Green
exit 0
