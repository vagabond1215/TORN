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

# The standalone OPTIMAL route card / projection stage is retired. This file is
# retained only as a local helper library used by OpportunityState and deterministic
# tests (evidence loading, arrival forecasting, waste policy, resale lookup, and
# capacity-aware country planning). Direct execution intentionally performs no work.
if ($SkipMain) { return }
return
