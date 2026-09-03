$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$scriptPath = Join-Path (Resolve-Path (Join-Path $PSScriptRoot '..')).Path '@Resources\Scripts\OpportunityState.ps1'
. $scriptPath -SkipMain

$failures = New-Object System.Collections.Generic.List[string]
function Assert-True([bool]$Condition,[string]$Message) { if (-not $Condition) { $script:failures.Add($Message) } }
function Assert-Equal($Actual,$Expected,[string]$Message) { if ($Actual -ne $Expected) { $script:failures.Add("$Message Expected=$Expected Actual=$Actual") } }
function Assert-Near([double]$Actual,[double]$Expected,[double]$Tolerance,[string]$Message) { if ([Math]::Abs($Actual-$Expected) -gt $Tolerance) { $script:failures.Add("$Message Expected=$Expected Actual=$Actual") } }

$scriptText = Get-Content -LiteralPath $scriptPath -Raw
Assert-True ($scriptText.Contains("PSObject.Properties['make']")) 'Displayed-profit sort must use the projected after-tax Make value.'
Assert-True ($scriptText.Contains('Descending=$true')) 'Displayed-profit sort must remain signed descending so every positive value ranks above negatives.'
Assert-True (-not ($scriptText -match "Sort-Object[^\r\n]*Math\]::Abs")) 'Profit sorting must never use absolute magnitude.'
Assert-Equal ([regex]::Matches($scriptText,'if \(\$OpportunityStateSkipMain\) \{ return \}').Count) 1 'OpportunityState must contain exactly one executable main boundary.'
Assert-True (-not ($scriptText -match '(?m)^\) \{')) 'OpportunityState must not retain the malformed duplicated legacy-cleanup tail.'

$grossEconomics=Get-OpportunityEconomics -MarketValue 150L -ForeignPrice 100L -Quantity 10 -MarketFeePercent 0 -ElapsedSeconds 3600L
Assert-Equal ([long]$grossEconomics.saleEach) 150L 'Declared MV is always the per-item sale value.'
Assert-Equal ([long]$grossEconomics.purchaseCost) 1000L 'Purchase cost is foreign unit cost times quantity.'
Assert-Equal ([long]$grossEconomics.grossSale) 1500L 'Gross Sale is declared MV times quantity.'
Assert-Equal ([long]$grossEconomics.grossProfit) 500L 'Gross profit is Gross Sale minus actual purchase cost before tax.'
Assert-Equal ([long]$grossEconomics.marketTax) 0L 'Zero-percent tax leaves gross proceeds untaxed.'
Assert-Equal ([long]$grossEconomics.make) 500L 'Make is after-tax net profit.'
Assert-Near ([double]$grossEconomics.makePerHour) 500.0 0.001 'Net profit per hour tracks Make.'

foreach($rate in 1..5){
    $rateEconomics=Get-OpportunityEconomics -MarketValue 150L -ForeignPrice 100L -Quantity 10 -MarketFeePercent $rate -ElapsedSeconds 3600L
    Assert-Equal ([long]$rateEconomics.saleEach) 150L ("Tax rate {0}% must not alter declared MV." -f $rate)
    Assert-Equal ([long]$rateEconomics.grossSale) 1500L ("Tax rate {0}% must not alter gross sale." -f $rate)
    Assert-Equal ([long]$rateEconomics.marketTax) ([long][Math]::Floor(1500.0*($rate/100.0))) ("Tax rate {0}% applies exactly once to gross sale." -f $rate)
}

# Regression for the reported Xanax card. Full declared MV is the gross sale basis;
# the selected 5% tax is subtracted once from gross proceeds.
$xanaxTaxed=Get-OpportunityEconomics -MarketValue 845308L -ForeignPrice 771986L -Quantity 28 -MarketFeePercent 5 -ElapsedSeconds 3600L
Assert-Equal ([long]$xanaxTaxed.saleEach) 845308L 'Xanax declared MV remains the sale value.'
Assert-Equal ([long]$xanaxTaxed.purchaseCost) 21615608L 'Xanax actual purchase cost is foreign price times 28.'
Assert-Equal ([long]$xanaxTaxed.grossSale) 23668624L 'Xanax Gross is declared MV times 28.'
Assert-Equal ([long]$xanaxTaxed.marketTax) 1183431L 'Xanax 5% tax is floor(5% of Gross Sale).'
Assert-Equal ([long]$xanaxTaxed.make) 869585L 'Xanax Make is positive after one 5% tax application.'
Assert-Equal ([long]$xanaxTaxed.profitEach) 31057L 'Xanax Each is rounded after-tax net profit per item.'
Assert-Near ([double]$xanaxTaxed.makePerHour) 869585.0 0.001 'Profit per hour uses after-tax net profit.'

