param(
    [Alias('SkipMain')]
    [switch]$StochasticCalibrationSkipMain,
    [long]$Now = 0,
    [ValidateRange(300,86400)]
    [int]$FreezeIntervalSeconds = 3600,
    [ValidateRange(0,3600)]
    [int]$OutcomeGraceSeconds = 300,
    [ValidateRange(3600,1209600)]
    [int]$MaximumOutcomeWaitSeconds = 604800,
    [ValidateRange(100,10000)]
    [int]$RecentScoreLimit = 2000
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RuntimeDir=Join-Path $ProjectRoot 'data\runtime'
$ForecastFile=Join-Path $RuntimeDir 'stochastic-forecast.json'
$StateFile=Join-Path $RuntimeDir 'stochastic-calibration-state.json'
$SummaryFile=Join-Path $RuntimeDir 'stochastic-calibration.json'
$ObservationFile=Join-Path $RuntimeDir 'observations.jsonl'
$CycleFile=Join-Path $RuntimeDir 'cycles.jsonl'
$AtomicFileScript=Join-Path $PSScriptRoot 'AtomicFile.ps1'
if (-not (Test-Path -LiteralPath $AtomicFileScript)) { throw 'AtomicFile.ps1 is required for stochastic calibration state.' }
. $AtomicFileScript

function Get-SCProperty {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property=$Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Set-SCProperty {
    param([object]$Object,[string]$Name,[object]$Value)
    if ($null -eq $Object) { return }
    $property=$Object.PSObject.Properties[$Name]
    if ($null -eq $property) { $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value }
    else { $property.Value=$Value }
}

function Read-SCJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw=Read-TravelAssistantSharedText -Path $Path
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    try { return ($raw | ConvertFrom-Json) } catch { return $null }
}

function New-SCCalibrationState {
    return [pscustomobject]@{
        schemaVersion=1
        updatedAt=0L
        pending=@()
        recentScores=@()
        lastFrozen=@()
        aggregates=@()
    }
}

function Repair-SCCalibrationState {
    param([object]$State)
    if ($null -eq $State) { $State=New-SCCalibrationState }
    foreach ($entry in @(
        [pscustomobject]@{name='schemaVersion';value=1},
        [pscustomobject]@{name='updatedAt';value=0L},
        [pscustomobject]@{name='pending';value=@()},
        [pscustomobject]@{name='recentScores';value=@()},
        [pscustomobject]@{name='lastFrozen';value=@()},
        [pscustomobject]@{name='aggregates';value=@()}
    )) {
        if ($null -eq $State.PSObject.Properties[[string]$entry.name]) {
            $State | Add-Member -MemberType NoteProperty -Name ([string]$entry.name) -Value $entry.value
        }
    }
    return $State
}

function Get-SCEvidenceAt {
    param([object]$Row)
    $at=[long](Get-SCProperty $Row 'sourceTimestamp')
    if ($at -le 0) { $at=[long](Get-SCProperty $Row 'timestamp') }
    return $at
}

function Get-SCMarketKeyFromLine {
    param([string]$Line)
    if ([string]::IsNullOrWhiteSpace($Line)) { return '' }
    $country=[regex]::Match($Line,'"country"\s*:\s*"([^"]+)"')
    $item=[regex]::Match($Line,'"itemId"\s*:\s*([1-9][0-9]*)')
    if (-not $country.Success -or -not $item.Success) { return '' }
    return ($country.Groups[1].Value.Trim().ToLowerInvariant()+':'+$item.Groups[1].Value)
}

function Read-SCEvidenceMap {
    param([string]$Path,[hashtable]$Wanted,[ValidateSet('cycle','observation')][string]$Kind,[long]$AsOf)
    $map=@{}
    if ($Wanted.Count -eq 0 -or -not (Test-Path -LiteralPath $Path)) { return $map }
    $reader=$null
    try {
        $reader=Open-TravelAssistantSharedTextReader -Path $Path
        while (($line=$reader.ReadLine()) -ne $null) {
            $key=Get-SCMarketKeyFromLine -Line $line
            if ([string]::IsNullOrWhiteSpace($key) -or -not $Wanted.ContainsKey($key)) { continue }
            try { $row=$line | ConvertFrom-Json } catch { continue }

            if ($Kind -eq 'observation') {
                $availableAt=Get-SCEvidenceAt $row
                if ($availableAt -le 0 -or ($AsOf -gt 0 -and $availableAt -gt $AsOf)) { continue }
            } else {
                $availableAt=[long](Get-SCProperty $row 'soldOutUpperBoundAt')
                if ($availableAt -le 0) { $availableAt=[long](Get-SCProperty $row 'soldOutAt') }
                if ($availableAt -le 0 -or ($AsOf -gt 0 -and $availableAt -gt $AsOf)) { continue }
            }

            if (-not $map.ContainsKey($key)) { $map[$key]=New-Object System.Collections.Generic.List[object] }
            $map[$key].Add($row)
        }
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
    }
    return $map
}

function Get-SCExactObservationOutcome {
    param([object[]]$Observations,[long]$ArrivalAt,[int]$TargetQuantity)
    $matches=@($Observations | Where-Object { (Get-SCEvidenceAt $_) -eq $ArrivalAt })
    if ($matches.Count -eq 0) {
        return [pscustomobject]@{
            anyScorable=$false; anyStock=-1
            targetScorable=$false; targetSuccess=-1
            quantityScorable=$false; actualQuantity=0L
            reason='no exact provider snapshot at arrival'; evidenceAt=0L
        }
    }

    $stocks=[long[]]@($matches | ForEach-Object { [Math]::Max(0L,[long](Get-SCProperty $_ 'stock')) })
    $minimum=[long](@($stocks | Measure-Object -Minimum).Minimum)
    $maximum=[long](@($stocks | Measure-Object -Maximum).Maximum)
    $target=[Math]::Max(1,$TargetQuantity)

    $anyScorable=($minimum -gt 0 -or $maximum -eq 0)
    $anyStock=if($minimum -gt 0){1}elseif($maximum -eq 0){0}else{-1}
    $targetScorable=($minimum -ge $target -or $maximum -lt $target)
    $targetSuccess=if($minimum -ge $target){1}elseif($maximum -lt $target){0}else{-1}
    $quantityScorable=($minimum -eq $maximum)

    return [pscustomobject]@{
        anyScorable=[bool]$anyScorable
        anyStock=[int]$anyStock
        targetScorable=[bool]$targetScorable
        targetSuccess=[int]$targetSuccess
        quantityScorable=[bool]$quantityScorable
        actualQuantity=$(if($quantityScorable){$minimum}else{0L})
        reason=$(if($quantityScorable){'exact provider snapshot at arrival'}else{'conflicting exact provider snapshots at arrival'})
        evidenceAt=[long]$ArrivalAt
    }
}

function Get-SCConfirmedOutcome {
    param(
        [long]$ArrivalAt,
        [int]$TargetQuantity,
        [object[]]$Observations,
        [object[]]$Cycles,
        [long]$AsOf
    )
    $exact=Get-SCExactObservationOutcome -Observations $Observations -ArrivalAt $ArrivalAt -TargetQuantity $TargetQuantity
    if ([bool]$exact.anyScorable) { return $exact }

    $eligible=New-Object System.Collections.Generic.List[object]
    foreach ($cycle in @($Cycles)) {
        $availableAt=[long](Get-SCProperty $cycle 'soldOutUpperBoundAt')
        if ($availableAt -le 0) { $availableAt=[long](Get-SCProperty $cycle 'soldOutAt') }
        if ($availableAt -le 0 -or ($AsOf -gt 0 -and $availableAt -gt $AsOf)) { continue }

        $restockLower=[long](Get-SCProperty $cycle 'restockLowerBoundAt')
        $restockUpper=[long](Get-SCProperty $cycle 'restockUpperBoundAt')
        $selloutLower=[long](Get-SCProperty $cycle 'soldOutLowerBoundAt')
        $selloutUpper=[long](Get-SCProperty $cycle 'soldOutUpperBoundAt')
        if ($restockUpper -le 0) { $restockUpper=[long](Get-SCProperty $cycle 'restockAt') }
        if ($restockLower -le 0) { $restockLower=$restockUpper }
        if ($selloutUpper -le 0) { $selloutUpper=[long](Get-SCProperty $cycle 'soldOutAt') }
        if ($selloutLower -le 0) { $selloutLower=$selloutUpper }
        if ($restockUpper -le 0 -or $selloutUpper -le $restockUpper) { continue }

        $eligible.Add([pscustomobject]@{
            restockLower=$restockLower
            restockUpper=$restockUpper
            selloutLower=$selloutLower
            selloutUpper=$selloutUpper
            availableAt=$availableAt
        })
    }

    $ordered=@($eligible.ToArray() | Sort-Object restockUpper)
    foreach ($cycle in $ordered) {
        if ($ArrivalAt -ge [long]$cycle.restockUpper -and $ArrivalAt -lt [long]$cycle.selloutLower) {
            return [pscustomobject]@{
                anyScorable=$true; anyStock=1
                targetScorable=$false; targetSuccess=-1
                quantityScorable=$false; actualQuantity=0L
                reason='arrival lies inside confirmed completed-cycle in-stock interval'
                evidenceAt=[long]$cycle.availableAt
            }
        }
    }

    for ($i=0; $i -lt ($ordered.Count-1); $i++) {
        $left=$ordered[$i]
        $right=$ordered[$i+1]
        if ($ArrivalAt -ge [long]$left.selloutUpper -and $ArrivalAt -lt [long]$right.restockLower) {
            return [pscustomobject]@{
                anyScorable=$true; anyStock=0
                targetScorable=$false; targetSuccess=-1
                quantityScorable=$false; actualQuantity=0L
                reason='arrival lies inside confirmed between-cycle out-of-stock interval'
                evidenceAt=[Math]::Max([long]$left.availableAt,[long]$right.availableAt)
            }
        }
    }

    return [pscustomobject]@{
        anyScorable=$false; anyStock=-1
        targetScorable=[bool]$exact.targetScorable; targetSuccess=[int]$exact.targetSuccess
        quantityScorable=[bool]$exact.quantityScorable; actualQuantity=[long]$exact.actualQuantity
        reason='arrival remains inside unresolved transition/censor interval'
        evidenceAt=[long]$exact.evidenceAt
    }
}

function Get-SCLastFrozen {
    param([object]$State,[string]$ModelVersion,[string]$MarketKey)
    return @($State.lastFrozen | Where-Object {
        [string](Get-SCProperty $_ 'modelVersion') -eq $ModelVersion -and
        [string](Get-SCProperty $_ 'marketKey') -eq $MarketKey
    } | Select-Object -First 1)
}

function Set-SCLastFrozen {
    param([object]$State,[string]$ModelVersion,[string]$MarketKey,[long]$Bucket)
    $found=Get-SCLastFrozen -State $State -ModelVersion $ModelVersion -MarketKey $MarketKey
    if ($found.Count -gt 0) {
        Set-SCProperty -Object $found[0] -Name 'bucket' -Value $Bucket
        return
    }
    $State.lastFrozen=@($State.lastFrozen)+@([pscustomobject]@{
        modelVersion=$ModelVersion
        marketKey=$MarketKey
        bucket=$Bucket
    })
}

function Get-SCFreezeRows {
    param(
        [object]$Artifact,
        [object]$State,
        [long]$NowEpoch,
        [int]$IntervalSeconds=3600,
        [int]$MaximumArtifactAgeSeconds=300
    )
    $rows=New-Object System.Collections.Generic.List[object]
    if ($null -eq $Artifact) { return $rows.ToArray() }

    $generatedAt=[long](Get-SCProperty $Artifact 'generatedAt')
    $modelVersion=([string](Get-SCProperty $Artifact 'modelVersion')).Trim()
    if ($generatedAt -le 0 -or [string]::IsNullOrWhiteSpace($modelVersion)) { return $rows.ToArray() }
    if ($generatedAt -gt $NowEpoch -or ($NowEpoch-$generatedAt) -gt $MaximumArtifactAgeSeconds) { return $rows.ToArray() }

    $bucket=[long][Math]::Floor($generatedAt/[double][Math]::Max(300,$IntervalSeconds))
    foreach ($market in @((Get-SCProperty $Artifact 'markets'))) {
        $marketKey=([string](Get-SCProperty $market 'marketKey')).Trim().ToLowerInvariant()
        $arrivalAt=[long](Get-SCProperty $market 'bestArrivalAt')
        if ([string]::IsNullOrWhiteSpace($marketKey) -or $arrivalAt -le 0 -or $arrivalAt -lt $generatedAt) { continue }

        $last=Get-SCLastFrozen -State $State -ModelVersion $modelVersion -MarketKey $marketKey
        if ($last.Count -gt 0 -and [long](Get-SCProperty $last[0] 'bucket') -eq $bucket) { continue }

        $arrival=@((Get-SCProperty $market 'arrivals') | Where-Object { [long](Get-SCProperty $_ 'arrivalAt') -eq $arrivalAt } | Select-Object -First 1)
        if ($arrival.Count -eq 0) { continue }

        $probability=[double](Get-SCProperty $arrival[0] 'pAnyStock')
        if ($probability -lt 0.0 -or $probability -gt 1.0) { continue }
        $targetProbability=[double](Get-SCProperty $arrival[0] 'pTargetQty')
        $targetQuantity=[int](Get-SCProperty $market 'targetQuantity')
        $country=[string](Get-SCProperty $market 'countryId')
        $itemId=[int](Get-SCProperty $market 'itemId')
        $evidenceQuality=[string](Get-SCProperty $market 'evidenceQuality')
        $decision=Get-SCProperty $market 'decision'
        $diagnostics=Get-SCProperty $market 'diagnostics'

        $row=[pscustomobject]@{
            schemaVersion=1
            forecastId=($modelVersion+'|'+$marketKey+'|'+[string]$bucket+'|'+[string]$arrivalAt)
            modelVersion=$modelVersion
            forecastKind='best_expected_profit'
            frozenAt=$NowEpoch
            generatedAt=$generatedAt
            freezeBucket=$bucket
            marketKey=$marketKey
            countryId=$country
            itemId=$itemId
            departureAt=[long](Get-SCProperty $market 'bestDepartureAt')
            arrivalAt=$arrivalAt
            horizonSeconds=[Math]::Max(0L,$arrivalAt-$generatedAt)
            pAnyStock=$probability
            pTargetQty=[Math]::Max(0.0,[Math]::Min(1.0,$targetProbability))
            targetQuantity=[Math]::Max(1,$targetQuantity)
            expectedQty=[double](Get-SCProperty $arrival[0] 'expectedQty')
            expectedAvailableQty=[double](Get-SCProperty $arrival[0] 'expectedAvailableQty')
            expectedProfit=[double](Get-SCProperty $arrival[0] 'expectedProfit')
            expectedProfitPerHour=[double](Get-SCProperty $arrival[0] 'expectedProfitPerHour')
            evidenceQuality=$evidenceQuality
            sampleCount=[int](Get-SCProperty $market 'sampleCount')
            effectiveSampleSize=[double](Get-SCProperty $market 'effectiveSampleSize')
            decisionState=[string](Get-SCProperty $decision 'state')
            travelMode=[string](Get-SCProperty $diagnostics 'travelMode')
            adaptivePoint=[bool](Get-SCProperty $arrival[0] 'adaptivePoint')
            adaptiveSource=[string](Get-SCProperty $arrival[0] 'adaptiveSource')
            depletionModel=[string](Get-SCProperty $market 'depletionModel')
        }
        $rows.Add($row)
        Set-SCLastFrozen -State $State -ModelVersion $modelVersion -MarketKey $marketKey -Bucket $bucket
    }
    return $rows.ToArray()
}

function New-SCAggregate {
    param([string]$ModelVersion,[string]$EvidenceQuality)
    $buckets=New-Object System.Collections.Generic.List[object]
    for ($i=0; $i -lt 10; $i++) {
        $buckets.Add([pscustomobject]@{index=$i;count=0;probabilitySum=0.0;outcomeSum=0.0})
    }
    return [pscustomobject]@{
        modelVersion=$ModelVersion
        evidenceQuality=$EvidenceQuality
        anyCount=0
        anyBrierSum=0.0
        anyLogLossSum=0.0
        anyProbabilitySum=0.0
        anyOutcomeSum=0.0
        targetCount=0
        targetBrierSum=0.0
        targetLogLossSum=0.0
        targetProbabilitySum=0.0
        targetOutcomeSum=0.0
        quantityCount=0
        quantityAbsoluteErrorSum=0.0
        quantitySquaredErrorSum=0.0
        buckets=$buckets.ToArray()
    }
}

function Get-SCAggregate {
    param([object]$State,[string]$ModelVersion,[string]$EvidenceQuality)
    $match=@($State.aggregates | Where-Object {
        [string](Get-SCProperty $_ 'modelVersion') -eq $ModelVersion -and
        [string](Get-SCProperty $_ 'evidenceQuality') -eq $EvidenceQuality
    } | Select-Object -First 1)
    if ($match.Count -gt 0) { return $match[0] }

    $aggregate=New-SCAggregate -ModelVersion $ModelVersion -EvidenceQuality $EvidenceQuality
    $State.aggregates=@($State.aggregates)+@($aggregate)
    return $aggregate
}

function Add-SCProbabilityScore {
    param([object]$Aggregate,[string]$Prefix,[double]$Probability,[int]$Outcome)
    $p=[Math]::Max(0.000001,[Math]::Min(0.999999,$Probability))
    $y=if($Outcome -gt 0){1}else{0}
    $brier=[Math]::Pow($p-$y,2)
    $logLoss=-($y*[Math]::Log($p)+(1-$y)*[Math]::Log(1-$p))

    if ($Prefix -eq 'any') {
        $Aggregate.anyCount=[int]$Aggregate.anyCount+1
        $Aggregate.anyBrierSum=[double]$Aggregate.anyBrierSum+$brier
        $Aggregate.anyLogLossSum=[double]$Aggregate.anyLogLossSum+$logLoss
        $Aggregate.anyProbabilitySum=[double]$Aggregate.anyProbabilitySum+$p
        $Aggregate.anyOutcomeSum=[double]$Aggregate.anyOutcomeSum+$y

        $bucket=[int][Math]::Min(9,[Math]::Floor($p*10.0))
        $entry=@($Aggregate.buckets | Where-Object { [int]$_.index -eq $bucket } | Select-Object -First 1)[0]
        $entry.count=[int]$entry.count+1
        $entry.probabilitySum=[double]$entry.probabilitySum+$p
        $entry.outcomeSum=[double]$entry.outcomeSum+$y
    } else {
        $Aggregate.targetCount=[int]$Aggregate.targetCount+1
        $Aggregate.targetBrierSum=[double]$Aggregate.targetBrierSum+$brier
        $Aggregate.targetLogLossSum=[double]$Aggregate.targetLogLossSum+$logLoss
        $Aggregate.targetProbabilitySum=[double]$Aggregate.targetProbabilitySum+$p
        $Aggregate.targetOutcomeSum=[double]$Aggregate.targetOutcomeSum+$y
    }
}

function Add-SCScoreToAggregate {
    param([object]$State,[object]$Score)
    $modelVersion=[string](Get-SCProperty $Score 'modelVersion')
    $quality=([string](Get-SCProperty $Score 'evidenceQuality')).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($quality)) { $quality='unknown' }

    foreach ($scope in @('all',$quality)) {
        $aggregate=Get-SCAggregate -State $State -ModelVersion $modelVersion -EvidenceQuality $scope
        Add-SCProbabilityScore -Aggregate $aggregate -Prefix 'any' -Probability ([double](Get-SCProperty $Score 'pAnyStock')) -Outcome ([int](Get-SCProperty $Score 'anyStock'))

        if ([bool](Get-SCProperty $Score 'targetScorable')) {
            Add-SCProbabilityScore -Aggregate $aggregate -Prefix 'target' -Probability ([double](Get-SCProperty $Score 'pTargetQty')) -Outcome ([int](Get-SCProperty $Score 'targetSuccess'))
        }
        if ([bool](Get-SCProperty $Score 'quantityScorable')) {
            $actual=[double](Get-SCProperty $Score 'actualQuantity')
            $predicted=[double](Get-SCProperty $Score 'expectedAvailableQty')
            $error=$predicted-$actual
            $aggregate.quantityCount=[int]$aggregate.quantityCount+1
            $aggregate.quantityAbsoluteErrorSum=[double]$aggregate.quantityAbsoluteErrorSum+[Math]::Abs($error)
            $aggregate.quantitySquaredErrorSum=[double]$aggregate.quantitySquaredErrorSum+($error*$error)
        }
    }
}

