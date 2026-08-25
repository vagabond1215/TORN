$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath=Join-Path $ProjectRoot '@Resources\Scripts\WindowPlanRefiner.ps1'
. $scriptPath -SkipMain

$failures=New-Object System.Collections.Generic.List[string]
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { $script:failures.Add($Message) } }
function Assert-Equal($Actual,$Expected,[string]$Message) { if ($Actual -ne $Expected) { $script:failures.Add("$Message Expected=$Expected Actual=$Actual") } }
function Assert-Near([double]$Actual,[double]$Expected,[double]$Tolerance,[string]$Message) { if ([Math]::Abs($Actual-$Expected) -gt $Tolerance) { $script:failures.Add("$Message Expected=$Expected Actual=$Actual") } }

$anchor=100000L
$cycles=@(
    [pscustomobject]@{restockDelaySeconds=3600L;availabilitySeconds=1800L;soldOutAt=10L}, # period 5400
    [pscustomobject]@{restockDelaySeconds=4200L;availabilitySeconds=1800L;soldOutAt=11L}, # period 6000
    [pscustomobject]@{restockDelaySeconds=4800L;availabilitySeconds=1800L;soldOutAt=12L}  # period 6600
)
$model=Get-StableRecurringScenarioModel -Cycles $cycles -AnchorAt $anchor -AnchorPhase sellout -NowEpoch $anchor -FutureHorizonSeconds 50000
Assert-Equal ([long]$model.medianPeriodSeconds) 6000L 'Stable recurring model should use the median complete-cycle period.'
$group0=@($model.groups | Where-Object { [int]$_.ordinal -eq 0 } | Select-Object -First 1)[0]
$group5=@($model.groups | Where-Object { [int]$_.ordinal -eq 5 } | Select-Object -First 1)[0]
Assert-Equal ([long]$group0.earlyRestockAt) ($anchor+3600L) 'First-cycle earliest restock should retain empirical minimum delay.'
Assert-Equal ([long]$group0.lateRestockAt) ($anchor+4800L) 'First-cycle latest restock should retain empirical maximum delay.'
Assert-Equal (([long]$group5.lateRestockAt-[long]$group5.earlyRestockAt)) 1200L 'Future-cycle restock uncertainty must not compound with ordinal.'
Assert-Equal ([long]$group5.earlyRestockAt) ($anchor+(5L*6000L)+3600L) 'Future groups should advance by median period plus one-cycle delay variance.'

# A collector outage / missed transition may create one implausibly long apparent cycle.
# Keep it in analytics, but exclude it from the live forecast when a stable majority exists.
$outlierCycles=@(
    [pscustomobject]@{restockDelaySeconds=3500L;availabilitySeconds=1700L;soldOutAt=20L},
    [pscustomobject]@{restockDelaySeconds=3600L;availabilitySeconds=1800L;soldOutAt=21L},
    [pscustomobject]@{restockDelaySeconds=3700L;availabilitySeconds=1800L;soldOutAt=22L},
    [pscustomobject]@{restockDelaySeconds=3800L;availabilitySeconds=1700L;soldOutAt=23L},
    [pscustomobject]@{restockDelaySeconds=3900L;availabilitySeconds=1800L;soldOutAt=24L},
    [pscustomobject]@{restockDelaySeconds=72000L;availabilitySeconds=1800L;soldOutAt=25L}
)
$filtered=@(Get-StableWindowUsableCycles -Cycles $outlierCycles)
Assert-Equal $filtered.Count 5 'Stable forecast should discard a many-hour pseudo-cycle when five normal recent cycles agree.'
Assert-True (-not (@($filtered | Where-Object { [long]$_.restockDelaySeconds -gt 10000L }).Count -gt 0)) 'Outage-length restock delay must not remain in live forecast evidence.'

# Selection is chronological. A near-term >50% Best Hit should not be skipped just
# because some later cycle eventually has a Safe Window.
$selectionModel=[pscustomobject]@{ groups=@(
    [pscustomobject]@{ ordinal=0; earlyRestockAt=$anchor+1000; earlySelloutAt=$anchor+1400; lateRestockAt=$anchor+1200; lateSelloutAt=$anchor+1600; safeStartAt=0L; safeEndAt=0L; bestStartAt=$anchor+1100; bestEndAt=$anchor+1300; bestProbability=(2.0/3.0) },
    [pscustomobject]@{ ordinal=1; earlyRestockAt=$anchor+5000; earlySelloutAt=$anchor+5800; lateRestockAt=$anchor+5200; lateSelloutAt=$anchor+6000; safeStartAt=$anchor+5200; safeEndAt=$anchor+5800; bestStartAt=$anchor+5200; bestEndAt=$anchor+5800; bestProbability=1.0 }
) }
$selected=Select-StableWindowPlanGroup -Model $selectionModel -EarliestArrivalAt $anchor -MinimumBestProbability .5
Assert-Equal ([string]$selected.mode) 'best' 'Near-term Best Hit must beat a much later Safe Window in another cycle.'
Assert-Near ([double]$selected.probability) (2.0/3.0) 0.0001 'Chronological Best Hit selection should retain its empirical confidence.'

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL: $failure" -ForegroundColor Red }
    Write-Host "Stable recurring-window tests failed with $($failures.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Stable recurring-window phase, outage outlier filtering, and chronological Safe/Best selection tests passed.' -ForegroundColor Green
exit 0
