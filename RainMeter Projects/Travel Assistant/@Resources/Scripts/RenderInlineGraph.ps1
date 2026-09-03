param(
    [Parameter(Mandatory=$true)]
    [string]$MarketKey
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

if ($MarketKey -notmatch '^[a-z0-9_]+:[1-9][0-9]*$') { throw 'MarketKey must be country:itemId.' }

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$SeedDir = Join-Path $ProjectRoot 'data\seed'
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$RuntimeObservationFile = Join-Path $RuntimeDir 'observations.jsonl'
$SeedObservationFile = Join-Path $SeedDir 'observations.jsonl'
$RuntimeCycleFile = Join-Path $RuntimeDir 'cycles.jsonl'
$SeedCycleFile = Join-Path $SeedDir 'cycles.jsonl'
$ChanceHistoryFile = Join-Path $RuntimeDir 'chance-history.jsonl'
$ResolvedArrivalHistoryFile = Join-Path $RuntimeDir 'resolved-arrival-history.jsonl'
$StateKvFile = Join-Path $GeneratedDir 'state.kv'
$FocusMarketFile = Join-Path $RuntimeDir 'focus-market.kv'
$SettingsFile = Join-Path $ConfigDir 'settings.example.json'
$LocalSettingsFile = Join-Path $ConfigDir 'settings.local.json'
$AtomicFileScript = Join-Path $PSScriptRoot 'AtomicFile.ps1'
if (-not (Test-Path -LiteralPath $AtomicFileScript)) { throw 'AtomicFile.ps1 is required for shared graph history reads.' }
. $AtomicFileScript
$CycleForecastFilterScript = Join-Path $PSScriptRoot 'CycleForecastFilter.ps1'
if (-not (Test-Path -LiteralPath $CycleForecastFilterScript)) { throw 'CycleForecastFilter.ps1 is required for modeled restock-window markers.' }
. $CycleForecastFilterScript

$focusUpdatedAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$focusText=('MarketKey={0}{1}UpdatedAt={2}{1}' -f $MarketKey,[Environment]::NewLine,$focusUpdatedAt)
Write-TravelAssistantAtomicText -Path $FocusMarketFile -Text $focusText

function Read-InlineKv {
    param([string]$Path)
    $values=@{}
    if(-not(Test-Path -LiteralPath $Path)){return $values}
    $reader=$null
    try{
        $reader=Open-TravelAssistantSharedTextReader -Path $Path
        while(($line=$reader.ReadLine()) -ne $null){
            if([string]::IsNullOrWhiteSpace($line)){continue}
            $eq=$line.IndexOf('=')
            if($eq -lt 1){continue}
            $values[$line.Substring(0,$eq).Trim([char]0xFEFF).Trim()]=$line.Substring($eq+1).Trim()
        }
    }finally{
        if($null -ne $reader){$reader.Dispose()}
    }
    return $values
}

function Get-InlineTravelSeconds {
    param([hashtable]$State,[string]$Country)
    $countryId=([string]$Country).Trim().ToLowerInvariant()
    $key=if($countryId -eq 'united_kingdom'){'UKTravelSeconds'}elseif($countryId -eq 'japan'){'JPTravelSeconds'}else{$countryId.ToUpperInvariant()+'TravelSeconds'}
    $value=0L
    if($State.ContainsKey($key)){[void][long]::TryParse([string]$State[$key],[ref]$value)}
    return [Math]::Max(0L,$value)
}

function Read-InlineJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Read-TravelAssistantSharedText -Path $Path
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Get-InlineProperty {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Write-InlineKvAtomic {
    param([string]$Path,[hashtable]$Values)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $tmp = $Path + '.tmp'
    $lines = @()
    foreach ($key in @($Values.Keys | Sort-Object)) {
        $value = ([string]$Values[$key]).Replace("`r",' ').Replace("`n",' ')
        $lines += ($key + '=' + $value)
    }
    [System.IO.File]::WriteAllLines($tmp,[string[]]$lines,(New-Object System.Text.UTF8Encoding($false)))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Read-MarketHistory {
    param([string]$Path,[string]$Country,[int]$ItemId)
    $rows = @()
    if (-not (Test-Path -LiteralPath $Path)) { return $rows }
    $countryNeedle = '"country":"' + $Country + '"'
    $itemPattern = '"itemId"\s*:\s*' + [regex]::Escape([string]$ItemId) + '(?=\s*[,}])'
    $reader = $null
    try {
        $reader = Open-TravelAssistantSharedTextReader -Path $Path
        while (($line = $reader.ReadLine()) -ne $null) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line.IndexOf($countryNeedle,[System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            if ($line -notmatch $itemPattern) { continue }
            try {
                $row = $line | ConvertFrom-Json
                $timestamp = [long](Get-InlineProperty $row 'timestamp')
                if ($timestamp -le 0) { continue }
                $source = [string](Get-InlineProperty $row 'source')
                # Older migration builds wrote current stock backward through time as
                # history_bootstrap/history_repair_baseline. Those are not observations
                # and must never be rendered as historical truth.
                if ($source -in @('history_bootstrap','history_repair_baseline')) { continue }
                $rows += [pscustomobject]@{
                    timestamp = $timestamp
                    stock = [long](Get-InlineProperty $row 'stock')
                    source = $source
                }
            } catch { }
        }
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
    }
    return $rows
}


function Read-InlineMarketCycles {
    param([string[]]$Paths,[string]$Country,[int]$ItemId)
    $rows=New-Object System.Collections.Generic.List[object]
    $seen=@{}
    $countryNeedle='"country":"'+$Country+'"'
    $itemPattern='"itemId"\s*:\s*'+[regex]::Escape([string]$ItemId)+'(?=\s*[,}])'
    foreach($path in $Paths){
        if(-not(Test-Path -LiteralPath $path)){continue}
        $reader=$null
        try{
            $reader=Open-TravelAssistantSharedTextReader -Path $path
            while(($line=$reader.ReadLine()) -ne $null){
                if([string]::IsNullOrWhiteSpace($line)){continue}
                if($line.IndexOf($countryNeedle,[System.StringComparison]::OrdinalIgnoreCase) -lt 0){continue}
                if($line -notmatch $itemPattern){continue}
                try{$row=$line|ConvertFrom-Json}catch{continue}
                $restockAt=[long](Get-InlineProperty $row 'restockAt')
                $soldOutAt=[long](Get-InlineProperty $row 'soldOutAt')
                $delay=[long](Get-InlineProperty $row 'restockDelaySeconds')
                $available=[long](Get-InlineProperty $row 'availabilitySeconds')
                if($delay -le 0){continue}
                $identity=('{0}:{1}:{2}:{3}' -f $restockAt,$soldOutAt,$delay,$available)
                if($seen.ContainsKey($identity)){continue}
                $seen[$identity]=$true
                $rows.Add($row)
            }
        }finally{
            if($null -ne $reader){$reader.Dispose()}
        }
    }
    return $rows.ToArray()
}

function Get-InlineRestockWindowSummary {
    param([object[]]$Cycles,[int]$RecentSamples=12)
    $usable=@($Cycles|Where-Object{
        $null -ne $_ -and
        $_.PSObject.Properties['restockDelaySeconds'] -and [long]$_.restockDelaySeconds -gt 0 -and
        (Test-CycleForecastBoundaryEvidence -Cycle $_ -Purpose Forecast)
    }|Sort-Object @{Expression={if($_.PSObject.Properties['soldOutAt']){[long]$_.soldOutAt}else{0L}};Descending=$true})
    if($usable.Count -eq 0){return $null}
    $recent=@($usable)
    if($RecentSamples -gt 0 -and $recent.Count -gt $RecentSamples){$recent=@($recent|Select-Object -First $RecentSamples)}
    $delays=[long[]]@($recent|ForEach-Object{[long]$_.restockDelaySeconds})
    $availability=[long[]]@($recent|Where-Object{$_.PSObject.Properties['availabilitySeconds'] -and [long]$_.availabilitySeconds -gt 0}|ForEach-Object{[long]$_.availabilitySeconds})
    $minimum=[long](($delays|Measure-Object -Minimum).Minimum)
    $maximum=[long](($delays|Measure-Object -Maximum).Maximum)
    $sigma=[long](Get-CycleForecastRobustSigma -Values $delays)
    if($sigma -le 0 -and $maximum -gt $minimum){
        $sigma=[long][Math]::Ceiling(($maximum-$minimum)/2.0)
    }
    return [pscustomobject]@{
        sampleCount=[int]$recent.Count
        averageDelaySeconds=[long][Math]::Round([double](($delays|Measure-Object -Average).Average))
        earliestDelaySeconds=$minimum
        latestDelaySeconds=$maximum
        varianceSeconds=[Math]::Max(0L,$sigma)
        averageInStockSeconds=$(if($availability.Count -gt 0){[long][Math]::Round([double](($availability|Measure-Object -Average).Average))}else{0L})
    }
}

function Get-InlineStockTransitions {
    param([object[]]$Rows)
    $result=New-Object System.Collections.Generic.List[object]
    $previous=$null
    foreach($row in @($Rows|Sort-Object timestamp)){
        $stock=[long]$row.stock
        if($null -ne $previous){
            if([long]$previous.stock -gt 0 -and $stock -eq 0){
                $result.Add([pscustomobject]@{kind='oos';timestamp=[long]$row.timestamp;quantity=0L})
            }elseif([long]$previous.stock -eq 0 -and $stock -gt 0){
                $result.Add([pscustomobject]@{kind='restock';timestamp=[long]$row.timestamp;quantity=$stock})
            }
        }
        $previous=$row
    }
    return $result.ToArray()
}

function Get-InlineRestockTransitions {
    param([object[]]$Rows)
    return @((Get-InlineStockTransitions -Rows $Rows)|Where-Object{[string]$_.kind -eq 'restock'}|ForEach-Object{[long]$_.timestamp})
}

function Get-InlineInfoTimeline {
    param(
        [object[]]$Transitions,
        [long]$Cutoff,
        [long]$NowEpoch,
        [long]$VarianceSeconds,
        [long]$FlightSeconds,
        [int]$MaximumCycles=4
    )

    $cycles=New-Object System.Collections.Generic.List[object]
    $active=$null
    $lastOosAt=0L
    foreach($event in @($Transitions|Sort-Object timestamp)){
        $at=[long]$event.timestamp
        $kind=[string]$event.kind
        if($kind -eq 'oos'){
            if($null -ne $active -and [long]$active.restockAt -gt 0 -and [long]$active.soldOutAt -le 0 -and $at -gt [long]$active.restockAt){
                $active.soldOutAt=$at
                $active.latestAt=$at
            }elseif($null -eq $active){
                $orphan=[pscustomobject]@{priorOosAt=0L;restockAt=0L;quantity=0L;soldOutAt=$at;latestAt=$at}
                $cycles.Add($orphan)
            }
            $lastOosAt=$at
        }elseif($kind -eq 'restock'){
            $record=[pscustomobject]@{
                priorOosAt=$lastOosAt
                restockAt=$at
                quantity=[long]$event.quantity
                soldOutAt=0L
                latestAt=$at
            }
            $cycles.Add($record)
            $active=$record
            $lastOosAt=0L
        }
    }

    $selected=@($cycles.ToArray()|Where-Object{
        [long]$_.latestAt -ge $Cutoff -or
        [long]$_.restockAt -ge $Cutoff -or
        [long]$_.priorOosAt -ge $Cutoff
    }|Sort-Object latestAt -Descending|Select-Object -First ([Math]::Max(1,$MaximumCycles)))

    $events=New-Object System.Collections.Generic.List[object]
    $seen=@{}
    function Add-InlineInfoEvent {
        param([long]$At,[string]$Kind,[string]$Label)
        if($At -lt $Cutoff -or $At -gt $NowEpoch){return}
        $key=$Kind+':'+[string]$At
        if($seen.ContainsKey($key)){return}
        $seen[$key]=$true
        $events.Add([pscustomobject]@{timestamp=$At;kind=$Kind;label=$Label})
    }

    foreach($cycle in $selected){
        $priorOos=[long]$cycle.priorOosAt
        $restock=[long]$cycle.restockAt
        $soldOut=[long]$cycle.soldOutAt
        if($priorOos -gt 0){Add-InlineInfoEvent -At $priorOos -Kind 'oos' -Label 'OoS'}
        if($restock -gt 0){
            $qty=[long]$cycle.quantity
            Add-InlineInfoEvent -At $restock -Kind 'restock' -Label ('Restock of '+('{0:N0}' -f $qty))
            if($VarianceSeconds -gt 0){
                Add-InlineInfoEvent -At ($restock-$VarianceSeconds) -Kind 'early_open' -Label 'Early open'
                Add-InlineInfoEvent -At ($restock+$VarianceSeconds) -Kind 'late_open' -Label 'Late open'
            }
            if($FlightSeconds -gt 0){
                Add-InlineInfoEvent -At ($restock-$FlightSeconds) -Kind 'actual_window_open' -Label 'Actual window open'
            }
        }
        if($soldOut -gt 0){
            Add-InlineInfoEvent -At $soldOut -Kind 'oos' -Label 'OoS'
            if($FlightSeconds -gt 0){
                Add-InlineInfoEvent -At ($soldOut-$FlightSeconds) -Kind 'actual_window_closed' -Label 'Actual window closed'
            }
        }
    }

    return [pscustomobject]@{
        cycleCount=$selected.Count
        events=@($events.ToArray()|Sort-Object timestamp -Descending)
    }
}

function Read-MarketChanceHistory {
    param([string]$Path,[string]$Key,[long]$Cutoff,[long]$MaximumTimestamp)
    $rows=@()
    if (-not (Test-Path -LiteralPath $Path)) { return $rows }
    $needle='"marketKey":"'+$Key+'"'
    $reader=$null
    try {
        $reader=Open-TravelAssistantSharedTextReader -Path $Path
        while (($line=$reader.ReadLine()) -ne $null) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line.IndexOf($needle,[System.StringComparison]::OrdinalIgnoreCase) -lt 0) { continue }
            try { $row=$line | ConvertFrom-Json } catch { continue }
            $timestamp=[long](Get-InlineProperty $row 'timestamp')
            $probability=[double](Get-InlineProperty $row 'probability')
            if ($timestamp -lt $Cutoff -or $timestamp -gt $MaximumTimestamp) { continue }
            if ($probability -lt 0.0 -or $probability -gt 1.0) { continue }
            $rows += [pscustomobject]@{
                timestamp=$timestamp
                probability=$probability
                source=[string](Get-InlineProperty $row 'source')
            }
        }
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
    }
    return @($rows | Sort-Object timestamp)
}

function Read-MarketResolvedArrivalHistory {
    param([string]$Path,[string]$Key,[long]$Cutoff,[long]$MaximumForecastAt)
    $rows=@()
    if(-not(Test-Path -LiteralPath $Path)){return $rows}
    $needle='"marketKey":"'+$Key+'"'
    $reader=$null
    try{
        $reader=Open-TravelAssistantSharedTextReader -Path $Path
        while(($line=$reader.ReadLine()) -ne $null){
            if([string]::IsNullOrWhiteSpace($line)){continue}
            if($line.IndexOf($needle,[System.StringComparison]::OrdinalIgnoreCase) -lt 0){continue}
            try{$row=$line|ConvertFrom-Json}catch{continue}
            $forecastAt=[long](Get-InlineProperty $row 'forecastAt')
            $probability=[double](Get-InlineProperty $row 'predictedProbability')
            $actual=[int](Get-InlineProperty $row 'actualAnyStock')
            if($forecastAt -lt $Cutoff -or $forecastAt -gt $MaximumForecastAt){continue}
            if($probability -lt 0.0 -or $probability -gt 1.0 -or $actual -notin @(0,1)){continue}
            $rows += [pscustomobject]@{
                forecastAt=$forecastAt
                predictedProbability=$probability
                actualAnyStock=$actual
                brier=[double](Get-InlineProperty $row 'brier')
                source=[string](Get-InlineProperty $row 'source')
            }
        }
    }finally{
        if($null -ne $reader){$reader.Dispose()}
    }
    return @($rows|Sort-Object forecastAt)
}

function Get-FlightShiftedRealizedHistory {
    param([object[]]$StockRows,[long]$FlightSeconds,[long]$Cutoff,[long]$NowEpoch)
    if($FlightSeconds -le 0){return @()}
    $actualStart=$Cutoff+$FlightSeconds
    $actualEnd=$NowEpoch
    if($actualStart -gt $actualEnd){return @()}

    $ordered=@($StockRows|Sort-Object timestamp)
    $result=New-Object System.Collections.Generic.List[object]
    $predecessor=@($ordered|Where-Object{[long]$_.timestamp -lt $actualStart}|Select-Object -Last 1)
    if($predecessor.Count -gt 0){
        $result.Add([pscustomobject]@{
            timestamp=[long]$Cutoff
            actualAnyStock=$(if([long]$predecessor[0].stock -gt 0){1}else{0})
            source='flight_shifted_observed_stock'
        })
    }
    foreach($row in @($ordered|Where-Object{[long]$_.timestamp -ge $actualStart -and [long]$_.timestamp -le $actualEnd})){
        $departureAt=[long]$row.timestamp-$FlightSeconds
        if($departureAt -lt $Cutoff -or $departureAt -gt $NowEpoch){continue}
        $result.Add([pscustomobject]@{
            timestamp=$departureAt
            actualAnyStock=$(if([long]$row.stock -gt 0){1}else{0})
            source='flight_shifted_observed_stock'
        })
    }
    $compressed=New-Object System.Collections.Generic.List[object]
    $previous=$null
    foreach($row in @($result.ToArray()|Sort-Object timestamp)){
        $actual=[int]$row.actualAnyStock
        if($null -eq $previous -or [int]$previous -ne $actual){
            $compressed.Add($row)
            $previous=$actual
        }
    }
    return $compressed.ToArray()
}

function Format-InlineDuration {
    param([long]$Seconds)
    $value=[Math]::Max(0L,$Seconds)
    $hours=[Math]::Floor($value/3600)
    $minutes=[Math]::Floor(($value%3600)/60)
    $seconds=$value%60
    return ('{0:00}:{1:00}:{2:00}' -f $hours,$minutes,$seconds)
}

function Format-InlineRelativeTime {
    param([long]$Timestamp,[long]$NowEpoch)
    if($Timestamp -le 0){return 'unknown'}
    $delta=$NowEpoch-$Timestamp
    if($delta -ge 0){return ((Format-InlineDuration -Seconds $delta)+' ago')}
    return ('in '+(Format-InlineDuration -Seconds (-$delta)))
}

function Format-InlineClockTime {
    param([long]$Timestamp)
    if($Timestamp -le 0){return '--:--:--'}
    return [DateTimeOffset]::FromUnixTimeSeconds($Timestamp).ToLocalTime().ToString('HH:mm:ss')
}

function Get-InlineSettingBool {
    param([object]$Base,[object]$Local,[string]$Name,[bool]$Default=$true)
    $value=$Default
    $baseVisuals=Get-InlineProperty $Base 'graphVisuals'
    if($null -ne $baseVisuals -and $null -ne $baseVisuals.PSObject.Properties[$Name]){
        $value=[bool]$baseVisuals.PSObject.Properties[$Name].Value
    }
    $localVisuals=Get-InlineProperty $Local 'graphVisuals'
    if($null -ne $localVisuals -and $null -ne $localVisuals.PSObject.Properties[$Name]){
        $value=[bool]$localVisuals.PSObject.Properties[$Name].Value
    }
    return [bool]$value
}

function Get-RealizedDepartureWindows {
    param([object[]]$Rows,[long]$RealizedThrough,[long]$Cutoff)
    $ordered=@($Rows|Sort-Object timestamp)
    $windows=New-Object System.Collections.Generic.List[object]
    $activeStart=0L
    foreach($row in $ordered){
        $at=[long]$row.timestamp
        if($at -lt $Cutoff -or $at -gt $RealizedThrough){continue}
        $actual=[int]$row.actualAnyStock
        if($actual -eq 1 -and $activeStart -le 0){
            $activeStart=$at
        }elseif($actual -eq 0 -and $activeStart -gt 0){
            if($at -gt $activeStart){
                $windows.Add([pscustomobject]@{startAt=$activeStart;endAt=$at})
            }
            $activeStart=0L
        }
    }
    if($activeStart -gt 0 -and $RealizedThrough -gt $activeStart){
        $windows.Add([pscustomobject]@{startAt=$activeStart;endAt=$RealizedThrough})
    }
    return $windows.ToArray()
}

function Compress-StockHistory {
    param([object[]]$Rows)
    $compressed = @()
    $previousStock = $null
    foreach ($row in @($Rows | Sort-Object timestamp)) {
        $stock = [long]$row.stock
        if ($null -eq $previousStock -or [long]$previousStock -ne $stock) {
            $compressed += $row
            $previousStock = $stock
        }
    }
    return @($compressed)
}

$settings = Read-InlineJson $SettingsFile
$localSettings = Read-InlineJson $LocalSettingsFile
$state = Read-InlineKv $StateKvFile
$engine = Read-InlineJson $EngineStateFile
if ($null -eq $engine -or -not $engine.PSObject.Properties['observedMarkets']) { throw 'No observed market state is available.' }

$windowHours = 8
if ($null -ne $settings -and $settings.PSObject.Properties['graphWindowHours']) { $windowHours = [int]$settings.graphWindowHours }
$windowHours = [Math]::Max(1,[Math]::Min(24,$windowHours))

$showGrid=Get-InlineSettingBool -Base $settings -Local $localSettings -Name 'showGrid' -Default $true
$showTransitions=Get-InlineSettingBool -Base $settings -Local $localSettings -Name 'showTransitions' -Default $true
$showRestockWindowBounds=Get-InlineSettingBool -Base $settings -Local $localSettings -Name 'showRestockWindowBounds' -Default $true
$showChance=Get-InlineSettingBool -Base $settings -Local $localSettings -Name 'showChance' -Default $true
$showHindsightWindows=Get-InlineSettingBool -Base $settings -Local $localSettings -Name 'showHindsightWindows' -Default $true
$showAccuracyMarkers=Get-InlineSettingBool -Base $settings -Local $localSettings -Name 'showAccuracyMarkers' -Default $true
$showTooltips=Get-InlineSettingBool -Base $settings -Local $localSettings -Name 'showTooltips' -Default $true

$parts = $MarketKey.Split(':')
$country = [string]$parts[0]
$itemId = [int]$parts[1]
$market = Get-InlineProperty $engine.observedMarkets $MarketKey
if ($null -eq $market) { throw ('Market not found in observedMarkets: ' + $MarketKey) }

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$cutoff = $now - ([long]$windowHours * 3600L)

# Runtime observations are the shared high-resolution ShadowCollector database and
# are authoritative. Seed evidence is used only if this market has no real retained
# runtime rows after synthetic migration rows are excluded.
$allRows = @(Read-MarketHistory -Path $RuntimeObservationFile -Country $country -ItemId $itemId)
$historySource = 'runtime_observations'
if ($allRows.Count -eq 0) {
    $allRows = @(Read-MarketHistory -Path $SeedObservationFile -Country $country -ItemId $itemId)
    $historySource = 'seed_fallback'
}
$allRows = @(Compress-StockHistory -Rows $allRows)
$cycleRows=@(Read-InlineMarketCycles -Paths @($RuntimeCycleFile,$SeedCycleFile) -Country $country -ItemId $itemId)
$restockWindowSummary=Get-InlineRestockWindowSummary -Cycles $cycleRows
$stockTransitions=@(Get-InlineStockTransitions -Rows $allRows)
$restockTransitions=@($stockTransitions|Where-Object{[string]$_.kind -eq 'restock'}|ForEach-Object{[long]$_.timestamp})

$rows = @()
$predecessor = @($allRows | Where-Object { [long]$_.timestamp -lt $cutoff } | Select-Object -Last 1)
if ($predecessor.Count -gt 0) {
    $rows += [pscustomobject]@{ timestamp=$cutoff; stock=[long]$predecessor[0].stock; source='carry_forward' }
}
$rows += @($allRows | Where-Object { [long]$_.timestamp -ge $cutoff -and [long]$_.timestamp -le ($now+60) })
$rows = @(Compress-StockHistory -Rows $rows)

# Never paint current stock backward through an interval with no retained sample.
# If there is no predecessor, the left side of the graph remains genuinely unknown.
$currentStock = [long](Get-InlineProperty $market 'lastStock')
$currentTimestamp = [long](Get-InlineProperty $market 'sourceTimestamp')
if ($currentTimestamp -le 0) { $currentTimestamp = [long](Get-InlineProperty $market 'lastSeenAt') }
if ($currentTimestamp -le 0 -or $currentTimestamp -lt $cutoff -or $currentTimestamp -gt ($now+60)) { $currentTimestamp = $now }
$rows += [pscustomobject]@{ timestamp=$currentTimestamp; stock=$currentStock; source='current_snapshot' }
$rows = @(Compress-StockHistory -Rows $rows)

# Chance history is forecast-only and intentionally separate from retained stock
# observations. It is sampled by the normal updater and rendered on an independent
# fixed 0..100% scale.
$chanceRows=@(Read-MarketChanceHistory -Path $ChanceHistoryFile -Key $MarketKey -Cutoff $cutoff -MaximumTimestamp ($now+60L))
$resolvedRows=@(Read-MarketResolvedArrivalHistory -Path $ResolvedArrivalHistoryFile -Key $MarketKey -Cutoff $cutoff -MaximumForecastAt $now)
$flightSeconds=Get-InlineTravelSeconds -State $state -Country $country
$realizedRows=@(Get-FlightShiftedRealizedHistory -StockRows $allRows -FlightSeconds $flightSeconds -Cutoff $cutoff -NowEpoch $now)
$realizedThrough=$now-$flightSeconds
$realizedWindows=@(Get-RealizedDepartureWindows -Rows $realizedRows -RealizedThrough $realizedThrough -Cutoff $cutoff)

$infoLines=New-Object System.Collections.Generic.List[string]
$infoTimeline=$null
$infoEnabled=$showTooltips
if($infoEnabled){
    $infoLines.Add('8h cycle summary')
    if($null -ne $restockWindowSummary){
        $avgDelay=[long]$restockWindowSummary.averageDelaySeconds
        $avgInStock=[long]$restockWindowSummary.averageInStockSeconds
        $variance=[long]$restockWindowSummary.varianceSeconds
        $midpoint=$avgDelay
        $leaveAfter=[Math]::Max(0L,$midpoint-$flightSeconds)
        $infoLines.Add('Avg restock delay: '+(Format-InlineDuration -Seconds $avgDelay))
        $infoLines.Add('Avg in-stock time: '+(Format-InlineDuration -Seconds $avgInStock))
        $infoLines.Add('Avg open variance: +/-'+(Format-InlineDuration -Seconds $variance))
        $infoLines.Add('Avg variance width: '+(Format-InlineDuration -Seconds (2L*$variance)))
        $infoLines.Add('Midpoint after OoS: '+(Format-InlineDuration -Seconds $midpoint))
        if($flightSeconds -le 0){
            $infoLines.Add('Leave after OoS for midpoint: travel time unavailable')
        }elseif($midpoint -le $flightSeconds){
            $infoLines.Add('Leave after OoS for midpoint: LEAVE NOW')
        }else{
            $infoLines.Add('Leave after OoS for midpoint: '+(Format-InlineDuration -Seconds $leaveAfter))
        }
    }else{
        $infoLines.Add('Averages: collecting forecast-eligible cycle evidence')
    }
    $infoLines.Add('Timeline - newest first (max 4 cycles)')
    $varianceForTimeline=if($null -ne $restockWindowSummary){[long]$restockWindowSummary.varianceSeconds}else{0L}
    $infoTimeline=Get-InlineInfoTimeline -Transitions $stockTransitions -Cutoff $cutoff -NowEpoch $now -VarianceSeconds $varianceForTimeline -FlightSeconds $flightSeconds -MaximumCycles 4
    if($null -eq $infoTimeline -or @($infoTimeline.events).Count -eq 0){
        $infoLines.Add('No cycle events in the last 8 hours')
    }else{
        foreach($event in @($infoTimeline.events)){
            $infoLines.Add('['+(Format-InlineClockTime -Timestamp ([long]$event.timestamp))+'] '+[string]$event.label)
        }
    }
}

$hoverRegions=New-Object System.Collections.Generic.List[object]
$transitionHoverRegions=New-Object System.Collections.Generic.List[object]
$forecastHoverRegions=New-Object System.Collections.Generic.List[object]
$forecastBoundaryCount=0
$maximumHoverRegions=48

$maxStock = 0L
if ($rows.Count -gt 0) {
    $measure = $rows | Measure-Object stock -Maximum
    if ($null -ne $measure.Maximum) { $maxStock = [long]$measure.Maximum }
}
$scaleMax = if ($maxStock -gt 0) { [double]$maxStock } else { 1.0 }

Add-Type -AssemblyName System.Drawing
# The image now nearly fills the 536px card width and is exactly 25% taller than
# the previous 100px renderer. CardTweaks reserves the matching 125px display area.
$width = 528
$height = 125
$plotLeft = 34.0
$plotRight = 522.0
$plotTop = 8.0
$plotBottom = 98.0
$plotWidth = $plotRight - $plotLeft
$plotHeight = $plotBottom - $plotTop

$bitmap = New-Object System.Drawing.Bitmap($width,$height)
$graphics = [System.Drawing.Graphics]::FromImage($bitmap)
$graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
$graphics.TextRenderingHint = [System.Drawing.Text.TextRenderingHint]::ClearTypeGridFit
$graphics.Clear([System.Drawing.Color]::FromArgb(0,0,0))

$gridMajor = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(72,78,88),1)
$gridMinor = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(48,53,61),1)
$stockPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(126,190,73),2)
$chancePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(105,200,235),1.5)
$hindsightBandBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(32,165,165,235))
$hindsightBoundaryPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(155,165,165,235),1)
$errorPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(85,225,225,225),1)
$hitBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(115,190,230,95))
$missBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(140,255,117,24))
$restockPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(0,71,171),1)
$restockWindowPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(145,132,165,190),1)
$selloutPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(255,117,24),1)
$labelBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(170,178,190))
$labelFont = New-Object System.Drawing.Font('Segoe UI',7,[System.Drawing.FontStyle]::Regular,[System.Drawing.GraphicsUnit]::Point)
$infoPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(190,198,210),1)
$infoBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(190,198,210))

