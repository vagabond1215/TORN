param(
    [Alias('SkipMain')]
    [switch]$StochasticForecastSkipMain,
    [long]$Now = 0,
    [ValidateRange(16,5000)]
    [int]$SimulationCount = 128,
    [ValidateRange(60,86400)]
    [int]$GridSeconds = 900,
    [ValidateRange(300,172800)]
    [int]$DepartureSearchSeconds = 43200,
    [int]$Seed = 0
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RuntimeDir=Join-Path $ProjectRoot 'data\runtime'
$GeneratedDir=Join-Path $ProjectRoot '@Resources\Generated'
$EngineStateFile=Join-Path $RuntimeDir 'engine-state.json'
$StateKvFile=Join-Path $GeneratedDir 'state.kv'
$RuntimeCycleFile=Join-Path $RuntimeDir 'cycles.jsonl'
$SeedCycleFile=Join-Path $ProjectRoot 'data\seed\cycles.jsonl'
$RuntimeObservationFile=Join-Path $RuntimeDir 'observations.jsonl'
$SeedObservationFile=Join-Path $ProjectRoot 'data\seed\observations.jsonl'
$ArtifactFile=Join-Path $RuntimeDir 'stochastic-forecast.json'
$AtomicFileScript=Join-Path $PSScriptRoot 'AtomicFile.ps1'
$CycleFilterScript=Join-Path $PSScriptRoot 'CycleForecastFilter.ps1'
if (-not (Test-Path -LiteralPath $AtomicFileScript)) { throw 'AtomicFile.ps1 is required for stochastic artifact publication.' }
if (-not (Test-Path -LiteralPath $CycleFilterScript)) { throw 'CycleForecastFilter.ps1 is required for stochastic evidence filtering.' }
. $AtomicFileScript
. $CycleFilterScript

function Get-SFProperty {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property=$Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Read-SFJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw=Read-TravelAssistantSharedText -Path $Path
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Read-SFStateKv {
    param([string]$Path)
    $state=@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $state }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $at=$line.IndexOf('=')
        if ($at -lt 1) { continue }
        $state[$line.Substring(0,$at).Trim([char]0xFEFF).Trim()]=$line.Substring($at+1).Trim()
    }
    return $state
}

function Get-SFStableSeed {
    param([string]$MarketKey,[int]$BaseSeed=0)
    [long]$hash=2166136261L
    foreach ($character in ([string]$MarketKey).ToCharArray()) {
        $hash=(($hash -bxor [int][char]$character) * 16777619L) -band 0x7fffffff
    }
    # Keep common random numbers across minute-to-minute runs. If retained
    # evidence is unchanged, forecast movement should come from the advancing
    # arrival horizon / posterior conditioning rather than a brand-new RNG draw.
    $hash=($hash -bxor $BaseSeed) -band 0x7fffffff
    if ($hash -eq 0) { $hash=1 }
    return [int]$hash
}

function Get-SFBoundedLong {
    param([object]$Object,[string]$MinimumName,[string]$MaximumName,[string]$FallbackName,[long]$Floor=0L)
    $fallback=[long](Get-SFProperty $Object $FallbackName)
    $minimum=[long](Get-SFProperty $Object $MinimumName)
    $maximum=[long](Get-SFProperty $Object $MaximumName)
    if ($minimum -lt $Floor) { $minimum=[Math]::Max($Floor,$fallback) }
    if ($maximum -lt $minimum) { $maximum=[Math]::Max($minimum,$fallback) }
    return [pscustomobject]@{ minimum=[long]$minimum; maximum=[long]$maximum }
}

function Get-SFEvidenceQualityWeight {
    param([object]$Cycle)
    $quality=([string](Get-SFProperty $Cycle 'evidenceQuality')).Trim().ToLowerInvariant()
    if ($quality -eq 'bounded_gap') { return 0.5 }
    if ($quality -eq 'bounded_fresh') { return 1.0 }

    $qualities=@(
        ([string](Get-SFProperty $Cycle 'restockBoundaryQuality')).Trim().ToLowerInvariant(),
        ([string](Get-SFProperty $Cycle 'soldOutBoundaryQuality')).Trim().ToLowerInvariant(),
        ([string](Get-SFProperty $Cycle 'previousSellOutBoundaryQuality')).Trim().ToLowerInvariant()
    )
    if (@($qualities | Where-Object { $_ -eq 'bounded' }).Count -gt 0) { return 0.75 }
    return 1.0
}

function Select-SFJointCycleEvidence {
    param(
        [object[]]$Cycles,
        [long]$AsOf,
        [object[]]$Observations=@(),
        [long]$HalfLifeSeconds=1209600L,
        [int]$MaximumSamples=96
    )
    $rows=New-Object System.Collections.Generic.List[object]
    foreach ($cycle in @($Cycles)) {
        if ($null -eq $cycle -or -not (Test-CycleForecastBoundaryEvidence -Cycle $cycle -Purpose Forecast)) { continue }
        $availableAt=[long](Get-SFProperty $cycle 'soldOutUpperBoundAt')
        if ($availableAt -le 0) { $availableAt=[long](Get-SFProperty $cycle 'soldOutAt') }
        if ($availableAt -le 0 -or ($AsOf -gt 0 -and $availableAt -gt $AsOf)) { continue }
        $delay=Get-SFBoundedLong -Object $cycle -MinimumName 'restockDelayMinimumSeconds' -MaximumName 'restockDelayMaximumSeconds' -FallbackName 'restockDelaySeconds' -Floor 1
        $available=Get-SFBoundedLong -Object $cycle -MinimumName 'availabilityMinimumSeconds' -MaximumName 'availabilityMaximumSeconds' -FallbackName 'availabilitySeconds' -Floor 1
        if ([long]$delay.minimum -le 0 -or [long]$available.minimum -le 0) { continue }
        $age=if ($AsOf -gt 0) { [Math]::Max(0L,$AsOf-$availableAt) } else { 0L }
        $recency=[Math]::Exp(-[Math]::Log(2.0)*([double]$age/[Math]::Max(1.0,[double]$HalfLifeSeconds)))
        $qualityWeight=Get-SFEvidenceQualityWeight -Cycle $cycle
        $weight=$recency*$qualityWeight
        if ($weight -le 0) { continue }
        $shape=Get-SFCycleDepletionShape -Cycle $cycle -Observations $Observations
        $rows.Add([pscustomobject]@{
            cycle=$cycle
            availableAt=$availableAt
            weight=[double]$weight
            qualityWeight=[double]$qualityWeight
            delayMinimum=[long]$delay.minimum
            delayMaximum=[long]$delay.maximum
            availabilityMinimum=[long]$available.minimum
            availabilityMaximum=[long]$available.maximum
            quantity=[Math]::Max(1L,[long](Get-SFProperty $cycle 'restockQuantity'))
            foreignPrice=[Math]::Max(0L,[long](Get-SFProperty $cycle 'foreignPrice'))
            depletionShape=$shape
            depletionShapePointCount=$(if($null -ne $shape){[int](Get-SFProperty $shape 'pointCount')}else{0})
        })
    }
    $selected=@($rows.ToArray() | Sort-Object availableAt -Descending)
    if ($MaximumSamples -gt 0 -and $selected.Count -gt $MaximumSamples) { $selected=@($selected | Select-Object -First $MaximumSamples) }
    return $selected
}

function Get-SFEffectiveSampleSize {
    param([object[]]$Evidence)
    $sum=0.0; $sumSquares=0.0
    foreach ($row in @($Evidence)) { $w=[double]$row.weight; $sum+=$w; $sumSquares+=($w*$w) }
    if ($sumSquares -le 0) { return 0.0 }
    return (($sum*$sum)/$sumSquares)
}

