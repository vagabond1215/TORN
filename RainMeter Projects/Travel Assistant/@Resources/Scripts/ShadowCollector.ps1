param(
    [int]$MinimumPollIntervalSeconds = 120,
    [switch]$Force
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
                observationsWritten = 0
                cyclesCompleted = 0
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
            observationsWritten = 0
            cyclesCompleted = 0
            lastErrorAt = 0
            lastError = ''
        })
    }
    foreach ($name in @('lastPollAt','lastProvider','countriesSeen','marketsSeen','observationsWritten','cyclesCompleted','lastErrorAt','lastError')) {
        if (-not $state.shadowCollection.PSObject.Properties[$name]) {
            $default = if ($name -in @('lastProvider','lastError')) { '' } else { 0 }
            $state.shadowCollection | Add-Member NoteProperty $name $default
        }
    }
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

function Get-LiveStockPayload {
    $providers = @(
        [pscustomobject]@{ id = 'prometheus'; uri = 'https://api.prombot.co.uk/api/travel' },
        [pscustomobject]@{ id = 'yata'; uri = 'https://yata.yt/api/v1/travel/export/' }
    )
    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($provider in $providers) {
        try {
            $payload = Invoke-RestMethod -Method Get -Uri ([string]$provider.uri) -Headers @{ Accept = 'application/json' } -TimeoutSec 8
            if ($null -eq $payload -or $null -eq $payload.stocks) { throw 'response does not contain stocks' }
            return [pscustomobject]@{ source = [string]$provider.id; payload = $payload }
        } catch {
            $errors.Add(('{0}: {1}' -f [string]$provider.id, $_.Exception.Message))
        }
    }

    throw ('All live stock providers failed: ' + ($errors -join ' | '))
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

    $code = [string](Get-DynamicProperty $Country.providerCodes $Source)
    if ([string]::IsNullOrWhiteSpace($code) -and $Source -eq 'prometheus') {
        $code = [string](Get-DynamicProperty $Country.providerCodes 'yata')
    }
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

        $rows.Add([pscustomobject]@{
            schemaVersion = 1
            timestamp = [long]$timestamp
            country = [string]$Country.id
            itemId = $itemId
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

function Test-IsPrimaryMarket {
    param([string]$CountryId, [int]$ItemId, [object]$PrimaryCountryIds, [object]$PrimaryItemIds)
    return ($PrimaryCountryIds.Contains($CountryId) -and $PrimaryItemIds.Contains($ItemId))
}

function Update-ObservedMarketMetadata {
    param([object]$EngineState, [object]$Observation, [long]$Now)
    $key = ([string]$Observation.country) + ':' + ([string]$Observation.itemId)
    $entry = Get-DynamicProperty $EngineState.observedMarkets $key
    if ($null -eq $entry) {
        $entry = [pscustomobject]@{
            country = [string]$Observation.country
            itemId = [int]$Observation.itemId
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

if ($MinimumPollIntervalSeconds -lt 60) { $MinimumPollIntervalSeconds = 60 }

$now = Get-NowEpoch
$engineState = Get-EngineState
$lastPollAt = [long]$engineState.shadowCollection.lastPollAt
if (-not $Force -and $lastPollAt -gt 0 -and ($now - $lastPollAt) -lt $MinimumPollIntervalSeconds) { return }

$itemsConfig = Read-JsonFile (Join-Path $ConfigDir 'items.json')
$countriesConfig = Read-JsonFile (Join-Path $ConfigDir 'countries.json')
if ($null -eq $itemsConfig -or $null -eq $countriesConfig) {
    Write-ShadowError -EngineState $engineState -Now $now -Message 'Shadow collection configuration is missing.'
    Write-JsonAtomic -Path $EngineStateFile -Value $engineState
    return
}

$primaryItemIds = New-Object 'System.Collections.Generic.HashSet[int]'
foreach ($item in @($itemsConfig.items | Where-Object { $_.enabled -eq $true })) { [void]$primaryItemIds.Add([int]$item.itemId) }
$primaryCountryIds = New-Object 'System.Collections.Generic.HashSet[string]'
foreach ($country in @($countriesConfig.countries | Where-Object { $_.enabled -eq $true })) { [void]$primaryCountryIds.Add([string]$country.id) }
$collectionCountries = @($countriesConfig.countries | Where-Object { $_.PSObject.Properties['collect'] -and $_.collect -eq $true })

try {
    $live = Get-LiveStockPayload
    $countriesSeen = 0
    $marketsSeen = 0
    $observationsWritten = 0
    $cyclesCompleted = 0

    foreach ($country in $collectionCountries) {
        $observations = @(Get-LiveStockObservationsForCountry -Payload $live.payload -Country $country -Now $now -Source ([string]$live.source))
        if ($observations.Count -gt 0) { $countriesSeen++ }

        foreach ($observation in $observations) {
            Update-ObservedMarketMetadata -EngineState $engineState -Observation $observation -Now $now
            $marketsSeen++

            if (Test-IsPrimaryMarket -CountryId ([string]$observation.country) -ItemId ([int]$observation.itemId) -PrimaryCountryIds $primaryCountryIds -PrimaryItemIds $primaryItemIds) {
                continue
            }

            $key = ([string]$observation.country) + ':' + ([string]$observation.itemId)
            $destState = Get-DestinationState -EngineState $engineState -Key $key
            $sameSource = ([long]$destState.lastSourceTimestamp -eq [long]$observation.sourceTimestamp -and [long]$observation.sourceTimestamp -gt 0)
            $sameValues = ([int]$destState.lastStock -eq [int]$observation.stock -and [long]$destState.lastForeignPrice -eq [long]$observation.foreignPrice)
            if ($sameSource -and $sameValues) { continue }

            Append-JsonLine -Path $ObservationFile -Value $observation
            $observationsWritten++
            $completed = Update-CycleState -DestState $destState -Observation $observation
            if ($null -ne $completed -and [long]$completed.availabilitySeconds -gt 0) {
                Append-JsonLine -Path $CycleFile -Value $completed
                $cyclesCompleted++
            }
        }
    }

    $engineState.shadowCollection.lastPollAt = $now
    $engineState.shadowCollection.lastProvider = [string]$live.source
    $engineState.shadowCollection.countriesSeen = $countriesSeen
    $engineState.shadowCollection.marketsSeen = $marketsSeen
    $engineState.shadowCollection.observationsWritten = $observationsWritten
    $engineState.shadowCollection.cyclesCompleted = $cyclesCompleted
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