# Eight one-hour segments: seven internal vertical separators plus both boundaries.
if($showGrid){
    for ($i=0; $i -le 8; $i++) {
        $x = [single]($plotLeft + ($plotWidth * $i / 8.0))
        $pen = if ($i -eq 0 -or $i -eq 8) { $gridMajor } else { $gridMinor }
        $graphics.DrawLine($pen,$x,[single]$plotTop,$x,[single]$plotBottom)
    }
    for ($i=0; $i -le 3; $i++) {
        $y = [single]($plotTop + ($plotHeight * $i / 3.0))
        $pen = if ($i -eq 0 -or $i -eq 3) { $gridMajor } else { $gridMinor }
        $graphics.DrawLine($pen,[single]$plotLeft,$y,[single]$plotRight,$y)
    }
}

function Get-InlineX([long]$Timestamp) {
    $clamped = [Math]::Max($cutoff,[Math]::Min($now,$Timestamp))
    return [single]($plotLeft + ((($clamped-$cutoff) / [double]($windowHours*3600L)) * $plotWidth))
}
function Get-InlineY([long]$Stock) {
    if ($maxStock -le 0) { return [single]$plotBottom }
    return [single]($plotBottom - (($Stock / $scaleMax) * $plotHeight))
}
function Get-ChanceY([double]$Probability) {
    $p=[Math]::Max(0.0,[Math]::Min(1.0,$Probability))
    return [single]($plotBottom - ($p * $plotHeight))
}

