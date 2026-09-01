param(
    [switch]$SkipMain,
    [long]$Now = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'TravelProfile.ps1')
. (Join-Path $PSScriptRoot 'FilterPreferences.ps1') -SkipMain
. (Join-Path $PSScriptRoot 'CycleForecastFilter.ps1')

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
    param([string]$Path, [object]$Value, [int]$Depth = 24)
    $tmp = $Path + '.tmp'
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Read-OptimalStateKv {
    param([string]$Path)
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $index = $line.IndexOf('=')
        if ($index -lt 1) { continue }
        $key = $line.Substring(0, $index).Trim([char]0xFEFF).Trim()
        $values[$key] = $line.Substring($index + 1).Trim()
    }
    return $values
}

function Write-OptimalStateKvAtomic {
    param([hashtable]$Values, [string]$Path)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $tmp = $Path + '.tmp'
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in ($Values.Keys | Sort-Object)) {
        $value = ([string]$Values[$key]).Replace("`r", ' ').Replace("`n", ' ')
        $lines.Add("$key=$value")
    }
    [System.IO.File]::WriteAllLines($tmp, $lines.ToArray(), [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-OptimalProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Set-OptimalProperty {
    param([object]$Object, [string]$Name, [object]$Value)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { $Object | Add-Member NoteProperty $Name $Value }
    else { $property.Value = $Value }
}

function Get-OptimalMedian {
    param([long[]]$Values)
    if ($null -eq $Values -or $Values.Count -eq 0) { return 0L }
    $sorted = @($Values | Sort-Object)
    $middle = [int][Math]::Floor($sorted.Count / 2)
    if (($sorted.Count % 2) -eq 1) { return [long]$sorted[$middle] }
    return [long][Math]::Round(([double]$sorted[$middle - 1] + [double]$sorted[$middle]) / 2.0)
}

function Add-EvidenceRow {
    param([hashtable]$Map, [string]$Key, [object]$Value)
    # Keep evidence values as ordinary object[] arrays. Windows PowerShell 5.1
    # can throw "Argument types do not match" when generic List<T> values are
    # later wrapped in @(...), which both route and opportunity projections do.
    if (-not $Map.ContainsKey($Key)) { $Map[$Key] = [object[]]@() }
    $Map[$Key] = [object[]](@($Map[$Key]) + @($Value))
}

function Get-OptimalEvidenceLineKey {
    param([string]$Line)

    if ([string]::IsNullOrWhiteSpace($Line)) { return '' }
    $countryMatch=[System.Text.RegularExpressions.Regex]::Match(
        $Line,
        '"country"\s*:\s*"([^"]+)"',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    $itemMatch=[System.Text.RegularExpressions.Regex]::Match(
        $Line,
        '"itemId"\s*:\s*([1-9][0-9]*)',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    if (-not $countryMatch.Success -or -not $itemMatch.Success) { return '' }
    return ($countryMatch.Groups[1].Value.Trim().ToLowerInvariant()+':'+$itemMatch.Groups[1].Value)
}

function Test-OptimalEvidenceKeyWanted {
    param([string]$Key,[hashtable]$WantedKeys)
    if ($null -eq $WantedKeys) { return $true }
    return $WantedKeys.ContainsKey(([string]$Key).Trim().ToLowerInvariant())
}

function Get-OptimalEvidence {
    param(
        [hashtable]$WantedKeys = $null,
        [switch]$SkipObservations
    )

    $cycles = @{}
    if ($null -ne $WantedKeys -and $WantedKeys.Count -eq 0) {
        return [pscustomobject]@{ cycles=@{}; observations=@{}; restockStock=@{} }
    }

    foreach ($path in @($SeedCycleFile, $RuntimeCycleFile)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        foreach ($line in Get-Content -LiteralPath $path) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $lineKey=Get-OptimalEvidenceLineKey -Line $line
            if ([string]::IsNullOrWhiteSpace($lineKey) -or -not (Test-OptimalEvidenceKeyWanted -Key $lineKey -WantedKeys $WantedKeys)) { continue }
            try {
                $row = $line | ConvertFrom-Json
                Add-EvidenceRow -Map $cycles -Key $lineKey -Value $row
            } catch { }
        }
    }

    $observations = @{}
    $restockStock = @{}
    if (-not $SkipObservations) {
        foreach ($path in @($SeedObservationFile, $RuntimeObservationFile)) {
            if (-not (Test-Path -LiteralPath $path)) { continue }
            foreach ($line in Get-Content -LiteralPath $path) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                $lineKey=Get-OptimalEvidenceLineKey -Line $line
                if ([string]::IsNullOrWhiteSpace($lineKey) -or -not (Test-OptimalEvidenceKeyWanted -Key $lineKey -WantedKeys $WantedKeys)) { continue }
                try {
                    $row = $line | ConvertFrom-Json
                    Add-EvidenceRow -Map $observations -Key $lineKey -Value $row
                } catch { }
            }
        }
    
        foreach ($key in @($observations.Keys)) {
            $samples = [long[]]@()
            $previousStock = $null
            foreach ($row in @($observations[$key] | Sort-Object timestamp)) {
                $stock = [long](Get-OptimalProperty $row 'stock')
                if ($null -ne $previousStock -and [long]$previousStock -eq 0 -and $stock -gt 0) { $samples = [long[]]($samples + $stock) }
                $previousStock = $stock
            }
            $restockStock[$key] = [long[]]$samples
        }
    
    }

    # Stored cycles remain untouched. Only the evidence handed to opportunity
    # forecasts excludes cadence-incompatible or boundary-unverifiable capture gaps.
    foreach ($key in @($cycles.Keys)) {
        $cycles[$key] = [object[]]@(Select-CadenceAwareForecastCycles -Cycles @($cycles[$key]))
    }

    return [pscustomobject]@{
        cycles = $cycles
        observations = $observations
        restockStock = $restockStock
    }
}

function Get-OptimalBarWaste {
    param(
        [object]$Bar,
        [long]$HorizonSeconds,
        [long]$NowEpoch,
        [switch]$EnergyStackBypass
    )

    if ($null -eq $Bar) {
        return [pscustomobject]@{ known = $false; loss = 0L; rawLoss = 0L; stacked = $false; bypass = $false; ticks = 0L }
    }

    $current = [long](Get-OptimalProperty $Bar 'current')
    $maximum = [long](Get-OptimalProperty $Bar 'maximum')
    $increment = [long](Get-OptimalProperty $Bar 'increment')
    $interval = [long](Get-OptimalProperty $Bar 'interval')
    $tick = [long](Get-OptimalProperty $Bar 'tickTime')
    if ($maximum -le 0 -or $increment -le 0 -or $interval -le 0) {
        return [pscustomobject]@{ known = $false; loss = 0L; rawLoss = 0L; stacked = $false; bypass = $false; ticks = 0L }
    }

    # Current Torn bars normally expose tick_time as the remaining seconds to the
    # next natural tick. Accept an epoch defensively if the API representation changes.
    if ($tick -gt 86400) { $tick = $tick - $NowEpoch }
    if ($tick -le 0 -or $tick -gt $interval) { $tick = $interval }

    $ticks = 0L
    if ($HorizonSeconds -ge $tick) {
        $ticks = 1L + [long][Math]::Floor(($HorizonSeconds - $tick) / [double]$interval)
    }

    $space = [Math]::Max(0L, $maximum - $current)
    $rawLoss = [Math]::Max(0L, ($ticks * $increment) - $space)
    $stacked = $current -gt $maximum
    $bypass = ($EnergyStackBypass -and $stacked)
    $effectiveLoss = $rawLoss
    if ($bypass) { $effectiveLoss = 0L }

    return [pscustomobject]@{
        known = $true
        loss = [long]$effectiveLoss
        rawLoss = [long]$rawLoss
        stacked = [bool]$stacked
        bypass = [bool]$bypass
        ticks = [long]$ticks
    }
}

function Test-OptimalWastePolicy {
    param([object]$Waste, [string]$Policy, [int]$MaximumLoss)
    $policyName = ([string]$Policy).ToLowerInvariant()
    if ($policyName -eq 'allowed') { return $true }
    if ($null -ne $Waste -and [bool](Get-OptimalProperty $Waste 'bypass')) { return $true }
    if ($null -eq $Waste -or -not [bool](Get-OptimalProperty $Waste 'known')) { return $false }

    $loss = [long](Get-OptimalProperty $Waste 'loss')
    if ($policyName -eq 'forbidden') { return $loss -le 0 }
    if ($policyName -eq 'limited') { return $loss -le [Math]::Max(0, $MaximumLoss) }
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
        [int]$MinimumSamples = 3
    )

    $stock = 0L
    if ($Market.PSObject.Properties['lastStock']) { $stock = [long]$Market.lastStock }
    $cycles = @()
    if ($Evidence.cycles.ContainsKey($MarketKey)) { $cycles = @($Evidence.cycles[$MarketKey]) }

    if ($stock -gt 0) {
        # If already at the destination, fresh current stock is direct evidence.
        if ($ArrivalSeconds -le 60) {
            return [pscustomobject]@{
                currentStock = $stock
                estimatedQuantity = $stock
                probabilityKnown = $true
                probability = 1.0
                sampleCount = 0
                mode = 'live_now'
            }
        }

        $restockAt = 0L
        if ($null -ne $DestinationState) {
            $activeCycle = Get-OptimalProperty $DestinationState 'activeCycle'
            if ($null -ne $activeCycle -and $activeCycle.PSObject.Properties['restockAt']) { $restockAt = [long]$activeCycle.restockAt }
        }
        $age = 0L
        if ($restockAt -gt 0) { $age = [Math]::Max(0L, $NowEpoch - $restockAt) }
        $requiredAge = $age + $ArrivalSeconds
        $durations = @($cycles | Where-Object {
            $_.PSObject.Properties['availabilitySeconds'] -and [long]$_.availabilitySeconds -gt 0
        } | ForEach-Object { [long]$_.availabilitySeconds })

        if ($durations.Count -lt $MinimumSamples) {
            return [pscustomobject]@{
                currentStock = $stock
                estimatedQuantity = $stock
                probabilityKnown = $false
                probability = -1.0
                sampleCount = $durations.Count
                mode = 'in_stock_learning'
            }
        }

        $hits = @($durations | Where-Object { $_ -ge $requiredAge }).Count
        return [pscustomobject]@{
            currentStock = $stock
            estimatedQuantity = $stock
            probabilityKnown = $true
            probability = ($hits / [double]$durations.Count)
            sampleCount = $durations.Count
            mode = 'in_stock'
        }
    }

    $lastSellOutAt = 0L
    if ($null -ne $DestinationState -and $DestinationState.PSObject.Properties['lastSellOutAt']) { $lastSellOutAt = [long]$DestinationState.lastSellOutAt }
    $usable = @($cycles | Where-Object {
        $_.PSObject.Properties['restockDelaySeconds'] -and [long]$_.restockDelaySeconds -gt 0 -and
        $_.PSObject.Properties['availabilitySeconds'] -and [long]$_.availabilitySeconds -gt 0
    })

    if ($lastSellOutAt -le 0 -or $usable.Count -lt $MinimumSamples) {
        return [pscustomobject]@{
            currentStock = 0L
            estimatedQuantity = 0L
            probabilityKnown = $false
            probability = -1.0
            sampleCount = $usable.Count
            mode = 'out_of_stock_learning'
        }
    }

    $targetAge = [Math]::Max(0L, $NowEpoch - $lastSellOutAt) + $ArrivalSeconds
    $hits = 0
    foreach ($cycle in $usable) {
        $delay = [long]$cycle.restockDelaySeconds
        $availability = [long]$cycle.availabilitySeconds
        if ($delay -le $targetAge -and $targetAge -lt ($delay + $availability)) { $hits++ }
    }

    $quantity = 0L
    if ($Evidence.restockStock.ContainsKey($MarketKey)) {
        $samples = [long[]]@($Evidence.restockStock[$MarketKey] | ForEach-Object { [long]$_ })
        $quantity = Get-OptimalMedian $samples
    }
    if ($quantity -le 0) {
        $cycleQuantitySamples=[long[]]@($usable | Where-Object {
            $_.PSObject.Properties['restockQuantity'] -and [long]$_.restockQuantity -gt 0
        } | ForEach-Object { [long]$_.restockQuantity })
        if ($cycleQuantitySamples.Count -gt 0) { $quantity=Get-OptimalMedian $cycleQuantitySamples }
    }

    return [pscustomobject]@{
        currentStock = 0L
        estimatedQuantity = $quantity
        probabilityKnown = $true
        probability = ($hits / [double]$usable.Count)
        sampleCount = $usable.Count
        mode = 'restock_forecast'
    }
}

function Get-OptimalResaleSnapshot {
    param([object]$Engine, [int]$ItemId, [long]$NowEpoch, [long]$FreshSeconds = 21600)
    $row = $null
    if ($null -ne $Engine -and $Engine.PSObject.Properties['resaleCache']) {
        $row = Get-OptimalProperty $Engine.resaleCache ([string]$ItemId)
    }

    $marketValue = 0L
    $fetchedAt = 0L
    if ($null -ne $row) {
        # Torn itemmarket.item.average_price is the MV reference used for route value.
        if ($row.PSObject.Properties['average']) { $marketValue = [long]$row.average }
        if ($row.PSObject.Properties['fetchedAt']) { $fetchedAt = [long]$row.fetchedAt }
    }
    $fresh = ($marketValue -gt 0 -and $fetchedAt -gt 0 -and ($NowEpoch - $fetchedAt) -le $FreshSeconds)
    return [pscustomobject]@{ marketValue = $marketValue; fetchedAt = $fetchedAt; fresh = $fresh }
}

function Test-OptimalMarketFilters {
    param([object]$Preferences, [string]$CountryId, [string]$TripBand, [int]$ItemId, [string]$Category)
    if (@($Preferences.ignoredItemIds) -contains $ItemId) { return $false }
    if (-not [bool]$Preferences.itemFilterAll -and -not (@($Preferences.selectedItemIds) -contains $ItemId)) { return $false }
    if (-not (@($Preferences.selectedTripBands) -contains $TripBand)) { return $false }
    if (-not (@($Preferences.selectedCountryIds) -contains $CountryId)) { return $false }
    if (-not [bool]$Preferences.categoryFilterAll -and -not (@($Preferences.selectedCategories) -contains $Category)) { return $false }
    return $true
}

function Get-OptimalMarketMetadata {
    param([object]$Engine, [int]$ItemId, [object]$Market)
    $name = 'Item ' + $ItemId
    if ($Market.PSObject.Properties['providerName']) { $name = [string]$Market.providerName }
    $category = 'Unknown'
    if ($Engine.PSObject.Properties['itemMetadata']) {
        $metadata = Get-OptimalProperty $Engine.itemMetadata ([string]$ItemId)
        if ($null -ne $metadata) {
            if ($metadata.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$metadata.name)) { $name = [string]$metadata.name }
            if ($metadata.PSObject.Properties['category']) { $category = [string]$metadata.category }
        }
    }
    return [pscustomobject]@{ itemId = $ItemId; name = $name; category = $category }
}