function Get-SFWeightedEvidenceRow {
    param([object[]]$Evidence,[System.Random]$Random)
    $total=0.0
    foreach ($row in @($Evidence)) { $total+=[double]$row.weight }
    if ($total -le 0 -or @($Evidence).Count -eq 0) { return $null }
    $target=$Random.NextDouble()*$total
    $running=0.0
    foreach ($row in @($Evidence)) {
        $running+=[double]$row.weight
        if ($target -le $running) { return $row }
    }
    return @($Evidence)[-1]
}

function Get-SFUniformLong {
    param([System.Random]$Random,[long]$Minimum,[long]$Maximum)
    if ($Maximum -le $Minimum) { return [long]$Minimum }
    return [long][Math]::Floor($Minimum+($Random.NextDouble()*([double]($Maximum-$Minimum)+1.0)))
}

function Get-SFEventAt {
    param([object]$Object,[string]$Representative,[string]$Lower,[string]$Upper,[System.Random]$Random)
    $value=[long](Get-SFProperty $Object $Representative)
    $lowerAt=[long](Get-SFProperty $Object $Lower)
    $upperAt=[long](Get-SFProperty $Object $Upper)
    if ($lowerAt -gt 0 -and $upperAt -ge $lowerAt) { return Get-SFUniformLong -Random $Random -Minimum $lowerAt -Maximum $upperAt }
    return $value
}

function Get-SFObservationAt {
    param([object]$Observation)
    $at=[long](Get-SFProperty $Observation 'sourceTimestamp')
    if ($at -le 0) { $at=[long](Get-SFProperty $Observation 'timestamp') }
    return $at
}

function Get-SFCycleDepletionShape {
    param([object]$Cycle,[object[]]$Observations)
    if ($null -eq $Cycle -or @($Observations).Count -eq 0) { return $null }

    $startAt=[long](Get-SFProperty $Cycle 'restockUpperBoundAt')
    if ($startAt -le 0) { $startAt=[long](Get-SFProperty $Cycle 'restockAt') }
    $endAt=[long](Get-SFProperty $Cycle 'soldOutUpperBoundAt')
    if ($endAt -le 0) { $endAt=[long](Get-SFProperty $Cycle 'soldOutAt') }
    $restockQuantity=[long](Get-SFProperty $Cycle 'restockQuantity')
    if ($startAt -le 0 -or $endAt -le $startAt -or $restockQuantity -le 0) { return $null }

    $restockLower=[long](Get-SFProperty $Cycle 'restockLowerBoundAt')
    if ($restockLower -le 0) { $restockLower=$startAt }
    $selloutLower=[long](Get-SFProperty $Cycle 'soldOutLowerBoundAt')
    if ($selloutLower -le 0) { $selloutLower=$endAt }
    $span=[Math]::Max(1L,$endAt-$startAt)
    $boundaryUncertainty=[Math]::Max(0L,$startAt-$restockLower)+[Math]::Max(0L,$endAt-$selloutLower)
    $boundaryUncertaintyRatio=[double]$boundaryUncertainty/[double]$span
    # Intermediate stock points are useful only if phase-boundary censoring does
    # not dominate the cycle itself. Wide brackets keep the cycle for duration
    # learning but fall back to linear quantity rather than fabricating phase.
    if ($boundaryUncertaintyRatio -gt 0.5) { return $null }

    $rows=@($Observations | Where-Object {
        $at=Get-SFObservationAt $_
        $at -ge $startAt -and $at -le $endAt
    } | Sort-Object @{Expression={Get-SFObservationAt $_}})
    if ($rows.Count -lt 2) { return $null }

    $points=New-Object System.Collections.Generic.List[object]
    $points.Add([pscustomobject]@{ x=0.0; y=1.0 })
    $lastX=0.0
    $lastY=1.0
    $informative=0

    foreach ($row in $rows) {
        $at=Get-SFObservationAt $row
        $stock=[long](Get-SFProperty $row 'stock')
        if ($at -le $startAt -or $at -ge $endAt -or $stock -le 0) { continue }

        $x=([double]($at-$startAt))/([double]($endAt-$startAt))
        if ($x -le $lastX -or $x -ge 1.0) { continue }
        $y=[Math]::Max(0.0,[Math]::Min(1.0,([double]$stock/[double]$restockQuantity)))

        # Treat within-cycle quantity as a lost-sales path. Price-only updates or
        # provider corrections can otherwise look like replenishment. Preserve a
        # monotone non-increasing envelope rather than inventing positive inflow.
        $y=[Math]::Min($lastY,$y)
        if ($y -ge ($lastY-0.000001)) { continue }

        $points.Add([pscustomobject]@{ x=[Math]::Round($x,6); y=[Math]::Round($y,6) })
        $lastX=$x
        $lastY=$y
        $informative++
    }

    if ($informative -lt 1) { return $null }
    $points.Add([pscustomobject]@{ x=1.0; y=0.0 })

    return [pscustomobject]@{
        source='retained_observation_shape'
        pointCount=$points.Count
        observedStartAt=$startAt
        observedEndAt=$endAt
        boundaryUncertaintyRatio=[Math]::Round($boundaryUncertaintyRatio,6)
        points=$points.ToArray()
    }
}

function Get-SFDepletionFraction {
    param([object]$Shape,[double]$Progress)
    $p=[Math]::Max(0.0,[Math]::Min(1.0,$Progress))
    if ($null -eq $Shape) { return [Math]::Max(0.0,1.0-$p) }
    $points=@(Get-SFProperty $Shape 'points')
    if ($points.Count -lt 2) { return [Math]::Max(0.0,1.0-$p) }

    if ($p -le [double]$points[0].x) {
        return [Math]::Max(0.0,[Math]::Min(1.0,[double]$points[0].y))
    }

    for ($i=0; $i -lt ($points.Count-1); $i++) {
        $left=$points[$i]
        $right=$points[$i+1]
        $x0=[double]$left.x
        $x1=[double]$right.x
        if ($p -gt $x1 -and $i -lt ($points.Count-2)) { continue }
        if ($x1 -le $x0) {
            return [Math]::Max(0.0,[Math]::Min(1.0,[double]$right.y))
        }
        $fraction=($p-$x0)/($x1-$x0)
        $y=[double]$left.y+($fraction*([double]$right.y-[double]$left.y))
        return [Math]::Max(0.0,[Math]::Min(1.0,$y))
    }
    return 0.0
}

function Get-SFIntervalQuantity {
    param([object]$Interval,[long]$ArrivalAt)
    if ($null -eq $Interval) { return 0L }
    $start=[long](Get-SFProperty $Interval 'startAt')
    $end=[long](Get-SFProperty $Interval 'endAt')
    $quantity=[long](Get-SFProperty $Interval 'quantity')
    if ($quantity -le 0 -or $ArrivalAt -lt $start -or $ArrivalAt -ge $end) { return 0L }

    $duration=[Math]::Max(1L,$end-$start)
    $progress=([double]($ArrivalAt-$start))/([double]$duration)
    $remainingFraction=Get-SFDepletionFraction -Shape (Get-SFProperty $Interval 'depletionShape') -Progress $progress
    return [long][Math]::Max(0L,[Math]::Ceiling([double]$quantity*$remainingFraction))
}

function New-SFStockInterval {
    param([long]$StartAt,[long]$EndAt,[long]$Quantity,[long]$ForeignPrice,[int]$Ordinal,[object]$DepletionShape=$null)
    return [pscustomobject]@{
        startAt=[long]$StartAt
        endAt=[long]$EndAt
        quantity=[long][Math]::Max(1L,$Quantity)
        foreignPrice=[long][Math]::Max(0L,$ForeignPrice)
        cycleOrdinal=[int]$Ordinal
        depletionShape=$DepletionShape
    }
}

