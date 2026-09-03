param(
    [Alias('SkipMain')]
    [switch]$ChanceHistorySkipMain,
    [long]$Now = 0,
    [ValidateRange(1,24)]
    [int]$RetentionHours = 8,
    [ValidateRange(15,300)]
    [int]$SampleBucketSeconds = 60
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RuntimeDir=Join-Path $ProjectRoot 'data\runtime'
$GeneratedDir=Join-Path $ProjectRoot '@Resources\Generated'
$StateKvFile=Join-Path $GeneratedDir 'state.kv'
$HistoryFile=Join-Path $RuntimeDir 'chance-history.jsonl'
$AtomicFileScript=Join-Path $PSScriptRoot 'AtomicFile.ps1'
if (-not (Test-Path -LiteralPath $AtomicFileScript)) { throw 'AtomicFile.ps1 is required for chance-history IO.' }
. $AtomicFileScript

function Read-CHStateKv {
    param([string]$Path)
    $values=@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    $reader=$null
    try {
        $reader=Open-TravelAssistantSharedTextReader -Path $Path
        while (($line=$reader.ReadLine()) -ne $null) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            $eq=$line.IndexOf('=')
            if ($eq -lt 1) { continue }
            $key=$line.Substring(0,$eq).Trim([char]0xFEFF).Trim()
            $values[$key]=$line.Substring($eq+1).Trim()
        }
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
    }
    return $values
}

function Get-CHDouble {
    param([hashtable]$State,[string]$Key,[double]$Default=-1.0)
    if ($null -eq $State -or -not $State.ContainsKey($Key)) { return $Default }
    $value=0.0
    if ([double]::TryParse([string]$State[$Key],[System.Globalization.NumberStyles]::Float,[System.Globalization.CultureInfo]::InvariantCulture,[ref]$value)) { return $value }
    if ([double]::TryParse([string]$State[$Key],[ref]$value)) { return $value }
    return $Default
}

function Get-CHLong {
    param([hashtable]$State,[string]$Key,[long]$Default=0L)
    if ($null -eq $State -or -not $State.ContainsKey($Key)) { return $Default }
    $value=0L
    if ([long]::TryParse([string]$State[$Key],[ref]$value)) { return $value }
    return $Default
}

function Get-CHTravelSeconds {
    param([hashtable]$State,[string]$Country)
    $countryId=([string]$Country).Trim().ToLowerInvariant()
    $key=if($countryId -eq 'united_kingdom'){'UKTravelSeconds'}elseif($countryId -eq 'japan'){'JPTravelSeconds'}else{$countryId.ToUpperInvariant()+'TravelSeconds'}
    return Get-CHLong -State $State -Key $key -Default 0L
}

function Get-CHArrivalPlan {
    param([hashtable]$State,[string]$Country,[long]$NowEpoch,[long]$OneWaySeconds)
    $travelState=([string]$State['TravelState']).Trim().ToLowerInvariant()
    $destination=([string]$State['TravelDestinationCountryId']).Trim().ToLowerInvariant()
    $countryId=([string]$Country).Trim().ToLowerInvariant()
    $left=Get-CHLong -State $State -Key 'TravelTimeLeft' -Default 0L

    if($travelState -in @('traveling_unknown','abroad_unknown','unknown')){
        return [pscustomobject]@{feasible=$false;travelMode='unknown';departureAt=0L;arrivalAt=0L}
    }
    if($travelState -in @('traveling','outbound','outbound_to_target')){
        if([string]::IsNullOrWhiteSpace($destination) -or $destination -ne $countryId){
            return [pscustomobject]@{feasible=$false;travelMode='traveling_elsewhere';departureAt=0L;arrivalAt=0L}
        }
        return [pscustomobject]@{feasible=$true;travelMode='committed';departureAt=0L;arrivalAt=[long]($NowEpoch+[Math]::Max(0L,$left))}
    }
    if($travelState -in @('abroad','foreign','abroad_at_target')){
        return [pscustomobject]@{feasible=$false;travelMode='already_abroad';departureAt=0L;arrivalAt=0L}
    }
    if($OneWaySeconds -le 0){
        return [pscustomobject]@{feasible=$false;travelMode='missing_travel_time';departureAt=0L;arrivalAt=0L}
    }
    $departure=$NowEpoch
    if($travelState -eq 'returning'){$departure=$NowEpoch+[Math]::Max(0L,$left)}
    elseif($travelState -notin @('home','torn','in_torn','')){
        return [pscustomobject]@{feasible=$false;travelMode='unsupported';departureAt=0L;arrivalAt=0L}
    }
    return [pscustomobject]@{
        feasible=$true
        travelMode=$(if($travelState -eq 'returning'){'returning'}else{'home'})
        departureAt=[long]$departure
        arrivalAt=[long]($departure+$OneWaySeconds)
    }
}

