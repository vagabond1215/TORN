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
        [string]$Message
    )

    # Keep a bounded local candidate pool in state.kv. Rainmeter renders only the
    # first eight after applying its local trip-band filter and selected sort, but
    # retaining all eligible markets here makes those controls genuinely instant.
    $maxProjectedRows = 256
    $previousCount = 0
    if ($State.ContainsKey('OpportunityCount')) { [void][int]::TryParse([string]$State['OpportunityCount'],[ref]$previousCount) }
    $projectCount = [Math]::Min($maxProjectedRows,@($Rows).Count)
    $clearCount = [Math]::Min($maxProjectedRows,[Math]::Max(8,[Math]::Max($previousCount,$projectCount)))

    $State['OpportunitySortMode'] = $SortMode
    $State['OpportunitySortText'] = $SortMode.ToUpperInvariant()
    $State['OpportunityMessage'] = $Message
    $State['OpportunityCount'] = $projectCount
    $State['OpportunityBestKey'] = ''

    foreach ($index in 1..$clearCount) {
        foreach ($suffix in @(
            'Key','RankText','OptimalText','Name','Country','CountryCode','TripBand','WindowText','LeaveText','ChanceText','TimeText',
            'GrossText','QuantityText','ProfitHourText','PriceText','MarketValueText','PriceColor','AccentColor','Tooltip',
            'GrossValue','ProfitHourValue','WindowStartAt','ProbabilityValue','ElapsedSeconds'
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
        $State['Opportunity'+$n+'RankText'] = ''
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
        $State['Opportunity'+$n+'WindowStartAt'] = [long]$row.windowStartAt
        $State['Opportunity'+$n+'ProbabilityValue'] = if ($probabilityKnown) { ('{0:R}' -f [double]$row.probability) } else { '-1' }
        $State['Opportunity'+$n+'ElapsedSeconds'] = [long]$row.elapsedSeconds
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
if ($sortMode -notin @('name','upcoming','gross','profit_per_hour')) { $sortMode = 'upcoming' }
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
        $sellBasis = [long][Math]::Floor([long]$resaleUse.marketValue * ($basisPercent/100.0))
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
            if ($evidence.restockStock.ContainsKey($marketKey)) {
                $samples = [long[]]@($evidence.restockStock[$marketKey] | ForEach-Object { [long]$_ })
                $availableQuantity = Get-OptimalMedian $samples
            }
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

        $grossProfit = [long]($quantity*$profitPerItem)
        $elapsedHours = [Math]::Max(1.0/60.0,$elapsedSeconds/3600.0)
        $profitPerHour = [double]$grossProfit/$elapsedHours
        $priceColor = if (-not $marketValueFresh) { '145,152,164,255' } elseif ($foreignPrice -le $sellBasis) { '86,190,116,255' } else { '224,90,90,255' }
        $leaveText = if ($leaveDelaySeconds -le 60) { 'LEAVE NOW' } else { 'LEAVE '+(Format-OpportunityDuration $leaveDelaySeconds) }
        if ($travelState -in @('abroad','foreign') -and $outboundSeconds -eq 0) { $leaveText = 'AT DEST.' }
        if ($travelState -eq 'traveling' -and $outboundSeconds -gt 0) { $leaveText = 'EN ROUTE' }
        $wasteText = Get-OpportunityWasteText -Energy $energy -Nerve $nerve
        $chanceText = if ($probabilityKnown) { ('{0:N0}% modeled hit' -f (100.0*$probability)) } else { 'hit likelihood learning' }
        $mvStateText = if ($marketValueFresh) { 'MV fresh' } else { 'MV STALE '+(Format-OpportunityDuration ([long]$resaleUse.ageSeconds))+' old; refresh queued' }
        $stockStateText = if ($useForecastOnly) { 'stock forecast only' } else { 'stock live' }
        $tooltip = ('{0} - {1} | {2} | {3} | {4} total elapsed | unit spread {5} x {6} = {7} gross at {8}% MV | {9}/hr | {10} | foreign {11}, MV {12} ({13}); {14}' -f [string]$metadata.name,[string]$country.name,$windowText,$chanceText,(Format-OpportunityDuration $elapsedSeconds),(Format-OpportunityMoney $profitPerItem),$quantity,(Format-OpportunityMoney $grossProfit),$basisPercent,(Format-OpportunityMoney ([long][Math]::Round($profitPerHour))),$wasteText,(Format-OpportunityMoney $foreignPrice),(Format-OpportunityMoney ([long]$resaleUse.marketValue)),$mvStateText,$stockStateText)

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
$sorted = @()
if ($sortMode -eq 'name') {
    $sorted = @($allRows | Sort-Object name,countryName,key)
} elseif ($sortMode -eq 'gross') {
    $sorted = @($allRows | Sort-Object @{Expression='grossProfit';Descending=$true},@{Expression='probability';Descending=$true},elapsedSeconds,name)
} elseif ($sortMode -eq 'profit_per_hour') {
    $sorted = @($allRows | Sort-Object @{Expression='profitPerHour';Descending=$true},@{Expression='grossProfit';Descending=$true},@{Expression='probability';Descending=$true},name)
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
Write-OpportunityProjection -State $state -Rows $sorted -SortMode $sortMode -Message $message
Write-OptimalStateKvAtomic -Values $state -Path $StateKvFile
