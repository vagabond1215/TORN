param(
    [int]$MinimumAttemptIntervalSeconds = 60,
    [int]$FailureBackoffSeconds = 900,
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
    $result=[pscustomobject]@{hasPositiveAfter=$false;known=@{}}
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
function Append-RecoveryObservation([object]$Observation){
    $line=($Observation|ConvertTo-Json -Compress -Depth 10)+[Environment]::NewLine
    $bytes=[System.Text.UTF8Encoding]::new($false).GetBytes($line)
    try{Write-RecoveryAppendBytes -Path $ObservationFile -Bytes $bytes}
    catch{Write-RecoveryAppendBytes -Path $PendingObservationFile -Bytes $bytes}
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

    $localSummary=Read-RecoveryObservationSummary -Path $ObservationFile -Country $countryId -ItemId $itemId -AfterAt $lastOos
    if([bool]$localSummary.hasPositiveAfter){continue}
    if(Test-Path -LiteralPath $PendingObservationFile){
        $pendingSummary=Read-RecoveryObservationSummary -Path $PendingObservationFile -Country $countryId -ItemId $itemId -AfterAt $lastOos
        if([bool]$pendingSummary.hasPositiveAfter){continue}
    }

    $attempt=Get-RecoveryAttempt -State $state -MarketKey $marketKey -Create
    if([long]$attempt.anchorAt -eq $lastOos -and [string]$attempt.status -in @('RECOVERED','NO_MISSED_TRANSITION')){continue}
    if([long]$attempt.lastAttemptAt -gt 0 -and ($now-[long]$attempt.lastAttemptAt) -lt $FailureBackoffSeconds -and [string]$attempt.status -eq 'ERROR'){continue}
    $countryCode=Get-RecoveryCountryCode -Countries $countries -CountryId $countryId
    if([string]::IsNullOrWhiteSpace($countryCode)){continue}
    $candidates.Add([pscustomobject]@{marketKey=$marketKey;country=$countryId;countryCode=$countryCode;itemId=$itemId;anchorAt=$lastOos;windowCloseAt=$windowClose;known=$localSummary.known})
}
if($candidates.Count -eq 0){$state.status='IDLE_NO_CANDIDATE';$state.lastError='';Save-RecoveryState $state;return}

$candidate=@($candidates.ToArray()|Sort-Object windowCloseAt,marketKey|Select-Object -First 1)[0]
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
        $normalized.Add([pscustomobject]@{at=$at;quantity=$qty;cost=$cost})
    }
    $ordered=@($normalized.ToArray()|Sort-Object at)
    $compressed=New-Object System.Collections.Generic.List[object]
    $previous=$null
    foreach($point in $ordered){if($null -eq $previous -or [long]$point.quantity -ne [long]$previous.quantity){$compressed.Add($point)};$previous=$point}

    $recovered=0;$sawPositiveAfter=$false;$previousPoint=$null
    foreach($point in $compressed.ToArray()){
        if([long]$point.at -gt [long]$candidate.anchorAt -and [long]$point.quantity -gt 0){$sawPositiveAfter=$true}
        $knownKey=([string][long]$point.at+':'+[string][long]$point.quantity)
        if($candidate.known.ContainsKey($knownKey)){$previousPoint=$point;continue}
        $prevAt=if($null -ne $previousPoint){[long]$previousPoint.at}else{0L}
        $prevQty=if($null -ne $previousPoint){[long]$previousPoint.quantity}else{-1L}
        $gap=if($prevAt -gt 0){[Math]::Max(0L,[long]$point.at-$prevAt)}else{0L}
        $kind='none';$units=0L;$lower=0L;$censored=$false
        if($prevQty -gt 0 -and [long]$point.quantity -eq 0){$kind='sellout_censored';$lower=$prevQty;$censored=$true}
        elseif($prevQty -gt [long]$point.quantity -and [long]$point.quantity -gt 0){$kind='observed_nonzero';$units=$prevQty-[long]$point.quantity;$lower=$units}
        $observation=[pscustomobject]@{
            schemaVersion=2;timestamp=[long]$point.at;sourceTimestamp=[long]$point.at
            country=[string]$candidate.country;itemId=[int]$candidate.itemId;stock=[long]$point.quantity;foreignPrice=[long]$point.cost
            source='torn_intel_history_recovery';previousFreshSourceTimestamp=$prevAt;transitionGapSeconds=$gap;transitionBoundaryQuality='recovered'
            depletionEvidence=$kind;depletionIntervalSeconds=$gap;depletionUnits=$units;depletionLowerBoundUnits=$lower;depletionCensored=$censored
            evidenceQuality='bounded_fresh';recoveryAnchorAt=[long]$candidate.anchorAt;recoveryWindowCloseAt=[long]$candidate.windowCloseAt;recoveredAt=$now
        }
        Append-RecoveryObservation -Observation $observation
        $candidate.known[$knownKey]=$true;$recovered++;$previousPoint=$point
    }
    if($sawPositiveAfter -and $recovered -gt 0){
        $attempt.status='RECOVERED';$attempt.lastSuccessAt=$now;$attempt.recoveredPoints=[int]$attempt.recoveredPoints+$recovered
        $state.status='RECOVERED';$state.lastSuccessAt=$now;$state.recoveredPoints=[int]$state.recoveredPoints+$recovered
    }else{$attempt.status='NO_MISSED_TRANSITION';$state.status='NO_MISSED_TRANSITION'}
    $attempt.lastError='';$state.lastError=''
}catch{
    $clean=([string]$_.Exception.Message).Replace([char]13,' ').Replace([char]10,' ').Trim()
    if($clean.Length -gt 600){$clean=$clean.Substring(0,600)}
    $attempt.status='ERROR';$attempt.lastError=$clean;$state.status='ERROR';$state.lastError=$clean
}
Save-RecoveryState $state