function ConvertTo-SCAggregateSummary {
    param([object]$Aggregate)
    $anyCount=[int](Get-SCProperty $Aggregate 'anyCount')
    $targetCount=[int](Get-SCProperty $Aggregate 'targetCount')
    $quantityCount=[int](Get-SCProperty $Aggregate 'quantityCount')
    $bucketRows=New-Object System.Collections.Generic.List[object]
    foreach ($entry in @((Get-SCProperty $Aggregate 'buckets'))) {
        $count=[int](Get-SCProperty $entry 'count')
        if ($count -le 0) { continue }
        $index=[int](Get-SCProperty $entry 'index')
        $bucketRows.Add([pscustomobject]@{
            index=$index
            lower=($index/10.0)
            upper=$(if($index -eq 9){1.0}else{($index+1)/10.0})
            count=$count
            meanProbability=[Math]::Round(([double](Get-SCProperty $entry 'probabilitySum')/$count),6)
            observedRate=[Math]::Round(([double](Get-SCProperty $entry 'outcomeSum')/$count),6)
        })
    }

    return [pscustomobject]@{
        modelVersion=[string](Get-SCProperty $Aggregate 'modelVersion')
        evidenceQuality=[string](Get-SCProperty $Aggregate 'evidenceQuality')
        anyStock=[pscustomobject]@{
            count=$anyCount
            brierScore=$(if($anyCount -gt 0){[Math]::Round(([double](Get-SCProperty $Aggregate 'anyBrierSum')/$anyCount),6)}else{0.0})
            logLoss=$(if($anyCount -gt 0){[Math]::Round(([double](Get-SCProperty $Aggregate 'anyLogLossSum')/$anyCount),6)}else{0.0})
            meanProbability=$(if($anyCount -gt 0){[Math]::Round(([double](Get-SCProperty $Aggregate 'anyProbabilitySum')/$anyCount),6)}else{0.0})
            observedRate=$(if($anyCount -gt 0){[Math]::Round(([double](Get-SCProperty $Aggregate 'anyOutcomeSum')/$anyCount),6)}else{0.0})
            calibrationBuckets=$bucketRows.ToArray()
        }
        targetQuantity=[pscustomobject]@{
            count=$targetCount
            brierScore=$(if($targetCount -gt 0){[Math]::Round(([double](Get-SCProperty $Aggregate 'targetBrierSum')/$targetCount),6)}else{0.0})
            logLoss=$(if($targetCount -gt 0){[Math]::Round(([double](Get-SCProperty $Aggregate 'targetLogLossSum')/$targetCount),6)}else{0.0})
            meanProbability=$(if($targetCount -gt 0){[Math]::Round(([double](Get-SCProperty $Aggregate 'targetProbabilitySum')/$targetCount),6)}else{0.0})
            observedRate=$(if($targetCount -gt 0){[Math]::Round(([double](Get-SCProperty $Aggregate 'targetOutcomeSum')/$targetCount),6)}else{0.0})
        }
        availableQuantity=[pscustomobject]@{
            count=$quantityCount
            meanAbsoluteError=$(if($quantityCount -gt 0){[Math]::Round(([double](Get-SCProperty $Aggregate 'quantityAbsoluteErrorSum')/$quantityCount),6)}else{0.0})
            rootMeanSquaredError=$(if($quantityCount -gt 0){[Math]::Round([Math]::Sqrt([double](Get-SCProperty $Aggregate 'quantitySquaredErrorSum')/$quantityCount),6)}else{0.0})
        }
    }
}

