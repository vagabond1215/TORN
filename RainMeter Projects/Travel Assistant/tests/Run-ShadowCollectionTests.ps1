$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$CollectorPath = Join-Path $ProjectRoot '@Resources\Scripts\ShadowCollector.ps1'
. (Join-Path $ProjectRoot '@Resources\Scripts\CycleForecastFilter.ps1')
. (Join-Path $ProjectRoot '@Resources\Scripts\AtomicFile.ps1')

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
$ast = [System.Management.Automation.Language.Parser]::ParseFile($CollectorPath, [ref]$tokens, [ref]$parseErrors)
if (@($parseErrors).Count -gt 0) {
    throw ('ShadowCollector.ps1 has parser errors: ' + ((@($parseErrors) | ForEach-Object { $_.Message }) -join '; '))
}

$wanted = @('Get-DynamicProperty','Set-DynamicProperty','Get-CountryProviderCode','Get-LiveStockObservationsForCountry','Write-SharedAppendBytes','Append-JsonLine','Flush-PendingJsonLines','Invalidate-PhaseAnchorForGap','Test-ForecastBoundaryQuality','Update-CycleState','Get-InactiveMarketIndex','Test-ObservationChanged','Update-ObservedMarketMetadata')
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
$script:blockedAppendPaths=@{}

$payload = [pscustomobject]@{
    stocks = [pscustomobject]@{
        uni = [pscustomobject]@{
            update = 1787327048
            stocks = @(
                [pscustomobject]@{ id = 206; name = 'Xanax'; quantity = 123; cost = 767000 },
                [pscustomobject]@{ id = 266; name = 'Nessie Plushie'; quantity = 450; cost = 200 },
                [pscustomobject]@{ id = 268; name = 'Red Fox Plushie'; quantity = 20; cost = 1000 },
                [pscustomobject]@{ id = 999; name = 'Malformed'; quantity = 1 }
            )
        }
    }
}
$country = [pscustomobject]@{
    id = 'united_kingdom'
    providerCodes = [pscustomobject]@{ prometheus = 'uni'; yata = 'uni' }
}

$rows = @(Get-LiveStockObservationsForCountry -Payload $payload -Country $country -Now 1787327100 -Source 'prometheus')
Assert-Equal 'All valid provider rows normalize' $rows.Count 3
Assert-Equal 'Shadow normalization keeps country' ([string]$rows[1].country) 'united_kingdom'
Assert-Equal 'Shadow normalization keeps item id' ([int]$rows[1].itemId) 266
Assert-Equal 'Shadow normalization keeps provider item name' ([string]$rows[1].itemName) 'Nessie Plushie'
Assert-Equal 'Shadow normalization keeps stock' ([int]$rows[1].stock) 450
Assert-Equal 'Shadow normalization keeps foreign price' ([long]$rows[1].foreignPrice) 200
Assert-Equal 'Shadow normalization keeps provider timestamp' ([long]$rows[1].sourceTimestamp) 1787327048

$catalogState = [pscustomobject]@{ observedMarkets = [pscustomobject]@{} }
Update-ObservedMarketMetadata -EngineState $catalogState -Observation $rows[1] -Now 1787327100
$catalogEntry = $catalogState.observedMarkets.PSObject.Properties['united_kingdom:266'].Value
Assert-Equal 'Observed market stores provider item name' ([string]$catalogEntry.providerName) 'Nessie Plushie'

$renamedObservation = [pscustomobject]@{
    country = 'united_kingdom'
    itemId = 266
    itemName = 'Nessie Plushie'
    stock = 400
    foreignPrice = 200
    source = 'yata'
    sourceTimestamp = 1787327200
}
Update-ObservedMarketMetadata -EngineState $catalogState -Observation $renamedObservation -Now 1787327200
Assert-Equal 'Observed market keeps provider name across refresh' ([string]$catalogEntry.providerName) 'Nessie Plushie'
Assert-Equal 'Observed market refresh still updates stock' ([int]$catalogEntry.lastStock) 400

$appendPath=Join-Path ([System.IO.Path]::GetTempPath()) ('travel-shadow-append-'+[guid]::NewGuid().ToString('N')+'.jsonl')
$readStream=$null
try {
    [System.IO.File]::WriteAllText($appendPath,'',[System.Text.UTF8Encoding]::new($false))
    $share=[System.IO.FileShare]([int][System.IO.FileShare]::ReadWrite -bor [int][System.IO.FileShare]::Delete)
    $readStream=[System.IO.File]::Open($appendPath,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,$share)
    Append-JsonLine -Path $appendPath -Value ([pscustomobject]@{stock=1;source='test'})
    Assert-Equal 'Transition append tolerates a shared runtime reader' (@([System.IO.File]::ReadAllLines($appendPath)).Count) 1
} finally {
    if($null -ne $readStream){$readStream.Dispose()}
    Remove-Item -LiteralPath $appendPath -Force -ErrorAction SilentlyContinue
}

