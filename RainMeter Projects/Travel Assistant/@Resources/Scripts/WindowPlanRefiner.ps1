param(
    [Alias('SkipMain')]
    [switch]$WindowPlanRefinerSkipMain,
    [long]$Now = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# WindowPlan exposes shared model helpers. Its -SkipMain switch intentionally uses
# its own variable; keep this refiner's entrypoint switch separately named so the
# dot-source cannot accidentally suppress normal production execution.
. (Join-Path $PSScriptRoot 'WindowPlan.ps1') -SkipMain

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$SeedDir = Join-Path $ProjectRoot 'data\seed'
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$StateKvFile = Join-Path $GeneratedDir 'state.kv'
$RuntimeCycleFile = Join-Path $RuntimeDir 'cycles.jsonl'
$SeedCycleFile = Join-Path $SeedDir 'cycles.jsonl'

function Get-StableWindowMedian {
    param([long[]]$Values)
    $sorted = [long[]]@($Values | Where-Object { $_ -gt 0 } | Sort-Object)
    if ($sorted.Count -eq 0) { return 0L }
    $mid = [int][Math]::Floor($sorted.Count / 2.0)
    if (($sorted.Count % 2) -eq 1) { return [long]$sorted[$mid] }
    return [long][Math]::Round(([double]$sorted[$mid-1] + [double]$sorted[$mid]) / 2.0)
}

function Test-WindowBoundaryQuality {
    param([string]$Quality)
    $value=([string]$Quality).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($value)) { return $false }
    return ($value -in @('observed','bounded','recovered'))
}

function Get-CurrentCycleDeparturePlan {
    param(
        [long]$CurrentStock,
        [long]$ActiveSelloutEstimateAt,
        [long]$FlightSeconds,
        [long]$EarliestDepartureAt,
        [long]$NowEpoch,
        [double]$SafetyMarginFraction = 0.05
    )

    $flight=[Math]::Max(0L,$FlightSeconds)
    $remaining=[Math]::Max(0L,$ActiveSelloutEstimateAt-$NowEpoch)
    $fraction=[Math]::Max(0.0,[Math]::Min(0.5,$SafetyMarginFraction))
    $safety=[long][Math]::Ceiling($remaining*$fraction)
    $deadline=0L
    if ($ActiveSelloutEstimateAt -gt 0) {
        $deadline=[long]$ActiveSelloutEstimateAt-$flight-$safety
    }
    $reachable=(
        $CurrentStock -gt 0 -and
        $ActiveSelloutEstimateAt -gt $NowEpoch -and
        $deadline -ge [Math]::Max($NowEpoch,$EarliestDepartureAt)
    )
    return [pscustomobject]@{
        reachable=[bool]$reachable
        leaveDeadlineAt=[long]$deadline
        selloutAt=[long]$ActiveSelloutEstimateAt
        flightSeconds=[long]$flight
        safetyMarginSeconds=[long]$safety
        safetyMarginFraction=[double]$fraction
    }
}

