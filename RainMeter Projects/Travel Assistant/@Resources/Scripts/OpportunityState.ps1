param(
    [switch]$SkipMain,
    [long]$Now = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'OptimalRoute.ps1') -SkipMain

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

function Get-OpportunityCountryCode {
    param([string]$CountryId)
    $map = @{
        mexico='MX'; cayman_islands='KY'; canada='CA'; hawaii='HI'; united_kingdom='UK'; argentina='AR'; switzerland='CH'; japan='JP'; china='CN'; united_arab_emirates='AE'; south_africa='ZA'
    }
    if ($map.ContainsKey($CountryId)) { return [string]$map[$CountryId] }
    return $CountryId.ToUpperInvariant()
}

function Write-OpportunityProjection {
    param(
        [hashtable]$State,
        [object[]]$Rows,
        [string]$SortMode,
        [string]$Message,
        [string]$BestKey
    )
    $State['OpportunitySortMode'] = $SortMode
    $State['OpportunitySortText'] = $SortMode.ToUpperInvariant()
    $State['OpportunityMessage'] = $Message
    $State['OpportunityCount'] = [Math]::Min(8,@($Rows).Count)
    $State['OpportunityBestKey'] = $BestKey

    foreach ($index in 1..8) {
        foreach ($suffix in @('Key','RankText','OptimalText','Name','Country','CountryCode','WindowText','LeaveText','ChanceText','TimeText','GrossText','PriceText','MarketValueText','PriceColor','AccentColor','Tooltip')) {
            $State['Opportunity'+$index+$suffix] = ''
        }
    }

    $count = [Math]::Min(8,@($Rows).Count)
    for ($i=0; $i -lt $count; $i++) {
        $row = $Rows[$i]
        $n = $i+1
        $isOptimal = ([string]$row.key -eq $BestKey)
        $State['Opportunity'+$n+'Key'] = [string]$row.key
        $State['Opportunity'+$n+'RankText'] = ('#{0}' -f $n)
        $State['Opportunity'+$n+'OptimalText'] = if ($isOptimal) { 'OPTIMAL' } else { '' }
        $State['Opportunity'+$n+'Name'] = [string]$row.name
        $State['Opportunity'+$n+'Country'] = [string]$row.countryName
        $State['Opportunity'+$n+'CountryCode'] = [string]$row.countryCode
        $State['Opportunity'+$n+'WindowText'] = [string]$row.windowText
        $State['Opportunity'+$n+'LeaveText'] = [string]$row.leaveText
        $State['Opportunity'+$n+'ChanceText'] = ('{0:N0}%' -f (100.0*[double]$row.probability))
        $State['Opportunity'+$n+'TimeText'] = Format-OpportunityDuration ([long]$row.elapsedSeconds)
        $State['Opportunity'+$n+'GrossText'] = Format-OpportunityMoney ([long]$row.grossProfit)
        $State['Opportunity'+$n+'PriceText'] = Format-OpportunityMoney ([long]$row.foreignPrice)
        $State['Opportunity'+$n+'MarketValueText'] = Format-OpportunityMoney ([long]$row.marketValue)
        $State['Opportunity'+$n+'PriceColor'] = [string]$row.priceColor
        $State['Opportunity'+$n+'AccentColor'] = if ($isOptimal) { '82,174,255,255' } else { '58,64,73,255' }
        $State['Opportunity'+$n+'Tooltip'] = [string]$row.tooltip
    }
}

