param(
    [switch]$SkipMain,
    [long]$Now = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$SeedDir = Join-Path $ProjectRoot 'data\seed'
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$StateKvFile = Join-Path $GeneratedDir 'state.kv'
$RuntimeCycleFile = Join-Path $RuntimeDir 'cycles.jsonl'
$SeedCycleFile = Join-Path $SeedDir 'cycles.jsonl'
. (Join-Path $PSScriptRoot 'CycleForecastFilter.ps1')

function Read-WindowJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Read-WindowStateKv {
    param([string]$Path)
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }
        $key = $line.Substring(0,$eq).Trim([char]0xFEFF).Trim()
        $values[$key] = $line.Substring($eq+1).Trim()
    }
    return $values
}

function Write-WindowStateKvAtomic {
    param([hashtable]$Values,[string]$Path)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $tmp = $Path + '.tmp'
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in @($Values.Keys | Sort-Object)) {
        $value = ([string]$Values[$key]).Replace("`r",' ').Replace("`n",' ')
        $lines.Add("$key=$value")
    }
    [System.IO.File]::WriteAllLines($tmp,$lines.ToArray(),[System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-WindowProperty {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Get-WindowUsableCycles {
    param([object[]]$Cycles,[int]$MaximumSamples = 48)
    return @(Select-CadenceAwareForecastCycles -Cycles $Cycles -MaximumSamples $MaximumSamples)
}

function Add-WindowDelta {
    param([hashtable]$Map,[long]$At,[int]$Delta)
    $key = [string]$At
    if (-not $Map.ContainsKey($key)) { $Map[$key] = 0 }
    $Map[$key] = [int]$Map[$key] + $Delta
}

function Get-RecurringScenarioModel {
    param(
        [object[]]$Cycles,
        [long]$AnchorAt,
        [ValidateSet('sellout','restock')][string]$AnchorPhase,
        [long]$NowEpoch,
        [long]$FutureHorizonSeconds = 86400L,
        [long]$MinimumSafeWindowSeconds = 60L,
        [int]$MaximumOrdinal = 1
    )
    $usable = @(Get-WindowUsableCycles -Cycles $Cycles)
    if ($AnchorAt -le 0 -or $usable.Count -eq 0) {
        return [pscustomobject]@{ sampleCount=0; anchorAt=$AnchorAt; anchorPhase=$AnchorPhase; cycles=@(); groups=@(); segments=@() }
    }

    $currentAge = [Math]::Max(0L,$NowEpoch-$AnchorAt)
    $maxAge = $currentAge + [Math]::Max(3600L,$FutureHorizonSeconds)
    $groups = @{}
    $deltas = @{}

    foreach ($cycle in $usable) {
        $delay = [long]$cycle.restockDelaySeconds
        $available = [long]$cycle.availabilitySeconds
        $period = $delay + $available
        if ($period -le 0) { continue }
        # Only the current and immediately next cycle are actionable in the
        # current UI. Always materialize ordinal 0/1 even when a long cycle lies
        # beyond the old fixed 24-hour horizon; do not spend CPU on +2/+3.
        for ($ordinal=0; $ordinal -le [Math]::Max(0,$MaximumOrdinal); $ordinal++) {
            $startAge = if ($AnchorPhase -eq 'restock') {
                [long]($ordinal * $period)
            } else {
                [long](($ordinal * $period) + $delay)
            }
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
        cycles=$cyclePairs
        groups=$resultGroups.ToArray()
        segments=$segments.ToArray()
    }
}

function Convert-WindowProbabilityText {
    param([double]$Value)
    return $Value.ToString('0.######',[System.Globalization.CultureInfo]::InvariantCulture)
}

function Convert-WindowPlanMachineText {
    param([object]$Model,[int]$MaximumGroups = 8)
    if ($null -eq $Model -or [int]$Model.sampleCount -le 0) { return '' }
    $phaseCode = if ([string]$Model.anchorPhase -eq 'restock') { 'R' } else { 'S' }
    $cycleParts = New-Object System.Collections.Generic.List[string]
    foreach ($cycle in @($Model.cycles)) { $cycleParts.Add(('{0}:{1}' -f [long]$cycle.delay,[long]$cycle.available)) }
    $groupParts = New-Object System.Collections.Generic.List[string]
    foreach ($group in @($Model.groups | Select-Object -First ([Math]::Max(1,$MaximumGroups)))) {
        $groupParts.Add(('G,{0},{1},{2},{3},{4},{5},{6},{7},{8},{9}' -f
            [int]$group.ordinal,[long]$group.earlyRestockAt,[long]$group.earlySelloutAt,[long]$group.lateRestockAt,[long]$group.lateSelloutAt,
            [long]$group.safeStartAt,[long]$group.safeEndAt,[long]$group.bestStartAt,[long]$group.bestEndAt,(Convert-WindowProbabilityText ([double]$group.bestProbability))))
    }
    return ('{0},{1},{2}~{3}' -f [long]$Model.anchorAt,$phaseCode,($cycleParts -join '/'),($groupParts -join '/'))
}

function Select-WindowPlanGroup {
    param([object]$Model,[long]$EarliestArrivalAt,[double]$MinimumBestProbability = 0.5)
    if ($null -eq $Model) { return $null }
    $future = @($Model.groups | Where-Object { [long]$_.lateSelloutAt -gt $EarliestArrivalAt })
    if ($future.Count -eq 0) { return $null }
    $safe = @($future | Where-Object { [long]$_.safeEndAt -gt [Math]::Max($EarliestArrivalAt,[long]$_.safeStartAt) } | Sort-Object safeStartAt)
    if ($safe.Count -gt 0) {
        $g=$safe[0]
        return [pscustomobject]@{ mode='safe'; startAt=[long]$g.safeStartAt; endAt=[long]$g.safeEndAt; probability=1.0; group=$g }
    }
    $best = @($future | Where-Object { [double]$_.bestProbability -gt $MinimumBestProbability -and [long]$_.bestEndAt -gt $EarliestArrivalAt } | Sort-Object @{Expression='ordinal';Ascending=$true},@{Expression='bestProbability';Descending=$true})
    if ($best.Count -gt 0) {
        $g=$best[0]
        return [pscustomobject]@{ mode='best'; startAt=[long]$g.bestStartAt; endAt=[long]$g.bestEndAt; probability=[double]$g.bestProbability; group=$g }
    }
    return $null
}

function Get-WindowTravelSeconds {
    param([hashtable]$State,[string]$CountryId)
    $key = if ($CountryId -eq 'united_kingdom') { 'UKTravelSeconds' } elseif ($CountryId -eq 'japan') { 'JPTravelSeconds' } else { $CountryId.ToUpperInvariant()+'TravelSeconds' }
    if (-not $State.ContainsKey($key)) { return 0L }
    $value=0L
    if ([long]::TryParse([string]$State[$key],[ref]$value)) { return [Math]::Max(0L,$value) }
    return 0L
}

function Test-WindowPriceVaries {
    param([object]$Engine,[string]$Key)
    if ($null -eq $Engine -or [string]::IsNullOrWhiteSpace($Key)) { return $false }
    $root=Get-WindowProperty $Engine 'cycleAnalytics'
    $markets=Get-WindowProperty $root 'markets'
    $market=Get-WindowProperty $markets $Key
    if ($null -eq $market) { return $false }

    $stats=Get-WindowProperty $market 'foreignPrice'
    if ($null -ne $stats) {
        $count=[int](Get-WindowProperty $stats 'count')
        $min=[long](Get-WindowProperty $stats 'min')
        $max=[long](Get-WindowProperty $stats 'max')
        if ($count -ge 2 -and $min -gt 0 -and $max -gt $min) { return $true }
    }

    $current=[long](Get-WindowProperty $market 'currentForeignPrice')
    $last=[long](Get-WindowProperty $market 'lastForeignPrice')
    if ($current -gt 0 -and $last -gt 0 -and $current -ne $last) { return $true }

    $events=Get-WindowProperty $market 'priceEvents'
    if (@($events).Count -gt 0) { return $true }
    return $false
}

function Read-WindowCyclesForKeys {
    param([string[]]$Paths,[hashtable]$Wanted)
    $map=@{}
    $seen=@{}
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        foreach ($line in [System.IO.File]::ReadLines($path)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $row=$line | ConvertFrom-Json } catch { continue }
            $country=[string](Get-WindowProperty $row 'country')
            $itemId=[int](Get-WindowProperty $row 'itemId')
            if ([string]::IsNullOrWhiteSpace($country) -or $itemId -le 0) { continue }
            $key=$country+':'+[string]$itemId
            if (-not $Wanted.ContainsKey($key)) { continue }
            $identity=('{0}:{1}:{2}' -f $key,[long](Get-WindowProperty $row 'restockAt'),[long](Get-WindowProperty $row 'soldOutAt'))
            if ($seen.ContainsKey($identity)) { continue }
            $seen[$identity]=$true
            if (-not $map.ContainsKey($key)) { $map[$key]=New-Object System.Collections.Generic.List[object] }
            $map[$key].Add($row)
        }
    }
    return $map
}

if ($SkipMain) { return }
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
        # OpportunityState already owns the cheap absolute Restocks in ~... state.
        # Do not deserialize cycle rows or build WP2 probability geometry.
        continue
    }
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

    $model=Get-RecurringScenarioModel -Cycles $cycles -AnchorAt $anchorAt -AnchorPhase $phase -NowEpoch $Now
    $machine=Convert-WindowPlanMachineText -Model $model
    $oldTooltip=[string]$state[$prefix+'Tooltip']
    $priceVaries=Test-WindowPriceVaries -Engine $engine -Key $key
    $priceEnvelope=if ($priceVaries) { 'PV1#' } else { 'PV0#' }
    if (-not [string]::IsNullOrWhiteSpace($machine)) { $state[$prefix+'Tooltip']='WP2:'+$machine+'#'+$priceEnvelope+$oldTooltip }
    else { $state[$prefix+'Tooltip']=$priceEnvelope+$oldTooltip }

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
    $selected=Select-WindowPlanGroup -Model $model -EarliestArrivalAt $earliestArrival
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