function New-SCScoreRecord {
    param([object]$Prediction,[object]$Outcome,[long]$ResolvedAt,[string]$Status)
    return [pscustomobject]@{
        schemaVersion=1
        status=$Status
        forecastId=[string](Get-SCProperty $Prediction 'forecastId')
        modelVersion=[string](Get-SCProperty $Prediction 'modelVersion')
        forecastKind=[string](Get-SCProperty $Prediction 'forecastKind')
        marketKey=[string](Get-SCProperty $Prediction 'marketKey')
        countryId=[string](Get-SCProperty $Prediction 'countryId')
        itemId=[int](Get-SCProperty $Prediction 'itemId')
        generatedAt=[long](Get-SCProperty $Prediction 'generatedAt')
        frozenAt=[long](Get-SCProperty $Prediction 'frozenAt')
        arrivalAt=[long](Get-SCProperty $Prediction 'arrivalAt')
        horizonSeconds=[long](Get-SCProperty $Prediction 'horizonSeconds')
        resolvedAt=$ResolvedAt
        evidenceAt=[long](Get-SCProperty $Outcome 'evidenceAt')
        evidenceQuality=[string](Get-SCProperty $Prediction 'evidenceQuality')
        sampleCount=[int](Get-SCProperty $Prediction 'sampleCount')
        effectiveSampleSize=[double](Get-SCProperty $Prediction 'effectiveSampleSize')
        pAnyStock=[double](Get-SCProperty $Prediction 'pAnyStock')
        pTargetQty=[double](Get-SCProperty $Prediction 'pTargetQty')
        targetQuantity=[int](Get-SCProperty $Prediction 'targetQuantity')
        expectedQty=[double](Get-SCProperty $Prediction 'expectedQty')
        expectedAvailableQty=[double](Get-SCProperty $Prediction 'expectedAvailableQty')
        expectedProfit=[double](Get-SCProperty $Prediction 'expectedProfit')
        expectedProfitPerHour=[double](Get-SCProperty $Prediction 'expectedProfitPerHour')
        anyScorable=[bool](Get-SCProperty $Outcome 'anyScorable')
        anyStock=[int](Get-SCProperty $Outcome 'anyStock')
        targetScorable=[bool](Get-SCProperty $Outcome 'targetScorable')
        targetSuccess=[int](Get-SCProperty $Outcome 'targetSuccess')
        quantityScorable=[bool](Get-SCProperty $Outcome 'quantityScorable')
        actualQuantity=[long](Get-SCProperty $Outcome 'actualQuantity')
        outcomeReason=[string](Get-SCProperty $Outcome 'reason')
        decisionState=[string](Get-SCProperty $Prediction 'decisionState')
        travelMode=[string](Get-SCProperty $Prediction 'travelMode')
        adaptivePoint=[bool](Get-SCProperty $Prediction 'adaptivePoint')
        adaptiveSource=[string](Get-SCProperty $Prediction 'adaptiveSource')
        depletionModel=[string](Get-SCProperty $Prediction 'depletionModel')
    }
}

