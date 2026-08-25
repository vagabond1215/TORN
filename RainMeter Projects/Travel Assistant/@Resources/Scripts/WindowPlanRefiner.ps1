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

function Get-StableWindowUsableCycles {
    param([object[]]$Cycles,[int]$MaximumSamples = 48)
    $usable = @($Cycles | Where-Object {
        $null -ne $_ -and
        $_.PSObject.Properties['restockDelaySeconds'] -and [long]$_.restockDelaySeconds -gt 0 -and
        $_.PSObject.Properties['availabilitySeconds'] -and [long]$_.availabilitySeconds -gt 0
    } | Sort-Object @{Expression={ if ($_.PSObject.Properties['soldOutAt']) { [long]$_.soldOutAt } else { 0L } };Descending=$true})
    if ($MaximumSamples -gt 0 -and $usable.Count -gt $MaximumSamples) { $usable = @($usable | Select-Object -First $MaximumSamples) }
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

function Get-StableRecurringScenarioModel {
    param(
        [object[]]$Cycles,
        [long]$AnchorAt,
        [ValidateSet('sellout','restock')][string]$AnchorPhase,
        [long]$NowEpoch,
        [long]$FutureHorizonSeconds = 86400L,
        [long]$MinimumSafeWindowSeconds = 60L
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
    $maxAge = $currentAge + [Math]::Max(3600L,$FutureHorizonSeconds)
    $groups = @{}
    $deltas = @{}

    foreach ($cycle in $usable) {
        $delay = [long]$cycle.restockDelaySeconds
        $available = [long]$cycle.availabilitySeconds
        $period = $delay + $available
        for ($ordinal=0; $ordinal -lt 2048; $ordinal++) {
            # Treat each future cycle as another draw from the observed distribution.
            # Do not repeat one historical period forever: doing so compounds harmless
            # period variance until otherwise-stable cycles drift many hours out of phase.
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
    $key=[string]$state['Opportunity'+$i+'Key']
    if (-not [string]::IsNullOrWhiteSpace($key)) { $wanted[$key]=$true }
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
    $countryId=($key -split ':',2)[0]
    $cycles=@()
    if ($cycleMap.ContainsKey($key)) { $cycles=@($cycleMap[$key].ToArray()) }
    $market=Get-WindowProperty $engine.observedMarkets $key
    $destinationState=$null
    if ($engine.PSObject.Properties['destinations']) { $destinationState=Get-WindowProperty $engine.destinations $key }
    $stock=0L
    if ($null -ne $market) { $stock=[long](Get-WindowProperty $market 'lastStock') }
    $anchorAt=0L; $phase='sellout'
    if ($stock -gt 0) {
        $phase='restock'
        $activeCycle=Get-WindowProperty $destinationState 'activeCycle'
        if ($null -ne $activeCycle) { $anchorAt=[long](Get-WindowProperty $activeCycle 'restockAt') }
    } else {
        $anchorAt=[long](Get-WindowProperty $destinationState 'lastSellOutAt')
    }

    $model=Get-StableRecurringScenarioModel -Cycles $cycles -AnchorAt $anchorAt -AnchorPhase $phase -NowEpoch $Now
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
