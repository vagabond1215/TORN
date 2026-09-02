param(
    [int]$MinimumAttemptIntervalSeconds = 60,
    [int]$CacheFreshSeconds = 21600,
    [int]$FailureBackoffSeconds = 3600,
    [int]$RequestTimeoutSeconds = 6,
    [switch]$Force,
    [int[]]$CandidateItemIds = @()
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$ErrorFile = Join-Path $RuntimeDir 'resale-queue-error.txt'
New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-JsonAtomic {
    param([string]$Path, [object]$Value, [int]$Depth = 20)
    $tmp = $Path + '.tmp'
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-DynamicProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Set-DynamicProperty {
    param([object]$Object, [string]$Name, [object]$Value)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value }
    else { $property.Value = $Value }
}

function Ensure-ResaleQueueState {
    param([object]$EngineState)
    if (-not $EngineState.PSObject.Properties['resaleCache']) { $EngineState | Add-Member NoteProperty resaleCache ([pscustomobject]@{}) }
    if (-not $EngineState.PSObject.Properties['resaleQueue']) {
        $EngineState | Add-Member NoteProperty resaleQueue ([pscustomobject]@{
            lastRunAt=0; lastAttemptAt=0; lastSuccessAt=0; lastItemId=0
            activeMarkets=0; activeItems=0; pricedItems=0; freshItems=0; staleItems=0; priorityItems=0
            successCount=0; failureCount=0; status='IDLE'; lastErrorAt=0; lastError=''; attempts=[pscustomobject]@{}
        })
    }
    $queue = $EngineState.resaleQueue
    if (-not $queue.PSObject.Properties['attempts']) { $queue | Add-Member NoteProperty attempts ([pscustomobject]@{}) }
    foreach ($name in @('lastRunAt','lastAttemptAt','lastSuccessAt','lastItemId','activeMarkets','activeItems','pricedItems','freshItems','staleItems','priorityItems','successCount','failureCount','lastErrorAt')) {
        if (-not $queue.PSObject.Properties[$name]) { $queue | Add-Member NoteProperty $name 0 }
    }
    foreach ($name in @('status','lastError')) { if (-not $queue.PSObject.Properties[$name]) { $queue | Add-Member NoteProperty $name '' } }
    return $queue
}

function Get-ActiveObservedItems {
    param([object]$ObservedMarkets)
    $ids = New-Object 'System.Collections.Generic.HashSet[int]'
    $activeMarkets = 0
    if ($null -eq $ObservedMarkets) { return [pscustomobject]@{ itemIds=@(); activeMarkets=0 } }
    foreach ($property in @($ObservedMarkets.PSObject.Properties)) {
        $entry = $property.Value
        if ($null -eq $entry) { continue }
        $inactive = $false
        if ($entry.PSObject.Properties['catalogActive'] -and $entry.catalogActive -eq $false) { $inactive = $true }
        if ($entry.PSObject.Properties['catalogStatus'] -and [string]$entry.catalogStatus -eq 'legacy_removed') { $inactive = $true }
        if ($inactive) { continue }
        $itemId = 0
        if ($entry.PSObject.Properties['itemId']) { $itemId = [int]$entry.itemId }
        else {
            $parts = ([string]$property.Name).Split(':')
            if ($parts.Count -gt 1) { [void][int]::TryParse($parts[$parts.Count - 1], [ref]$itemId) }
        }
        if ($itemId -le 0) { continue }
        $activeMarkets++
        [void]$ids.Add($itemId)
    }
    return [pscustomobject]@{ itemIds=@($ids | Sort-Object); activeMarkets=$activeMarkets }
}

function Get-VisibleResalePriorityIds {
    param([object]$ItemsConfig, [object]$EngineState)
    $ids = New-Object 'System.Collections.Generic.HashSet[int]'
    if ($null -ne $ItemsConfig -and $ItemsConfig.PSObject.Properties['items']) {
        foreach ($item in @($ItemsConfig.items)) {
            if ($null -eq $item -or -not $item.PSObject.Properties['itemId']) { continue }
            if (-not $item.PSObject.Properties['visible'] -or $item.visible -ne $true) { continue }
            $itemId = [int]$item.itemId
            if ($itemId -gt 0) { [void]$ids.Add($itemId) }
        }
    }
    if ($null -ne $EngineState -and $EngineState.PSObject.Properties['optimizer']) {
        $optimizer = $EngineState.optimizer
        if ($null -ne $optimizer -and $optimizer.PSObject.Properties['pricingPriorityItemIds']) {
            foreach ($id in @($optimizer.pricingPriorityItemIds)) {
                $itemId = 0
                if ([int]::TryParse([string]$id,[ref]$itemId) -and $itemId -gt 0) { [void]$ids.Add($itemId) }
            }
        }
    }
    return @($ids | Sort-Object)
}

function Get-ItemAttemptState {
    param([object]$QueueState, [int]$ItemId, [switch]$Create)
    $key = [string]$ItemId
    $attempt = Get-DynamicProperty $QueueState.attempts $key
    if ($null -eq $attempt -and $Create) {
        $attempt = [pscustomobject]@{ lastAttemptAt=0; lastSuccessAt=0; lastErrorAt=0; attemptCount=0; successCount=0; lastError='' }
        Set-DynamicProperty $QueueState.attempts $key $attempt
    }
    return $attempt
}

function Get-ResaleQueueCandidate {
    param(
        [object]$EngineState,
        [object]$QueueState,
        [int[]]$ItemIds,
        [int[]]$PriorityItemIds = @(),
        [long]$Now,
        [int]$FreshSeconds,
        [int]$BackoffSeconds
    )
    $prioritySet = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($priorityId in @($PriorityItemIds)) { if ([int]$priorityId -gt 0) { [void]$prioritySet.Add([int]$priorityId) } }
    $eligible = New-Object System.Collections.Generic.List[object]
    foreach ($itemId in @($ItemIds)) {
        $key = [string]$itemId
        $cached = Get-DynamicProperty $EngineState.resaleCache $key
        $price = 0L; $fetchedAt = 0L
        if ($null -ne $cached) {
            if ($cached.PSObject.Properties['price']) { $price = [long]$cached.price }
            if ($cached.PSObject.Properties['fetchedAt']) { $fetchedAt = [long]$cached.fetchedAt }
        }
        if ($price -gt 0 -and $fetchedAt -gt 0 -and ($Now - $fetchedAt) -lt $FreshSeconds) { continue }
        $attempt = Get-ItemAttemptState -QueueState $QueueState -ItemId $itemId
        $lastAttemptAt = 0L
        if ($null -ne $attempt -and $attempt.PSObject.Properties['lastAttemptAt']) { $lastAttemptAt = [long]$attempt.lastAttemptAt }
        $eligibleAt = 0L
        if ($price -gt 0 -and $fetchedAt -gt 0) { $eligibleAt = $fetchedAt + $FreshSeconds }
        if ($lastAttemptAt -gt 0) {
            $attemptEligibleAt = $lastAttemptAt + $BackoffSeconds
            if ($attemptEligibleAt -gt $eligibleAt) { $eligibleAt = $attemptEligibleAt }
        }
        if ($eligibleAt -gt $Now) { continue }
        $priority = 1
        if ($prioritySet.Contains([int]$itemId)) { $priority = 0 }
        $eligible.Add([pscustomobject]@{ itemId=[int]$itemId; priority=$priority; eligibleAt=[long]$eligibleAt; fetchedAt=[long]$fetchedAt; lastAttemptAt=[long]$lastAttemptAt })
    }
    if ($eligible.Count -eq 0) { return $null }
    return @($eligible | Sort-Object priority,eligibleAt,fetchedAt,lastAttemptAt,itemId | Select-Object -First 1)[0]
}

function Get-ResaleQueueMetrics {
    param([object]$EngineState, [int[]]$ItemIds, [long]$Now, [int]$FreshSeconds)
    $priced = 0; $fresh = 0
    foreach ($itemId in @($ItemIds)) {
        $cached = Get-DynamicProperty $EngineState.resaleCache ([string]$itemId)
        if ($null -eq $cached) { continue }
        $price = 0L; $fetchedAt = 0L
        if ($cached.PSObject.Properties['price']) { $price = [long]$cached.price }
        if ($cached.PSObject.Properties['fetchedAt']) { $fetchedAt = [long]$cached.fetchedAt }
        if ($price -gt 0) { $priced++ }
        if ($price -gt 0 -and $fetchedAt -gt 0 -and ($Now - $fetchedAt) -lt $FreshSeconds) { $fresh++ }
    }
    return [pscustomobject]@{ pricedItems=$priced; freshItems=$fresh; staleItems=[Math]::Max(0,$ItemIds.Count-$fresh) }
}

function Get-LocalApiKey {
    $local = Read-JsonFile (Join-Path $ConfigDir 'settings.local.json')
    if ($null -ne $local -and $local.PSObject.Properties['tornApiKey'] -and -not [string]::IsNullOrWhiteSpace([string]$local.tornApiKey)) { return [string]$local.tornApiKey }
    if (-not [string]::IsNullOrWhiteSpace($env:TORN_API_KEY)) { return [string]$env:TORN_API_KEY }
    return ''
}

function Invoke-TornItemMarketCurl {
    param([Parameter(Mandatory=$true)][int]$ItemId,[Parameter(Mandatory=$true)][string]$ApiKey,[int]$TimeoutSec=6)
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -eq $curl) { throw 'curl.exe is required for the resale queue on this Windows environment.' }
    if ($TimeoutSec -lt 2) { $TimeoutSec=2 }; if ($TimeoutSec -gt 10) { $TimeoutSec=10 }
    $uri = 'https://api.torn.com/v2/market/{0}/itemmarket?limit=1' -f $ItemId
    $connectTimeout = [Math]::Min(3,$TimeoutSec)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName=$curl.Source; $psi.Arguments='-q --config -'; $psi.UseShellExecute=$false; $psi.CreateNoWindow=$true
    $psi.RedirectStandardInput=$true; $psi.RedirectStandardOutput=$true; $psi.RedirectStandardError=$true
    $process = New-Object System.Diagnostics.Process; $process.StartInfo=$psi
    try {
        if (-not $process.Start()) { throw 'Failed to start curl.exe.' }
        $process.StandardInput.WriteLine('silent'); $process.StandardInput.WriteLine('show-error'); $process.StandardInput.WriteLine('fail')
        $process.StandardInput.WriteLine(('connect-timeout = {0}' -f $connectTimeout)); $process.StandardInput.WriteLine(('max-time = {0}' -f $TimeoutSec))
        $process.StandardInput.WriteLine(('url = "{0}"' -f $uri)); $process.StandardInput.WriteLine('header = "Accept: application/json"')
        $process.StandardInput.WriteLine(('header = "Authorization: ApiKey {0}"' -f $ApiKey.Replace('"','')))
        $process.StandardInput.WriteLine('header = "User-Agent: TornTravelAssistant/0.5"'); $process.StandardInput.Close()
        $waitMs=[Math]::Max(3000,($TimeoutSec+2)*1000)
        if (-not $process.WaitForExit($waitMs)) { try{$process.Kill()}catch{}; throw ('curl.exe exceeded the {0}s Torn Item Market timeout.' -f $TimeoutSec) }
        $stdout=$process.StandardOutput.ReadToEnd(); $stderr=$process.StandardError.ReadToEnd()
        if ($process.ExitCode -ne 0) { if([string]::IsNullOrWhiteSpace($stderr)){$stderr='curl.exe returned a non-zero exit code.'}; throw ('Torn Item Market request failed: {0}' -f $stderr.Trim()) }
        if ([string]::IsNullOrWhiteSpace($stdout)) { throw 'Torn Item Market request returned an empty response.' }
        return ($stdout | ConvertFrom-Json)
    } finally { $process.Dispose() }
}

