$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$guardPath=Join-Path $ProjectRoot '@Resources\Scripts\FreshnessGuard.lua'
$infoPath=Join-Path $ProjectRoot '@Resources\Includes\OpportunityInfo.inc'
$errors=New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($guardPath,$infoPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing freshness-guard asset: $path" }
}

if ($errors.Count -eq 0) {
    $guard=Get-Content -LiteralPath $guardPath -Raw
    $info=Get-Content -LiteralPath $infoPath -Raw

    foreach ($token in @(
        'UIFreshestMarketSourceTimestamp',
        'UIOldestMarketSourceTimestamp',
        'staleAfter=300',
        'hardStaleAfter=21600',
        'retryInterval=15',
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

    if (-not $guard.Contains("local hardStale=(sourceAt<=0) or (sourceAge>hardStaleAfter) or (not hasCachedOpportunities(data))")) {
        Fail 'FreshnessGuard.lua must reserve row hiding for missing/very old evidence or missing cached opportunities.'
    }
    if (-not $guard.Contains("if hardStale then")) { Fail 'FreshnessGuard.lua must separate degraded and hard-stale UI states.' }
    if (-not $guard.Contains("SKIN:Bang('!HideMeter','MeterOpportunityMessage')")) { Fail 'Degraded mode must remove the full-panel stale message so cached cards remain visible.' }
    if ($guard -match '(?i)https?://|Invoke-RestMethod|curl|RunCommand') { Fail 'FreshnessGuard.lua must remain local-only.' }

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

Write-Host 'Degraded stock freshness guard validation passed.' -ForegroundColor Green
Write-Host 'Five-minute provider freshness remains strict, but cached opportunity cards stay visible as FORECAST ONLY for up to six hours; only missing/very old evidence enters the hard blank safety state.'
exit 0
