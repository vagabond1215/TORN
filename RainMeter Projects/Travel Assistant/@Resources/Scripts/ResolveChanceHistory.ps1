param(
    [Alias('SkipMain')]
    [switch]$ResolveChanceHistorySkipMain,
    [long]$Now = 0,
    [ValidateRange(1,24)]
    [int]$RetentionHours = 8,
    [ValidateRange(0,1800)]
    [int]$OutcomeGraceSeconds = 120
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RuntimeDir=Join-Path $ProjectRoot 'data\runtime'
$ChanceHistoryFile=Join-Path $RuntimeDir 'chance-history.jsonl'
$ResolvedFile=Join-Path $RuntimeDir 'resolved-arrival-history.jsonl'
$SummaryFile=Join-Path $RuntimeDir 'chance-accuracy.json'
$ObservationFile=Join-Path $RuntimeDir 'observations.jsonl'
$CycleFile=Join-Path $RuntimeDir 'cycles.jsonl'
$CalibrationScript=Join-Path $PSScriptRoot 'StochasticCalibration.ps1'
if (-not (Test-Path -LiteralPath $CalibrationScript)) { throw 'StochasticCalibration.ps1 is required for shared confirmed-outcome semantics.' }
. $CalibrationScript -SkipMain

function Get-RCHProperty {
    param([object]$Object,[string]$Name)
    if($null -eq $Object){return $null}
    $property=$Object.PSObject.Properties[$Name]
    if($null -eq $property){return $null}
    return $property.Value
}

function Get-RCHForecastAt {
    param([object]$Row)
    $at=[long](Get-RCHProperty $Row 'forecastAt')
    if($at -le 0){$at=[long](Get-RCHProperty $Row 'timestamp')}
    return $at
}

function Get-RCHIdentity {
    param([object]$Row)
    $key=([string](Get-RCHProperty $Row 'marketKey')).Trim().ToLowerInvariant()
    $forecastAt=Get-RCHForecastAt -Row $Row
    $arrivalAt=[long](Get-RCHProperty $Row 'arrivalAt')
    $source=([string](Get-RCHProperty $Row 'source')).Trim().ToLowerInvariant()
    $model=([string](Get-RCHProperty $Row 'modelVersion')).Trim().ToLowerInvariant()
    if([string]::IsNullOrWhiteSpace($key) -or $forecastAt -le 0 -or $arrivalAt -le 0){return ''}
    return ($key+'|'+[string]$forecastAt+'|'+[string]$arrivalAt+'|'+$source+'|'+$model)
}

function Read-RCHRows {
    param([string]$Path,[long]$Cutoff,[long]$MaximumForecastAt=0L)
    $rows=New-Object System.Collections.Generic.List[object]
    if(-not(Test-Path -LiteralPath $Path)){return $rows.ToArray()}
    $reader=$null
    try{
        $reader=Open-TravelAssistantSharedTextReader -Path $Path
        while(($line=$reader.ReadLine()) -ne $null){
            if([string]::IsNullOrWhiteSpace($line)){continue}
            try{$row=$line|ConvertFrom-Json}catch{continue}
            $forecastAt=Get-RCHForecastAt -Row $row
            if($forecastAt -lt $Cutoff){continue}
            if($MaximumForecastAt -gt 0 -and $forecastAt -gt $MaximumForecastAt){continue}
            $rows.Add($row)
        }
    }finally{
        if($null -ne $reader){$reader.Dispose()}
    }
    return $rows.ToArray()
}

function Write-RCHJsonLines {
    param([string]$Path,[object[]]$Rows)
    $tmp=New-TravelAssistantAtomicTempPath -Path $Path
    $writer=$null
    try{
        New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent)|Out-Null
        $writer=New-Object System.IO.StreamWriter($tmp,$false,[System.Text.UTF8Encoding]::new($false))
        foreach($row in @($Rows|Sort-Object forecastAt,marketKey)){
            $writer.WriteLine(($row|ConvertTo-Json -Compress -Depth 8))
        }
        $writer.Flush()
        $writer.Dispose()
        $writer=$null
        Publish-TravelAssistantAtomicTempFile -TempPath $tmp -Path $Path
    }finally{
        if($null -ne $writer){$writer.Dispose()}
        if(Test-Path -LiteralPath $tmp){Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue}
    }
}