function Convert-TornItemMarketPrice {
    param([object]$Payload,[int]$ItemId,[long]$FetchedAt)
    if ($null -eq $Payload -or -not $Payload.PSObject.Properties['itemmarket']) { return $null }
    $average=0L; $lowest=0L
    if ($Payload.itemmarket -and $Payload.itemmarket.PSObject.Properties['item'] -and $Payload.itemmarket.item -and $Payload.itemmarket.item.PSObject.Properties['average_price']) { $average=[long]$Payload.itemmarket.item.average_price }
    if ($Payload.itemmarket -and $Payload.itemmarket.PSObject.Properties['listings'] -and @($Payload.itemmarket.listings).Count -gt 0) {
        $candidate=@($Payload.itemmarket.listings)[0]
        if ($null -ne $candidate -and $candidate.PSObject.Properties['price']) { $lowest=[long]$candidate.price }
    }
    $price=$lowest; if($price -le 0){$price=$average}; if($price -le 0){return $null}
    return [pscustomobject]@{ itemId=[int]$ItemId; price=[long]$price; lowest=[long]$lowest; average=[long]$average; fetchedAt=[long]$FetchedAt; source='torn_itemmarket' }
}

function Set-QueueErrorFile {
    param([string]$Message)
    $clean=([string]$Message).Replace("`r",' ').Replace("`n",' ').Trim(); if($clean.Length -gt 600){$clean=$clean.Substring(0,600)}
    [System.IO.File]::WriteAllText($ErrorFile,$clean,[System.Text.UTF8Encoding]::new($false))
}

