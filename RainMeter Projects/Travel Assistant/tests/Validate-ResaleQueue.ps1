$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$queuePath = Join-Path $ProjectRoot '@Resources\Scripts\ResaleQueue.ps1'
$priorityPath = Join-Path $ProjectRoot '@Resources\Scripts\ResalePriority.ps1'
$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

if (-not (Test-Path -LiteralPath $queuePath)) {
    Fail 'Missing ResaleQueue.ps1.'
} else {
    $text = Get-Content -LiteralPath $queuePath -Raw
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($queuePath,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in ResaleQueue.ps1: $($parseError.Message)" }

    foreach ($functionName in @('Ensure-ResaleQueueState','Get-ActiveObservedItems','Get-VisibleResalePriorityIds','Get-ItemAttemptState','Get-ResaleQueueCandidate','Get-ResaleQueueMetrics','Get-LocalApiKey','Invoke-TornItemMarketCurl','Convert-TornItemMarketPrice')) {
        if ($text -notmatch ('(?m)^function\s+'+[regex]::Escape($functionName)+'\s*\{')) { Fail "Missing resale queue function $functionName." }
    }
    if ($text -notmatch '(?m)^\s*\[int\]\$MinimumAttemptIntervalSeconds\s*=\s*60') { Fail 'Resale queue default attempt interval must be 60 seconds.' }
    if ($text -notmatch '(?m)^\s*\[int\]\$CacheFreshSeconds\s*=\s*21600') { Fail 'Broad resale cache default freshness must be six hours.' }
    if ($text -notmatch '(?m)^\s*\[int\]\$FailureBackoffSeconds\s*=\s*3600') { Fail 'General failed items must retain one-hour backoff.' }
    if ($text -notmatch '(?m)^\s*\[int\]\$RequestTimeoutSeconds\s*=\s*6') { Fail 'Broad resale request timeout must be six seconds.' }
    foreach ($token in @('catalogActive','legacy_removed','resaleCache','resaleQueue','attempts','torn_itemmarket','IDLE_FRESH_OR_BACKOFF','PriorityItemIds','pricingPriorityItemIds','average_price')) {
        if (-not $text.Contains($token)) { Fail "Resale queue contract missing '$token'." }
    }
    if (-not $text.Contains('Get-VisibleResalePriorityIds -ItemsConfig $itemsConfig -EngineState $engineState')) { Fail 'Resale queue must merge optimizer MV needs into its priority set.' }
    if ($text -notmatch 'Sort-Object\s+priority,\s*eligibleAt,\s*fetchedAt,\s*lastAttemptAt,\s*itemId') { Fail 'Priority items must sort ahead of broad hidden catalog items.' }
    if (-not $text.Contains('https://api.torn.com/v2/market/{0}/itemmarket?limit=1')) { Fail 'Resale queue must use the specific-item Torn Item Market endpoint.' }
    if (-not $text.Contains("`$psi.Arguments='-q --config -'") -and -not $text.Contains("`$psi.Arguments = '-q --config -'")) { Fail 'Resale queue must pass curl configuration through stdin.' }
    if (-not $text.Contains('Authorization: ApiKey {0}')) { Fail 'Resale queue must use Authorization header.' }
    if ($text -match '(?i)[?&](key|api_key|apikey)=') { Fail 'Resale queue must never put key in URL.' }
    if ($text -match '(?i)Arguments\s*=.*ApiKey') { Fail 'Resale queue must never put key in process arguments.' }
    $marketCalls = [regex]::Matches($text,'(?m)^\s*\$payload\s*=\s*Invoke-TornItemMarketCurl\b').Count
    if ($marketCalls -ne 1) { Fail "Resale queue must contain exactly one production Item Market invocation; found $marketCalls." }
}

if (-not (Test-Path -LiteralPath $priorityPath)) {
    Fail 'Missing ResalePriority.ps1.'
} else {
    $text = Get-Content -LiteralPath $priorityPath -Raw
    $tokens=$null; $parseErrors=$null
    [void][System.Management.Automation.Language.Parser]::ParseFile($priorityPath,[ref]$tokens,[ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in ResalePriority.ps1: $($parseError.Message)" }
    if ($text -notmatch '(?m)^\s*\[int\]\$PriorityBackoffSeconds\s*=\s*300') { Fail 'Optimizer-needed failed items must default to five-minute retry eligibility.' }
    foreach ($token in @('ignoredItemIds','ignored_by_user','315360000','pricingPriorityItemIds','priorityOptimizerItems','pinnedMarket')) {
        if (-not $text.Contains($token)) { Fail "ResalePriority.ps1 missing '$token'." }
    }
    if ($text -match '(?i)https?://|curl\.exe|Invoke-RestMethod|Invoke-WebRequest') { Fail 'ResalePriority.ps1 must remain local-only and never add a second request path.' }
}

if (-not (Test-Path -LiteralPath $wrapperPath)) {
    Fail 'Missing RunUpdate.ps1.'
} else {
    $wrapper = Get-Content -LiteralPath $wrapperPath -Raw
    foreach ($token in @('ResalePriority.ps1','ResaleQueue.ps1','Write-UpdateHeartbeat')) {
        if (-not $wrapper.Contains($token)) { Fail "RunUpdate.ps1 missing $token." }
    }
    $heartbeatCalls=[regex]::Matches($wrapper,'(?m)^\s*Write-UpdateHeartbeat\s*$')
    $priorityCalls=[regex]::Matches($wrapper,'(?m)^\s*if \(Test-Path -LiteralPath \$ResalePriority\) \{ & \$ResalePriority \}\s*$')
    $queueCalls=[regex]::Matches($wrapper,'(?m)^\s*&\s+\$ResaleQueue\s*$')
    if ($heartbeatCalls.Count -ne 1) { Fail "Expected one heartbeat; found $($heartbeatCalls.Count)." }
    if ($priorityCalls.Count -ne 1) { Fail "Expected one local ResalePriority call; found $($priorityCalls.Count)." }
    if ($queueCalls.Count -ne 1) { Fail "Expected one ResaleQueue call; found $($queueCalls.Count)." }
    if ($heartbeatCalls.Count -eq 1 -and $priorityCalls.Count -eq 1 -and $queueCalls.Count -eq 1 -and -not ($heartbeatCalls[0].Index -lt $priorityCalls[0].Index -and $priorityCalls[0].Index -lt $queueCalls[0].Index)) {
        Fail 'Runtime must remain heartbeat -> local ResalePriority -> single ResaleQueue request path.'
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Resale queue validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Resale queue configuration validation passed.' -ForegroundColor Green
Write-Host 'Optimizer MV blockers are prioritized inside the same one-request-per-update queue; ignored items remain parked.'
exit 0
