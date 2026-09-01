param(
    [int]$MinimumPollIntervalSeconds = 60,
    [int]$MaximumProviderAgeSeconds = 300,
    [switch]$Force,
    [Alias('SkipMain')]
    [switch]$ShadowCollectorSkipMain
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$ObservationFile = Join-Path $RuntimeDir 'observations.jsonl'
$CycleFile = Join-Path $RuntimeDir 'cycles.jsonl'
$PendingObservationFile = Join-Path $RuntimeDir 'observations.pending.jsonl'
$PendingCycleFile = Join-Path $RuntimeDir 'cycles.pending.jsonl'
$SeedCycleFile = Join-Path $ProjectRoot 'data\seed\cycles.jsonl'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$ErrorFile = Join-Path $RuntimeDir 'shadow-collection-error.txt'
$CycleForecastFilter = Join-Path $PSScriptRoot 'CycleForecastFilter.ps1'
$AtomicFileScript = Join-Path $PSScriptRoot 'AtomicFile.ps1'

. $CycleForecastFilter
if (-not (Test-Path -LiteralPath $AtomicFileScript)) { throw 'AtomicFile.ps1 is required for shared history/state IO.' }
. $AtomicFileScript

New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
$script:blockedAppendPaths=@{}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Read-TravelAssistantSharedText -Path $Path
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-JsonAtomic {
    param([string]$Path, [object]$Value, [int]$Depth = 16)
    Write-TravelAssistantAtomicJson -Path $Path -Value $Value -Depth $Depth
}

function Get-DynamicProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Set-DynamicProperty {
    param([object]$Object, [string]$Name, [object]$Value)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    } else {
        $property.Value = $Value
    }
}

function Get-NowEpoch {
    return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}

function Get-EngineState {
    $state = Read-JsonFile $EngineStateFile
    if ($null -eq $state) {
        $state = [pscustomobject]@{
            schemaVersion = 1
            lastPruneAt = 0
            destinations = [pscustomobject]@{}
            resaleCache = [pscustomobject]@{}
            observedMarkets = [pscustomobject]@{}
            shadowCollection = [pscustomobject]@{
                lastPollAt = 0
                lastProvider = ''
                countriesSeen = 0
                marketsSeen = 0
                legacyMarketsSeen = 0
                observationsWritten = 0
                cyclesCompleted = 0
                countryProviders = [pscustomobject]@{}
                staleCountries = [string[]]@()
                lastErrorAt = 0
                lastError = ''
            }
        }
    }
    if (-not $state.PSObject.Properties['destinations']) { $state | Add-Member NoteProperty destinations ([pscustomobject]@{}) }
    if (-not $state.PSObject.Properties['resaleCache']) { $state | Add-Member NoteProperty resaleCache ([pscustomobject]@{}) }
    if (-not $state.PSObject.Properties['observedMarkets']) { $state | Add-Member NoteProperty observedMarkets ([pscustomobject]@{}) }
    if (-not $state.PSObject.Properties['shadowCollection']) {
        $state | Add-Member NoteProperty shadowCollection ([pscustomobject]@{
            lastPollAt = 0
            lastProvider = ''
            countriesSeen = 0
            marketsSeen = 0
            legacyMarketsSeen = 0
            observationsWritten = 0
            cyclesCompleted = 0
            countryProviders = [pscustomobject]@{}
            staleCountries = [string[]]@()
            lastErrorAt = 0
            lastError = ''
        })
    }
    foreach ($name in @('lastPollAt','lastProvider','countriesSeen','marketsSeen','legacyMarketsSeen','observationsWritten','cyclesCompleted','lastErrorAt','lastError')) {
        if (-not $state.shadowCollection.PSObject.Properties[$name]) {
            $default = if ($name -in @('lastProvider','lastError')) { '' } else { 0 }
            $state.shadowCollection | Add-Member NoteProperty $name $default
        }
    }
    if (-not $state.shadowCollection.PSObject.Properties['countryProviders']) { $state.shadowCollection | Add-Member NoteProperty countryProviders ([pscustomobject]@{}) }
    if (-not $state.shadowCollection.PSObject.Properties['staleCountries']) { $state.shadowCollection | Add-Member NoteProperty staleCountries ([string[]]@()) }
    return $state
}

function Get-DestinationState {
    param([object]$EngineState, [string]$Key)
    $dest = Get-DynamicProperty $EngineState.destinations $Key
    if ($null -eq $dest) {
        $dest = [pscustomobject]@{
            lastStock = -1
            lastForeignPrice = 0
            lastSourceTimestamp = 0
            lastSellOutAt = 0
            lastSellOutLowerBoundAt = 0
            lastSellOutUpperBoundAt = 0
            lastSellOutBoundaryQuality = 'unknown'
            continuityInvalidatedAt = 0
            boundaryPolicy = $null
            activeCycle = $null
        }
        Set-DynamicProperty $EngineState.destinations $Key $dest
    }
    foreach ($property in @{
        lastSellOutLowerBoundAt=0L
        lastSellOutUpperBoundAt=0L
        lastSellOutBoundaryQuality='unknown'
        continuityInvalidatedAt=0L
        boundaryPolicy=$null
    }.GetEnumerator()) {
        if (-not $dest.PSObject.Properties[$property.Key]) { $dest | Add-Member NoteProperty $property.Key $property.Value }
    }
    return $dest
}

