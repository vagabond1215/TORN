$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $ProjectRoot '@Resources\Scripts\OptimalRoute.ps1') -SkipMain

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
function Assert-Near {
    param([string]$Name,[double]$Actual,[double]$Expected,[double]$Tolerance=0.0001)
    if ([Math]::Abs($Actual-$Expected) -gt $Tolerance) { throw "$Name - expected '$Expected', got '$Actual'." }
    Write-Host "PASS $Name" -ForegroundColor DarkGreen
}

$now = 2000000000L
$bar = [pscustomobject]@{ current=150; maximum=150; increment=5; interval=600; tickTime=300; fullTime=0 }
$waste = Get-OptimalBarWaste -Bar $bar -HorizonSeconds 3600 -NowEpoch $now
Assert-Equal 'Full bar loses six natural ticks over one hour fixture' ([long]$waste.loss) 30
Assert-True 'Non-stacked bar does not bypass restriction' (-not [bool]$waste.bypass)
Assert-True 'Forbidden policy rejects nonzero loss' (-not (Test-OptimalWastePolicy -Waste $waste -Policy forbidden -MaximumLoss 0))
Assert-True 'Limited policy accepts exact loss ceiling' (Test-OptimalWastePolicy -Waste $waste -Policy limited -MaximumLoss 30)
Assert-True 'Limited policy rejects lower loss ceiling' (-not (Test-OptimalWastePolicy -Waste $waste -Policy limited -MaximumLoss 29))
Assert-True 'Allowed policy ignores loss' (Test-OptimalWastePolicy -Waste $waste -Policy allowed -MaximumLoss 0)

$stacked = [pscustomobject]@{ current=1000; maximum=150; increment=5; interval=600; tickTime=300; fullTime=0 }
$energyWaste = Get-OptimalBarWaste -Bar $stacked -HorizonSeconds 3600 -NowEpoch $now -EnergyStackBypass
Assert-True 'Stacked Energy is detected' ([bool]$energyWaste.stacked)
Assert-True 'Stacked Energy activates Energy-only bypass' ([bool]$energyWaste.bypass)
Assert-Equal 'Stacked Energy effective loss is bypassed' ([long]$energyWaste.loss) 0
Assert-True 'Forbidden Energy permits a stacked Energy route' (Test-OptimalWastePolicy -Waste $energyWaste -Policy forbidden -MaximumLoss 0)

$nerveWaste = Get-OptimalBarWaste -Bar $stacked -HorizonSeconds 3600 -NowEpoch $now
Assert-True 'Stacked Nerve is detected' ([bool]$nerveWaste.stacked)
Assert-True 'Stacked Nerve has no bypass' (-not [bool]$nerveWaste.bypass)
Assert-Equal 'Stacked Nerve retains natural regeneration loss' ([long]$nerveWaste.loss) 30
Assert-True 'Forbidden Nerve still rejects stacked Nerve waste' (-not (Test-OptimalWastePolicy -Waste $nerveWaste -Policy forbidden -MaximumLoss 0))
Assert-True 'Unknown non-Allowed bars fail safe' (-not (Test-OptimalWastePolicy -Waste $null -Policy forbidden -MaximumLoss 0))

$engine = [pscustomobject]@{
    resaleCache = [pscustomobject]@{
        '266' = [pscustomobject]@{ price=29000; lowest=29000; average=30000; fetchedAt=1999999900; source='torn_itemmarket' }
    }
}
$resale = Get-OptimalResaleSnapshot -Engine $engine -ItemId 266 -NowEpoch $now
Assert-Equal 'Optimizer uses Torn average_price as MV, not lowest listing' ([long]$resale.marketValue) 30000
Assert-True 'Fresh MV snapshot is usable' ([bool]$resale.fresh)

$cycles = @{}
$cycles['japan:277'] = @(
    [pscustomobject]@{ availabilitySeconds=1000; restockDelaySeconds=500 },
    [pscustomobject]@{ availabilitySeconds=2000; restockDelaySeconds=1000 },
    [pscustomobject]@{ availabilitySeconds=3000; restockDelaySeconds=1500 }
)
$restockStock = @{}
$restockStock['japan:277'] = [long[]]@(100,200,300)
$evidence = [pscustomobject]@{ cycles=$cycles; observations=@{}; restockStock=$restockStock }
$market = [pscustomobject]@{ lastStock=500 }
$destination = [pscustomobject]@{ activeCycle=[pscustomobject]@{ restockAt=$now } }
$forecast = Get-OptimalArrivalForecast -MarketKey 'japan:277' -Market $market -DestinationState $destination -Evidence $evidence -ArrivalSeconds 1500 -NowEpoch $now -MinimumSamples 3
Assert-True 'In-stock trained forecast is probability-known' ([bool]$forecast.probabilityKnown)
Assert-Near 'In-stock arrival hit probability uses retained availability durations' ([double]$forecast.probability) (2.0/3.0)
Assert-Equal 'In-stock forecast retains current available quantity' ([long]$forecast.estimatedQuantity) 500

