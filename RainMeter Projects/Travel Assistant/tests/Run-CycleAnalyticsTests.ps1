$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$scriptPath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path '@Resources\Scripts\CycleAnalytics.ps1'
. $scriptPath -SkipMain

$failures = @()
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { $script:failures += $Message } }
function Assert-Equal($Actual,$Expected,[string]$Message) { if ($Actual -ne $Expected) { $script:failures += ("$Message Expected=$Expected Actual=$Actual") } }
function Assert-Near([double]$Actual,[double]$Expected,[double]$Tolerance,[string]$Message) { if ([Math]::Abs($Actual-$Expected) -gt $Tolerance) { $script:failures += ("$Message Expected=$Expected Actual=$Actual") } }

$config = [pscustomobject]@{
    significantPriceChangePercent = 5.0
    significantSelloutChangePercent = 15.0
    significantSelloutChangeSeconds = 300
    maxRecentSamplesPerMarket = 96
    maxRegimesPerMarket = 24
    maxPriceEventsPerMarket = 48
}
$root = New-CycleAnalyticsRoot -Config $config
$cycles = @(
    [pscustomobject]@{ country='japan'; itemId=206; restockDelaySeconds=3600L; availabilitySeconds=2700L; foreignPrice=100L; restockAt=1000L; soldOutAt=3700L },
    [pscustomobject]@{ country='japan'; itemId=206; restockDelaySeconds=3300L; availabilitySeconds=2760L; foreignPrice=103L; restockAt=5000L; soldOutAt=7760L },
    [pscustomobject]@{ country='japan'; itemId=206; restockDelaySeconds=3900L; availabilitySeconds=2820L; foreignPrice=110L; restockAt=9000L; soldOutAt=11820L },
    [pscustomobject]@{ country='japan'; itemId=206; restockDelaySeconds=3700L; availabilitySeconds=3600L; foreignPrice=110L; restockAt=13000L; soldOutAt=16600L }
)
foreach ($cycle in $cycles) { [void](Update-CycleMarketAnalytics -Root $root -Cycle $cycle -Config $config -MarketValue 200L) }
$market = $root.markets.'japan:206'

Assert-Equal ([int]$market.sampleCount) 4 'Cycle sample count should include every completed cycle.'
Assert-Equal ([long]$market.restockDelay.min) 3300L 'Minimum observed restock delay must be retained.'
Assert-Equal ([long]$market.restockDelay.max) 3900L 'Maximum observed restock delay must be retained.'
Assert-Near ([double]$market.restockDelay.mean) 3625.0 0.001 'Mean restock delay should be tracked.'
Assert-True ([double]$market.restockDelay.stdDev -gt 0) 'Restock delay variance should be retained.'
Assert-Equal ([long]$market.selloutDuration.min) 2700L 'Minimum stocked/sellout duration must be retained.'
Assert-Equal ([long]$market.selloutDuration.max) 3600L 'Maximum stocked/sellout duration must be retained.'
Assert-True ([double]$market.selloutDuration.stdDev -gt 0) 'Sellout-duration variance should be retained.'
Assert-Equal (@($market.regimes).Count) 3 'Price and material sellout changes should open new regimes.'
Assert-Equal ([string]$market.regimes[0].reason) 'initial' 'First regime should be the initial baseline.'
Assert-Equal ([string]$market.regimes[1].reason) 'price' 'A >=5% price move should start a price regime.'
Assert-Equal ([string]$market.regimes[2].reason) 'sellout' 'A material sellout-duration move should start a sellout regime.'
Assert-Equal ([int]$market.regimes[0].sampleCount) 2 'Small price/time changes should remain in the same regime.'
Assert-Equal ([int]$market.priceToMvRatioBps.count) 4 'Known MV ratios should be sampled with completed cycles.'
Assert-Near ([double]$market.priceToMvRatioBps.mean) 5287.5 0.1 'Price/MV basis-point ratio should remain item-specific.'
Assert-Equal (@($market.recentSamples).Count) 4 'Recent raw cycle summaries should remain available for later model calibration.'

$engine = [pscustomobject]@{
    observedMarkets = [pscustomobject]@{
        'japan:206' = [pscustomobject]@{ itemId=206; lastForeignPrice=100L; lastStock=50L }
    }
    resaleCache = [pscustomobject]@{
        '206' = [pscustomobject]@{ average=200L }
    }
}
$eventRoot = New-CycleAnalyticsRoot -Config $config
Assert-True (Update-CurrentCycleMarketSnapshots -Root $eventRoot -EngineState $engine -Config $config -NowEpoch 20000L) 'Initial current-price snapshot should be stored.'
$eventMarket = $eventRoot.markets.'japan:206'
Assert-Equal (@($eventMarket.priceEvents).Count) 0 'Initial price snapshot is not itself a change event.'
$engine.observedMarkets.'japan:206'.lastForeignPrice = 103L
[void](Update-CurrentCycleMarketSnapshots -Root $eventRoot -EngineState $engine -Config $config -NowEpoch 20100L)
Assert-Equal (@($eventMarket.priceEvents).Count) 0 'Sub-threshold price noise should not create an event.'
$engine.observedMarkets.'japan:206'.lastForeignPrice = 106L
[void](Update-CurrentCycleMarketSnapshots -Root $eventRoot -EngineState $engine -Config $config -NowEpoch 20200L)
Assert-Equal (@($eventMarket.priceEvents).Count) 1 'Cumulative >=5% price movement from the anchor should create an event.'
Assert-Equal ([long]$eventMarket.priceEvents[0].fromPrice) 100L 'Price event should retain its previous significant anchor.'
Assert-Equal ([long]$eventMarket.priceEvents[0].toPrice) 106L 'Price event should retain the new significant price.'
Assert-Equal ([int]$eventMarket.priceEvents[0].priceToMvRatioBps) 5300 'Price event should capture contemporaneous foreign-price/MV ratio.'

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL: $failure" -ForegroundColor Red }
    Write-Host "Cycle analytics deterministic tests failed with $($failures.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Cycle analytics deterministic tests passed.' -ForegroundColor Green
Write-Host 'Engine analytics retain restock bounds/variance, sellout-duration variance, material price/sellout regimes, recent samples, and significant price-to-MV events.'
exit 0