function Get-LivePayloadFreshness {
    param([object]$Payload, [long]$NowEpoch)
    $timestamps = @()
    if ($null -eq $Payload -or $null -eq $Payload.stocks) {
        return [pscustomobject]@{ timestampCount=0; freshest=0L; oldest=0L; freshestAgeSeconds=[long]::MaxValue }
    }
    foreach ($property in @($Payload.stocks.PSObject.Properties)) {
        $country = $property.Value
        if ($null -eq $country -or -not $country.PSObject.Properties['update']) { continue }
        $timestamp = 0L
        try { $timestamp = [long]$country.update } catch { $timestamp = 0L }
        if ($timestamp -gt 0) { $timestamps += $timestamp }
    }
    if ($timestamps.Count -eq 0) {
        return [pscustomobject]@{ timestampCount=0; freshest=0L; oldest=0L; freshestAgeSeconds=[long]::MaxValue }
    }
    $freshest = [long]($timestamps | Measure-Object -Maximum).Maximum
    $oldest = [long]($timestamps | Measure-Object -Minimum).Minimum
    $age = [Math]::Max(0L, $NowEpoch - $freshest)
    return [pscustomobject]@{ timestampCount=$timestamps.Count; freshest=$freshest; oldest=$oldest; freshestAgeSeconds=$age }
}

function Assert-LivePayloadFresh {
    param([object]$Payload, [long]$NowEpoch, [int]$MaximumAgeSeconds, [string]$ProviderName)
    $freshness = Get-LivePayloadFreshness -Payload $Payload -NowEpoch $NowEpoch
    if ([int]$freshness.timestampCount -le 0) {
        throw ('{0} response has no usable country update timestamps' -f $ProviderName)
    }
    if ([long]$freshness.freshestAgeSeconds -gt [long]$MaximumAgeSeconds) {
        throw ('{0} response is stale: freshest country sample is {1}s old (limit {2}s)' -f $ProviderName,[long]$freshness.freshestAgeSeconds,$MaximumAgeSeconds)
    }
    return $freshness
}

function Get-CountryProviderCode {
    param([object]$Country,[string]$Source)
    if ($null -eq $Country -or -not $Country.PSObject.Properties['providerCodes']) { return '' }
    $code = [string](Get-DynamicProperty $Country.providerCodes $Source)
    if ([string]::IsNullOrWhiteSpace($code) -and $Source -eq 'prometheus') {
        $code = [string](Get-DynamicProperty $Country.providerCodes 'yata')
    }
    return $code
}

function Get-CountryPayloadStatus {
    param(
        [object]$Payload,
        [object]$Country,
        [string]$Source,
        [long]$NowEpoch,
        [int]$MaximumAgeSeconds
    )
    $countryId = if ($null -ne $Country -and $Country.PSObject.Properties['id']) { [string]$Country.id } else { '' }
    $code = Get-CountryProviderCode -Country $Country -Source $Source
    if ([string]::IsNullOrWhiteSpace($code) -or $null -eq $Payload -or $null -eq $Payload.stocks) {
        return [pscustomobject]@{ country=$countryId; source=$Source; code=$code; available=$false; fresh=$false; timestamp=0L; ageSeconds=[long]::MaxValue; countryObject=$null }
    }
    $countryObj = Get-DynamicProperty $Payload.stocks $code
    if ($null -eq $countryObj -or -not $countryObj.PSObject.Properties['stocks']) {
        return [pscustomobject]@{ country=$countryId; source=$Source; code=$code; available=$false; fresh=$false; timestamp=0L; ageSeconds=[long]::MaxValue; countryObject=$countryObj }
    }
    $timestamp = 0L
    if ($countryObj.PSObject.Properties['update']) {
        try { $timestamp = [long]$countryObj.update } catch { $timestamp = 0L }
    }
    $age = if ($timestamp -gt 0) { [Math]::Max(0L,$NowEpoch-$timestamp) } else { [long]::MaxValue }
    $fresh = ($timestamp -gt 0 -and $age -le [long]$MaximumAgeSeconds)
    return [pscustomobject]@{ country=$countryId; source=$Source; code=$code; available=$true; fresh=$fresh; timestamp=$timestamp; ageSeconds=$age; countryObject=$countryObj }
}

function Invoke-LiveStockProvider {
    param([string]$Id,[string]$Uri)
    try {
        $payload = Invoke-RestMethod -Method Get -Uri $Uri -Headers @{ Accept = 'application/json' } -TimeoutSec 5
        if ($null -eq $payload -or $null -eq $payload.stocks) { throw 'response does not contain stocks' }
        return [pscustomobject]@{ source=$Id; payload=$payload; error='' }
    } catch {
        return [pscustomobject]@{ source=$Id; payload=$null; error=$_.Exception.Message }
    }
}