function ConvertTo-CHLine {
    param([object]$Value)
    return ($Value | ConvertTo-Json -Compress -Depth 6)
}

function Get-CHIdentity {
    param([object]$Row,[int]$BucketSeconds)
    if ($null -eq $Row) { return '' }
    $marketKey=''
    $timestamp=0L
    if ($Row.PSObject.Properties['marketKey']) { $marketKey=([string]$Row.marketKey).Trim().ToLowerInvariant() }
    if ($Row.PSObject.Properties['timestamp']) { $timestamp=[long]$Row.timestamp }
    if ([string]::IsNullOrWhiteSpace($marketKey) -or $timestamp -le 0) { return '' }
    $bucket=[long][Math]::Floor($timestamp/[double][Math]::Max(15,$BucketSeconds))
    return ($marketKey+'|'+[string]$bucket)
}

function Write-CHHistory {
    param(
        [string]$Path,
        [object[]]$CurrentRows,
        [long]$Cutoff,
        [long]$MaximumTimestamp,
        [int]$BucketSeconds
    )

    $byIdentity=@{}
    if (Test-Path -LiteralPath $Path) {
        $reader=$null
        try {
            $reader=Open-TravelAssistantSharedTextReader -Path $Path
            while (($line=$reader.ReadLine()) -ne $null) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                try { $row=$line | ConvertFrom-Json } catch { continue }
                $timestamp=if ($row.PSObject.Properties['timestamp']) { [long]$row.timestamp } else { 0L }
                if ($timestamp -lt $Cutoff -or $timestamp -gt $MaximumTimestamp) { continue }
                $identity=Get-CHIdentity -Row $row -BucketSeconds $BucketSeconds
                if ([string]::IsNullOrWhiteSpace($identity)) { continue }
                if (-not $byIdentity.ContainsKey($identity) -or [long]$byIdentity[$identity].timestamp -le $timestamp) {
                    $byIdentity[$identity]=$row
                }
            }
        } finally {
            if ($null -ne $reader) { $reader.Dispose() }
        }
    }

    foreach ($row in @($CurrentRows)) {
        $identity=Get-CHIdentity -Row $row -BucketSeconds $BucketSeconds
        if ([string]::IsNullOrWhiteSpace($identity)) { continue }
        $byIdentity[$identity]=$row
    }

    $tmp=New-TravelAssistantAtomicTempPath -Path $Path
    $writer=$null
    try {
        New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
        $writer=New-Object System.IO.StreamWriter($tmp,$false,[System.Text.UTF8Encoding]::new($false))
        foreach ($row in @($byIdentity.Values | Sort-Object timestamp,marketKey)) {
            $writer.WriteLine((ConvertTo-CHLine -Value $row))
        }
        $writer.Flush()
        $writer.Dispose()
        $writer=$null
        Publish-TravelAssistantAtomicTempFile -TempPath $tmp -Path $Path
    } finally {
        if ($null -ne $writer) { $writer.Dispose() }
        if (Test-Path -LiteralPath $tmp) { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
    }
}