function Invoke-SCResolvePending {
    param(
        [object]$State,
        [hashtable]$ObservationMap,
        [hashtable]$CycleMap,
        [long]$NowEpoch,
        [int]$GraceSeconds=300,
        [int]$MaximumWaitSeconds=604800,
        [int]$ScoreLimit=2000
    )
    $remaining=New-Object System.Collections.Generic.List[object]
    $resolved=New-Object System.Collections.Generic.List[object]

    foreach ($prediction in @($State.pending)) {
        $arrival=[long](Get-SCProperty $prediction 'arrivalAt')
        if ($arrival -le 0) { continue }
        if ($NowEpoch -lt ($arrival+[Math]::Max(0,$GraceSeconds))) {
            $remaining.Add($prediction)
            continue
        }

        $key=[string](Get-SCProperty $prediction 'marketKey')
        $observations=@()
        $cycles=@()
        if ($ObservationMap.ContainsKey($key)) { $observations=@($ObservationMap[$key].ToArray()) }
        if ($CycleMap.ContainsKey($key)) { $cycles=@($CycleMap[$key].ToArray()) }

        $outcome=Get-SCConfirmedOutcome -ArrivalAt $arrival -TargetQuantity ([int](Get-SCProperty $prediction 'targetQuantity')) -Observations $observations -Cycles $cycles -AsOf $NowEpoch
        if ([bool](Get-SCProperty $outcome 'anyScorable')) {
            $score=New-SCScoreRecord -Prediction $prediction -Outcome $outcome -ResolvedAt $NowEpoch -Status 'scored'
            Add-SCScoreToAggregate -State $State -Score $score
            $resolved.Add($score)
            continue
        }

        if (($NowEpoch-$arrival) -ge [Math]::Max(3600,$MaximumWaitSeconds)) {
            $score=New-SCScoreRecord -Prediction $prediction -Outcome $outcome -ResolvedAt $NowEpoch -Status 'expired_unscorable'
            $resolved.Add($score)
            continue
        }

        $remaining.Add($prediction)
    }

    $State.pending=$remaining.ToArray()
    if ($resolved.Count -gt 0) {
        $combined=@($State.recentScores)+@($resolved.ToArray())
        if ($combined.Count -gt $ScoreLimit) { $combined=@($combined | Select-Object -Last $ScoreLimit) }
        $State.recentScores=$combined
    }
    return $resolved.ToArray()
}