$liveNow = Get-OptimalArrivalForecast -MarketKey 'japan:277' -Market $market -DestinationState $destination -Evidence ([pscustomobject]@{cycles=@{};observations=@{};restockStock=@{}}) -ArrivalSeconds 0 -NowEpoch $now -MinimumSamples 3
Assert-True 'Fresh stock at destination is direct evidence' ([bool]$liveNow.probabilityKnown)
Assert-Near 'Fresh stock at destination has current-state hit probability one' ([double]$liveNow.probability) 1.0

$learning = Get-OptimalArrivalForecast -MarketKey 'japan:277' -Market $market -DestinationState $destination -Evidence ([pscustomobject]@{cycles=@{};observations=@{};restockStock=@{}}) -ArrivalSeconds 1500 -NowEpoch $now -MinimumSamples 3
Assert-True 'Untrained in-stock flight remains learning rather than pretending 100 percent' (-not [bool]$learning.probabilityKnown)

$oosMarket = [pscustomobject]@{ lastStock=0 }
$oosDestination = [pscustomobject]@{ lastSellOutAt=$now-200 }
$oosForecast = Get-OptimalArrivalForecast -MarketKey 'japan:277' -Market $oosMarket -DestinationState $oosDestination -Evidence $evidence -ArrivalSeconds 600 -NowEpoch $now -MinimumSamples 3
Assert-True 'OOS restock forecast requires and uses completed-cycle evidence' ([bool]$oosForecast.probabilityKnown)
Assert-Near 'OOS forecast counts cycles live at modeled arrival' ([double]$oosForecast.probability) (1.0/3.0)
Assert-Equal 'OOS forecast uses median observed restock quantity' ([long]$oosForecast.estimatedQuantity) 200

$country = [pscustomobject]@{ id='united_kingdom'; name='United Kingdom'; tripBand='medium' }
$candidates = @(
    [pscustomobject]@{ itemId=206; name='Xanax'; category='Drug'; foreignPrice=700000; marketValue=800000; sellBasis=800000; profitPerItem=100000; probability=0.8; probabilityKnown=$true; expectedUnitProfit=80000.0; priceColor='86,190,116,255'; sourceTimestamp=$now; availableQuantity=18; extraCapacity=0; allocated=0 },
    [pscustomobject]@{ itemId=266; name='Nessie Plushie'; category='Plushie'; foreignPrice=200; marketValue=30000; sellBasis=30000; profitPerItem=29800; probability=1.0; probabilityKnown=$true; expectedUnitProfit=29800.0; priceColor='86,190,116,255'; sourceTimestamp=$now; availableQuantity=100; extraCapacity=5; allocated=0 }
)
$route = Get-OptimalCountryPlan -Country $country -Candidates $candidates -GeneralCapacity 18 -TravelCost 0 -HorizonSeconds 12720 -EnergyWaste $waste -NerveWaste $nerveWaste -MaxPlanItems 8 -ShowProfitableOnly $false
Assert-True 'Country plan resolves' ($null -ne $route)
Assert-Equal 'General plus category-only capacity is represented' ([int]$route.capacity) 23
Assert-Equal 'Plan fills all general and category-only slots when stock permits' ([int]$route.quantity) 23
Assert-Equal 'Plan contains two purchase item rows' @($route.plan).Count 2
$nessie = @($route.plan | Where-Object { [int]$_.itemId -eq 266 } | Select-Object -First 1)
Assert-Equal 'Category-only slots are filled with matching item' ([int]$nessie[0].quantity) 5

$negativeCandidate = @([pscustomobject]@{ itemId=999; name='Collector Item'; category='Miscellaneous'; foreignPrice=1000; marketValue=900; sellBasis=900; profitPerItem=-100; probability=1.0; probabilityKnown=$true; expectedUnitProfit=-100.0; priceColor='224,90,90,255'; sourceTimestamp=$now; availableQuantity=18; extraCapacity=0; allocated=0 })
$negativeRoute = Get-OptimalCountryPlan -Country $country -Candidates $negativeCandidate -GeneralCapacity 18 -TravelCost 0 -HorizonSeconds 3600 -EnergyWaste $waste -NerveWaste $nerveWaste -ShowProfitableOnly $false
Assert-True 'Negative-value item remains a legal optimizer candidate by default' ($null -ne $negativeRoute)
$negativeCandidate[0].allocated = 0
$filteredNegative = Get-OptimalCountryPlan -Country $country -Candidates $negativeCandidate -GeneralCapacity 18 -TravelCost 0 -HorizonSeconds 3600 -EnergyWaste $waste -NerveWaste $nerveWaste -ShowProfitableOnly $true
Assert-True 'Profitable-only setting can explicitly suppress negative route' ($null -eq $filteredNegative)

Write-Host 'Optimal route deterministic tests passed.' -ForegroundColor Green
exit 0
