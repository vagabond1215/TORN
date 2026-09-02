$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$runUpdate=Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1')
$windowPlan=Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot '@Resources\Scripts\WindowPlan.ps1')
$refiner=Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot '@Resources\Scripts\WindowPlanRefiner.ps1')
$opportunity=Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot '@Resources\Scripts\OpportunityState.ps1')
$filterState=Get-Content -Raw -LiteralPath (Join-Path $ProjectRoot '@Resources\Scripts\FilterState.ps1')

function Assert-Contains([string]$Text,[string]$Needle,[string]$Message) { if (-not $Text.Contains($Needle)) { throw $Message } }
function Assert-NotContains([string]$Text,[string]$Needle,[string]$Message) { if ($Text.Contains($Needle)) { throw $Message } }

Assert-Contains $runUpdate "`$WindowPlan = Join-Path `$PSScriptRoot 'WindowPlan.ps1'" 'RunUpdate must retain WindowPlan as the authoritative legacy stage.'
Assert-NotContains $runUpdate "`$WindowPlanRefiner =" 'RunUpdate must not expose a second competing legacy producer.'
Assert-NotContains $filterState 'WindowPlanRefiner.ps1' 'FilterState must not run a second legacy timing producer.'
Assert-Contains $windowPlan "& (Join-Path `$PSScriptRoot 'WindowPlanRefiner.ps1') -Now `$Now" 'WindowPlan must explicitly delegate to the richer implementation.'
Assert-Contains $refiner "`$state['LegacyWindowPlanAuthority']='WindowPlan'" 'Authoritative stage must stamp its ownership.'
Assert-Contains $opportunity "`$State['LegacyWindowPlanAuthority'] = ''" 'OpportunityState must clear the authority stamp before each generation so a fail-soft window error cannot leave stale ownership metadata.'
Assert-Contains $refiner "`$state[`$prefix+'WindowDataQualityReason']='window evidence was not evaluated'" 'Every projected row must initialize generation-scoped timing state before fast paths.'

foreach ($suffix in @(
    'CurrentStock','StockEvidenceAt','ActiveRestockAt','ActiveSelloutEstimateAt','NextRestockEstimateAt',
    'MedianRestockDelaySeconds','LiveCycleProjectionMode','WindowDataQuality','WindowDataQualityReason',
    'CurrentCycleReachable','CurrentCycleLeaveDeadlineAt','CurrentCycleSafetyMarginSeconds','NextCycleOrdinal','WindowMedianPeriodSeconds'
)) {
    Assert-Contains $opportunity ("'"+$suffix+"'") ("OpportunityState does not clear legacy timing field '"+$suffix+"'.")
}

Write-Host 'Authoritative legacy WindowPlan ownership and stale-field clearing contract passed.' -ForegroundColor Green
exit 0