# Periwinkle is hindsight truth, not another forecast encoding. Shift actual
# observed stock backward by the configured one-way flight duration and fill only
# historical departure intervals that are now known to have landed in stock.
if($showHindsightWindows){
    foreach($window in $realizedWindows){
        $startX=Get-InlineX ([long]$window.startAt)
        $endX=Get-InlineX ([long]$window.endAt)
        $bandWidth=[single][Math]::Max(1.0,$endX-$startX)
        $graphics.FillRectangle($hindsightBandBrush,$startX,[single]$plotTop,$bandWidth,[single]$plotHeight)
        $graphics.DrawLine($hindsightBoundaryPen,$startX,[single]$plotTop,$startX,[single]$plotBottom)
        $graphics.DrawLine($hindsightBoundaryPen,$endX,[single]$plotTop,$endX,[single]$plotBottom)

        if($showTooltips){
            $opened=Format-InlineRelativeTime -Timestamp ([long]$window.startAt) -NowEpoch $now
            $closed=Format-InlineRelativeTime -Timestamp ([long]$window.endAt) -NowEpoch $now
            $duration=Format-InlineDuration -Seconds ([long]$window.endAt-[long]$window.startAt)
            $hoverRegions.Add([pscustomobject]@{
                x=[double]$startX;y=[double]$plotTop;w=[double]$bandWidth;h=[double]$plotHeight
                text=('Hindsight departure window: '+$opened+' to '+$closed+' | duration '+$duration)
                kind='hindsight_window';timestamp=[long]$window.startAt
            })
            $hoverRegions.Add([pscustomobject]@{
                x=[double]([Math]::Max($plotLeft,$startX-3));y=[double]$plotTop;w=7.0;h=[double]$plotHeight
                text=('Actual hindsight window opened: '+$opened)
                kind='hindsight_open';timestamp=[long]$window.startAt
            })
            $hoverRegions.Add([pscustomobject]@{
                x=[double]([Math]::Max($plotLeft,$endX-3));y=[double]$plotTop;w=7.0;h=[double]$plotHeight
                text=('Actual hindsight window closed: '+$closed)
                kind='hindsight_close';timestamp=[long]$window.endAt
            })
        }
    }
}