function Get-StableCurrentCycleArrivalProbability {
    param(
        [object[]]$Cycles,
        [long]$ActiveRestockAt,
        [long]$ArrivalAt
    )
    $usable=@(Get-StableWindowUsableCycles -Cycles $Cycles)
    if ($usable.Count -eq 0 -or $ActiveRestockAt -le 0 -or $ArrivalAt -lt $ActiveRestockAt) { return -1.0 }
    $age=[Math]::Max(0L,$ArrivalAt-$ActiveRestockAt)
    $hits=0
    foreach ($cycle in $usable) {
        if ([long]$cycle.availabilitySeconds -gt $age) { $hits++ }
    }
    return ($hits/[double]$usable.Count)
}
function Get-StableWindowUsableCycles {
    param(
        [object[]]$Cycles,
        [int]$MaximumSamples = 48,
        [long]$RecentRegimeSeconds = 43200L,
        [int]$MinimumRecentRegimeSamples = 4
    )
    $usable = @(Select-CadenceAwareForecastCycles -Cycles $Cycles -MaximumSamples $MaximumSamples)

    # Live Safe/Best geometry should describe the current market regime. Older
    # cycles remain retained for long-horizon analytics and shadow forecasting,
    # but a materially different old delay must not widen the immediate restock
    # band when at least four completed cycles exist inside the latest 12 hours.
    # Anchor the window to the newest completed cycle rather than wall clock so a
    # short collector outage does not make all recent evidence disappear at once.
    if ($usable.Count -ge $MinimumRecentRegimeSamples -and $RecentRegimeSeconds -gt 0) {
        $latestSoldOutAt = 0L
        foreach ($cycle in $usable) {
            if ($cycle.PSObject.Properties['soldOutAt']) {
                $soldOutAt = [long]$cycle.soldOutAt
                if ($soldOutAt -gt $latestSoldOutAt) { $latestSoldOutAt = $soldOutAt }
            }
        }
        if ($latestSoldOutAt -gt 0) {
            $recentCutoff = $latestSoldOutAt - $RecentRegimeSeconds
            $recent = @($usable | Where-Object {
                $_.PSObject.Properties['soldOutAt'] -and [long]$_.soldOutAt -ge $recentCutoff
            })
            if ($recent.Count -ge $MinimumRecentRegimeSamples) { $usable = $recent }
        }
    }

    if ($usable.Count -lt 5) { return $usable }

    $periods = [long[]]@($usable | ForEach-Object { [long]$_.restockDelaySeconds + [long]$_.availabilitySeconds })
    $medianPeriod = Get-StableWindowMedian -Values $periods
    if ($medianPeriod -le 0) { return $usable }

    # Collector outages can turn one apparent out-of-stock span into a many-hour
    # pseudo-cycle. Keep those records for analytics, but do not let them phase-shift
    # the live departure forecast. Require a broad robust band around the recent median.
    $minimumPeriod = [Math]::Max(60L,[long][Math]::Floor($medianPeriod * 0.35))
    $maximumPeriod = [Math]::Max([long][Math]::Ceiling($medianPeriod * 2.5),$medianPeriod + 3600L)
    $filtered = @($usable | Where-Object {
        $period = [long]$_.restockDelaySeconds + [long]$_.availabilitySeconds
        $period -ge $minimumPeriod -and $period -le $maximumPeriod
    })
    $minimumKeep = [Math]::Max(3,[int][Math]::Ceiling($usable.Count * 0.5))
    if ($filtered.Count -ge $minimumKeep) { return $filtered }
    return $usable
}

