$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$guardPath=Join-Path $ProjectRoot '@Resources\Scripts\FreshnessGuard.lua'
$infoPath=Join-Path $ProjectRoot '@Resources\Includes\OpportunityInfo.inc'
$opportunityPath=Join-Path $ProjectRoot '@Resources\Scripts\OpportunityState.ps1'
$errors=New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($guardPath,$infoPath,$opportunityPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing freshness-guard asset: $path" }
}

if ($errors.Count -eq 0) {
    $guard=Get-Content -LiteralPath $guardPath -Raw
    $info=Get-Content -LiteralPath $infoPath -Raw
    $opportunity=Get-Content -LiteralPath $opportunityPath -Raw

    foreach ($token in @(
        'UIFreshestMarketSourceTimestamp',
        'UIOldestMarketSourceTimestamp',
        'staleAfter=300',
        'hardStaleAfter=21600',
        'retryInterval=15',
        "opportunity-cache.kv",
        'projectionSnapshot',
        'saveOpportunityCache',
        'cachedProjection',
        'restoreCachedProjection',
        "key:match('^Opportunity%d+')",
        "SKIN:Bang('!UpdateMeasure','MeasureState')",
        'hasCachedOpportunities',
        'enterDegradedMode',
        "StockFreshnessMode','degraded'",
        "StockFreshnessMode','hard-stale'",
        "FORECAST ONLY - ",
        "STOCK UNAVAILABLE - ",
        "Foreign stock cache is too old - waiting for a usable Prometheus/YATA snapshot",
        "!HideMeterGroup','OpportunityRow",
        "!CommandMeasure','MeasureUpdate','Run'"
    )) {
        if (-not $guard.Contains($token)) { Fail "FreshnessGuard.lua missing '$token'." }
    }

    if (-not $guard.Contains("local hardStale=(freshestAt<=0) or (freshestAge>hardStaleAfter) or (not hasCachedOpportunities(data))")) {
        Fail 'FreshnessGuard.lua must reserve row hiding for missing/very old evidence or missing cached opportunities.'
    }
    if (-not $guard.Contains("if opportunityCount(data)>0 then saveOpportunityCache(data) end")) {
        Fail 'FreshnessGuard.lua must persist the last non-empty opportunity projection before an outage can clear it.'
    }
    if (-not $guard.Contains("restoreCachedProjection(data)")) {
        Fail 'Degraded mode must restore the persisted opportunity projection when a stale projection becomes empty.'
    }
    if (-not $guard.Contains("if hardStale then")) { Fail 'FreshnessGuard.lua must separate degraded and hard-stale UI states.' }
    if (-not $guard.Contains("SKIN:Bang('!HideMeter','MeterOpportunityMessage')")) { Fail 'Degraded mode must remove the full-panel stale message so forecast cards remain visible.' }
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

    foreach ($token in @(
        '[MeasureFreshnessGuard]',
        'FreshnessGuard.lua',
        'StateFile=#@#Generated\state.kv',
        'HeartbeatFile=#@#Generated\last-update.txt',
        'StaleAfter=300',
        'HardStaleAfter=21600',
        'RetryInterval=15',
        'UpdateDivider=1'
    )) {
        if (-not $info.Contains($token)) { Fail "OpportunityInfo.inc missing freshness-guard token '$token'." }
    }
}

if ($errors.Count -gt 0) {
    foreach ($validationError in $errors) { Write-Host "FAIL: $validationError" -ForegroundColor Red }
    Write-Host "Freshness-guard validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Persistent degraded stock freshness guard validation passed.' -ForegroundColor Green
Write-Host 'Five-minute provider freshness remains strict; 5m-6h evidence is forecast-only with stale stock quantity suppressed, and the last non-empty projection survives outages/skin refreshes.'
exit 0
