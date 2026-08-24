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
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$ErrorFile = Join-Path $RuntimeDir 'shadow-collection-error.txt'

New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-JsonAtomic {
    param([string]$Path, [object]$Value, [int]$Depth = 16)
    $tmp = $Path + '.tmp'
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
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
            activeCycle = $null
        }
        Set-DynamicProperty $EngineState.destinations $Key $dest
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

function Append-JsonLine {
    param([string]$Path, [object]$Value)
    $line = $Value | ConvertTo-Json -Compress -Depth 10
    Add-Content -LiteralPath $Path -Value $line -Encoding UTF8
}

function Update-CycleState {
    param([object]$DestState, [object]$Observation)
    $previousStock = [int]$DestState.lastStock
    $currentStock = [int]$Observation.stock
    $ts = [long]$Observation.timestamp
    $completed = $null

    if ($previousStock -ge 0) {
        if ($previousStock -eq 0 -and $currentStock -gt 0) {
            $DestState.activeCycle = [pscustomobject]@{
                previousSoldOutAt = [long]$DestState.lastSellOutAt
                restockAt = $ts
                restockQuantity = $currentStock
                foreignPrice = [long]$Observation.foreignPrice
                source = [string]$Observation.source
            }
        } elseif ($previousStock -gt 0 -and $currentStock -eq 0) {
            $DestState.lastSellOutAt = $ts
            if ($null -ne $DestState.activeCycle) {
                $restockAt = [long]$DestState.activeCycle.restockAt
                $previousSoldOutAt = [long]$DestState.activeCycle.previousSoldOutAt
                $delay = 0L
                if ($previousSoldOutAt -gt 0 -and $restockAt -gt $previousSoldOutAt) { $delay = $restockAt - $previousSoldOutAt }
                $completed = [pscustomobject]@{
                    schemaVersion = 1
                    country = [string]$Observation.country
                    itemId = [int]$Observation.itemId
                    foreignPrice = [long]$DestState.activeCycle.foreignPrice
                    restockAt = $restockAt
                    restockQuantity = [int]$DestState.activeCycle.restockQuantity
                    soldOutAt = $ts
                    availabilitySeconds = [long]($ts - $restockAt)
                    previousSoldOutAt = $previousSoldOutAt
                    restockDelaySeconds = $delay
                    source = [string]$DestState.activeCycle.source
                }
                $DestState.activeCycle = $null
            }
        }
    }

    $DestState.lastStock = $currentStock
    $DestState.lastForeignPrice = [long]$Observation.foreignPrice
    $DestState.lastSourceTimestamp = [long]$Observation.sourceTimestamp
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
            if (-not (Test-ObservationChanged -DestState $destState -Observation $observation)) {
                $destState.lastForeignPrice = [long]$observation.foreignPrice
                $destState.lastSourceTimestamp = [long]$observation.sourceTimestamp
                continue
            }

            Append-JsonLine -Path $ObservationFile -Value $observation
            $observationsWritten++
            $completed = Update-CycleState -DestState $destState -Observation $observation
            if ($null -ne $completed -and [long]$completed.availabilitySeconds -gt 0) {
                Append-JsonLine -Path $CycleFile -Value $completed
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