function Get-LiveCycleProjection {
    param(
        [long]$CurrentStock,
        [long]$SourceTimestamp,
        [object]$DestinationState,
        [object[]]$Cycles,
        [long]$NowEpoch,
        [long]$LiveMaximumAgeSeconds = 300L
    )
    $usable = @(Get-StableWindowUsableCycles -Cycles $Cycles)
    $medianDelay = Get-StableWindowMedian -Values ([long[]]@($usable | ForEach-Object { [long]$_.restockDelaySeconds }))
    $medianAvailable = Get-StableWindowMedian -Values ([long[]]@($usable | ForEach-Object { [long]$_.availabilitySeconds }))
    $sourceAt = if ($SourceTimestamp -gt 0) { [Math]::Min($SourceTimestamp,$NowEpoch) } else { $NowEpoch }
    $sourceFresh = ($SourceTimestamp -gt 0 -and ($NowEpoch-$SourceTimestamp) -le $LiveMaximumAgeSeconds)
    $stock = if ($sourceFresh) { [Math]::Max(0L,$CurrentStock) } else { 0L }
    $activeRestockAt=0L; $selloutAt=0L; $nextRestockAt=0L; $mode='none'

    $activeCycle=Get-WindowProperty $DestinationState 'activeCycle'
    if ($null -ne $activeCycle) { $activeRestockAt=[long](Get-WindowProperty $activeCycle 'restockAt') }
    if ($stock -gt 0 -and $activeRestockAt -gt 0) {
        $restockQuantity=[long](Get-WindowProperty $activeCycle 'restockQuantity')
        $elapsed=[Math]::Max(0L,$sourceAt-$activeRestockAt)
        $sold=[Math]::Max(0L,$restockQuantity-$stock)
        if ($restockQuantity -gt $stock -and $elapsed -ge 120L -and $sold -ge 10L) {
            $unitsPerSecond=$sold/[double]$elapsed
            if ($unitsPerSecond -gt 0) {
                $remaining=[long][Math]::Ceiling($stock/$unitsPerSecond)
                $selloutAt=$sourceAt+[Math]::Max(60L,$remaining)
                $mode='live-depletion'
                if ($medianDelay -gt 0) { $nextRestockAt=$selloutAt+$medianDelay }
            }
        }
        if ($mode -eq 'none' -and $medianAvailable -gt 0) {
            $historicalSelloutAt=$activeRestockAt+$medianAvailable
            if ($historicalSelloutAt -gt $sourceAt) {
                $selloutAt=$historicalSelloutAt
                $mode='historical-duration'
                if ($medianDelay -gt 0) { $nextRestockAt=$selloutAt+$medianDelay }
            }
        }
        if ($mode -eq 'none') { $mode='live-stock-learning' }
    } elseif ($sourceFresh -and $stock -eq 0) {
        $lastSellOutAt=[long](Get-WindowProperty $DestinationState 'lastSellOutAt')
        if ($lastSellOutAt -gt 0 -and $medianDelay -gt 0) {
            $nextRestockAt=$lastSellOutAt+$medianDelay
            $mode='observed-oos'
        } else { $mode='oos-learning' }
    } elseif (-not $sourceFresh) { $mode='stale-source' }

    return [pscustomobject]@{
        currentStock=[long]$stock
        sourceTimestamp=[long]$SourceTimestamp
        activeRestockAt=[long]$activeRestockAt
        activeSelloutEstimateAt=[long]$selloutAt
        nextRestockEstimateAt=[long]$nextRestockAt
        medianRestockDelaySeconds=[long]$medianDelay
        medianAvailabilitySeconds=[long]$medianAvailable
        mode=[string]$mode
    }
}