function New-RCHAggregate {
    param([object[]]$Rows,[string]$ScopeType,[string]$ScopeValue)
    $scored=@($Rows|Where-Object{[string](Get-RCHProperty $_ 'status') -eq 'scored'})
    $count=$scored.Count
    if($count -eq 0){
        return [pscustomobject]@{
            scopeType=$ScopeType;scopeValue=$ScopeValue;count=0
            brierScore=$null;rootBrierScore=$null;logLoss=$null
            meanAbsoluteOutcomeError=$null;classificationAccuracy=$null
            meanPredictedProbability=$null;observedHitRate=$null;calibrationGap=$null
        }
    }
    $brier=0.0;$logLoss=0.0;$absolute=0.0;$correct=0;$predicted=0.0;$observed=0.0
    foreach($row in $scored){
        $brier+=[double](Get-RCHProperty $row 'brier')
        $logLoss+=[double](Get-RCHProperty $row 'logLoss')
        $absolute+=[double](Get-RCHProperty $row 'absoluteOutcomeError')
        $correct+=[int](Get-RCHProperty $row 'classificationCorrect')
        $predicted+=[double](Get-RCHProperty $row 'predictedProbability')
        $observed+=[double](Get-RCHProperty $row 'actualAnyStock')
    }
    $meanPred=$predicted/$count
    $hitRate=$observed/$count
    $meanBrier=$brier/$count
    return [pscustomobject]@{
        scopeType=$ScopeType
        scopeValue=$ScopeValue
        count=$count
        brierScore=[Math]::Round($meanBrier,6)
        rootBrierScore=[Math]::Round([Math]::Sqrt([Math]::Max(0.0,$meanBrier)),6)
        logLoss=[Math]::Round($logLoss/$count,6)
        meanAbsoluteOutcomeError=[Math]::Round($absolute/$count,6)
        classificationAccuracy=[Math]::Round($correct/[double]$count,6)
        meanPredictedProbability=[Math]::Round($meanPred,6)
        observedHitRate=[Math]::Round($hitRate,6)
        calibrationGap=[Math]::Round($meanPred-$hitRate,6)
    }
}

function New-RCHSummary {
    param([object[]]$Rows,[long]$NowEpoch,[long]$WindowStart)
    $markets=New-Object System.Collections.Generic.List[object]
    foreach($key in @($Rows|ForEach-Object{([string](Get-RCHProperty $_ 'marketKey')).Trim().ToLowerInvariant()}|Where-Object{-not[string]::IsNullOrWhiteSpace($_)}|Sort-Object -Unique)){
        $marketRows=@($Rows|Where-Object{([string](Get-RCHProperty $_ 'marketKey')).Trim().ToLowerInvariant() -eq $key})
        $sources=New-Object System.Collections.Generic.List[object]
        foreach($source in @($marketRows|ForEach-Object{([string](Get-RCHProperty $_ 'source')).Trim().ToLowerInvariant()}|Where-Object{-not[string]::IsNullOrWhiteSpace($_)}|Sort-Object -Unique)){
            $sourceRows=@($marketRows|Where-Object{([string](Get-RCHProperty $_ 'source')).Trim().ToLowerInvariant() -eq $source})
            $sources.Add((New-RCHAggregate -Rows $sourceRows -ScopeType 'source' -ScopeValue $source))
        }
        $aggregate=New-RCHAggregate -Rows $marketRows -ScopeType 'market' -ScopeValue $key
        $markets.Add([pscustomobject]@{
            marketKey=$key
            count=$aggregate.count
            brierScore=$aggregate.brierScore
            rootBrierScore=$aggregate.rootBrierScore
            logLoss=$aggregate.logLoss
            meanAbsoluteOutcomeError=$aggregate.meanAbsoluteOutcomeError
            classificationAccuracy=$aggregate.classificationAccuracy
            meanPredictedProbability=$aggregate.meanPredictedProbability
            observedHitRate=$aggregate.observedHitRate
            calibrationGap=$aggregate.calibrationGap
            bySource=$sources.ToArray()
        })
    }
    return [pscustomobject]@{
        schemaVersion=1
        generatedAt=[long]$NowEpoch
        windowStartAt=[long]$WindowStart
        retentionHours=[Math]::Round(($NowEpoch-$WindowStart)/3600.0,3)
        methodology=[pscustomobject]@{
            alignment='forecast recorded before arrival; outcome resolved later at its flight-aligned arrival timestamp'
            truth='same confirmed exact/cycle/continuity semantics as StochasticCalibration.ps1'
            brier='raw probability against binary any-stock outcome'
            logLoss='epsilon-clipped only for numerical stability'
            classificationThreshold=0.5
            futureLeakage='future evidence is used only to label the later outcome, never to alter the frozen probability'
        }
        overall=(New-RCHAggregate -Rows $Rows -ScopeType 'all' -ScopeValue 'all')
        markets=$markets.ToArray()
    }
}