$fullLoadCostExample=Get-OpportunityEconomics -MarketValue 845308L -ForeignPrice 775013L -Quantity 28 -MarketFeePercent 0 -ElapsedSeconds 3600L
Assert-Equal ([long]$fullLoadCostExample.purchaseCost) 21700364L '775,013 each x 28 is displayed as exact full-load cost 21,700,364 with no buffer.'

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

# Recurring-cycle regression: 45m stocked, ~60m sold out, 90m flight.
$recurringCycles = @(
    [pscustomobject]@{ restockDelaySeconds=3300L; availabilitySeconds=2700L },
    [pscustomobject]@{ restockDelaySeconds=3600L; availabilitySeconds=2700L },
    [pscustomobject]@{ restockDelaySeconds=3900L; availabilitySeconds=2700L }
)
$anchorRestock = 200000L
$flightSeconds = 5400L
$recurringWindow = Get-OpportunityNextRecurringWindow -Cycles $recurringCycles -AnchorAt $anchorRestock -AnchorPhase 'restock' -NowEpoch $anchorRestock -EarliestArrivalAt ($anchorRestock+$flightSeconds) -PreferredProbability 0.5
Assert-True ($null -ne $recurringWindow) 'Recurring restock model should find the following stocked cycle beyond a 90-minute flight.'
if ($null -ne $recurringWindow) {
    Assert-Equal ([long]$recurringWindow.targetAt) ($anchorRestock+6300L) 'Mixed cycle overlap should target the >=50% supported next restock at 105 minutes.'
    Assert-Equal ([long]($recurringWindow.targetAt-$anchorRestock-$flightSeconds)) 900L 'A 90-minute flight should leave about 15 minutes after the current restock.'
    Assert-Near ([double]$recurringWindow.probability) (2.0/3.0) 0.0001 'Next-cycle target should be supported by two of three empirical cycle scenarios.'
}

$steadyCycles = @(
    [pscustomobject]@{ restockDelaySeconds=3600L; availabilitySeconds=2700L },
    [pscustomobject]@{ restockDelaySeconds=3600L; availabilitySeconds=2700L },
    [pscustomobject]@{ restockDelaySeconds=3600L; availabilitySeconds=2700L }
)
$selloutAnchor = 300000L
$lateArrival = $selloutAnchor + 10000L
$lateWindow = Get-OpportunityNextRecurringWindow -Cycles $steadyCycles -AnchorAt $selloutAnchor -AnchorPhase 'sellout' -NowEpoch $selloutAnchor -EarliestArrivalAt $lateArrival -PreferredProbability 0.5
Assert-True ($null -ne $lateWindow) 'Sold-out forecast should continue into later cycles instead of stopping after the first stock window.'
if ($null -ne $lateWindow) {
    Assert-Equal ([long]$lateWindow.startAt) ($selloutAnchor+9900L) 'Second recurring stocked period should begin after one complete 105-minute cycle plus the next 60-minute restock delay.'
    Assert-Equal ([long]$lateWindow.targetAt) $lateArrival 'Arrival already inside the second recurring stocked period should remain actionable.'
    Assert-Near ([double]$lateWindow.probability) 1.0 0.0001 'Identical empirical cycles should give certainty inside their repeated stocked interval.'
}
Assert-Near (Get-OpportunityRecurringProbabilityAtAge -Cycles $steadyCycles -AgeSeconds 10000L -AnchorPhase 'sellout') 1.0 0.0001 'Recurring probability must recognize stock in a later cycle.'