$previous = $null
foreach ($row in $rows) {
    $x = Get-InlineX ([long]$row.timestamp)
    $y = Get-InlineY ([long]$row.stock)
    if ($null -ne $previous) {
        $graphics.DrawLine($stockPen,[single]$previous.x,[single]$previous.y,$x,[single]$previous.y)
        $graphics.DrawLine($stockPen,$x,[single]$previous.y,$x,$y)
        # Restock/sellout transitions are event ticks, not stock magnitude. Draw
        # them in the gutter below the X axis so they never obscure the stock trace.
        $markerTop=[single]($plotBottom+2)
        $markerBottom=[single]($plotBottom+8)
        if ($showTransitions -and [long]$previous.stock -eq 0 -and [long]$row.stock -gt 0) {
            $graphics.DrawLine($restockPen,$x,$markerTop,$x,$markerBottom)
            if($showTooltips){
                $transitionHoverRegions.Add([pscustomobject]@{
                    x=[double]([Math]::Max($plotLeft,$x-4));y=[double]$plotBottom;w=9.0;h=12.0
                    text=('Restocked: '+(Format-InlineRelativeTime -Timestamp ([long]$row.timestamp) -NowEpoch $now))
                    kind='restock';timestamp=[long]$row.timestamp
                })
            }
        }
        if ($showTransitions -and [long]$previous.stock -gt 0 -and [long]$row.stock -eq 0) {
            $graphics.DrawLine($selloutPen,$x,$markerTop,$x,$markerBottom)
            if($showTooltips){
                $transitionHoverRegions.Add([pscustomobject]@{
                    x=[double]([Math]::Max($plotLeft,$x-4));y=[double]$plotBottom;w=9.0;h=12.0
                    text=('OoS: '+(Format-InlineRelativeTime -Timestamp ([long]$row.timestamp) -NowEpoch $now))
                    kind='oos';timestamp=[long]$row.timestamp
                })
            }
        }
    }
    $previous = [pscustomobject]@{ x=$x; y=$y; stock=[long]$row.stock }
}
if ($null -ne $previous -and [single]$previous.x -lt [single]$plotRight) {
    $graphics.DrawLine($stockPen,[single]$previous.x,[single]$previous.y,[single]$plotRight,[single]$previous.y)
}

