param(
    [switch]$SkipMain,
    [long]$Now = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'TravelProfile.ps1')
. (Join-Path $PSScriptRoot 'FilterPreferences.ps1') -SkipMain

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$SeedDir = Join-Path $ProjectRoot 'data\seed'
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$StateKvFile = Join-Path $GeneratedDir 'state.kv'
$RuntimeCycleFile = Join-Path $RuntimeDir 'cycles.jsonl'
$SeedCycleFile = Join-Path $SeedDir 'cycles.jsonl'
$RuntimeObservationFile = Join-Path $RuntimeDir 'observations.jsonl'
$SeedObservationFile = Join-Path $SeedDir 'observations.jsonl'

function Read-OptimalJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-OptimalJsonAtomic {
    param([string]$Path,[object]$Value,[int]$Depth=24)
    $tmp=$Path+'.tmp'
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Read-OptimalStateKv {
    param([string]$Path)
    $values=@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $i=$line.IndexOf('='); if ($i -lt 1) { continue }
        $values[$line.Substring(0,$i).Trim([char]0xFEFF).Trim()]=$line.Substring($i+1).Trim()
    }
    return $values
}

function Write-OptimalStateKvAtomic {
    param([hashtable]$Values,[string]$Path)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $tmp=$Path+'.tmp'
    $lines=New-Object System.Collections.Generic.List[string]
    foreach ($key in ($Values.Keys | Sort-Object)) {
        $value=([string]$Values[$key]).Replace("`r",' ').Replace("`n",' ')
        $lines.Add("$key=$value")
    }
    [System.IO.File]::WriteAllLines($tmp,$lines.ToArray(),[System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-OptimalProperty {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $p=$Object.PSObject.Properties[$Name]
    if ($null -eq $p) { return $null }
    return $p.Value
}

function Set-OptimalProperty {
    param([object]$Object,[string]$Name,[object]$Value)
    $p=$Object.PSObject.Properties[$Name]
    if ($null -eq $p) { $Object | Add-Member NoteProperty $Name $Value }
    else { $p.Value=$Value }
}

function Get-OptimalMedian {
    param([long[]]$Values)
    if ($null -eq $Values -or $Values.Count -eq 0) { return 0L }
    $sorted=@($Values | Sort-Object)
    $mid=[int][Math]::Floor($sorted.Count/2)
    if (($sorted.Count % 2) -eq 1) { return [long]$sorted[$mid] }
    return [long][Math]::Round(([double]$sorted[$mid-1]+[double]$sorted[$mid])/2.0)
}

function Add-EvidenceRow {
    param([hashtable]$Map,[string]$Key,[object]$Value)
    if (-not $Map.ContainsKey($Key)) { $Map[$Key]=New-Object System.Collections.Generic.List[object] }
    $Map[$Key].Add($Value)
}

function Get-OptimalEvidence {
    $cycles=@{}
    foreach ($path in @($SeedCycleFile,$RuntimeCycleFile)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        foreach ($line in Get-Content -LiteralPath $path) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row=$line | ConvertFrom-Json
                $country=[string](Get-OptimalProperty $row 'country'); $itemId=[int](Get-OptimalProperty $row 'itemId')
                if ([string]::IsNullOrWhiteSpace($country) -or $itemId -le 0) { continue }
                Add-EvidenceRow -Map $cycles -Key ($country+':'+$itemId) -Value $row
            } catch { }
        }
    }

    $observations=@{}
    foreach ($path in @($SeedObservationFile,$RuntimeObservationFile)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        foreach ($line in Get-Content -LiteralPath $path) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try {
                $row=$line | ConvertFrom-Json
                $country=[string](Get-OptimalProperty $row 'country'); $itemId=[int](Get-OptimalProperty $row 'itemId')
                if ([string]::IsNullOrWhiteSpace($country) -or $itemId -le 0) { continue }
                Add-EvidenceRow -Map $observations -Key ($country+':'+$itemId) -Value $row
            } catch { }
        }
    }

    $restockStock=@{}
    foreach ($key in @($observations.Keys)) {
        $samples=New-Object System.Collections.Generic.List[long]
        $prev=$null
        foreach ($row in @($observations[$key] | Sort-Object timestamp)) {
            $stock=[long](Get-OptimalProperty $row 'stock')
            if ($null -ne $prev -and [long]$prev -eq 0 -and $stock -gt 0) { $samples.Add($stock) }
            $prev=$stock
        }
        $restockStock[$key]=$samples
    }

    return [pscustomobject]@{ cycles=$cycles; observations=$observations; restockStock=$restockStock }
}