$lockedPath=Join-Path ([System.IO.Path]::GetTempPath()) ('travel-shadow-locked-'+[guid]::NewGuid().ToString('N')+'.jsonl')
$pendingPath=$lockedPath+'.pending'
$exclusiveReader=$null
try {
    [System.IO.File]::WriteAllText($lockedPath,'',[System.Text.UTF8Encoding]::new($false))
    $exclusiveReader=[System.IO.File]::Open($lockedPath,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::Read)
    Append-JsonLine -Path $lockedPath -FallbackPath $pendingPath -Value ([pscustomobject]@{stock=2;source='pending-test'})
    Assert-Equal 'Locked canonical history falls back to pending journal' (@([System.IO.File]::ReadAllLines($pendingPath)).Count) 1
    $exclusiveReader.Dispose();$exclusiveReader=$null
    $script:blockedAppendPaths=@{}
    Assert-True 'Pending journal flushes after canonical lock clears' (Flush-PendingJsonLines -Path $lockedPath -PendingPath $pendingPath)
    Assert-Equal 'Flushed transition reaches canonical history' (@([System.IO.File]::ReadAllLines($lockedPath)).Count) 1
    Assert-Equal 'Successful flush removes pending journal' (Test-Path -LiteralPath $pendingPath) $false
} finally {
    if($null -ne $exclusiveReader){$exclusiveReader.Dispose()}
    Remove-Item -LiteralPath $lockedPath -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $pendingPath -Force -ErrorAction SilentlyContinue
}

$overrideFixture = [pscustomobject]@{
    marketOverrides = [pscustomobject]@{
        'mexico:21' = [pscustomobject]@{ active=$false; status='legacy_removed' }
        'mexico:232' = [pscustomobject]@{ active=$false; status='legacy_removed' }
        'japan:277' = [pscustomobject]@{ active=$true; status='verified_active' }
    }
}
$inactiveMarkets = Get-InactiveMarketIndex -OverrideConfig $overrideFixture
Assert-Equal 'Inactive market index keeps only inactive rows' $inactiveMarkets.Count 2
Assert-True 'Legacy Dual Berettas market is suppressed' $inactiveMarkets.ContainsKey('mexico:21')
Assert-True 'Legacy SIG 550 market is suppressed' $inactiveMarkets.ContainsKey('mexico:232')
Assert-Equal 'Active market is not suppressed' $inactiveMarkets.ContainsKey('japan:277') $false

$unchangedState = [pscustomobject]@{
    lastStock = 450
    lastForeignPrice = 200
    lastSourceTimestamp = 100
    lastSellOutAt = 0
    activeCycle = $null
}
$timestampOnlyRefresh = [pscustomobject]@{
    stock = 450
    foreignPrice = 200
    sourceTimestamp = 200
}
Assert-Equal 'Provider timestamp alone does not create raw history' (Test-ObservationChanged -DestState $unchangedState -Observation $timestampOnlyRefresh) $false
$stockChange = [pscustomobject]@{ stock = 449; foreignPrice = 200; sourceTimestamp = 200 }
Assert-True 'Stock change creates raw history' (Test-ObservationChanged -DestState $unchangedState -Observation $stockChange)
$priceChange = [pscustomobject]@{ stock = 450; foreignPrice = 250; sourceTimestamp = 200 }
Assert-Equal 'Foreign-price-only change stays in observed market state' (Test-ObservationChanged -DestState $unchangedState -Observation $priceChange) $false

$destState = [pscustomobject]@{
    lastStock = 0
    lastForeignPrice = 200
    lastSourceTimestamp = 100
    lastSellOutAt = 100
    lastSellOutLowerBoundAt = 90
    lastSellOutUpperBoundAt = 100
    lastSellOutBoundaryQuality = 'bounded'
    continuityInvalidatedAt = 0
    activeCycle = $null
}
$restockObservation = [pscustomobject]@{
    timestamp = 200
    country = 'united_kingdom'
    itemId = 266
    stock = 450
    foreignPrice = 200
    source = 'prometheus'
    sourceTimestamp = 200
}
$null = Update-CycleState -DestState $destState -Observation $restockObservation
Assert-Equal 'Shadow cycle records restock transition' ([long]$destState.activeCycle.restockAt) 200
Assert-Equal 'Restock lower bound uses last observed OOS point' ([long]$destState.activeCycle.restockLowerBoundAt) 100