function New-SFMarketWorld {
    param(
        [object[]]$Evidence,
        [object]$Market,
        [object]$Destination,
        [long]$NowEpoch,
        [long]$HorizonAt,
        [System.Random]$Random,
        [long]$FreshSeconds=300L
    )
    $intervals=New-Object System.Collections.Generic.List[object]
    $sourceAt=[long](Get-SFProperty $Market 'sourceTimestamp')
    $currentStock=[long](Get-SFProperty $Market 'lastStock')
    $currentPrice=[long](Get-SFProperty $Market 'lastForeignPrice')
    $sourceFresh=($sourceAt -gt 0 -and $sourceAt -le $NowEpoch -and ($NowEpoch-$sourceAt) -le $FreshSeconds)
    if (-not $sourceFresh) { $currentStock=0L }
    $anchor=0L
    $ordinal=0

    if ($currentStock -gt 0) {
        $sample=Get-SFWeightedEvidenceRow -Evidence $Evidence -Random $Random
        if ($null -eq $sample) { return @() }
        $active=Get-SFProperty $Destination 'activeCycle'
        $restockAt=Get-SFEventAt -Object $active -Representative 'restockAt' -Lower 'restockLowerBoundAt' -Upper 'restockUpperBoundAt' -Random $Random
        $observationAt=$sourceAt

        if ($restockAt -gt 0 -and $restockAt -le $observationAt) {
            # Condition empirical duration on the fact that inventory was still
            # positive at the provider timestamp. This is survival conditioning,
            # not permission to assume the same stock is still present at Now.
            $observedAge=[Math]::Max(0L,$observationAt-$restockAt)
            $survivalEvidence=@($Evidence | Where-Object { [long]$_.availabilityMaximum -gt $observedAge })
            if ($survivalEvidence.Count -gt 0) {
                $sample=Get-SFWeightedEvidenceRow -Evidence $survivalEvidence -Random $Random
                $durationMinimum=[Math]::Max([long]$sample.availabilityMinimum,$observedAge+1L)
                $durationMaximum=[long]$sample.availabilityMaximum
                $duration=Get-SFUniformLong -Random $Random -Minimum $durationMinimum -Maximum $durationMaximum
                $selloutAt=$restockAt+$duration
            } else {
                # The observed cycle has already outlived every usable historical
                # duration. Preserve the factual positive observation but do not
                # invent a long residual tail from incompatible history.
                $selloutAt=$observationAt+1L
            }
        } else {
            # Left-censored restock: only the positive observation time is known.
            # Use empirical lifetime as a residual-life approximation until richer
            # within-cycle depletion evidence is wired into stochastic-v2.
            $duration=Get-SFUniformLong -Random $Random -Minimum ([long]$sample.availabilityMinimum) -Maximum ([long]$sample.availabilityMaximum)
            $selloutAt=$observationAt+[Math]::Max(1L,$duration)
        }

        $intervals.Add((New-SFStockInterval -StartAt $observationAt -EndAt $selloutAt -Quantity $currentStock -ForeignPrice $currentPrice -Ordinal 0))
        # If the last positive snapshot is old enough that this sampled cycle sold
        # out before Now, continue simulating later restocks from that sellout. This
        # lets current market state become genuinely latent between provider polls.
        $anchor=$selloutAt
        $ordinal=1
    } else {
        $anchor=Get-SFEventAt -Object $Destination -Representative 'lastSellOutAt' -Lower 'lastSellOutLowerBoundAt' -Upper 'lastSellOutUpperBoundAt' -Random $Random
        if ($anchor -le 0) { return @() }
    }

    $guard=0
    while ($anchor -lt $HorizonAt -and $guard -lt 256) {
        $sample=Get-SFWeightedEvidenceRow -Evidence $Evidence -Random $Random
        if ($null -eq $sample) { break }
        $delay=Get-SFUniformLong -Random $Random -Minimum ([long]$sample.delayMinimum) -Maximum ([long]$sample.delayMaximum)
        $available=Get-SFUniformLong -Random $Random -Minimum ([long]$sample.availabilityMinimum) -Maximum ([long]$sample.availabilityMaximum)
        $restockAt=$anchor+$delay
        $selloutAt=$restockAt+$available
        if ($selloutAt -gt $NowEpoch -and $restockAt -le $HorizonAt) {
            $intervals.Add((New-SFStockInterval -StartAt $restockAt -EndAt $selloutAt -Quantity ([long]$sample.quantity) -ForeignPrice ([long]$sample.foreignPrice) -Ordinal $ordinal -DepletionShape (Get-SFProperty $sample 'depletionShape')))
        }
        $anchor=$selloutAt
        $ordinal++
        $guard++
    }
    return $intervals.ToArray()
}

function Get-SFQuantityAt {
    param([object[]]$Intervals,[long]$ArrivalAt)
    foreach ($interval in @($Intervals)) {
        $quantity=Get-SFIntervalQuantity -Interval $interval -ArrivalAt $ArrivalAt
        if ($quantity -le 0) { continue }
        return [pscustomobject]@{ quantity=[long]$quantity; foreignPrice=[long]$interval.foreignPrice; cycleOrdinal=[int]$interval.cycleOrdinal }
    }
    return [pscustomobject]@{ quantity=0L; foreignPrice=0L; cycleOrdinal=-1 }
}

function Get-SFTravelCandidates {
    param(
        [string]$TravelState,
        [string]$MarketCountry,
        [string]$TravelDestinationCountry,
        [long]$TravelTimeLeft,
        [long]$OneWaySeconds,
        [long]$NowEpoch,
        [int]$StepSeconds=900,
        [int]$SearchSeconds=43200
    )
    $state=([string]$TravelState).Trim().ToLowerInvariant()
    $target=([string]$TravelDestinationCountry).Trim().ToLowerInvariant()
    $country=([string]$MarketCountry).Trim().ToLowerInvariant()
    $candidates=New-Object System.Collections.Generic.List[object]

    if ($state -in @('traveling_unknown','abroad_unknown','unknown')) {
        return [pscustomobject]@{ feasible=$false; mode='unknown_destination'; reason='travel destination is unresolved'; candidates=@() }
    }
    if ($state -in @('traveling','outbound','outbound_to_target')) {
        if ([string]::IsNullOrWhiteSpace($target) -or $target -ne $country) {
            return [pscustomobject]@{ feasible=$false; mode='traveling_elsewhere'; reason='already outbound to another destination'; candidates=@() }
        }
        $candidates.Add([pscustomobject]@{ departureAt=0L; arrivalAt=$NowEpoch+[Math]::Max(0L,$TravelTimeLeft) })
        return [pscustomobject]@{ feasible=$true; mode='committed'; reason='outbound landing is committed'; candidates=$candidates.ToArray() }
    }
    if ($state -in @('abroad','foreign','abroad_at_target')) {
        if ([string]::IsNullOrWhiteSpace($target) -or $target -ne $country) {
            return [pscustomobject]@{ feasible=$false; mode='abroad_elsewhere'; reason='cannot depart Torn while abroad elsewhere'; candidates=@() }
        }
        $candidates.Add([pscustomobject]@{ departureAt=0L; arrivalAt=$NowEpoch })
        return [pscustomobject]@{ feasible=$true; mode='at_target'; reason='already at target market'; candidates=$candidates.ToArray() }
    }

    if ($OneWaySeconds -le 0) {
        return [pscustomobject]@{ feasible=$false; mode='missing_travel_time'; reason='configured one-way travel time is unavailable'; candidates=@() }
    }

    $earliestDeparture=$NowEpoch
    if ($state -eq 'returning') { $earliestDeparture=$NowEpoch+[Math]::Max(0L,$TravelTimeLeft) }
    elseif ($state -notin @('home','torn','in_torn','')) {
        return [pscustomobject]@{ feasible=$false; mode='unsupported_travel_state'; reason=('unsupported travel state: '+$state); candidates=@() }
    }
    $step=[Math]::Max(60,$StepSeconds)
    $search=[Math]::Max($step,$SearchSeconds)
    for ($offset=0; $offset -le $search; $offset+=$step) {
        $departure=$earliestDeparture+$offset
        $candidates.Add([pscustomobject]@{ departureAt=[long]$departure; arrivalAt=[long]($departure+[Math]::Max(0L,$OneWaySeconds)) })
    }
    return [pscustomobject]@{ feasible=$true; mode=$(if($state -eq 'returning'){'returning'}else{'home'}); reason='feasible Torn departure grid'; candidates=$candidates.ToArray() }
}

