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
    param([string]$MarketKey,[long]$TimeBucket,[int]$BaseSeed=0)
    [long]$hash=2166136261L
    foreach ($character in ([string]$MarketKey).ToCharArray()) {
        $hash=(($hash -bxor [int][char]$character) * 16777619L) -band 0x7fffffff
    }
    $hash=($hash -bxor ($TimeBucket -band 0x7fffffff) -bxor $BaseSeed) -band 0x7fffffff
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

function New-SFStockInterval {
    param([long]$StartAt,[long]$EndAt,[long]$Quantity,[long]$ForeignPrice,[int]$Ordinal)
    return [pscustomobject]@{
        startAt=[long]$StartAt
        endAt=[long]$EndAt
        quantity=[long][Math]::Max(1L,$Quantity)
        foreignPrice=[long][Math]::Max(0L,$ForeignPrice)
        cycleOrdinal=[int]$Ordinal
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
        $duration=Get-SFUniformLong -Random $Random -Minimum ([long]$sample.availabilityMinimum) -Maximum ([long]$sample.availabilityMaximum)
        $selloutAt=0L
        if ($restockAt -gt 0) { $selloutAt=$restockAt+$duration }
        else { $selloutAt=$NowEpoch+(Get-SFUniformLong -Random $Random -Minimum 1L -Maximum ([Math]::Max(1L,$duration))) }
        # Condition the sampled residual life on the fresh factual observation:
        # current stock cannot already have sold out at the forecast origin.
        $selloutAt=[Math]::Max($NowEpoch+1L,$selloutAt)
        $intervals.Add((New-SFStockInterval -StartAt $NowEpoch -EndAt $selloutAt -Quantity $currentStock -ForeignPrice $currentPrice -Ordinal 0))
        $anchor=[Math]::Max($NowEpoch,$selloutAt)
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
            $intervals.Add((New-SFStockInterval -StartAt $restockAt -EndAt $selloutAt -Quantity ([long]$sample.quantity) -ForeignPrice ([long]$sample.foreignPrice) -Ordinal $ordinal))
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
        $start=[long]$interval.startAt; $end=[long]$interval.endAt
        if ($ArrivalAt -lt $start -or $ArrivalAt -ge $end) { continue }
        $duration=[Math]::Max(1L,$end-$start)
        $remaining=[Math]::Max(0L,$end-$ArrivalAt)
        $quantity=[long][Math]::Ceiling(([double][long]$interval.quantity*$remaining)/$duration)
        return [pscustomobject]@{ quantity=[Math]::Max(0L,$quantity); foreignPrice=[long]$interval.foreignPrice; cycleOrdinal=[int]$interval.cycleOrdinal }
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
    if ($ArrivalAt -ne $NowEpoch -or $sourceAt -le 0 -or ($NowEpoch-$sourceAt) -gt 300L -or $stock -le 0) { return $null }
    $qty=[Math]::Min([Math]::Max(1,$TargetQuantity),[int]$stock)
    $economics=Get-SFEconomics -Quantity $qty -MarketValue $MarketValue -ForeignPrice ([long](Get-SFProperty $Market 'lastForeignPrice')) -MarketFeePercent $MarketFeePercent -OneWaySeconds $OneWaySeconds
    return [pscustomobject]@{
        arrivalAt=$ArrivalAt; departureAt=0L; pAnyStock=1.0; pTargetQty=$(if($stock -ge $TargetQuantity){1.0}else{0.0})
        expectedQty=[double]$qty; expectedProfit=[double]$economics.profit; expectedProfitPerHour=[double]$economics.profitPerHour
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
    if ([double]$best.pAnyStock -le 0 -or [double]$best.expectedProfit -le 0) { return [pscustomobject]@{ state='WAIT'; reason='no positive expected-profit arrival is present on the evaluated grid' } }
    $departure=[long]$best.departureAt
    if ($departure -le ($NowEpoch+60L)) { return [pscustomobject]@{ state='LEAVE_NOW'; reason='best expected-profit feasible departure is now' } }
    return [pscustomobject]@{ state='LEAVE_IN'; reason='a later feasible departure has the highest expected profit' }
}

function Invoke-SFMarketForecast {
    param(
        [string]$MarketKey,
        [object[]]$Cycles,
        [object]$Market,
        [object]$Destination,
        [object]$Travel,
        [long]$NowEpoch,
        [int]$ScenarioCount=128,
        [int]$TargetQuantity=1,
        [long]$MarketValue=0L,
        [int]$MarketFeePercent=0,
        [long]$OneWaySeconds=0L,
        [int]$RandomSeed=1,
        [long]$HalfLifeSeconds=1209600L
    )
    $evidence=@(Select-SFJointCycleEvidence -Cycles $Cycles -AsOf $NowEpoch -HalfLifeSeconds $HalfLifeSeconds)
    $candidates=@(Get-SFProperty $Travel 'candidates')
    $sampleCount=$evidence.Count
    $effective=Get-SFEffectiveSampleSize -Evidence $evidence

    if ($sampleCount -lt 3) {
        $direct=@()
        if (@($candidates).Count -eq 1) {
            $observed=Get-SFDirectObservedArrival -Market $Market -NowEpoch $NowEpoch -ArrivalAt ([long]$candidates[0].arrivalAt) -TargetQuantity $TargetQuantity -MarketValue $MarketValue -MarketFeePercent $MarketFeePercent -OneWaySeconds $OneWaySeconds
            if ($null -ne $observed) { $direct=@($observed) }
        }
        $decision=Get-SFDecision -Travel $Travel -Arrivals $direct -SampleCount $(if($direct.Count -gt 0){3}else{$sampleCount}) -NowEpoch $NowEpoch
        return [pscustomobject]@{ sampleCount=$sampleCount; effectiveSampleSize=[Math]::Round($effective,3); evidenceQuality=$(if($direct.Count -gt 0){'bounded_fresh'}else{'insufficient'}); arrivals=$direct; decision=$decision; maximumCycleOrdinal=0 }
    }
    if (-not [bool](Get-SFProperty $Travel 'feasible') -or $candidates.Count -eq 0) {
        $decision=Get-SFDecision -Travel $Travel -Arrivals @() -SampleCount $sampleCount -NowEpoch $NowEpoch
        return [pscustomobject]@{ sampleCount=$sampleCount; effectiveSampleSize=[Math]::Round($effective,3); evidenceQuality='usable'; arrivals=@(); decision=$decision; maximumCycleOrdinal=0 }
    }

    $n=$candidates.Count
    $any=New-Object 'double[]' $n
    $target=New-Object 'double[]' $n
    $quantity=New-Object 'double[]' $n
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
                    $duration=[Math]::Max(1L,[long]$interval.endAt-[long]$interval.startAt)
                    $remaining=[Math]::Max(0L,[long]$interval.endAt-$arrivalAt)
                    $stock.quantity=[long][Math]::Ceiling(([double][long]$interval.quantity*$remaining)/$duration)
                    $stock.foreignPrice=[long]$interval.foreignPrice
                    $stock.cycleOrdinal=[int]$interval.cycleOrdinal
                }
            }
            $available=[long]$stock.quantity
            if ($available -gt 0) { $any[$j]++ }
            if ($available -ge $TargetQuantity) { $target[$j]++ }
            $purchasable=[Math]::Min([Math]::Max(1,$TargetQuantity),[int]$available)
            $quantity[$j]+=$purchasable
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
            expectedProfit=[Math]::Round($expectedProfit,2)
            expectedProfitPerHour=[Math]::Round($(if($hours -gt 0){$expectedProfit/$hours}else{0.0}),2)
            maximumCycleOrdinal=[int]$maxOrdinal[$j]
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
    $oneWay=Get-SFTravelSeconds -State $state -Country $country
    $travel=Get-SFTravelCandidates -TravelState $travelState -MarketCountry $country -TravelDestinationCountry $travelDestination -TravelTimeLeft $travelLeft -OneWaySeconds $oneWay -NowEpoch $Now -StepSeconds $GridSeconds -SearchSeconds $DepartureSearchSeconds
    $targetQuantity=1
    $quantityText=[string]$state[$prefix+'QuantityText']
    if ($quantityText -match '([1-9][0-9]*)') { $targetQuantity=[int]$Matches[1] }
    $marketValue=0L; $fee=0
    [void][long]::TryParse([string]$state[$prefix+'MarketValueValue'],[ref]$marketValue)
    [void][int]::TryParse([string]$state[$prefix+'MarketFeePercent'],[ref]$fee)
    $marketSeed=Get-SFStableSeed -MarketKey $key -TimeBucket ([long][Math]::Floor($Now/60.0)) -BaseSeed $Seed
    $forecast=Invoke-SFMarketForecast -MarketKey $key -Cycles $cycles -Market $market -Destination $destination -Travel $travel -NowEpoch $Now -ScenarioCount $SimulationCount -TargetQuantity $targetQuantity -MarketValue $marketValue -MarketFeePercent $fee -OneWaySeconds $oneWay -RandomSeed $marketSeed
    $best=$null
    if (@($forecast.arrivals).Count -gt 0) { $best=@($forecast.arrivals | Sort-Object @{Expression='expectedProfit';Descending=$true},@{Expression='pTargetQty';Descending=$true},arrivalAt | Select-Object -First 1)[0] }
    $lastGoodDepartureAt=0L
    if (@($forecast.arrivals).Count -gt 0) {
        $lastGood=@($forecast.arrivals | Where-Object { [double]$_.expectedProfit -gt 0 -and [double]$_.pAnyStock -gt 0 } | Sort-Object departureAt -Descending | Select-Object -First 1)
        if ($lastGood.Count -gt 0) { $lastGoodDepartureAt=[long]$lastGood[0].departureAt }
    }
    $markets.Add([pscustomobject]@{
        marketKey=$key; countryId=$country; itemId=$itemId; generatedAt=$Now; modelVersion='stochastic-v1'
        sampleCount=[int]$forecast.sampleCount; effectiveSampleSize=[double]$forecast.effectiveSampleSize; evidenceQuality=[string]$forecast.evidenceQuality
        targetQuantity=$targetQuantity; targetQuantityDefinition='projected trip quantity'; simulationCount=$SimulationCount; gridSeconds=$GridSeconds
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
            expectedProfit=$(if($null -ne $best){[double]$best.expectedProfit}else{0.0})
            expectedProfitPerHour=$(if($null -ne $best){[double]$best.expectedProfitPerHour}else{0.0})
            bestDepartureAt=$(if($null -ne $best){[long]$best.departureAt}else{0L})
            bestArrivalAt=$(if($null -ne $best){[long]$best.arrivalAt}else{0L})
            lastGoodDepartureAt=$lastGoodDepartureAt
            evidenceQuality=[string]$forecast.evidenceQuality
        }
        diagnostics=[pscustomobject]@{
            travelMode=[string]$travel.mode; travelReason=[string]$travel.reason; maximumCycleOrdinal=[int]$forecast.maximumCycleOrdinal
            recencyHalfLifeSeconds=1209600L; utilityObjective='expectedProfit'; regimeAdaptation='extension_point'; valueOfInformation='not_implemented'
        }
    })
}

$stopwatch.Stop()
$artifact=[pscustomobject]@{
    schemaVersion=1
    modelVersion='stochastic-v1'
    mode='shadow'
    generatedAt=$Now
    simulationCount=$SimulationCount
    gridSeconds=$GridSeconds
    departureSearchSeconds=$DepartureSearchSeconds
    runtimeMilliseconds=[Math]::Round($stopwatch.Elapsed.TotalMilliseconds,2)
    marketCount=$markets.Count
    decisionStates=@('INSUFFICIENT_DATA','NO_ACTIONABLE_TRIP','WAIT','LEAVE_IN','LEAVE_NOW','LEAVE_BEFORE','COMMITTED','BUY_NOW','MISSED_TARGET')
    limitations=@('uncalibrated probabilities','linear within-cycle depletion','empirical cycles only','no value-of-information solver','expectedProfit utility')
    markets=$markets.ToArray()
}
New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
Write-TravelAssistantAtomicJson -Path $ArtifactFile -Value $artifact -Depth 16
