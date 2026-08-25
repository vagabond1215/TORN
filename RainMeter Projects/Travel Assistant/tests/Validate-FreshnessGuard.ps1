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
        'retryInterval=15',
        "Foreign stock is stale - waiting for a fresh Prometheus/YATA snapshot",
        "STOCK STALE - ",
        "!HideMeterGroup','OpportunityRow",
        "!CommandMeasure','MeasureUpdate','Run'"
    )) {
        if (-not $guard.Contains($token)) { Fail "FreshnessGuard.lua missing '$token'." }
    }
    if ($guard -match '(?i)https?://|Invoke-RestMethod|curl|RunCommand') { Fail 'FreshnessGuard.lua must remain local-only.' }

    foreach ($token in @(
        '[MeasureFreshnessGuard]',
        'FreshnessGuard.lua',
        'StateFile=#@#Generated\state.kv',
        'HeartbeatFile=#@#Generated\last-update.txt',
        'StaleAfter=300',
        'RetryInterval=15',
        'UpdateDivider=1'
    )) {
        if (-not $info.Contains($token)) { Fail "OpportunityInfo.inc missing freshness-guard token '$token'." }
    }
}

if ($errors.Count -gt 0) {
    foreach ($error in $errors) { Write-Host "FAIL: $error" -ForegroundColor Red }
    Write-Host "Freshness-guard validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Render-time stock freshness guard validation passed.' -ForegroundColor Green
Write-Host 'Provider evidence older than five minutes hides actionable cards and retries every 15 seconds while the UI heartbeat remains separately visible.'
exit 0