function Get-LiveStockProviderSet {
    param([object[]]$CollectionCountries,[long]$NowEpoch,[int]$MaximumAgeSeconds)
    $snapshots = @{}
    $errors = @()

    $primary = Invoke-LiveStockProvider -Id 'prometheus' -Uri 'https://api.prombot.co.uk/api/travel'
    if ($null -ne $primary.payload) { $snapshots['prometheus'] = $primary }
    elseif (-not [string]::IsNullOrWhiteSpace([string]$primary.error)) { $errors += ('prometheus: ' + [string]$primary.error) }

    $needFallback = ($null -eq $primary.payload)
    if (-not $needFallback) {
        foreach ($country in @($CollectionCountries)) {
            $status = Get-CountryPayloadStatus -Payload $primary.payload -Country $country -Source 'prometheus' -NowEpoch $NowEpoch -MaximumAgeSeconds $MaximumAgeSeconds
            if (-not [bool]$status.fresh) { $needFallback = $true; break }
        }
    }

    if ($needFallback) {
        $fallback = Invoke-LiveStockProvider -Id 'yata' -Uri 'https://yata.yt/api/v1/travel/export/'
        if ($null -ne $fallback.payload) { $snapshots['yata'] = $fallback }
        elseif (-not [string]::IsNullOrWhiteSpace([string]$fallback.error)) { $errors += ('yata: ' + [string]$fallback.error) }
    }

    if ($snapshots.Count -eq 0) {
        throw ('All live stock providers failed network/shape validation: ' + ($errors -join ' | '))
    }
    return [pscustomobject]@{ snapshots=$snapshots; errors=[string[]]$errors }
}

function Select-LiveCountryProvider {
    param([object]$ProviderSet,[object]$Country,[long]$NowEpoch,[int]$MaximumAgeSeconds)
    $candidates = @()
    foreach ($source in @('prometheus','yata')) {
        if ($null -eq $ProviderSet -or -not $ProviderSet.snapshots.ContainsKey($source)) { continue }
        $snapshot = $ProviderSet.snapshots[$source]
        if ($null -eq $snapshot -or $null -eq $snapshot.payload) { continue }
        $status = Get-CountryPayloadStatus -Payload $snapshot.payload -Country $Country -Source $source -NowEpoch $NowEpoch -MaximumAgeSeconds $MaximumAgeSeconds
        if (-not [bool]$status.fresh) { continue }
        $priority = if ($source -eq 'prometheus') { 0 } else { 1 }
        $candidates += [pscustomobject]@{ source=$source; payload=$snapshot.payload; status=$status; priority=$priority }
    }
    if ($candidates.Count -eq 0) { return $null }
    return @($candidates | Sort-Object @{Expression={ [long]$_.status.timestamp };Descending=$true},priority | Select-Object -First 1)[0]
}

function Get-LiveStockPayload {
    param([long]$NowEpoch, [int]$MaximumAgeSeconds)
    $providers = @(
        [pscustomobject]@{ id = 'prometheus'; uri = 'https://api.prombot.co.uk/api/travel' },
        [pscustomobject]@{ id = 'yata'; uri = 'https://yata.yt/api/v1/travel/export/' }
    )
    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($provider in $providers) {
        try {
            $payload = Invoke-RestMethod -Method Get -Uri ([string]$provider.uri) -Headers @{ Accept = 'application/json' } -TimeoutSec 5
            if ($null -eq $payload -or $null -eq $payload.stocks) { throw 'response does not contain stocks' }
            $freshness = Assert-LivePayloadFresh -Payload $payload -NowEpoch $NowEpoch -MaximumAgeSeconds $MaximumAgeSeconds -ProviderName ([string]$provider.id)
            return [pscustomobject]@{ source = [string]$provider.id; payload = $payload; freshness = $freshness }
        } catch {
            $errors.Add(('{0}: {1}' -f [string]$provider.id, $_.Exception.Message))
        }
    }

    throw ('All live stock providers failed freshness/network validation: ' + ($errors -join ' | '))
}

function Get-LiveStockObservationsForCountry {
    param(
        [object]$Payload,
        [object]$Country,
        [long]$Now,
        [string]$Source
    )

    $rows = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Payload -or $null -eq $Payload.stocks -or [string]::IsNullOrWhiteSpace($Source)) { return $rows.ToArray() }

    $code = Get-CountryProviderCode -Country $Country -Source $Source
    if ([string]::IsNullOrWhiteSpace($code)) { return $rows.ToArray() }

    $countryObj = Get-DynamicProperty $Payload.stocks $code
    if ($null -eq $countryObj -or -not $countryObj.PSObject.Properties['stocks']) { return $rows.ToArray() }

    $sourceTimestamp = 0L
    if ($countryObj.PSObject.Properties['update']) { $sourceTimestamp = [long]$countryObj.update }
    $timestamp = if ($sourceTimestamp -gt 0) { $sourceTimestamp } else { $Now }

    foreach ($row in @($countryObj.stocks)) {
        if ($null -eq $row) { continue }
        $validRow = $true
        foreach ($required in @('id','quantity','cost')) {
            if (-not $row.PSObject.Properties[$required]) {
                $validRow = $false
                break
            }
        }
        if (-not $validRow) { continue }

        $itemId = [int]$row.id
        $stock = [int]$row.quantity
        $foreignPrice = [long]$row.cost
        if ($itemId -le 0 -or $stock -lt 0 -or $foreignPrice -lt 0) { continue }

        $itemName = ''
        if ($row.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$row.name)) {
            $itemName = [string]$row.name
        }

        $rows.Add([pscustomobject]@{
            schemaVersion = 1
            timestamp = [long]$timestamp
            country = [string]$Country.id
            itemId = $itemId
            itemName = $itemName
            stock = $stock
            foreignPrice = $foreignPrice
            source = $Source
            sourceTimestamp = $sourceTimestamp
        })
    }

    return $rows.ToArray()
}

