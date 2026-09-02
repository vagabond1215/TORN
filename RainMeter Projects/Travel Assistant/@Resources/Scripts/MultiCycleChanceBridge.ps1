param(
    [Alias('SkipMain')]
    [switch]$MultiCycleChanceBridgeSkipMain,
    [long]$Now = 0,
    [ValidateRange(32,1024)]
    [int]$SimulationCount = 256,
    [ValidateRange(1.0,20.0)]
    [double]$MinimumFlightCycleRatio = 2.0,
    [ValidateRange(3,96)]
    [int]$MinimumCycleSamples = 3
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
$AtomicFileScript=Join-Path $PSScriptRoot 'AtomicFile.ps1'
$StochasticScript=Join-Path $PSScriptRoot 'StochasticForecast.ps1'
if (-not (Test-Path -LiteralPath $AtomicFileScript)) { throw 'AtomicFile.ps1 is required for multi-cycle chance bridge publication.' }
if (-not (Test-Path -LiteralPath $StochasticScript)) { throw 'StochasticForecast.ps1 is required for multi-cycle chance bridge evaluation.' }
. $AtomicFileScript
. $StochasticScript -SkipMain

function Write-MCStateKvAtomic {
    param([hashtable]$Values,[string]$Path)
    $lines=New-Object System.Collections.Generic.List[string]
    foreach ($key in @($Values.Keys | Sort-Object)) {
        $value=([string]$Values[$key]).Replace([char]13,[char]32).Replace([char]10,[char]32)
        $lines.Add($key+'='+$value)
    }
    $text=($lines.ToArray() -join [Environment]::NewLine)+[Environment]::NewLine
    Write-TravelAssistantAtomicText -Path $Path -Text $text
}

function Get-MCWeightedTimingDiagnostics {
    param([object[]]$Evidence,[long]$ArrivalHorizonSeconds)

    $rows=@($Evidence)
    if ($rows.Count -eq 0) {
        return [pscustomobject]@{
            sampleCount=0; effectiveSampleSize=0.0
            meanCycleSeconds=0.0; meanInStockSeconds=0.0; cycleStdDevSeconds=0.0
            dutyCycleProbability=-1.0; arrivalCycleRatio=0.0; expectedFullCycles=0
            phaseStdDevSeconds=0.0; phaseStdDevCycles=0.0
        }
    }

    $weightSum=0.0
    $weightedCycle=0.0
    $weightedStock=0.0
    foreach ($row in $rows) {
        $weight=[Math]::Max(0.0,[double](Get-SFProperty $row 'weight'))
        if ($weight -le 0) { continue }
        $delay=(([double](Get-SFProperty $row 'delayMinimum'))+([double](Get-SFProperty $row 'delayMaximum')))/2.0
        $stock=(([double](Get-SFProperty $row 'availabilityMinimum'))+([double](Get-SFProperty $row 'availabilityMaximum')))/2.0
        $period=[Math]::Max(1.0,$delay+$stock)
        $weightSum+=$weight
        $weightedCycle+=($weight*$period)
        $weightedStock+=($weight*[Math]::Max(0.0,$stock))
    }

    if ($weightSum -le 0) {
        return [pscustomobject]@{
            sampleCount=$rows.Count; effectiveSampleSize=[Math]::Round((Get-SFEffectiveSampleSize -Evidence $rows),3)
            meanCycleSeconds=0.0; meanInStockSeconds=0.0; cycleStdDevSeconds=0.0
            dutyCycleProbability=-1.0; arrivalCycleRatio=0.0; expectedFullCycles=0
            phaseStdDevSeconds=0.0; phaseStdDevCycles=0.0
        }
    }

    $meanCycle=$weightedCycle/$weightSum
    $meanStock=$weightedStock/$weightSum
    $variance=0.0
    foreach ($row in $rows) {
        $weight=[Math]::Max(0.0,[double](Get-SFProperty $row 'weight'))
        if ($weight -le 0) { continue }
        $delay=(([double](Get-SFProperty $row 'delayMinimum'))+([double](Get-SFProperty $row 'delayMaximum')))/2.0
        $stock=(([double](Get-SFProperty $row 'availabilityMinimum'))+([double](Get-SFProperty $row 'availabilityMaximum')))/2.0
        $period=[Math]::Max(1.0,$delay+$stock)
        $delta=$period-$meanCycle
        $variance+=($weight*$delta*$delta)
    }
    $variance/=$weightSum
    $std=[Math]::Sqrt([Math]::Max(0.0,$variance))
    $horizon=[Math]::Max(0L,$ArrivalHorizonSeconds)
    $ratio=if($meanCycle -gt 0){[double]$horizon/$meanCycle}else{0.0}
    $phaseStd=if($ratio -gt 0){[Math]::Sqrt($ratio)*$std}else{0.0}
    $duty=if($meanCycle -gt 0){[Math]::Max(0.0,[Math]::Min(1.0,$meanStock/$meanCycle))}else{-1.0}

    return [pscustomobject]@{
        sampleCount=$rows.Count
        effectiveSampleSize=[Math]::Round((Get-SFEffectiveSampleSize -Evidence $rows),3)
        meanCycleSeconds=[Math]::Round($meanCycle,3)
        meanInStockSeconds=[Math]::Round($meanStock,3)
        cycleStdDevSeconds=[Math]::Round($std,3)
        dutyCycleProbability=[Math]::Round($duty,6)
        arrivalCycleRatio=[Math]::Round($ratio,6)
        expectedFullCycles=[int][Math]::Floor([Math]::Max(0.0,$ratio))
        phaseStdDevSeconds=[Math]::Round($phaseStd,3)
        phaseStdDevCycles=$(if($meanCycle -gt 0){[Math]::Round($phaseStd/$meanCycle,6)}else{0.0})
    }
}

function Get-MCArrivalCandidate {
    param(
        [string]$TravelState,
        [string]$MarketCountry,
        [string]$TravelDestinationCountry,
        [long]$TravelTimeLeft,
        [long]$OneWaySeconds,
        [long]$NowEpoch
    )

    $state=([string]$TravelState).Trim().ToLowerInvariant()
    $country=([string]$MarketCountry).Trim().ToLowerInvariant()
    $destination=([string]$TravelDestinationCountry).Trim().ToLowerInvariant()

    if ($state -in @('traveling_unknown','abroad_unknown','unknown')) {
        return [pscustomobject]@{ feasible=$false; mode='unknown_destination'; reason='travel destination is unresolved'; arrivalHorizonSeconds=0L; candidates=@() }
    }
    if ($state -in @('traveling','outbound','outbound_to_target')) {
        if ([string]::IsNullOrWhiteSpace($destination) -or $destination -ne $country) {
            return [pscustomobject]@{ feasible=$false; mode='traveling_elsewhere'; reason='already outbound to another destination'; arrivalHorizonSeconds=0L; candidates=@() }
        }
        $horizon=[Math]::Max(0L,$TravelTimeLeft)
        return [pscustomobject]@{
            feasible=$true; mode='committed'; reason='evaluate the already committed landing'
            arrivalHorizonSeconds=$horizon
            candidates=@([pscustomobject]@{departureAt=0L;arrivalAt=[long]($NowEpoch+$horizon)})
        }
    }
    if ($state -in @('abroad','foreign','abroad_at_target')) {
        return [pscustomobject]@{ feasible=$false; mode='already_abroad'; reason='multi-cycle departure fallback is unnecessary while abroad'; arrivalHorizonSeconds=0L; candidates=@() }
    }
    if ($OneWaySeconds -le 0) {
        return [pscustomobject]@{ feasible=$false; mode='missing_travel_time'; reason='configured one-way travel time is unavailable'; arrivalHorizonSeconds=0L; candidates=@() }
    }

    $departure=$NowEpoch
    if ($state -eq 'returning') { $departure=$NowEpoch+[Math]::Max(0L,$TravelTimeLeft) }
    elseif ($state -notin @('home','torn','in_torn','')) {
        return [pscustomobject]@{ feasible=$false; mode='unsupported_travel_state'; reason=('unsupported travel state: '+$state); arrivalHorizonSeconds=0L; candidates=@() }
    }
    $arrival=$departure+[Math]::Max(0L,$OneWaySeconds)
    return [pscustomobject]@{
        feasible=$true
        mode=$(if($state -eq 'returning'){'returning'}else{'home'})
        reason=$(if($state -eq 'returning'){'leave for target immediately after return to Torn'}else{'leave for target now'})
        arrivalHorizonSeconds=[Math]::Max(0L,$arrival-$NowEpoch)
        candidates=@([pscustomobject]@{departureAt=[long]$departure;arrivalAt=[long]$arrival})
    }
}

function Get-MCMultiCycleChance {
    param(
        [string]$MarketKey,
        [object[]]$Cycles,
        [object[]]$Observations,
        [object]$Market,
        [object]$Destination,
        [object]$Travel,
        [long]$NowEpoch,
        [int]$ScenarioCount=256,
        [int]$TargetQuantity=1,
        [long]$MarketValue=0L,
        [int]$MarketFeePercent=0,
        [long]$OneWaySeconds=0L,
        [double]$MinimumRatio=2.0,
        [int]$MinimumSamples=3,
        [int]$RandomSeed=1
    )

    $evidence=@(Select-SFJointCycleEvidence -Cycles $Cycles -AsOf $NowEpoch -Observations $Observations)
    $horizon=[long](Get-SFProperty $Travel 'arrivalHorizonSeconds')
    $timing=Get-MCWeightedTimingDiagnostics -Evidence $evidence -ArrivalHorizonSeconds $horizon
    $eligible=(
        [bool](Get-SFProperty $Travel 'feasible') -and
        [int]$timing.sampleCount -ge [Math]::Max(3,$MinimumSamples) -and
        [double]$timing.arrivalCycleRatio -ge $MinimumRatio -and
        @((Get-SFProperty $Travel 'candidates')).Count -eq 1
    )

    if (-not $eligible) {
        return [pscustomobject]@{
            eligible=$false
            reason=$(if(-not [bool](Get-SFProperty $Travel 'feasible')){[string](Get-SFProperty $Travel 'reason')}
                elseif([int]$timing.sampleCount -lt [Math]::Max(3,$MinimumSamples)){'fewer than the required usable completed cycles'}
                elseif([double]$timing.arrivalCycleRatio -lt $MinimumRatio){'arrival horizon does not span enough empirical cycles'}
                else{'single-arrival candidate is unavailable'})
            timing=$timing
            forecast=$null
            arrival=$null
        }
    }

    $forecast=Invoke-SFMarketForecast -MarketKey $MarketKey -Cycles $Cycles -Observations $Observations -Market $Market -Destination $Destination -Travel $Travel -NowEpoch $NowEpoch -ScenarioCount $ScenarioCount -TargetQuantity $TargetQuantity -MarketValue $MarketValue -MarketFeePercent $MarketFeePercent -OneWaySeconds $OneWaySeconds -RandomSeed $RandomSeed -EnableAdaptiveGrid $false
    $arrivals=@($forecast.arrivals)
    if ($arrivals.Count -ne 1) {
        return [pscustomobject]@{ eligible=$false; reason='stochastic single-arrival forecast was unavailable'; timing=$timing; forecast=$forecast; arrival=$null }
    }

    return [pscustomobject]@{
        eligible=$true
        reason='arrival spans multiple empirical cycles; stochastic-v1.1 single-arrival renewal simulation is usable'
        timing=$timing
        forecast=$forecast
        arrival=$arrivals[0]
    }
}

if ($MultiCycleChanceBridgeSkipMain) { return }
if ($Now -le 0) { $Now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

$state=Read-SFStateKv $StateKvFile
$engine=Read-SFJson $EngineStateFile
if ($state.Count -eq 0 -or $null -eq $engine -or -not $engine.PSObject.Properties['observedMarkets']) { return }

$count=0
[void][int]::TryParse([string]$state['OpportunityCount'],[ref]$count)
$count=[Math]::Min(256,[Math]::Max(0,$count))
if ($count -le 0) { return }

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

for ($i=1; $i -le $count; $i++) {
    $prefix='Opportunity'+$i

    $state[$prefix+'MultiCycleChanceEligible']='0'
    $state[$prefix+'MultiCycleChanceProbability']='-1'
    $state[$prefix+'MultiCycleTargetProbability']='-1'
    $state[$prefix+'MultiCycleDutyCycleProbability']='-1'
    $state[$prefix+'MultiCycleMeanPeriodSeconds']='0'
    $state[$prefix+'MultiCycleMeanInStockSeconds']='0'
    $state[$prefix+'MultiCyclePeriodStdDevSeconds']='0'
    $state[$prefix+'MultiCycleArrivalCycleRatio']='0'
    $state[$prefix+'MultiCycleExpectedFullCycles']='0'
    $state[$prefix+'MultiCyclePhaseStdDevSeconds']='0'
    $state[$prefix+'MultiCyclePhaseStdDevCycles']='0'
    $state[$prefix+'MultiCycleSampleCount']='0'
    $state[$prefix+'MultiCycleEffectiveSampleSize']='0'
    $state[$prefix+'MultiCycleMaximumOrdinal']='0'
    $state[$prefix+'MultiCycleArrivalAt']='0'
    $state[$prefix+'MultiCycleGeneratedAt']=[long]$Now
    $state[$prefix+'MultiCycleSimulationCount']=$SimulationCount
    $state[$prefix+'MultiCycleModelVersion']='stochastic-v1.1'
    $state[$prefix+'MultiCycleReason']='not evaluated'

    $key=([string]$state[$prefix+'Key']).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($key)) { continue }
    $parts=@($key -split ':',2)
    if ($parts.Count -ne 2) { $state[$prefix+'MultiCycleReason']='invalid market key'; continue }
    $country=[string]$parts[0]
    $oneWay=Get-SFTravelSeconds -State $state -Country $country
    $travel=Get-MCArrivalCandidate -TravelState $travelState -MarketCountry $country -TravelDestinationCountry $travelDestination -TravelTimeLeft $travelLeft -OneWaySeconds $oneWay -NowEpoch $Now

    $cycles=@()
    if ($cycleMap.ContainsKey($key)) { $cycles=@($cycleMap[$key].ToArray()) }
    $observations=@()
    if ($observationMap.ContainsKey($key)) { $observations=@($observationMap[$key].ToArray()) }
    $market=Get-SFProperty $engine.observedMarkets $key
    if ($null -eq $market) { $state[$prefix+'MultiCycleReason']='observed market state is unavailable'; continue }
    $destination=Get-SFProperty (Get-SFProperty $engine 'destinations') $key
    if ($null -eq $destination) { $destination=[pscustomobject]@{} }

    $targetQuantity=1
    $quantityText=[string]$state[$prefix+'QuantityText']
    if ($quantityText -match '([1-9][0-9]*)') { $targetQuantity=[int]$Matches[1] }
    $marketValue=0L
    $fee=0
    [void][long]::TryParse([string]$state[$prefix+'MarketValueValue'],[ref]$marketValue)
    [void][int]::TryParse([string]$state[$prefix+'MarketFeePercent'],[ref]$fee)

    $marketSeed=Get-SFStableSeed -MarketKey $key -BaseSeed 1804289383
    $result=Get-MCMultiCycleChance -MarketKey $key -Cycles $cycles -Observations $observations -Market $market -Destination $destination -Travel $travel -NowEpoch $Now -ScenarioCount $SimulationCount -TargetQuantity $targetQuantity -MarketValue $marketValue -MarketFeePercent $fee -OneWaySeconds $oneWay -MinimumRatio $MinimumFlightCycleRatio -MinimumSamples $MinimumCycleSamples -RandomSeed $marketSeed
    $timing=$result.timing

    $state[$prefix+'MultiCycleDutyCycleProbability']=[double]$timing.dutyCycleProbability
    $state[$prefix+'MultiCycleMeanPeriodSeconds']=[long][Math]::Round([double]$timing.meanCycleSeconds)
    $state[$prefix+'MultiCycleMeanInStockSeconds']=[long][Math]::Round([double]$timing.meanInStockSeconds)
    $state[$prefix+'MultiCyclePeriodStdDevSeconds']=[long][Math]::Round([double]$timing.cycleStdDevSeconds)
    $state[$prefix+'MultiCycleArrivalCycleRatio']=[double]$timing.arrivalCycleRatio
    $state[$prefix+'MultiCycleExpectedFullCycles']=[int]$timing.expectedFullCycles
    $state[$prefix+'MultiCyclePhaseStdDevSeconds']=[long][Math]::Round([double]$timing.phaseStdDevSeconds)
    $state[$prefix+'MultiCyclePhaseStdDevCycles']=[double]$timing.phaseStdDevCycles
    $state[$prefix+'MultiCycleSampleCount']=[int]$timing.sampleCount
    $state[$prefix+'MultiCycleEffectiveSampleSize']=[double]$timing.effectiveSampleSize
    $state[$prefix+'MultiCycleReason']=[string]$result.reason

    if (-not [bool]$result.eligible) { continue }
    $arrival=$result.arrival
    $state[$prefix+'MultiCycleChanceEligible']='1'
    $state[$prefix+'MultiCycleChanceProbability']=[double]$arrival.pAnyStock
    $state[$prefix+'MultiCycleTargetProbability']=[double]$arrival.pTargetQty
    $state[$prefix+'MultiCycleMaximumOrdinal']=[int]$arrival.maximumCycleOrdinal
    $state[$prefix+'MultiCycleArrivalAt']=[long]$arrival.arrivalAt
}

$state['MultiCycleChanceBridgeGeneratedAt']=[long]$Now
$state['MultiCycleChanceBridgeModelVersion']='stochastic-v1.1'
$state['MultiCycleChanceBridgeSimulationCount']=$SimulationCount
$state['MultiCycleChanceBridgeMinimumRatio']=$MinimumFlightCycleRatio
Write-MCStateKvAtomic -Values $state -Path $StateKvFile