function Get-SFEconomics {
    param([long]$Quantity,[long]$MarketValue,[long]$ForeignPrice,[int]$MarketFeePercent,[long]$OneWaySeconds)
    $qty=[Math]::Max(0L,$Quantity)
    $sale=[Math]::Max(0L,$MarketValue)*$qty
    $cost=[Math]::Max(0L,$ForeignPrice)*$qty
    $tax=[long][Math]::Floor([double]$sale*([Math]::Max(0,[Math]::Min(5,$MarketFeePercent))/100.0))
    $profit=[long]($sale-$cost-$tax)
    $hours=if ($OneWaySeconds -gt 0) { (2.0*$OneWaySeconds)/3600.0 } else { 0.0 }
    return [pscustomobject]@{ profit=$profit; profitPerHour=$(if($hours -gt 0){$profit/$hours}else{0.0}); tax=$tax }
}

function Get-SFDirectObservedArrival {
    param([object]$Market,[long]$NowEpoch,[long]$ArrivalAt,[int]$TargetQuantity,[long]$MarketValue,[int]$MarketFeePercent,[long]$OneWaySeconds)
    $sourceAt=[long](Get-SFProperty $Market 'sourceTimestamp')
    $stock=[long](Get-SFProperty $Market 'lastStock')
    # A positive provider snapshot is certain only at the timestamp it describes.
    # Do not turn the normal five-minute freshness allowance into a fabricated
    # 100% "stock now" probability for fast-selling items. Older direct evidence
    # requires a learned survival model; with insufficient cycles we stay unknown.
    if ($ArrivalAt -ne $NowEpoch -or $sourceAt -ne $NowEpoch -or $stock -le 0) { return $null }
    $qty=[Math]::Min([Math]::Max(1,$TargetQuantity),[int]$stock)
    $economics=Get-SFEconomics -Quantity $qty -MarketValue $MarketValue -ForeignPrice ([long](Get-SFProperty $Market 'lastForeignPrice')) -MarketFeePercent $MarketFeePercent -OneWaySeconds $OneWaySeconds
    return [pscustomobject]@{
        arrivalAt=$ArrivalAt; departureAt=0L; pAnyStock=1.0; pTargetQty=$(if($stock -ge $TargetQuantity){1.0}else{0.0})
        expectedQty=[double]$qty; expectedAvailableQty=[double]$stock
        expectedProfit=[double]$economics.profit; expectedProfitPerHour=[double]$economics.profitPerHour
        maximumCycleOrdinal=0
    }
}

function Get-SFDecision {
    param([object]$Travel,[object[]]$Arrivals,[int]$SampleCount,[long]$NowEpoch)
    $mode=[string](Get-SFProperty $Travel 'mode')
    if (-not [bool](Get-SFProperty $Travel 'feasible')) { return [pscustomobject]@{ state='NO_ACTIONABLE_TRIP'; reason=[string](Get-SFProperty $Travel 'reason') } }
    if ($mode -eq 'committed') { return [pscustomobject]@{ state='COMMITTED'; reason='evaluate the already committed landing' } }
    if (@($Arrivals).Count -eq 0 -or $SampleCount -lt 3) { return [pscustomobject]@{ state='INSUFFICIENT_DATA'; reason='fewer than three usable completed joint cycles' } }
    $best=@($Arrivals | Sort-Object @{Expression='expectedProfit';Descending=$true},@{Expression='pTargetQty';Descending=$true},arrivalAt | Select-Object -First 1)[0]
    if ($mode -eq 'at_target') {
        if ([double]$best.pAnyStock -gt 0) { return [pscustomobject]@{ state='BUY_NOW'; reason='current target-market stock is observed or simulated available' } }
        return [pscustomobject]@{ state='MISSED_TARGET'; reason='no stock is available at the current target-market arrival' }
    }
    if ([double]$best.pAnyStock -le 0 -or [double]$best.expectedProfit -le 0) { return [pscustomobject]@{ state='NO_ACTIONABLE_TRIP'; reason='no positive expected-profit arrival is present on the evaluated grid' } }
    $departure=[long]$best.departureAt
    if ($departure -le ($NowEpoch+60L)) { return [pscustomobject]@{ state='LEAVE_NOW'; reason='best expected-profit feasible departure is now' } }
    return [pscustomobject]@{ state='LEAVE_IN'; reason='a later feasible departure has the highest expected profit' }
}

function Get-SFTargetQuantityEndAt {
    param([object]$Interval,[int]$TargetQuantity)
    if ($null -eq $Interval) { return 0L }
    $start=[long](Get-SFProperty $Interval 'startAt')
    $end=[long](Get-SFProperty $Interval 'endAt')
    if ($end -le $start) { return 0L }
    $target=[Math]::Max(1,$TargetQuantity)
    if ((Get-SFIntervalQuantity -Interval $Interval -ArrivalAt $start) -lt $target) { return 0L }
    if ($target -le 1) { return $end }

    $low=$start
    $high=$end
    while (($high-$low) -gt 1) {
        $mid=[long][Math]::Floor(([double]$low+[double]$high)/2.0)
        if ((Get-SFIntervalQuantity -Interval $Interval -ArrivalAt $mid) -ge $target) { $low=$mid }
        else { $high=$mid }
    }
    return [long]$high
}