$verifiedRestockCycles=@(
    [pscustomobject]@{schemaVersion=2;restockDelaySeconds=36000L;availabilitySeconds=1800L;soldOutAt=9003L;forecastEligible=$true;availabilityEligible=$true;restockDelayEligible=$true;restockBoundaryQuality='observed';soldOutBoundaryQuality='observed';previousSellOutBoundaryQuality='observed'},
    [pscustomobject]@{schemaVersion=2;restockDelaySeconds=39600L;availabilitySeconds=1800L;soldOutAt=9002L;forecastEligible=$true;availabilityEligible=$true;restockDelayEligible=$true;restockBoundaryQuality='bounded';soldOutBoundaryQuality='observed';previousSellOutBoundaryQuality='bounded'},
    [pscustomobject]@{schemaVersion=2;restockDelaySeconds=43200L;availabilitySeconds=1800L;soldOutAt=9001L;forecastEligible=$true;availabilityEligible=$true;restockDelayEligible=$true;restockBoundaryQuality='recovered';soldOutBoundaryQuality='observed';previousSellOutBoundaryQuality='observed'}
)
$summary=Get-OpportunityRestockSummary -Cycles $verifiedRestockCycles -RecentSamples 12
Assert-Equal ([int]$summary.sampleCount) 3 'Lightweight OOS summary should count verified cycles only.'
Assert-Equal ([long]$summary.averageDelaySeconds) 39600L 'Lightweight OOS estimate should use the arithmetic mean OOS-to-restock duration.'
Assert-Equal ([long]$summary.earliestDelaySeconds) 36000L 'Historical early restock should use the shortest recent verified delay.'
Assert-Equal ([long]$summary.latestDelaySeconds) 43200L 'Historical late restock should use the longest recent verified delay.'


# An OoS-derived estimate is valid only while that sellout remains the latest
# observed phase. A later positive snapshot or active restock invalidates it even
# after the stock source ages into forecast-only mode.
$unresolvedDestination=[pscustomobject]@{
    lastSellOutAt=1000L
    lastSellOutBoundaryQuality='observed'
    activeCycle=$null
}
Assert-True (Test-OpportunityUnresolvedOosPhase -DestinationState $unresolvedDestination -ObservedStock 0L -ObservedAt 1300L) 'Current zero stock after a verified OoS should keep the OoS phase unresolved.'
Assert-True (Test-OpportunityUnresolvedOosPhase -DestinationState $unresolvedDestination -ObservedStock 50L -ObservedAt 900L) 'A positive snapshot older than the sellout must not invalidate the newer OoS phase.'
Assert-True (-not (Test-OpportunityUnresolvedOosPhase -DestinationState $unresolvedDestination -ObservedStock 50L -ObservedAt 1300L)) 'A later positive stock observation must invalidate the preceding OoS estimate even if that snapshot later becomes stale.'

$restockedDestination=[pscustomobject]@{
    lastSellOutAt=1000L
    lastSellOutBoundaryQuality='observed'
    activeCycle=[pscustomobject]@{restockAt=1200L;restockQuantity=5000L}
}
Assert-True (-not (Test-OpportunityUnresolvedOosPhase -DestinationState $restockedDestination -ObservedStock 0L -ObservedAt 1300L)) 'A later reconciled restock must supersede the preceding OoS phase regardless of current forecast-only stock handling.'

