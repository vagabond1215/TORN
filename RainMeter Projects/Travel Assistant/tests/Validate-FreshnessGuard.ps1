$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$guardPath=Join-Path $ProjectRoot '@Resources\Scripts\FreshnessGuard.lua'
$infoPath=Join-Path $ProjectRoot '@Resources\Includes\OpportunityInfo.inc'
$opportunityPath=Join-Path $ProjectRoot '@Resources\Scripts\OpportunityState.ps1'
$settingsPath=Join-Path $ProjectRoot 'config\settings.example.json'
$errors=New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($guardPath,$infoPath,$opportunityPath,$settingsPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing freshness-guard asset: $path" }
}

if ($errors.Count -eq 0) {
    $guard=Get-Content -LiteralPath $guardPath -Raw
    $info=Get-Content -LiteralPath $infoPath -Raw
    $opportunity=Get-Content -LiteralPath $opportunityPath -Raw
    $settings=Get-Content -LiteralPath $settingsPath -Raw | ConvertFrom-Json

    foreach ($token in @(
        'UIFreshestMarketSourceTimestamp',
        'UIOldestMarketSourceTimestamp',
        'staleAfter=300',
        'hardStaleAfter=21600',
        'enterDegradedMode',
        "StockFreshnessMode','degraded'",
        "StockFreshnessMode','hard-stale'",
        "FORECAST ONLY - ",
        "STOCK UNAVAILABLE - ",
        "No retained-cycle forecast is available from the stale stock evidence",
        "Foreign stock evidence is over six hours old",
        "!HideMeterGroup','OpportunityRow",
        'Display-only fence',
        'local data=readKv(statePath)',
        'local heartbeat=readEpoch(heartbeatPath)'
    )) {
        if (-not $guard.Contains($token)) { Fail "FreshnessGuard.lua missing '$token'." }
    }

    if (-not $guard.Contains("local hardStale=(freshestAt<=0) or (freshestAge>hardStaleAfter)")) {
        Fail 'FreshnessGuard.lua must reserve the hard stop for missing evidence or evidence older than the configured hard horizon.'
    }
    if (-not $guard.Contains("if opportunityCount(data)>0 then")) {
        Fail 'Degraded mode must keep model-produced forecast rows visible when they exist.'
    }
    foreach ($forbidden in @(
        'writeKvAtomic','opportunity-cache.kv','restoreCachedProjection',"!UpdateMeasure','MeasureState",
        "!CommandMeasure','MeasureUpdate','Run'",'requestRetry','retryInterval','lastRetryAt','PublishedState.lua'
    )) {
        if ($guard.Contains($forbidden)) { Fail "FreshnessGuard.lua must remain direct-read and display-only; found '$forbidden'." }
    }
    if ($guard -match '(?i)https?://|Invoke-RestMethod|curl|RunCommand') { Fail 'FreshnessGuard.lua must remain local-only.' }

    foreach ($token in @(
        'function Get-OpportunityStockEvidenceMode',
        "return 'live'",
        "return 'forecast'",
        "return 'unusable'",
        '$forecastStockMaxAge = 21600L',
        "`$useForecastOnly = (`$stockEvidenceMode -eq 'forecast')",
        "`$stock = if (`$useForecastOnly) { 0L } else { [long](Get-OptimalProperty `$market 'lastStock') }",
        'Get-OpportunityActiveRestockAt -DestinationState $destinationState',
        "-AnchorPhase 'restock'",
        "'OpportunityForecastStockCount'",
        "'stock forecast only'"
    )) {
        if (-not $opportunity.Contains($token)) { Fail "OpportunityState.ps1 missing forecast-only stock contract '$token'." }
    }
    if ($opportunity -match '\$useForecastOnly[^\r\n]*lastStock[^\r\n]*-gt\s*0') {
        Fail 'Forecast-only mode must never promote the stale lastStock quantity back to live stock.'
    }
    if ([long]$settings.staleAfterSeconds -ne 300L) { Fail 'Provider/live-stock presentation threshold must remain five minutes.' }
    if ([long]$settings.forecastOnlyMaxAgeSeconds -ne 21600L) { Fail 'Forecast-only stock evidence horizon must remain six hours unless intentionally revised with this contract.' }

    foreach ($token in @(
        '[MeasureFreshnessGuard]',
        'FreshnessGuard.lua',
        'StateFile=#@#Generated\ui-state.kv',
        'HeartbeatFile=#@#Generated\last-update.txt',
        'StaleAfter=300',
        'HardStaleAfter=21600',
        'UpdateDivider=1'
    )) {
        if (-not $info.Contains($token)) { Fail "OpportunityInfo.inc missing freshness-guard token '$token'." }
    }
    if ($info.Contains('RetryInterval=')) { Fail 'OpportunityInfo.inc must not configure a second freshness-guard updater cadence.' }
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host "FAIL: $validationError" -ForegroundColor Red }
    Write-Host "Freshness-guard validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Forecast-only stock freshness validation passed.' -ForegroundColor Green
Write-Host 'Five-minute provider freshness stays strict; 5m-6h evidence drives recurring forecasts with stale stock quantity suppressed, while the render-time freshness guard reads finalized ui-state.kv directly and never launches the updater.'
exit 0
