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
$PendingCycleFile = Join-Path $RuntimeDir 'cycles.pending.jsonl'
$SeedCycleFile = Join-Path $SeedDir 'cycles.jsonl'
$RuntimeObservationFile = Join-Path $RuntimeDir 'observations.jsonl'
$PendingObservationFile = Join-Path $RuntimeDir 'observations.pending.jsonl'
$AtomicFileScript = Join-Path $PSScriptRoot 'AtomicFile.ps1'
if (-not (Test-Path -LiteralPath $AtomicFileScript)) { throw 'AtomicFile.ps1 is required for shared depletion-history reads.' }
. $AtomicFileScript

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
        [long]$ObservationAt = 0L,
        [long]$ArrivalAt
    )
    $usable=@(Get-StableWindowUsableCycles -Cycles $Cycles)
    if ($usable.Count -eq 0 -or $ActiveRestockAt -le 0 -or $ArrivalAt -lt $ActiveRestockAt) { return -1.0 }

    # The current cycle is factually still in stock at ObservationAt. Estimate
    # survival to arrival conditional on having already survived that long; the old
    # unconditional fraction could fall to 0% even while live stock remained high.
    $observedAt=if($ObservationAt -gt $ActiveRestockAt){$ObservationAt}else{$ActiveRestockAt}
    $observedAge=[Math]::Max(0L,$observedAt-$ActiveRestockAt)
    $arrivalAge=[Math]::Max(0L,$ArrivalAt-$ActiveRestockAt)
    $survivors=@($usable|Where-Object{[long]$_.availabilitySeconds -gt $observedAge})
    if($survivors.Count -eq 0){return -1.0}
    $hits=@($survivors|Where-Object{[long]$_.availabilitySeconds -gt $arrivalAge}).Count
    return ($hits/[double]$survivors.Count)
}

function Get-LiveDepletionArrivalProbability {
    param(
        [long]$CurrentStock,
        [long]$SourceTimestamp,
        [object[]]$Observations,
        [long]$ArrivalAt,
        [long]$NowEpoch,
        [long]$LiveMaximumAgeSeconds=300L,
        [int]$MinimumSamples=3,
        [long]$MinimumEvidenceSpanSeconds=600L,
        [long]$MaximumDepletionIntervalSeconds=600L
    )

    $sourceAt=if($SourceTimestamp -gt 0){[Math]::Min($SourceTimestamp,$NowEpoch)}else{0L}
    $sourceFresh=($sourceAt -gt 0 -and ($NowEpoch-$sourceAt) -le $LiveMaximumAgeSeconds)
    if(-not $sourceFresh -or $CurrentStock -le 0 -or $ArrivalAt -le $sourceAt){
        return [pscustomobject]@{eligible=$false;probability=-1.0;sampleCount=0;evidenceSpanSeconds=0L;medianRunwaySeconds=0L;reason='fresh positive stock and a future arrival are required'}
    }

    $rows=@($Observations|Sort-Object{
        $at=[long](Get-WindowProperty $_ 'sourceTimestamp')
        if($at -le 0){$at=[long](Get-WindowProperty $_ 'timestamp')}
        $at
    })
    $rates=New-Object System.Collections.Generic.List[object]
    $previousStock=$null
    foreach($row in $rows){
        $at=[long](Get-WindowProperty $row 'sourceTimestamp')
        if($at -le 0){$at=[long](Get-WindowProperty $row 'timestamp')}
        if($at -le 0 -or $at -gt ($sourceAt+60L)){continue}
        $stock=[long](Get-WindowProperty $row 'stock')
        $transitionGap=[long](Get-WindowProperty $row 'transitionGapSeconds')
        $reset=(
            $stock -le 0 -or
            ($null -ne $previousStock -and $previousStock -gt 0 -and $stock -gt $previousStock) -or
            $transitionGap -gt $MaximumDepletionIntervalSeconds
        )
        if($reset){$rates.Clear()}

        $kind=([string](Get-WindowProperty $row 'depletionEvidence')).Trim().ToLowerInvariant()
        $censored=[bool](Get-WindowProperty $row 'depletionCensored')
        $interval=[long](Get-WindowProperty $row 'depletionIntervalSeconds')
        $units=[long](Get-WindowProperty $row 'depletionUnits')
        if(
            $stock -gt 0 -and
            $kind -eq 'observed_nonzero' -and
            -not $censored -and
            $interval -ge 10L -and
            $interval -le $MaximumDepletionIntervalSeconds -and
            $units -gt 0
        ){
            $rates.Add([pscustomobject]@{at=$at;unitsPerSecond=($units/[double]$interval)})
        }
        $previousStock=$stock
    }

    if($rates.Count -lt $MinimumSamples){
        return [pscustomobject]@{eligible=$false;probability=-1.0;sampleCount=$rates.Count;evidenceSpanSeconds=0L;medianRunwaySeconds=0L;reason='too few uncensored live depletion samples'}
    }
    $firstAt=[long](@($rates.ToArray()|Sort-Object at|Select-Object -First 1)[0].at)
    $lastAt=[long](@($rates.ToArray()|Sort-Object at|Select-Object -Last 1)[0].at)
    $span=[Math]::Max(0L,$lastAt-$firstAt)
    if($span -lt $MinimumEvidenceSpanSeconds){
        return [pscustomobject]@{eligible=$false;probability=-1.0;sampleCount=$rates.Count;evidenceSpanSeconds=$span;medianRunwaySeconds=0L;reason='live depletion evidence does not yet span enough time'}
    }

    $horizon=[Math]::Max(0L,$ArrivalAt-$sourceAt)
    $runways=New-Object System.Collections.Generic.List[long]
    $hits=0
    foreach($sample in $rates.ToArray()){
        $rate=[double]$sample.unitsPerSecond
        if($rate -le 0){continue}
        $runway=[long][Math]::Ceiling($CurrentStock/$rate)
        $runways.Add($runway)
        if($runway -gt $horizon){$hits++}
    }
    if($runways.Count -lt $MinimumSamples){
        return [pscustomobject]@{eligible=$false;probability=-1.0;sampleCount=$runways.Count;evidenceSpanSeconds=$span;medianRunwaySeconds=0L;reason='too few usable live depletion rates'}
    }
    $ordered=[long[]]@($runways.ToArray()|Sort-Object)
    $mid=[int][Math]::Floor($ordered.Count/2.0)
    $medianRunway=if(($ordered.Count%2)-eq 1){[long]$ordered[$mid]}else{[long][Math]::Round(([double]$ordered[$mid-1]+[double]$ordered[$mid])/2.0)}
    return [pscustomobject]@{
        eligible=$true
        probability=($hits/[double]$runways.Count)
        sampleCount=$runways.Count
        evidenceSpanSeconds=$span
        medianRunwaySeconds=$medianRunway
        reason='arrival probability from uncensored live current-run depletion rates'
    }
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

function Read-WindowObservationsForKeys {
    param([string]$Path,[hashtable]$Wanted,[long]$Cutoff)
    $map=@{}
    if ($null -eq $Wanted -or $Wanted.Count -eq 0 -or -not (Test-Path -LiteralPath $Path)) { return $map }
    $reader=$null
    try {
        $reader=Open-TravelAssistantSharedTextReader -Path $Path
        while (($line=$reader.ReadLine()) -ne $null) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $key=Get-WindowCycleLineKey -Line $line
            if ([string]::IsNullOrWhiteSpace($key) -or -not $Wanted.ContainsKey($key)) { continue }
            try { $row=$line | ConvertFrom-Json } catch { continue }
            $at=[long](Get-WindowProperty $row 'sourceTimestamp')
            if ($at -le 0) { $at=[long](Get-WindowProperty $row 'timestamp') }
            if ($at -lt $Cutoff) { continue }
            if (-not $map.ContainsKey($key)) { $map[$key]=New-Object System.Collections.Generic.List[object] }
            $map[$key].Add($row)
        }
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
    }
    return $map
}