function Get-StableRecurringScenarioModel {
    param(
        [object[]]$Cycles,
        [long]$AnchorAt,
        [ValidateSet('sellout','restock')][string]$AnchorPhase,
        [long]$NowEpoch,
        [long]$FutureHorizonSeconds = 86400L,
        [long]$MinimumSafeWindowSeconds = 60L,
        [int]$MaximumOrdinal = 1
    )
    $usable = @(Get-StableWindowUsableCycles -Cycles $Cycles)
    if ($AnchorAt -le 0 -or $usable.Count -eq 0) {
        return [pscustomobject]@{ sampleCount=0; anchorAt=$AnchorAt; anchorPhase=$AnchorPhase; medianPeriodSeconds=0L; cycles=@(); groups=@(); segments=@() }
    }

    $periods = [long[]]@($usable | ForEach-Object { [long]$_.restockDelaySeconds + [long]$_.availabilitySeconds })
    $medianPeriod = Get-StableWindowMedian -Values $periods
    if ($medianPeriod -le 0) {
        return [pscustomobject]@{ sampleCount=0; anchorAt=$AnchorAt; anchorPhase=$AnchorPhase; medianPeriodSeconds=0L; cycles=@(); groups=@(); segments=@() }
    }

    $currentAge = [Math]::Max(0L,$NowEpoch-$AnchorAt)

    # The fixed horizon is only a minimum. Long stock/depletion cycles must still
    # generate the immediately next cycle; otherwise valid evidence incorrectly
    # collapses to WAIT DATA simply because the period exceeds 24 hours.
    $maximumObservedPeriod = 0L
    $maximumObservedAvailability = 0L
    foreach ($cycle in $usable) {
        $cycleDelay=[long]$cycle.restockDelaySeconds
        $cycleAvailable=[long]$cycle.availabilitySeconds
        $cyclePeriod=$cycleDelay+$cycleAvailable
        if ($cyclePeriod -gt $maximumObservedPeriod) { $maximumObservedPeriod=$cyclePeriod }
        if ($cycleAvailable -gt $maximumObservedAvailability) { $maximumObservedAvailability=$cycleAvailable }
    }
    $nextCycleRequiredAge = if ($AnchorPhase -eq 'restock') {
        $maximumObservedPeriod + $maximumObservedAvailability + 1L
    } else {
        $maximumObservedPeriod + 1L
    }
    $maxAge = [Math]::Max(
        $currentAge + [Math]::Max(3600L,$FutureHorizonSeconds),
        $nextCycleRequiredAge
    )
    $groups = @{}
    $deltas = @{}

    foreach ($cycle in $usable) {
        $delay = [long]$cycle.restockDelaySeconds
        $available = [long]$cycle.availabilitySeconds
        $period = $delay + $available
        for ($ordinal=0; $ordinal -le [Math]::Max(0,$MaximumOrdinal); $ordinal++) {
            # Home/Torn currently supports only the current cycle and the
            # immediately next cycle. Do not spend CPU projecting cycle +2/+3 until
            # those scenarios are explicitly implemented. Each retained cycle remains
            # an empirical draw for the supported ordinal(s).
            if ($AnchorPhase -eq 'restock') {
                $startAge = if ($ordinal -eq 0) { 0L } else { (($ordinal-1) * $medianPeriod) + $period }
            } else {
                $startAge = ($ordinal * $medianPeriod) + $delay
            }
            if ($startAge -ge $maxAge) { break }
            $endAge = $startAge + $available
            if (-not $groups.ContainsKey($ordinal)) { $groups[$ordinal] = New-Object System.Collections.Generic.List[object] }
            $groups[$ordinal].Add([pscustomobject]@{ startAge=[long]$startAge; endAge=[long]$endAge })
            Add-WindowDelta -Map $deltas -At $startAge -Delta 1
            Add-WindowDelta -Map $deltas -At $endAge -Delta -1
        }
    }

    $segments = New-Object System.Collections.Generic.List[object]
    if ($deltas.Count -ge 2) {
        $times = [long[]]@($deltas.Keys | ForEach-Object { [long]$_ } | Sort-Object -Unique)
        $active = 0
        for ($i=0; $i -lt ($times.Count-1); $i++) {
            $at = [long]$times[$i]
            $active += [int]$deltas[[string]$at]
            $next = [long]$times[$i+1]
            if ($next -le $at -or $active -le 0) { continue }
            $segments.Add([pscustomobject]@{
                startAt = $AnchorAt + $at
                endAt = $AnchorAt + $next
                probability = ($active / [double]$usable.Count)
            })
        }
    }

    $resultGroups = New-Object System.Collections.Generic.List[object]
    foreach ($ordinal in @($groups.Keys | Sort-Object {[int]$_})) {
        $intervals = @($groups[$ordinal].ToArray())
        if ($intervals.Count -ne $usable.Count) { continue }
        $starts = [long[]]@($intervals | ForEach-Object { $AnchorAt + [long]$_.startAge })
        $ends = [long[]]@($intervals | ForEach-Object { $AnchorAt + [long]$_.endAge })
        $earlyRestockAt = [long](@($starts | Measure-Object -Minimum).Minimum)
        $lateRestockAt = [long](@($starts | Measure-Object -Maximum).Maximum)
        $earlySelloutAt = [long](@($ends | Measure-Object -Minimum).Minimum)
        $lateSelloutAt = [long](@($ends | Measure-Object -Maximum).Maximum)
        if ($lateSelloutAt -le $NowEpoch) { continue }

        $safeStartAt = $lateRestockAt
        $safeEndAt = $earlySelloutAt
        $safeSeconds = [Math]::Max(0L,$safeEndAt-$safeStartAt)
        if ($safeSeconds -lt $MinimumSafeWindowSeconds) { $safeStartAt=0L; $safeEndAt=0L; $safeSeconds=0L }

        $overlapSegments = @($segments.ToArray() | Where-Object {
            [long]$_.endAt -gt $earlyRestockAt -and [long]$_.startAt -lt $lateSelloutAt
        })
        $best = $null
        if ($overlapSegments.Count -gt 0) {
            $best = @($overlapSegments | Sort-Object @{Expression='probability';Descending=$true},startAt | Select-Object -First 1)[0]
        }
        $bestStartAt=0L; $bestEndAt=0L; $bestProbability=0.0
        if ($null -ne $best) {
            $bestStartAt=[long]$best.startAt
            $bestEndAt=[long]$best.endAt
            $bestProbability=[double]$best.probability
        }

        $resultGroups.Add([pscustomobject]@{
            ordinal=[int]$ordinal
            earlyRestockAt=$earlyRestockAt
            earlySelloutAt=$earlySelloutAt
            lateRestockAt=$lateRestockAt
            lateSelloutAt=$lateSelloutAt
            safeStartAt=$safeStartAt
            safeEndAt=$safeEndAt
            safeSeconds=$safeSeconds
            bestStartAt=$bestStartAt
            bestEndAt=$bestEndAt
            bestProbability=$bestProbability
            sampleCount=$usable.Count
        })
    }

    $cyclePairs = @($usable | ForEach-Object { [pscustomobject]@{ delay=[long]$_.restockDelaySeconds; available=[long]$_.availabilitySeconds } })
    return [pscustomobject]@{
        sampleCount=$usable.Count
        anchorAt=$AnchorAt
        anchorPhase=$AnchorPhase
        medianPeriodSeconds=$medianPeriod
        cycles=$cyclePairs
        groups=$resultGroups.ToArray()
        segments=$segments.ToArray()
    }
}