if ($MinimumAttemptIntervalSeconds -lt 60) { $MinimumAttemptIntervalSeconds=60 }
if ($CacheFreshSeconds -lt 3600) { $CacheFreshSeconds=3600 }
if ($FailureBackoffSeconds -lt 300) { $FailureBackoffSeconds=300 }
if ($RequestTimeoutSeconds -lt 2) { $RequestTimeoutSeconds=2 }; if ($RequestTimeoutSeconds -gt 10) { $RequestTimeoutSeconds=10 }

$engineState=Read-JsonFile $EngineStateFile
if ($null -eq $engineState -or -not $engineState.PSObject.Properties['observedMarkets']) { return }
$queue=Ensure-ResaleQueueState -EngineState $engineState
$now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
if (-not $Force -and [long]$queue.lastRunAt -gt 0 -and ($now-[long]$queue.lastRunAt) -lt $MinimumAttemptIntervalSeconds) { return }
$queue.lastRunAt=$now

$active=Get-ActiveObservedItems -ObservedMarkets $engineState.observedMarkets
$itemIds=[int[]]@($active.itemIds)
$queue.activeMarkets=[int]$active.activeMarkets
$queue.activeItems=$itemIds.Count
$metrics=Get-ResaleQueueMetrics -EngineState $engineState -ItemIds $itemIds -Now $now -FreshSeconds $CacheFreshSeconds
$queue.pricedItems=[int]$metrics.pricedItems; $queue.freshItems=[int]$metrics.freshItems; $queue.staleItems=[int]$metrics.staleItems
if ($itemIds.Count -eq 0) { $queue.status='NO_ACTIVE_ITEMS'; $queue.lastError=''; Write-JsonAtomic -Path $EngineStateFile -Value $engineState; return }

