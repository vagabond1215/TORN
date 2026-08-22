$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
. (Join-Path $ProjectRoot '@Resources\Scripts\VisibleItems.ps1') -SkipMain

function Read-Json([string]$Relative) { Get-Content -LiteralPath (Join-Path $ProjectRoot $Relative) -Raw | ConvertFrom-Json }
function Assert-Equal { param([string]$Name, $Actual, $Expected) if ($Actual -ne $Expected) { throw "$Name - expected '$Expected', got '$Actual'." }; Write-Host "PASS $Name" -ForegroundColor DarkGreen }
function Assert-True { param([string]$Name, [bool]$Condition) if (-not $Condition) { throw "$Name - condition was false." }; Write-Host "PASS $Name" -ForegroundColor DarkGreen }

$items = Read-Json 'config\items.json'
$countries = Read-Json 'config\countries.json'
$perks = Read-Json 'config\travel-perks.json'
$settings = Read-Json 'config\settings.example.json'
$uk = @($countries.countries | Where-Object { [string]$_.id -eq 'united_kingdom' } | Select-Object -First 1)[0]
$japan = @($countries.countries | Where-Object { [string]$_.id -eq 'japan' } | Select-Object -First 1)[0]
$nessie = @($items.items | Where-Object { [int]$_.itemId -eq 266 } | Select-Object -First 1)[0]
$cherry = @($items.items | Where-Object { [int]$_.itemId -eq 277 } | Select-Object -First 1)[0]

Assert-Equal 'UK selects Nessie as secondary visible item' ([int](Get-VisibleSecondaryItem -ItemsConfig $items -CountryId 'united_kingdom' -PrimaryItemId 206).itemId) 266
Assert-Equal 'Japan selects Cherry as secondary visible item' ([int](Get-VisibleSecondaryItem -ItemsConfig $items -CountryId 'japan' -PrimaryItemId 206).itemId) 277

$now = 2000000000L
$engine = [pscustomobject]@{
    observedMarkets = [pscustomobject]@{
        'united_kingdom:266' = [pscustomobject]@{ country='united_kingdom'; itemId=266; lastStock=80; lastForeignPrice=10000; source='prometheus'; sourceTimestamp=1999999940; lastSeenAt=1999999945; catalogActive=$true }
        'japan:277' = [pscustomobject]@{ country='japan'; itemId=277; lastStock=120; lastForeignPrice=500; source='prometheus'; sourceTimestamp=1999999940; lastSeenAt=1999999945; catalogActive=$true }
    }
    destinations = [pscustomobject]@{
        'united_kingdom:266' = [pscustomobject]@{ lastSellOutAt=0 }
        'japan:277' = [pscustomobject]@{ lastSellOutAt=0 }
    }
    resaleCache = [pscustomobject]@{
        '206' = [pscustomobject]@{ price=850000; fetchedAt=1999999990; source='torn_itemmarket' }
        '266' = [pscustomobject]@{ price=65000; fetchedAt=1999999900; source='torn_itemmarket' }
        '277' = [pscustomobject]@{ price=25000; fetchedAt=1999999900; source='torn_itemmarket' }
    }
    itemMetadata = [pscustomobject]@{
        '266' = [pscustomobject]@{ name='Nessie Plushie'; category='Plushie' }
        '277' = [pscustomobject]@{ name='Cherry Blossom'; category='Flower' }
    }
}
$profitability = [pscustomobject]@{ itemMarketFeePercent=5.0; minimumProfitPerItem=0; minimumMarginPercent=0; minimumTotalTripProfit=0; capacityOverride=0 }

$toyProfile = Get-TravelProfile -BaseSettings $settings -LocalSettings ([pscustomobject]@{ travelProfile=[pscustomobject]@{
    companyType='toy_shop'; companyStars=7; currentCapacityKnown=$true; currentCapacityMode='airstrip'; currentCapacity=18; currentCapacityBonus=3; currentCapacitySyncedAt=$now
} })
$nessieView = Get-VisibleSecondaryPresentation -Country $uk -Item $nessie -EngineState $engine -TravelProfile $toyProfile -PerksConfig $perks -Profitability $profitability -TravelMode 'airstrip' -NowEpoch $now
Assert-True 'Nessie active market is visible' ([bool]$nessieView.visible)
Assert-Equal 'Nessie keeps provider stock' ([int]$nessieView.stock) 80
Assert-Equal 'Nessie keeps foreign shop price' ([long]$nessieView.foreignPrice) 10000
Assert-Equal 'Nessie exposes Torn market value' ([long]$nessieView.marketValue) 65000
Assert-Equal 'Toy Shop applies Plushie category capacity' ([int]$nessieView.capacity) 23
Assert-Equal 'Profitable fresh Nessie card is green-class eligible' ([string]$nessieView.priceClass) 'GOOD'