function Write-SharedAppendBytes {
    param([string]$Path,[byte[]]$Bytes,[int]$MaximumAttempts=12)
    $shareValue = ([int][System.IO.FileShare]::ReadWrite -bor [int][System.IO.FileShare]::Delete)
    $share = [System.IO.FileShare]$shareValue
    $appendMutex = New-Object System.Threading.Mutex($false,(Get-TravelAssistantAtomicMutexName -Path $Path))
    $appendAcquired = $false
    try {
        try { $appendAcquired = $appendMutex.WaitOne(5000) }
        catch [System.Threading.AbandonedMutexException] { $appendAcquired = $true }
        if (-not $appendAcquired) { throw ('Timed out waiting to append shared journal: ' + $Path) }

        for ($attempt=1; $attempt -le $MaximumAttempts; $attempt++) {
            $stream = $null
            try {
                $stream = New-Object System.IO.FileStream($Path,[System.IO.FileMode]::Append,[System.IO.FileAccess]::Write,$share)
                $stream.Write($Bytes,0,$Bytes.Length)
                $stream.Flush($true)
                return
            } catch {
                if ($attempt -ge $MaximumAttempts -or ($_.Exception -isnot [System.IO.IOException] -and $_.Exception -isnot [System.UnauthorizedAccessException])) { throw }
                Start-Sleep -Milliseconds (50 * [Math]::Min($attempt,5))
            } finally {
                if ($null -ne $stream) { $stream.Dispose() }
            }
        }
    } finally {
        if ($appendAcquired) { try { $appendMutex.ReleaseMutex() } catch { } }
        $appendMutex.Dispose()
    }
}

function Append-JsonLine {
    param([string]$Path,[object]$Value,[string]$FallbackPath='')
    $line = ($Value | ConvertTo-Json -Compress -Depth 10) + [Environment]::NewLine
    $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($line)
    if ($script:blockedAppendPaths.ContainsKey($Path) -and -not [string]::IsNullOrWhiteSpace($FallbackPath)) {
        Write-SharedAppendBytes -Path $FallbackPath -Bytes $bytes
        return
    }
    try {
        Write-SharedAppendBytes -Path $Path -Bytes $bytes
    } catch {
        if ([string]::IsNullOrWhiteSpace($FallbackPath)) { throw }
        # Do not let a OneDrive/Rainmeter reader abort collection for every other
        # market. The pending journal is local evidence and is merged losslessly
        # into the canonical JSONL file on a later heartbeat.
        $script:blockedAppendPaths[$Path]=$true
        Write-SharedAppendBytes -Path $FallbackPath -Bytes $bytes
    }
}

function Flush-PendingJsonLines {
    param([string]$Path,[string]$PendingPath)
    if (-not (Test-Path -LiteralPath $PendingPath)) { return $true }
    $pendingBytes = $null
    try {
        $pendingBytes = [System.IO.File]::ReadAllBytes($PendingPath)
        if ($pendingBytes.Length -gt 0) { Write-SharedAppendBytes -Path $Path -Bytes $pendingBytes }
        Remove-Item -LiteralPath $PendingPath -Force -ErrorAction Stop
        return $true
    } catch {
        $script:blockedAppendPaths[$Path]=$true
        return $false
    }
}

function Read-CycleHistoryMap {
    param([string[]]$Paths)
    $map = @{}
    foreach ($path in $Paths) {
        if (-not (Test-Path -LiteralPath $path)) { continue }
        foreach ($line in [System.IO.File]::ReadLines($path)) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            try { $row = $line | ConvertFrom-Json } catch { continue }
            if ($null -eq $row -or -not $row.PSObject.Properties['country'] -or -not $row.PSObject.Properties['itemId']) { continue }
            $key = (([string]$row.country) + ':' + [string][int]$row.itemId).ToLowerInvariant()
            if (-not $map.ContainsKey($key)) { $map[$key] = New-Object System.Collections.Generic.List[object] }
            $map[$key].Add($row)
        }
    }
    return $map
}