function Get-SFAdaptiveGridPlan {
    param(
        [object[]]$Evidence,
        [object]$Travel,
        [int]$TargetQuantity=1,
        [int]$CoarseStepSeconds=900,
        [bool]$Enabled=$true
    )
    $coarse=[Math]::Max(60,$CoarseStepSeconds)
    $mode=([string](Get-SFProperty $Travel 'mode')).Trim().ToLowerInvariant()
    $candidates=@(Get-SFProperty $Travel 'candidates')
    $disabled=[pscustomobject]@{
        enabled=$false
        reason='adaptive grid disabled'
        referenceAvailabilitySeconds=0L
        referenceUsefulQuantityWindowSeconds=0L
        desiredFineStepSeconds=0
        discoveryScenarioCount=0
        refinedCellCount=0
        additionalCandidateCount=0
        totalCandidateCount=$candidates.Count
    }
    if (-not $Enabled) { return $disabled }
    if ($mode -notin @('home','returning')) {
        $disabled.reason='travel state has a fixed arrival rather than a departure search'
        return $disabled
    }
    if ($candidates.Count -lt 2) {
        $disabled.reason='fewer than two coarse departure candidates'
        return $disabled
    }

    $durations=New-Object System.Collections.Generic.List[long]
    $usefulWindows=New-Object System.Collections.Generic.List[long]
    foreach ($row in @($Evidence)) {
        $minimum=[long](Get-SFProperty $row 'availabilityMinimum')
        $maximum=[long](Get-SFProperty $row 'availabilityMaximum')
        if ($minimum -le 0 -and $maximum -le 0) { continue }
        if ($minimum -le 0) { $minimum=$maximum }
        if ($maximum -lt $minimum) { $maximum=$minimum }
        $duration=[long][Math]::Max(1L,[Math]::Round(([double]$minimum+[double]$maximum)/2.0))
        $durations.Add($duration)

        $quantity=[Math]::Max(1L,[long](Get-SFProperty $row 'quantity'))
        $probe=New-SFStockInterval -StartAt 0L -EndAt $duration -Quantity $quantity -ForeignPrice 0L -Ordinal 0 -DepletionShape (Get-SFProperty $row 'depletionShape')
        $targetEnd=Get-SFTargetQuantityEndAt -Interval $probe -TargetQuantity $TargetQuantity
        $useful=if($targetEnd -gt 0){[long]$targetEnd}else{[long][Math]::Max(1L,[Math]::Ceiling($duration/2.0))}
        $usefulWindows.Add([Math]::Min($duration,$useful))
    }
    if ($durations.Count -lt 3) {
        $disabled.reason='fewer than three usable availability durations'
        return $disabled
    }

    $sorted=[long[]]@($durations.ToArray() | Sort-Object)
    $sortedUseful=[long[]]@($usefulWindows.ToArray() | Sort-Object)
    $index=[int][Math]::Floor(($sorted.Count-1)*0.25)
    $usefulIndex=[int][Math]::Floor(($sortedUseful.Count-1)*0.25)
    $reference=[long]$sorted[$index]
    $referenceUseful=[long]$sortedUseful[$usefulIndex]
    $disabled.referenceAvailabilitySeconds=$reference
    $disabled.referenceUsefulQuantityWindowSeconds=$referenceUseful
    if ($reference -ge $coarse -and $referenceUseful -ge $coarse) {
        $disabled.reason='stock and required-quantity windows are at least the coarse grid step'
        return $disabled
    }

    $resolutionReference=[Math]::Min($reference,$referenceUseful)
    $fine=[int][Math]::Round($resolutionReference/2.0)
    $fine=[Math]::Max(5,[Math]::Min(300,$fine))
    $fine=[Math]::Min($fine,[Math]::Max(5,[int][Math]::Floor($coarse/2.0)))
    return [pscustomobject]@{
        enabled=$true
        reason='stock or required-quantity window requires bounded sub-grid search'
        referenceAvailabilitySeconds=$reference
        referenceUsefulQuantityWindowSeconds=$referenceUseful
        desiredFineStepSeconds=$fine
        discoveryScenarioCount=0
        refinedCellCount=0
        additionalCandidateCount=0
        totalCandidateCount=$candidates.Count
    }
}

function Get-SFAdaptiveTravelCandidates {
    param(
        [object[]]$CoarseCandidates,
        [object[]]$DiscoveryWorlds,
        [int]$FineStepSeconds,
        [int]$TargetQuantity=1,
        [int]$MaximumCells=4,
        [int]$MaximumAdditionalPoints=192
    )
    $coarse=@($CoarseCandidates | Sort-Object arrivalAt)
    if ($coarse.Count -lt 2 -or @($DiscoveryWorlds).Count -eq 0) {
        return [pscustomobject]@{ candidates=$coarse; refinedCellCount=0; additionalCandidateCount=0; maximumHiddenSupport=0 }
    }

    $cellCount=$coarse.Count-1
    $support=New-Object 'int[]' $cellCount
    $hidden=New-Object 'int[]' $cellCount
    $starts=@{}
    for ($i=0; $i -lt $cellCount; $i++) { $starts[$i]=New-Object System.Collections.Generic.List[long] }

    foreach ($worldRecord in @($DiscoveryWorlds)) {
        $world=@(Get-SFProperty $worldRecord 'intervals')
        $seenSupport=@{}
        $seenHidden=@{}
        foreach ($interval in $world) {
            $start=[long]$interval.startAt
            $end=[long]$interval.endAt
            if ($end -le $start) { continue }

            $targetEnd=Get-SFTargetQuantityEndAt -Interval $interval -TargetQuantity $TargetQuantity
            $focusEnd=if($targetEnd -gt $start){[long]$targetEnd}else{[long]($start+[Math]::Max(1L,[Math]::Ceiling(($end-$start)/2.0)))}
            $focusEnd=[Math]::Min($end,$focusEnd)
            if ($focusEnd -le $start) { continue }

            for ($i=0; $i -lt $cellCount; $i++) {
                $left=[long]$coarse[$i].arrivalAt
                $right=[long]$coarse[$i+1].arrivalAt
                if ($focusEnd -le $left -or $start -ge $right) { continue }
                $seenSupport[$i]=$true
                if ($start -gt $left -and $start -lt $right) { $starts[$i].Add($start) }
                $leftHit=($left -ge $start -and $left -lt $focusEnd)
                $rightHit=($right -ge $start -and $right -lt $focusEnd)
                if (-not $leftHit -and -not $rightHit) { $seenHidden[$i]=$true }
            }
        }
        foreach ($key in @($seenSupport.Keys)) { $support[[int]$key]++ }
        foreach ($key in @($seenHidden.Keys)) { $hidden[[int]$key]++ }
    }

    $ranked=New-Object System.Collections.Generic.List[object]
    for ($i=0; $i -lt $cellCount; $i++) {
        if ($support[$i] -le 0) { continue }
        $ranked.Add([pscustomobject]@{
            index=$i
            hidden=[int]$hidden[$i]
            support=[int]$support[$i]
            score=([int]$hidden[$i]*2)+[int]$support[$i]
        })
    }
    $selected=@($ranked.ToArray() | Sort-Object @{Expression='hidden';Descending=$true},@{Expression='support';Descending=$true},index | Select-Object -First ([Math]::Max(1,$MaximumCells)))
    if ($selected.Count -eq 0) {
        return [pscustomobject]@{ candidates=$coarse; refinedCellCount=0; additionalCandidateCount=0; maximumHiddenSupport=0 }
    }

    $candidateMap=@{}
    foreach ($candidate in $coarse) { $candidateMap[[string][long]$candidate.arrivalAt]=$candidate }
    $perCellBudget=[Math]::Max(1,[int][Math]::Floor([Math]::Max(1,$MaximumAdditionalPoints)/[double]$selected.Count))
    $added=0

    foreach ($cell in $selected) {
        $i=[int]$cell.index
        $leftArrival=[long]$coarse[$i].arrivalAt
        $rightArrival=[long]$coarse[$i+1].arrivalAt
        $leftDeparture=[long]$coarse[$i].departureAt
        $travelOffset=$leftArrival-$leftDeparture
        $width=[Math]::Max(1L,$rightArrival-$leftArrival)
        $step=[Math]::Max(1,$FineStepSeconds)
        $budgetStep=[int][Math]::Ceiling($width/[double]($perCellBudget+1))
        if ($budgetStep -gt $step) { $step=$budgetStep }

        for ($arrival=$leftArrival+$step; $arrival -lt $rightArrival -and $added -lt $MaximumAdditionalPoints; $arrival+=$step) {
            $key=[string][long]$arrival
            if ($candidateMap.ContainsKey($key)) { continue }
            $candidate=[pscustomobject]@{
                departureAt=[long]($arrival-$travelOffset)
                arrivalAt=[long]$arrival
                adaptive=$true
                adaptiveSource='uniform_refinement'
            }
            $candidateMap[$key]=$candidate
            $added++
        }

        # Also add a few distributional restock anchors from the independent
        # discovery worlds. These anchors make sub-minute bursts discoverable even
        # when the bounded uniform budget cannot make the entire 15-minute cell
        # second-scale. They are scored only on the independent full scenario set.
        $cellStarts=[long[]]@($starts[$i].ToArray() | Sort-Object)
        if ($cellStarts.Count -gt 0 -and $added -lt $MaximumAdditionalPoints) {
            $quantiles=@(0.0,0.25,0.5,0.75,1.0)
            foreach ($q in $quantiles) {
                $qIndex=[int][Math]::Round(($cellStarts.Count-1)*$q)
                $arrival=[long]$cellStarts[$qIndex]
                if ($arrival -le $leftArrival -or $arrival -ge $rightArrival) { continue }
                $key=[string]$arrival
                if ($candidateMap.ContainsKey($key)) { continue }
                $candidateMap[$key]=[pscustomobject]@{
                    departureAt=[long]($arrival-$travelOffset)
                    arrivalAt=[long]$arrival
                    adaptive=$true
                    adaptiveSource='discovery_restock_quantile'
                }
                $added++
                if ($added -ge $MaximumAdditionalPoints) { break }
            }
        }
        if ($added -ge $MaximumAdditionalPoints) { break }
    }

    $all=@($candidateMap.Values | Sort-Object arrivalAt)
    $maxHidden=0
    if ($selected.Count -gt 0) { $maxHidden=[int](@($selected.hidden | Measure-Object -Maximum).Maximum) }
    return [pscustomobject]@{
        candidates=$all
        refinedCellCount=$selected.Count
        additionalCandidateCount=[Math]::Max(0,$all.Count-$coarse.Count)
        maximumHiddenSupport=$maxHidden
    }
}