# Restock-window brackets are a variance diagnostic around observed truth. Center
# each pair on the actual restock transition; never project unrelated old OoS anchors
# forward into the visible chart. The blue observed restock tick must sit between them.
if($showRestockWindowBounds -and $null -ne $restockWindowSummary){
    $varianceSeconds=[long]$restockWindowSummary.varianceSeconds
    $sampleCount=[int]$restockWindowSummary.sampleCount
    $forecastMarkerTop=[single]($plotBottom+3)
    $forecastMarkerBottom=[single]($plotBottom+6)
    if($varianceSeconds -gt 0){
        foreach($restockAt in $restockTransitions){
            if($restockAt -lt $cutoff -or $restockAt -gt $now){continue}
            $openAt=[long]$restockAt-$varianceSeconds
            $closeAt=[long]$restockAt+$varianceSeconds
            if($openAt -ge $cutoff){
                $x=Get-InlineX $openAt
                $graphics.DrawLine($restockWindowPen,$x,$forecastMarkerTop,$x,$forecastMarkerBottom)
                $graphics.DrawLine($restockWindowPen,$x,$forecastMarkerBottom,[single]($x+3),$forecastMarkerBottom)
                $forecastBoundaryCount++
                if($showTooltips){
                    $forecastHoverRegions.Add([pscustomobject]@{
                        x=[double]([Math]::Max($plotLeft,$x-4));y=[double]$plotBottom;w=9.0;h=12.0
                        text=('Restock variance opens: '+(Format-InlineRelativeTime -Timestamp $openAt -NowEpoch $now)+' | actual restock - '+(Format-InlineDuration -Seconds $varianceSeconds)+' | '+$sampleCount+' recent cycle(s)')
                        kind='restock_window_open';timestamp=$openAt
                    })
                }
            }
            if($closeAt -le $now){
                $x=Get-InlineX $closeAt
                $graphics.DrawLine($restockWindowPen,$x,$forecastMarkerTop,$x,$forecastMarkerBottom)
                $graphics.DrawLine($restockWindowPen,[single]($x-3),$forecastMarkerBottom,$x,$forecastMarkerBottom)
                $forecastBoundaryCount++
                if($showTooltips){
                    $forecastHoverRegions.Add([pscustomobject]@{
                        x=[double]([Math]::Max($plotLeft,$x-4));y=[double]$plotBottom;w=9.0;h=12.0
                        text=('Restock variance closes: '+(Format-InlineRelativeTime -Timestamp $closeAt -NowEpoch $now)+' | actual restock + '+(Format-InlineDuration -Seconds $varianceSeconds)+' | '+$sampleCount+' recent cycle(s)')
                        kind='restock_window_close';timestamp=$closeAt
                    })
                }
            }
        }
    }
}

