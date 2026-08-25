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

Write-Host 'Recent fixed/variable price classification tests passed.' -ForegroundColor Green
exit 0