function New-SCCalibrationSummary {
    param([object]$State,[long]$NowEpoch,[string]$CurrentModelVersion,[int]$FreezeSeconds,[int]$GraceSeconds,[int]$MaximumWaitSeconds)
    $models=New-Object System.Collections.Generic.List[object]
    foreach ($aggregate in @($State.aggregates)) {
        $models.Add((ConvertTo-SCAggregateSummary -Aggregate $aggregate))
    }
    return [pscustomobject]@{
        schemaVersion=1
        generatedAt=$NowEpoch
        currentModelVersion=$CurrentModelVersion
        mode='prospective_shadow_calibration'
        pendingCount=@($State.pending).Count
        recentScoreCount=@($State.recentScores).Count
        freezeIntervalSeconds=$FreezeSeconds
        outcomeGraceSeconds=$GraceSeconds
        maximumOutcomeWaitSeconds=$MaximumWaitSeconds
        methodology=[pscustomobject]@{
            forecastSelection='one best-expected-profit arrival per market/model/hour bucket'
            freezeRule='artifact must be <=5 minutes old when frozen'
            anyStockOutcome='exact provider snapshot, confirmed completed-cycle in-stock interval, or confirmed between-cycle OOS interval'
            targetQuantityOutcome='exact provider snapshot only'
            availableQuantityOutcome='exact non-conflicting provider snapshot only'
            unscorablePolicy='retain pending until maximum wait, then expire without affecting calibration metrics'
            calibrationStatus='diagnostic only; no probability transformation is applied'
        }
        models=$models.ToArray()
    }
}