function Select-StableWindowPlanGroup {
    param([object]$Model,[long]$EarliestArrivalAt,[double]$MinimumBestProbability = 0.5)
    if ($null -eq $Model) { return $null }
    foreach ($group in @($Model.groups | Sort-Object ordinal)) {
        if ([long]$group.lateSelloutAt -le $EarliestArrivalAt) { continue }
        if ([long]$group.safeStartAt -gt 0 -and [long]$group.safeEndAt -gt [Math]::Max($EarliestArrivalAt,[long]$group.safeStartAt)) {
            return [pscustomobject]@{ mode='safe'; startAt=[long]$group.safeStartAt; endAt=[long]$group.safeEndAt; probability=1.0; group=$group }
        }
        if ([double]$group.bestProbability -gt $MinimumBestProbability -and [long]$group.bestEndAt -gt $EarliestArrivalAt) {
            return [pscustomobject]@{ mode='best'; startAt=[long]$group.bestStartAt; endAt=[long]$group.bestEndAt; probability=[double]$group.bestProbability; group=$group }
        }
    }
    return $null
}

function Get-WindowPriceInfo {
    param([object]$Engine,[string]$Key)
    $varies = Test-WindowPriceVaries -Engine $Engine -Key $Key
    $minimum = 0L
    $maximum = 0L
    $root=Get-WindowProperty $Engine 'cycleAnalytics'
    $markets=Get-WindowProperty $root 'markets'
    $market=Get-WindowProperty $markets $Key
    $stats=Get-WindowProperty $market 'foreignPrice'
    if ($null -ne $stats) {
        $minimum=[long](Get-WindowProperty $stats 'min')
        $maximum=[long](Get-WindowProperty $stats 'max')
    }
    return [pscustomobject]@{ varies=[bool]$varies; minimum=$minimum; maximum=$maximum }
}

function Remove-WindowMachineEnvelope {
    param([string]$Text)
    $value=[string]$Text
    if ($value -match '^WP2:[^#]*#PV[01]#(.*)$') { return [string]$Matches[1] }
    if ($value -match '^PV[01]#(.*)$') { return [string]$Matches[1] }
    return $value
}