$candidatePool=[int[]]@($itemIds)
if (@($CandidateItemIds).Count -gt 0) {
    $requested = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach($candidateId in @($CandidateItemIds)) {
        if([int]$candidateId -gt 0) { [void]$requested.Add([int]$candidateId) }
    }
    $candidatePool=[int[]]@($itemIds | Where-Object { $requested.Contains([int]$_) })
    if($candidatePool.Count -eq 0) {
        $queue.status='NO_MATCHING_CANDIDATES'
        $queue.lastError=''
        Write-JsonAtomic -Path $EngineStateFile -Value $engineState
        return
    }
}

$apiKey=Get-LocalApiKey
if ([string]::IsNullOrWhiteSpace($apiKey)) { $queue.status='NO_API_KEY'; $queue.lastError=''; Write-JsonAtomic -Path $EngineStateFile -Value $engineState; return }
$itemsConfig=Read-JsonFile (Join-Path $ConfigDir 'items.json')
$priorityItemIds=[int[]]@(Get-VisibleResalePriorityIds -ItemsConfig $itemsConfig -EngineState $engineState)
$queue.priorityItems=$priorityItemIds.Count
$candidate=Get-ResaleQueueCandidate -EngineState $engineState -QueueState $queue -ItemIds $candidatePool -PriorityItemIds $priorityItemIds -Now $now -FreshSeconds $CacheFreshSeconds -BackoffSeconds $FailureBackoffSeconds
if ($null -eq $candidate) { $queue.status='IDLE_FRESH_OR_BACKOFF'; $queue.lastError=''; Write-JsonAtomic -Path $EngineStateFile -Value $engineState; return }