if ($ChanceHistorySkipMain) { return }
if ($Now -le 0) { $Now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

$state=Read-CHStateKv -Path $StateKvFile
if ($state.Count -eq 0) { return }

$count=0
[void][int]::TryParse([string]$state['OpportunityCount'],[ref]$count)
$count=[Math]::Max(0,[Math]::Min(256,$count))
$current=New-Object System.Collections.Generic.List[object]

for ($i=1; $i -le $count; $i++) {
    $prefix='Opportunity'+$i
    $key=([string]$state[$prefix+'Key']).Trim().ToLowerInvariant()
    if ([string]::IsNullOrWhiteSpace($key)) { continue }

    $parts=@($key -split ':',2)
    $country=if($parts.Count -gt 0){[string]$parts[0]}else{''}
    $itemId=0
    if($parts.Count -gt 1){[void][int]::TryParse([string]$parts[1],[ref]$itemId)}
    $oneWay=Get-CHTravelSeconds -State $state -Country $country
    $arrivalPlan=Get-CHArrivalPlan -State $state -Country $country -NowEpoch $Now -OneWaySeconds $oneWay

    $probability=-1.0
    $source=''
    $modelVersion=''
    $arrivalAt=0L
    $departureAt=0L
    $travelMode=[string]$arrivalPlan.travelMode
    $ratio=0.0
    $sampleCount=0
    $targetQuantity=1
    $quantityText=[string]$state[$prefix+'QuantityText']
    if($quantityText -match '([1-9][0-9]*)'){$targetQuantity=[int]$Matches[1]}

    $multiEligible=(Get-CHLong -State $state -Key ($prefix+'MultiCycleChanceEligible')) -gt 0
    $multiProbability=Get-CHDouble -State $state -Key ($prefix+'MultiCycleChanceProbability')
    if ($multiEligible -and $multiProbability -ge 0.0 -and $multiProbability -le 1.0) {
        $probability=$multiProbability
        $source='multi_cycle_arrival'
        $modelVersion=([string]$state[$prefix+'MultiCycleModelVersion']).Trim()
        $arrivalAt=Get-CHLong -State $state -Key ($prefix+'MultiCycleArrivalAt')
        $departureAt=[long]$arrivalPlan.departureAt
        $ratio=Get-CHDouble -State $state -Key ($prefix+'MultiCycleArrivalCycleRatio') -Default 0.0
        $sampleCount=[int](Get-CHLong -State $state -Key ($prefix+'MultiCycleSampleCount'))
    } else {
        # ProbabilityValue may describe a recommended future Safe/Best window.
        # Replay needs the probability for the physically earliest arrival instead.
        $legacyProbability=Get-CHDouble -State $state -Key ($prefix+'ImmediateArrivalProbabilityValue')
        $legacyArrivalAt=Get-CHLong -State $state -Key ($prefix+'ImmediateArrivalAt')
        if ($legacyProbability -ge 0.0 -and $legacyProbability -le 1.0 -and [bool]$arrivalPlan.feasible) {
            $probability=$legacyProbability
            $source='legacy_immediate_arrival'
            $modelVersion='window-plan-immediate'
            $departureAt=[long]$arrivalPlan.departureAt
            $arrivalAt=if($legacyArrivalAt -gt $Now){$legacyArrivalAt}else{[long]$arrivalPlan.arrivalAt}
        }
    }
    # Only journal genuinely prospective travel forecasts. A current-state value
    # with no future arrival cannot later be scored as a travel prediction.
    if ($probability -lt 0.0 -or $probability -gt 1.0 -or $arrivalAt -le $Now) { continue }

    $current.Add([pscustomobject]@{
        schemaVersion=1
        timestamp=[long]$Now
        forecastAt=[long]$Now
        departureAt=[long]$departureAt
        arrivalAt=[long]$arrivalAt
        flightSeconds=[long]$oneWay
        travelMode=$travelMode
        targetQuantity=[int]$targetQuantity
        marketKey=$key
        country=$country
        itemId=$itemId
        probability=[Math]::Round([double]$probability,6)
        source=$source
        modelVersion=$modelVersion
        arrivalCycleRatio=[Math]::Round([double]$ratio,6)
        sampleCount=[int]$sampleCount
    })
}

$cutoff=$Now-([long][Math]::Max(1,$RetentionHours)*3600L)
Write-CHHistory -Path $HistoryFile -CurrentRows $current.ToArray() -Cutoff $cutoff -MaximumTimestamp ($Now+60L) -BucketSeconds $SampleBucketSeconds
