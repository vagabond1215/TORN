param(
    [Alias('SkipMain')]
    [switch]$OpportunityStateSkipMain,
    [long]$Now = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$requestedNow = $Now
. (Join-Path $PSScriptRoot 'OptimalRoute.ps1') -SkipMain -Now $requestedNow
$Now = $requestedNow

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$StateKvFile = Join-Path $GeneratedDir 'state.kv'

function Format-OpportunityDuration {
    param([long]$Seconds)
    $Seconds = [Math]::Max(0,$Seconds)
    if ($Seconds -lt 60) { return '<1m' }
    $hours = [Math]::Floor($Seconds / 3600)
    $minutes = [Math]::Floor(($Seconds % 3600) / 60)
    if ($hours -gt 0) { return ('{0}h {1}m' -f $hours,$minutes) }
    return ('{0}m' -f $minutes)
}

function Format-OpportunityMoney {
    param([long]$Value)
    if ($Value -lt 0) { return ('-${0:N0}' -f [Math]::Abs($Value)) }
    return ('${0:N0}' -f $Value)
}

function Get-OpportunityEconomics {
    param(
        [long]$MarketValue,
        [long]$ForeignPrice,
        [int]$Quantity,
        [int]$MarketFeePercent,
        [long]$ElapsedSeconds
    )
    $quantity=[Math]::Max(0,$Quantity)
    $fee=[Math]::Max(0,[Math]::Min(5,$MarketFeePercent))
    # Declared/list MV is the sale price. Tax never changes MV or gross sale;
    # it is applied exactly once to gross proceeds and then subtracted for net profit.
    $saleEach=if ($MarketValue -gt 0) { [long]$MarketValue } else { 0L }
    $purchaseCost=[long]([Math]::Max(0L,$ForeignPrice)*$quantity)
    $grossSale=[long]($saleEach*$quantity)
    $grossProfit=[long]($grossSale-$purchaseCost)
    $marketTax=if ($grossSale -gt 0 -and $fee -gt 0) { [long][Math]::Floor([double]$grossSale*($fee/100.0)) } else { 0L }
    $make=[long]($grossProfit-$marketTax)
    $each=if ($quantity -gt 0) { [long][Math]::Round($make/[double]$quantity) } else { 0L }
    $hours=[Math]::Max(1.0/60.0,[Math]::Max(1L,$ElapsedSeconds)/3600.0)
    return [pscustomobject]@{
        marketFeePercent=$fee
        saleEach=$saleEach
        purchaseCost=$purchaseCost
        grossSale=$grossSale
        grossProfit=$grossProfit
        marketTax=$marketTax
        make=$make
        profitEach=$each
        grossProfitPerHour=([double]$grossProfit/$hours)
        makePerHour=([double]$make/$hours)
    }
}
function Get-OpportunityRoundTripProfitPerHour {
    param([long]$Profit,[long]$OneWaySeconds)
    if ($OneWaySeconds -le 0) { return 0.0 }
    $hours=(2.0*[double]$OneWaySeconds)/3600.0
    if ($hours -le 0) { return 0.0 }
    return ([double]$Profit/$hours)
}

function Add-OpportunityDelta {
    param([hashtable]$Map,[long]$At,[int]$Delta)
    $key = [string]$At
    if (-not $Map.ContainsKey($key)) { $Map[$key] = 0 }
    $Map[$key] = [int]$Map[$key] + $Delta
}

function Get-OpportunityWindowSegments {
    param([object[]]$Cycles)
    $usable = @($Cycles | Where-Object {
        $null -ne $_ -and
        $_.PSObject.Properties['restockDelaySeconds'] -and [long]$_.restockDelaySeconds -ge 0 -and
        $_.PSObject.Properties['availabilitySeconds'] -and [long]$_.availabilitySeconds -gt 0
    })
    if ($usable.Count -eq 0) { return @() }

    $deltas = @{}
    foreach ($cycle in $usable) {
        $start = [long]$cycle.restockDelaySeconds
        $end = $start + [long]$cycle.availabilitySeconds
        if ($end -le $start) { continue }
        Add-OpportunityDelta -Map $deltas -At $start -Delta 1
        Add-OpportunityDelta -Map $deltas -At $end -Delta -1
    }
    if ($deltas.Count -lt 2) { return @() }

    $times = [long[]]@($deltas.Keys | ForEach-Object { [long]$_ } | Sort-Object -Unique)
    $segments = New-Object System.Collections.Generic.List[object]
    $active = 0
    for ($i=0; $i -lt ($times.Count-1); $i++) {
        $at = [long]$times[$i]
        $active += [int]$deltas[[string]$at]
        $next = [long]$times[$i+1]
        if ($next -le $at -or $active -le 0) { continue }
        $segments.Add([pscustomobject]@{
            startAgeSeconds = $at
            endAgeSeconds = $next
            probability = ($active / [double]$usable.Count)
            sampleCount = $usable.Count
        })
    }
    return $segments.ToArray()
}

function Get-OpportunityNextWindow {
    param(
        [object[]]$Cycles,
        [long]$LastSellOutAt,
        [long]$NowEpoch,
        [double]$PreferredProbability = 0.5
    )
    if ($LastSellOutAt -le 0) { return $null }
    $segments = @(Get-OpportunityWindowSegments -Cycles $Cycles)
    if ($segments.Count -eq 0) { return $null }
    $currentAge = [Math]::Max(0L,$NowEpoch-$LastSellOutAt)
    $future = @($segments | Where-Object { [long]$_.endAgeSeconds -gt $currentAge })
    if ($future.Count -eq 0) { return $null }

    $qualified = @($future | Where-Object { [double]$_.probability -ge $PreferredProbability } | Sort-Object startAgeSeconds)
    $chosen = $null
    if ($qualified.Count -gt 0) { $chosen = $qualified[0] }
    else { $chosen = @($future | Sort-Object @{Expression='probability';Descending=$true},startAgeSeconds | Select-Object -First 1)[0] }

    return [pscustomobject]@{
        startAt = $LastSellOutAt + [long]$chosen.startAgeSeconds
        endAt = $LastSellOutAt + [long]$chosen.endAgeSeconds
        probability = [double]$chosen.probability
        sampleCount = [int]$chosen.sampleCount
        startAgeSeconds = [long]$chosen.startAgeSeconds
        endAgeSeconds = [long]$chosen.endAgeSeconds
    }
}

function Get-OpportunityProbabilityAtAge {
    param([object[]]$Cycles,[long]$AgeSeconds)
    $usable = @($Cycles | Where-Object {
        $null -ne $_ -and $_.PSObject.Properties['restockDelaySeconds'] -and $_.PSObject.Properties['availabilitySeconds'] -and
        [long]$_.restockDelaySeconds -ge 0 -and [long]$_.availabilitySeconds -gt 0
    })
    if ($usable.Count -eq 0) { return -1.0 }
    $hits = @($usable | Where-Object {
        $start = [long]$_.restockDelaySeconds
        $end = $start + [long]$_.availabilitySeconds
        $start -le $AgeSeconds -and $AgeSeconds -lt $end
    }).Count
    return ($hits / [double]$usable.Count)
}

function Get-OpportunityRecurringCycles {
    param([object[]]$Cycles)
    return @($Cycles | Where-Object {
        $null -ne $_ -and
        $_.PSObject.Properties['restockDelaySeconds'] -and [long]$_.restockDelaySeconds -gt 0 -and
        $_.PSObject.Properties['availabilitySeconds'] -and [long]$_.availabilitySeconds -gt 0
    })
}

function Get-OpportunityRecurringWindowSegments {
    param(
        [object[]]$Cycles,
        [ValidateSet('sellout','restock')][string]$AnchorPhase = 'sellout',
        [long]$HorizonSeconds = 86400L
    )
    $usable = @(Get-OpportunityRecurringCycles -Cycles $Cycles)
    if ($usable.Count -eq 0 -or $HorizonSeconds -le 0) { return @() }

    $deltas = @{}
    foreach ($cycle in $usable) {
        $delay = [long]$cycle.restockDelaySeconds
        $available = [long]$cycle.availabilitySeconds
        $period = $delay + $available
        if ($period -le 0) { continue }

        $start = if ($AnchorPhase -eq 'restock') { 0L } else { $delay }
        $iterations = 0
        while ($start -lt $HorizonSeconds -and $iterations -lt 2048) {
            $end = [Math]::Min($HorizonSeconds,$start+$available)
            if ($end -gt $start) {
                Add-OpportunityDelta -Map $deltas -At $start -Delta 1
                Add-OpportunityDelta -Map $deltas -At $end -Delta -1
            }
            $start += $period
            $iterations++
        }
    }
    if ($deltas.Count -lt 2) { return @() }

    $times = [long[]]@($deltas.Keys | ForEach-Object { [long]$_ } | Sort-Object -Unique)
    $segments = New-Object System.Collections.Generic.List[object]
    $active = 0
    for ($i=0; $i -lt ($times.Count-1); $i++) {
        $at = [long]$times[$i]
        $active += [int]$deltas[[string]$at]
        $next = [long]$times[$i+1]
        if ($next -le $at -or $active -le 0) { continue }
        $segments.Add([pscustomobject]@{
            startAgeSeconds = $at
            endAgeSeconds = $next
            probability = ($active / [double]$usable.Count)
            sampleCount = $usable.Count
            anchorPhase = $AnchorPhase
        })
    }
    return $segments.ToArray()
}

function Get-OpportunityRecurringProbabilityAtAge {
    param(
        [object[]]$Cycles,
        [long]$AgeSeconds,
        [ValidateSet('sellout','restock')][string]$AnchorPhase = 'sellout'
    )
    $usable = @(Get-OpportunityRecurringCycles -Cycles $Cycles)
    if ($usable.Count -eq 0) { return -1.0 }
    $age = [Math]::Max(0L,$AgeSeconds)
    $hits = 0
    foreach ($cycle in $usable) {
        $delay = [long]$cycle.restockDelaySeconds
        $available = [long]$cycle.availabilitySeconds
        $period = $delay + $available
        if ($period -le 0) { continue }
        $phase = $age % $period
        $hit = if ($AnchorPhase -eq 'restock') {
            $phase -lt $available
        } else {
            $phase -ge $delay -and $phase -lt ($delay+$available)
        }
        if ($hit) { $hits++ }
    }
    return ($hits / [double]$usable.Count)
}

function Get-OpportunityNextRecurringWindow {
    param(
        [object[]]$Cycles,
        [long]$AnchorAt,
        [ValidateSet('sellout','restock')][string]$AnchorPhase,
        [long]$NowEpoch,
        [long]$EarliestArrivalAt,
        [double]$PreferredProbability = 0.5,
        [long]$SearchHorizonSeconds = 86400L
    )
    if ($AnchorAt -le 0 -or $EarliestArrivalAt -le 0) { return $null }
    $earliestAge = [Math]::Max(0L,$EarliestArrivalAt-$AnchorAt)
    $currentAge = [Math]::Max(0L,$NowEpoch-$AnchorAt)
    $horizon = [Math]::Max($earliestAge,$currentAge) + [Math]::Max(3600L,$SearchHorizonSeconds)
    $segments = @(Get-OpportunityRecurringWindowSegments -Cycles $Cycles -AnchorPhase $AnchorPhase -HorizonSeconds ($horizon+1))
    if ($segments.Count -eq 0) { return $null }

    $future = @($segments | Where-Object { [long]$_.endAgeSeconds -gt $earliestAge })
    if ($future.Count -eq 0) { return $null }

    $qualified = @($future | Where-Object { [double]$_.probability -ge $PreferredProbability } | Sort-Object @{Expression={ [Math]::Max($earliestAge,[long]$_.startAgeSeconds) };Ascending=$true},@{Expression='probability';Descending=$true})
    $chosen = $null
    if ($qualified.Count -gt 0) {
        $chosen = $qualified[0]
    } else {
        $chosen = @($future | Sort-Object @{Expression='probability';Descending=$true},@{Expression={ [Math]::Max($earliestAge,[long]$_.startAgeSeconds) };Ascending=$true} | Select-Object -First 1)[0]
    }

    $targetAge = [Math]::Max($earliestAge,[long]$chosen.startAgeSeconds)
    return [pscustomobject]@{
        startAt = $AnchorAt + [long]$chosen.startAgeSeconds
        targetAt = $AnchorAt + $targetAge
        endAt = $AnchorAt + [long]$chosen.endAgeSeconds
        probability = [double]$chosen.probability
        sampleCount = [int]$chosen.sampleCount
        startAgeSeconds = [long]$chosen.startAgeSeconds
        targetAgeSeconds = [long]$targetAge
        endAgeSeconds = [long]$chosen.endAgeSeconds
        anchorPhase = $AnchorPhase
    }
}

function Test-OpportunityBoundaryQuality {
    param([string]$Quality)
    return (([string]$Quality).Trim().ToLowerInvariant() -in @('observed','bounded','recovered'))
}

function Get-OpportunityRestockSummary {
    param([object[]]$Cycles,[int]$RecentSamples = 12)

    $usable=@($Cycles | Where-Object {
        $null -ne $_ -and
        $_.PSObject.Properties['restockDelaySeconds'] -and [long]$_.restockDelaySeconds -gt 0 -and
        (Test-CycleForecastBoundaryEvidence -Cycle $_ -Purpose Forecast)
    } | Sort-Object @{Expression={ if ($_.PSObject.Properties['soldOutAt']) { [long]$_.soldOutAt } else { 0L } };Descending=$true})
    if ($usable.Count -eq 0) { return $null }

    $recent=@($usable)
    if ($RecentSamples -gt 0 -and $recent.Count -gt $RecentSamples) { $recent=@($recent | Select-Object -First $RecentSamples) }
    $recentDelays=[long[]]@($recent | ForEach-Object { [long]$_.restockDelaySeconds })
    $lifetimeDelays=[long[]]@($usable | ForEach-Object { [long]$_.restockDelaySeconds })
    $average=[long][Math]::Round([double]($recentDelays | Measure-Object -Average).Average)
    return [pscustomobject]@{
        sampleCount=[int]$recent.Count
        averageDelaySeconds=$average
        earliestDelaySeconds=[long]($recentDelays | Measure-Object -Minimum).Minimum
        latestDelaySeconds=[long]($recentDelays | Measure-Object -Maximum).Maximum
        lifetimeShortestDelaySeconds=[long]($lifetimeDelays | Measure-Object -Minimum).Minimum
        lifetimeLongestDelaySeconds=[long]($lifetimeDelays | Measure-Object -Maximum).Maximum
    }
}

function Get-OpportunityEligibleEvidenceKeys {
    param(
        [object]$Engine,
        [object]$Countries,
        [object]$Preferences,
        [string]$FixedCountry,
        [long]$NowEpoch,
        [long]$ResaleFallbackMaxAgeSeconds
    )
    $wanted=@{}
    if ($null -eq $Engine -or $null -eq $Countries -or -not $Engine.PSObject.Properties['observedMarkets']) { return $wanted }
    $countryMap=@{}
    foreach ($country in @($Countries.countries | Where-Object { $_.collect -eq $true })) {
        $countryMap[[string]$country.id]=$country
    }
    foreach ($property in @($Engine.observedMarkets.PSObject.Properties)) {
        $market=$property.Value
        if ($null -eq $market) { continue }
        $countryId=[string](Get-OptimalProperty $market 'country')
        if (-not $countryMap.ContainsKey($countryId)) { continue }
        $country=$countryMap[$countryId]
        $tripBand=[string]$country.tripBand
        if (-not [string]::IsNullOrWhiteSpace($FixedCountry) -and $countryId -ne $FixedCountry) { continue }
        if (@($Preferences.displayTripBands) -notcontains $tripBand) { continue }
        if (@($Preferences.selectedCountryIds) -notcontains $countryId) { continue }
        $itemId=[int](Get-OptimalProperty $market 'itemId')
        if ($itemId -le 0) { continue }
        $metadata=Get-OptimalMarketMetadata -Engine $Engine -ItemId $itemId -Market $market
        if (-not (Test-OptimalMarketFilters -Preferences $Preferences -CountryId $countryId -TripBand $tripBand -ItemId $itemId -Category ([string]$metadata.category))) { continue }

        if ([bool]$Preferences.showProfitableOnly) {
            $resale=Get-OptimalResaleSnapshot -Engine $Engine -ItemId $itemId -NowEpoch $NowEpoch
            $resaleUse=Get-OpportunityResaleUse -Resale $resale -NowEpoch $NowEpoch -MaximumAgeSeconds $ResaleFallbackMaxAgeSeconds
            if (-not [bool]$resaleUse.usable) { continue }
            $foreignPrice=[long](Get-OptimalProperty $market 'lastForeignPrice')
            if ($foreignPrice -le 0 -or [long]$resaleUse.marketValue -le $foreignPrice) { continue }
        }

        $wanted[($countryId+':'+[string]$itemId).ToLowerInvariant()]=$true
    }
    return $wanted
}

function Get-OpportunityActiveRestockAt {
    param([object]$DestinationState)
    if ($null -eq $DestinationState) { return 0L }
    $activeCycle = Get-OptimalProperty $DestinationState 'activeCycle'
    if ($null -eq $activeCycle -or -not $activeCycle.PSObject.Properties['restockAt']) { return 0L }
    return [Math]::Max(0L,[long]$activeCycle.restockAt)
}

function Get-OpportunityCountryCode {
    param([string]$CountryId)
    $map = @{
        mexico='MX'; cayman_islands='KY'; canada='CA'; hawaii='HI'; united_kingdom='UK'; argentina='AR'; switzerland='CH'; japan='JP'; china='CN'; united_arab_emirates='AE'; south_africa='ZA'
    }
    if ($map.ContainsKey($CountryId)) { return [string]$map[$CountryId] }
    return $CountryId.ToUpperInvariant()
}

function Get-OpportunityWasteText {
    param([object]$Energy,[object]$Nerve)
    $parts = New-Object System.Collections.Generic.List[string]
    if ($null -ne $Energy -and [bool](Get-OptimalProperty $Energy 'bypass')) { $parts.Add('E stacked') }
    elseif ($null -ne $Energy -and [bool](Get-OptimalProperty $Energy 'known')) { $parts.Add(('E loss {0}' -f [long](Get-OptimalProperty $Energy 'loss'))) }
    else { $parts.Add('E ?') }
    if ($null -ne $Nerve -and [bool](Get-OptimalProperty $Nerve 'known')) { $parts.Add(('N loss {0}' -f [long](Get-OptimalProperty $Nerve 'loss'))) }
    else { $parts.Add('N ?') }
    return ($parts -join ', ')
}

function Get-OpportunityResaleUse {
    param([object]$Resale,[long]$NowEpoch,[long]$MaximumAgeSeconds = 604800L)
    $marketValue = 0L
    $fetchedAt = 0L
    $fresh = $false
    if ($null -ne $Resale) {
        if ($Resale.PSObject.Properties['marketValue']) { $marketValue = [long]$Resale.marketValue }
        if ($Resale.PSObject.Properties['fetchedAt']) { $fetchedAt = [long]$Resale.fetchedAt }
        if ($Resale.PSObject.Properties['fresh']) { $fresh = [bool]$Resale.fresh }
    }
    $age = [long]::MaxValue
    if ($fetchedAt -gt 0) { $age = [Math]::Max(0L,$NowEpoch-$fetchedAt) }
    $usable = ($marketValue -gt 0 -and $fetchedAt -gt 0 -and $age -le [Math]::Max(60L,$MaximumAgeSeconds))
    return [pscustomobject]@{
        marketValue = $marketValue
        fetchedAt = $fetchedAt
        ageSeconds = $age
        fresh = ($usable -and $fresh)
        stale = ($usable -and -not $fresh)
        usable = $usable
    }
}

function Get-OpportunityStockEvidenceMode {
    param(
        [long]$SourceTimestamp,
        [long]$NowEpoch,
        [long]$LiveMaximumAgeSeconds = 300L,
        [long]$ForecastMaximumAgeSeconds = 21600L
    )
    if ($SourceTimestamp -le 0) { return 'unusable' }
    $age = [Math]::Max(0L,$NowEpoch-$SourceTimestamp)
    $liveBound = [Math]::Max(60L,$LiveMaximumAgeSeconds)
    $forecastBound = [Math]::Max($liveBound,$ForecastMaximumAgeSeconds)
    if ($age -le $liveBound) { return 'live' }
    if ($age -le $forecastBound) { return 'forecast' }
    return 'unusable'
}

function Write-OpportunityProjection {
    param(
        [hashtable]$State,
        [object[]]$Rows,
        [string]$SortMode,
        [string]$Message,
        [string]$EffectiveSortMode = ''
    )

    # Keep a bounded local candidate pool in state.kv. Rainmeter renders only the
    # first eight after applying its local trip-band filter and selected sort, but
    # retaining all eligible markets here makes those controls genuinely instant.
    $maxProjectedRows = 256
    $previousCount = 0
    if ($State.ContainsKey('OpportunityCount')) { [void][int]::TryParse([string]$State['OpportunityCount'],[ref]$previousCount) }
    $projectCount = [Math]::Min($maxProjectedRows,@($Rows).Count)
    $clearCount = [Math]::Min($maxProjectedRows,[Math]::Max(8,[Math]::Max($previousCount,$projectCount)))

    if ([string]::IsNullOrWhiteSpace($EffectiveSortMode)) {
        $EffectiveSortMode = if (@($Rows).Count -eq 0) { 'name' } else { $SortMode }
    }
    $State['OpportunitySortMode'] = $SortMode
    $State['OpportunitySortEffectiveMode'] = $EffectiveSortMode
    $State['OpportunitySortText'] = if ($SortMode -eq 'gross') { 'PROFIT' } else { $SortMode.ToUpperInvariant() }
    $State['OpportunityMessage'] = $Message
    $State['OpportunityCount'] = $projectCount

    # Purge fields left by the retired ranked / OPTIMAL card surfaces instead of
    # continuing to publish blank compatibility values on every projection.
    [void]$State.Remove('OpportunityBestKey')
    foreach ($legacyKey in @($State.Keys)) {
        if ([string]$legacyKey -match '^Opportunity[0-9]+(RankText|OptimalText|TakeValue|TakeBufferPercent|SaleBasisValue|GrossProfitHourValue|MvBasisPercent)$') {
            [void]$State.Remove([string]$legacyKey)
        }
    }
    foreach ($index in 1..$clearCount) {
        foreach ($suffix in @(
            'Key','Name','Country','CountryCode','TripBand','WindowText','LeaveText','ChanceText','TimeText',
            'GrossText','QuantityText','ProfitHourText','PriceText','MarketValueText','PriceColor','AccentColor','Tooltip',
            'GrossValue','ProfitHourValue','WindowStartAt','ProbabilityValue','ElapsedSeconds',
            'MarketValueValue','PurchaseCostValue','TotalCostValue','GrossSaleValue','GrossProfitValue','MarketTaxValue','MakeValue','ProfitEachValue','MarketFeePercent',
            'ForecastMode','RestockEstimateAt','RestockAverageDelaySeconds','RestockEarliestDelaySeconds','RestockLatestDelaySeconds',
            'RestockLifetimeShortestDelaySeconds','RestockLifetimeLongestDelaySeconds','RestockSampleCount',
            # WindowPlan owns these generation-scoped legacy timing fields. Clear
            # them before every projection so an interrupted/degraded window pass
            # cannot leak a value produced for an older row or generation.
            'CurrentStock','StockEvidenceAt','ActiveRestockAt','ActiveSelloutEstimateAt','NextRestockEstimateAt',
            'MedianRestockDelaySeconds','LiveCycleProjectionMode','WindowDataQuality','WindowDataQualityReason',
            'CurrentCycleReachable','CurrentCycleLeaveDeadlineAt','CurrentCycleSafetyMarginSeconds',
            'NextCycleOrdinal','WindowMedianPeriodSeconds','PriceVaries','PriceVariationReason',
            'MinObservedPrice','MaxObservedPrice'
        )) {
            $State['Opportunity'+$index+$suffix] = ''
        }
    }

    for ($i=0; $i -lt $projectCount; $i++) {
        $row = $Rows[$i]
        $n = $i+1
        $probabilityKnown = $true
        if ($row.PSObject.Properties['probabilityKnown']) { $probabilityKnown = [bool]$row.probabilityKnown }
        $rowName = ([string]$row.name).Trim()
        if ([string]::IsNullOrWhiteSpace($rowName)) {
            $rowItemId = 0
            if ($row.PSObject.Properties['itemId']) { $rowItemId = [int]$row.itemId }
            $rowName = if ($rowItemId -gt 0) { 'Item ' + [string]$rowItemId } else { 'Unknown item' }
        }
        $marketValueText = Format-OpportunityMoney ([long]$row.marketValue)
        if ($row.PSObject.Properties['marketValueFresh'] -and -not [bool]$row.marketValueFresh) { $marketValueText += ' STALE' }

        $State['Opportunity'+$n+'Key'] = [string]$row.key
        $State['Opportunity'+$n+'Name'] = $rowName
        $State['Opportunity'+$n+'Country'] = [string]$row.countryName
        $State['Opportunity'+$n+'CountryCode'] = [string]$row.countryCode
        $State['Opportunity'+$n+'TripBand'] = if ($row.PSObject.Properties['tripBand']) { [string]$row.tripBand } else { '' }
        $State['Opportunity'+$n+'WindowText'] = [string]$row.windowText
        $State['Opportunity'+$n+'LeaveText'] = [string]$row.leaveText
        $State['Opportunity'+$n+'ChanceText'] = if ($probabilityKnown) { ('{0:N0}%' -f (100.0*[double]$row.probability)) } else { 'LEARNING' }
        $State['Opportunity'+$n+'TimeText'] = Format-OpportunityDuration ([long]$row.elapsedSeconds)
        $State['Opportunity'+$n+'GrossText'] = Format-OpportunityMoney ([long]$row.grossProfit)
        $State['Opportunity'+$n+'QuantityText'] = ('x{0}' -f [int]$row.quantity)
        $State['Opportunity'+$n+'ProfitHourText'] = ((Format-OpportunityMoney ([long][Math]::Round([double]$row.profitPerHour))) + '/hr')
        $State['Opportunity'+$n+'PriceText'] = Format-OpportunityMoney ([long]$row.foreignPrice)
        $State['Opportunity'+$n+'MarketValueText'] = $marketValueText
        $State['Opportunity'+$n+'PriceColor'] = [string]$row.priceColor
        $State['Opportunity'+$n+'AccentColor'] = '58,64,73,255'
        $State['Opportunity'+$n+'Tooltip'] = [string]$row.tooltip
        $State['Opportunity'+$n+'GrossValue'] = [long]$row.grossProfit
        $State['Opportunity'+$n+'ProfitHourValue'] = ('{0:R}' -f [double]$row.profitPerHour)
        $State['Opportunity'+$n+'MarketValueValue'] = if ($row.PSObject.Properties['marketValue']) { [long]$row.marketValue } else { 0L }
        $State['Opportunity'+$n+'PurchaseCostValue'] = if ($row.PSObject.Properties['purchaseCost']) { [long]$row.purchaseCost } else { 0L }
        $State['Opportunity'+$n+'GrossSaleValue'] = if ($row.PSObject.Properties['grossSale']) { [long]$row.grossSale } else { 0L }
        $State['Opportunity'+$n+'GrossProfitValue'] = if ($row.PSObject.Properties['grossProfitBeforeTax']) { [long]$row.grossProfitBeforeTax } else { [long]$row.grossProfit }
        $State['Opportunity'+$n+'MarketTaxValue'] = if ($row.PSObject.Properties['marketTax']) { [long]$row.marketTax } else { 0L }
        $State['Opportunity'+$n+'MakeValue'] = if ($row.PSObject.Properties['make']) { [long]$row.make } else { [long]$row.grossProfit }
        $State['Opportunity'+$n+'ProfitEachValue'] = if ($row.PSObject.Properties['profitEach']) { [long]$row.profitEach } else { 0L }
        $State['Opportunity'+$n+'MarketFeePercent'] = if ($row.PSObject.Properties['marketFeePercent']) { [int]$row.marketFeePercent } else { 0 }
        $State['Opportunity'+$n+'TotalCostValue'] = if ($row.PSObject.Properties['purchaseCost']) { [long]$row.purchaseCost } else { 0L }
        $State['Opportunity'+$n+'WindowStartAt'] = [long]$row.windowStartAt
        $State['Opportunity'+$n+'ProbabilityValue'] = if ($probabilityKnown) { ('{0:R}' -f [double]$row.probability) } else { '-1' }
        $State['Opportunity'+$n+'ElapsedSeconds'] = [long]$row.elapsedSeconds
        $State['Opportunity'+$n+'ForecastMode'] = if ($row.PSObject.Properties['forecastMode']) { [string]$row.forecastMode } else { '' }
        $State['Opportunity'+$n+'RestockEstimateAt'] = if ($row.PSObject.Properties['restockEstimateAt']) { [long]$row.restockEstimateAt } else { 0 }
        $State['Opportunity'+$n+'RestockAverageDelaySeconds'] = if ($row.PSObject.Properties['restockAverageDelaySeconds']) { [long]$row.restockAverageDelaySeconds } else { 0 }
        $State['Opportunity'+$n+'RestockEarliestDelaySeconds'] = if ($row.PSObject.Properties['restockEarliestDelaySeconds']) { [long]$row.restockEarliestDelaySeconds } else { 0 }
        $State['Opportunity'+$n+'RestockLatestDelaySeconds'] = if ($row.PSObject.Properties['restockLatestDelaySeconds']) { [long]$row.restockLatestDelaySeconds } else { 0 }
        $State['Opportunity'+$n+'RestockLifetimeShortestDelaySeconds'] = if ($row.PSObject.Properties['restockLifetimeShortestDelaySeconds']) { [long]$row.restockLifetimeShortestDelaySeconds } else { 0 }
        $State['Opportunity'+$n+'RestockLifetimeLongestDelaySeconds'] = if ($row.PSObject.Properties['restockLifetimeLongestDelaySeconds']) { [long]$row.restockLifetimeLongestDelaySeconds } else { 0 }
        $State['Opportunity'+$n+'RestockSampleCount'] = if ($row.PSObject.Properties['restockSampleCount']) { [int]$row.restockSampleCount } else { 0 }
    }
}

if ($OpportunityStateSkipMain) { return }
if ($Now -le 0) { $Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

$engine = Read-OptimalJson $EngineStateFile
$settings = Read-OptimalJson (Join-Path $ConfigDir 'settings.example.json')
$local = Read-OptimalJson (Join-Path $ConfigDir 'settings.local.json')
$countries = Read-OptimalJson (Join-Path $ConfigDir 'countries.json')
$perks = Read-OptimalJson (Join-Path $ConfigDir 'travel-perks.json')
$state = Read-OptimalStateKv $StateKvFile
$missing = New-Object System.Collections.Generic.List[string]
if ($null -eq $engine) { $missing.Add('engine-state.json') }
if ($null -eq $settings) { $missing.Add('settings.example.json') }
if ($null -eq $countries) { $missing.Add('countries.json') }
if ($null -eq $perks) { $missing.Add('travel-perks.json') }
if ($state.Count -eq 0) { $missing.Add('state.kv') }
if ($null -ne $engine -and -not $engine.PSObject.Properties['observedMarkets']) { $missing.Add('engine.observedMarkets') }
if ($missing.Count -gt 0) { throw ('Opportunity prerequisites missing or invalid: ' + ($missing -join ', ')) }

$preferences = Read-UiPreferences
$sortMode = [string]$preferences.sortMode
if ($sortMode -notin @('upcoming','gross','profit_per_hour')) { $sortMode = 'upcoming' }
$profile = Get-TravelProfile -BaseSettings $settings -LocalSettings $local
$optimizerSettings = Get-OptimalProperty $settings 'optimizer'
$minimumSamples = 3
$purchaseBuffer = 60L
if ($null -ne $optimizerSettings) {
    if ($optimizerSettings.PSObject.Properties['minimumAvailabilitySamples']) { $minimumSamples = [Math]::Max(1,[int]$optimizerSettings.minimumAvailabilitySamples) }
    if ($optimizerSettings.PSObject.Properties['purchaseBufferSeconds']) { $purchaseBuffer = [Math]::Max(0L,[long]$optimizerSettings.purchaseBufferSeconds) }
}
$marketFeePercent = [Math]::Max(0,[Math]::Min(5,[int]$preferences.itemMarketFeePercent))
$travelMode = [string]$preferences.travelMode
$staleAfter = [Math]::Max(60L,[long]$settings.staleAfterSeconds)
$forecastStockMaxAge = 21600L
if ($settings.PSObject.Properties['forecastOnlyMaxAgeSeconds']) {
    $forecastStockMaxAge = [Math]::Max($staleAfter,[long]$settings.forecastOnlyMaxAgeSeconds)
}
$resaleFallbackMaxAge = 604800L
if ($settings.PSObject.Properties['profitability'] -and $settings.profitability.PSObject.Properties['resaleFallbackMaxAgeSeconds']) {
    $resaleFallbackMaxAge = [Math]::Max(21600L,[long]$settings.profitability.resaleFallbackMaxAgeSeconds)
}

$travelContext = Get-OptimalProperty $engine 'travelContext'
$travelState = 'unknown'
if ($null -ne $travelContext) { $travelState = [string](Get-OptimalProperty $travelContext 'state') }
if ($travelState -in @('traveling_unknown','abroad_unknown')) {
    Write-OpportunityProjection -State $state -Rows @() -SortMode $sortMode -Message 'Travel destination unresolved - opportunities paused until Torn reports a recognized destination'
    Write-OptimalStateKvAtomic -Values $state -Path $StateKvFile
    return
}

$fixedCountry = ''
if ($null -ne $travelContext -and [bool](Get-OptimalProperty $travelContext 'filterActive')) { $fixedCountry = [string](Get-OptimalProperty $travelContext 'destinationCountryId') }

$eligibleEvidenceKeys=Get-OpportunityEligibleEvidenceKeys -Engine $engine -Countries $countries -Preferences $preferences -FixedCountry $fixedCountry -NowEpoch $Now -ResaleFallbackMaxAgeSeconds $resaleFallbackMaxAge
$evidence=Get-OptimalEvidence -WantedKeys $eligibleEvidenceKeys -SkipObservations

$returningWait = 0L
if ($travelState -eq 'returning' -and $null -ne $travelContext) { $returningWait = [Math]::Max(0L,[long](Get-OptimalProperty $travelContext 'timeLeft')) }

$rows = New-Object System.Collections.Generic.List[object]
$learning = 0
$stale = 0
$forecastOnly = 0
$missingMv = 0
$staleMv = 0
$wasteBlocked = 0
$pricingPriorityIds = New-Object 'System.Collections.Generic.HashSet[int]'
$countryStats = @{}

foreach ($country in @($countries.countries | Where-Object { $_.collect -eq $true })) {
    $countryId = [string]$country.id
    $tripBand = [string]$country.tripBand
    $countryStats[$countryId] = [pscustomobject]@{ observed=0; staleStock=0; forecastStock=0; missingMv=0; staleMv=0; rows=0 }
    if (-not [string]::IsNullOrWhiteSpace($fixedCountry) -and $countryId -ne $fixedCountry) { continue }
    if (@($preferences.displayTripBands) -notcontains $tripBand) { continue }
    if (@($preferences.selectedCountryIds) -notcontains $countryId) { continue }
    if (-not $country.PSObject.Properties['travelSeconds']) { continue }
    $travelProperty = $country.travelSeconds.PSObject.Properties[$travelMode]
    if ($null -eq $travelProperty) { continue }
    $oneWaySeconds = [long]$travelProperty.Value
    if ($oneWaySeconds -le 0) { continue }

    foreach ($property in @($engine.observedMarkets.PSObject.Properties)) {
        $market = $property.Value
        if ($null -eq $market -or [string](Get-OptimalProperty $market 'country') -ne $countryId) { continue }
        if (($market.PSObject.Properties['catalogActive'] -and $market.catalogActive -eq $false) -or ($market.PSObject.Properties['catalogStatus'] -and [string]$market.catalogStatus -eq 'legacy_removed')) { continue }
        $countryStats[$countryId].observed = [int]$countryStats[$countryId].observed + 1

        $sourceTimestamp = [long](Get-OptimalProperty $market 'sourceTimestamp')
        $stockEvidenceMode = Get-OpportunityStockEvidenceMode -SourceTimestamp $sourceTimestamp -NowEpoch $Now -LiveMaximumAgeSeconds $staleAfter -ForecastMaximumAgeSeconds $forecastStockMaxAge
        if ($stockEvidenceMode -eq 'unusable') {
            $stale++
            $countryStats[$countryId].staleStock = [int]$countryStats[$countryId].staleStock + 1
            continue
        }
        $useForecastOnly = ($stockEvidenceMode -eq 'forecast')
        if ($useForecastOnly) {
            $stale++
            $forecastOnly++
            $countryStats[$countryId].staleStock = [int]$countryStats[$countryId].staleStock + 1
            $countryStats[$countryId].forecastStock = [int]$countryStats[$countryId].forecastStock + 1
        }

        $itemId = [int](Get-OptimalProperty $market 'itemId')
        if ($itemId -le 0) { continue }
        $metadata = Get-OptimalMarketMetadata -Engine $engine -ItemId $itemId -Market $market
        if ([string]::IsNullOrWhiteSpace([string]$metadata.name)) { $metadata.name = 'Item ' + [string]$itemId }
        if (-not (Test-OptimalMarketFilters -Preferences $preferences -CountryId $countryId -TripBand $tripBand -ItemId $itemId -Category ([string]$metadata.category))) { continue }

        $resale = Get-OptimalResaleSnapshot -Engine $engine -ItemId $itemId -NowEpoch $Now
        $resaleUse = Get-OpportunityResaleUse -Resale $resale -NowEpoch $Now -MaximumAgeSeconds $resaleFallbackMaxAge
        if (-not [bool]$resaleUse.usable) {
            [void]$pricingPriorityIds.Add($itemId)
            $missingMv++
            $countryStats[$countryId].missingMv = [int]$countryStats[$countryId].missingMv + 1
            continue
        }
        $marketValueFresh = [bool]$resaleUse.fresh
        if (-not $marketValueFresh) {
            [void]$pricingPriorityIds.Add($itemId)
            $staleMv++
            $countryStats[$countryId].staleMv = [int]$countryStats[$countryId].staleMv + 1
        }
        $foreignPrice = [long](Get-OptimalProperty $market 'lastForeignPrice')
        if ($foreignPrice -le 0) { continue }
        $item = [pscustomobject]@{ itemId=$itemId; category=[string]$metadata.category }
        $effects = Get-TravelProfileEffects -Profile $profile -PerksConfig $perks -Item $item
        $capacityOverride = 0
        if ($settings.profitability.PSObject.Properties['capacityOverride']) { $capacityOverride = [int]$settings.profitability.capacityOverride }
        $economics = Get-EffectiveTravelEconomics -Country $country -TravelMode $travelMode -Effects $effects -CapacityOverride $capacityOverride
        if (-not [bool]$economics.capacityKnown -or [int]$economics.capacity -le 0) { continue }
        $capacity = [int]$economics.capacity

        $marketKey = $countryId+':'+[string]$itemId
        $cycles = @()
        if ($evidence.cycles.ContainsKey($marketKey)) { $cycles = @($evidence.cycles[$marketKey]) }
        $recurringCycles = @(Get-OpportunityRecurringCycles -Cycles $cycles)
        $destinationState = $null
        if ($engine.PSObject.Properties['destinations']) { $destinationState = Get-OptimalProperty $engine.destinations $marketKey }
        $stock = if ($useForecastOnly) { 0L } else { [long](Get-OptimalProperty $market 'lastStock') }

        $initialWait = $returningWait
        $outboundSeconds = $oneWaySeconds
        $returnSeconds = $oneWaySeconds
        if (-not [string]::IsNullOrWhiteSpace($fixedCountry)) {
            $initialWait = 0L
            if ($travelState -eq 'traveling') {
                $outboundSeconds = [Math]::Max(0L,[long](Get-OptimalProperty $travelContext 'timeLeft'))
            } elseif ($travelState -in @('abroad','foreign')) {
                $outboundSeconds = 0L
            }
        }

        # Long-OOS markets do not need a full recurring-window/waste calculation
        # every minute. Keep a cheap absolute restock estimate from verified cycle
        # delays and wake detailed forecasting only near the historically earliest
        # restock boundary.
        if ($stock -le 0) {
            $lastSellOutAt=0L
            $lastSellOutQuality=''
            if ($null -ne $destinationState) {
                if ($destinationState.PSObject.Properties['lastSellOutAt']) { $lastSellOutAt=[long]$destinationState.lastSellOutAt }
                if ($destinationState.PSObject.Properties['lastSellOutBoundaryQuality']) { $lastSellOutQuality=[string]$destinationState.lastSellOutBoundaryQuality }
            }
            $restockSummary=Get-OpportunityRestockSummary -Cycles $recurringCycles -RecentSamples 12
            if ($null -ne $restockSummary -and $lastSellOutAt -gt 0 -and (Test-OpportunityBoundaryQuality -Quality $lastSellOutQuality)) {
                $restockEstimateAt=$lastSellOutAt+[long]$restockSummary.averageDelaySeconds
                $wakeDelay=[long]$restockSummary.earliestDelaySeconds
                $lifetimeForWake=if ($null -ne $destinationState) { Get-OptimalProperty $destinationState 'lifetimeStats' } else { $null }
                if ($null -ne $lifetimeForWake) {
                    $lifetimeShortestForWake=[long](Get-OptimalProperty $lifetimeForWake 'shortestRestockDelaySeconds')
                    if ($lifetimeShortestForWake -gt 0 -and ($wakeDelay -le 0 -or $lifetimeShortestForWake -lt $wakeDelay)) {
                        $wakeDelay=$lifetimeShortestForWake
                    }
                }
                $earlyRestockAt=$lastSellOutAt+$wakeDelay
                $wakeAt=$earlyRestockAt-600L
                $sleeping=(
                    $restockEstimateAt -gt $Now -and
                    $Now -lt $wakeAt
                )
                if ($sleeping) {
                    $availableQuantity=$capacity
                    $quantitySamples=[long[]]@($recurringCycles | Where-Object {
                        $_.PSObject.Properties['restockQuantity'] -and [long]$_.restockQuantity -gt 0
                    } | ForEach-Object { [long]$_.restockQuantity })
                    if ($quantitySamples.Count -gt 0) {
                        $sampleQuantity=Get-OptimalMedian $quantitySamples
                        if ($sampleQuantity -gt 0) { $availableQuantity=[Math]::Min($capacity,[int]$sampleQuantity) }
                    }
                    $quantity=[Math]::Max(1,[Math]::Min($capacity,[int]$availableQuantity))
                    $remaining=[Math]::Max(1L,$restockEstimateAt-$Now)
                    $elapsedSeconds=[Math]::Max(1L,$remaining+$returnSeconds+$purchaseBuffer)
                    $tripEconomics=Get-OpportunityEconomics -MarketValue ([long]$resaleUse.marketValue) -ForeignPrice $foreignPrice -Quantity $quantity -MarketFeePercent $marketFeePercent -ElapsedSeconds $elapsedSeconds
                    $grossProfit=[long]$tripEconomics.grossProfit
                    $profitPerHour=Get-OpportunityRoundTripProfitPerHour -Profit ([long]$tripEconomics.make) -OneWaySeconds $oneWaySeconds
                    $profitPerItem=[long]$tripEconomics.profitEach
                    if ([bool]$preferences.showProfitableOnly -and $profitPerItem -le 0) { continue }
                    $priceColor=if (-not $marketValueFresh) { '150,150,150,255' } elseif ($profitPerItem -gt 0) { '86,190,116,255' } else { '224,90,90,255' }
                    $lifetimeShortest=[long]$restockSummary.lifetimeShortestDelaySeconds
                    $lifetimeLongest=[long]$restockSummary.lifetimeLongestDelaySeconds
                    $lifetimeStats=if ($null -ne $destinationState) { Get-OptimalProperty $destinationState 'lifetimeStats' } else { $null }
                    if ($null -ne $lifetimeStats) {
                        $storedShortest=[long](Get-OptimalProperty $lifetimeStats 'shortestRestockDelaySeconds')
                        $storedLongest=[long](Get-OptimalProperty $lifetimeStats 'longestRestockDelaySeconds')
                        if ($storedShortest -gt 0) { $lifetimeShortest=$storedShortest }
                        if ($storedLongest -gt 0) { $lifetimeLongest=$storedLongest }
                    }
                    $restockText='Restocks in ~'+(Format-OpportunityDuration $remaining)
                    $tooltip=('{0} - {1} | {2} | average OOS->restock {3} over {4} verified cycle(s); recent earliest {5}, recent latest {6}; detailed forecast sleeps until 10m before the historical early-restock boundary or while focused' -f
                        [string]$metadata.name,[string]$country.name,$restockText,
                        (Format-OpportunityDuration ([long]$restockSummary.averageDelaySeconds)),
                        [int]$restockSummary.sampleCount,
                        (Format-OpportunityDuration ([long]$restockSummary.earliestDelaySeconds)),
                        (Format-OpportunityDuration ([long]$restockSummary.latestDelaySeconds)))

                    $rows.Add([pscustomobject]@{
                        key=$marketKey
                        countryId=$countryId
                        countryName=[string]$country.name
                        countryCode=Get-OpportunityCountryCode $countryId
                        tripBand=$tripBand
                        itemId=$itemId
                        name=[string]$metadata.name
                        category=[string]$metadata.category
                        probability=-1.0
                        probabilityKnown=$false
                        quantity=[int]$quantity
                        grossProfit=$grossProfit
                        profitPerHour=[double]$profitPerHour
                        purchaseCost=[long]$tripEconomics.purchaseCost
                        grossSale=[long]$tripEconomics.grossSale
                        grossProfitBeforeTax=[long]$tripEconomics.grossProfit
                        marketTax=[long]$tripEconomics.marketTax
                        make=[long]$tripEconomics.make
                        profitEach=[long]$tripEconomics.profitEach
                        marketFeePercent=[int]$tripEconomics.marketFeePercent
                        elapsedSeconds=[long]$elapsedSeconds
                        windowStartAt=[long]$restockEstimateAt
                        windowEndAt=0L
                        leaveDelaySeconds=[long][Math]::Max(0L,$restockEstimateAt-$Now)
                        windowText='RESTOCK ESTIMATE'
                        leaveText=$restockText
                        foreignPrice=$foreignPrice
                        marketValue=[long]$resaleUse.marketValue
                        marketValueFresh=[bool]$marketValueFresh
                        priceColor=$priceColor
                        tooltip=$tooltip
                        forecastMode='sleeping_oos'
                        restockEstimateAt=[long]$restockEstimateAt
                        restockAverageDelaySeconds=[long]$restockSummary.averageDelaySeconds
                        restockEarliestDelaySeconds=[long]$restockSummary.earliestDelaySeconds
                        restockLatestDelaySeconds=[long]$restockSummary.latestDelaySeconds
                        restockLifetimeShortestDelaySeconds=[long]$lifetimeShortest
                        restockLifetimeLongestDelaySeconds=[long]$lifetimeLongest
                        restockSampleCount=[int]$restockSummary.sampleCount
                    })
                    $countryStats[$countryId].rows=[int]$countryStats[$countryId].rows+1
                    continue
                }
            }
        }

        $probability = -1.0
        $probabilityKnown = $false
        $availableQuantity = 0L
        $purchaseAtSeconds = 0L
        $windowStartAt = $Now
        $windowEndAt = 0L
        $windowText = ''
        $leaveDelaySeconds = $initialWait
        $earliestArrivalAt = $Now + $initialWait + $outboundSeconds

        if ($stock -gt 0) {
            $activeRestockAt = Get-OpportunityActiveRestockAt -DestinationState $destinationState
            $window = $null
            if ($activeRestockAt -gt 0 -and $recurringCycles.Count -ge $minimumSamples) {
                $window = Get-OpportunityNextRecurringWindow -Cycles $recurringCycles -AnchorAt $activeRestockAt -AnchorPhase 'restock' -NowEpoch $Now -EarliestArrivalAt $earliestArrivalAt
            }

            if ($null -ne $window) {
                $windowStartAt = [long]$window.startAt
                $windowEndAt = [long]$window.endAt
                $targetPurchaseAt = [long]$window.targetAt
                $purchaseAtSeconds = [Math]::Max(0L,$targetPurchaseAt-$Now)
                $leaveDelaySeconds = [Math]::Max($initialWait,$purchaseAtSeconds-$outboundSeconds)
                $probabilityKnown = $true
                $probability = [double]$window.probability
                $availableQuantity = $stock
                if ($targetPurchaseAt -le ($earliestArrivalAt+1) -and $windowStartAt -le $earliestArrivalAt) {
                    $windowText = 'IN STOCK'
                } elseif ($windowStartAt -le $Now) {
                    $windowText = 'WINDOW NOW'
                } else {
                    $windowText = 'WINDOW '+(Format-OpportunityDuration ($windowStartAt-$Now))
                }
            } else {
                $purchaseAtSeconds = $initialWait + $outboundSeconds
                $forecast = Get-OptimalArrivalForecast -MarketKey $marketKey -Market $market -DestinationState $destinationState -Evidence $evidence -ArrivalSeconds $purchaseAtSeconds -NowEpoch $Now -MinimumSamples $minimumSamples
                if ([bool]$forecast.probabilityKnown) {
                    $probabilityKnown = $true
                    $probability = [double]$forecast.probability
                    $availableQuantity = [long]$forecast.estimatedQuantity
                    if ($availableQuantity -le 0) { $availableQuantity = $stock }
                } else {
                    $learning++
                    $probabilityKnown = $false
                    $probability = -1.0
                    $availableQuantity = $stock
                }
                $windowText = 'IN STOCK'
            }
        } else {
            if ($recurringCycles.Count -lt $minimumSamples) { $learning++; continue }
            $window = $null

            # A stale positive stock count is never carried forward as current stock.
            # Its historical active restock timestamp is still a real observed phase
            # anchor, so use that anchor for the recurring forecast when available.
            if ($useForecastOnly) {
                $activeRestockAt = Get-OpportunityActiveRestockAt -DestinationState $destinationState
                if ($activeRestockAt -gt 0) {
                    $window = Get-OpportunityNextRecurringWindow -Cycles $recurringCycles -AnchorAt $activeRestockAt -AnchorPhase 'restock' -NowEpoch $Now -EarliestArrivalAt $earliestArrivalAt
                }
            }

            if ($null -eq $window) {
                $lastSellOutAt = 0L
                if ($null -ne $destinationState -and $destinationState.PSObject.Properties['lastSellOutAt']) { $lastSellOutAt = [long]$destinationState.lastSellOutAt }
                $window = Get-OpportunityNextRecurringWindow -Cycles $recurringCycles -AnchorAt $lastSellOutAt -AnchorPhase 'sellout' -NowEpoch $Now -EarliestArrivalAt $earliestArrivalAt
            }
            if ($null -eq $window) { $learning++; continue }

            $windowStartAt = [long]$window.startAt
            $windowEndAt = [long]$window.endAt
            $targetPurchaseAt = [long]$window.targetAt
            if ($windowEndAt -gt 0 -and $targetPurchaseAt -ge $windowEndAt) { continue }
            $purchaseAtSeconds = [Math]::Max(0L,$targetPurchaseAt-$Now)
            $leaveDelaySeconds = [Math]::Max($initialWait,$purchaseAtSeconds-$outboundSeconds)
            $probability = [double]$window.probability
            if ($probability -le 0) { continue }
            $probabilityKnown = $true
            $quantitySamples=[long[]]@($recurringCycles | Where-Object {
                $_.PSObject.Properties['restockQuantity'] -and [long]$_.restockQuantity -gt 0
            } | ForEach-Object { [long]$_.restockQuantity })
            if ($quantitySamples.Count -gt 0) { $availableQuantity=Get-OptimalMedian $quantitySamples }
            if ($availableQuantity -le 0) { $learning++; continue }
            if ($windowStartAt -le $Now) { $windowText = 'WINDOW NOW' }
            else { $windowText = 'WINDOW '+(Format-OpportunityDuration ($windowStartAt-$Now)) }
        }

        if ($availableQuantity -le 0) { continue }
        if ($stock -le 0 -and (-not $probabilityKnown -or $probability -le 0)) { continue }
        $quantity = [Math]::Min($capacity,[int]$availableQuantity)
        if ($quantity -le 0) { continue }

        $elapsedSeconds = [Math]::Max(1L,$purchaseAtSeconds+$returnSeconds+$purchaseBuffer)
        $energy = Get-OptimalBarWaste -Bar (Get-OptimalProperty $travelContext 'energy') -HorizonSeconds $elapsedSeconds -NowEpoch $Now -EnergyStackBypass
        $nerve = Get-OptimalBarWaste -Bar (Get-OptimalProperty $travelContext 'nerve') -HorizonSeconds $elapsedSeconds -NowEpoch $Now
        $constraintsApply = [string]::IsNullOrWhiteSpace($fixedCountry)
        if ($constraintsApply) {
            if (-not (Test-OptimalWastePolicy -Waste $energy -Policy ([string]$preferences.energyWastePolicy) -MaximumLoss ([int]$preferences.maxEnergyLoss))) { $wasteBlocked++; continue }
            if (-not (Test-OptimalWastePolicy -Waste $nerve -Policy ([string]$preferences.nerveWastePolicy) -MaximumLoss ([int]$preferences.maxNerveLoss))) { $wasteBlocked++; continue }
        }

        $tripEconomics=Get-OpportunityEconomics -MarketValue ([long]$resaleUse.marketValue) -ForeignPrice $foreignPrice -Quantity $quantity -MarketFeePercent $marketFeePercent -ElapsedSeconds $elapsedSeconds
        $grossProfit = [long]$tripEconomics.grossProfit
        $profitPerHour = Get-OpportunityRoundTripProfitPerHour -Profit ([long]$tripEconomics.make) -OneWaySeconds $oneWaySeconds
        $profitPerItem = [long]$tripEconomics.profitEach
        if ([bool]$preferences.showProfitableOnly -and $profitPerItem -le 0) { continue }
        $priceColor = if (-not $marketValueFresh) { '150,150,150,255' } elseif ($profitPerItem -gt 0) { '86,190,116,255' } else { '224,90,90,255' }
        $leaveText = if ($leaveDelaySeconds -le 60) { 'LEAVE NOW' } else { 'LEAVE '+(Format-OpportunityDuration $leaveDelaySeconds) }
        if ($travelState -in @('abroad','foreign') -and $outboundSeconds -eq 0) { $leaveText = 'AT DEST.' }
        if ($travelState -eq 'traveling' -and $outboundSeconds -gt 0) { $leaveText = 'EN ROUTE' }
        $wasteText = Get-OpportunityWasteText -Energy $energy -Nerve $nerve
        $chanceText = if ($probabilityKnown) { ('{0:N0}% modeled hit' -f (100.0*$probability)) } else { 'hit likelihood learning' }
        $mvStateText = if ($marketValueFresh) { 'MV fresh' } else { 'MV STALE '+(Format-OpportunityDuration ([long]$resaleUse.ageSeconds))+' old; refresh queued' }
        $stockStateText = if ($useForecastOnly) { 'stock forecast only' } else { 'stock live' }
        $tooltip = ('{0} - {1} | {2} | {3} | {4} total elapsed | net each {5} x {6} = {7} make | gross sale {8} at declared MV | tax {9} ({10}%) | {11}/hr round-trip flight net | {12} | foreign {13}, MV {14} ({15}); {16}' -f [string]$metadata.name,[string]$country.name,$windowText,$chanceText,(Format-OpportunityDuration $elapsedSeconds),(Format-OpportunityMoney $profitPerItem),$quantity,(Format-OpportunityMoney ([long]$tripEconomics.make)),(Format-OpportunityMoney ([long]$tripEconomics.grossSale)),(Format-OpportunityMoney ([long]$tripEconomics.marketTax)),$marketFeePercent,(Format-OpportunityMoney ([long][Math]::Round($profitPerHour))),$wasteText,(Format-OpportunityMoney $foreignPrice),(Format-OpportunityMoney ([long]$resaleUse.marketValue)),$mvStateText,$stockStateText)

        $rows.Add([pscustomobject]@{
            key=$marketKey
            countryId=$countryId
            countryName=[string]$country.name
            countryCode=Get-OpportunityCountryCode $countryId
            tripBand=$tripBand
            itemId=$itemId
            name=[string]$metadata.name
            category=[string]$metadata.category
            probability=[double]$probability
            probabilityKnown=[bool]$probabilityKnown
            quantity=[int]$quantity
            grossProfit=$grossProfit
            profitPerHour=[double]$profitPerHour
            purchaseCost=[long]$tripEconomics.purchaseCost
            grossSale=[long]$tripEconomics.grossSale
            grossProfitBeforeTax=[long]$tripEconomics.grossProfit
            marketTax=[long]$tripEconomics.marketTax
            make=[long]$tripEconomics.make
            profitEach=[long]$tripEconomics.profitEach
            marketFeePercent=[int]$tripEconomics.marketFeePercent
            elapsedSeconds=[long]$elapsedSeconds
            windowStartAt=[long]$windowStartAt
            windowEndAt=[long]$windowEndAt
            leaveDelaySeconds=[long]$leaveDelaySeconds
            windowText=$windowText
            leaveText=$leaveText
            foreignPrice=$foreignPrice
            marketValue=[long]$resaleUse.marketValue
            marketValueFresh=[bool]$marketValueFresh
            priceColor=$priceColor
            tooltip=$tooltip
        })
        $countryStats[$countryId].rows = [int]$countryStats[$countryId].rows + 1
    }
}

$allRows = @($rows.ToArray())
$hasKnownSortData=$false
foreach ($row in $allRows) {
    $timeKnown=($row.PSObject.Properties['windowStartAt'] -and [long]$row.windowStartAt -gt 0)
    $profitKnown=($row.PSObject.Properties['marketValue'] -and [long]$row.marketValue -gt 0 -and $row.PSObject.Properties['foreignPrice'] -and [long]$row.foreignPrice -gt 0)
    if ($timeKnown -or $profitKnown) { $hasKnownSortData=$true; break }
}
$effectiveSortMode=if ($hasKnownSortData) { $sortMode } else { 'name' }
$sorted = @()
if ($effectiveSortMode -eq 'name') {
    $sorted = @($allRows | Sort-Object name,countryName,key)
} elseif ($effectiveSortMode -eq 'gross') {
    $sorted = @($allRows | Sort-Object @{Expression={ if ($_.PSObject.Properties['make']) { [double]$_.make } else { [double]$_.grossProfit } };Descending=$true},@{Expression='probability';Descending=$true},elapsedSeconds,name)
} elseif ($effectiveSortMode -eq 'profit_per_hour') {
    $sorted = @($allRows | Sort-Object @{Expression='profitPerHour';Descending=$true},@{Expression={ if ($_.PSObject.Properties['make']) { [double]$_.make } else { [double]$_.grossProfit } };Descending=$true},@{Expression='probability';Descending=$true},name)
} else {
    $sorted = @($allRows | Sort-Object @{Expression='windowStartAt';Ascending=$true},@{Expression='probability';Descending=$true},@{Expression='grossProfit';Descending=$true},name)
}

$state['OpportunityStaleStockCount'] = $stale
$state['OpportunityForecastStockCount'] = $forecastOnly
$state['OpportunityMissingMvCount'] = $missingMv
$state['OpportunityStaleMvCount'] = $staleMv
# The retired standalone route optimizer used to persist this list under
# engine.optimizer. OpportunityState already evaluates the same resale freshness
# blockers, so publish the compact priority signal with the visible projection.
$state['ResalePricingPriorityItemIds'] = (($pricingPriorityIds | Sort-Object) -join ',')
foreach ($countryId in @($countryStats.Keys | Sort-Object)) {
    $stats = $countryStats[$countryId]
    $prefix = 'OpportunityCountry_'+$countryId
    $state[$prefix+'_Observed'] = [int]$stats.observed
    $state[$prefix+'_StaleStock'] = [int]$stats.staleStock
    $state[$prefix+'_ForecastStock'] = [int]$stats.forecastStock
    $state[$prefix+'_MissingMv'] = [int]$stats.missingMv
    $state[$prefix+'_StaleMv'] = [int]$stats.staleMv
    $state[$prefix+'_Rows'] = [int]$stats.rows
}

$message = ''
if ($sorted.Count -eq 0) {
    $message = 'No evidence-backed opportunities match current filters'
    if ($missingMv -gt 0) { $message = 'Learning market values - opportunity pricing is still filling' }
    elseif ($learning -gt 0) { $message = 'Learning recurring restock windows - fresh in-stock markets remain visible while likelihood learns' }
    elseif ($wasteBlocked -gt 0) { $message = 'Current Energy/Nerve waste limits block the available opportunities' }
    elseif ($stale -gt 0) { $message = 'Foreign stock is outside the forecast horizon - waiting for a fresh provider poll' }
}
Write-OpportunityProjection -State $state -Rows $sorted -SortMode $sortMode -EffectiveSortMode $effectiveSortMode -Message $message
Write-OptimalStateKvAtomic -Values $state -Path $StateKvFile