if ($StochasticCalibrationSkipMain) { return }
if ($Now -le 0) { $Now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

$state=Repair-SCCalibrationState (Read-SCJson $StateFile)
$artifact=Read-SCJson $ForecastFile
$currentModelVersion=''
if ($null -ne $artifact) { $currentModelVersion=[string](Get-SCProperty $artifact 'modelVersion') }

$wanted=@{}
foreach ($prediction in @($state.pending)) {
    $arrival=[long](Get-SCProperty $prediction 'arrivalAt')
    if ($arrival -le 0 -or $Now -lt ($arrival+[Math]::Max(0,$OutcomeGraceSeconds))) { continue }
    $key=([string](Get-SCProperty $prediction 'marketKey')).Trim().ToLowerInvariant()
    if (-not [string]::IsNullOrWhiteSpace($key)) { $wanted[$key]=$true }
}

$observations=Read-SCEvidenceMap -Path $ObservationFile -Wanted $wanted -Kind observation -AsOf $Now
$cycles=Read-SCEvidenceMap -Path $CycleFile -Wanted $wanted -Kind cycle -AsOf $Now
$resolved=@(Invoke-SCResolvePending -State $state -ObservationMap $observations -CycleMap $cycles -NowEpoch $Now -GraceSeconds $OutcomeGraceSeconds -MaximumWaitSeconds $MaximumOutcomeWaitSeconds -ScoreLimit $RecentScoreLimit)

$frozen=@(Get-SCFreezeRows -Artifact $artifact -State $state -NowEpoch $Now -IntervalSeconds $FreezeIntervalSeconds)
if ($frozen.Count -gt 0) { $state.pending=@($state.pending)+@($frozen) }

$changed=($resolved.Count -gt 0 -or $frozen.Count -gt 0 -or -not (Test-Path -LiteralPath $StateFile))
if ($changed) {
    $state.updatedAt=$Now
    New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
    Write-TravelAssistantAtomicJson -Path $StateFile -Value $state -Depth 18
}

if ($changed -or -not (Test-Path -LiteralPath $SummaryFile)) {
    $summary=New-SCCalibrationSummary -State $state -NowEpoch $Now -CurrentModelVersion $currentModelVersion -FreezeSeconds $FreezeIntervalSeconds -GraceSeconds $OutcomeGraceSeconds -MaximumWaitSeconds $MaximumOutcomeWaitSeconds
    Write-TravelAssistantAtomicJson -Path $SummaryFile -Value $summary -Depth 18
}