function Invalidate-PhaseAnchorForGap {
    param([object]$DestState,[object]$Observation,[object]$BoundaryPolicy)
    $previousAt = [long]$DestState.lastSourceTimestamp
    $currentAt = [long]$Observation.sourceTimestamp
    if ($currentAt -le 0) { $currentAt = [long]$Observation.timestamp }
    if ($previousAt -le 0 -or $currentAt -le $previousAt) { return $false }
    $gap = $currentAt - $previousAt
    $hardGap = [Math]::Min([long]$BoundaryPolicy.selloutHardGapSeconds,[long]$BoundaryPolicy.restockHardGapSeconds)
    if ($gap -lt $hardGap) { return $false }

    Set-DynamicProperty -Object $DestState -Name 'continuityInvalidatedAt' -Value $currentAt
    if ([int]$Observation.stock -gt 0) {
        $DestState.activeCycle = $null
    } else {
        $DestState.lastSellOutAt = 0L
        Set-DynamicProperty -Object $DestState -Name 'lastSellOutLowerBoundAt' -Value 0L
        Set-DynamicProperty -Object $DestState -Name 'lastSellOutUpperBoundAt' -Value 0L
        Set-DynamicProperty -Object $DestState -Name 'lastSellOutBoundaryQuality' -Value 'unknown_gap'
    }
    return $true
}