function Get-CurrentStockSafetyProjection {
    param(
        [long]$CurrentStock,
        [long]$SourceTimestamp,
        [object[]]$Observations,
        [long]$EarliestArrivalAt,
        [long]$NowEpoch,
        [long]$KnownSelloutEstimateAt=0L,
        [long]$LiveMaximumAgeSeconds=300L,
        [int]$MinimumDepletionSamples=3,
        [long]$MinimumEvidenceSpanSeconds=600L,
        [long]$MaximumDepletionIntervalSeconds=600L,
        [double]$RateGuardMultiplier=1.5,
        [double]$MinimumGuardedUnitsPerHour=60.0,
        [double]$MinimumRunwayToArrivalRatio=2.0,
        [long]$MinimumArrivalMarginSeconds=1800L,
        [long]$MinimumFarHorizonSeconds=21600L,
        [double]$FarHorizonArrivalMultiplier=2.0,
        [int]$MinimumLowDepletionObservationSamples=3,
        [long]$MinimumLowDepletionEvidenceSpanSeconds=900L,
        [double]$LowDepletionNetRateMultiplier=2.0
    )

    $sourceAt=if($SourceTimestamp -gt 0){[Math]::Min($SourceTimestamp,$NowEpoch)}else{0L}
    $sourceFresh=($sourceAt -gt 0 -and ($NowEpoch-$sourceAt) -le $LiveMaximumAgeSeconds)
    $arrivalHorizon=[Math]::Max(0L,$EarliestArrivalAt-$sourceAt)
    $adaptiveHoldHorizon=[long][Math]::Ceiling([Math]::Max(
        [double][Math]::Max(0L,$MinimumFarHorizonSeconds),
        [double]$arrivalHorizon*[Math]::Max(1.0,$FarHorizonArrivalMultiplier)
    ))
    $requiredRunway=[long][Math]::Ceiling([Math]::Max(
        $arrivalHorizon*[Math]::Max(1.0,$MinimumRunwayToArrivalRatio),
        $arrivalHorizon+[Math]::Max(0L,$MinimumArrivalMarginSeconds)
    ))

    if (-not $sourceFresh -or $CurrentStock -le 0 -or $EarliestArrivalAt -le $sourceAt) {
        return [pscustomobject]@{
            eligible=$false; mode='none'; reason='fresh positive stock and a future arrival are required'
            sampleCount=0; evidenceSpanSeconds=0L; guardedUnitsPerHour=0.0; percentileUnitsPerHour=0.0
            runwaySeconds=0L; arrivalHorizonSeconds=$arrivalHorizon; arrivalMarginSeconds=0L
            selloutEstimateAt=0L; minimumHoldHorizonSeconds=$adaptiveHoldHorizon
        }
    }

    # If another verified live projection already places sellout far beyond both
    # the flight and a six-hour floor, that alone is useful low-authority fallback
    # evidence. It must never supersede a normal actionable forecast.
    if(
        $KnownSelloutEstimateAt -gt $sourceAt -and
        ($KnownSelloutEstimateAt-$sourceAt) -ge $adaptiveHoldHorizon -and
        $KnownSelloutEstimateAt -gt $EarliestArrivalAt
    ){
        $runway=[long]($KnownSelloutEstimateAt-$sourceAt)
        return [pscustomobject]@{
            eligible=$true; mode='far-sellout'
            reason='verified current stock has a live sellout estimate beyond the adaptive hold horizon'
            sampleCount=0; evidenceSpanSeconds=0L; guardedUnitsPerHour=0.0; percentileUnitsPerHour=0.0
            runwaySeconds=$runway; arrivalHorizonSeconds=$arrivalHorizon
            arrivalMarginSeconds=[long][Math]::Max(0L,$runway-$arrivalHorizon)
            selloutEstimateAt=[long]$KnownSelloutEstimateAt; minimumHoldHorizonSeconds=$adaptiveHoldHorizon
        }
    }

    $rows=@($Observations | Sort-Object {
        $at=[long](Get-WindowProperty $_ 'sourceTimestamp')
        if($at -le 0){$at=[long](Get-WindowProperty $_ 'timestamp')}
        $at
    })
    $rates=New-Object System.Collections.Generic.List[object]
    $runSamples=New-Object System.Collections.Generic.List[object]
    $previousStock=$null
    foreach($row in $rows){
        $at=[long](Get-WindowProperty $row 'sourceTimestamp')
        if($at -le 0){$at=[long](Get-WindowProperty $row 'timestamp')}
        if($at -le 0 -or $at -gt ($sourceAt+60L)){continue}
        $stock=[long](Get-WindowProperty $row 'stock')
        $transitionGap=[long](Get-WindowProperty $row 'transitionGapSeconds')

        # A zero state, observed replenishment, or a long provider gap begins a new
        # run. Neither positive depletion nor flat-stock evidence may cross it.
        $reset=(
            $stock -le 0 -or
            ($null -ne $previousStock -and $previousStock -gt 0 -and $stock -gt $previousStock) -or
            $transitionGap -gt $MaximumDepletionIntervalSeconds
        )
        if($reset){
            $rates.Clear()
            $runSamples.Clear()
        }

        if($stock -gt 0){
            $runSamples.Add([pscustomobject]@{at=$at;stock=$stock})
        }

        $kind=([string](Get-WindowProperty $row 'depletionEvidence')).Trim().ToLowerInvariant()
        $censored=[bool](Get-WindowProperty $row 'depletionCensored')
        $interval=[long](Get-WindowProperty $row 'depletionIntervalSeconds')
        $units=[long](Get-WindowProperty $row 'depletionUnits')
        if(
            $stock -gt 0 -and
            $kind -eq 'observed_nonzero' -and
            -not $censored -and
            $interval -ge 10L -and
            $interval -le $MaximumDepletionIntervalSeconds -and
            $units -gt 0
        ){
            $rates.Add([pscustomobject]@{at=$at;unitsPerSecond=($units/[double]$interval)})
        }
        $previousStock=$stock
    }

    # First retain the existing strict path: three uncensored positive-depletion
    # intervals spanning ten minutes, guarded by p90 * 1.5 and a 60 units/hour floor.
    $sampleCount=$rates.Count
    if($sampleCount -ge $MinimumDepletionSamples){
        $ordered=@($rates.ToArray() | Sort-Object unitsPerSecond)
        $firstAt=[long](@($rates.ToArray() | Sort-Object at | Select-Object -First 1)[0].at)
        $lastAt=[long](@($rates.ToArray() | Sort-Object at | Select-Object -Last 1)[0].at)
        $span=[Math]::Max(0L,$lastAt-$firstAt)
        if($span -ge $MinimumEvidenceSpanSeconds){
            $rank=[int][Math]::Ceiling(0.90*$ordered.Count)-1
            $rank=[Math]::Max(0,[Math]::Min($ordered.Count-1,$rank))
            $percentileRate=[double]$ordered[$rank].unitsPerSecond
            $guardedRate=[Math]::Max($MinimumGuardedUnitsPerHour/3600.0,$percentileRate*[Math]::Max(1.0,$RateGuardMultiplier))
            if($guardedRate -gt 0){
                $runway=[long][Math]::Ceiling($CurrentStock/$guardedRate)
                $eligible=($runway -ge $requiredRunway)
                $selloutAt=$sourceAt+$runway
                return [pscustomobject]@{
                    eligible=[bool]$eligible; mode=$(if($eligible){'depletion-runway'}else{'none'})
                    reason=$(if($eligible){'conservative current-stock runway comfortably exceeds time to arrival'}else{'conservative current-stock runway is not large enough for the safety gate'})
                    sampleCount=$sampleCount; evidenceSpanSeconds=[long]$span
                    percentileUnitsPerHour=[Math]::Round($percentileRate*3600.0,3)
                    guardedUnitsPerHour=[Math]::Round($guardedRate*3600.0,3)
                    runwaySeconds=[long]$runway; arrivalHorizonSeconds=[long]$arrivalHorizon
                    arrivalMarginSeconds=[long][Math]::Max(0L,$runway-$arrivalHorizon)
                    selloutEstimateAt=[long]$selloutAt; minimumHoldHorizonSeconds=$adaptiveHoldHorizon
                }
            }
        }
    }

    # Low/flat depletion can make an exact OOS regression numerically meaningless.
    # Treat a long uninterrupted positive-stock run as fallback evidence only after
    # three observations span 15 minutes. Stress it with the worst of:
    #   * 60 units/hour,
    #   * 2x net run depletion,
    #   * 1.5x the largest observed uncensored burst.
    # This branch deliberately does not publish a precise sellout timestamp.
    $runCount=$runSamples.Count
    if($runCount -ge $MinimumLowDepletionObservationSamples){
        $orderedRun=@($runSamples.ToArray() | Sort-Object at)
        $runFirstAt=[long]$orderedRun[0].at
        $runLastAt=[long]$orderedRun[$orderedRun.Count-1].at
        $runSpan=[Math]::Max(0L,$runLastAt-$runFirstAt)
        if($runSpan -ge $MinimumLowDepletionEvidenceSpanSeconds){
            $firstStock=[long]$orderedRun[0].stock
            $lastStock=[long]$orderedRun[$orderedRun.Count-1].stock
            $netUnits=[Math]::Max(0L,$firstStock-$lastStock)
            $netRatePerHour=if($runSpan -gt 0){($netUnits*3600.0)/$runSpan}else{0.0}
            $burstRatePerHour=0.0
            foreach($sample in $rates.ToArray()){
                $candidate=[double]$sample.unitsPerSecond*3600.0
                if($candidate -gt $burstRatePerHour){$burstRatePerHour=$candidate}
            }
            $stressRatePerHour=[Math]::Max(
                $MinimumGuardedUnitsPerHour,
                [Math]::Max(
                    $netRatePerHour*[Math]::Max(1.0,$LowDepletionNetRateMultiplier),
                    $burstRatePerHour*[Math]::Max(1.0,$RateGuardMultiplier)
                )
            )
            if($stressRatePerHour -gt 0){
                $stressRunway=[long][Math]::Ceiling(($CurrentStock*3600.0)/$stressRatePerHour)
                $eligible=(
                    $stressRunway -ge $requiredRunway -and
                    $stressRunway -ge $adaptiveHoldHorizon
                )
                return [pscustomobject]@{
                    eligible=[bool]$eligible; mode=$(if($eligible){'low-depletion-hold'}else{'none'})
                    reason=$(if($eligible){'verified positive stock is holding under a stress-tested low-depletion envelope'}else{'low-depletion evidence exists but stress-tested runway is not long enough'})
                    sampleCount=$runCount; evidenceSpanSeconds=[long]$runSpan
                    percentileUnitsPerHour=[Math]::Round($netRatePerHour,3)
                    guardedUnitsPerHour=[Math]::Round($stressRatePerHour,3)
                    runwaySeconds=[long]$stressRunway; arrivalHorizonSeconds=[long]$arrivalHorizon
                    arrivalMarginSeconds=[long][Math]::Max(0L,$stressRunway-$arrivalHorizon)
                    selloutEstimateAt=0L; minimumHoldHorizonSeconds=$adaptiveHoldHorizon
                }
            }
        }
    }

    $reason=if($sampleCount -lt $MinimumDepletionSamples){
        'too few uncensored depletion samples and insufficient low-depletion hold evidence'
    }else{
        'depletion evidence does not yet support a safe fallback'
    }
    return [pscustomobject]@{
        eligible=$false; mode='none'; reason=$reason
        sampleCount=$sampleCount; evidenceSpanSeconds=0L; guardedUnitsPerHour=0.0; percentileUnitsPerHour=0.0
        runwaySeconds=0L; arrivalHorizonSeconds=$arrivalHorizon; arrivalMarginSeconds=0L
        selloutEstimateAt=0L; minimumHoldHorizonSeconds=$adaptiveHoldHorizon
    }
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

function Get-StableRecurringProbabilityAt {
    param([object]$Model,[long]$ArrivalAt)
    if($null -eq $Model -or [int](Get-WindowProperty $Model 'sampleCount') -le 0 -or $ArrivalAt -le 0){return -1.0}
    $groups=@(Get-WindowProperty $Model 'groups')
    if($groups.Count -eq 0){return -1.0}
    $maxSupportedAt=0L
    foreach($group in $groups){
        $end=[long](Get-WindowProperty $group 'lateSelloutAt')
        if($end -gt $maxSupportedAt){$maxSupportedAt=$end}
    }
    # Legacy geometry intentionally ends at the immediately next cycle. Do not
    # call a later multi-cycle arrival a known 0% merely because it lies beyond
    # the supported legacy horizon.
    if($maxSupportedAt -le 0 -or $ArrivalAt -gt $maxSupportedAt){return -1.0}
    foreach($segment in @(Get-WindowProperty $Model 'segments')){
        $start=[long](Get-WindowProperty $segment 'startAt')
        $end=[long](Get-WindowProperty $segment 'endAt')
        if($ArrivalAt -ge $start -and $ArrivalAt -lt $end){
            return [Math]::Max(0.0,[Math]::Min(1.0,[double](Get-WindowProperty $segment 'probability')))
        }
    }
    return 0.0
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
    if ($value -match '^WP2:[^#]*#PV[01]#(.*)
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
    if([string]::IsNullOrWhiteSpace($key)){continue}
    if($forecastMode -ne 'sleeping_oos'){
        $wanted[$key]=$true
        continue
    }
    # Sleeping OoS is only a performance hint. If live observed phase has already
    # advanced to a restock, wake this market immediately and load full evidence.
    $phaseInfo=Get-WindowObservedPhase -Engine $engine -Key $key
    if(-not[bool]$phaseInfo.unresolvedOos){$wanted[$key]=$true}
}
$cycleMap=Read-WindowCyclesForKeys -Paths @($SeedCycleFile,$RuntimeCycleFile,$PendingCycleFile) -Wanted $wanted
$observationMap=Read-WindowObservationsForKeys -Path $RuntimeObservationFile -Wanted $wanted -Cutoff ($Now-28800L)
$pendingObservationMap=Read-WindowObservationsForKeys -Path $PendingObservationFile -Wanted $wanted -Cutoff ($Now-28800L)
foreach($pendingKey in @($pendingObservationMap.Keys)){
    if(-not $observationMap.ContainsKey($pendingKey)){$observationMap[$pendingKey]=New-Object System.Collections.Generic.List[object]}
    $seenObservation=@{}
    foreach($existing in @($observationMap[$pendingKey].ToArray())){
        $at=[long](Get-WindowProperty $existing 'sourceTimestamp');if($at -le 0){$at=[long](Get-WindowProperty $existing 'timestamp')}
        $seenObservation[([string]$at+':'+[string][long](Get-WindowProperty $existing 'stock'))]=$true
    }
    foreach($pending in @($pendingObservationMap[$pendingKey].ToArray())){
        $at=[long](Get-WindowProperty $pending 'sourceTimestamp');if($at -le 0){$at=[long](Get-WindowProperty $pending 'timestamp')}
        $identity=([string]$at+':'+[string][long](Get-WindowProperty $pending 'stock'))
        if(-not$seenObservation.ContainsKey($identity)){$observationMap[$pendingKey].Add($pending);$seenObservation[$identity]=$true}
    }
}
foreach($observationKey in @($observationMap.Keys)){
    $filtered=@(Get-PlausibilityFilteredStockObservations -Rows @($observationMap[$observationKey].ToArray()) -ExpectedPollIntervalSeconds 60)
    $list=New-Object System.Collections.Generic.List[object]
    foreach($row in $filtered){$list.Add($row)}
    $observationMap[$observationKey]=$list
}
$travelState=([string]$state['TravelState']).Trim().ToLowerInvariant()
$destinationCountry=([string]$state['TravelDestinationCountryId']).Trim().ToLowerInvariant()
$travelLeft=0L
[void][long]::TryParse([string]$state['TravelTimeLeft'],[ref]$travelLeft)

for ($i=1; $i -le $count; $i++) {
    $prefix='Opportunity'+$i
    $key=[string]$state[$prefix+'Key']
    if ([string]::IsNullOrWhiteSpace($key)) { continue }

    # Every field owned by the authoritative legacy window stage is initialized
    # for this generation before any fast-path/continue branch. This prevents a
    # previous row at the same numeric index from surviving into the new snapshot.
    $state[$prefix+'CurrentStock']='0'
    $state[$prefix+'StockEvidenceAt']='0'
    $state[$prefix+'ActiveRestockAt']='0'
    $state[$prefix+'ActiveSelloutEstimateAt']='0'
    $state[$prefix+'NextRestockEstimateAt']='0'
    $state[$prefix+'LastObservedOosAt']='0'
    $state[$prefix+'MedianRestockDelaySeconds']='0'
    $state[$prefix+'LiveCycleProjectionMode']='none'
    $state[$prefix+'WindowDataQuality']='collecting'
    $state[$prefix+'WindowDataQualityReason']='window evidence was not evaluated'
    $state[$prefix+'CurrentCycleReachable']='0'
    $state[$prefix+'CurrentCycleLeaveDeadlineAt']='0'
    $state[$prefix+'CurrentCycleSafetyMarginSeconds']='0'
    $state[$prefix+'NextCycleOrdinal']='0'
    $state[$prefix+'WindowMedianPeriodSeconds']='0'
    $state[$prefix+'ImmediateArrivalAt']='0'
    $state[$prefix+'ImmediateArrivalProbabilityValue']='-1'
    $state[$prefix+'ImmediateArrivalProbabilitySource']='unknown'
    $state[$prefix+'CurrentCycleLiveProbability']='-1'
    $state[$prefix+'CurrentCycleLiveProbabilitySampleCount']='0'
    $state[$prefix+'CurrentCycleLiveProbabilityEvidenceSpanSeconds']='0'
    $state[$prefix+'CurrentCycleLiveProbabilityMedianRunwaySeconds']='0'
    $state[$prefix+'CurrentStockSafetyEligible']='0'
    $state[$prefix+'CurrentStockSafetyMode']='none'
    $state[$prefix+'CurrentStockSafetyMinimumHoldHorizonSeconds']='0'
    $state[$prefix+'CurrentStockSafetySampleCount']='0'
    $state[$prefix+'CurrentStockSafetyEvidenceSpanSeconds']='0'
    $state[$prefix+'CurrentStockSafetyPercentileUnitsPerHour']='0'
    $state[$prefix+'CurrentStockSafetyGuardedUnitsPerHour']='0'
    $state[$prefix+'CurrentStockSafetyRunwaySeconds']='0'
    $state[$prefix+'CurrentStockSafetyArrivalHorizonSeconds']='0'
    $state[$prefix+'CurrentStockSafetyMarginSeconds']='0'
    $state[$prefix+'CurrentStockSafetySelloutEstimateAt']='0'
    $state[$prefix+'CurrentStockSafetyReason']=''
    $forecastMode=([string]$state[$prefix+'ForecastMode']).Trim().ToLowerInvariant()
    $phaseInfo=Get-WindowObservedPhase -Engine $engine -Key $key
    $market=$phaseInfo.market
    $destinationState=$phaseInfo.destinationState
    $observedStock=[long]$phaseInfo.observedStock
    $sourceTimestamp=[long]$phaseInfo.sourceTimestamp

    if ($forecastMode -eq 'sleeping_oos' -and [bool]$phaseInfo.unresolvedOos) {
        # OpportunityState published a cheap OoS estimate and the OoS is still the
        # latest verified phase. Keep the low-cost path without loading cycle data.
        $state[$prefix+'CurrentStock']='0'
        $state[$prefix+'StockEvidenceAt']=$sourceTimestamp
        $state[$prefix+'ActiveRestockAt']=[long]$phaseInfo.activeRestockAt
        $state[$prefix+'LastObservedOosAt']=[long]$phaseInfo.lastSellOutAt
        $state[$prefix+'WindowDataQuality']='ready'
        $state[$prefix+'WindowDataQualityReason']=''
        $state[$prefix+'CurrentCycleReachable']='0'
        $state[$prefix+'CurrentCycleLeaveDeadlineAt']='0'
        $state[$prefix+'CurrentCycleSafetyMarginSeconds']='0'
        continue
    }
    if($forecastMode -eq 'sleeping_oos'){
        # Defensive same-generation repair: a later observed restock invalidates the
        # old OoS countdown even if OpportunityState and this pass straddle a refresh.
        $state[$prefix+'ForecastMode']='phase_invalidated'
        $forecastMode='phase_invalidated'
    }

    $countryId=($key -split ':',2)[0]
    $cycles=@()
    if ($cycleMap.ContainsKey($key)) { $cycles=@($cycleMap[$key].ToArray()) }
    $forecastEligibleCycles=@($cycles | Where-Object { Test-CycleForecastBoundaryEvidence -Cycle $_ -Purpose Forecast })
    $stock=$observedStock
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
    # LastObservedOosAt means an unresolved current OoS phase, not merely the
    # historical timestamp of the most recent sellout. A later restock supersedes it.
    $lastObservedOosAt=if([bool]$phaseInfo.unresolvedOos){[long]$phaseInfo.lastSellOutAt}else{0L}
    $state[$prefix+'LastObservedOosAt']=$lastObservedOosAt
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
        if($observedStock -gt 0 -and $sourceTimestamp -gt [long]$phaseInfo.lastSellOutAt){
            $collectingReason='live stock source is stale after a later observed restock; preceding OoS timing is suppressed'
        } else {
            $collectingReason='live stock source is stale'
        }
    } elseif ($stock -gt 0) {
        $activeCycle=Get-WindowProperty $destinationState 'activeCycle'
        $restockAt=if ($null -ne $activeCycle) { [long](Get-WindowProperty $activeCycle 'restockAt') } else { 0L }
        $restockQuality=if ($null -ne $activeCycle) { [string](Get-WindowProperty $activeCycle 'restockBoundaryQuality') } else { '' }
        if ($restockAt -le 0 -or -not (Test-WindowBoundaryQuality -Quality $restockQuality)) {
            $qualityLabel=if([string]::IsNullOrWhiteSpace($restockQuality)){'missing'}else{$restockQuality}
            $collectingReason=('current restock boundary was not observed or recovered (restock {0}, quality {1})' -f $restockAt,$qualityLabel)
        } elseif ([long]$liveProjection.activeSelloutEstimateAt -le 0) {
            $restockQuantity=if($null -ne $activeCycle){[long](Get-WindowProperty $activeCycle 'restockQuantity')}else{0L}
            $collectingReason=('current sellout cannot yet be estimated (mode {0}; restock qty {1}; raw cycles {2}, eligible {3})' -f [string]$liveProjection.mode,$restockQuantity,$cycles.Count,$forecastEligibleCycles.Count)
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
    $state[$prefix+'ImmediateArrivalAt']=[long]$earliestArrival
    $state[$prefix+'CurrentCycleReachable']='0'
    $state[$prefix+'CurrentCycleLeaveDeadlineAt']='0'
    $state[$prefix+'CurrentCycleSafetyMarginSeconds']='0'
    $state[$prefix+'NextCycleOrdinal']=if ($stock -gt 0) { '1' } else { '0' }

    # Compute direct current-stock fallback telemetry for every fresh positive-stock
    # market. Normal current-cycle / Safe-Best / multi-cycle logic still owns the
    # card whenever it can produce actionable guidance; this evidence is consumed
    # only by otherwise non-informative presentation states.
    $safety=$null
    if ($stock -gt 0) {
        $marketObservations=@()
        if($observationMap.ContainsKey($key)){$marketObservations=@($observationMap[$key].ToArray())}
        $safety=Get-CurrentStockSafetyProjection -CurrentStock $stock -SourceTimestamp $sourceTimestamp -Observations $marketObservations -EarliestArrivalAt $earliestArrival -NowEpoch $Now -KnownSelloutEstimateAt ([long]$liveProjection.activeSelloutEstimateAt)
        $state[$prefix+'CurrentStockSafetyMode']=[string](Get-WindowProperty $safety 'mode')
        $state[$prefix+'CurrentStockSafetyMinimumHoldHorizonSeconds']=[long](Get-WindowProperty $safety 'minimumHoldHorizonSeconds')
        $state[$prefix+'CurrentStockSafetySampleCount']=[int](Get-WindowProperty $safety 'sampleCount')
        $state[$prefix+'CurrentStockSafetyEvidenceSpanSeconds']=[long](Get-WindowProperty $safety 'evidenceSpanSeconds')
        $state[$prefix+'CurrentStockSafetyPercentileUnitsPerHour']=[double](Get-WindowProperty $safety 'percentileUnitsPerHour')
        $state[$prefix+'CurrentStockSafetyGuardedUnitsPerHour']=[double](Get-WindowProperty $safety 'guardedUnitsPerHour')
        $state[$prefix+'CurrentStockSafetyRunwaySeconds']=[long](Get-WindowProperty $safety 'runwaySeconds')
        $state[$prefix+'CurrentStockSafetyArrivalHorizonSeconds']=[long](Get-WindowProperty $safety 'arrivalHorizonSeconds')
        $state[$prefix+'CurrentStockSafetyMarginSeconds']=[long](Get-WindowProperty $safety 'arrivalMarginSeconds')
        $state[$prefix+'CurrentStockSafetySelloutEstimateAt']=[long](Get-WindowProperty $safety 'selloutEstimateAt')
        $state[$prefix+'CurrentStockSafetyReason']=[string](Get-WindowProperty $safety 'reason')
        if([bool](Get-WindowProperty $safety 'eligible')){$state[$prefix+'CurrentStockSafetyEligible']='1'}
    }

    # Only an already-non-informative producer state may be replaced directly here.
    # A ready model continues below even when fallback telemetry is eligible.
    if (
        [string]$state[$prefix+'WindowDataQuality'] -eq 'collecting' -and
        $null -ne $safety -and
        [bool](Get-WindowProperty $safety 'eligible')
    ) {
        $state[$prefix+'WindowDataQuality']='current_stock_safe'
        $state[$prefix+'WindowDataQualityReason']='verified current stock provides low-authority travel guidance while the main window model is non-informative'
        $state[$prefix+'WindowStartAt']=[Math]::Max($Now,$earliestDeparture)
        $state[$prefix+'WindowText']='STOCK HOLDING'
        $state[$prefix+'ChanceText']=''
        $state[$prefix+'ProbabilityValue']='-1'
        continue
    }

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
        $marketObservations=@()
        if($observationMap.ContainsKey($key)){$marketObservations=@($observationMap[$key].ToArray())}
        $liveProbability=Get-LiveDepletionArrivalProbability -CurrentStock $stock -SourceTimestamp $sourceTimestamp -Observations $marketObservations -ArrivalAt $earliestArrival -NowEpoch $Now
        $state[$prefix+'CurrentCycleLiveProbability']=[double]$liveProbability.probability
        $state[$prefix+'CurrentCycleLiveProbabilitySampleCount']=[int]$liveProbability.sampleCount
        $state[$prefix+'CurrentCycleLiveProbabilityEvidenceSpanSeconds']=[long]$liveProbability.evidenceSpanSeconds
        $state[$prefix+'CurrentCycleLiveProbabilityMedianRunwaySeconds']=[long]$liveProbability.medianRunwaySeconds

        $currentProbability=-1.0
        $currentProbabilitySource='unknown'
        if([bool]$liveProbability.eligible){
            $currentProbability=[double]$liveProbability.probability
            $currentProbabilitySource='current_cycle_live_depletion'
        }else{
            $currentProbability=Get-StableCurrentCycleArrivalProbability -Cycles $cycles -ActiveRestockAt ([long]$liveProjection.activeRestockAt) -ObservationAt $sourceTimestamp -ArrivalAt $earliestArrival
            if($currentProbability -ge 0){$currentProbabilitySource='current_cycle_conditional_survival'}
        }

        if ($currentProbability -ge 0) {
            $state[$prefix+'ProbabilityValue']=(Convert-WindowProbabilityText ([double]$currentProbability))
            $state[$prefix+'ChanceText']=('{0:N0}%' -f (100.0*[double]$currentProbability))
            $state[$prefix+'ImmediateArrivalProbabilityValue']=(Convert-WindowProbabilityText ([double]$currentProbability))
            $state[$prefix+'ImmediateArrivalProbabilitySource']=$currentProbabilitySource
        }else{
            $state[$prefix+'ProbabilityValue']='-1'
            $state[$prefix+'ChanceText']=''
            $state[$prefix+'ImmediateArrivalProbabilityValue']='-1'
            $state[$prefix+'ImmediateArrivalProbabilitySource']='current_cycle_insufficient_live_or_conditional_evidence'
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
        $state[$prefix+'WindowDataQualityReason']=('no forecast-eligible completed cycles are available for the next restock (raw cycles {0}, eligible {1})' -f $cycles.Count,$forecastEligibleCycles.Count)
        $state[$prefix+'WindowStartAt']='0'
        $state[$prefix+'WindowText']='Collecting Data: See Weav3r'
        $state[$prefix+'ChanceText']=''
        $state[$prefix+'ProbabilityValue']='-1'
        continue
    }

    $immediateProbability=Get-StableRecurringProbabilityAt -Model $model -ArrivalAt $earliestArrival
    if($immediateProbability -ge 0){
        $state[$prefix+'ImmediateArrivalProbabilityValue']=(Convert-WindowProbabilityText ([double]$immediateProbability))
        $state[$prefix+'ImmediateArrivalProbabilitySource']='legacy_current_or_next_cycle'
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
$state['LegacyWindowPlanAuthority']='WindowPlan'
$state['LegacyWindowPlanGeneratedAt']=[long]$Now
Write-WindowStateKvAtomic -Values $state -Path $StateKvFile
) { return [string]$Matches[1] }
    if ($value -match '^PV[01]#(.*)
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
$cycleMap=Read-WindowCyclesForKeys -Paths @($SeedCycleFile,$RuntimeCycleFile,$PendingCycleFile) -Wanted $wanted
$observationMap=Read-WindowObservationsForKeys -Path $RuntimeObservationFile -Wanted $wanted -Cutoff ($Now-28800L)
$pendingObservationMap=Read-WindowObservationsForKeys -Path $PendingObservationFile -Wanted $wanted -Cutoff ($Now-28800L)
foreach($pendingKey in @($pendingObservationMap.Keys)){
    if(-not $observationMap.ContainsKey($pendingKey)){$observationMap[$pendingKey]=New-Object System.Collections.Generic.List[object]}
    $seenObservation=@{}
    foreach($existing in @($observationMap[$pendingKey].ToArray())){
        $at=[long](Get-WindowProperty $existing 'sourceTimestamp');if($at -le 0){$at=[long](Get-WindowProperty $existing 'timestamp')}
        $seenObservation[([string]$at+':'+[string][long](Get-WindowProperty $existing 'stock'))]=$true
    }
    foreach($pending in @($pendingObservationMap[$pendingKey].ToArray())){
        $at=[long](Get-WindowProperty $pending 'sourceTimestamp');if($at -le 0){$at=[long](Get-WindowProperty $pending 'timestamp')}
        $identity=([string]$at+':'+[string][long](Get-WindowProperty $pending 'stock'))
        if(-not$seenObservation.ContainsKey($identity)){$observationMap[$pendingKey].Add($pending);$seenObservation[$identity]=$true}
    }
}
foreach($observationKey in @($observationMap.Keys)){
    $filtered=@(Get-PlausibilityFilteredStockObservations -Rows @($observationMap[$observationKey].ToArray()) -ExpectedPollIntervalSeconds 60)
    $list=New-Object System.Collections.Generic.List[object]
    foreach($row in $filtered){$list.Add($row)}
    $observationMap[$observationKey]=$list
}
$travelState=([string]$state['TravelState']).Trim().ToLowerInvariant()
$destinationCountry=([string]$state['TravelDestinationCountryId']).Trim().ToLowerInvariant()
$travelLeft=0L
[void][long]::TryParse([string]$state['TravelTimeLeft'],[ref]$travelLeft)

for ($i=1; $i -le $count; $i++) {
    $prefix='Opportunity'+$i
    $key=[string]$state[$prefix+'Key']
    if ([string]::IsNullOrWhiteSpace($key)) { continue }

    # Every field owned by the authoritative legacy window stage is initialized
    # for this generation before any fast-path/continue branch. This prevents a
    # previous row at the same numeric index from surviving into the new snapshot.
    $state[$prefix+'CurrentStock']='0'
    $state[$prefix+'StockEvidenceAt']='0'
    $state[$prefix+'ActiveRestockAt']='0'
    $state[$prefix+'ActiveSelloutEstimateAt']='0'
    $state[$prefix+'NextRestockEstimateAt']='0'
    $state[$prefix+'LastObservedOosAt']='0'
    $state[$prefix+'MedianRestockDelaySeconds']='0'
    $state[$prefix+'LiveCycleProjectionMode']='none'
    $state[$prefix+'WindowDataQuality']='collecting'
    $state[$prefix+'WindowDataQualityReason']='window evidence was not evaluated'
    $state[$prefix+'CurrentCycleReachable']='0'
    $state[$prefix+'CurrentCycleLeaveDeadlineAt']='0'
    $state[$prefix+'CurrentCycleSafetyMarginSeconds']='0'
    $state[$prefix+'NextCycleOrdinal']='0'
    $state[$prefix+'WindowMedianPeriodSeconds']='0'
    $state[$prefix+'ImmediateArrivalAt']='0'
    $state[$prefix+'ImmediateArrivalProbabilityValue']='-1'
    $state[$prefix+'ImmediateArrivalProbabilitySource']='unknown'
    $state[$prefix+'CurrentCycleLiveProbability']='-1'
    $state[$prefix+'CurrentCycleLiveProbabilitySampleCount']='0'
    $state[$prefix+'CurrentCycleLiveProbabilityEvidenceSpanSeconds']='0'
    $state[$prefix+'CurrentCycleLiveProbabilityMedianRunwaySeconds']='0'
    $state[$prefix+'CurrentStockSafetyEligible']='0'
    $state[$prefix+'CurrentStockSafetyMode']='none'
    $state[$prefix+'CurrentStockSafetyMinimumHoldHorizonSeconds']='0'
    $state[$prefix+'CurrentStockSafetySampleCount']='0'
    $state[$prefix+'CurrentStockSafetyEvidenceSpanSeconds']='0'
    $state[$prefix+'CurrentStockSafetyPercentileUnitsPerHour']='0'
    $state[$prefix+'CurrentStockSafetyGuardedUnitsPerHour']='0'
    $state[$prefix+'CurrentStockSafetyRunwaySeconds']='0'
    $state[$prefix+'CurrentStockSafetyArrivalHorizonSeconds']='0'
    $state[$prefix+'CurrentStockSafetyMarginSeconds']='0'
    $state[$prefix+'CurrentStockSafetySelloutEstimateAt']='0'
    $state[$prefix+'CurrentStockSafetyReason']=''
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
    $forecastEligibleCycles=@($cycles | Where-Object { Test-CycleForecastBoundaryEvidence -Cycle $_ -Purpose Forecast })
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
    $lastObservedOosAt=0L
    if($null -ne $destinationState){
        $candidateOosAt=[long](Get-WindowProperty $destinationState 'lastSellOutAt')
        $candidateOosQuality=[string](Get-WindowProperty $destinationState 'lastSellOutBoundaryQuality')
        if($candidateOosAt -gt 0 -and (Test-WindowBoundaryQuality -Quality $candidateOosQuality)){
            $lastObservedOosAt=$candidateOosAt
        }
    }
    $state[$prefix+'LastObservedOosAt']=$lastObservedOosAt
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
            $qualityLabel=if([string]::IsNullOrWhiteSpace($restockQuality)){'missing'}else{$restockQuality}
            $collectingReason=('current restock boundary was not observed or recovered (restock {0}, quality {1})' -f $restockAt,$qualityLabel)
        } elseif ([long]$liveProjection.activeSelloutEstimateAt -le 0) {
            $restockQuantity=if($null -ne $activeCycle){[long](Get-WindowProperty $activeCycle 'restockQuantity')}else{0L}
            $collectingReason=('current sellout cannot yet be estimated (mode {0}; restock qty {1}; raw cycles {2}, eligible {3})' -f [string]$liveProjection.mode,$restockQuantity,$cycles.Count,$forecastEligibleCycles.Count)
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
    $state[$prefix+'ImmediateArrivalAt']=[long]$earliestArrival
    $state[$prefix+'CurrentCycleReachable']='0'
    $state[$prefix+'CurrentCycleLeaveDeadlineAt']='0'
    $state[$prefix+'CurrentCycleSafetyMarginSeconds']='0'
    $state[$prefix+'NextCycleOrdinal']=if ($stock -gt 0) { '1' } else { '0' }

    # Compute direct current-stock fallback telemetry for every fresh positive-stock
    # market. Normal current-cycle / Safe-Best / multi-cycle logic still owns the
    # card whenever it can produce actionable guidance; this evidence is consumed
    # only by otherwise non-informative presentation states.
    $safety=$null
    if ($stock -gt 0) {
        $marketObservations=@()
        if($observationMap.ContainsKey($key)){$marketObservations=@($observationMap[$key].ToArray())}
        $safety=Get-CurrentStockSafetyProjection -CurrentStock $stock -SourceTimestamp $sourceTimestamp -Observations $marketObservations -EarliestArrivalAt $earliestArrival -NowEpoch $Now -KnownSelloutEstimateAt ([long]$liveProjection.activeSelloutEstimateAt)
        $state[$prefix+'CurrentStockSafetyMode']=[string](Get-WindowProperty $safety 'mode')
        $state[$prefix+'CurrentStockSafetyMinimumHoldHorizonSeconds']=[long](Get-WindowProperty $safety 'minimumHoldHorizonSeconds')
        $state[$prefix+'CurrentStockSafetySampleCount']=[int](Get-WindowProperty $safety 'sampleCount')
        $state[$prefix+'CurrentStockSafetyEvidenceSpanSeconds']=[long](Get-WindowProperty $safety 'evidenceSpanSeconds')
        $state[$prefix+'CurrentStockSafetyPercentileUnitsPerHour']=[double](Get-WindowProperty $safety 'percentileUnitsPerHour')
        $state[$prefix+'CurrentStockSafetyGuardedUnitsPerHour']=[double](Get-WindowProperty $safety 'guardedUnitsPerHour')
        $state[$prefix+'CurrentStockSafetyRunwaySeconds']=[long](Get-WindowProperty $safety 'runwaySeconds')
        $state[$prefix+'CurrentStockSafetyArrivalHorizonSeconds']=[long](Get-WindowProperty $safety 'arrivalHorizonSeconds')
        $state[$prefix+'CurrentStockSafetyMarginSeconds']=[long](Get-WindowProperty $safety 'arrivalMarginSeconds')
        $state[$prefix+'CurrentStockSafetySelloutEstimateAt']=[long](Get-WindowProperty $safety 'selloutEstimateAt')
        $state[$prefix+'CurrentStockSafetyReason']=[string](Get-WindowProperty $safety 'reason')
        if([bool](Get-WindowProperty $safety 'eligible')){$state[$prefix+'CurrentStockSafetyEligible']='1'}
    }

    # Only an already-non-informative producer state may be replaced directly here.
    # A ready model continues below even when fallback telemetry is eligible.
    if (
        [string]$state[$prefix+'WindowDataQuality'] -eq 'collecting' -and
        $null -ne $safety -and
        [bool](Get-WindowProperty $safety 'eligible')
    ) {
        $state[$prefix+'WindowDataQuality']='current_stock_safe'
        $state[$prefix+'WindowDataQualityReason']='verified current stock provides low-authority travel guidance while the main window model is non-informative'
        $state[$prefix+'WindowStartAt']=[Math]::Max($Now,$earliestDeparture)
        $state[$prefix+'WindowText']='STOCK HOLDING'
        $state[$prefix+'ChanceText']=''
        $state[$prefix+'ProbabilityValue']='-1'
        continue
    }

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
        $marketObservations=@()
        if($observationMap.ContainsKey($key)){$marketObservations=@($observationMap[$key].ToArray())}
        $liveProbability=Get-LiveDepletionArrivalProbability -CurrentStock $stock -SourceTimestamp $sourceTimestamp -Observations $marketObservations -ArrivalAt $earliestArrival -NowEpoch $Now
        $state[$prefix+'CurrentCycleLiveProbability']=[double]$liveProbability.probability
        $state[$prefix+'CurrentCycleLiveProbabilitySampleCount']=[int]$liveProbability.sampleCount
        $state[$prefix+'CurrentCycleLiveProbabilityEvidenceSpanSeconds']=[long]$liveProbability.evidenceSpanSeconds
        $state[$prefix+'CurrentCycleLiveProbabilityMedianRunwaySeconds']=[long]$liveProbability.medianRunwaySeconds

        $currentProbability=-1.0
        $currentProbabilitySource='unknown'
        if([bool]$liveProbability.eligible){
            $currentProbability=[double]$liveProbability.probability
            $currentProbabilitySource='current_cycle_live_depletion'
        }else{
            $currentProbability=Get-StableCurrentCycleArrivalProbability -Cycles $cycles -ActiveRestockAt ([long]$liveProjection.activeRestockAt) -ObservationAt $sourceTimestamp -ArrivalAt $earliestArrival
            if($currentProbability -ge 0){$currentProbabilitySource='current_cycle_conditional_survival'}
        }

        if ($currentProbability -ge 0) {
            $state[$prefix+'ProbabilityValue']=(Convert-WindowProbabilityText ([double]$currentProbability))
            $state[$prefix+'ChanceText']=('{0:N0}%' -f (100.0*[double]$currentProbability))
            $state[$prefix+'ImmediateArrivalProbabilityValue']=(Convert-WindowProbabilityText ([double]$currentProbability))
            $state[$prefix+'ImmediateArrivalProbabilitySource']=$currentProbabilitySource
        }else{
            $state[$prefix+'ProbabilityValue']='-1'
            $state[$prefix+'ChanceText']=''
            $state[$prefix+'ImmediateArrivalProbabilityValue']='-1'
            $state[$prefix+'ImmediateArrivalProbabilitySource']='current_cycle_insufficient_live_or_conditional_evidence'
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
        $state[$prefix+'WindowDataQualityReason']=('no forecast-eligible completed cycles are available for the next restock (raw cycles {0}, eligible {1})' -f $cycles.Count,$forecastEligibleCycles.Count)
        $state[$prefix+'WindowStartAt']='0'
        $state[$prefix+'WindowText']='Collecting Data: See Weav3r'
        $state[$prefix+'ChanceText']=''
        $state[$prefix+'ProbabilityValue']='-1'
        continue
    }

    $immediateProbability=Get-StableRecurringProbabilityAt -Model $model -ArrivalAt $earliestArrival
    if($immediateProbability -ge 0){
        $state[$prefix+'ImmediateArrivalProbabilityValue']=(Convert-WindowProbabilityText ([double]$immediateProbability))
        $state[$prefix+'ImmediateArrivalProbabilitySource']='legacy_current_or_next_cycle'
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
$state['LegacyWindowPlanAuthority']='WindowPlan'
$state['LegacyWindowPlanGeneratedAt']=[long]$Now
Write-WindowStateKvAtomic -Values $state -Path $StateKvFile
) { return [string]$Matches[1] }
    return $value
}

function Get-WindowObservedPhase {
    param([object]$Engine,[string]$Key)
    $market=Get-WindowProperty $Engine.observedMarkets $Key
    $destinationState=$null
    if($Engine.PSObject.Properties['destinations']){$destinationState=Get-WindowProperty $Engine.destinations $Key}

    $observedStock=0L;$sourceTimestamp=0L
    if($null -ne $market){
        $observedStock=[long](Get-WindowProperty $market 'lastStock')
        $sourceTimestamp=[long](Get-WindowProperty $market 'sourceTimestamp')
    }
    $activeRestockAt=0L
    $activeCycle=Get-WindowProperty $destinationState 'activeCycle'
    if($null -ne $activeCycle){$activeRestockAt=[long](Get-WindowProperty $activeCycle 'restockAt')}

    $lastSellOutAt=0L;$lastSellOutQuality=''
    if($null -ne $destinationState){
        $lastSellOutAt=[long](Get-WindowProperty $destinationState 'lastSellOutAt')
        $lastSellOutQuality=[string](Get-WindowProperty $destinationState 'lastSellOutBoundaryQuality')
    }
    $unresolvedOos=(
        $lastSellOutAt -gt 0 -and
        (Test-WindowBoundaryQuality -Quality $lastSellOutQuality) -and
        $activeRestockAt -le $lastSellOutAt -and
        -not($observedStock -gt 0 -and $sourceTimestamp -gt $lastSellOutAt)
    )
    return [pscustomobject]@{
        market=$market;destinationState=$destinationState
        observedStock=$observedStock;sourceTimestamp=$sourceTimestamp
        activeRestockAt=$activeRestockAt
        lastSellOutAt=$lastSellOutAt;lastSellOutQuality=$lastSellOutQuality
        unresolvedOos=[bool]$unresolvedOos
    }
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
$cycleMap=Read-WindowCyclesForKeys -Paths @($SeedCycleFile,$RuntimeCycleFile,$PendingCycleFile) -Wanted $wanted
$observationMap=Read-WindowObservationsForKeys -Path $RuntimeObservationFile -Wanted $wanted -Cutoff ($Now-28800L)
$pendingObservationMap=Read-WindowObservationsForKeys -Path $PendingObservationFile -Wanted $wanted -Cutoff ($Now-28800L)
foreach($pendingKey in @($pendingObservationMap.Keys)){
    if(-not $observationMap.ContainsKey($pendingKey)){$observationMap[$pendingKey]=New-Object System.Collections.Generic.List[object]}
    $seenObservation=@{}
    foreach($existing in @($observationMap[$pendingKey].ToArray())){
        $at=[long](Get-WindowProperty $existing 'sourceTimestamp');if($at -le 0){$at=[long](Get-WindowProperty $existing 'timestamp')}
        $seenObservation[([string]$at+':'+[string][long](Get-WindowProperty $existing 'stock'))]=$true
    }
    foreach($pending in @($pendingObservationMap[$pendingKey].ToArray())){
        $at=[long](Get-WindowProperty $pending 'sourceTimestamp');if($at -le 0){$at=[long](Get-WindowProperty $pending 'timestamp')}
        $identity=([string]$at+':'+[string][long](Get-WindowProperty $pending 'stock'))
        if(-not$seenObservation.ContainsKey($identity)){$observationMap[$pendingKey].Add($pending);$seenObservation[$identity]=$true}
    }
}
foreach($observationKey in @($observationMap.Keys)){
    $filtered=@(Get-PlausibilityFilteredStockObservations -Rows @($observationMap[$observationKey].ToArray()) -ExpectedPollIntervalSeconds 60)
    $list=New-Object System.Collections.Generic.List[object]
    foreach($row in $filtered){$list.Add($row)}
    $observationMap[$observationKey]=$list
}
$travelState=([string]$state['TravelState']).Trim().ToLowerInvariant()
$destinationCountry=([string]$state['TravelDestinationCountryId']).Trim().ToLowerInvariant()
$travelLeft=0L
[void][long]::TryParse([string]$state['TravelTimeLeft'],[ref]$travelLeft)

for ($i=1; $i -le $count; $i++) {
    $prefix='Opportunity'+$i
    $key=[string]$state[$prefix+'Key']
    if ([string]::IsNullOrWhiteSpace($key)) { continue }

    # Every field owned by the authoritative legacy window stage is initialized
    # for this generation before any fast-path/continue branch. This prevents a
    # previous row at the same numeric index from surviving into the new snapshot.
    $state[$prefix+'CurrentStock']='0'
    $state[$prefix+'StockEvidenceAt']='0'
    $state[$prefix+'ActiveRestockAt']='0'
    $state[$prefix+'ActiveSelloutEstimateAt']='0'
    $state[$prefix+'NextRestockEstimateAt']='0'
    $state[$prefix+'LastObservedOosAt']='0'
    $state[$prefix+'MedianRestockDelaySeconds']='0'
    $state[$prefix+'LiveCycleProjectionMode']='none'
    $state[$prefix+'WindowDataQuality']='collecting'
    $state[$prefix+'WindowDataQualityReason']='window evidence was not evaluated'
    $state[$prefix+'CurrentCycleReachable']='0'
    $state[$prefix+'CurrentCycleLeaveDeadlineAt']='0'
    $state[$prefix+'CurrentCycleSafetyMarginSeconds']='0'
    $state[$prefix+'NextCycleOrdinal']='0'
    $state[$prefix+'WindowMedianPeriodSeconds']='0'
    $state[$prefix+'ImmediateArrivalAt']='0'
    $state[$prefix+'ImmediateArrivalProbabilityValue']='-1'
    $state[$prefix+'ImmediateArrivalProbabilitySource']='unknown'
    $state[$prefix+'CurrentCycleLiveProbability']='-1'
    $state[$prefix+'CurrentCycleLiveProbabilitySampleCount']='0'
    $state[$prefix+'CurrentCycleLiveProbabilityEvidenceSpanSeconds']='0'
    $state[$prefix+'CurrentCycleLiveProbabilityMedianRunwaySeconds']='0'
    $state[$prefix+'CurrentStockSafetyEligible']='0'
    $state[$prefix+'CurrentStockSafetyMode']='none'
    $state[$prefix+'CurrentStockSafetyMinimumHoldHorizonSeconds']='0'
    $state[$prefix+'CurrentStockSafetySampleCount']='0'
    $state[$prefix+'CurrentStockSafetyEvidenceSpanSeconds']='0'
    $state[$prefix+'CurrentStockSafetyPercentileUnitsPerHour']='0'
    $state[$prefix+'CurrentStockSafetyGuardedUnitsPerHour']='0'
    $state[$prefix+'CurrentStockSafetyRunwaySeconds']='0'
    $state[$prefix+'CurrentStockSafetyArrivalHorizonSeconds']='0'
    $state[$prefix+'CurrentStockSafetyMarginSeconds']='0'
    $state[$prefix+'CurrentStockSafetySelloutEstimateAt']='0'
    $state[$prefix+'CurrentStockSafetyReason']=''
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
    $forecastEligibleCycles=@($cycles | Where-Object { Test-CycleForecastBoundaryEvidence -Cycle $_ -Purpose Forecast })
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
    $lastObservedOosAt=0L
    if($null -ne $destinationState){
        $candidateOosAt=[long](Get-WindowProperty $destinationState 'lastSellOutAt')
        $candidateOosQuality=[string](Get-WindowProperty $destinationState 'lastSellOutBoundaryQuality')
        if($candidateOosAt -gt 0 -and (Test-WindowBoundaryQuality -Quality $candidateOosQuality)){
            $lastObservedOosAt=$candidateOosAt
        }
    }
    $state[$prefix+'LastObservedOosAt']=$lastObservedOosAt
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
            $qualityLabel=if([string]::IsNullOrWhiteSpace($restockQuality)){'missing'}else{$restockQuality}
            $collectingReason=('current restock boundary was not observed or recovered (restock {0}, quality {1})' -f $restockAt,$qualityLabel)
        } elseif ([long]$liveProjection.activeSelloutEstimateAt -le 0) {
            $restockQuantity=if($null -ne $activeCycle){[long](Get-WindowProperty $activeCycle 'restockQuantity')}else{0L}
            $collectingReason=('current sellout cannot yet be estimated (mode {0}; restock qty {1}; raw cycles {2}, eligible {3})' -f [string]$liveProjection.mode,$restockQuantity,$cycles.Count,$forecastEligibleCycles.Count)
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
    $state[$prefix+'ImmediateArrivalAt']=[long]$earliestArrival
    $state[$prefix+'CurrentCycleReachable']='0'
    $state[$prefix+'CurrentCycleLeaveDeadlineAt']='0'
    $state[$prefix+'CurrentCycleSafetyMarginSeconds']='0'
    $state[$prefix+'NextCycleOrdinal']=if ($stock -gt 0) { '1' } else { '0' }

    # Compute direct current-stock fallback telemetry for every fresh positive-stock
    # market. Normal current-cycle / Safe-Best / multi-cycle logic still owns the
    # card whenever it can produce actionable guidance; this evidence is consumed
    # only by otherwise non-informative presentation states.
    $safety=$null
    if ($stock -gt 0) {
        $marketObservations=@()
        if($observationMap.ContainsKey($key)){$marketObservations=@($observationMap[$key].ToArray())}
        $safety=Get-CurrentStockSafetyProjection -CurrentStock $stock -SourceTimestamp $sourceTimestamp -Observations $marketObservations -EarliestArrivalAt $earliestArrival -NowEpoch $Now -KnownSelloutEstimateAt ([long]$liveProjection.activeSelloutEstimateAt)
        $state[$prefix+'CurrentStockSafetyMode']=[string](Get-WindowProperty $safety 'mode')
        $state[$prefix+'CurrentStockSafetyMinimumHoldHorizonSeconds']=[long](Get-WindowProperty $safety 'minimumHoldHorizonSeconds')
        $state[$prefix+'CurrentStockSafetySampleCount']=[int](Get-WindowProperty $safety 'sampleCount')
        $state[$prefix+'CurrentStockSafetyEvidenceSpanSeconds']=[long](Get-WindowProperty $safety 'evidenceSpanSeconds')
        $state[$prefix+'CurrentStockSafetyPercentileUnitsPerHour']=[double](Get-WindowProperty $safety 'percentileUnitsPerHour')
        $state[$prefix+'CurrentStockSafetyGuardedUnitsPerHour']=[double](Get-WindowProperty $safety 'guardedUnitsPerHour')
        $state[$prefix+'CurrentStockSafetyRunwaySeconds']=[long](Get-WindowProperty $safety 'runwaySeconds')
        $state[$prefix+'CurrentStockSafetyArrivalHorizonSeconds']=[long](Get-WindowProperty $safety 'arrivalHorizonSeconds')
        $state[$prefix+'CurrentStockSafetyMarginSeconds']=[long](Get-WindowProperty $safety 'arrivalMarginSeconds')
        $state[$prefix+'CurrentStockSafetySelloutEstimateAt']=[long](Get-WindowProperty $safety 'selloutEstimateAt')
        $state[$prefix+'CurrentStockSafetyReason']=[string](Get-WindowProperty $safety 'reason')
        if([bool](Get-WindowProperty $safety 'eligible')){$state[$prefix+'CurrentStockSafetyEligible']='1'}
    }

    # Only an already-non-informative producer state may be replaced directly here.
    # A ready model continues below even when fallback telemetry is eligible.
    if (
        [string]$state[$prefix+'WindowDataQuality'] -eq 'collecting' -and
        $null -ne $safety -and
        [bool](Get-WindowProperty $safety 'eligible')
    ) {
        $state[$prefix+'WindowDataQuality']='current_stock_safe'
        $state[$prefix+'WindowDataQualityReason']='verified current stock provides low-authority travel guidance while the main window model is non-informative'
        $state[$prefix+'WindowStartAt']=[Math]::Max($Now,$earliestDeparture)
        $state[$prefix+'WindowText']='STOCK HOLDING'
        $state[$prefix+'ChanceText']=''
        $state[$prefix+'ProbabilityValue']='-1'
        continue
    }

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
        $marketObservations=@()
        if($observationMap.ContainsKey($key)){$marketObservations=@($observationMap[$key].ToArray())}
        $liveProbability=Get-LiveDepletionArrivalProbability -CurrentStock $stock -SourceTimestamp $sourceTimestamp -Observations $marketObservations -ArrivalAt $earliestArrival -NowEpoch $Now
        $state[$prefix+'CurrentCycleLiveProbability']=[double]$liveProbability.probability
        $state[$prefix+'CurrentCycleLiveProbabilitySampleCount']=[int]$liveProbability.sampleCount
        $state[$prefix+'CurrentCycleLiveProbabilityEvidenceSpanSeconds']=[long]$liveProbability.evidenceSpanSeconds
        $state[$prefix+'CurrentCycleLiveProbabilityMedianRunwaySeconds']=[long]$liveProbability.medianRunwaySeconds

        $currentProbability=-1.0
        $currentProbabilitySource='unknown'
        if([bool]$liveProbability.eligible){
            $currentProbability=[double]$liveProbability.probability
            $currentProbabilitySource='current_cycle_live_depletion'
        }else{
            $currentProbability=Get-StableCurrentCycleArrivalProbability -Cycles $cycles -ActiveRestockAt ([long]$liveProjection.activeRestockAt) -ObservationAt $sourceTimestamp -ArrivalAt $earliestArrival
            if($currentProbability -ge 0){$currentProbabilitySource='current_cycle_conditional_survival'}
        }

        if ($currentProbability -ge 0) {
            $state[$prefix+'ProbabilityValue']=(Convert-WindowProbabilityText ([double]$currentProbability))
            $state[$prefix+'ChanceText']=('{0:N0}%' -f (100.0*[double]$currentProbability))
            $state[$prefix+'ImmediateArrivalProbabilityValue']=(Convert-WindowProbabilityText ([double]$currentProbability))
            $state[$prefix+'ImmediateArrivalProbabilitySource']=$currentProbabilitySource
        }else{
            $state[$prefix+'ProbabilityValue']='-1'
            $state[$prefix+'ChanceText']=''
            $state[$prefix+'ImmediateArrivalProbabilityValue']='-1'
            $state[$prefix+'ImmediateArrivalProbabilitySource']='current_cycle_insufficient_live_or_conditional_evidence'
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
        $state[$prefix+'WindowDataQualityReason']=('no forecast-eligible completed cycles are available for the next restock (raw cycles {0}, eligible {1})' -f $cycles.Count,$forecastEligibleCycles.Count)
        $state[$prefix+'WindowStartAt']='0'
        $state[$prefix+'WindowText']='Collecting Data: See Weav3r'
        $state[$prefix+'ChanceText']=''
        $state[$prefix+'ProbabilityValue']='-1'
        continue
    }

    $immediateProbability=Get-StableRecurringProbabilityAt -Model $model -ArrivalAt $earliestArrival
    if($immediateProbability -ge 0){
        $state[$prefix+'ImmediateArrivalProbabilityValue']=(Convert-WindowProbabilityText ([double]$immediateProbability))
        $state[$prefix+'ImmediateArrivalProbabilitySource']='legacy_current_or_next_cycle'
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
$state['LegacyWindowPlanAuthority']='WindowPlan'
$state['LegacyWindowPlanGeneratedAt']=[long]$Now
Write-WindowStateKvAtomic -Values $state -Path $StateKvFile