if ($SkipMain) { return }
if ($Now -le 0) { $Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

$engine = Read-OptimalJson $EngineStateFile
$settings = Read-OptimalJson (Join-Path $ConfigDir 'settings.example.json')
$local = Read-OptimalJson (Join-Path $ConfigDir 'settings.local.json')
$countries = Read-OptimalJson (Join-Path $ConfigDir 'countries.json')
$perks = Read-OptimalJson (Join-Path $ConfigDir 'travel-perks.json')
$state = Read-OptimalStateKv $StateKvFile
if ($null -eq $engine -or $null -eq $settings -or $null -eq $countries -or $null -eq $perks -or $state.Count -eq 0 -or -not $engine.PSObject.Properties['observedMarkets']) { return }

$preferences = Read-UiPreferences
$sortMode = [string]$preferences.sortMode
if ($sortMode -notin @('optimal','upcoming','profit','time')) { $sortMode = 'optimal' }
$profile = Get-TravelProfile -BaseSettings $settings -LocalSettings $local
$evidence = Get-OptimalEvidence
$optimizerSettings = Get-OptimalProperty $settings 'optimizer'
$minimumSamples = 3
$purchaseBuffer = 60L
if ($null -ne $optimizerSettings) {
    if ($optimizerSettings.PSObject.Properties['minimumAvailabilitySamples']) { $minimumSamples = [Math]::Max(1,[int]$optimizerSettings.minimumAvailabilitySamples) }
    if ($optimizerSettings.PSObject.Properties['purchaseBufferSeconds']) { $purchaseBuffer = [Math]::Max(0L,[long]$optimizerSettings.purchaseBufferSeconds) }
}
$basisPercent = if ([bool]$preferences.use95PercentMarketValue) { 95 } else { 100 }
$travelMode = [string]$preferences.travelMode
$staleAfter = [Math]::Max(60L,[long]$settings.staleAfterSeconds)

$travelContext = Get-OptimalProperty $engine 'travelContext'
$travelState = 'unknown'
if ($null -ne $travelContext) { $travelState = [string](Get-OptimalProperty $travelContext 'state') }
if ($travelState -in @('traveling_unknown','abroad_unknown')) {
    Write-OpportunityProjection -State $state -Rows @() -SortMode $sortMode -Message 'Travel destination unresolved - opportunities paused until Torn reports a recognized destination' -BestKey ''
    Write-OptimalStateKvAtomic -Values $state -Path $StateKvFile
    return
}

$fixedCountry = ''
if ($null -ne $travelContext -and [bool](Get-OptimalProperty $travelContext 'filterActive')) { $fixedCountry = [string](Get-OptimalProperty $travelContext 'destinationCountryId') }
$returningWait = 0L
if ($travelState -eq 'returning' -and $null -ne $travelContext) { $returningWait = [Math]::Max(0L,[long](Get-OptimalProperty $travelContext 'timeLeft')) }

$rows = New-Object System.Collections.Generic.List[object]
$learning = 0
$stale = 0
$missingMv = 0

foreach ($country in @($countries.countries | Where-Object { $_.collect -eq $true })) {
    $countryId = [string]$country.id
    $tripBand = [string]$country.tripBand
    if (-not [string]::IsNullOrWhiteSpace($fixedCountry) -and $countryId -ne $fixedCountry) { continue }
    if (@($preferences.selectedTripBands) -notcontains $tripBand) { continue }
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

        $sourceTimestamp = [long](Get-OptimalProperty $market 'sourceTimestamp')
        if ($sourceTimestamp -le 0 -or ($Now-$sourceTimestamp) -gt $staleAfter) { $stale++; continue }
        $itemId = [int](Get-OptimalProperty $market 'itemId')
        if ($itemId -le 0) { continue }
        $metadata = Get-OptimalMarketMetadata -Engine $engine -ItemId $itemId -Market $market
        if (-not (Test-OptimalMarketFilters -Preferences $preferences -CountryId $countryId -TripBand $tripBand -ItemId $itemId -Category ([string]$metadata.category))) { continue }

        $resale = Get-OptimalResaleSnapshot -Engine $engine -ItemId $itemId -NowEpoch $Now
        if (-not [bool]$resale.fresh) { $missingMv++; continue }
        $foreignPrice = [long](Get-OptimalProperty $market 'lastForeignPrice')
        if ($foreignPrice -le 0) { continue }
        $sellBasis = [long][Math]::Floor([long]$resale.marketValue * ($basisPercent/100.0))
        $profitPerItem = [long]($sellBasis-$foreignPrice)
        if ([bool]$preferences.showProfitableOnly -and $profitPerItem -le 0) { continue }

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
        $destinationState = $null
        if ($engine.PSObject.Properties['destinations']) { $destinationState = Get-OptimalProperty $engine.destinations $marketKey }
        $stock = [long](Get-OptimalProperty $market 'lastStock')

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

        $probability = -1.0
        $availableQuantity = 0L
        $purchaseAtSeconds = 0L
        $windowStartAt = $Now
        $windowEndAt = 0L
        $windowText = ''
        $leaveDelaySeconds = $initialWait

        if ($stock -gt 0) {
            $purchaseAtSeconds = $initialWait + $outboundSeconds
            $forecast = Get-OptimalArrivalForecast -MarketKey $marketKey -Market $market -DestinationState $destinationState -Evidence $evidence -ArrivalSeconds $purchaseAtSeconds -NowEpoch $Now -MinimumSamples $minimumSamples
            if (-not [bool]$forecast.probabilityKnown) { $learning++; continue }
            $probability = [double]$forecast.probability
            $availableQuantity = [long]$forecast.estimatedQuantity
            $windowText = 'IN STOCK'
        } else {
            if ($cycles.Count -lt $minimumSamples) { $learning++; continue }
            $lastSellOutAt = 0L
            if ($null -ne $destinationState -and $destinationState.PSObject.Properties['lastSellOutAt']) { $lastSellOutAt = [long]$destinationState.lastSellOutAt }
            $window = Get-OpportunityNextWindow -Cycles $cycles -LastSellOutAt $lastSellOutAt -NowEpoch $Now
            if ($null -eq $window) { $learning++; continue }
            $windowStartAt = [long]$window.startAt
            $windowEndAt = [long]$window.endAt

            $earliestArrivalAt = $Now + $initialWait + $outboundSeconds
            $targetPurchaseAt = [Math]::Max($earliestArrivalAt,$windowStartAt)
            if ($windowEndAt -gt 0 -and $targetPurchaseAt -ge $windowEndAt) { continue }
            $purchaseAtSeconds = [Math]::Max(0L,$targetPurchaseAt-$Now)
            $leaveDelaySeconds = [Math]::Max($initialWait,$purchaseAtSeconds-$outboundSeconds)
            $targetAge = [Math]::Max(0L,$targetPurchaseAt-$lastSellOutAt)
            $probability = Get-OpportunityProbabilityAtAge -Cycles $cycles -AgeSeconds $targetAge
            if ($probability -le 0) { continue }
            if ($evidence.restockStock.ContainsKey($marketKey)) {
                $samples = [long[]]@($evidence.restockStock[$marketKey] | ForEach-Object { [long]$_ })
                $availableQuantity = Get-OptimalMedian $samples
            }
            if ($availableQuantity -le 0) { $learning++; continue }
            if ($windowStartAt -le $Now) { $windowText = 'WINDOW NOW' }
            else { $windowText = 'WINDOW '+(Format-OpportunityDuration ($windowStartAt-$Now)) }
        }

        if ($probability -le 0 -or $availableQuantity -le 0) { continue }
        $quantity = [Math]::Min($capacity,[int]$availableQuantity)
        if ($quantity -le 0) { continue }
        $grossProfit = [long]($quantity*$profitPerItem)
        $expectedGross = [double]$grossProfit*[double]$probability
        $elapsedSeconds = [Math]::Max(1L,$purchaseAtSeconds+$returnSeconds+$purchaseBuffer)
        $elapsedHours = [Math]::Max(1.0/60.0,$elapsedSeconds/3600.0)
        $optimalScore = $expectedGross/$elapsedHours
        $priceColor = if ($foreignPrice -le $sellBasis) { '86,190,116,255' } else { '224,90,90,255' }
        $leaveText = if ($leaveDelaySeconds -le 60) { 'LEAVE NOW' } else { 'LEAVE '+(Format-OpportunityDuration $leaveDelaySeconds) }
        if ($travelState -in @('abroad','foreign') -and $outboundSeconds -eq 0) { $leaveText = 'AT DEST.' }
        if ($travelState -eq 'traveling' -and $outboundSeconds -gt 0) { $leaveText = 'EN ROUTE' }
        $tooltip = ('{0} - {1} | {2} | {3:N0}% modeled hit | {4} total elapsed | {5} gross at {6}% MV | foreign {7}, MV {8}, qty {9}' -f [string]$metadata.name,[string]$country.name,$windowText,(100.0*$probability),(Format-OpportunityDuration $elapsedSeconds),(Format-OpportunityMoney $grossProfit),$basisPercent,(Format-OpportunityMoney $foreignPrice),(Format-OpportunityMoney ([long]$resale.marketValue)),$quantity)

        $rows.Add([pscustomobject]@{
            key=$marketKey
            countryId=$countryId
            countryName=[string]$country.name
            countryCode=Get-OpportunityCountryCode $countryId
            itemId=$itemId
            name=[string]$metadata.name
            category=[string]$metadata.category
            probability=[double]$probability
            grossProfit=$grossProfit
            expectedGross=[double]$expectedGross
            optimalScore=[double]$optimalScore
            elapsedSeconds=[long]$elapsedSeconds
            windowStartAt=[long]$windowStartAt
            windowEndAt=[long]$windowEndAt
            leaveDelaySeconds=[long]$leaveDelaySeconds
            windowText=$windowText
            leaveText=$leaveText
            foreignPrice=$foreignPrice
            marketValue=[long]$resale.marketValue
            priceColor=$priceColor
            tooltip=$tooltip
        })
    }
}

