$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath=Join-Path $ProjectRoot '@Resources\Scripts\TrendForecast.ps1'
. $scriptPath -SkipMain

function Assert-True([bool]$Condition,[string]$Message) {
    if (-not $Condition) { Write-Host "FAIL: $Message" -ForegroundColor Red; exit 1 }
    Write-Host "PASS $Message" -ForegroundColor Green
}

function New-Sample([long]$At,[long]$Delay,[long]$Available,[long]$Price,[int]$Ratio) {
    [pscustomobject]@{ soldOutAt=$At; restockDelaySeconds=$Delay; availabilitySeconds=$Available; foreignPrice=$Price; priceToMvRatioBps=$Ratio }
}

$growing=@(
    New-Sample 1 3600 480 10000 3000
    New-Sample 2 3610 600 10500 3100
    New-Sample 3 3590 720 11000 3200
    New-Sample 4 3605 900 11600 3300
)
$availability=Get-TFLinearTrend -Samples $growing -Property 'availabilitySeconds' -MinimumAbsoluteSlope 30 -MinimumRelativeSlope 0.02
Assert-True ($availability.direction -eq 'growing') '8-10-12-15 minute stocked durations are detected as growing'
Assert-True ([double]$availability.boundedForecast -gt 900) 'growing duration forecast extends beyond the latest 15-minute sample'
Assert-True ([double]$availability.rSquared -gt 0.90) 'clean growth has strong regression fit'
$priceCorr=Get-TFCorrelation -Samples $growing -XProperty 'foreignPrice' -YProperty 'availabilitySeconds'
Assert-True ($priceCorr -gt 0.90) 'rising price and stocked duration expose positive correlation'

$flat=@(
    New-Sample 1 3600 600 14000 2500
    New-Sample 2 3610 605 14000 2500
    New-Sample 3 3590 595 14000 2500
    New-Sample 4 3605 600 14000 2500
    New-Sample 5 3600 602 14000 2500
)
$flatTrend=Get-TFLinearTrend -Samples $flat -Property 'availabilitySeconds' -MinimumAbsoluteSlope 30 -MinimumRelativeSlope 0.02
Assert-True ($flatTrend.direction -eq 'neutral') 'small duration noise remains neutral'

$accuracy=New-TFAccuracy
$pending=[pscustomobject]@{ basedOnCycleAt=10L; availabilitySeconds=900L; restockDelaySeconds=3600L }
$actual=[pscustomobject]@{ soldOutAt=20L; availabilitySeconds=840L; restockDelaySeconds=3660L }
$accuracy=Update-TFAccuracy -Accuracy $accuracy -Pending $pending -Actual $actual
Assert-True ($accuracy.count -eq 1) 'next completed cycle scores one shadow forecast'
Assert-True ([Math]::Round([double]$accuracy.availabilityMaeSeconds) -eq 60) 'availability forecast error is retained'
Assert-True ([Math]::Round([double]$accuracy.restockDelayMaeSeconds) -eq 60) 'restock forecast error is retained'

$market=[pscustomobject]@{ recentSamples=$growing; trendForecast=$null }
Assert-True (Update-TFMarket -Market $market -NowEpoch 100) 'market trend forecast is projected'
Assert-True ([string]$market.trendForecast.mode -eq 'shadow') 'trend forecast remains explicitly shadow-only'
Assert-True ([string]$market.trendForecast.availability.direction -eq 'growing') 'market projection retains duration direction'
Assert-True ([double]$market.trendForecast.availabilityVsPriceCorrelation -gt 0.90) 'market projection retains price/duration correlation'

Write-Host 'Shadow next-cycle trend forecast tests passed.' -ForegroundColor Green
exit 0
