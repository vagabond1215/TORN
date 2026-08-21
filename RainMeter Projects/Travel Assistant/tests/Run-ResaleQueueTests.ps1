$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ScriptPath = Join-Path $ProjectRoot '@Resources\Scripts\ResaleQueue.ps1'

function Assert-Equal {
    param([string]$Name, $Actual, $Expected)
    if ($Actual -ne $Expected) { throw "$Name - expected '$Expected', got '$Actual'." }
    Write-Host "PASS $Name" -ForegroundColor DarkGreen
}
function Assert-True {
    param([string]$Name, [bool]$Value)
    if (-not $Value) { throw "$Name - expected true." }
    Write-Host "PASS $Name" -ForegroundColor DarkGreen
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$parseErrors)
if (@($parseErrors).Count -gt 0) { throw ('ResaleQueue.ps1 has parser errors: ' + ((@($parseErrors) | ForEach-Object { $_.Message }) -join '; ')) }

$wanted = @('Get-DynamicProperty','Set-DynamicProperty','Ensure-ResaleQueueState','Get-ActiveObservedItems','Get-VisibleResalePriorityIds','Get-ItemAttemptState','Get-ResaleQueueCandidate','Get-ResaleQueueMetrics','Convert-TornItemMarketPrice')
$definitions = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $node.Name
}, $true))
foreach ($name in $wanted) {
    $definition = @($definitions | Where-Object { $_.Name -eq $name } | Select-Object -First 1)
    if ($definition.Count -ne 1) { throw "Could not locate production function '$name'." }
    $source = [string]$definition[0].Extent.Text
    $scoped = $source -replace ('^function\s+' + [regex]::Escape($name)), ('function script:' + $name)
    Invoke-Expression $scoped
}

$observed = [pscustomobject]@{
    'united_kingdom:266' = [pscustomobject]@{ country='united_kingdom'; itemId=266; catalogActive=$true }
    'japan:266' = [pscustomobject]@{ country='japan'; itemId=266; catalogActive=$true }
    'japan:206' = [pscustomobject]@{ country='japan'; itemId=206; catalogActive=$true }
    'mexico:999' = [pscustomobject]@{ country='mexico'; itemId=999 }
    'mexico:21' = [pscustomobject]@{ country='mexico'; itemId=21; catalogActive=$false; catalogStatus='legacy_removed' }
    'united_arab_emirates:440' = [pscustomobject]@{ country='united_arab_emirates'; itemId=440; catalogStatus='legacy_removed' }
}

$active = Get-ActiveObservedItems -ObservedMarkets $observed
Assert-Equal 'Active-market scan counts only eligible country-item rows' ([int]$active.activeMarkets) 4
Assert-Equal 'Active-market scan collapses duplicate item IDs' @($active.itemIds).Count 3
Assert-True 'Active items include Xanax' (@($active.itemIds) -contains 206)
Assert-True 'Active items include Nessie' (@($active.itemIds) -contains 266)
Assert-True 'Active items include unseeded active item' (@($active.itemIds) -contains 999)
Assert-Equal 'catalogActive false item is excluded' (@($active.itemIds) -contains 21) $false
Assert-Equal 'legacy status item is excluded defensively' (@($active.itemIds) -contains 440) $false

$priorityFixture = [pscustomobject]@{ items = @(
    [pscustomobject]@{ itemId=206; visible=$true },
    [pscustomobject]@{ itemId=266; visible=$true },
    [pscustomobject]@{ itemId=999; visible=$false }
) }
$priorityIds = [int[]]@(Get-VisibleResalePriorityIds -ItemsConfig $priorityFixture)
Assert-Equal 'Visible priority list contains two items' $priorityIds.Count 2
Assert-True 'Visible priority includes Nessie' ($priorityIds -contains 266)
Assert-Equal 'Hidden item is not prioritized' ($priorityIds -contains 999) $false

