$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$queuePath = Join-Path $ProjectRoot '@Resources\Scripts\ResaleQueue.ps1'
$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

if (-not (Test-Path -LiteralPath $queuePath)) {
    Fail 'Missing @Resources\Scripts\ResaleQueue.ps1.'
} else {
    $text = Get-Content -LiteralPath $queuePath -Raw
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($queuePath, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in ResaleQueue.ps1: $($parseError.Message)" }

    foreach ($functionName in @('Ensure-ResaleQueueState','Get-ActiveObservedItems','Get-ItemAttemptState','Get-ResaleQueueCandidate','Get-ResaleQueueMetrics','Get-LocalApiKey','Invoke-TornItemMarketCurl','Convert-TornItemMarketPrice')) {
        if ($text -notmatch ('(?m)^function\s+' + [regex]::Escape($functionName) + '\s*\{')) { Fail "Missing resale queue function $functionName." }
    }

    if ($text -notmatch '(?m)^\s*\[int\]\$MinimumAttemptIntervalSeconds\s*=\s*60') { Fail 'Resale queue default attempt interval must be 60 seconds.' }
    if ($text -notmatch '(?m)^\s*\[int\]\$CacheFreshSeconds\s*=\s*21600') { Fail 'Broad resale cache default freshness must be 21600 seconds (6 hours).' }
    if ($text -notmatch '(?m)^\s*\[int\]\$FailureBackoffSeconds\s*=\s*3600') { Fail 'Failed resale items must default to a one-hour backoff.' }
    if ($text -notmatch '(?m)^\s*\[int\]\$RequestTimeoutSeconds\s*=\s*6') { Fail 'Broad resale request default timeout must be six seconds.' }

    foreach ($token in @('catalogActive','legacy_removed','resaleCache','resaleQueue','attempts','torn_itemmarket','IDLE_FRESH_OR_BACKOFF')) {
        if (-not $text.Contains($token)) { Fail "Resale queue contract is missing '$token'." }
    }

    if (-not $text.Contains('https://api.torn.com/v2/market/{0}/itemmarket?limit=1')) { Fail 'Resale queue must use the established specific-item Torn Item Market endpoint.' }
    if (-not $text.Contains("`$psi.Arguments = '-q --config -'")) { Fail 'Resale queue must pass curl configuration through stdin.' }
    if (-not $text.Contains('Authorization: ApiKey {0}')) { Fail 'Resale queue must send the Torn key through the Authorization header.' }
    if ($text -match '(?i)[?&](key|api_key|apikey)=') { Fail 'Resale queue must never put the Torn API key in a request URL.' }
    if ($text -match '(?i)Arguments\s*=.*ApiKey') { Fail 'Resale queue must never put the Torn API key in process arguments.' }

    $marketCalls = [regex]::Matches($text, '(?m)^\s*\$payload\s*=\s*Invoke-TornItemMarketCurl\b').Count
    if ($marketCalls -ne 1) { Fail "Resale queue must contain exactly one production Item Market invocation per run path; found $marketCalls." }
}

if (-not (Test-Path -LiteralPath $wrapperPath)) {
    Fail 'Missing RunUpdate.ps1.'
} else {
    $wrapper = Get-Content -LiteralPath $wrapperPath -Raw
    foreach ($token in @('ResaleQueue.ps1','Write-ResaleQueueFailure','Write-UpdateHeartbeat')) {
        if (-not $wrapper.Contains($token)) { Fail "RunUpdate.ps1 is missing $token." }
    }
    if (-not $wrapper.Contains("`$Action -eq 'Update'")) { Fail 'Broad resale queue must not run for CycleTravelMode actions.' }

    $heartbeatIndex = $wrapper.IndexOf('Write-UpdateHeartbeat')
    $queueCallIndex = $wrapper.IndexOf('& $ResaleQueue')
    if ($heartbeatIndex -lt 0 -or $queueCallIndex -lt 0 -or $heartbeatIndex -gt $queueCallIndex) {
        Fail 'Visible heartbeat must be written before the broad resale queue runs.'
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Resale queue validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Resale queue configuration validation passed.' -ForegroundColor Green
Write-Host 'Active observed items are priced one bounded Torn request at a time after the visible heartbeat; legacy markets are excluded.'
exit 0