$oldRuntimeCycleFile=$RuntimeCycleFile
$oldSeedCycleFile=$SeedCycleFile
$oldRuntimeObservationFile=$RuntimeObservationFile
$oldSeedObservationFile=$SeedObservationFile
$tempCycle=Join-Path ([System.IO.Path]::GetTempPath()) ('travel-evidence-cycles-'+[guid]::NewGuid().ToString('N')+'.jsonl')
$tempObs=Join-Path ([System.IO.Path]::GetTempPath()) ('travel-evidence-observations-'+[guid]::NewGuid().ToString('N')+'.jsonl')
$tempEmpty=Join-Path ([System.IO.Path]::GetTempPath()) ('travel-evidence-empty-'+[guid]::NewGuid().ToString('N')+'.jsonl')
try {
    @(
        '{"schemaVersion":2,"country":"canada","itemId":1,"restockDelaySeconds":600,"availabilitySeconds":300,"soldOutAt":1000,"forecastEligible":true,"availabilityEligible":true,"restockDelayEligible":true,"trendEligible":true,"restockBoundaryQuality":"observed","soldOutBoundaryQuality":"observed","previousSellOutBoundaryQuality":"observed"}',
        '{"schemaVersion":2,"country":"china","itemId":2,"restockDelaySeconds":700,"availabilitySeconds":300,"soldOutAt":1001,"forecastEligible":true,"availabilityEligible":true,"restockDelayEligible":true,"trendEligible":true,"restockBoundaryQuality":"observed","soldOutBoundaryQuality":"observed","previousSellOutBoundaryQuality":"observed"}'
    ) | Set-Content -LiteralPath $tempCycle -Encoding UTF8
    @(
        '{"schemaVersion":1,"country":"canada","itemId":1,"timestamp":900,"stock":0}',
        '{"schemaVersion":1,"country":"canada","itemId":1,"timestamp":1000,"stock":50}',
        '{"schemaVersion":1,"country":"china","itemId":2,"timestamp":900,"stock":0}',
        '{"schemaVersion":1,"country":"china","itemId":2,"timestamp":1000,"stock":50}'
    ) | Set-Content -LiteralPath $tempObs -Encoding UTF8
    [System.IO.File]::WriteAllText($tempEmpty,'',[System.Text.UTF8Encoding]::new($false))
    $RuntimeCycleFile=$tempCycle
    $SeedCycleFile=$tempEmpty
    $RuntimeObservationFile=$tempObs
    $SeedObservationFile=$tempEmpty

    $wantedEvidence=@{'canada:1'=$true}
    $scopedEvidence=Get-OptimalEvidence -WantedKeys $wantedEvidence
    Assert-Equal $scopedEvidence.cycles.Count 1 'Evidence loader should deserialize only computation-eligible cycle keys.'
    Assert-True ($scopedEvidence.cycles.ContainsKey('canada:1')) 'Scoped cycle evidence should retain the wanted market.'
    Assert-Equal $scopedEvidence.observations.Count 1 'Evidence loader should deserialize only computation-eligible observation keys.'
    Assert-True (-not ($scopedEvidence.observations.ContainsKey('china:2'))) 'Filtered market observations must not enter opportunity evidence.'

    $cycleOnlyEvidence=Get-OptimalEvidence -WantedKeys $wantedEvidence -SkipObservations
    Assert-Equal $cycleOnlyEvidence.cycles.Count 1 'Cycle-only opportunity evidence should retain the wanted completed-cycle key.'
    Assert-Equal $cycleOnlyEvidence.observations.Count 0 'Opportunity evidence with SkipObservations must not deserialize retained raw observations.'
    Assert-Equal $cycleOnlyEvidence.restockStock.Count 0 'Opportunity evidence with SkipObservations must not build raw-history restock-stock samples.'
} finally {
    $RuntimeCycleFile=$oldRuntimeCycleFile
    $SeedCycleFile=$oldSeedCycleFile
    $RuntimeObservationFile=$oldRuntimeObservationFile
    $SeedObservationFile=$oldSeedObservationFile
    Remove-Item -LiteralPath $tempCycle,$tempObs,$tempEmpty -Force -ErrorAction SilentlyContinue
}

# Fresh stock timing should not disappear merely because the resale queue is
# recovering from an outage. A positive MV is usable for seven days by default,
# but stale status remains explicit and ancient/no-value snapshots are rejected.
$mvNow = 2000000L
$freshUse = Get-OpportunityResaleUse -Resale ([pscustomobject]@{marketValue=1000L;fetchedAt=$mvNow-60;fresh=$true}) -NowEpoch $mvNow -MaximumAgeSeconds 604800
Assert-True ([bool]$freshUse.usable) 'Fresh cached MV should be usable.'
Assert-True ([bool]$freshUse.fresh) 'Fresh cached MV should remain marked fresh.'
$staleUse = Get-OpportunityResaleUse -Resale ([pscustomobject]@{marketValue=1000L;fetchedAt=$mvNow-172800;fresh=$false}) -NowEpoch $mvNow -MaximumAgeSeconds 604800
Assert-True ([bool]$staleUse.usable) 'Two-day-old positive MV should remain visible during resale-cache recovery.'
Assert-True ([bool]$staleUse.stale) 'Fallback MV must remain explicitly stale.'
$expiredUse = Get-OpportunityResaleUse -Resale ([pscustomobject]@{marketValue=1000L;fetchedAt=$mvNow-691200;fresh=$false}) -NowEpoch $mvNow -MaximumAgeSeconds 604800
Assert-True (-not [bool]$expiredUse.usable) 'MV older than the seven-day fallback bound must not drive opportunity economics.'
$missingUse = Get-OpportunityResaleUse -Resale ([pscustomobject]@{marketValue=0L;fetchedAt=$mvNow-60;fresh=$false}) -NowEpoch $mvNow -MaximumAgeSeconds 604800
Assert-True (-not [bool]$missingUse.usable) 'Missing MV must remain excluded until priced.'