function Get-OptimalBarWaste {
    param([object]$Bar,[long]$HorizonSeconds,[long]$NowEpoch,[switch]$EnergyStackBypass)
    if ($null -eq $Bar) { return [pscustomobject]@{ known=$false; loss=0L; rawLoss=0L; stacked=$false; bypass=$false; ticks=0L } }
    $current=[long](Get-OptimalProperty $Bar 'current')
    $maximum=[long](Get-OptimalProperty $Bar 'maximum')
    $increment=[long](Get-OptimalProperty $Bar 'increment')
    $interval=[long](Get-OptimalProperty $Bar 'interval')
    $tick=[long](Get-OptimalProperty $Bar 'tickTime')
    if ($maximum -le 0 -or $increment -le 0 -or $interval -le 0) { return [pscustomobject]@{ known=$false; loss=0L; rawLoss=0L; stacked=$false; bypass=$false; ticks=0L } }
    if ($tick -gt 86400) { $tick=$tick-$NowEpoch }
    if ($tick -le 0 -or $tick -gt $interval) { $tick=$interval }
    $ticks=0L
    if ($HorizonSeconds -ge $tick) { $ticks=1L+[long][Math]::Floor(($HorizonSeconds-$tick)/[double]$interval) }
    $space=[Math]::Max(0L,$maximum-$current)
    $rawLoss=[Math]::Max(0L,($ticks*$increment)-$space)
    $stacked=$current -gt $maximum
    $bypass=($EnergyStackBypass -and $stacked)
    $effective=if ($bypass) { 0L } else { $rawLoss }
    return [pscustomobject]@{ known=$true; loss=[long]$effective; rawLoss=[long]$rawLoss; stacked=[bool]$stacked; bypass=[bool]$bypass; ticks=[long]$ticks }
}

function Test-OptimalWastePolicy {
    param([object]$Waste,[string]$Policy,[int]$MaximumLoss)
    $policy=([string]$Policy).ToLowerInvariant()
    if ($policy -eq 'allowed') { return $true }
    if ($null -ne $Waste -and [bool](Get-OptimalProperty $Waste 'bypass')) { return $true }
    if ($null -eq $Waste -or -not [bool](Get-OptimalProperty $Waste 'known')) { return $false }
    $loss=[long](Get-OptimalProperty $Waste 'loss')
    if ($policy -eq 'forbidden') { return $loss -le 0 }
    if ($policy -eq 'limited') { return $loss -le [Math]::Max(0,$MaximumLoss) }
    return $true
}

function Get-OptimalArrivalForecast {
    param(
        [string]$MarketKey,
        [object]$Market,
        [object]$DestinationState,
        [object]$Evidence,
        [long]$ArrivalSeconds,
        [long]$NowEpoch,
        [int]$MinimumSamples=3
    )
    $stock=if ($Market.PSObject.Properties['lastStock']) { [long]$Market.lastStock } else { 0L }
    $cycles=@(); if ($Evidence.cycles.ContainsKey($MarketKey)) { $cycles=@($Evidence.cycles[$MarketKey]) }
    if ($stock -gt 0) {
        $restockAt=0L
        if ($null -ne $DestinationState) {
            $active=Get-OptimalProperty $DestinationState 'activeCycle'
            if ($null -ne $active -and $active.PSObject.Properties['restockAt']) { $restockAt=[long]$active.restockAt }
        }
        $age=if ($restockAt -gt 0) { [Math]::Max(0L,$NowEpoch-$restockAt) } else { 0L }
        $requiredAge=$age+$ArrivalSeconds
        $durations=@($cycles | Where-Object { $_.PSObject.Properties['availabilitySeconds'] -and [long]$_.availabilitySeconds -gt 0 } | ForEach-Object { [long]$_.availabilitySeconds })
        $known=$durations.Count -ge $MinimumSamples
        $probability=-1.0
        if ($known) {
            $hits=@($durations | Where-Object { $_ -ge $requiredAge }).Count
            $probability=$hits/[double]$durations.Count
        }
        return [pscustomobject]@{ currentStock=$stock; estimatedQuantity=$stock; probabilityKnown=$known; probability=$probability; sampleCount=$durations.Count; mode='in_stock' }
    }

    $lastSellOutAt=0L
    if ($null -ne $DestinationState -and $DestinationState.PSObject.Properties['lastSellOutAt']) { $lastSellOutAt=[long]$DestinationState.lastSellOutAt }
    $usable=@($cycles | Where-Object {
        $_.PSObject.Properties['restockDelaySeconds'] -and [long]$_.restockDelaySeconds -gt 0 -and
        $_.PSObject.Properties['availabilitySeconds'] -and [long]$_.availabilitySeconds -gt 0
    })
    if ($lastSellOutAt -le 0 -or $usable.Count -lt $MinimumSamples) {
        return [pscustomobject]@{ currentStock=0L; estimatedQuantity=0L; probabilityKnown=$false; probability=-1.0; sampleCount=$usable.Count; mode='out_of_stock' }
    }

    $target=[Math]::Max(0L,$NowEpoch-$lastSellOutAt)+$ArrivalSeconds
    $hits=0
    foreach ($cycle in $usable) {
        $delay=[long]$cycle.restockDelaySeconds; $availability=[long]$cycle.availabilitySeconds
        if ($delay -le $target -and $target -lt ($delay+$availability)) { $hits++ }
    }
    $probability=$hits/[double]$usable.Count
    $qty=0L
    if ($Evidence.restockStock.ContainsKey($MarketKey)) {
        $samples=[long[]]@($Evidence.restockStock[$MarketKey] | ForEach-Object { [long]$_ })
        $qty=Get-OptimalMedian $samples
    }
    return [pscustomobject]@{ currentStock=0L; estimatedQuantity=$qty; probabilityKnown=$true; probability=$probability; sampleCount=$usable.Count; mode='restock_forecast' }
}