function Invoke-SFMarketForecast {
    param(
        [string]$MarketKey,
        [object[]]$Cycles,
        [object]$Market,
        [object]$Destination,
        [object]$Travel,
        [long]$NowEpoch,
        [object[]]$Observations=@(),
        [int]$ScenarioCount=128,
        [int]$TargetQuantity=1,
        [long]$MarketValue=0L,
        [int]$MarketFeePercent=0,
        [long]$OneWaySeconds=0L,
        [int]$RandomSeed=1,
        [long]$HalfLifeSeconds=1209600L,
        [bool]$EnableAdaptiveGrid=$true,
        [int]$CoarseGridSeconds=900
    )
    $evidence=@(Select-SFJointCycleEvidence -Cycles $Cycles -AsOf $NowEpoch -Observations $Observations -HalfLifeSeconds $HalfLifeSeconds)
    $candidates=@(Get-SFProperty $Travel 'candidates')
    $sampleCount=$evidence.Count
    $effective=Get-SFEffectiveSampleSize -Evidence $evidence
    $shapeEvidenceCount=@($evidence | Where-Object { $null -ne (Get-SFProperty $_ 'depletionShape') }).Count
    $depletionModel=if($shapeEvidenceCount -gt 0){'empirical_piecewise_with_linear_fallback'}else{'linear_fallback'}
    $adaptiveGrid=[pscustomobject]@{
        enabled=$false; reason='not evaluated'; referenceAvailabilitySeconds=0L; desiredFineStepSeconds=0
        discoveryScenarioCount=0; refinedCellCount=0; additionalCandidateCount=0; totalCandidateCount=$candidates.Count; maximumHiddenSupport=0
    }

    if ($sampleCount -lt 3) {
        $direct=@()
        if (@($candidates).Count -eq 1) {
            $observed=Get-SFDirectObservedArrival -Market $Market -NowEpoch $NowEpoch -ArrivalAt ([long]$candidates[0].arrivalAt) -TargetQuantity $TargetQuantity -MarketValue $MarketValue -MarketFeePercent $MarketFeePercent -OneWaySeconds $OneWaySeconds
            if ($null -ne $observed) { $direct=@($observed) }
        }
        $decision=Get-SFDecision -Travel $Travel -Arrivals $direct -SampleCount $(if($direct.Count -gt 0){3}else{$sampleCount}) -NowEpoch $NowEpoch
        return [pscustomobject]@{ sampleCount=$sampleCount; effectiveSampleSize=[Math]::Round($effective,3); evidenceQuality=$(if($direct.Count -gt 0){'bounded_fresh'}else{'insufficient'}); arrivals=$direct; decision=$decision; maximumCycleOrdinal=0; adaptiveGrid=$adaptiveGrid; depletionModel=$depletionModel; depletionShapeEvidenceCount=$shapeEvidenceCount }
    }
    if (-not [bool](Get-SFProperty $Travel 'feasible') -or $candidates.Count -eq 0) {
        $decision=Get-SFDecision -Travel $Travel -Arrivals @() -SampleCount $sampleCount -NowEpoch $NowEpoch
        return [pscustomobject]@{ sampleCount=$sampleCount; effectiveSampleSize=[Math]::Round($effective,3); evidenceQuality='usable'; arrivals=@(); decision=$decision; maximumCycleOrdinal=0; adaptiveGrid=$adaptiveGrid; depletionModel=$depletionModel; depletionShapeEvidenceCount=$shapeEvidenceCount }
    }

    $adaptiveGrid=Get-SFAdaptiveGridPlan -Evidence $evidence -Travel $Travel -TargetQuantity $TargetQuantity -CoarseStepSeconds $CoarseGridSeconds -Enabled $EnableAdaptiveGrid
    if ([bool]$adaptiveGrid.enabled) {
        $coarseHorizon=[long](@($candidates | Measure-Object arrivalAt -Maximum).Maximum)+1L
        $discoveryCount=[Math]::Min(32,[Math]::Max(16,[int][Math]::Ceiling($ScenarioCount/4.0)))
        $discoverySeed=($RandomSeed -bxor 1597463007) -band 0x7fffffff
        if ($discoverySeed -eq 0) { $discoverySeed=1 }
        $discoveryRandom=New-Object System.Random($discoverySeed)
        $discoveryWorlds=New-Object System.Collections.Generic.List[object]
        for ($scenario=0; $scenario -lt $discoveryCount; $scenario++) {
            $world=@(New-SFMarketWorld -Evidence $evidence -Market $Market -Destination $Destination -NowEpoch $NowEpoch -HorizonAt $coarseHorizon -Random $discoveryRandom)
            $discoveryWorlds.Add([pscustomobject]@{ intervals=$world })
        }
        $refined=Get-SFAdaptiveTravelCandidates -CoarseCandidates $candidates -DiscoveryWorlds $discoveryWorlds.ToArray() -FineStepSeconds ([int]$adaptiveGrid.desiredFineStepSeconds) -TargetQuantity $TargetQuantity
        $candidates=@($refined.candidates)
        $adaptiveGrid.discoveryScenarioCount=$discoveryCount
        $adaptiveGrid.refinedCellCount=[int]$refined.refinedCellCount
        $adaptiveGrid.additionalCandidateCount=[int]$refined.additionalCandidateCount
        $adaptiveGrid.totalCandidateCount=$candidates.Count
        $adaptiveGrid | Add-Member -NotePropertyName maximumHiddenSupport -NotePropertyValue ([int]$refined.maximumHiddenSupport) -Force
        if ([int]$refined.additionalCandidateCount -le 0) {
            $adaptiveGrid.reason='short-duration evidence found, but discovery worlds exposed no refinable support'
        }
    }

    $n=$candidates.Count
    $any=New-Object 'double[]' $n
    $target=New-Object 'double[]' $n
    $quantity=New-Object 'double[]' $n
    $availableQuantity=New-Object 'double[]' $n
    $profit=New-Object 'double[]' $n
    $maxOrdinal=New-Object 'int[]' $n
    for ($j=0; $j -lt $n; $j++) { $maxOrdinal[$j]=-1 }
    $random=New-Object System.Random($RandomSeed)
    $horizon=[long](@($candidates | Measure-Object arrivalAt -Maximum).Maximum)+1L

    for ($scenario=0; $scenario -lt $ScenarioCount; $scenario++) {
        $world=@(New-SFMarketWorld -Evidence $evidence -Market $Market -Destination $Destination -NowEpoch $NowEpoch -HorizonAt $horizon -Random $random)
        $worldIndex=0
        for ($j=0; $j -lt $n; $j++) {
            $arrivalAt=[long]$candidates[$j].arrivalAt
            while ($worldIndex -lt $world.Count -and [long]$world[$worldIndex].endAt -le $arrivalAt) { $worldIndex++ }
            $stock=[pscustomobject]@{quantity=0L;foreignPrice=0L;cycleOrdinal=-1}
            if ($worldIndex -lt $world.Count) {
                $interval=$world[$worldIndex]
                if ($arrivalAt -ge [long]$interval.startAt -and $arrivalAt -lt [long]$interval.endAt) {
                    $stock.quantity=Get-SFIntervalQuantity -Interval $interval -ArrivalAt $arrivalAt
                    $stock.foreignPrice=[long]$interval.foreignPrice
                    $stock.cycleOrdinal=[int]$interval.cycleOrdinal
                }
            }
            $available=[long]$stock.quantity
            if ($available -gt 0) { $any[$j]++ }
            if ($available -ge $TargetQuantity) { $target[$j]++ }
            $purchasable=[Math]::Min([Math]::Max(1,$TargetQuantity),[int]$available)
            $quantity[$j]+=$purchasable
            $availableQuantity[$j]+=$available
            $price=if ([long]$stock.foreignPrice -gt 0) { [long]$stock.foreignPrice } else { [long](Get-SFProperty $Market 'lastForeignPrice') }
            $economics=Get-SFEconomics -Quantity $purchasable -MarketValue $MarketValue -ForeignPrice $price -MarketFeePercent $MarketFeePercent -OneWaySeconds $OneWaySeconds
            $profit[$j]+=[double]$economics.profit
            if ([int]$stock.cycleOrdinal -gt $maxOrdinal[$j]) { $maxOrdinal[$j]=[int]$stock.cycleOrdinal }
        }
    }

    $arrivals=New-Object System.Collections.Generic.List[object]
    $hours=if ($OneWaySeconds -gt 0) { (2.0*$OneWaySeconds)/3600.0 } else { 0.0 }
    for ($j=0; $j -lt $n; $j++) {
        $expectedProfit=$profit[$j]/$ScenarioCount
        $arrivals.Add([pscustomobject]@{
            arrivalAt=[long]$candidates[$j].arrivalAt
            departureAt=[long]$candidates[$j].departureAt
            pAnyStock=[Math]::Round($any[$j]/$ScenarioCount,6)
            pTargetQty=[Math]::Round($target[$j]/$ScenarioCount,6)
            expectedQty=[Math]::Round($quantity[$j]/$ScenarioCount,3)
            expectedAvailableQty=[Math]::Round($availableQuantity[$j]/$ScenarioCount,3)
            expectedProfit=[Math]::Round($expectedProfit,2)
            expectedProfitPerHour=[Math]::Round($(if($hours -gt 0){$expectedProfit/$hours}else{0.0}),2)
            maximumCycleOrdinal=[int]$maxOrdinal[$j]
            adaptivePoint=$(if($candidates[$j].PSObject.Properties['adaptive']){[bool]$candidates[$j].adaptive}else{$false})
            adaptiveSource=$(if($candidates[$j].PSObject.Properties['adaptiveSource']){[string]$candidates[$j].adaptiveSource}else{'coarse'})
        })
    }
    $arrivalArray=$arrivals.ToArray()
    $decision=Get-SFDecision -Travel $Travel -Arrivals $arrivalArray -SampleCount $sampleCount -NowEpoch $NowEpoch
    $quality=if (@($evidence | Where-Object { [double]$_.qualityWeight -lt 0.999 }).Count -gt 0) { 'bounded_gap' } else { 'bounded_fresh' }
    return [pscustomobject]@{
        sampleCount=$sampleCount
        effectiveSampleSize=[Math]::Round($effective,3)
        evidenceQuality=$quality
        arrivals=$arrivalArray
        decision=$decision
        maximumCycleOrdinal=$(if($maxOrdinal.Count -gt 0){[int](@($maxOrdinal | Measure-Object -Maximum).Maximum)}else{0})
        adaptiveGrid=$adaptiveGrid
        depletionModel=$depletionModel
        depletionShapeEvidenceCount=$shapeEvidenceCount
    }
}

