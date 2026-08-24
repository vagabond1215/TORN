$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath=Join-Path $ProjectRoot '@Resources\Scripts\WindowPlan.ps1'
. $scriptPath -SkipMain

$failures=New-Object System.Collections.Generic.List[string]
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { $script:failures.Add($Message) } }
function Assert-Equal($Actual,$Expected,[string]$Message) { if ($Actual -ne $Expected) { $script:failures.Add("$Message Expected=$Expected Actual=$Actual") } }
function Assert-Near([double]$Actual,[double]$Expected,[double]$Tolerance,[string]$Message) { if ([Math]::Abs($Actual-$Expected) -gt $Tolerance) { $script:failures.Add("$Message Expected=$Expected Actual=$Actual") } }

$anchor=100000L
$now=$anchor
# User example: earliest restock 1h50, latest 2h10, stocked for 30m.
# Intervals are 1:50-2:20, 2:00-2:30, 2:10-2:40, so the
# all-scenario overlap is 2:10-2:20 = ten minutes.
$safeCycles=@(
    [pscustomobject]@{restockDelaySeconds=6600L;availabilitySeconds=1800L;soldOutAt=1L},
    [pscustomobject]@{restockDelaySeconds=7200L;availabilitySeconds=1800L;soldOutAt=2L},
    [pscustomobject]@{restockDelaySeconds=7800L;availabilitySeconds=1800L;soldOutAt=3L}
)
$safeModel=Get-RecurringScenarioModel -Cycles $safeCycles -AnchorAt $anchor -AnchorPhase sellout -NowEpoch $now -FutureHorizonSeconds 20000
Assert-Equal ([int]$safeModel.sampleCount) 3 'Safe model should retain all three completed cycles.'
$g=@($safeModel.groups | Select-Object -First 1)[0]
Assert-Equal ([long]$g.earlyRestockAt) ($anchor+6600L) 'Early Restock must use the minimum projected restock.'
Assert-Equal ([long]$g.earlySelloutAt) ($anchor+8400L) 'Early sellout must use the earliest projected sellout.'
Assert-Equal ([long]$g.lateRestockAt) ($anchor+7800L) 'Late Restock must use the maximum projected restock.'
Assert-Equal ([long]$g.lateSelloutAt) ($anchor+9600L) 'Late sellout must use the latest projected sellout.'
Assert-Equal ([long]$g.safeStartAt) ($anchor+7800L) 'Safe Window begins at the latest projected restock.'
Assert-Equal ([long]$g.safeEndAt) ($anchor+8400L) 'Safe Window ends at the earliest projected sellout.'
Assert-Equal ([long]$g.safeSeconds) 600L 'User example must produce a ten-minute safe overlap.'
Assert-Near ([double]$g.bestProbability) 1.0 0.0001 'The safe overlap is also supported by all empirical scenarios.'
$selected=Select-WindowPlanGroup -Model $safeModel -EarliestArrivalAt $anchor -MinimumBestProbability .5
Assert-Equal ([string]$selected.mode) 'safe' 'A nontrivial all-scenario overlap must win over best-hit mode.'

# No full overlap, but two-of-three scenarios overlap in short segments.
$bestCycles=@(
    [pscustomobject]@{restockDelaySeconds=6600L;availabilitySeconds=900L;soldOutAt=1L},
    [pscustomobject]@{restockDelaySeconds=7200L;availabilitySeconds=900L;soldOutAt=2L},
    [pscustomobject]@{restockDelaySeconds=7800L;availabilitySeconds=900L;soldOutAt=3L}
)
$bestModel=Get-RecurringScenarioModel -Cycles $bestCycles -AnchorAt $anchor -AnchorPhase sellout -NowEpoch $now -FutureHorizonSeconds 20000
$bg=@($bestModel.groups | Select-Object -First 1)[0]
Assert-Equal ([long]$bg.safeSeconds) 0L 'No all-scenario overlap means there is no Safe Window.'
Assert-Near ([double]$bg.bestProbability) (2.0/3.0) 0.0001 'Best Hit Window should retain the two-of-three overlap confidence.'
$bestSelected=Select-WindowPlanGroup -Model $bestModel -EarliestArrivalAt $anchor -MinimumBestProbability .5
Assert-Equal ([string]$bestSelected.mode) 'best' 'Without a Safe Window, a >50% empirical overlap becomes Best Hit.'
Assert-Near ([double]$bestSelected.probability) (2.0/3.0) 0.0001 'Best-hit selection must expose its confidence.'

$machine=Convert-WindowPlanMachineText -Model $safeModel
Assert-True ($machine.StartsWith('G,')) 'Machine plan must encode conservative group bounds.'
Assert-True ($machine.Contains('~')) 'Machine plan must separate group geometry from live probability segments.'
Assert-True (($safeModel.segments | Where-Object { [double]$_.probability -eq 1.0 }).Count -gt 0) 'Probability timeline must retain the 100% support interval.'

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL: $failure" -ForegroundColor Red }
    Write-Host "Window-plan deterministic tests failed with $($failures.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Safe-window bounds and best-hit probability geometry tests passed.' -ForegroundColor Green
Write-Host 'Safe = latest restock to earliest sellout; Best Hit = highest empirical overlap when no nontrivial safe overlap exists.'
exit 0