function Get-OptimalResaleSnapshot {
    param([object]$Engine,[int]$ItemId,[long]$NowEpoch,[long]$FreshSeconds=21600)
    $row=$null
    if ($null -ne $Engine -and $Engine.PSObject.Properties['resaleCache']) { $row=Get-OptimalProperty $Engine.resaleCache ([string]$ItemId) }
    $mv=0L; $fetched=0L
    if ($null -ne $row) {
        if ($row.PSObject.Properties['average']) { $mv=[long]$row.average }
        if ($row.PSObject.Properties['fetchedAt']) { $fetched=[long]$row.fetchedAt }
    }
    $fresh=($mv -gt 0 -and $fetched -gt 0 -and ($NowEpoch-$fetched) -le $FreshSeconds)
    return [pscustomobject]@{ marketValue=$mv; fetchedAt=$fetched; fresh=$fresh }
}

function Test-OptimalMarketFilters {
    param([object]$Preferences,[string]$CountryId,[string]$TripBand,[int]$ItemId,[string]$Category)
    if (@($Preferences.ignoredItemIds) -contains $ItemId) { return $false }
    if (-not [bool]$Preferences.itemFilterAll -and -not (@($Preferences.selectedItemIds) -contains $ItemId)) { return $false }
    if (-not (@($Preferences.selectedTripBands) -contains $TripBand)) { return $false }
    if (-not (@($Preferences.selectedCountryIds) -contains $CountryId)) { return $false }
    if (-not [bool]$Preferences.categoryFilterAll -and -not (@($Preferences.selectedCategories) -contains $Category)) { return $false }
    return $true
}

function Get-OptimalMarketMetadata {
    param([object]$Engine,[int]$ItemId,[object]$Market)
    $name=if ($Market.PSObject.Properties['providerName']) { [string]$Market.providerName } else { 'Item '+$ItemId }
    $category='Unknown'
    if ($Engine.PSObject.Properties['itemMetadata']) {
        $meta=Get-OptimalProperty $Engine.itemMetadata ([string]$ItemId)
        if ($null -ne $meta) {
            if ($meta.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$meta.name)) { $name=[string]$meta.name }
            if ($meta.PSObject.Properties['category']) { $category=[string]$meta.category }
        }
    }
    return [pscustomobject]@{ itemId=$ItemId; name=$name; category=$category }
}