$engine = [pscustomobject]@{
    observedMarkets = $observed
    resaleCache = [pscustomobject]@{
        '206' = [pscustomobject]@{ price=800000; lowest=800000; average=810000; fetchedAt=19500; source='torn_itemmarket' }
        '266' = [pscustomobject]@{ price=25000; lowest=25000; average=26000; fetchedAt=1000; source='torn_itemmarket' }
    }
}
$queue = Ensure-ResaleQueueState -EngineState $engine
Assert-True 'Queue state creates attempt table' ($null -ne $queue.attempts)
Assert-Equal 'Queue state starts with zero successes' ([int]$queue.successCount) 0

$now = 20000L
$freshSeconds = 4000
$backoffSeconds = 1000

$attempt999 = Get-ItemAttemptState -QueueState $queue -ItemId 999 -Create
$attempt999.lastAttemptAt = 19500
$candidate = Get-ResaleQueueCandidate -EngineState $engine -QueueState $queue -ItemIds ([int[]]@($active.itemIds)) -PriorityItemIds $priorityIds -Now $now -FreshSeconds $freshSeconds -BackoffSeconds $backoffSeconds
Assert-Equal 'Fresh cache and recent failure backoff leave stale visible Nessie next' ([int]$candidate.itemId) 266

$attempt999.lastAttemptAt = 0
$candidate = Get-ResaleQueueCandidate -EngineState $engine -QueueState $queue -ItemIds ([int[]]@($active.itemIds)) -PriorityItemIds $priorityIds -Now $now -FreshSeconds $freshSeconds -BackoffSeconds $backoffSeconds
Assert-Equal 'Visible stale item is prioritized over never-priced hidden catalog item' ([int]$candidate.itemId) 266

$candidateNoPriority = Get-ResaleQueueCandidate -EngineState $engine -QueueState $queue -ItemIds ([int[]]@($active.itemIds)) -PriorityItemIds ([int[]]@()) -Now $now -FreshSeconds $freshSeconds -BackoffSeconds $backoffSeconds
Assert-Equal 'Without visible priority never-priced item remains normal first choice' ([int]$candidateNoPriority.itemId) 999

$metrics = Get-ResaleQueueMetrics -EngineState $engine -ItemIds ([int[]]@($active.itemIds)) -Now $now -FreshSeconds $freshSeconds
Assert-Equal 'Two active items have a resale price' ([int]$metrics.pricedItems) 2
Assert-Equal 'Only Xanax cache is fresh in fixture' ([int]$metrics.freshItems) 1
Assert-Equal 'Two active items are stale or unpriced' ([int]$metrics.staleItems) 2

$payload = [pscustomobject]@{
    itemmarket = [pscustomobject]@{
        item = [pscustomobject]@{ average_price = 27000 }
        listings = @([pscustomobject]@{ price = 25000 })
    }
}
$parsed = Convert-TornItemMarketPrice -Payload $payload -ItemId 266 -FetchedAt 20000
Assert-Equal 'Item Market parser prefers lowest listing' ([long]$parsed.price) 25000
Assert-Equal 'Item Market parser keeps average reference' ([long]$parsed.average) 27000
Assert-Equal 'Item Market parser keeps item identity' ([int]$parsed.itemId) 266
Assert-Equal 'Item Market parser keeps source provenance' ([string]$parsed.source) 'torn_itemmarket'

$averageOnlyPayload = [pscustomobject]@{
    itemmarket = [pscustomobject]@{
        item = [pscustomobject]@{ average_price = 32000 }
        listings = @()
    }
}
$averageOnly = Convert-TornItemMarketPrice -Payload $averageOnlyPayload -ItemId 999 -FetchedAt 20000
Assert-Equal 'Item Market parser falls back to average when no listing exists' ([long]$averageOnly.price) 32000

$emptyPayload = [pscustomobject]@{
    itemmarket = [pscustomobject]@{
        item = [pscustomobject]@{ average_price = 0 }
        listings = @()
    }
}
Assert-Equal 'Zero-price response remains unresolved rather than zero economics' ($null -eq (Convert-TornItemMarketPrice -Payload $emptyPayload -ItemId 999 -FetchedAt 20000)) $true

Write-Host 'Resale queue selection/normalization tests passed.' -ForegroundColor Green
exit 0
