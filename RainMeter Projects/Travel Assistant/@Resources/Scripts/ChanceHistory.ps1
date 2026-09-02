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

    $probability=-1.0
    $source=''
    $modelVersion=''
    $arrivalAt=0L
    $ratio=0.0
    $sampleCount=0

    $multiEligible=(Get-CHLong -State $state -Key ($prefix+'MultiCycleChanceEligible')) -gt 0
    $multiProbability=Get-CHDouble -State $state -Key ($prefix+'MultiCycleChanceProbability')
    if ($multiEligible -and $multiProbability -ge 0.0 -and $multiProbability -le 1.0) {
        $probability=$multiProbability
        $source='multi_cycle_arrival'
        $modelVersion=([string]$state[$prefix+'MultiCycleModelVersion']).Trim()
        $arrivalAt=Get-CHLong -State $state -Key ($prefix+'MultiCycleArrivalAt')
        $ratio=Get-CHDouble -State $state -Key ($prefix+'MultiCycleArrivalCycleRatio') -Default 0.0
        $sampleCount=[int](Get-CHLong -State $state -Key ($prefix+'MultiCycleSampleCount'))
    } else {
        $legacyProbability=Get-CHDouble -State $state -Key ($prefix+'ProbabilityValue')
        if ($legacyProbability -ge 0.0 -and $legacyProbability -le 1.0) {
            $probability=$legacyProbability
            $source='legacy_arrival'
            $modelVersion='window-plan'
        }
    }
    if ($probability -lt 0.0 -or $probability -gt 1.0) { continue }

    $parts=@($key -split ':',2)
    $country=if($parts.Count -gt 0){[string]$parts[0]}else{''}
    $itemId=0
    if($parts.Count -gt 1){[void][int]::TryParse([string]$parts[1],[ref]$itemId)}
    $current.Add([pscustomobject]@{
        schemaVersion=1
        timestamp=[long]$Now
        marketKey=$key
        country=$country
        itemId=$itemId
        probability=[Math]::Round([double]$probability,6)
        source=$source
        modelVersion=$modelVersion
        arrivalAt=[long]$arrivalAt
        arrivalCycleRatio=[Math]::Round([double]$ratio,6)
        sampleCount=[int]$sampleCount
    })
}

$cutoff=$Now-([long][Math]::Max(1,$RetentionHours)*3600L)
Write-CHHistory -Path $HistoryFile -CurrentRows $current.ToArray() -Cutoff $cutoff -MaximumTimestamp ($Now+60L) -BucketSeconds $SampleBucketSeconds
