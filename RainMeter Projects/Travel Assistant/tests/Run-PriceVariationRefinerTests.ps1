$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath=Join-Path $ProjectRoot '@Resources\Scripts\PriceVariationRefiner.ps1'
. $scriptPath -SkipMain

function Assert-True([bool]$Condition,[string]$Message) {
    if (-not $Condition) { Write-Host "FAIL: $Message" -ForegroundColor Red; exit 1 }
    Write-Host "PASS $Message" -ForegroundColor Green
}

function New-PriceSample([long]$At,[long]$Price) {
    [pscustomobject]@{ soldOutAt=$At; foreignPrice=$Price }
}

Assert-True ((Get-PVTakeValue -PurchaseCost 1000L -PriceVaries $false) -eq 1000L) 'fixed foreign prices require exactly the planned purchase cost'
Assert-True ((Get-PVTakeValue -PurchaseCost 1000L -PriceVaries $true) -eq 1050L) 'variable foreign prices add a five-percent Take reserve'
Assert-True ((Get-PVTakeValue -PurchaseCost 1001L -PriceVaries $true) -eq 1052L) 'variable-price Take reserve rounds upward to ensure enough cash'

$fixed=[pscustomobject]@{
    currentForeignPrice=14000L
    recentSamples=@(
        New-PriceSample 1 14000
        New-PriceSample 2 14000
        New-PriceSample 3 17000  # one old/provider anomaly
        New-PriceSample 4 14000
        New-PriceSample 5 14000
        New-PriceSample 6 14000
    )
    priceEvents=@([pscustomobject]@{at=3;fromPrice=14000;toPrice=17000})
}
$fixedResult=Test-PVRecentVariation -Market $fixed
Assert-True (-not [bool]$fixedResult.varies) 'one historical anomaly does not permanently mark a fixed-price item variable'
Assert-True ([string]$fixedResult.reason -eq 'recent-fixed') 'fixed classification reports recent-fixed reason'

$recoveredFixed=[pscustomobject]@{
    currentForeignPrice=6000L
    recentSamples=@(
        New-PriceSample 1 6000
        New-PriceSample 2 6000
        New-PriceSample 3 6500  # isolated bad/provider value
        New-PriceSample 4 6000  # latest sample returns to the stable shop price
    )
}
$recoveredResult=Test-PVRecentVariation -Market $recoveredFixed
Assert-True (-not [bool]$recoveredResult.varies) 'returning from one anomalous sample to a stable fixed price stays fixed'
Assert-True ([string]$recoveredResult.reason -eq 'recent-fixed') 'fixed recovery reports recent-fixed reason'

$currentChange=[pscustomobject]@{
    currentForeignPrice=15000L
    recentSamples=@(
        New-PriceSample 1 14000
        New-PriceSample 2 14000
        New-PriceSample 3 14000
        New-PriceSample 4 14000
    )
}
$currentResult=Test-PVRecentVariation -Market $currentChange
Assert-True ([bool]$currentResult.varies) 'material current price change is detected immediately'
Assert-True ([string]$currentResult.reason -eq 'current-vs-recent') 'current transition reason is explicit'

$scopedStale=[pscustomobject]@{
    currentForeignPrice=14000L
    recentSamples=@(
        New-PriceSample 1 14000
        New-PriceSample 2 14000
        New-PriceSample 3 14000
        New-PriceSample 4 14000
    )
}
$overrideResult=Test-PVRecentVariation -Market $scopedStale -CurrentOverride 15000L
Assert-True ([bool]$overrideResult.varies) 'current observed price override detects variation even when transient analytics are sleeping'
Assert-True ([string]$overrideResult.reason -eq 'current-vs-recent') 'sleeping/current override reports current-vs-recent reason'

$recurring=[pscustomobject]@{
    currentForeignPrice=15000L
    recentSamples=@(
        New-PriceSample 1 14000
        New-PriceSample 2 14000
        New-PriceSample 3 15000
        New-PriceSample 4 15000
        New-PriceSample 5 14000
        New-PriceSample 6 14000
        New-PriceSample 7 15000
        New-PriceSample 8 15000
    )
}
$recurringResult=Test-PVRecentVariation -Market $recurring
Assert-True ([bool]$recurringResult.varies) 'recurring materially separated price levels remain variable'

$enveloped=Set-PVEnvelope -Text 'WP2:abc#PV1#human' -Varies $false
Assert-True ($enveloped -eq 'WP2:abc#PV0#human') 'WP2 price-variance envelope can be corrected to fixed'

$sleepEnvelope=Set-PVEnvelope -Text 'Sleeping OOS estimate' -Varies $true
Assert-True ($sleepEnvelope -eq 'PV1#Sleeping OOS estimate') 'sleeping rows can carry price-variance metadata without WP2 geometry'

Write-Host 'Recent fixed/variable price classification tests passed.' -ForegroundColor Green
exit 0
