$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$sourceScript = Join-Path $ProjectRoot '@Resources\Scripts\ResalePriority.ps1'
$tempRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('TornTravelAssistant-ResalePriority-' + [guid]::NewGuid().ToString('N'))

function Assert-Equal {
    param([string]$Name,$Actual,$Expected)
    if ($Actual -ne $Expected) { throw "$Name - expected '$Expected', got '$Actual'." }
    Write-Host "PASS $Name" -ForegroundColor DarkGreen
}
function Assert-True {
    param([string]$Name,[bool]$Condition)
    if (-not $Condition) { throw "$Name - condition was false." }
    Write-Host "PASS $Name" -ForegroundColor DarkGreen
}

try {
    $scriptDir = Join-Path $tempRoot '@Resources\Scripts'
    $configDir = Join-Path $tempRoot 'config'
    $runtimeDir = Join-Path $tempRoot 'data\runtime'
    New-Item -ItemType Directory -Force -Path $scriptDir,$configDir,$runtimeDir | Out-Null
    Copy-Item -LiteralPath $sourceScript -Destination (Join-Path $scriptDir 'ResalePriority.ps1')

    [pscustomobject]@{
        schemaVersion = 1
        items = @(
            [pscustomobject]@{ itemId=206; name='Xanax'; visible=$true },
            [pscustomobject]@{ itemId=266; name='Nessie Plushie'; visible=$true },
            [pscustomobject]@{ itemId=277; name='Cherry Blossom'; visible=$true },
            [pscustomobject]@{ itemId=4; name='Optimizer Hidden Item'; visible=$false },
            [pscustomobject]@{ itemId=5; name='General Hidden Item'; visible=$false }
        )
    } | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $configDir 'items.json') -Encoding UTF8

    $engine = [pscustomobject]@{
        optimizer = [pscustomobject]@{ pricingPriorityItemIds = @(4) }
        resaleQueue = [pscustomobject]@{
            attempts = [pscustomobject]@{
                '266' = [pscustomobject]@{ lastAttemptAt=19600; lastSuccessAt=0; lastErrorAt=19600; attemptCount=1; successCount=0; lastError='timeout' }
                '277' = [pscustomobject]@{ lastAttemptAt=0; lastSuccessAt=0; lastErrorAt=0; attemptCount=0; successCount=0; lastError='' }
                '4'   = [pscustomobject]@{ lastAttemptAt=19600; lastSuccessAt=0; lastErrorAt=19600; attemptCount=1; successCount=0; lastError='timeout' }
                '5'   = [pscustomobject]@{ lastAttemptAt=19600; lastSuccessAt=0; lastErrorAt=19600; attemptCount=1; successCount=0; lastError='timeout' }
            }
        }
    }
    $engine | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath (Join-Path $runtimeDir 'engine-state.json') -Encoding UTF8

    [pscustomobject]@{ schemaVersion=3; pinnedMarket='united_kingdom:266'; ignoredItemIds=@(277) } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runtimeDir 'preferences.json') -Encoding UTF8

    & (Join-Path $scriptDir 'ResalePriority.ps1') -Now 20000 -PriorityBackoffSeconds 300
    $after = Get-Content -LiteralPath (Join-Path $runtimeDir 'engine-state.json') -Raw | ConvertFrom-Json

    Assert-Equal 'Pinned failed item is re-enabled after five-minute priority backoff' ([long]$after.resaleQueue.attempts.'266'.lastAttemptAt) 0
    Assert-Equal 'Optimizer-needed hidden item receives the same bounded retry policy' ([long]$after.resaleQueue.attempts.'4'.lastAttemptAt) 0
    Assert-Equal 'General hidden failed item keeps normal queue backoff state' ([long]$after.resaleQueue.attempts.'5'.lastAttemptAt) 19600
    Assert-Equal 'Ignored item is marked with synthetic queue hold' ([string]$after.resaleQueue.attempts.'277'.lastError) 'ignored_by_user'
    Assert-True 'Ignored item hold is in the future' ([long]$after.resaleQueue.attempts.'277'.lastAttemptAt -gt 20000)
    Assert-Equal 'Priority diagnostics count one ignored item' ([int]$after.resaleQueue.ignoredItems) 1
    Assert-Equal 'Pinned item diagnostic keeps item id' ([int]$after.resaleQueue.pinnedItemId) 266
    Assert-Equal 'Two failed priority items were reset' ([int]$after.resaleQueue.priorityRetryResetCount) 2
    Assert-True 'Priority diagnostics include optimizer and configured priority items' ([int]$after.resaleQueue.priorityOptimizerItems -ge 3)

    [pscustomobject]@{ schemaVersion=3; pinnedMarket='united_kingdom:266'; ignoredItemIds=@() } |
        ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $runtimeDir 'preferences.json') -Encoding UTF8

    & (Join-Path $scriptDir 'ResalePriority.ps1') -Now 20010 -PriorityBackoffSeconds 300
    $unignored = Get-Content -LiteralPath (Join-Path $runtimeDir 'engine-state.json') -Raw | ConvertFrom-Json
    Assert-Equal 'Unignored item synthetic hold clears immediately' ([long]$unignored.resaleQueue.attempts.'277'.lastAttemptAt) 0
    Assert-Equal 'Unignored item synthetic error clears immediately' ([string]$unignored.resaleQueue.attempts.'277'.lastError) ''
    Assert-Equal 'Ignore diagnostic returns to zero' ([int]$unignored.resaleQueue.ignoredItems) 0

    Write-Host 'Resale priority policy tests passed.' -ForegroundColor Green
    exit 0
} finally {
    if (Test-Path -LiteralPath $tempRoot) { Remove-Item -LiteralPath $tempRoot -Recurse -Force -ErrorAction SilentlyContinue }
}