if ($WindowPlanRefinerSkipMain) { return }
if ($Now -le 0) { $Now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
$state=Read-WindowStateKv $StateKvFile
$engine=Read-WindowJson $EngineStateFile
if ($state.Count -eq 0 -or $null -eq $engine -or -not $engine.PSObject.Properties['observedMarkets']) { return }
$count=0
[void][int]::TryParse([string]$state['OpportunityCount'],[ref]$count)
$count=[Math]::Min(256,[Math]::Max(0,$count))
if ($count -le 0) { return }

$wanted=@{}
for ($i=1; $i -le $count; $i++) {
    $prefix='Opportunity'+$i
    $key=[string]$state[$prefix+'Key']
    $forecastMode=([string]$state[$prefix+'ForecastMode']).Trim().ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($key) -and $forecastMode -ne 'sleeping_oos') { $wanted[$key]=$true }
}
$cycleMap=Read-WindowCyclesForKeys -Paths @($SeedCycleFile,$RuntimeCycleFile) -Wanted $wanted
$travelState=([string]$state['TravelState']).Trim().ToLowerInvariant()
$destinationCountry=([string]$state['TravelDestinationCountryId']).Trim().ToLowerInvariant()
$travelLeft=0L
[void][long]::TryParse([string]$state['TravelTimeLeft'],[ref]$travelLeft)