function Add-OptimalPlanQuantity {
    param([hashtable]$Plan, [object]$Candidate, [int]$Quantity)
    if ($Quantity -le 0) { return }
    $key = [string]$Candidate.itemId
    if (-not $Plan.ContainsKey($key)) {
        $Plan[$key] = [pscustomobject]@{
            itemId = [int]$Candidate.itemId
            name = [string]$Candidate.name
            category = [string]$Candidate.category
            quantity = 0
            foreignPrice = [long]$Candidate.foreignPrice
            marketValue = [long]$Candidate.marketValue
            sellBasis = [long]$Candidate.sellBasis
            profitPerItem = [long]$Candidate.profitPerItem
            probability = [double]$Candidate.probability
            probabilityKnown = [bool]$Candidate.probabilityKnown
            expectedUnitProfit = [double]$Candidate.expectedUnitProfit
            priceColor = [string]$Candidate.priceColor
            sourceTimestamp = [long]$Candidate.sourceTimestamp
        }
    }
    $Plan[$key].quantity = [int]$Plan[$key].quantity + $Quantity
}

function Get-OptimalCountryPlan {
    param(
        [object]$Country,
        [object[]]$Candidates,
        [int]$GeneralCapacity,
        [long]$TravelCost,
        [long]$HorizonSeconds,
        [object]$EnergyWaste,
        [object]$NerveWaste,
        [int]$MaxPlanItems = 8,
        [bool]$ShowProfitableOnly = $false
    )

    if ($null -eq $Candidates -or $Candidates.Count -eq 0 -or $GeneralCapacity -le 0) { return $null }
    $sorted = @($Candidates | Sort-Object @{ Expression = 'expectedUnitProfit'; Descending = $true }, @{ Expression = 'probability'; Descending = $true }, itemId)
    $plan = @{}
    $remaining = $GeneralCapacity

    foreach ($candidate in $sorted) {
        if ($remaining -le 0 -or $plan.Count -ge $MaxPlanItems) { break }
        $quantity = [Math]::Min($remaining, [int]$candidate.availableQuantity)
        if ($quantity -le 0) { continue }
        Add-OptimalPlanQuantity -Plan $plan -Candidate $candidate -Quantity $quantity
        $candidate.allocated = $quantity
        $remaining -= $quantity
    }

    # Category-only company slots are capacity above the general/Xanax capacity.
    # Current Torn company effects make these mutually exclusive (Flower or Plushie),
    # so the maximum candidate extra is the route's category-only slot pool.
    $extraSlots = 0
    foreach ($candidate in $sorted) { $extraSlots = [Math]::Max($extraSlots, [int]$candidate.extraCapacity) }
    $extraRemaining = $extraSlots
    if ($extraRemaining -gt 0) {
        foreach ($candidate in @($sorted | Where-Object { [int]$_.extraCapacity -gt 0 })) {
            if ($extraRemaining -le 0) { break }
            if (-not $plan.ContainsKey([string]$candidate.itemId) -and $plan.Count -ge $MaxPlanItems) { continue }
            $alreadyAllocated = [int]$candidate.allocated
            $available = [Math]::Max(0, [int]$candidate.availableQuantity - $alreadyAllocated)
            $quantity = [Math]::Min($extraRemaining, $available)
            if ($quantity -le 0) { continue }
            Add-OptimalPlanQuantity -Plan $plan -Candidate $candidate -Quantity $quantity
            $candidate.allocated = $alreadyAllocated + $quantity
            $extraRemaining -= $quantity
        }
    }

    $rows = @($plan.Values | Sort-Object @{ Expression = 'expectedUnitProfit'; Descending = $true }, name)
    if ($rows.Count -eq 0) { return $null }

    $quantityTotal = [int](($rows | Measure-Object quantity -Sum).Sum)
    $targetCapacity = $GeneralCapacity + $extraSlots
    $rawItemProfit = 0.0
    $expectedItemProfit = 0.0
    $probabilityQuantity = 0.0
    $knownQuantity = 0

    foreach ($row in $rows) {
        $rawItemProfit += [double]$row.quantity * [double]$row.profitPerItem
        $probabilityFactor = [Math]::Max(0.0, [Math]::Min(1.0, [double]$row.probability))
        $expectedItemProfit += [double]$row.quantity * [double]$row.profitPerItem * $probabilityFactor
        $probabilityQuantity += [double]$row.quantity * $probabilityFactor
        $knownQuantity += [int]$row.quantity
    }

    $rawTripProfit = [long][Math]::Round($rawItemProfit - $TravelCost)
    $expectedTripProfit = [long][Math]::Round($expectedItemProfit - $TravelCost)
    if ($ShowProfitableOnly -and $rawTripProfit -le 0) { return $null }

    $hours = [Math]::Max(1.0 / 60.0, $HorizonSeconds / 3600.0)
    $score = $expectedTripProfit / $hours
    $routeProbability = -1.0
    if ($knownQuantity -gt 0) { $routeProbability = $probabilityQuantity / $knownQuantity }

    return [pscustomobject]@{
        countryId = [string]$Country.id
        countryName = [string]$Country.name
        tripBand = [string]$Country.tripBand
        plan = $rows
        quantity = $quantityTotal
        capacity = $targetCapacity
        generalCapacity = $GeneralCapacity
        extraCapacity = $extraSlots
        travelCost = [long]$TravelCost
        rawTripProfit = $rawTripProfit
        expectedTripProfit = $expectedTripProfit
        score = [double]$score
        routeProbability = [double]$routeProbability
        energyWaste = $EnergyWaste
        nerveWaste = $NerveWaste
        horizonSeconds = [long]$HorizonSeconds
    }
}