$allRows = @($rows.ToArray())
$bestKey = ''
if ($allRows.Count -gt 0) {
    $bestKey = [string](@($allRows | Sort-Object @{Expression='optimalScore';Descending=$true},@{Expression='expectedGross';Descending=$true},elapsedSeconds | Select-Object -First 1)[0].key)
}

$sorted = @()
if ($sortMode -eq 'upcoming') {
    $sorted = @($allRows | Sort-Object @{Expression='windowStartAt';Ascending=$true},@{Expression='probability';Descending=$true},@{Expression='grossProfit';Descending=$true})
} elseif ($sortMode -eq 'profit') {
    $sorted = @($allRows | Sort-Object @{Expression='grossProfit';Descending=$true},@{Expression='probability';Descending=$true},elapsedSeconds)
} elseif ($sortMode -eq 'time') {
    $sorted = @($allRows | Sort-Object @{Expression='elapsedSeconds';Ascending=$true},@{Expression='expectedGross';Descending=$true})
} else {
    $sorted = @($allRows | Sort-Object @{Expression='optimalScore';Descending=$true},@{Expression='expectedGross';Descending=$true},elapsedSeconds)
}

$message = ''
if ($sorted.Count -eq 0) {
    $message = 'No evidence-backed opportunities match current filters'
    if ($missingMv -gt 0) { $message = 'Learning market values - opportunity pricing is still filling' }
    elseif ($learning -gt 0) { $message = 'Learning availability - more completed stock cycles are needed' }
    elseif ($stale -gt 0) { $message = 'Foreign stock is stale - waiting for a fresh provider poll' }
}
Write-OpportunityProjection -State $state -Rows $sorted -SortMode $sortMode -Message $message -BestKey $bestKey
Write-OptimalStateKvAtomic -Values $state -Path $StateKvFile
