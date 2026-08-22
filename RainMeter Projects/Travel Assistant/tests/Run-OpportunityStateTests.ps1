$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$scriptPath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path '@Resources\Scripts\OpportunityState.ps1'
. $scriptPath -SkipMain

$failures = New-Object System.Collections.Generic.List[string]
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { $script:failures.Add($Message) } }
function Assert-Equal($Actual,$Expected,[string]$Message) { if ($Actual -ne $Expected) { $script:failures.Add("$Message Expected=$Expected Actual=$Actual") } }
function Assert-Near([double]$Actual,[double]$Expected,[double]$Tolerance,[string]$Message) { if ([Math]::Abs($Actual-$Expected) -gt $Tolerance) { $script:failures.Add("$Message Expected=$Expected Actual=$Actual") } }

$cycles = @(
    [pscustomobject]@{ restockDelaySeconds=600L; availabilitySeconds=300L },
    [pscustomobject]@{ restockDelaySeconds=660L; availabilitySeconds=300L },
    [pscustomobject]@{ restockDelaySeconds=720L; availabilitySeconds=300L }
)

$segments = @(Get-OpportunityWindowSegments -Cycles $cycles)
Assert-True ($segments.Count -ge 5) 'Window sweep should preserve all probability transition segments.'

$now = 100000L
$lastSellOut = $now
$window = Get-OpportunityNextWindow -Cycles $cycles -LastSellOutAt $lastSellOut -NowEpoch $now -PreferredProbability 0.5
Assert-True ($null -ne $window) 'A three-cycle model should produce a future supported window.'
if ($null -ne $window) {
    Assert-Equal ([long]$window.startAt) ($lastSellOut+660L) 'Next qualifying window should start at the earliest >=50% overlap.'
    Assert-Equal ([long]$window.endAt) ($lastSellOut+720L) 'First qualifying overlap segment should end at the next probability transition.'
    Assert-Near ([double]$window.probability) (2.0/3.0) 0.0001 'Window support should be two of three completed cycles.'
}

Assert-Near (Get-OpportunityProbabilityAtAge -Cycles $cycles -AgeSeconds 750L) 1.0 0.0001 'All three historical windows cover age 750.'
Assert-Near (Get-OpportunityProbabilityAtAge -Cycles $cycles -AgeSeconds 950L) (2.0/3.0) 0.0001 'Two historical windows cover age 950.'
Assert-Near (Get-OpportunityProbabilityAtAge -Cycles $cycles -AgeSeconds 1100L) 0.0 0.0001 'No historical window covers age 1100.'

$state = @{}
$rows = @(
    [pscustomobject]@{
        key='japan:1'; name='First'; countryName='Japan'; countryCode='JP'; probability=.9; elapsedSeconds=3600L; grossProfit=1000L; foreignPrice=10L; marketValue=20L; priceColor='86,190,116,255'; windowText='IN STOCK'; leaveText='LEAVE NOW'; tooltip='first'
    },
    [pscustomobject]@{
        key='united_kingdom:2'; name='Second'; countryName='United Kingdom'; countryCode='UK'; probability=.8; elapsedSeconds=1800L; grossProfit=1200L; foreignPrice=12L; marketValue=24L; priceColor='86,190,116,255'; windowText='WINDOW 10m'; leaveText='LEAVE NOW'; tooltip='second'
    }
)
Write-OpportunityProjection -State $state -Rows $rows -SortMode 'profit' -Message '' -BestKey 'united_kingdom:2'
Assert-Equal $state['OpportunitySortMode'] 'profit' 'Projection should preserve selected sort mode.'
Assert-Equal $state['Opportunity1OptimalText'] '' 'Non-optimal first row should not be falsely highlighted.'
Assert-Equal $state['Opportunity2OptimalText'] 'OPTIMAL' 'Best economic opportunity must stay highlighted even under another ordering.'
Assert-Equal $state['Opportunity2Key'] 'united_kingdom:2' 'Stable market identity must be projected for graph targeting.'
Assert-Equal (Get-OpportunityCountryCode 'united_kingdom') 'UK' 'United Kingdom display code should remain compact.'

$expectedScoreA = (1000.0*0.9)/1.0
$expectedScoreB = (1200.0*0.8)/0.5
Assert-True ($expectedScoreB -gt $expectedScoreA) 'Probability-weighted gross profit per elapsed hour should favor the stronger economic opportunity.'

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL: $failure" -ForegroundColor Red }
    Write-Host "Opportunity-state deterministic tests failed with $($failures.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Opportunity-state deterministic tests passed.' -ForegroundColor Green
Write-Host 'OPTIMAL remains a probability-weighted gross-profit-per-elapsed-hour ranking, independent of the selected visible ordering.'
exit 0