$flowerProfile = Get-TravelProfile -BaseSettings $settings -LocalSettings ([pscustomobject]@{ travelProfile=[pscustomobject]@{
    companyType='flower_shop'; companyStars=7; currentCapacityKnown=$true; currentCapacityMode='airstrip'; currentCapacity=18; currentCapacityBonus=3; currentCapacitySyncedAt=$now
} })
$cherryView = Get-VisibleSecondaryPresentation -Country $japan -Item $cherry -EngineState $engine -TravelProfile $flowerProfile -PerksConfig $perks -Profitability $profitability -TravelMode 'airstrip' -NowEpoch $now
Assert-Equal 'Flower Shop applies Flower category capacity' ([int]$cherryView.capacity) 23
Assert-Equal 'Cherry keeps canonical category' ([string]$cherryView.category) 'Flower'
Assert-Equal 'Cherry exposes cached market value' ([long]$cherryView.marketValue) 25000

$staleEngine = $engine | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$staleEngine.resaleCache.'266'.fetchedAt = $now - 30000
$staleView = Get-VisibleSecondaryPresentation -Country $uk -Item $nessie -EngineState $staleEngine -TravelProfile $toyProfile -PerksConfig $perks -Profitability $profitability -TravelMode 'airstrip' -NowEpoch $now
Assert-Equal 'Stale market value remains displayable' ([long]$staleView.marketValue) 65000
Assert-True 'Stale market value is marked not fresh' (-not [bool]$staleView.marketValueFresh)
Assert-Equal 'Stale market value does not drive profitability color' ([string]$staleView.priceClass) 'UNKNOWN'

$legacyEngine = $engine | ConvertTo-Json -Depth 10 | ConvertFrom-Json
$legacyEngine.observedMarkets.'united_kingdom:266' | Add-Member NoteProperty catalogStatus 'legacy_removed' -Force
$legacyEngine.observedMarkets.'united_kingdom:266'.catalogActive = $false
$legacyView = Get-VisibleSecondaryPresentation -Country $uk -Item $nessie -EngineState $legacyEngine -TravelProfile $toyProfile -PerksConfig $perks -Profitability $profitability -TravelMode 'airstrip' -NowEpoch $now
Assert-True 'Inactive market is suppressed from visible item card' (-not [bool]$legacyView.visible)

$primaryResale = Get-VisibleItemsResaleSnapshot -EngineState $engine -ItemId 206 -NowEpoch $now
Assert-Equal 'Primary Xanax market reference is exposed from shared resale cache' ([long]$primaryResale.price) 850000

$graphMarket = [pscustomobject]@{
    lastStock=42
    lastForeignPrice=1234
    source='prometheus'
    sourceTimestamp=$now - 30
    lastSeenAt=$now - 20
}
$graphRows = @(Get-VisibleItemGraphRows -CountryId 'fixture_country' -ItemId 999999 -Cutoff ($now - 3600) -Market $graphMarket)
Assert-Equal 'Graph snapshot adds one current provider observation for an otherwise unknown fixture market' $graphRows.Count 1
Assert-Equal 'Graph snapshot keeps source timestamp instead of inventing now-time history' ([long]$graphRows[0].timestamp) ($now - 30)
Assert-Equal 'Graph snapshot keeps current stock' ([int]$graphRows[0].stock) 42

$state = @{}
Set-VisibleSecondaryState -State $state -Prefix 'UK' -Presentation $nessieView
Assert-Equal 'UK secondary card owns an item-specific graph name' ([string]$state['UKSecondaryGraphName']) 'uk-266-stock.png'
Assert-Equal 'UK secondary state remains independently visible' ([int]$state['UKSecondaryVisible']) 1

Write-Host 'Visible-item presentation tests passed.' -ForegroundColor Green
exit 0
