param(
    [int]$MinimumAttemptIntervalSeconds = 60,
    [int]$FailureBackoffSeconds = 900,
    [int]$NoEvidenceRetrySeconds = 900,
    [int]$MaximumHistoryHours = 12,
    [switch]$SkipMain
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir=Join-Path $ProjectRoot 'config'
$RuntimeDir=Join-Path $ProjectRoot 'data\runtime'
$EngineStateFile=Join-Path $RuntimeDir 'engine-state.json'
$CycleFile=Join-Path $RuntimeDir 'cycles.jsonl'
$PendingCycleFile=Join-Path $RuntimeDir 'cycles.pending.jsonl'
$SeedCycleFile=Join-Path $ProjectRoot 'data\seed\cycles.jsonl'
$ObservationFile=Join-Path $RuntimeDir 'observations.jsonl'
$PendingObservationFile=Join-Path $RuntimeDir 'observations.pending.jsonl'
$RecoveryStateFile=Join-Path $RuntimeDir 'history-recovery.json'
$AtomicFileScript=Join-Path $PSScriptRoot 'AtomicFile.ps1'
$CycleForecastFilterScript=Join-Path $PSScriptRoot 'CycleForecastFilter.ps1'
if(-not(Test-Path -LiteralPath $AtomicFileScript)){throw 'AtomicFile.ps1 is required for history recovery.'}
if(-not(Test-Path -LiteralPath $CycleForecastFilterScript)){throw 'CycleForecastFilter.ps1 is required for history recovery.'}
. $AtomicFileScript
. $CycleForecastFilterScript

function Read-RecoveryJson([string]$Path){
    if(-not(Test-Path -LiteralPath $Path)){return $null}
    $raw=Read-TravelAssistantSharedText -Path $Path
    if([string]::IsNullOrWhiteSpace($raw)){return $null}
    return ($raw|ConvertFrom-Json)
}
function Get-RecoveryProperty([object]$Object,[string]$Name){
    if($null -eq $Object){return $null}
    $p=$Object.PSObject.Properties[$Name]
    if($null -eq $p){return $null}
    return $p.Value
}
function Get-RecoveryClientKey {
    $local=Read-RecoveryJson (Join-Path $ConfigDir 'settings.local.json')
    if($null -ne $local -and $local.PSObject.Properties['tornIntelClientKey']){
        $value=([string]$local.tornIntelClientKey).Trim()
        if(-not [string]::IsNullOrWhiteSpace($value)){return $value}
    }
    if(-not [string]::IsNullOrWhiteSpace($env:TORN_INTEL_CLIENT_KEY)){return ([string]$env:TORN_INTEL_CLIENT_KEY).Trim()}
    return ''
}
function Get-RecoveryCountryCode([object]$Countries,[string]$CountryId){
    $row=@($Countries.countries|Where-Object{[string]$_.id -eq $CountryId}|Select-Object -First 1)
    if($row.Count -eq 0){return ''}
    $country=$row[0]
    if($country.PSObject.Properties['providerCodes'] -and $null -ne $country.providerCodes){
        $p=$country.providerCodes.PSObject.Properties['tornIntel']
        if($null -ne $p -and -not [string]::IsNullOrWhiteSpace([string]$p.Value)){return [string]$p.Value}
        $p=$country.providerCodes.PSObject.Properties['prometheus']
        if($null -ne $p){return [string]$p.Value}
    }
    return ''
}
function Read-RecoveryCycleMap([string[]]$Paths){
    $map=@{};$seen=@{}
    foreach($path in $Paths){
        if(-not(Test-Path -LiteralPath $path)){continue}
        $reader=$null
        try{
            $reader=Open-TravelAssistantSharedTextReader -Path $path
            while(($line=$reader.ReadLine()) -ne $null){
                if([string]::IsNullOrWhiteSpace($line)){continue}
                try{$row=$line|ConvertFrom-Json}catch{continue}
                $country=[string](Get-RecoveryProperty $row 'country')
                $itemId=[int](Get-RecoveryProperty $row 'itemId')
                $delay=[long](Get-RecoveryProperty $row 'restockDelaySeconds')
                if([string]::IsNullOrWhiteSpace($country) -or $itemId -le 0 -or $delay -le 0){continue}
                if(-not(Test-CycleForecastBoundaryEvidence -Cycle $row -Purpose Forecast)){continue}
                $id=('{0}:{1}:{2}:{3}' -f $country,$itemId,[long](Get-RecoveryProperty $row 'restockAt'),[long](Get-RecoveryProperty $row 'soldOutAt'))
                if($seen.ContainsKey($id)){continue};$seen[$id]=$true
                $key=($country+':'+[string]$itemId).ToLowerInvariant()
                if(-not$map.ContainsKey($key)){$map[$key]=New-Object System.Collections.Generic.List[object]}
                $map[$key].Add($row)
            }
        }finally{if($null -ne $reader){$reader.Dispose()}}
    }
    return $map
}
function Get-RecoveryWindowSummary([object[]]$Cycles,[int]$RecentSamples=12){
    $usable=@($Cycles|Where-Object{$null -ne $_ -and [long](Get-RecoveryProperty $_ 'restockDelaySeconds') -gt 0}|Sort-Object @{Expression={[long](Get-RecoveryProperty $_ 'soldOutAt')};Descending=$true})
    if($usable.Count -eq 0){return $null}
    if($RecentSamples -gt 0 -and $usable.Count -gt $RecentSamples){$usable=@($usable|Select-Object -First $RecentSamples)}
    $delays=[long[]]@($usable|ForEach-Object{[long](Get-RecoveryProperty $_ 'restockDelaySeconds')})
    $average=[long][Math]::Round([double](($delays|Measure-Object -Average).Average))
    $minimum=[long](($delays|Measure-Object -Minimum).Minimum)
    $maximum=[long](($delays|Measure-Object -Maximum).Maximum)
    $sigma=[long](Get-CycleForecastRobustSigma -Values $delays)
    if($sigma -le 0 -and $maximum -gt $minimum){$sigma=[long][Math]::Ceiling(($maximum-$minimum)/2.0)}
    return [pscustomobject]@{sampleCount=$delays.Count;averageDelaySeconds=$average;varianceSeconds=[Math]::Max(0L,$sigma)}
}
function Read-RecoveryObservationSummary([string]$Path,[string]$Country,[int]$ItemId,[long]$AfterAt){
    $result=[pscustomobject]@{hasPositiveAfter=$false;known=@{};knownAt=@{}}
    if(-not(Test-Path -LiteralPath $Path)){return $result}
    $reader=$null
    try{
        $reader=Open-TravelAssistantSharedTextReader -Path $Path
        while(($line=$reader.ReadLine()) -ne $null){
            if([string]::IsNullOrWhiteSpace($line)){continue}
            try{$row=$line|ConvertFrom-Json}catch{continue}
            if([string](Get-RecoveryProperty $row 'country') -ne $Country){continue}
            if([int](Get-RecoveryProperty $row 'itemId') -ne $ItemId){continue}
            $at=[long](Get-RecoveryProperty $row 'sourceTimestamp');if($at -le 0){$at=[long](Get-RecoveryProperty $row 'timestamp')}
            if($at -le 0){continue}
            $stock=[long](Get-RecoveryProperty $row 'stock')
            $result.known[([string]$at+':'+[string]$stock)]=$true
            $result.knownAt[[string]$at]=$true
            if($at -gt $AfterAt -and $stock -gt 0){$result.hasPositiveAfter=$true}
        }
    }finally{if($null -ne $reader){$reader.Dispose()}}
    return $result
}
function Write-RecoveryAppendBytes([string]$Path,[byte[]]$Bytes){
    $shareValue=([int][System.IO.FileShare]::ReadWrite -bor [int][System.IO.FileShare]::Delete)
    $share=[System.IO.FileShare]$shareValue
    $mutex=New-Object System.Threading.Mutex($false,(Get-TravelAssistantAtomicMutexName -Path $Path))
    $acquired=$false
    try{
        try{$acquired=$mutex.WaitOne(5000)}catch [System.Threading.AbandonedMutexException]{$acquired=$true}
        if(-not$acquired){throw ('Timed out waiting to append history recovery evidence: '+$Path)}
        $stream=New-Object System.IO.FileStream($Path,[System.IO.FileMode]::Append,[System.IO.FileAccess]::Write,$share)
        try{$stream.Write($Bytes,0,$Bytes.Length);$stream.Flush($true)}finally{$stream.Dispose()}
    }finally{
        if($acquired){try{$mutex.ReleaseMutex()}catch{}}
        $mutex.Dispose()
    }
}
function Append-RecoveryJsonLine([string]$Path,[string]$PendingPath,[object]$Value){
    $line=($Value|ConvertTo-Json -Compress -Depth 12)+[Environment]::NewLine
    $bytes=[System.Text.UTF8Encoding]::new($false).GetBytes($line)
    try{Write-RecoveryAppendBytes -Path $Path -Bytes $bytes}
    catch{Write-RecoveryAppendBytes -Path $PendingPath -Bytes $bytes}
}
function Append-RecoveryObservation([object]$Observation){
    Append-RecoveryJsonLine -Path $ObservationFile -PendingPath $PendingObservationFile -Value $Observation
}
function Append-RecoveryCycle([object]$Cycle){
    Append-RecoveryJsonLine -Path $CycleFile -PendingPath $PendingCycleFile -Value $Cycle
}
function Invoke-TornIntelHistory([string]$ClientKey,[string]$CountryCode,[int]$ItemId,[int]$Hours,[int]$TimeoutSec=6){
    $hours=[Math]::Max(1,[Math]::Min(48,$Hours))
    $uri='https://torn-intel.com/api/v1/public/foreign-stock/history?itemId={0}&country={1}&hours={2}' -f $ItemId,[uri]::EscapeDataString($CountryCode),$hours
    return Microsoft.PowerShell.Utility\Invoke-RestMethod -Method Get -Uri $uri -Headers @{'Accept'='application/json';'X-Torn-Intel-Key'=$ClientKey;'User-Agent'='TornTravelAssistant/0.6'} -TimeoutSec $TimeoutSec
}
function Convert-RecoveryTimestamp([object]$Value){
    if($null -eq $Value){return 0L}
    $numeric=0L
    if([long]::TryParse([string]$Value,[ref]$numeric) -and $numeric -gt 0){return $numeric}
    $dto=[DateTimeOffset]::MinValue
    if([DateTimeOffset]::TryParse([string]$Value,[ref]$dto)){return $dto.ToUnixTimeSeconds()}
    return 0L
}
function Ensure-RecoveryState {
    $state=Read-RecoveryJson $RecoveryStateFile
    if($null -eq $state){$state=[pscustomobject]@{schemaVersion=1;lastAttemptAt=0;lastSuccessAt=0;lastMarketKey='';status='IDLE';lastError='';attempts=[pscustomobject]@{};recoveredPoints=0}}
    if(-not$state.PSObject.Properties['attempts']){$state|Add-Member NoteProperty attempts ([pscustomobject]@{})}
    foreach($name in @('lastAttemptAt','lastSuccessAt','recoveredPoints')){if(-not$state.PSObject.Properties[$name]){$state|Add-Member NoteProperty $name 0}}
    foreach($name in @('lastMarketKey','status','lastError')){if(-not$state.PSObject.Properties[$name]){$state|Add-Member NoteProperty $name ''}}
    return $state
}
function Save-RecoveryState([object]$State){Write-TravelAssistantAtomicJson -Path $RecoveryStateFile -Value $State -Depth 12}
function Get-RecoveryAttempt([object]$State,[string]$MarketKey,[switch]$Create){
    $p=$State.attempts.PSObject.Properties[$MarketKey]
    if($null -ne $p){return $p.Value}
    if(-not$Create){return $null}
    $row=[pscustomobject]@{anchorAt=0;windowCloseAt=0;lastAttemptAt=0;lastSuccessAt=0;status='';recoveredPoints=0;lastError=''}
    $State.attempts|Add-Member NoteProperty $MarketKey $row
    return $row
}

if($SkipMain){return}
New-Item -ItemType Directory -Force -Path $RuntimeDir|Out-Null
$now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
if($MinimumAttemptIntervalSeconds -lt 60){$MinimumAttemptIntervalSeconds=60}
if($FailureBackoffSeconds -lt 300){$FailureBackoffSeconds=300}
if($NoEvidenceRetrySeconds -lt 300){$NoEvidenceRetrySeconds=300}
if($MaximumHistoryHours -lt 1){$MaximumHistoryHours=1};if($MaximumHistoryHours -gt 48){$MaximumHistoryHours=48}
$state=Ensure-RecoveryState
$key=Get-RecoveryClientKey
if([string]::IsNullOrWhiteSpace($key)){$state.status='NO_CLIENT_KEY';$state.lastError='';Save-RecoveryState $state;return}
if([long]$state.lastAttemptAt -gt 0 -and ($now-[long]$state.lastAttemptAt) -lt $MinimumAttemptIntervalSeconds){return}

$engine=Read-RecoveryJson $EngineStateFile
$countries=Read-RecoveryJson (Join-Path $ConfigDir 'countries.json')
if($null -eq $engine -or $null -eq $countries -or -not$engine.PSObject.Properties['observedMarkets']){return}
$cycleMap=Read-RecoveryCycleMap -Paths @($CycleFile,$SeedCycleFile)
$candidates=New-Object System.Collections.Generic.List[object]
foreach($marketProperty in @($engine.observedMarkets.PSObject.Properties)){
    $marketKey=([string]$marketProperty.Name).ToLowerInvariant()
    $market=$marketProperty.Value
    if($null -eq $market -or -not$cycleMap.ContainsKey($marketKey)){continue}
    $parts=$marketKey.Split(':');if($parts.Count -ne 2){continue}
    $countryId=$parts[0];$itemId=0;if(-not[int]::TryParse($parts[1],[ref]$itemId) -or $itemId -le 0){continue}
    $dest=$null
    if($engine.PSObject.Properties['destinations']){$p=$engine.destinations.PSObject.Properties[$marketKey];if($null -ne $p){$dest=$p.Value}}
    if($null -eq $dest){continue}
    $lastOos=[long](Get-RecoveryProperty $dest 'lastSellOutAt')
    $quality=([string](Get-RecoveryProperty $dest 'lastSellOutBoundaryQuality')).Trim().ToLowerInvariant()
    if($lastOos -le 0 -or $quality -notin @('observed','bounded','recovered')){continue}
    $summary=Get-RecoveryWindowSummary -Cycles @($cycleMap[$marketKey].ToArray())
    if($null -eq $summary -or [int]$summary.sampleCount -lt 2){continue}
    $windowClose=$lastOos+[long]$summary.averageDelaySeconds+[long]$summary.varianceSeconds
    if($windowClose -le 0 -or $now -lt ($windowClose+60L)){continue}
    if(($now-$lastOos) -gt ([long]$MaximumHistoryHours*3600L)){continue}

    # A currently positive market proves this expected restock was observed on our
    # live path. Recovery is for a restock that may have appeared and sold out
    # entirely between local snapshots, leaving the current phase at zero.
    if([long](Get-RecoveryProperty $market 'lastStock') -gt 0){continue}

    $attempt=Get-RecoveryAttempt -State $state -MarketKey $marketKey -Create
    if([long]$attempt.anchorAt -eq $lastOos -and [string]$attempt.status -eq 'RECOVERED'){continue}
    if([long]$attempt.anchorAt -eq $lastOos -and [long]$attempt.lastAttemptAt -gt 0){
        $retryDelay=if([string]$attempt.status -eq 'NO_MISSED_TRANSITION'){$NoEvidenceRetrySeconds}else{$FailureBackoffSeconds}
        if([string]$attempt.status -in @('NO_MISSED_TRANSITION','ERROR') -and ($now-[long]$attempt.lastAttemptAt) -lt $retryDelay){continue}
    }
    $countryCode=Get-RecoveryCountryCode -Countries $countries -CountryId $countryId
    if([string]::IsNullOrWhiteSpace($countryCode)){continue}
    $candidates.Add([pscustomobject]@{
        marketKey=$marketKey;country=$countryId;countryCode=$countryCode;itemId=$itemId
        anchorAt=$lastOos;anchorLowerAt=[long](Get-RecoveryProperty $dest 'lastSellOutLowerBoundAt')
        anchorUpperAt=[long](Get-RecoveryProperty $dest 'lastSellOutUpperBoundAt')
        anchorQuality=$quality;windowCloseAt=$windowClose
        currentStock=[long](Get-RecoveryProperty $market 'lastStock')
        currentSourceTimestamp=[long](Get-RecoveryProperty $market 'sourceTimestamp')
        currentForeignPrice=[long](Get-RecoveryProperty $market 'lastForeignPrice')
    })
}
if($candidates.Count -eq 0){$state.status='IDLE_NO_CANDIDATE';$state.lastError='';Save-RecoveryState $state;return}

$candidate=@($candidates.ToArray()|Sort-Object windowCloseAt,marketKey|Select-Object -First 1)[0]

# Scan retained evidence only for the one request we are actually about to make.
$localSummary=Read-RecoveryObservationSummary -Path $ObservationFile -Country ([string]$candidate.country) -ItemId ([int]$candidate.itemId) -AfterAt ([long]$candidate.anchorAt)
if(Test-Path -LiteralPath $PendingObservationFile){
    $pendingSummary=Read-RecoveryObservationSummary -Path $PendingObservationFile -Country ([string]$candidate.country) -ItemId ([int]$candidate.itemId) -AfterAt ([long]$candidate.anchorAt)
    if([bool]$pendingSummary.hasPositiveAfter){
        $attempt=Get-RecoveryAttempt -State $state -MarketKey ([string]$candidate.marketKey) -Create
        $attempt.anchorAt=[long]$candidate.anchorAt;$attempt.windowCloseAt=[long]$candidate.windowCloseAt;$attempt.status='NO_MISSED_TRANSITION'
        $state.status='IDLE_LOCAL_TRANSITION';Save-RecoveryState $state;return
    }
    foreach($knownKey in @($pendingSummary.known.Keys)){$localSummary.known[$knownKey]=$true}
    foreach($knownAt in @($pendingSummary.knownAt.Keys)){$localSummary.knownAt[$knownAt]=$true}
}
if([bool]$localSummary.hasPositiveAfter){
    $attempt=Get-RecoveryAttempt -State $state -MarketKey ([string]$candidate.marketKey) -Create
    $attempt.anchorAt=[long]$candidate.anchorAt;$attempt.windowCloseAt=[long]$candidate.windowCloseAt;$attempt.status='NO_MISSED_TRANSITION'
    $state.status='IDLE_LOCAL_TRANSITION';Save-RecoveryState $state;return
}
$candidate|Add-Member NoteProperty known $localSummary.known
$candidate|Add-Member NoteProperty knownAt $localSummary.knownAt

$attempt=Get-RecoveryAttempt -State $state -MarketKey ([string]$candidate.marketKey) -Create
$attempt.anchorAt=[long]$candidate.anchorAt;$attempt.windowCloseAt=[long]$candidate.windowCloseAt;$attempt.lastAttemptAt=$now;$attempt.status='CHECKING'
$state.lastAttemptAt=$now;$state.lastMarketKey=[string]$candidate.marketKey;$state.status='CHECKING';Save-RecoveryState $state

try{
    $ageHours=[int][Math]::Ceiling(([Math]::Max(3600L,$now-[long]$candidate.anchorAt+1800L))/3600.0)
    $hours=[Math]::Max(1,[Math]::Min($MaximumHistoryHours,$ageHours))
    $payload=Invoke-TornIntelHistory -ClientKey $key -CountryCode ([string]$candidate.countryCode) -ItemId ([int]$candidate.itemId) -Hours $hours
    $points=@();if($null -ne $payload -and $payload.PSObject.Properties['points']){$points=@($payload.points)}
    $normalized=New-Object System.Collections.Generic.List[object]
    foreach($point in $points){
        $at=Convert-RecoveryTimestamp (Get-RecoveryProperty $point 't')
        $qty=[long](Get-RecoveryProperty $point 'quantity');$cost=[long](Get-RecoveryProperty $point 'cost')
        if($at -lt ([long]$candidate.anchorAt-120L) -or $at -gt $now -or $qty -lt 0){continue}
        $normalized.Add([pscustomobject]@{at=$at;quantity=$qty;cost=$cost;source='torn_intel_history_recovery'})
    }
    # If the upstream history catches a brief positive period but ends before the
    # final zero, our current fresh zero snapshot can close the recovered sequence.
    if([long]$candidate.currentStock -eq 0 -and [long]$candidate.currentSourceTimestamp -gt [long]$candidate.anchorAt){
        $normalized.Add([pscustomobject]@{
            at=[long]$candidate.currentSourceTimestamp;quantity=0L;cost=[long]$candidate.currentForeignPrice
            source='history_recovery_live_bridge'
        })
    }
    $ordered=@($normalized.ToArray()|Sort-Object at)
    $compressed=New-Object System.Collections.Generic.List[object]
    $previous=$null
    foreach($point in $ordered){if($null -eq $previous -or [long]$point.quantity -ne [long]$previous.quantity){$compressed.Add($point)};$previous=$point}

    $recovered=0;$sawPositiveAfter=$false;$previousPoint=$null
    foreach($point in $compressed.ToArray()){
        if([long]$point.at -gt [long]$candidate.anchorAt -and [long]$point.quantity -gt 0){$sawPositiveAfter=$true}
        $knownKey=([string][long]$point.at+':'+[string][long]$point.quantity)
        if($candidate.known.ContainsKey($knownKey) -or $candidate.knownAt.ContainsKey([string][long]$point.at)){$previousPoint=$point;continue}
        $prevAt=if($null -ne $previousPoint){[long]$previousPoint.at}else{0L}
        $prevQty=if($null -ne $previousPoint){[long]$previousPoint.quantity}else{-1L}
        $gap=if($prevAt -gt 0){[Math]::Max(0L,[long]$point.at-$prevAt)}else{0L}
        $kind='none';$units=0L;$lower=0L;$censored=$false
        if($prevQty -gt 0 -and [long]$point.quantity -eq 0){$kind='sellout_censored';$lower=$prevQty;$censored=$true}
        elseif($prevQty -gt [long]$point.quantity -and [long]$point.quantity -gt 0){$kind='observed_nonzero';$units=$prevQty-[long]$point.quantity;$lower=$units}
        $observation=[pscustomobject]@{
            schemaVersion=2;timestamp=[long]$point.at;sourceTimestamp=[long]$point.at
            country=[string]$candidate.country;itemId=[int]$candidate.itemId;stock=[long]$point.quantity;foreignPrice=[long]$point.cost
            source=[string]$point.source;previousFreshSourceTimestamp=$prevAt;transitionGapSeconds=$gap;transitionBoundaryQuality='recovered'
            depletionEvidence=$kind;depletionIntervalSeconds=$gap;depletionUnits=$units;depletionLowerBoundUnits=$lower;depletionCensored=$censored
            evidenceQuality='bounded_fresh';recoveryAnchorAt=[long]$candidate.anchorAt;recoveryWindowCloseAt=[long]$candidate.windowCloseAt;recoveredAt=$now
        }
        Append-RecoveryObservation -Observation $observation
        $candidate.known[$knownKey]=$true;$candidate.knownAt[[string][long]$point.at]=$true;$recovered++;$previousPoint=$point
    }
    $recoveredCycle=$null
    if($sawPositiveAfter){
        $sequence=New-Object System.Collections.Generic.List[object]
        $sequence.Add([pscustomobject]@{
            at=[long]$candidate.anchorAt;quantity=0L;cost=[long]$candidate.currentForeignPrice;source='local_verified_oos_anchor'
        })
        foreach($point in $compressed.ToArray()){
            if([long]$point.at -gt [long]$candidate.anchorAt){$sequence.Add($point)}
        }
        $restockPoint=$null;$selloutPoint=$null;$beforeRestock=$null;$beforeSellout=$null;$previousSequence=$null
        foreach($point in @($sequence.ToArray()|Sort-Object at)){
            if($null -eq $restockPoint -and [long]$point.quantity -gt 0){
                $restockPoint=$point;$beforeRestock=$previousSequence
            }elseif($null -ne $restockPoint -and $null -eq $selloutPoint -and [long]$point.at -gt [long]$restockPoint.at -and [long]$point.quantity -eq 0){
                $selloutPoint=$point;$beforeSellout=$previousSequence;break
            }
            $previousSequence=$point
        }
        if($null -ne $restockPoint -and $null -ne $selloutPoint){
            $restockAt=[long]$restockPoint.at;$soldOutAt=[long]$selloutPoint.at
            $restockLower=if($null -ne $beforeRestock){[long]$beforeRestock.at}else{[long]$candidate.anchorAt}
            $restockUpper=$restockAt
            $selloutLower=if($null -ne $beforeSellout){[long]$beforeSellout.at}else{$restockAt}
            $selloutUpper=$soldOutAt
            $anchorLower=if([long]$candidate.anchorLowerAt -gt 0){[long]$candidate.anchorLowerAt}else{[long]$candidate.anchorAt}
            $anchorUpper=if([long]$candidate.anchorUpperAt -gt 0){[long]$candidate.anchorUpperAt}else{[long]$candidate.anchorAt}
            $delayMin=[Math]::Max(0L,$restockLower-$anchorUpper)
            $delayMax=[Math]::Max(0L,$restockUpper-$anchorLower)
            $availabilityMin=[Math]::Max(0L,$selloutLower-$restockUpper)
            $availabilityMax=[Math]::Max(0L,$selloutUpper-$restockLower)
            $availabilityEligible=($availabilityMin -gt 0)
            $restockDelayEligible=($delayMax -gt 0)
            $forecastEligible=($availabilityEligible -and $restockDelayEligible)
            $existing=@($cycleMap[[string]$candidate.marketKey].ToArray()|Where-Object{
                [long](Get-RecoveryProperty $_ 'restockAt') -eq $restockAt -and [long](Get-RecoveryProperty $_ 'soldOutAt') -eq $soldOutAt
            })
            if($existing.Count -eq 0){
                $price=[long]$restockPoint.cost
                $recoveredCycle=[pscustomobject]@{
                    schemaVersion=2;country=[string]$candidate.country;itemId=[int]$candidate.itemId
                    foreignPrice=$price;minimumForeignPrice=$price;maximumForeignPrice=$price
                    restockAt=$restockAt;restockLowerBoundAt=$restockLower;restockUpperBoundAt=$restockUpper;restockBoundaryQuality='recovered'
                    restockQuantity=[long]$restockPoint.quantity
                    soldOutAt=$soldOutAt;soldOutLowerBoundAt=$selloutLower;soldOutUpperBoundAt=$selloutUpper;soldOutBoundaryQuality='recovered'
                    availabilitySeconds=[Math]::Max(0L,$soldOutAt-$restockAt)
                    availabilityMinimumSeconds=$availabilityMin;availabilityMaximumSeconds=$availabilityMax;availabilityEligible=$availabilityEligible
                    previousSoldOutAt=[long]$candidate.anchorAt;previousSoldOutLowerBoundAt=$anchorLower;previousSoldOutUpperBoundAt=$anchorUpper
                    previousSellOutBoundaryQuality=[string]$candidate.anchorQuality
                    restockDelaySeconds=$(if($restockDelayEligible){[Math]::Max(0L,$restockAt-[long]$candidate.anchorAt)}else{0L})
                    restockDelayMinimumSeconds=$delayMin;restockDelayMaximumSeconds=$delayMax;restockDelayEligible=$restockDelayEligible
                    trendEligible=$forecastEligible;forecastEligible=$forecastEligible
                    evidenceQuality=$(if($forecastEligible){'bounded_fresh'}else{'incomplete'});isRightCensored=$false
                    selloutDepletionEvidence='sellout_censored'
                    selloutDemandLowerBoundUnits=$(if($null -ne $beforeSellout){[Math]::Max(0L,[long]$beforeSellout.quantity)}else{0L})
                    source='torn_intel_history_recovery';recoveredAt=$now;recoveryWindowCloseAt=[long]$candidate.windowCloseAt
                }
                Append-RecoveryCycle -Cycle $recoveredCycle
                $cycleMap[[string]$candidate.marketKey].Add($recoveredCycle)
            }
        }
    }

    if($sawPositiveAfter -and $recovered -gt 0){
        $attempt.status='RECOVERED';$attempt.lastSuccessAt=$now;$attempt.recoveredPoints=[int]$attempt.recoveredPoints+$recovered
        $state.status=$(if($null -ne $recoveredCycle){'RECOVERED_CYCLE'}else{'RECOVERED'})
        $state.lastSuccessAt=$now;$state.recoveredPoints=[int]$state.recoveredPoints+$recovered
    }else{$attempt.status='NO_MISSED_TRANSITION';$state.status='NO_MISSED_TRANSITION'}
    $attempt.lastError='';$state.lastError=''
}catch{
    $clean=([string]$_.Exception.Message).Replace([char]13,' ').Replace([char]10,' ').Trim()
    if($clean.Length -gt 600){$clean=$clean.Substring(0,600)}
    $attempt.status='ERROR';$attempt.lastError=$clean;$state.status='ERROR';$state.lastError=$clean
}
Save-RecoveryState $state