function Update-CycleState {
    param([object]$DestState, [object]$Observation, [object]$BoundaryPolicy)
    $previousStock = [int]$DestState.lastStock
    $currentStock = [int]$Observation.stock
    $ts = [long]$Observation.timestamp
    $previousObservedAt = [long]$DestState.lastSourceTimestamp
    if ($previousObservedAt -le 0 -or $previousObservedAt -gt $ts) { $previousObservedAt = $ts }
    if ($null -eq $BoundaryPolicy) { $BoundaryPolicy = Get-CycleBoundaryPolicy -Cycles @() -ExpectedPollIntervalSeconds 60 }
    $gapSeconds = [Math]::Max(0L,$ts-$previousObservedAt)
    $completed = $null

    if (($previousStock -gt 0 -and $currentStock -gt 0) -or ($previousStock -eq 0 -and $currentStock -eq 0)) {
        [void](Invalidate-PhaseAnchorForGap -DestState $DestState -Observation $Observation -BoundaryPolicy $BoundaryPolicy)
    }

    if ($previousStock -ge 0) {
        if ($previousStock -eq 0 -and $currentStock -gt 0) {
            $quality = Get-CycleBoundaryQuality -GapSeconds $gapSeconds -Policy $BoundaryPolicy -Phase restock
            $restockKnown = ($quality -ne 'unknown_gap')
            $previousSoldOutAt = [long]$DestState.lastSellOutAt
            $previousSoldOutLower = if ($DestState.PSObject.Properties['lastSellOutLowerBoundAt'] -and [long]$DestState.lastSellOutLowerBoundAt -gt 0) { [long]$DestState.lastSellOutLowerBoundAt } else { $previousSoldOutAt }
            $previousSoldOutUpper = if ($DestState.PSObject.Properties['lastSellOutUpperBoundAt'] -and [long]$DestState.lastSellOutUpperBoundAt -gt 0) { [long]$DestState.lastSellOutUpperBoundAt } else { $previousSoldOutAt }
            $previousSelloutQuality = if ($DestState.PSObject.Properties['lastSellOutBoundaryQuality']) { [string]$DestState.lastSellOutBoundaryQuality } else { 'legacy_exact' }
            $DestState.activeCycle = [pscustomobject]@{
                previousSoldOutAt = $previousSoldOutAt
                previousSoldOutLowerBoundAt = $previousSoldOutLower
                previousSoldOutUpperBoundAt = $previousSoldOutUpper
                previousSellOutBoundaryQuality = $previousSelloutQuality
                restockAt = $(if ($restockKnown) { $ts } else { 0L })
                restockLowerBoundAt = $(if ($restockKnown) { $previousObservedAt } else { 0L })
                restockUpperBoundAt = $(if ($restockKnown) { $ts } else { 0L })
                restockBoundaryQuality = $quality
                restockGapSeconds = $gapSeconds
                restockQuantity = $currentStock
                foreignPrice = [long]$Observation.foreignPrice
                source = [string]$Observation.source
            }
            if ($restockKnown) {
                Set-DynamicProperty -Object $DestState -Name 'continuityInvalidatedAt' -Value 0L
            } else {
                Set-DynamicProperty -Object $DestState -Name 'continuityInvalidatedAt' -Value $ts
                $DestState.lastSellOutAt = 0L
                Set-DynamicProperty -Object $DestState -Name 'lastSellOutLowerBoundAt' -Value 0L
                Set-DynamicProperty -Object $DestState -Name 'lastSellOutUpperBoundAt' -Value 0L
                Set-DynamicProperty -Object $DestState -Name 'lastSellOutBoundaryQuality' -Value 'unknown_gap'
            }
        } elseif ($previousStock -gt 0 -and $currentStock -eq 0) {
            $quality = Get-CycleBoundaryQuality -GapSeconds $gapSeconds -Policy $BoundaryPolicy -Phase sellout
            $selloutKnown = ($quality -ne 'unknown_gap')
            $selloutLower = if ($selloutKnown) { $previousObservedAt } else { 0L }
            $selloutUpper = if ($selloutKnown) { $ts } else { 0L }
            $DestState.lastSellOutAt = $selloutLower
            Set-DynamicProperty -Object $DestState -Name 'lastSellOutLowerBoundAt' -Value $selloutLower
            Set-DynamicProperty -Object $DestState -Name 'lastSellOutUpperBoundAt' -Value $selloutUpper
            Set-DynamicProperty -Object $DestState -Name 'lastSellOutBoundaryQuality' -Value $quality
            if ($selloutKnown) { Set-DynamicProperty -Object $DestState -Name 'continuityInvalidatedAt' -Value 0L }
            else { Set-DynamicProperty -Object $DestState -Name 'continuityInvalidatedAt' -Value $ts }
            if ($null -ne $DestState.activeCycle) {
                $restockAt = [long]$DestState.activeCycle.restockAt
                $previousSoldOutAt = [long]$DestState.activeCycle.previousSoldOutAt
                $restockLower = if ($DestState.activeCycle.PSObject.Properties['restockLowerBoundAt']) { [long]$DestState.activeCycle.restockLowerBoundAt } else { $restockAt }
                $restockUpper = if ($DestState.activeCycle.PSObject.Properties['restockUpperBoundAt']) { [long]$DestState.activeCycle.restockUpperBoundAt } else { $restockAt }
                $previousSoldOutLower = if ($DestState.activeCycle.PSObject.Properties['previousSoldOutLowerBoundAt']) { [long]$DestState.activeCycle.previousSoldOutLowerBoundAt } else { $previousSoldOutAt }
                $previousSoldOutUpper = if ($DestState.activeCycle.PSObject.Properties['previousSoldOutUpperBoundAt']) { [long]$DestState.activeCycle.previousSoldOutUpperBoundAt } else { $previousSoldOutAt }
                $restockQuality = if ($DestState.activeCycle.PSObject.Properties['restockBoundaryQuality']) { [string]$DestState.activeCycle.restockBoundaryQuality } else { 'legacy_exact' }
                $previousSelloutQuality = if ($DestState.activeCycle.PSObject.Properties['previousSellOutBoundaryQuality']) { [string]$DestState.activeCycle.previousSellOutBoundaryQuality } else { 'legacy_exact' }
                $availabilityMinimum = if ($selloutKnown -and $restockUpper -gt 0) { [Math]::Max(0L,$selloutLower-$restockUpper) } else { 0L }
                $availabilityMaximum = if ($selloutKnown -and $restockLower -gt 0) { [Math]::Max(0L,$selloutUpper-$restockLower) } else { 0L }
                $delayMinimum = if ($restockLower -gt 0 -and $previousSoldOutUpper -gt 0) { [Math]::Max(0L,$restockLower-$previousSoldOutUpper) } else { 0L }
                $delayMaximum = if ($restockUpper -gt 0 -and $previousSoldOutLower -gt 0) { [Math]::Max(0L,$restockUpper-$previousSoldOutLower) } else { 0L }
                $availabilityEligible = ($selloutKnown -and $restockAt -gt 0 -and $availabilityMinimum -gt 0)
                $restockDelayEligible = ($restockAt -gt 0 -and $previousSoldOutAt -gt 0 -and $previousSelloutQuality -ne 'unknown_gap' -and $delayMaximum -gt 0)
                $trendEligible = ($availabilityEligible -and $restockDelayEligible -and $quality -ne 'uncertain' -and $restockQuality -ne 'uncertain' -and $previousSelloutQuality -ne 'uncertain')
                $completed = [pscustomobject]@{
                    schemaVersion = 2
                    country = [string]$Observation.country
                    itemId = [int]$Observation.itemId
                    foreignPrice = [long]$DestState.activeCycle.foreignPrice
                    restockAt = $restockAt
                    restockLowerBoundAt = $restockLower
                    restockUpperBoundAt = $restockUpper
                    restockBoundaryQuality = $restockQuality
                    restockQuantity = [int]$DestState.activeCycle.restockQuantity
                    soldOutAt = $selloutLower
                    soldOutLowerBoundAt = $selloutLower
                    soldOutUpperBoundAt = $selloutUpper
                    soldOutBoundaryQuality = $quality
                    availabilitySeconds = $availabilityMinimum
                    availabilityMinimumSeconds = $availabilityMinimum
                    availabilityMaximumSeconds = $availabilityMaximum
                    availabilityEligible = $availabilityEligible
                    previousSoldOutAt = $previousSoldOutAt
                    previousSoldOutLowerBoundAt = $previousSoldOutLower
                    previousSoldOutUpperBoundAt = $previousSoldOutUpper
                    restockDelaySeconds = $delayMaximum
                    restockDelayMinimumSeconds = $delayMinimum
                    restockDelayMaximumSeconds = $delayMaximum
                    restockDelayEligible = $restockDelayEligible
                    trendEligible = $trendEligible
                    forecastEligible = ($availabilityEligible -and $restockDelayEligible)
                    source = [string]$DestState.activeCycle.source
                }
                $DestState.activeCycle = $null
            }
        }
    }

    $DestState.lastStock = $currentStock
    $DestState.lastForeignPrice = [long]$Observation.foreignPrice
    $sourceTimestamp = [long]$Observation.sourceTimestamp
    $DestState.lastSourceTimestamp = $(if ($sourceTimestamp -gt 0) { $sourceTimestamp } else { $ts })
    return $completed
}