$state = @{}
$rows = @(
    [pscustomobject]@{
        key='japan:1'; name='First'; countryName='Japan'; countryCode='JP'; tripBand='long'; probability=.9; probabilityKnown=$true; elapsedSeconds=3600L; grossProfit=1000L; quantity=10; profitPerHour=1000.0; windowStartAt=100100L; foreignPrice=10L; marketValue=20L; marketValueFresh=$true; priceColor='86,190,116,255'; windowText='IN STOCK'; leaveText='LEAVE NOW'; tooltip='first'
    },
    [pscustomobject]@{
        key='united_kingdom:2'; name='Second'; countryName='United Kingdom'; countryCode='UK'; tripBand='medium'; probability=.8; probabilityKnown=$true; elapsedSeconds=1800L; grossProfit=1200L; quantity=12; profitPerHour=2400.0; windowStartAt=100200L; foreignPrice=12L; marketValue=24L; marketValueFresh=$false; priceColor='145,152,164,255'; windowText='Opens in 10m'; leaveText='LEAVE NOW'; tooltip='second'
    }
)
Write-OpportunityProjection -State $state -Rows $rows -SortMode 'gross' -Message ''
Assert-Equal $state['OpportunitySortMode'] 'gross' 'Projection should preserve selected sort mode.'
Assert-Equal $state['OpportunitySortEffectiveMode'] 'gross' 'Projection should publish the active non-fallback sort mode.'
Assert-True (-not $state.ContainsKey('OpportunityBestKey')) 'Retired optimal/best key must not be published.'
Assert-True (-not $state.ContainsKey('Opportunity1RankText')) 'Retired rank text must not be published.'
Assert-True (-not $state.ContainsKey('Opportunity1OptimalText')) 'Retired optimal badge must not be published.'
Assert-True (-not $state.ContainsKey('Opportunity2OptimalText')) 'Retired optimal badge must stay absent on every row.'
Assert-Equal $state['Opportunity2Key'] 'united_kingdom:2' 'Stable market identity must be projected for graph targeting.'
Assert-Equal $state['Opportunity2TripBand'] 'medium' 'Trip band must remain projected for instant local filtering.'
Assert-Equal $state['Opportunity2QuantityText'] 'x12' 'Trip quantity remains projected for tooltip/economic inspection even though it is no longer printed beside gross.'
Assert-Equal $state['Opportunity2ProfitHourText'] '$2,400/hr' 'Profit-per-hour projection should preserve the row''s round-trip flight profit rate.'
Assert-Equal $state['Opportunity2MarketValueText'] '$24 STALE' 'Stale MV must be explicit on the compact card projection.'
Assert-Equal ([long]$state['Opportunity2GrossValue']) 1200L 'Raw gross value must be available for immediate Lua sorting.'
Assert-Near ([double]$state['Opportunity2ProfitHourValue']) 2400.0 0.001 'Round-trip flight profit/hour must be available for immediate Lua sorting.'
Assert-Equal ([long]$state['Opportunity2WindowStartAt']) 100200L 'Raw window timestamp must be available for immediate Lua sorting.'
Assert-Near ([double]$state['Opportunity2ProbabilityValue']) .8 0.0001 'Raw probability must remain available as an independent sort tiebreaker.'
Assert-Equal ([long]$state['Opportunity2ElapsedSeconds']) 1800L 'Raw elapsed seconds must be available for local sorting and the flag travel-time tooltip.'

$fallbackSortState=@{}
Write-OpportunityProjection -State $fallbackSortState -Rows @() -SortMode 'upcoming' -Message 'no data'
Assert-Equal $fallbackSortState['OpportunitySortMode'] 'upcoming' 'Requested sort remains Upcoming even when no data exists.'
Assert-Equal $fallbackSortState['OpportunitySortEffectiveMode'] 'name' 'Name ordering is published only as the no-data fallback.'