# Strictly resolved forecasts use confirmed calibration truth. Keep this as
# validation metadata rather than another full curve.
if($showAccuracyMarkers){
    foreach($row in $resolvedRows){
        $x=Get-InlineX ([long]$row.forecastAt)
        $predicted=[double]$row.predictedProbability
        $actual=[int]$row.actualAnyStock
        $predictedY=Get-ChanceY $predicted
        $actualY=Get-ChanceY ([double]$actual)
        $graphics.DrawLine($errorPen,$x,$predictedY,$x,$actualY)
        $brush=if($actual -eq 1){$hitBrush}else{$missBrush}
        $graphics.FillEllipse($brush,[single]($x-1.75),[single]($actualY-1.75),[single]3.5,[single]3.5)
        if($showTooltips){
            $actualText=if($actual -eq 1){'HIT'}else{'MISS'}
            $hoverRegions.Add([pscustomobject]@{
                x=[double]([Math]::Max($plotLeft,$x-4));y=[double]$plotTop;w=9.0;h=[double]$plotHeight
                text=('Forecast '+([Math]::Round(100.0*$predicted,1))+'% | Actual '+$actualText+' | Brier '+([Math]::Round([double]$row.brier,3)))
                kind='resolved_forecast';timestamp=[long]$row.forecastAt
            })
        }
    }
}