function Get-InactiveMarketIndex {
    param([object]$OverrideConfig)
    $index = @{}
    if ($null -eq $OverrideConfig -or -not $OverrideConfig.PSObject.Properties['marketOverrides']) { return $index }
    foreach ($property in @($OverrideConfig.marketOverrides.PSObject.Properties)) {
        if ($null -eq $property.Value -or -not $property.Value.PSObject.Properties['active']) { continue }
        if ([bool]$property.Value.active) { continue }
        $key = ([string]$property.Name).Trim().ToLowerInvariant()
        if (-not [string]::IsNullOrWhiteSpace($key)) { $index[$key] = $true }
    }
    return $index
}

function Test-ObservationChanged {
    param([object]$DestState, [object]$Observation)
    # The retained observation database is stock-transition evidence. Foreign
    # prices belong to current observed-market state and must not create dozens
    # of duplicate zero-stock history rows merely because pricing moved.
    return ([int]$DestState.lastStock -ne [int]$Observation.stock)
}

function Update-ObservedMarketMetadata {
    param([object]$EngineState, [object]$Observation, [long]$Now)
    $key = ([string]$Observation.country) + ':' + ([string]$Observation.itemId)
    $entry = Get-DynamicProperty $EngineState.observedMarkets $key
    $providerName = ''
    if ($Observation.PSObject.Properties['itemName'] -and -not [string]::IsNullOrWhiteSpace([string]$Observation.itemName)) {
        $providerName = [string]$Observation.itemName
    }

    if ($null -eq $entry) {
        $entry = [pscustomobject]@{
            country = [string]$Observation.country
            itemId = [int]$Observation.itemId
            providerName = $providerName
            firstSeenAt = $Now
            lastSeenAt = $Now
            lastStock = [int]$Observation.stock
            lastForeignPrice = [long]$Observation.foreignPrice
            source = [string]$Observation.source
            sourceTimestamp = [long]$Observation.sourceTimestamp
        }
        Set-DynamicProperty $EngineState.observedMarkets $key $entry
        return
    }

    if (-not $entry.PSObject.Properties['providerName']) {
        $entry | Add-Member NoteProperty providerName ''
    }
    if (-not [string]::IsNullOrWhiteSpace($providerName)) {
        $entry.providerName = $providerName
    }
    $entry.lastSeenAt = $Now
    $entry.lastStock = [int]$Observation.stock
    $entry.lastForeignPrice = [long]$Observation.foreignPrice
    $entry.source = [string]$Observation.source
    $entry.sourceTimestamp = [long]$Observation.sourceTimestamp
}

function Write-ShadowError {
    param([object]$EngineState, [long]$Now, [string]$Message)
    $clean = ([string]$Message).Replace("`r", ' ').Replace("`n", ' ').Trim()
    if ($clean.Length -gt 600) { $clean = $clean.Substring(0, 600) }
    $EngineState.shadowCollection.lastErrorAt = $Now
    $EngineState.shadowCollection.lastError = $clean
    try { [System.IO.File]::WriteAllText($ErrorFile, $clean, [System.Text.UTF8Encoding]::new($false)) } catch { }
}

if ($ShadowCollectorSkipMain) { return }
if ($MinimumPollIntervalSeconds -lt 60) { $MinimumPollIntervalSeconds = 60 }
if ($MaximumProviderAgeSeconds -lt 60) { $MaximumProviderAgeSeconds = 60 }

$now = Get-NowEpoch
$engineState = Get-EngineState
$lastPollAt = [long]$engineState.shadowCollection.lastPollAt
if (-not $Force -and $lastPollAt -gt 0 -and ($now - $lastPollAt) -lt $MinimumPollIntervalSeconds) { return }

$pendingObservationsFlushed = Flush-PendingJsonLines -Path $ObservationFile -PendingPath $PendingObservationFile
$pendingCyclesFlushed = Flush-PendingJsonLines -Path $CycleFile -PendingPath $PendingCycleFile
Set-DynamicProperty -Object $engineState.shadowCollection -Name 'pendingObservationJournal' -Value (-not $pendingObservationsFlushed -or (Test-Path -LiteralPath $PendingObservationFile))
Set-DynamicProperty -Object $engineState.shadowCollection -Name 'pendingCycleJournal' -Value (-not $pendingCyclesFlushed -or (Test-Path -LiteralPath $PendingCycleFile))

$countriesConfig = Read-JsonFile (Join-Path $ConfigDir 'countries.json')
$marketOverrideConfig = Read-JsonFile (Join-Path $ConfigDir 'foreign-market-overrides.json')
if ($null -eq $countriesConfig) {
    Write-ShadowError -EngineState $engineState -Now $now -Message 'Shadow collection configuration is missing.'
    Write-JsonAtomic -Path $EngineStateFile -Value $engineState
    return
}

$collectionCountries = @($countriesConfig.countries | Where-Object { $_.PSObject.Properties['collect'] -and $_.collect -eq $true })
$inactiveMarketIndex = Get-InactiveMarketIndex -OverrideConfig $marketOverrideConfig