$positiveObservation = [pscustomobject]@{
    timestamp = 230
    country = 'united_kingdom'
    itemId = 266
    stock = 400
    foreignPrice = 200
    source = 'prometheus'
    sourceTimestamp = 230
}
$null = Update-CycleState -DestState $destState -Observation $positiveObservation

$soldOutObservation = [pscustomobject]@{
    timestamp = 260
    country = 'united_kingdom'
    itemId = 266
    stock = 0
    foreignPrice = 200
    source = 'prometheus'
    sourceTimestamp = 260
}
$completed = Update-CycleState -DestState $destState -Observation $soldOutObservation
Assert-Equal 'Completed cycle keeps item identity' ([int]$completed.itemId) 266
Assert-Equal 'Completed cycle keeps country identity' ([string]$completed.country) 'united_kingdom'
Assert-Equal 'Completed cycle uses conservative confirmed availability' ([long]$completed.availabilitySeconds) 30
Assert-Equal 'Completed cycle retains maximum availability bound' ([long]$completed.availabilityMaximumSeconds) 160
Assert-Equal 'Completed cycle restock delay is isolated' ([long]$completed.restockDelaySeconds) 100
Assert-True 'Bounded completed cycle remains forecast eligible' ([bool]$completed.forecastEligible)

$gapPolicy = [pscustomobject]@{
    expectedPollSeconds=60
    selloutSafeGapSeconds=180
    restockSafeGapSeconds=180
    selloutHardGapSeconds=600
    restockHardGapSeconds=600
}
$longGapState = [pscustomobject]@{
    lastStock=0
    lastForeignPrice=200
    lastSourceTimestamp=100
    lastSellOutAt=100
    lastSellOutLowerBoundAt=90
    lastSellOutUpperBoundAt=100
    lastSellOutBoundaryQuality='bounded'
    continuityInvalidatedAt=0
    activeCycle=$null
}
$interiorGapObservation = [pscustomobject]@{timestamp=800;sourceTimestamp=800;stock=0;foreignPrice=200}
Assert-Equal 'Same-phase outage shorter than a full possible cycle does not erase a known boundary' (Invalidate-PhaseAnchorForGap -DestState $longGapState -Observation $interiorGapObservation -BoundaryPolicy $gapPolicy) $false
Assert-Equal 'Bridgeable same-phase outage keeps the known sellout anchor' ([long]$longGapState.lastSellOutAt) 100

$fullCycleGapObservation = [pscustomobject]@{timestamp=1400;sourceTimestamp=1400;stock=0;foreignPrice=200}
Assert-True 'Same-phase outage long enough to hide a full cycle invalidates continuity' (Invalidate-PhaseAnchorForGap -DestState $longGapState -Observation $fullCycleGapObservation -BoundaryPolicy $gapPolicy)
Assert-Equal 'Full-cycle OOS gap clears the sellout anchor' ([long]$longGapState.lastSellOutAt) 0
Assert-Equal 'Full-cycle gap records invalidation point' ([long]$longGapState.continuityInvalidatedAt) 1400

$unknownBoundaryState = [pscustomobject]@{
    lastStock=400
    lastForeignPrice=200
    lastSourceTimestamp=100
    lastSellOutAt=0
    lastSellOutLowerBoundAt=0
    lastSellOutUpperBoundAt=0
    lastSellOutBoundaryQuality='unknown'
    continuityInvalidatedAt=0
    activeCycle=[pscustomobject]@{
        previousSoldOutAt=50L
        previousSoldOutLowerBoundAt=40L
        previousSoldOutUpperBoundAt=50L
        previousSellOutBoundaryQuality='bounded'
        restockAt=60L
        restockLowerBoundAt=50L
        restockUpperBoundAt=60L
        restockBoundaryQuality='bounded'
        restockGapSeconds=10L
        restockQuantity=500
        foreignPrice=200
        source='prometheus'
    }
}
$unknownSellout=[pscustomobject]@{timestamp=900;sourceTimestamp=900;country='united_kingdom';itemId=266;stock=0;foreignPrice=200;source='prometheus'}
$unknownCompleted=Update-CycleState -DestState $unknownBoundaryState -Observation $unknownSellout -BoundaryPolicy $gapPolicy
Assert-Equal 'Sellout across an unobservable outage is not assigned a fake timestamp' ([long]$unknownBoundaryState.lastSellOutAt) 0
Assert-Equal 'Unobservable sellout boundary is explicitly unknown' ([string]$unknownBoundaryState.lastSellOutBoundaryQuality) 'unknown_gap'
Assert-Equal 'Partial cycle with missing sellout boundary is excluded from forecast' ([bool]$unknownCompleted.forecastEligible) $false

Write-Host 'Shadow collection tests passed.' -ForegroundColor Green
exit 0