function Resolve-RCHForecasts {
    param(
        [object[]]$ChanceRows,
        [object[]]$ExistingResolved,
        [long]$NowEpoch,
        [int]$GraceSeconds
    )

    $resolved=@{}
    foreach($row in @($ExistingResolved)){
        $identity=Get-RCHIdentity -Row $row
        if(-not[string]::IsNullOrWhiteSpace($identity)){$resolved[$identity]=$row}
    }

    $mature=@($ChanceRows|Where-Object{
        $forecastAt=Get-RCHForecastAt -Row $_
        $arrivalAt=[long](Get-RCHProperty $_ 'arrivalAt')
        $forecastAt -gt 0 -and $arrivalAt -gt $forecastAt -and $arrivalAt -le ($NowEpoch-[Math]::Max(0,$GraceSeconds))
    })
    $wanted=@{}
    foreach($row in $mature){
        $identity=Get-RCHIdentity -Row $row
        if([string]::IsNullOrWhiteSpace($identity) -or $resolved.ContainsKey($identity)){continue}
        $key=([string](Get-RCHProperty $row 'marketKey')).Trim().ToLowerInvariant()
        if(-not[string]::IsNullOrWhiteSpace($key)){$wanted[$key]=$true}
    }
    if($wanted.Count -eq 0){return @($resolved.Values)}

    $observationMap=Read-SCEvidenceMap -Path $ObservationFile -Wanted $wanted -Kind observation -AsOf $NowEpoch
    $cycleMap=Read-SCEvidenceMap -Path $CycleFile -Wanted $wanted -Kind cycle -AsOf $NowEpoch

    foreach($forecast in $mature){
        $identity=Get-RCHIdentity -Row $forecast
        if([string]::IsNullOrWhiteSpace($identity) -or $resolved.ContainsKey($identity)){continue}
        $key=([string](Get-RCHProperty $forecast 'marketKey')).Trim().ToLowerInvariant()
        $arrivalAt=[long](Get-RCHProperty $forecast 'arrivalAt')
        $target=[int](Get-RCHProperty $forecast 'targetQuantity')
        if($target -lt 1){$target=1}
        $observations=@()
        if($observationMap.ContainsKey($key)){$observations=@($observationMap[$key].ToArray())}
        $cycles=@()
        if($cycleMap.ContainsKey($key)){$cycles=@($cycleMap[$key].ToArray())}

        $outcome=Get-SCConfirmedOutcome -ArrivalAt $arrivalAt -TargetQuantity $target -Observations $observations -Cycles $cycles -AsOf $NowEpoch
        if(-not[bool]$outcome.anyScorable){continue}

        $p=[double](Get-RCHProperty $forecast 'probability')
        if($p -lt 0.0 -or $p -gt 1.0){continue}
        $y=[int]$outcome.anyStock
        $logP=[Math]::Max(0.000001,[Math]::Min(0.999999,$p))
        $brier=[Math]::Pow($p-$y,2)
        $logLoss=-($y*[Math]::Log($logP)+(1-$y)*[Math]::Log(1-$logP))
        $predictedClass=if($p -ge 0.5){1}else{0}

        $resolved[$identity]=[pscustomobject]@{
            schemaVersion=1
            status='scored'
            forecastId=$identity
            marketKey=$key
            country=[string](Get-RCHProperty $forecast 'country')
            itemId=[int](Get-RCHProperty $forecast 'itemId')
            forecastAt=[long](Get-RCHForecastAt -Row $forecast)
            departureAt=[long](Get-RCHProperty $forecast 'departureAt')
            arrivalAt=$arrivalAt
            flightSeconds=[long](Get-RCHProperty $forecast 'flightSeconds')
            travelMode=[string](Get-RCHProperty $forecast 'travelMode')
            source=[string](Get-RCHProperty $forecast 'source')
            modelVersion=[string](Get-RCHProperty $forecast 'modelVersion')
            targetQuantity=$target
            predictedProbability=[Math]::Round($p,6)
            actualAnyStock=$y
            targetScorable=[bool]$outcome.targetScorable
            actualTargetSuccess=[int]$outcome.targetSuccess
            quantityScorable=[bool]$outcome.quantityScorable
            actualQuantity=[long]$outcome.actualQuantity
            outcomeReason=[string]$outcome.reason
            outcomeEvidenceAt=[long]$outcome.evidenceAt
            resolvedAt=[long]$NowEpoch
            probabilityError=[Math]::Round($p-$y,6)
            absoluteOutcomeError=[Math]::Round([Math]::Abs($p-$y),6)
            brier=[Math]::Round($brier,6)
            logLoss=[Math]::Round($logLoss,6)
            predictedClass=$predictedClass
            classificationCorrect=$(if($predictedClass -eq $y){1}else{0})
        }
    }
    return @($resolved.Values)
}

if($ResolveChanceHistorySkipMain){return}
if($Now -le 0){$Now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()}
$cutoff=$Now-([long][Math]::Max(1,$RetentionHours)*3600L)
$chanceRows=@(Read-RCHRows -Path $ChanceHistoryFile -Cutoff $cutoff -MaximumForecastAt $Now)
$existing=@(Read-RCHRows -Path $ResolvedFile -Cutoff $cutoff -MaximumForecastAt $Now)
$resolved=@(Resolve-RCHForecasts -ChanceRows $chanceRows -ExistingResolved $existing -NowEpoch $Now -GraceSeconds $OutcomeGraceSeconds)
Write-RCHJsonLines -Path $ResolvedFile -Rows $resolved
$summary=New-RCHSummary -Rows $resolved -NowEpoch $Now -WindowStart $cutoff
Write-TravelAssistantAtomicJson -Path $SummaryFile -Value $summary -Depth 12