for ($i=1; $i -le $count; $i++) {
    $prefix='Opportunity'+$i
    $key=[string]$state[$prefix+'Key']
    if ([string]::IsNullOrWhiteSpace($key)) { continue }
    $forecastMode=([string]$state[$prefix+'ForecastMode']).Trim().ToLowerInvariant()
    if ($forecastMode -eq 'sleeping_oos') {
        # OpportunityState already published the cheap absolute restock estimate.
        # Do not read cycle evidence or build recurring probability geometry until
        # the wake boundary/focus marker promotes this market back to detailed mode.
        $state[$prefix+'CurrentStock']='0'
        $state[$prefix+'WindowDataQuality']='ready'
        $state[$prefix+'WindowDataQualityReason']=''
        $state[$prefix+'CurrentCycleReachable']='0'
        $state[$prefix+'CurrentCycleLeaveDeadlineAt']='0'
        $state[$prefix+'CurrentCycleSafetyMarginSeconds']='0'
        continue
    }
    $countryId=($key -split ':',2)[0]
    $cycles=@()
    if ($cycleMap.ContainsKey($key)) { $cycles=@($cycleMap[$key].ToArray()) }
    $market=Get-WindowProperty $engine.observedMarkets $key
    $destinationState=$null
    if ($engine.PSObject.Properties['destinations']) { $destinationState=Get-WindowProperty $engine.destinations $key }
    $stock=0L; $sourceTimestamp=0L
    if ($null -ne $market) {
        $stock=[long](Get-WindowProperty $market 'lastStock')
        $sourceTimestamp=[long](Get-WindowProperty $market 'sourceTimestamp')
    }
    $liveProjection=Get-LiveCycleProjection -CurrentStock $stock -SourceTimestamp $sourceTimestamp -DestinationState $destinationState -Cycles $cycles -NowEpoch $Now
    $stock=[long]$liveProjection.currentStock
    $state[$prefix+'CurrentStock']=$stock
    $state[$prefix+'StockEvidenceAt']=[long]$liveProjection.sourceTimestamp
    $state[$prefix+'ActiveRestockAt']=[long]$liveProjection.activeRestockAt
    $state[$prefix+'ActiveSelloutEstimateAt']=[long]$liveProjection.activeSelloutEstimateAt
    $state[$prefix+'NextRestockEstimateAt']=[long]$liveProjection.nextRestockEstimateAt
    $state[$prefix+'MedianRestockDelaySeconds']=[long]$liveProjection.medianRestockDelaySeconds
    $state[$prefix+'LiveCycleProjectionMode']=[string]$liveProjection.mode
    $state[$prefix+'WindowDataQuality']='ready'
    $state[$prefix+'WindowDataQualityReason']=''
    $anchorAt=0L; $phase='sellout'
    if ($stock -gt 0) {
        $phase='restock'
        $activeCycle=Get-WindowProperty $destinationState 'activeCycle'
        if ($null -ne $activeCycle) { $anchorAt=[long](Get-WindowProperty $activeCycle 'restockAt') }
    } else {
        $anchorAt=[long](Get-WindowProperty $destinationState 'lastSellOutAt')
    }

    # Never turn frozen provider state or an unobserved transition into forecast
    # duration. Check direct current-cycle evidence before paying for any recurring
    # next-cycle geometry.
    $collectingReason=''
    if ([string]$liveProjection.mode -eq 'stale-source') {
        $collectingReason='live stock source is stale'
    } elseif ($stock -gt 0) {
        $activeCycle=Get-WindowProperty $destinationState 'activeCycle'
        $restockAt=if ($null -ne $activeCycle) { [long](Get-WindowProperty $activeCycle 'restockAt') } else { 0L }
        $restockQuality=if ($null -ne $activeCycle) { [string](Get-WindowProperty $activeCycle 'restockBoundaryQuality') } else { '' }
        if ($restockAt -le 0 -or -not (Test-WindowBoundaryQuality -Quality $restockQuality)) {
            $collectingReason='current restock boundary was not observed or recovered'
        } elseif ([long]$liveProjection.activeSelloutEstimateAt -le 0) {
            $collectingReason='current sellout cannot yet be estimated from verified evidence'
        }
    } else {
        $lastSellOutAt=if ($null -ne $destinationState) { [long](Get-WindowProperty $destinationState 'lastSellOutAt') } else { 0L }
        $lastSellOutQuality=if ($null -ne $destinationState) { [string](Get-WindowProperty $destinationState 'lastSellOutBoundaryQuality') } else { '' }
        if ($lastSellOutAt -le 0 -or -not (Test-WindowBoundaryQuality -Quality $lastSellOutQuality)) {
            $collectingReason='sellout boundary was missed during collection'
        }
    }

    if (-not [string]::IsNullOrWhiteSpace($collectingReason)) {
        $state[$prefix+'WindowDataQuality']='collecting'
        $state[$prefix+'WindowDataQualityReason']=$collectingReason
    }

    $flightSeconds=Get-WindowTravelSeconds -State $state -CountryId $countryId
    $earliestDeparture=$Now
    if ($travelState -eq 'returning') { $earliestDeparture=$Now+[Math]::Max(0L,$travelLeft) }
    $earliestArrival=$earliestDeparture+$flightSeconds
    if ($travelState -eq 'traveling' -and $countryId -eq $destinationCountry) {
        $earliestArrival=$Now+[Math]::Max(0L,$travelLeft)
    } elseif ($travelState -in @('abroad','foreign') -and $countryId -eq $destinationCountry) {
        $earliestArrival=$Now
        $flightSeconds=0L
    }
    $state[$prefix+'CurrentCycleReachable']='0'
    $state[$prefix+'CurrentCycleLeaveDeadlineAt']='0'
    $state[$prefix+'CurrentCycleSafetyMarginSeconds']='0'
    $state[$prefix+'NextCycleOrdinal']=if ($stock -gt 0) { '1' } else { '0' }

    if ([string]$state[$prefix+'WindowDataQuality'] -eq 'collecting') {
        $state[$prefix+'WindowStartAt']='0'
        $state[$prefix+'WindowText']='Collecting Data: See Weav3r'
        $state[$prefix+'ChanceText']=''
        $state[$prefix+'ProbabilityValue']='-1'
        continue
    }

    $currentCycle=Get-CurrentCycleDeparturePlan -CurrentStock $stock -ActiveSelloutEstimateAt ([long]$liveProjection.activeSelloutEstimateAt) -FlightSeconds $flightSeconds -EarliestDepartureAt $earliestDeparture -NowEpoch $Now -SafetyMarginFraction 0.05
    if ([bool]$currentCycle.reachable) {
        $state[$prefix+'CurrentCycleReachable']='1'
        $state[$prefix+'CurrentCycleLeaveDeadlineAt']=[long]$currentCycle.leaveDeadlineAt
        $state[$prefix+'CurrentCycleSafetyMarginSeconds']=[long]$currentCycle.safetyMarginSeconds
        $state[$prefix+'WindowStartAt']=[Math]::Max($Now,$earliestDeparture)
        $state[$prefix+'WindowText']='IN STOCK'
        $currentProbability=Get-StableCurrentCycleArrivalProbability -Cycles $cycles -ActiveRestockAt ([long]$liveProjection.activeRestockAt) -ArrivalAt $earliestArrival
        if ($currentProbability -ge 0) {
            $state[$prefix+'ProbabilityValue']=(Convert-WindowProbabilityText ([double]$currentProbability))
            $state[$prefix+'ChanceText']=('{0:N0}%' -f (100.0*[double]$currentProbability))
        }
        # Scenario 1 is fully resolved from the direct current cycle. Do not build
        # the recurring next-cycle model merely to calculate a far-future close.
        continue
    }

    # Only an unreachable current cycle or an OOS market needs next-restock
    # probability geometry.
    $model=Get-StableRecurringScenarioModel -Cycles $cycles -AnchorAt $anchorAt -AnchorPhase $phase -NowEpoch $Now
    if ([int]$model.sampleCount -le 0) {
        $state[$prefix+'WindowDataQuality']='collecting'
        $state[$prefix+'WindowDataQualityReason']='no verified completed cycles are available for the next restock'
        $state[$prefix+'WindowStartAt']='0'
        $state[$prefix+'WindowText']='Collecting Data: See Weav3r'
        $state[$prefix+'ChanceText']=''
        $state[$prefix+'ProbabilityValue']='-1'
        continue
    }

    $machine=Convert-WindowPlanMachineText -Model $model
    $baseTooltip=Remove-WindowMachineEnvelope -Text ([string]$state[$prefix+'Tooltip'])
    $priceInfo=Get-WindowPriceInfo -Engine $engine -Key $key
    $priceEnvelope=if ([bool]$priceInfo.varies) { 'PV1#' } else { 'PV0#' }
    $state[$prefix+'PriceVaries']=if ([bool]$priceInfo.varies) { '1' } else { '0' }
    $state[$prefix+'MinObservedPrice']=[long]$priceInfo.minimum
    $state[$prefix+'MaxObservedPrice']=[long]$priceInfo.maximum
    $state[$prefix+'WindowMedianPeriodSeconds']=[long]$model.medianPeriodSeconds
    if (-not [string]::IsNullOrWhiteSpace($machine)) { $state[$prefix+'Tooltip']='WP2:'+$machine+'#'+$priceEnvelope+$baseTooltip }
    else { $state[$prefix+'Tooltip']=$priceEnvelope+$baseTooltip }

    $selected=Select-StableWindowPlanGroup -Model $model -EarliestArrivalAt $earliestArrival
    if ($null -ne $selected) {
        $departureStart=[long]$selected.startAt-$flightSeconds
        $state[$prefix+'WindowStartAt']=[Math]::Max($Now,$departureStart)
        $state[$prefix+'ProbabilityValue']=(Convert-WindowProbabilityText ([double]$selected.probability))
        if ([string]$selected.mode -eq 'safe') {
            $state[$prefix+'WindowText']='SAFE WINDOW'
            $state[$prefix+'ChanceText']=''
        } else {
            $state[$prefix+'WindowText']='BEST HIT'
            $state[$prefix+'ChanceText']=('{0:N0}%' -f (100.0*[double]$selected.probability))
        }
    }
}
Write-WindowStateKvAtomic -Values $state -Path $StateKvFile