function Add-OptimalPlanQuantity {
    param([hashtable]$Plan,[object]$Candidate,[int]$Quantity)
    if ($Quantity -le 0) { return }
    $key=[string]$Candidate.itemId
    if (-not $Plan.ContainsKey($key)) {
        $Plan[$key]=[pscustomobject]@{
            itemId=[int]$Candidate.itemId; name=[string]$Candidate.name; category=[string]$Candidate.category
            quantity=0; foreignPrice=[long]$Candidate.foreignPrice; marketValue=[long]$Candidate.marketValue
            sellBasis=[long]$Candidate.sellBasis; profitPerItem=[long]$Candidate.profitPerItem
            probability=[double]$Candidate.probability; probabilityKnown=[bool]$Candidate.probabilityKnown
            priceColor=[string]$Candidate.priceColor; sourceTimestamp=[long]$Candidate.sourceTimestamp
        }
    }
    $Plan[$key].quantity=[int]$Plan[$key].quantity+$Quantity
}

function Get-OptimalCountryPlan {
    param(
        [object]$Country,[object[]]$Candidates,[int]$GeneralCapacity,[long]$TravelCost,[long]$HorizonSeconds,
        [object]$EnergyWaste,[object]$NerveWaste,[int]$MaxPlanItems=8,[bool]$ShowProfitableOnly=$false
    )
    if ($Candidates.Count -eq 0 -or $GeneralCapacity -le 0) { return $null }
    $sorted=@($Candidates | Sort-Object @{Expression='expectedUnitProfit';Descending=$true}, @{Expression='probabilitySort';Descending=$true}, itemId)
    $plan=@{}
    $remaining=$GeneralCapacity
    foreach ($candidate in $sorted) {
        if ($remaining -le 0 -or $plan.Count -ge $MaxPlanItems) { break }
        $qty=[Math]::Min($remaining,[int]$candidate.availableQuantity)
        if ($qty -le 0) { continue }
        Add-OptimalPlanQuantity -Plan $plan -Candidate $candidate -Quantity $qty
        $candidate.allocated=$qty
        $remaining-=$qty
    }

    $extraSlots=0
    foreach ($candidate in $sorted) { $extraSlots=[Math]::Max($extraSlots,[int]$candidate.extraCapacity) }
    $extraRemaining=$extraSlots
    if ($extraRemaining -gt 0) {
        foreach ($candidate in @($sorted | Where-Object { [int]$_.extraCapacity -gt 0 })) {
            if ($extraRemaining -le 0) { break }
            if (-not $plan.ContainsKey([string]$candidate.itemId) -and $plan.Count -ge $MaxPlanItems) { continue }
            $already=[int]$candidate.allocated
            $available=[Math]::Max(0,[int]$candidate.availableQuantity-$already)
            $qty=[Math]::Min($extraRemaining,$available)
            if ($qty -le 0) { continue }
            Add-OptimalPlanQuantity -Plan $plan -Candidate $candidate -Quantity $qty
            $candidate.allocated=$already+$qty
            $extraRemaining-=$qty
        }
    }

    $rows=@($plan.Values | Sort-Object @{Expression={ [double]$_.profitPerItem * (if ($_.probabilityKnown) { [double]$_.probability } else { 1.0 }) };Descending=$true}, name)
    if ($rows.Count -eq 0) { return $null }
    $qtyTotal=[int](($rows | Measure-Object quantity -Sum).Sum)
    $target=$GeneralCapacity+$extraSlots
    $rawItemProfit=0.0; $expectedItemProfit=0.0; $probQty=0.0; $knownQty=0
    foreach ($row in $rows) {
        $rawItemProfit += [double]$row.quantity * [double]$row.profitPerItem
        $factor=if ([bool]$row.probabilityKnown) { [Math]::Max(0.0,[Math]::Min(1.0,[double]$row.probability)) } else { 1.0 }
        $expectedItemProfit += [double]$row.quantity * [double]$row.profitPerItem * $factor
        if ([bool]$row.probabilityKnown) { $probQty += [double]$row.quantity*$factor; $knownQty += [int]$row.quantity }
    }
    $rawTrip=[long][Math]::Round($rawItemProfit-$TravelCost)
    $expectedTrip=[long][Math]::Round($expectedItemProfit-$TravelCost)
    if ($ShowProfitableOnly -and $rawTrip -le 0) { return $null }
    $hours=[Math]::Max(1.0/60.0,$HorizonSeconds/3600.0)
    $score=$expectedTrip/$hours
    $routeProbability=if ($knownQty -gt 0) { $probQty/$knownQty } else { -1.0 }
    $hasUnknown=@($rows | Where-Object { -not [bool]$_.probabilityKnown }).Count -gt 0
    return [pscustomobject]@{
        countryId=[string]$Country.id; countryName=[string]$Country.name; tripBand=[string]$Country.tripBand
        plan=$rows; quantity=$qtyTotal; capacity=$target; generalCapacity=$GeneralCapacity; extraCapacity=$extraSlots
        travelCost=[long]$TravelCost; rawTripProfit=$rawTrip; expectedTripProfit=$expectedTrip; score=[double]$score
        routeProbability=[double]$routeProbability; routeProbabilityHasUnknown=[bool]$hasUnknown
        energyWaste=$EnergyWaste; nerveWaste=$NerveWaste; horizonSeconds=[long]$HorizonSeconds
    }
}