function Get-SFCycleLineKey {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return '' }
    $country=[regex]::Match($Line,'"country"\s*:\s*"([^"]+)"')
    $item=[regex]::Match($Line,'"itemId"\s*:\s*([1-9][0-9]*)')
    if (-not $country.Success -or -not $item.Success) { return '' }
    return ($country.Groups[1].Value.Trim().ToLowerInvariant()+':'+$item.Groups[1].Value)
}

function Read-SFCyclesForKeys {
    param([string[]]$Paths,[hashtable]$Wanted)
    $map=@{}
    $seen=@{}
    foreach ($path in @($Paths)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        foreach ($line in [System.IO.File]::ReadLines($path)) {
            $key=Get-SFCycleLineKey -Line $line
            if ([string]::IsNullOrWhiteSpace($key) -or -not $Wanted.ContainsKey($key)) { continue }
            try { $row=$line | ConvertFrom-Json } catch { continue }
            $identity=$key+':'+[string](Get-SFProperty $row 'restockUpperBoundAt')+':'+[string](Get-SFProperty $row 'soldOutUpperBoundAt')
            if ($seen.ContainsKey($identity)) { continue }
            $seen[$identity]=$true
            if (-not $map.ContainsKey($key)) { $map[$key]=New-Object System.Collections.Generic.List[object] }
            $map[$key].Add($row)
        }
    }
    return $map
}

function Read-SFObservationsForKeys {
    param([string[]]$Paths,[hashtable]$Wanted)
    $map=@{}
    $seen=@{}
    foreach ($path in @($Paths)) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        foreach ($line in [System.IO.File]::ReadLines($path)) {
            $key=Get-SFCycleLineKey -Line $line
            if ([string]::IsNullOrWhiteSpace($key) -or -not $Wanted.ContainsKey($key)) { continue }
            try { $row=$line | ConvertFrom-Json } catch { continue }
            $at=Get-SFObservationAt $row
            if ($at -le 0) { continue }
            $identity=$key+':'+[string]$at+':'+[string](Get-SFProperty $row 'stock')+':'+[string](Get-SFProperty $row 'foreignPrice')
            if ($seen.ContainsKey($identity)) { continue }
            $seen[$identity]=$true
            if (-not $map.ContainsKey($key)) { $map[$key]=New-Object System.Collections.Generic.List[object] }
            $map[$key].Add($row)
        }
    }
    return $map
}

function Get-SFTravelSeconds {
    param([hashtable]$State,[string]$Country)
    $key=if($Country -eq 'united_kingdom'){'UKTravelSeconds'}elseif($Country -eq 'japan'){'JPTravelSeconds'}else{$Country.ToUpperInvariant()+'TravelSeconds'}
    $value=0L
    if ($State.ContainsKey($key)) { [void][long]::TryParse([string]$State[$key],[ref]$value) }
    return [Math]::Max(0L,$value)
}