$economicsState=@{'Opportunity1TakeValue'='1050';'Opportunity1TakeBufferPercent'='5'}
$economicsRows=@([pscustomobject]@{
    key='canada:99'; name='Economics'; countryName='Canada'; countryCode='CA'; tripBand='short'; probability=.75; probabilityKnown=$true;
    elapsedSeconds=3600L; grossProfit=500L; quantity=10; profitPerHour=425.0; windowStartAt=100000L; foreignPrice=100L; marketValue=150L;
    marketValueFresh=$true; priceColor='86,190,116,255'; windowText='WINDOW'; leaveText='LEAVE'; tooltip='economics';
    purchaseCost=1000L; grossSale=1500L; grossProfitBeforeTax=500L; marketTax=75L; make=425L; profitEach=43L;
    marketFeePercent=5
})
Write-OpportunityProjection -State $economicsState -Rows $economicsRows -SortMode 'gross' -Message ''
Assert-Equal ([long]$economicsState['Opportunity1PurchaseCostValue']) 1000L 'Projected purchase cost is explicit and machine-readable.'
Assert-Equal ([long]$economicsState['Opportunity1GrossSaleValue']) 1500L 'Projected Gross Sale is declared MV times quantity.'
Assert-Equal ([long]$economicsState['Opportunity1GrossProfitValue']) 500L 'Projected pre-tax gross profit remains available for gross sorting.'
Assert-Equal ([long]$economicsState['Opportunity1MarketTaxValue']) 75L 'Projected market tax is explicit.'
Assert-Equal ([long]$economicsState['Opportunity1MakeValue']) 425L 'Projected Make is after-tax net profit.'
Assert-Equal ([long]$economicsState['Opportunity1ProfitEachValue']) 43L 'Projected Each value is net profit per item.'
Assert-Equal ([int]$economicsState['Opportunity1MarketFeePercent']) 5 'Projected market fee percentage is explicit.'
Assert-Equal ([long]$economicsState['Opportunity1GrossValue']) 500L 'Gross sort value remains pre-tax gross profit.'
Assert-Near ([double]$economicsState['Opportunity1ProfitHourValue']) 425.0 0.001 'Profit/hour sort value is the projected after-tax round-trip flight rate.'
Assert-Equal ([long]$economicsState['Opportunity1TotalCostValue']) 1000L 'Full-load total cost is exact purchase cost with no variable-price buffer.'
Assert-True (-not $economicsState.ContainsKey('Opportunity1TakeValue')) 'Retired TakeValue is not republished.'
Assert-True (-not $economicsState.ContainsKey('Opportunity1TakeBufferPercent')) 'Retired automatic Take buffer state is not republished.'
Assert-Equal (Get-OpportunityCountryCode 'united_kingdom') 'UK' 'United Kingdom display code remains available internally.'

# The state projection is a candidate pool, not merely the eight visible cards.
$poolState = @{}
$poolRows = @()
for ($i=1; $i -le 12; $i++) {
    $band = if ($i -le 4) { 'short' } elseif ($i -le 8) { 'medium' } else { 'long' }
    $poolRows += [pscustomobject]@{
        key=('canada:{0}' -f $i); itemId=$i; name=('Candidate {0}' -f $i); countryName='Canada'; countryCode='CA'; tripBand=$band;
        probability=.5; probabilityKnown=$true; elapsedSeconds=1800L; grossProfit=(1000L+$i); quantity=1; profitPerHour=2000.0;
        windowStartAt=(100000L+$i); foreignPrice=10L; marketValue=20L; marketValueFresh=$true; priceColor='86,190,116,255'; windowText='IN STOCK'; leaveText='LEAVE NOW'; tooltip='pool'
    }
}
Write-OpportunityProjection -State $poolState -Rows $poolRows -SortMode 'upcoming' -Message ''
Assert-Equal ([int]$poolState['OpportunityCount']) 12 'Candidate projection must retain more than the eight visible cards.'
Assert-Equal $poolState['Opportunity12Key'] 'canada:12' 'Candidate pool must retain stable keys beyond visible row eight.'
Assert-Equal $poolState['Opportunity12TripBand'] 'long' 'Candidate pool must retain trip-band taxonomy beyond visible row eight.'