$itemId=[int]$candidate.itemId
$attempt=Get-ItemAttemptState -QueueState $queue -ItemId $itemId -Create
$attempt.lastAttemptAt=$now; $attempt.attemptCount=[int]$attempt.attemptCount+1; $queue.lastAttemptAt=$now; $queue.lastItemId=$itemId
try {
    $payload=Invoke-TornItemMarketCurl -ItemId $itemId -ApiKey $apiKey -TimeoutSec $RequestTimeoutSeconds
    $result=Convert-TornItemMarketPrice -Payload $payload -ItemId $itemId -FetchedAt $now
    if ($null -eq $result) { throw 'Torn Item Market response did not contain a usable price.' }
    Set-DynamicProperty $engineState.resaleCache ([string]$itemId) ([pscustomobject]@{ price=[long]$result.price; lowest=[long]$result.lowest; average=[long]$result.average; fetchedAt=[long]$result.fetchedAt; source=[string]$result.source })
    $attempt.lastSuccessAt=$now; $attempt.successCount=[int]$attempt.successCount+1; $attempt.lastErrorAt=0; $attempt.lastError=''
    $queue.lastSuccessAt=$now; $queue.successCount=[int]$queue.successCount+1; $queue.status='OK'; $queue.lastErrorAt=0; $queue.lastError=''
    if(Test-Path -LiteralPath $ErrorFile){Remove-Item -LiteralPath $ErrorFile -Force -ErrorAction SilentlyContinue}
} catch {
    $clean=([string]$_.Exception.Message).Replace("`r",' ').Replace("`n",' ').Trim(); if($clean.Length -gt 600){$clean=$clean.Substring(0,600)}
    $attempt.lastErrorAt=$now; $attempt.lastError=$clean; $queue.failureCount=[int]$queue.failureCount+1; $queue.status='ERROR'; $queue.lastErrorAt=$now; $queue.lastError=$clean
    try{Set-QueueErrorFile -Message $clean}catch{}
}
$metrics=Get-ResaleQueueMetrics -EngineState $engineState -ItemIds $itemIds -Now $now -FreshSeconds $CacheFreshSeconds
$queue.pricedItems=[int]$metrics.pricedItems; $queue.freshItems=[int]$metrics.freshItems; $queue.staleItems=[int]$metrics.staleItems
Write-JsonAtomic -Path $EngineStateFile -Value $engineState