# Draw the prospective probability continuously wherever it was actually recorded.
# No 50% display suppression is permitted; missing evidence remains a gap.
if($showChance){
    $previousChance=$null
    foreach ($row in $chanceRows) {
        $x=Get-InlineX ([long]$row.timestamp)
        $y=Get-ChanceY ([double]$row.probability)
        if ($null -ne $previousChance) {
            $gap=[long]$row.timestamp-[long]$previousChance.timestamp
            if ($gap -gt 0 -and $gap -le 300L) {
                $graphics.DrawLine($chancePen,[single]$previousChance.x,[single]$previousChance.y,$x,$y)
            }
        }
        $previousChance=[pscustomobject]@{x=$x;y=$y;timestamp=[long]$row.timestamp;probability=[double]$row.probability}
    }
    if ($null -ne $previousChance -and ($now-[long]$previousChance.timestamp) -le 180L -and [single]$previousChance.x -lt [single]$plotRight) {
        $graphics.DrawLine($chancePen,[single]$previousChance.x,[single]$previousChance.y,[single]$plotRight,[single]$previousChance.y)
    }
    
    
}

# Hindsight/accuracy regions take priority. Actual transitions are next, then the
# current-model restock-window boundary ticks use any remaining bounded capacity.
$remaining=[Math]::Max(0,$maximumHoverRegions-$hoverRegions.Count)
if($remaining -gt 0){
    foreach($region in @($transitionHoverRegions.ToArray()|Sort-Object timestamp -Descending|Select-Object -First $remaining)){
        $hoverRegions.Add($region)
    }
}
$remaining=[Math]::Max(0,$maximumHoverRegions-$hoverRegions.Count)
if($remaining -gt 0){
    foreach($region in @($forecastHoverRegions.ToArray()|Sort-Object timestamp -Descending|Select-Object -First $remaining)){
        $hoverRegions.Add($region)
    }
}

$maxLabel = if ($maxStock -gt 0) { ('{0:N0}' -f $maxStock) } else { '0' }
$graphics.DrawString($maxLabel,$labelFont,$labelBrush,0,0)
$graphics.DrawString('0',$labelFont,$labelBrush,18,88)
$graphics.DrawString(('-{0}h' -f $windowHours),$labelFont,$labelBrush,[single]($plotLeft-8),110)
$graphics.DrawString('now',$labelFont,$labelBrush,[single]($plotRight-18),110)

$infoCenterX=[single](($plotLeft+$plotRight)/2.0)
$infoCenterY=[single]114.0
$infoRadius=[single]6.0
$infoX=[double]($infoCenterX-$infoRadius-2.0)
$infoY=[double]($infoCenterY-$infoRadius-2.0)
$infoW=16.0
$infoH=16.0
if($infoEnabled){
    $graphics.DrawEllipse($infoPen,[single]($infoCenterX-$infoRadius),[single]($infoCenterY-$infoRadius),[single](2.0*$infoRadius),[single](2.0*$infoRadius))
    $graphics.FillEllipse($infoBrush,[single]($infoCenterX-0.8),[single]($infoCenterY-3.5),[single]1.6,[single]1.6)
    $graphics.DrawLine($infoPen,$infoCenterX,[single]($infoCenterY-0.5),$infoCenterX,[single]($infoCenterY+3.5))
}