function Format-OptimalDuration {
    param([long]$Seconds)
    $Seconds=[Math]::Max(0,$Seconds); $h=[Math]::Floor($Seconds/3600); $m=[Math]::Floor(($Seconds%3600)/60)
    if ($h -gt 0) { return ('{0}h {1}m' -f $h,$m) }
    return ('{0}m' -f $m)
}

function Format-OptimalMoney {
    param([long]$Value)
    $sign=if ($Value -lt 0) { '-' } else { '' }
    return ('{0}${1:N0}' -f $sign,[Math]::Abs($Value))
}

function Write-OptimalProjection {
    param([hashtable]$State,[object]$Route,[string]$Message,[int]$BasisPercent,[string]$TravelState,[long]$ArrivalSeconds=0)
    $State['OptimalVisible']=if ($null -ne $Route) { 1 } else { 0 }
    $State['OptimalMessage']=$Message
    $State['OptimalProfitBasisPercent']=$BasisPercent
    $State['OptimalProfitBasisText']=('{0}% MV' -f $BasisPercent)
    $State['OptimalTravelState']=$TravelState
    foreach ($i in 1..8) {
        foreach ($suffix in @('Name','Category','QtyText','PriceText','MarketValueText','ChanceText','PriceColor','Tooltip')) { $State['OptimalItem'+$i+$suffix]='' }
    }
    $State['OptimalItemCount']=0
    if ($null -eq $Route) { return }

    $State['OptimalCountryId']=[string]$Route.countryId
    $State['OptimalCountryName']=[string]$Route.countryName
    $State['OptimalTripBand']=[string]$Route.tripBand
    $State['OptimalCapacityText']=('{0}/{1} slots' -f [int]$Route.quantity,[int]$Route.capacity)
    $State['OptimalTravelText']=Format-OptimalDuration ([long]$Route.horizonSeconds)
    $State['OptimalExpectedProfitText']=Format-OptimalMoney ([long]$Route.expectedTripProfit)
    if ([bool]$Route.routeProbabilityHasUnknown) { $State['OptimalChanceText']='hit: learning' }
    elseif ([double]$Route.routeProbability -ge 0) { $State['OptimalChanceText']=('hit: {0:N0}%' -f (100.0*[double]$Route.routeProbability)) }
    else { $State['OptimalChanceText']='hit: live stock' }

    $energy=$Route.energyWaste; $nerve=$Route.nerveWaste
    $State['OptimalEnergyText']=if ($null -ne $energy -and [bool]$energy.bypass) { 'E: stacked' } elseif ($null -ne $energy -and [bool]$energy.known) { 'E loss: '+[string][long]$energy.loss } else { 'E: ?' }
    $State['OptimalNerveText']=if ($null -ne $nerve -and [bool]$nerve.known) { 'N loss: '+[string][long]$nerve.loss } else { 'N: ?' }
    if ($TravelState -eq 'traveling' -and $ArrivalSeconds -gt 0) { $State['OptimalArrivalText']='arrive '+(Format-OptimalDuration $ArrivalSeconds) }
    elseif ($TravelState -eq 'abroad' -or $TravelState -eq 'foreign') { $State['OptimalArrivalText']='at destination' }
    else { $State['OptimalArrivalText']='out '+(Format-OptimalDuration ([long]($Route.horizonSeconds/2))) }

    $rows=@($Route.plan); $count=[Math]::Min(8,$rows.Count); $State['OptimalItemCount']=$count
    for ($index=0; $index -lt $count; $index++) {
        $row=$rows[$index]; $n=$index+1
        $State['OptimalItem'+$n+'Name']=[string]$row.name
        $State['OptimalItem'+$n+'Category']=[string]$row.category
        $State['OptimalItem'+$n+'QtyText']='x'+[string][int]$row.quantity
        $State['OptimalItem'+$n+'PriceText']=('${0:N0}' -f [long]$row.foreignPrice)
        $State['OptimalItem'+$n+'MarketValueText']=('${0:N0}' -f [long]$row.marketValue)
        $State['OptimalItem'+$n+'ChanceText']=if ([bool]$row.probabilityKnown) { ('{0:N0}%' -f (100.0*[double]$row.probability)) } else { 'LIVE' }
        $State['OptimalItem'+$n+'PriceColor']=[string]$row.priceColor
        $State['OptimalItem'+$n+'Tooltip']=('{0}% MV basis {1}; {2}/item before travel; qty {3}; availability {4}' -f $BasisPercent,(Format-OptimalMoney ([long]$row.sellBasis)),(Format-OptimalMoney ([long]$row.profitPerItem)),[int]$row.quantity,[string]$State['OptimalItem'+$n+'ChanceText'])
    }
}