function Format-OptimalDuration {
    param([long]$Seconds)
    $Seconds = [Math]::Max(0, $Seconds)
    $hours = [Math]::Floor($Seconds / 3600)
    $minutes = [Math]::Floor(($Seconds % 3600) / 60)
    if ($hours -gt 0) { return ('{0}h {1}m' -f $hours, $minutes) }
    return ('{0}m' -f $minutes)
}

function Format-OptimalMoney {
    param([long]$Value)
    $sign = ''
    if ($Value -lt 0) { $sign = '-' }
    return ('{0}${1:N0}' -f $sign, [Math]::Abs($Value))
}

function Write-OptimalProjection {
    param(
        [hashtable]$State,
        [object]$Route,
        [string]$Message,
        [int]$BasisPercent,
        [string]$TravelState,
        [long]$ArrivalSeconds = 0
    )

    $State['OptimalVisible'] = 0
    if ($null -ne $Route) { $State['OptimalVisible'] = 1 }
    $State['OptimalMessage'] = $Message
    $State['OptimalProfitBasisPercent'] = $BasisPercent
    $State['OptimalProfitBasisText'] = ('{0}% MV' -f $BasisPercent)
    $State['OptimalTravelState'] = $TravelState
    $State['OptimalCountryId'] = ''
    $State['OptimalCountryName'] = ''
    $State['OptimalTripBand'] = ''
    $State['OptimalCapacityText'] = ''
    $State['OptimalTravelText'] = ''
    $State['OptimalExpectedProfitText'] = ''
    $State['OptimalChanceText'] = ''
    $State['OptimalEnergyText'] = ''
    $State['OptimalNerveText'] = ''
    $State['OptimalArrivalText'] = ''

    foreach ($index in 1..8) {
        foreach ($suffix in @('Name', 'Category', 'QtyText', 'PriceText', 'MarketValueText', 'ChanceText', 'PriceColor', 'Tooltip')) {
            $State['OptimalItem' + $index + $suffix] = ''
        }
    }
    $State['OptimalItemCount'] = 0
    if ($null -eq $Route) { return }

    $State['OptimalCountryId'] = [string]$Route.countryId
    $State['OptimalCountryName'] = [string]$Route.countryName
    $State['OptimalTripBand'] = [string]$Route.tripBand
    $State['OptimalCapacityText'] = ('{0}/{1} slots' -f [int]$Route.quantity, [int]$Route.capacity)
    $State['OptimalTravelText'] = Format-OptimalDuration ([long]$Route.horizonSeconds)
    $State['OptimalExpectedProfitText'] = Format-OptimalMoney ([long]$Route.expectedTripProfit)
    if ([double]$Route.routeProbability -ge 0) { $State['OptimalChanceText'] = ('hit: {0:N0}%' -f (100.0 * [double]$Route.routeProbability)) }
    else { $State['OptimalChanceText'] = 'hit: learning' }

    $energy = $Route.energyWaste
    $nerve = $Route.nerveWaste
    if ($null -ne $energy -and [bool]$energy.bypass) { $State['OptimalEnergyText'] = 'E: stacked' }
    elseif ($null -ne $energy -and [bool]$energy.known) { $State['OptimalEnergyText'] = 'E loss: ' + [string][long]$energy.loss }
    else { $State['OptimalEnergyText'] = 'E: ?' }

    if ($null -ne $nerve -and [bool]$nerve.known) { $State['OptimalNerveText'] = 'N loss: ' + [string][long]$nerve.loss }
    else { $State['OptimalNerveText'] = 'N: ?' }

    if ($TravelState -eq 'traveling' -and $ArrivalSeconds -gt 0) { $State['OptimalArrivalText'] = 'arrive ' + (Format-OptimalDuration $ArrivalSeconds) }
    elseif ($TravelState -eq 'abroad' -or $TravelState -eq 'foreign') { $State['OptimalArrivalText'] = 'at destination' }
    else { $State['OptimalArrivalText'] = 'out ' + (Format-OptimalDuration ([long]($Route.horizonSeconds / 2))) }

    $rows = @($Route.plan)
    $count = [Math]::Min(8, $rows.Count)
    $State['OptimalItemCount'] = $count
    for ($offset = 0; $offset -lt $count; $offset++) {
        $row = $rows[$offset]
        $number = $offset + 1
        $State['OptimalItem' + $number + 'Name'] = [string]$row.name
        $State['OptimalItem' + $number + 'Category'] = [string]$row.category
        $State['OptimalItem' + $number + 'QtyText'] = 'x' + [string][int]$row.quantity
        $State['OptimalItem' + $number + 'PriceText'] = ('${0:N0}' -f [long]$row.foreignPrice)
        $State['OptimalItem' + $number + 'MarketValueText'] = ('${0:N0}' -f [long]$row.marketValue)
        $State['OptimalItem' + $number + 'ChanceText'] = ('{0:N0}%' -f (100.0 * [double]$row.probability))
        $State['OptimalItem' + $number + 'PriceColor'] = [string]$row.priceColor
        $State['OptimalItem' + $number + 'Tooltip'] = ('{0}% MV basis {1}; {2}/item before travel; qty {3}; modeled arrival availability {4}' -f $BasisPercent, (Format-OptimalMoney ([long]$row.sellBasis)), (Format-OptimalMoney ([long]$row.profitPerItem)), [int]$row.quantity, [string]$State['OptimalItem' + $number + 'ChanceText'])
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
$profile = Get-TravelProfile -BaseSettings $settings -LocalSettings $local
$evidence = Get-OptimalEvidence
$optimizerSettings = Get-OptimalProperty $settings 'optimizer'
$minimumSamples = 3
$purchaseBuffer = 60L
$maxPlanItems = 8
if ($null -ne $optimizerSettings) {
    if ($optimizerSettings.PSObject.Properties['minimumAvailabilitySamples']) { $minimumSamples = [int]$optimizerSettings.minimumAvailabilitySamples }
    if ($optimizerSettings.PSObject.Properties['purchaseBufferSeconds']) { $purchaseBuffer = [long]$optimizerSettings.purchaseBufferSeconds }
    if ($optimizerSettings.PSObject.Properties['maxPlanItems']) { $maxPlanItems = [int]$optimizerSettings.maxPlanItems }
}
$minimumSamples = [Math]::Max(1, $minimumSamples)
$maxPlanItems = [Math]::Max(1, [Math]::Min(8, $maxPlanItems))
$basisPercent = 100
if ([bool]$preferences.use95PercentMarketValue) { $basisPercent = 95 }
$travelMode = [string]$preferences.travelMode
$travelContext = Get-OptimalProperty $engine 'travelContext'
$travelState = 'unknown'
if ($null -ne $travelContext) { $travelState = [string](Get-OptimalProperty $travelContext 'state') }
$fixedCountry = ''
if ($null -ne $travelContext -and [bool](Get-OptimalProperty $travelContext 'filterActive')) { $fixedCountry = [string](Get-OptimalProperty $travelContext 'destinationCountryId') }

if ($travelState -eq 'returning') {
    Write-OptimalProjection -State $state -Route $null -Message 'Returning to Torn - next route available on arrival' -BasisPercent $basisPercent -TravelState $travelState
    Write-OptimalStateKvAtomic -Values $state -Path $StateKvFile
    return
}

$pricingPriority = New-Object 'System.Collections.Generic.HashSet[int]'
$routes = New-Object System.Collections.Generic.List[object]
$availabilityLearning = 0
$staleMarkets = 0
$staleAfter = [long]$settings.staleAfterSeconds
if ($staleAfter -lt 60) { $staleAfter = 60 }

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

    $arrivalSeconds = $oneWaySeconds
    $horizonSeconds = (2 * $oneWaySeconds) + $purchaseBuffer
    $travelCostMultiplier = 2
    if (-not [string]::IsNullOrWhiteSpace($fixedCountry)) {
        if ($travelState -eq 'traveling') {
            $timeLeft = [long](Get-OptimalProperty $travelContext 'timeLeft')
            if ($timeLeft -gt 0) { $arrivalSeconds = $timeLeft }
            $horizonSeconds = $arrivalSeconds + $oneWaySeconds + $purchaseBuffer
            $travelCostMultiplier = 1
        } elseif ($travelState -eq 'abroad' -or $travelState -eq 'foreign') {
            $arrivalSeconds = 0
            $horizonSeconds = $oneWaySeconds + $purchaseBuffer
            $travelCostMultiplier = 1
        }
    }

    $neutralItem = [pscustomobject]@{ itemId = 0; category = '' }
    $neutralEffects = Get-TravelProfileEffects -Profile $profile -PerksConfig $perks -Item $neutralItem
    $capacityOverride = 0
    if ($settings.profitability.PSObject.Properties['capacityOverride']) { $capacityOverride = [int]$settings.profitability.capacityOverride }
    $generalEconomics = Get-EffectiveTravelEconomics -Country $country -TravelMode $travelMode -Effects $neutralEffects -CapacityOverride $capacityOverride
    if (-not [bool]$generalEconomics.capacityKnown -or -not [bool]$generalEconomics.travelCostKnown -or [int]$generalEconomics.capacity -le 0) { continue }
    $generalCapacity = [int]$generalEconomics.capacity
    $routeTravelCost = [long]$generalEconomics.travelCost * $travelCostMultiplier

    $energy = Get-OptimalBarWaste -Bar (Get-OptimalProperty $travelContext 'energy') -HorizonSeconds $horizonSeconds -NowEpoch $Now -EnergyStackBypass
    $nerve = Get-OptimalBarWaste -Bar (Get-OptimalProperty $travelContext 'nerve') -HorizonSeconds $horizonSeconds -NowEpoch $Now

    # Do not reject a route after the user has already committed to the destination.
    $constraintsApply = [string]::IsNullOrWhiteSpace($fixedCountry)
    if ($constraintsApply) {
        if (-not (Test-OptimalWastePolicy -Waste $energy -Policy ([string]$preferences.energyWastePolicy) -MaximumLoss ([int]$preferences.maxEnergyLoss))) { continue }
        if (-not (Test-OptimalWastePolicy -Waste $nerve -Policy ([string]$preferences.nerveWastePolicy) -MaximumLoss ([int]$preferences.maxNerveLoss))) { continue }
    }

    $candidates = New-Object System.Collections.Generic.List[object]
    foreach ($property in @($engine.observedMarkets.PSObject.Properties)) {
        $market = $property.Value
        if ($null -eq $market) { continue }
        if ([string](Get-OptimalProperty $market 'country') -ne $countryId) { continue }
        if (($market.PSObject.Properties['catalogActive'] -and $market.catalogActive -eq $false) -or
            ($market.PSObject.Properties['catalogStatus'] -and [string]$market.catalogStatus -eq 'legacy_removed')) { continue }

        $sourceTimestamp = 0L
        if ($market.PSObject.Properties['sourceTimestamp']) { $sourceTimestamp = [long]$market.sourceTimestamp }
        if ($sourceTimestamp -le 0 -or ($Now - $sourceTimestamp) -gt $staleAfter) { $staleMarkets++; continue }

        $itemId = [int](Get-OptimalProperty $market 'itemId')
        if ($itemId -le 0) { continue }
        $metadata = Get-OptimalMarketMetadata -Engine $engine -ItemId $itemId -Market $market
        if (-not (Test-OptimalMarketFilters -Preferences $preferences -CountryId $countryId -TripBand $tripBand -ItemId $itemId -Category ([string]$metadata.category))) { continue }

        $resale = Get-OptimalResaleSnapshot -Engine $engine -ItemId $itemId -NowEpoch $Now
        if (-not [bool]$resale.fresh) { [void]$pricingPriority.Add($itemId); continue }

        $foreignPrice = [long](Get-OptimalProperty $market 'lastForeignPrice')
        if ($foreignPrice -le 0) { continue }
        $destinationState = $null
        if ($engine.PSObject.Properties['destinations']) { $destinationState = Get-OptimalProperty $engine.destinations ($countryId + ':' + $itemId) }
        $forecast = Get-OptimalArrivalForecast -MarketKey ($countryId + ':' + $itemId) -Market $market -DestinationState $destinationState -Evidence $evidence -ArrivalSeconds $arrivalSeconds -NowEpoch $Now -MinimumSamples $minimumSamples
        if (-not [bool]$forecast.probabilityKnown) { $availabilityLearning++; continue }
        if ([double]$forecast.probability -le 0 -or [long]$forecast.estimatedQuantity -le 0) { continue }

        $item = [pscustomobject]@{ itemId = $itemId; category = [string]$metadata.category }
        $effects = Get-TravelProfileEffects -Profile $profile -PerksConfig $perks -Item $item
        $itemEconomics = Get-EffectiveTravelEconomics -Country $country -TravelMode $travelMode -Effects $effects -CapacityOverride $capacityOverride
        $itemCapacity = $generalCapacity
        if ([bool]$itemEconomics.capacityKnown) { $itemCapacity = [int]$itemEconomics.capacity }
        $extraCapacity = [Math]::Max(0, $itemCapacity - $generalCapacity)

        $sellBasis = [long][Math]::Floor([long]$resale.marketValue * ($basisPercent / 100.0))
        $profitPerItem = [long]($sellBasis - $foreignPrice)
        if ([bool]$preferences.showProfitableOnly -and $profitPerItem -le 0) { continue }

        $probabilityFactor = [Math]::Max(0.0, [Math]::Min(1.0, [double]$forecast.probability))
        $priceColor = '224,90,90,255'
        if ($foreignPrice -le $sellBasis) { $priceColor = '86,190,116,255' }
        $candidates.Add([pscustomobject]@{
            itemId = $itemId
            name = [string]$metadata.name
            category = [string]$metadata.category
            foreignPrice = $foreignPrice
            marketValue = [long]$resale.marketValue
            sellBasis = $sellBasis
            profitPerItem = $profitPerItem
            probabilityKnown = $true
            probability = [double]$forecast.probability
            availableQuantity = [Math]::Max(0, [int]$forecast.estimatedQuantity)
            extraCapacity = $extraCapacity
            expectedUnitProfit = [double]$profitPerItem * $probabilityFactor
            priceColor = $priceColor
            sourceTimestamp = $sourceTimestamp
            allocated = 0
        })
    }

    $route = Get-OptimalCountryPlan -Country $country -Candidates $candidates.ToArray() -GeneralCapacity $generalCapacity -TravelCost $routeTravelCost -HorizonSeconds $horizonSeconds -EnergyWaste $energy -NerveWaste $nerve -MaxPlanItems $maxPlanItems -ShowProfitableOnly ([bool]$preferences.showProfitableOnly)
    if ($null -ne $route) {
        $route | Add-Member NoteProperty arrivalSeconds $arrivalSeconds
        $routes.Add($route)
    }
}

$best = $null
if ($routes.Count -gt 0) {
    $best = @($routes | Sort-Object @{ Expression = 'score'; Descending = $true }, @{ Expression = 'expectedTripProfit'; Descending = $true }, horizonSeconds | Select-Object -First 1)[0]
}

$message = 'No route satisfies current filters and waste constraints'
if ($null -ne $best) { $message = 'Optimal route from current stock, MV, capacity, travel time, and observed availability' }
elseif ($pricingPriority.Count -gt 0) { $message = 'Learning market values - optimizer pricing queue still filling' }
elseif ($availabilityLearning -gt 0) { $message = 'Learning availability - more completed stock cycles are needed' }
elseif ($staleMarkets -gt 0) { $message = 'Foreign stock is stale - waiting for a fresh provider poll' }

$bestArrivalSeconds = 0L
if ($null -ne $best -and $best.PSObject.Properties['arrivalSeconds']) { $bestArrivalSeconds = [long]$best.arrivalSeconds }
Write-OptimalProjection -State $state -Route $best -Message $message -BasisPercent $basisPercent -TravelState $travelState -ArrivalSeconds $bestArrivalSeconds
Write-OptimalStateKvAtomic -Values $state -Path $StateKvFile

if (-not $engine.PSObject.Properties['optimizer']) { $engine | Add-Member NoteProperty optimizer ([pscustomobject]@{}) }
$selectedCountryId = ''
$selectedQuantity = 0
$selectedCapacity = 0
$selectedExpectedTripProfit = 0L
if ($null -ne $best) {
    $selectedCountryId = [string]$best.countryId
    $selectedQuantity = [int]$best.quantity
    $selectedCapacity = [int]$best.capacity
    $selectedExpectedTripProfit = [long]$best.expectedTripProfit
}
Set-OptimalProperty $engine.optimizer 'lastRunAt' $Now
Set-OptimalProperty $engine.optimizer 'marketValueBasisPercent' $basisPercent
Set-OptimalProperty $engine.optimizer 'pricingPriorityItemIds' ([int[]]@($pricingPriority | Sort-Object))
Set-OptimalProperty $engine.optimizer 'candidateRoutes' $routes.Count
Set-OptimalProperty $engine.optimizer 'availabilityLearningItems' $availabilityLearning
Set-OptimalProperty $engine.optimizer 'staleMarkets' $staleMarkets
Set-OptimalProperty $engine.optimizer 'selectedCountryId' $selectedCountryId
Set-OptimalProperty $engine.optimizer 'selectedQuantity' $selectedQuantity
Set-OptimalProperty $engine.optimizer 'selectedCapacity' $selectedCapacity
Set-OptimalProperty $engine.optimizer 'selectedExpectedTripProfit' $selectedExpectedTripProfit
Write-OptimalJsonAtomic -Path $EngineStateFile -Value $engine