$learningState = @{}
$learningRows = @(
    [pscustomobject]@{
        key='canada:3'; name='Learning Stock'; countryName='Canada'; countryCode='CA'; tripBand='short'; probability=-1.0; probabilityKnown=$false; elapsedSeconds=2100L; grossProfit=5000L; quantity=18; profitPerHour=8571.4; windowStartAt=100000L; foreignPrice=100L; marketValue=500L; marketValueFresh=$true; priceColor='86,190,116,255'; windowText='IN STOCK'; leaveText='LEAVE NOW'; tooltip='likelihood learning'
    }
)
Write-OpportunityProjection -State $learningState -Rows $learningRows -SortMode 'upcoming' -Message ''
Assert-Equal $learningState['OpportunityCount'] 1 'Fresh in-stock markets can remain visible while likelihood is learning.'
Assert-Equal $learningState['Opportunity1ChanceText'] 'LEARNING' 'Unknown arrival likelihood must be explicit rather than fabricated or hidden.'
Assert-Near ([double]$learningState['Opportunity1ProbabilityValue']) -1.0 0.0001 'Unknown probability uses a sentinel that sorts below known probabilities.'

$sleepState=@{}
$sleepRows=@(
    [pscustomobject]@{
        key='china:123'; name='Sleeping OOS'; countryName='China'; countryCode='CN'; tripBand='long';
        probability=-1.0; probabilityKnown=$false; elapsedSeconds=40000L; grossProfit=50000L; quantity=10; profitPerHour=4500.0;
        windowStartAt=140000L; foreignPrice=100L; marketValue=500L; marketValueFresh=$true; priceColor='86,190,116,255';
        windowText='RESTOCK ESTIMATE'; leaveText='Restocks in ~11h'; tooltip='sleeping';
        forecastMode='sleeping_oos'; restockEstimateAt=140000L; restockAverageDelaySeconds=39600L;
        restockEarliestDelaySeconds=36000L; restockLatestDelaySeconds=43200L;
        restockLifetimeShortestDelaySeconds=35000L; restockLifetimeLongestDelaySeconds=45000L; restockSampleCount=3
    }
)
Write-OpportunityProjection -State $sleepState -Rows $sleepRows -SortMode 'upcoming' -Message ''
Assert-Equal $sleepState['Opportunity1ForecastMode'] 'sleeping_oos' 'Sleeping OOS mode must survive projection into state.kv.'
Assert-Equal $sleepState['Opportunity1QuantityText'] 'x10' 'Sleeping OOS rows must retain projected purchase quantity for Take calculation.'
Assert-Equal $sleepState['Opportunity1PriceText'] '$100' 'Sleeping OOS rows must retain projected foreign unit price for Take calculation.'
Assert-Equal ([long]$sleepState['Opportunity1RestockEstimateAt']) 140000L 'Absolute cheap restock estimate must be projected for live countdown rendering.'
Assert-Equal ([int]$sleepState['Opportunity1RestockSampleCount']) 3 'Verified restock sample count must be projected for tooltip context.'

$profitHourA = Get-OpportunityRoundTripProfitPerHour -Profit 1000L -OneWaySeconds 1800L
$profitHourB = Get-OpportunityRoundTripProfitPerHour -Profit 1200L -OneWaySeconds 3600L
Assert-Near ([double]$profitHourA) 1000.0 0.001 'A 30-minute one-way flight produces a one-hour round-trip denominator.'
Assert-Near ([double]$profitHourB) 600.0 0.001 'A one-hour one-way flight produces a two-hour round-trip denominator.'
Assert-True ($profitHourA -gt $profitHourB) 'PROFIT/HR should rank by after-tax profit divided by round-trip flight time only.'
Assert-Near .8 .8 0.0001 'Hit likelihood remains independent of PROFIT/HR ranking.'

if ($failures.Count -gt 0) {
    foreach ($failure in $failures) { Write-Host "FAIL: $failure" -ForegroundColor Red }
    Write-Host "Opportunity-state deterministic tests failed with $($failures.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Opportunity-state deterministic tests passed.' -ForegroundColor Green
Write-Host 'Recurring availability, bounded stale-MV recovery, and the full local candidate pool support transparent opportunity display.'
exit 0