if ($StochasticForecastSkipMain) { return }
if ($Now -le 0) { $Now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
$stopwatch=[System.Diagnostics.Stopwatch]::StartNew()
$engine=Read-SFJson $EngineStateFile
$state=Read-SFStateKv $StateKvFile
if ($null -eq $engine -or $state.Count -eq 0 -or -not $engine.PSObject.Properties['observedMarkets']) { throw 'Stochastic forecast prerequisites are missing.' }

$count=0
[void][int]::TryParse([string]$state['OpportunityCount'],[ref]$count)
$count=[Math]::Min(256,[Math]::Max(0,$count))
$wanted=@{}
for ($i=1; $i -le $count; $i++) {
    $key=([string]$state['Opportunity'+$i+'Key']).Trim().ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($key)) { $wanted[$key]=$true }
}
$cycleMap=Read-SFCyclesForKeys -Paths @($SeedCycleFile,$RuntimeCycleFile) -Wanted $wanted
$observationMap=Read-SFObservationsForKeys -Paths @($SeedObservationFile,$RuntimeObservationFile) -Wanted $wanted
$travelState=([string]$state['TravelState']).Trim().ToLowerInvariant()
$travelDestination=([string]$state['TravelDestinationCountryId']).Trim().ToLowerInvariant()
$travelLeft=0L
[void][long]::TryParse([string]$state['TravelTimeLeft'],[ref]$travelLeft)
$markets=New-Object System.Collections.Generic.List[object]

for ($i=1; $i -le $count; $i++) {
    $prefix='Opportunity'+$i
    $key=([string]$state[$prefix+'Key']).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($key)) { continue }
    $parts=$key -split ':',2
    if ($parts.Count -ne 2) { continue }
    $country=[string]$parts[0]
    $itemId=0
    if (-not [int]::TryParse($parts[1],[ref]$itemId)) { continue }
    $market=Get-SFProperty $engine.observedMarkets $key
    if ($null -eq $market) { continue }
    $destination=Get-SFProperty (Get-SFProperty $engine 'destinations') $key
    if ($null -eq $destination) { $destination=[pscustomobject]@{} }
    $cycles=@()
    if ($cycleMap.ContainsKey($key)) { $cycles=@($cycleMap[$key].ToArray()) }
    $observations=@()
    if ($observationMap.ContainsKey($key)) { $observations=@($observationMap[$key].ToArray()) }
    $oneWay=Get-SFTravelSeconds -State $state -Country $country
    $travel=Get-SFTravelCandidates -TravelState $travelState -MarketCountry $country -TravelDestinationCountry $travelDestination -TravelTimeLeft $travelLeft -OneWaySeconds $oneWay -NowEpoch $Now -StepSeconds $GridSeconds -SearchSeconds $DepartureSearchSeconds
    $targetQuantity=1
    $quantityText=[string]$state[$prefix+'QuantityText']
    if ($quantityText -match '([1-9][0-9]*)') { $targetQuantity=[int]$Matches[1] }
    $marketValue=0L; $fee=0
    [void][long]::TryParse([string]$state[$prefix+'MarketValueValue'],[ref]$marketValue)
    [void][int]::TryParse([string]$state[$prefix+'MarketFeePercent'],[ref]$fee)
    $marketSeed=Get-SFStableSeed -MarketKey $key -BaseSeed $Seed
    $forecast=Invoke-SFMarketForecast -MarketKey $key -Cycles $cycles -Market $market -Destination $destination -Travel $travel -NowEpoch $Now -Observations $observations -ScenarioCount $SimulationCount -TargetQuantity $targetQuantity -MarketValue $marketValue -MarketFeePercent $fee -OneWaySeconds $oneWay -RandomSeed $marketSeed -CoarseGridSeconds $GridSeconds
    $best=$null
    if (@($forecast.arrivals).Count -gt 0) { $best=@($forecast.arrivals | Sort-Object @{Expression='expectedProfit';Descending=$true},@{Expression='pTargetQty';Descending=$true},arrivalAt | Select-Object -First 1)[0] }
    $lastGoodDepartureAt=0L
    if (@($forecast.arrivals).Count -gt 0) {
        $lastGood=@($forecast.arrivals | Where-Object { [double]$_.expectedProfit -gt 0 -and [double]$_.pAnyStock -gt 0 } | Sort-Object departureAt -Descending | Select-Object -First 1)
        if ($lastGood.Count -gt 0) { $lastGoodDepartureAt=[long]$lastGood[0].departureAt }
    }
    $markets.Add([pscustomobject]@{
        marketKey=$key; countryId=$country; itemId=$itemId; generatedAt=$Now; modelVersion='stochastic-v1.1'
        sampleCount=[int]$forecast.sampleCount; effectiveSampleSize=[double]$forecast.effectiveSampleSize; evidenceQuality=[string]$forecast.evidenceQuality
        targetQuantity=$targetQuantity; targetQuantityDefinition='projected trip quantity'; simulationCount=$SimulationCount; gridSeconds=$GridSeconds
        adaptiveGrid=$(Get-SFProperty $forecast 'adaptiveGrid')
        depletionModel=[string](Get-SFProperty $forecast 'depletionModel')
        depletionShapeEvidenceCount=[int](Get-SFProperty $forecast 'depletionShapeEvidenceCount')
        arrivals=@($forecast.arrivals)
        bestArrivalAt=$(if($null -ne $best){[long]$best.arrivalAt}else{0L})
        bestDepartureAt=$(if($null -ne $best){[long]$best.departureAt}else{0L})
        lastActionableDepartureAt=$lastGoodDepartureAt
        bestUtility=$(if($null -ne $best){[double]$best.expectedProfit}else{0.0})
        currentTravelFeasible=[bool]$travel.feasible
        decision=[pscustomobject]@{
            state=[string]$forecast.decision.state; reason=[string]$forecast.decision.reason
            successProbability=$(if($null -ne $best){[double]$best.pAnyStock}else{0.0})
            targetQuantityProbability=$(if($null -ne $best){[double]$best.pTargetQty}else{0.0})
            expectedQuantity=$(if($null -ne $best){[double]$best.expectedQty}else{0.0})
            expectedAvailableQuantity=$(if($null -ne $best -and $best.PSObject.Properties['expectedAvailableQty']){[double]$best.expectedAvailableQty}else{0.0})
            expectedProfit=$(if($null -ne $best){[double]$best.expectedProfit}else{0.0})
            expectedProfitPerHour=$(if($null -ne $best){[double]$best.expectedProfitPerHour}else{0.0})
            bestDepartureAt=$(if($null -ne $best){[long]$best.departureAt}else{0L})
            bestArrivalAt=$(if($null -ne $best){[long]$best.arrivalAt}else{0L})
            lastGoodDepartureAt=$lastGoodDepartureAt
            evidenceQuality=[string]$forecast.evidenceQuality
        }
        diagnostics=[pscustomobject]@{
            travelMode=[string]$travel.mode; travelReason=[string]$travel.reason; maximumCycleOrdinal=[int]$forecast.maximumCycleOrdinal
            recencyHalfLifeSeconds=1209600L; utilityObjective='expectedProfit'; regimeAdaptation='extension_point'; valueOfInformation='not_implemented'; waitDecision='reserved_for_information_or_explicit_delay_model'
        }
    })
}

$stopwatch.Stop()
$artifact=[pscustomobject]@{
    schemaVersion=1
    modelVersion='stochastic-v1.1'
    mode='shadow'
    generatedAt=$Now
    simulationCount=$SimulationCount
    gridSeconds=$GridSeconds
    departureSearchSeconds=$DepartureSearchSeconds
    runtimeMilliseconds=[Math]::Round($stopwatch.Elapsed.TotalMilliseconds,2)
    marketCount=$markets.Count
    decisionStates=@('INSUFFICIENT_DATA','NO_ACTIONABLE_TRIP','WAIT','LEAVE_IN','LEAVE_NOW','LEAVE_BEFORE','COMMITTED','BUY_NOW','MISSED_TARGET')
    adaptiveGridMode='bounded coarse-to-fine hidden-support refinement'
    limitations=@('uncalibrated probabilities','empirical depletion shapes require retained intermediate observations and otherwise fall back to linear','empirical cycles only','bounded adaptive candidate budget','no value-of-information solver','expectedProfit utility')
    markets=$markets.ToArray()
}
New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
Write-TravelAssistantAtomicJson -Path $ArtifactFile -Value $artifact -Depth 16