if ($SkipMain) { return }
if ($Now -le 0) { $Now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
$engine=Read-OptimalJson $EngineStateFile
$settings=Read-OptimalJson (Join-Path $ConfigDir 'settings.example.json')
$local=Read-OptimalJson (Join-Path $ConfigDir 'settings.local.json')
$countries=Read-OptimalJson (Join-Path $ConfigDir 'countries.json')
$perks=Read-OptimalJson (Join-Path $ConfigDir 'travel-perks.json')
$state=Read-OptimalStateKv $StateKvFile
if ($null -eq $engine -or $null -eq $settings -or $null -eq $countries -or $null -eq $perks -or $state.Count -eq 0 -or -not $engine.PSObject.Properties['observedMarkets']) { return }
$prefs=Read-UiPreferences
$profile=Get-TravelProfile -BaseSettings $settings -LocalSettings $local
$evidence=Get-OptimalEvidence
$optimizer=Get-OptimalProperty $settings 'optimizer'
$minSamples=if ($null -ne $optimizer -and $optimizer.PSObject.Properties['minimumAvailabilitySamples']) { [int]$optimizer.minimumAvailabilitySamples } else { 3 }
$buffer=if ($null -ne $optimizer -and $optimizer.PSObject.Properties['purchaseBufferSeconds']) { [long]$optimizer.purchaseBufferSeconds } else { 60L }
$maxPlanItems=if ($null -ne $optimizer -and $optimizer.PSObject.Properties['maxPlanItems']) { [int]$optimizer.maxPlanItems } else { 8 }
$maxPlanItems=[Math]::Max(1,[Math]::Min(8,$maxPlanItems))
$basisPercent=if ([bool]$prefs.use95PercentMarketValue) { 95 } else { 100 }
$travelMode=[string]$prefs.travelMode
$travelContext=Get-OptimalProperty $engine 'travelContext'
$travelState=if ($null -ne $travelContext) { [string](Get-OptimalProperty $travelContext 'state') } else { 'unknown' }
$fixedCountry=''; if ($null -ne $travelContext -and [bool](Get-OptimalProperty $travelContext 'filterActive')) { $fixedCountry=[string](Get-OptimalProperty $travelContext 'destinationCountryId') }
if ($travelState -eq 'returning') {
    Write-OptimalProjection -State $state -Route $null -Message 'Returning to Torn - next route available on arrival' -BasisPercent $basisPercent -TravelState $travelState
    Write-OptimalStateKvAtomic -Values $state -Path $StateKvFile
    return
}

$pricingPriority=New-Object 'System.Collections.Generic.HashSet[int]'
$routes=New-Object System.Collections.Generic.List[object]
foreach ($country in @($countries.countries | Where-Object { $_.collect -eq $true })) {
    $countryId=[string]$country.id; $tripBand=[string]$country.tripBand
    if (-not [string]::IsNullOrWhiteSpace($fixedCountry) -and $countryId -ne $fixedCountry) { continue }
    if (@($prefs.selectedTripBands) -notcontains $tripBand -or @($prefs.selectedCountryIds) -notcontains $countryId) { continue }
    if (-not $country.PSObject.Properties['travelSeconds']) { continue }
    $travelProp=$country.travelSeconds.PSObject.Properties[$travelMode]; if ($null -eq $travelProp) { continue }
    $oneWay=[long]$travelProp.Value; if ($oneWay -le 0) { continue }

    $arrivalSeconds=$oneWay; $horizon=(2*$oneWay)+$buffer; $costMultiplier=2
    if (-not [string]::IsNullOrWhiteSpace($fixedCountry)) {
        if ($travelState -eq 'traveling') { $left=[long](Get-OptimalProperty $travelContext 'timeLeft'); if ($left -gt 0) { $arrivalSeconds=$left }; $horizon=$arrivalSeconds+$oneWay+$buffer; $costMultiplier=1 }
        elseif ($travelState -in @('abroad','foreign')) { $arrivalSeconds=0; $horizon=$oneWay+$buffer; $costMultiplier=1 }
    }

    $neutral=[pscustomobject]@{ itemId=0; category='' }
    $neutralEffects=Get-TravelProfileEffects -Profile $profile -PerksConfig $perks -Item $neutral
    $capacityOverride=if ($settings.profitability.PSObject.Properties['capacityOverride']) { [int]$settings.profitability.capacityOverride } else { 0 }
    $generalEconomics=Get-EffectiveTravelEconomics -Country $country -TravelMode $travelMode -Effects $neutralEffects -CapacityOverride $capacityOverride
    if (-not [bool]$generalEconomics.capacityKnown -or -not [bool]$generalEconomics.travelCostKnown -or [int]$generalEconomics.capacity -le 0) { continue }
    $generalCapacity=[int]$generalEconomics.capacity
    $routeTravelCost=[long]$generalEconomics.travelCost*$costMultiplier

    $energy=Get-OptimalBarWaste -Bar (Get-OptimalProperty $travelContext 'energy') -HorizonSeconds $horizon -NowEpoch $Now -EnergyStackBypass
    $nerve=Get-OptimalBarWaste -Bar (Get-OptimalProperty $travelContext 'nerve') -HorizonSeconds $horizon -NowEpoch $Now
    $constraintsApply=[string]::IsNullOrWhiteSpace($fixedCountry)
    if ($constraintsApply) {
        if (-not (Test-OptimalWastePolicy -Waste $energy -Policy ([string]$prefs.energyWastePolicy) -MaximumLoss ([int]$prefs.maxEnergyLoss))) { continue }
        if (-not (Test-OptimalWastePolicy -Waste $nerve -Policy ([string]$prefs.nerveWastePolicy) -MaximumLoss ([int]$prefs.maxNerveLoss))) { continue }
    }

    $candidates=New-Object System.Collections.Generic.List[object]
    foreach ($property in @($engine.observedMarkets.PSObject.Properties)) {
        $market=$property.Value; if ($null -eq $market) { continue }
        if ([string](Get-OptimalProperty $market 'country') -ne $countryId) { continue }
        if (($market.PSObject.Properties['catalogActive'] -and $market.catalogActive -eq $false) -or ($market.PSObject.Properties['catalogStatus'] -and [string]$market.catalogStatus -eq 'legacy_removed')) { continue }
        $itemId=[int](Get-OptimalProperty $market 'itemId'); if ($itemId -le 0) { continue }
        $meta=Get-OptimalMarketMetadata -Engine $engine -ItemId $itemId -Market $market
        if (-not (Test-OptimalMarketFilters -Preferences $prefs -CountryId $countryId -TripBand $tripBand -ItemId $itemId -Category ([string]$meta.category))) { continue }
        $resale=Get-OptimalResaleSnapshot -Engine $engine -ItemId $itemId -NowEpoch $Now
        if (-not [bool]$resale.fresh) { [void]$pricingPriority.Add($itemId); continue }
        $foreignPrice=[long](Get-OptimalProperty $market 'lastForeignPrice'); if ($foreignPrice -le 0) { continue }
        $dest=$null; if ($engine.PSObject.Properties['destinations']) { $dest=Get-OptimalProperty $engine.destinations ($countryId+':'+$itemId) }
        $forecast=Get-OptimalArrivalForecast -MarketKey ($countryId+':'+$itemId) -Market $market -DestinationState $dest -Evidence $evidence -ArrivalSeconds $arrivalSeconds -NowEpoch $Now -MinimumSamples $minSamples
        if ([long]$forecast.estimatedQuantity -le 0) { continue }
        if ([bool]$forecast.probabilityKnown -and [double]$forecast.probability -le 0) { continue }

        $item=[pscustomobject]@{ itemId=$itemId; category=[string]$meta.category }
        $effects=Get-TravelProfileEffects -Profile $profile -PerksConfig $perks -Item $item
        $itemEconomics=Get-EffectiveTravelEconomics -Country $country -TravelMode $travelMode -Effects $effects -CapacityOverride $capacityOverride
        $itemCapacity=if ([bool]$itemEconomics.capacityKnown) { [int]$itemEconomics.capacity } else { $generalCapacity }
        $extra=[Math]::Max(0,$itemCapacity-$generalCapacity)
        $sellBasis=[long][Math]::Floor([long]$resale.marketValue*($basisPercent/100.0))
        $profitPerItem=[long]($sellBasis-$foreignPrice)
        if ([bool]$prefs.showProfitableOnly -and $profitPerItem -le 0) { continue }
        $factor=if ([bool]$forecast.probabilityKnown) { [Math]::Max(0.0,[Math]::Min(1.0,[double]$forecast.probability)) } else { 1.0 }
        $color=if ($foreignPrice -le $sellBasis) { '86,190,116,255' } else { '224,90,90,255' }
        $sourceTimestamp=if ($market.PSObject.Properties['sourceTimestamp']) { [long]$market.sourceTimestamp } else { 0L }
        $candidates.Add([pscustomobject]@{
            itemId=$itemId; name=[string]$meta.name; category=[string]$meta.category; foreignPrice=$foreignPrice
            marketValue=[long]$resale.marketValue; sellBasis=$sellBasis; profitPerItem=$profitPerItem
            probabilityKnown=[bool]$forecast.probabilityKnown; probability=[double]$forecast.probability; probabilitySort=if ([bool]$forecast.probabilityKnown) { [double]$forecast.probability } else { 1.0 }
            availableQuantity=[Math]::Max(0,[int]$forecast.estimatedQuantity); extraCapacity=$extra; expectedUnitProfit=[double]$profitPerItem*$factor
            priceColor=$color; sourceTimestamp=$sourceTimestamp; allocated=0
        })
    }

    $route=Get-OptimalCountryPlan -Country $country -Candidates $candidates.ToArray() -GeneralCapacity $generalCapacity -TravelCost $routeTravelCost -HorizonSeconds $horizon -EnergyWaste $energy -NerveWaste $nerve -MaxPlanItems $maxPlanItems -ShowProfitableOnly ([bool]$prefs.showProfitableOnly)
    if ($null -ne $route) { $route | Add-Member NoteProperty arrivalSeconds $arrivalSeconds; $routes.Add($route) }
}

$best=$null
if ($routes.Count -gt 0) { $best=@($routes | Sort-Object @{Expression='score';Descending=$true}, @{Expression='expectedTripProfit';Descending=$true}, horizonSeconds | Select-Object -First 1)[0] }
$message=if ($null -ne $best) { 'Optimal route from current stock, MV, capacity, travel time, and observed availability' } elseif ($pricingPriority.Count -gt 0) { 'Learning market values - optimizer pricing queue still filling' } else { 'No route satisfies current filters and waste constraints' }
Write-OptimalProjection -State $state -Route $best -Message $message -BasisPercent $basisPercent -TravelState $travelState -ArrivalSeconds (if ($null -ne $best -and $best.PSObject.Properties['arrivalSeconds']) { [long]$best.arrivalSeconds } else { 0L })
Write-OptimalStateKvAtomic -Values $state -Path $StateKvFile

if (-not $engine.PSObject.Properties['optimizer']) { $engine | Add-Member NoteProperty optimizer ([pscustomobject]@{}) }
Set-OptimalProperty $engine.optimizer 'lastRunAt' $Now
Set-OptimalProperty $engine.optimizer 'marketValueBasisPercent' $basisPercent
Set-OptimalProperty $engine.optimizer 'pricingPriorityItemIds' ([int[]]@($pricingPriority | Sort-Object))
Set-OptimalProperty $engine.optimizer 'candidateRoutes' $routes.Count
Set-OptimalProperty $engine.optimizer 'selectedCountryId' (if ($null -ne $best) { [string]$best.countryId } else { '' })
Set-OptimalProperty $engine.optimizer 'selectedQuantity' (if ($null -ne $best) { [int]$best.quantity } else { 0 })
Set-OptimalProperty $engine.optimizer 'selectedCapacity' (if ($null -ne $best) { [int]$best.capacity } else { 0 })
Set-OptimalProperty $engine.optimizer 'selectedExpectedTripProfit' (if ($null -ne $best) { [long]$best.expectedTripProfit } else { 0L })
Write-OptimalJsonAtomic -Path $EngineStateFile -Value $engine
