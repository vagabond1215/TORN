$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$filterPath=Join-Path $ProjectRoot '@Resources\Scripts\CycleForecastFilter.ps1'
. $filterPath

$failures=New-Object System.Collections.Generic.List[string]
function Fail([string]$Message){$script:failures.Add($Message)}
function Assert-True([bool]$Condition,[string]$Message){if(-not$Condition){Fail $Message}}
function Assert-Equal($Actual,$Expected,[string]$Message){if($Actual -ne $Expected){Fail ("{0} Expected={1} Actual={2}" -f $Message,$Expected,$Actual)}}

$isolatedZero=@(
    [pscustomobject]@{timestamp=100L;stock=1000L;source='prometheus'},
    [pscustomobject]@{timestamp=160L;stock=900L;source='prometheus'},
    [pscustomobject]@{timestamp=220L;stock=0L;source='prometheus'},
    [pscustomobject]@{timestamp=280L;stock=820L;source='prometheus'},
    [pscustomobject]@{timestamp=340L;stock=700L;source='prometheus'}
)
$classified=@(Resolve-StockObservationPlausibility -Rows $isolatedZero -ExpectedPollIntervalSeconds 60)
$zero=@($classified|Where-Object{[long]$_.timestamp -eq 220L})[0]
$partner=@($classified|Where-Object{[long]$_.timestamp -eq 280L})[0]
Assert-Equal ([string]$zero.transitionPlausibility) 'spurious_zero' 'Isolated contradictory zero should be classified as spurious.'
Assert-True (-not[bool]$zero.calculationEligible) 'Spurious zero should be excluded from calculations.'
Assert-True (-not[bool]$partner.transitionCalculationEligible) 'Positive partner after a spurious zero must not manufacture a restock transition.'
$filtered=@(Get-PlausibilityFilteredStockObservations -Rows $isolatedZero -ExpectedPollIntervalSeconds 60)
Assert-Equal $filtered.Count 4 'Spurious zero should be removed while surrounding positive observations remain.'
Assert-True (@($filtered|Where-Object{[long]$_.stock -eq 0}).Count -eq 0) 'Filtered trajectory should remain continuously positive.'

$realRestock=@(
    [pscustomobject]@{timestamp=100L;stock=120L;source='prometheus'},
    [pscustomobject]@{timestamp=160L;stock=0L;source='prometheus'},
    [pscustomobject]@{timestamp=220L;stock=5000L;source='prometheus'},
    [pscustomobject]@{timestamp=280L;stock=4700L;source='prometheus'}
)
$realClassified=@(Resolve-StockObservationPlausibility -Rows $realRestock -ExpectedPollIntervalSeconds 60)
Assert-True ([bool](@($realClassified|Where-Object{[long]$_.timestamp -eq 160L})[0].calculationEligible) 'A zero followed by a clear replenishment jump must remain a real sellout.'
Assert-True ([bool](@($realClassified|Where-Object{[long]$_.timestamp -eq 220L})[0].transitionCalculationEligible) 'A full replenishment jump must remain a real restock.'

$tinyBlip=@(
    [pscustomobject]@{timestamp=100L;stock=0L;source='prometheus'},
    [pscustomobject]@{timestamp=160L;stock=5000L;source='prometheus'},
    [pscustomobject]@{timestamp=700L;stock=0L;source='prometheus'},
    [pscustomobject]@{timestamp=760L;stock=5000L;source='prometheus'},
    [pscustomobject]@{timestamp=1300L;stock=0L;source='prometheus'},
    [pscustomobject]@{timestamp=1360L;stock=5L;source='prometheus'},
    [pscustomobject]@{timestamp=1420L;stock=0L;source='prometheus'}
)
$tinyClassified=@(Resolve-StockObservationPlausibility -Rows $tinyBlip -ExpectedPollIntervalSeconds 60)
$tiny=@($tinyClassified|Where-Object{[long]$_.timestamp -eq 1360L})[0]
Assert-Equal ([string]$tiny.transitionPlausibility) 'spurious_restock' 'Tiny one-poll positive blip inside an OoS plateau should be suppressed.'
Assert-True (-not[bool]$tiny.calculationEligible) 'Spurious tiny restock must be excluded from calculations.'

$recoveredTiny=@(
    [pscustomobject]@{timestamp=100L;stock=0L;source='prometheus'},
    [pscustomobject]@{timestamp=160L;stock=5L;source='torn_intel_history_recovery';transitionBoundaryQuality='recovered'},
    [pscustomobject]@{timestamp=220L;stock=0L;source='history_recovery_live_bridge';transitionBoundaryQuality='recovered'}
)
$recoveredClassified=@(Resolve-StockObservationPlausibility -Rows $recoveredTiny -ExpectedPollIntervalSeconds 60)
Assert-True ([bool](@($recoveredClassified|Where-Object{[long]$_.timestamp -eq 160L})[0].calculationEligible) 'Recovered micro-restock evidence must override the heuristic suppression gate.'

$script:CycleSpuriousRegistryLoaded=$true
$script:CycleSpuriousRegistry=[pscustomobject]@{
    markets=[pscustomobject]@{
        'uae:123'=[pscustomobject]@{transitionTimestamps=@(220L,280L)}
    }
}
$fakeCycle=[pscustomobject]@{
    schemaVersion=2;country='uae';itemId=123;source='prometheus'
    restockAt=280L;soldOutAt=500L;previousSoldOutAt=220L
    restockDelaySeconds=60L;availabilitySeconds=220L
    forecastEligible=$true;availabilityEligible=$true;restockDelayEligible=$true;trendEligible=$true
    restockBoundaryQuality='observed';soldOutBoundaryQuality='observed';previousSellOutBoundaryQuality='observed'
}
Assert-True (-not(Test-CycleForecastBoundaryEvidence -Cycle $fakeCycle -Purpose Forecast)) 'A cycle anchored to suppressed transition timestamps must not teach the forecast.'

$recoveredCycle=[pscustomobject]@{
    schemaVersion=2;country='uae';itemId=123;source='torn_intel_history_recovery'
    restockAt=280L;soldOutAt=500L;previousSoldOutAt=220L
    restockDelaySeconds=60L;availabilitySeconds=220L
    forecastEligible=$true;availabilityEligible=$true;restockDelayEligible=$true;trendEligible=$true
    restockBoundaryQuality='recovered';soldOutBoundaryQuality='recovered';previousSellOutBoundaryQuality='recovered'
}
Assert-True (Test-CycleForecastBoundaryEvidence -Cycle $recoveredCycle -Purpose Forecast) 'Externally recovered cycle truth must remain eligible despite a prior local heuristic suppression.'

if($failures.Count -gt 0){
    foreach($failure in $failures){Write-Host "FAIL: $failure" -ForegroundColor Red}
    Write-Host "Observation plausibility tests failed with $($failures.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Observation plausibility filtering tests passed.' -ForegroundColor Green
exit 0