try {
    $providerSet = Get-LiveStockProviderSet -CollectionCountries $collectionCountries -NowEpoch $now -MaximumAgeSeconds $MaximumProviderAgeSeconds
    $countriesSeen = 0
    $marketsSeen = 0
    $legacyMarketsSeen = 0
    $observationsWritten = 0
    $cyclesCompleted = 0
    $providersUsed = @()
    $staleCountries = @()
    $countryProviders = [pscustomobject]@{}
    $cycleHistoryMap = $null

    foreach ($country in $collectionCountries) {
        $selection = Select-LiveCountryProvider -ProviderSet $providerSet -Country $country -NowEpoch $now -MaximumAgeSeconds $MaximumProviderAgeSeconds
        if ($null -eq $selection) {
            $staleCountries += [string]$country.id
            continue
        }
        $source = [string]$selection.source
        if ($providersUsed -notcontains $source) { $providersUsed += $source }
        Set-DynamicProperty -Object $countryProviders -Name ([string]$country.id) -Value $source

        $observations = @(Get-LiveStockObservationsForCountry -Payload $selection.payload -Country $country -Now $now -Source $source)
        if ($observations.Count -gt 0) { $countriesSeen++ }

        foreach ($observation in $observations) {
            Update-ObservedMarketMetadata -EngineState $engineState -Observation $observation -Now $now
            $marketsSeen++

            $key = (([string]$observation.country) + ':' + ([string]$observation.itemId)).ToLowerInvariant()
            if ($inactiveMarketIndex.ContainsKey($key)) {
                $legacyMarketsSeen++
                continue
            }

            # One collector owns stock-transition history for every active foreign
            # market. Per-country provider selection only changes the live source;
            # stable country:item identity keeps cycle evidence continuous.
            $destState = Get-DestinationState -EngineState $engineState -Key $key
            $boundaryPolicy = Get-DynamicProperty -Object $destState -Name 'boundaryPolicy'
            if ($null -eq $boundaryPolicy) {
                if ($null -eq $cycleHistoryMap) { $cycleHistoryMap = Read-CycleHistoryMap -Paths @($SeedCycleFile,$CycleFile) }
                $marketCycles = if ($cycleHistoryMap.ContainsKey($key)) { @($cycleHistoryMap[$key].ToArray()) } else { @() }
                $boundaryPolicy = Get-CycleBoundaryPolicy -Cycles $marketCycles -ExpectedPollIntervalSeconds $MinimumPollIntervalSeconds
                Set-DynamicProperty -Object $destState -Name 'boundaryPolicy' -Value $boundaryPolicy
            }
            if (-not (Test-ObservationChanged -DestState $destState -Observation $observation)) {
                [void](Invalidate-PhaseAnchorForGap -DestState $destState -Observation $observation -BoundaryPolicy $boundaryPolicy)
                $destState.lastForeignPrice = [long]$observation.foreignPrice
                $destState.lastSourceTimestamp = $(if ([long]$observation.sourceTimestamp -gt 0) { [long]$observation.sourceTimestamp } else { [long]$observation.timestamp })
                continue
            }

            Append-JsonLine -Path $ObservationFile -Value $observation -FallbackPath $PendingObservationFile
            $observationsWritten++
            $completed = Update-CycleState -DestState $destState -Observation $observation -BoundaryPolicy $boundaryPolicy
            if ($null -ne $completed) {
                Append-JsonLine -Path $CycleFile -Value $completed -FallbackPath $PendingCycleFile
                $cyclesCompleted++
            }
        }
    }

    if ($countriesSeen -le 0) {
        throw 'No collected country had a fresh usable stock snapshot from Prometheus or YATA.'
    }

    $engineState.shadowCollection.lastPollAt = $now
    $engineState.shadowCollection.lastProvider = (@($providersUsed | Sort-Object) -join '+')
    $engineState.shadowCollection.countriesSeen = $countriesSeen
    $engineState.shadowCollection.marketsSeen = $marketsSeen
    $engineState.shadowCollection.legacyMarketsSeen = $legacyMarketsSeen
    $engineState.shadowCollection.observationsWritten = $observationsWritten
    $engineState.shadowCollection.cyclesCompleted = $cyclesCompleted
    Set-DynamicProperty -Object $engineState.shadowCollection -Name 'countryProviders' -Value $countryProviders
    Set-DynamicProperty -Object $engineState.shadowCollection -Name 'staleCountries' -Value ([string[]]@($staleCountries | Sort-Object))
    Set-DynamicProperty -Object $engineState.shadowCollection -Name 'pendingObservationJournal' -Value (Test-Path -LiteralPath $PendingObservationFile)
    Set-DynamicProperty -Object $engineState.shadowCollection -Name 'pendingCycleJournal' -Value (Test-Path -LiteralPath $PendingCycleFile)
    $engineState.shadowCollection.lastErrorAt = 0
    $engineState.shadowCollection.lastError = ''
    if (Test-Path -LiteralPath $ErrorFile) { Remove-Item -LiteralPath $ErrorFile -Force -ErrorAction SilentlyContinue }
    Write-JsonAtomic -Path $EngineStateFile -Value $engineState
    return
} catch {
    Write-ShadowError -EngineState $engineState -Now $now -Message $_.Exception.Message
    Write-JsonAtomic -Path $EngineStateFile -Value $engineState
    return
}