$safeName = ($MarketKey -replace '[^a-zA-Z0-9_-]','_')
$imageFile = ('inline-graph-{0}-{1}.png' -f $safeName,$now)
$imagePath = Join-Path $GeneratedDir $imageFile
$stableImagePath = Join-Path $GeneratedDir ('inline-graph-' + $safeName + '.png')
$tmpImage = $imagePath + '.tmp'
$bitmap.Save($tmpImage,[System.Drawing.Imaging.ImageFormat]::Png)
$graphics.Dispose()
$bitmap.Dispose()
$gridMajor.Dispose(); $gridMinor.Dispose(); $stockPen.Dispose(); $chancePen.Dispose(); $hindsightBandBrush.Dispose(); $hindsightBoundaryPen.Dispose(); $errorPen.Dispose(); $hitBrush.Dispose(); $missBrush.Dispose(); $restockPen.Dispose(); $restockWindowPen.Dispose(); $selloutPen.Dispose(); $labelBrush.Dispose(); $labelFont.Dispose(); $infoPen.Dispose(); $infoBrush.Dispose()
Move-Item -LiteralPath $tmpImage -Destination $imagePath -Force
Copy-Item -LiteralPath $imagePath -Destination $stableImagePath -Force

$changes = 0
for ($i=1; $i -lt $rows.Count; $i++) {
    if ([long]$rows[$i].stock -ne [long]$rows[$i-1].stock) { $changes++ }
}
$earliestTimestamp = if ($rows.Count -gt 0) { [long]$rows[0].timestamp } else { 0L }
$latestTimestamp = if ($rows.Count -gt 0) { [long]$rows[$rows.Count-1].timestamp } else { 0L }
$unknownBefore = if ($predecessor.Count -gt 0) { 0L } else { $earliestTimestamp }

$hoverValues=@{}
$hoverCount=[Math]::Min($maximumHoverRegions,$hoverRegions.Count)
for($i=0;$i -lt $hoverCount;$i++){
    $region=$hoverRegions[$i]
    $n=$i+1
    $hoverValues['Hover'+$n+'X']=[Math]::Round([double]$region.x,2)
    $hoverValues['Hover'+$n+'Y']=[Math]::Round([double]$region.y,2)
    $hoverValues['Hover'+$n+'W']=[Math]::Round([Math]::Max(1.0,[double]$region.w),2)
    $hoverValues['Hover'+$n+'H']=[Math]::Round([Math]::Max(1.0,[double]$region.h),2)
    $hoverValues['Hover'+$n+'Text']=[string]$region.text
    $hoverValues['Hover'+$n+'Kind']=[string]$region.kind
}

$infoValues=@{}
$infoLineCount=if($infoEnabled){$infoLines.Count}else{0}
for($i=0;$i -lt $infoLineCount;$i++){
    $infoValues['InfoLine'+($i+1)]=[string]$infoLines[$i]
}

$specPath = Join-Path $GeneratedDir ('inline-graph-' + $safeName + '.kv')
$specValues=@{
    MarketKey = $MarketKey
    UpdatedAt = $now
    ImageFile = $imageFile
    StableImageFile = ('inline-graph-' + $safeName + '.png')
    HistorySource = $historySource
    MaxStock = $maxStock
    CurrentStock = $currentStock
    ChancePointCount = $chanceRows.Count
    CurrentChancePercent = $(if($chanceRows.Count -gt 0){[Math]::Round(100.0*[double]$chanceRows[$chanceRows.Count-1].probability,1)}else{-1})
    FlightSeconds = $flightSeconds
    RealizedHitProxyPointCount = $realizedRows.Count
    ResolvedForecastPointCount = $resolvedRows.Count
    ResolvedBrierScore = $(if($resolvedRows.Count -gt 0){[Math]::Round((($resolvedRows|Measure-Object brier -Average).Average),4)}else{-1})
    ResolvedObservedHitRate = $(if($resolvedRows.Count -gt 0){[Math]::Round((($resolvedRows|Measure-Object actualAnyStock -Average).Average),4)}else{-1})
    ResolvedMeanPredictedChance = $(if($resolvedRows.Count -gt 0){[Math]::Round((($resolvedRows|Measure-Object predictedProbability -Average).Average),4)}else{-1})
    PointCount = $rows.Count
    ChangeCount = $changes
    EarliestTimestamp = $earliestTimestamp
    LatestTimestamp = $latestTimestamp
    UnknownBeforeTimestamp = $unknownBefore
    WindowStartTimestamp = $cutoff
    HindsightWindowCount = $realizedWindows.Count
    ForecastRestockBoundaryCount = $forecastBoundaryCount
    RestockWindowSampleCount = $(if($null -ne $restockWindowSummary){[int]$restockWindowSummary.sampleCount}else{0})
    RestockWindowEarlyDelaySeconds = $(if($null -ne $restockWindowSummary){[long]$restockWindowSummary.earliestDelaySeconds}else{0})
    RestockWindowLateDelaySeconds = $(if($null -ne $restockWindowSummary){[long]$restockWindowSummary.latestDelaySeconds}else{0})
    RestockWindowVarianceSeconds = $(if($null -ne $restockWindowSummary){[long]$restockWindowSummary.varianceSeconds}else{0})
    ShowGrid = $(if($showGrid){1}else{0})
    ShowTransitions = $(if($showTransitions){1}else{0})
    ShowRestockWindowBounds = $(if($showRestockWindowBounds){1}else{0})
    ShowChance = $(if($showChance){1}else{0})
    ShowHindsightWindows = $(if($showHindsightWindows){1}else{0})
    ShowAccuracyMarkers = $(if($showAccuracyMarkers){1}else{0})
    ShowTooltips = $(if($showTooltips){1}else{0})
    HoverCount = $hoverCount
    InfoEnabled = $(if($infoEnabled){1}else{0})
    InfoX = [Math]::Round($infoX,2)
    InfoY = [Math]::Round($infoY,2)
    InfoW = [Math]::Round($infoW,2)
    InfoH = [Math]::Round($infoH,2)
    InfoLineCount = $infoLineCount
    InfoTimelineCycleCount = $(if($null -ne $infoTimeline){[int]$infoTimeline.cycleCount}else{0})
}
foreach($hoverKey in $hoverValues.Keys){$specValues[$hoverKey]=$hoverValues[$hoverKey]}
foreach($infoKey in $infoValues.Keys){$specValues[$infoKey]=$infoValues[$infoKey]}
Write-InlineKvAtomic -Path $specPath -Values $specValues

Get-ChildItem -LiteralPath $GeneratedDir -Filter 'inline-graph-*-*.png' -File -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending |
    Select-Object -Skip 24 |
    Remove-Item -Force -ErrorAction SilentlyContinue

exit 0