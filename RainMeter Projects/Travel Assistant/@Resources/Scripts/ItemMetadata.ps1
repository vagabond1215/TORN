param(
    [int]$RefreshIntervalSeconds = 21600,
    [int]$TimeoutSec = 12,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$ErrorFile = Join-Path $RuntimeDir 'item-metadata-error.txt'

New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-JsonAtomic {
    param([string]$Path, [object]$Value, [int]$Depth = 18)
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
    if ($null -eq $state) { return $null }
    if (-not $state.PSObject.Properties['observedMarkets']) { $state | Add-Member NoteProperty observedMarkets ([pscustomobject]@{}) }
    if (-not $state.PSObject.Properties['itemMetadata']) { $state | Add-Member NoteProperty itemMetadata ([pscustomobject]@{}) }
    if (-not $state.PSObject.Properties['metadataCollection']) {
        $state | Add-Member NoteProperty metadataCollection ([pscustomobject]@{
            lastRefreshAt = 0
            lastAttemptAt = 0
            source = ''
            distinctObservedItems = 0
            itemsRequested = 0
            itemsResolved = 0
            categories = @()
            lastErrorAt = 0
            lastError = ''
        })
    }
    foreach ($name in @('lastRefreshAt','lastAttemptAt','source','distinctObservedItems','itemsRequested','itemsResolved','categories','lastErrorAt','lastError')) {
        if (-not $state.metadataCollection.PSObject.Properties[$name]) {
            $default = if ($name -in @('source','lastError')) { '' } elseif ($name -eq 'categories') { @() } else { 0 }
            $state.metadataCollection | Add-Member NoteProperty $name $default
        }
    }
    return $state
}

function Get-ApiKey {
    $local = Read-JsonFile (Join-Path $ConfigDir 'settings.local.json')
    if ($null -ne $local -and $local.PSObject.Properties['tornApiKey'] -and -not [string]::IsNullOrWhiteSpace([string]$local.tornApiKey)) {
        return [string]$local.tornApiKey
    }
    if (-not [string]::IsNullOrWhiteSpace($env:TORN_API_KEY)) { return [string]$env:TORN_API_KEY }
    return ''
}

function Get-ObservedItemIds {
    param([object]$EngineState)
    $set = New-Object 'System.Collections.Generic.HashSet[int]'
    if ($null -eq $EngineState -or $null -eq $EngineState.observedMarkets) { return @() }
    foreach ($property in @($EngineState.observedMarkets.PSObject.Properties)) {
        $entry = $property.Value
        if ($null -ne $entry -and $entry.PSObject.Properties['itemId']) {
            $id = [int]$entry.itemId
            if ($id -gt 0) { [void]$set.Add($id) }
            continue
        }
        $parts = ([string]$property.Name).Split(':')
        if ($parts.Count -ge 2) {
            $parsed = 0
            if ([int]::TryParse($parts[$parts.Count - 1], [ref]$parsed) -and $parsed -gt 0) { [void]$set.Add($parsed) }
        }
    }
    return @($set | Sort-Object)
}

function Import-ConfiguredMetadataSeeds {
    param([object]$EngineState, [object]$ItemsConfig, [long]$Now)
    if ($null -eq $EngineState -or $null -eq $ItemsConfig -or -not $ItemsConfig.PSObject.Properties['items']) { return 0 }

    $written = 0
    foreach ($item in @($ItemsConfig.items)) {
        if ($null -eq $item -or -not $item.PSObject.Properties['itemId'] -or -not $item.PSObject.Properties['name']) { continue }
        $itemId = [int]$item.itemId
        $name = [string]$item.name
        $category = if ($item.PSObject.Properties['category']) { [string]$item.category } else { '' }
        if ($itemId -le 0 -or [string]::IsNullOrWhiteSpace($name) -or [string]::IsNullOrWhiteSpace($category)) { continue }

        $existing = Get-DynamicProperty $EngineState.itemMetadata ([string]$itemId)
        if ($null -ne $existing -and $existing.PSObject.Properties['source'] -and [string]$existing.source -ne 'config_seed') { continue }

        $metadata = [pscustomobject]@{
            schemaVersion = 1
            itemId = $itemId
            name = $name
            type = $category
            weaponType = ''
            category = $category
            categoryResolved = $true
            tradabilityKnown = $false
            isTradable = $null
            marketPrice = 0
            fetchedAt = $Now
            source = 'config_seed'
        }
        Set-DynamicProperty $EngineState.itemMetadata ([string]$itemId) $metadata
        $written++
    }
    return $written
}

function Get-CanonicalCategory {
    param([object]$Item)
    $type = if ($null -ne $Item -and $Item.PSObject.Properties['type']) { [string]$Item.type } else { '' }
    if ([string]::IsNullOrWhiteSpace($type)) {
        return [pscustomobject]@{ category = 'Unknown'; resolved = $false }
    }
    return [pscustomobject]@{ category = $type; resolved = $true }
}

function Convert-TornBulkItemMetadata {
    param([int]$ItemId, [object]$Item, [long]$Now)
    if ($ItemId -le 0 -or $null -eq $Item -or -not $Item.PSObject.Properties['name']) { return $null }

    $categoryResult = Get-CanonicalCategory -Item $Item
    $marketPrice = 0L
    if ($Item.PSObject.Properties['market_value'] -and $null -ne $Item.market_value) { $marketPrice = [long]$Item.market_value }

    $tradabilityKnown = $false
    $isTradable = $null
    foreach ($field in @('tradeable','tradable','is_tradable')) {
        if ($Item.PSObject.Properties[$field] -and $null -ne $Item.$field) {
            $tradabilityKnown = $true
            $isTradable = [bool]$Item.$field
            break
        }
    }

    return [pscustomobject]@{
        schemaVersion = 1
        itemId = $ItemId
        name = [string]$Item.name
        type = if ($Item.PSObject.Properties['type']) { [string]$Item.type } else { '' }
        weaponType = if ($Item.PSObject.Properties['weapon_type'] -and $null -ne $Item.weapon_type) { [string]$Item.weapon_type } else { '' }
        category = [string]$categoryResult.category
        categoryResolved = [bool]$categoryResult.resolved
        tradabilityKnown = $tradabilityKnown
        isTradable = $isTradable
        marketPrice = $marketPrice
        fetchedAt = $Now
        source = 'torn_items_bulk'
    }
}

function Invoke-TornBulkItemsJsonWithCurl {
    param([string]$ApiKey, [int]$RequestTimeoutSec = 12)
    if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw 'A local Torn API key is required for item metadata enrichment.' }

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -eq $curl) { throw 'curl.exe is required for Torn item metadata requests on this Windows environment.' }
    if ($RequestTimeoutSec -lt 1) { $RequestTimeoutSec = 12 }
    $connectTimeout = [Math]::Min(5, $RequestTimeoutSec)
    $uri = 'https://api.torn.com/torn/?selections=items'

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $curl.Source
    $psi.Arguments = '-q --config -'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi
    try {
        if (-not $process.Start()) { throw 'Failed to start curl.exe.' }
        $process.StandardInput.WriteLine('silent')
        $process.StandardInput.WriteLine('show-error')
        $process.StandardInput.WriteLine('fail')
        $process.StandardInput.WriteLine(('connect-timeout = {0}' -f $connectTimeout))
        $process.StandardInput.WriteLine(('max-time = {0}' -f $RequestTimeoutSec))
        $process.StandardInput.WriteLine(('url = "{0}"' -f $uri))
        $process.StandardInput.WriteLine('header = "Accept: application/json"')
        $process.StandardInput.WriteLine('header = "User-Agent: TravelAssistant-MetadataMaintenance/1.0"')
        $safeKey = $ApiKey.Replace("`r", '').Replace("`n", '').Replace('"', '\"')
        $process.StandardInput.WriteLine(('header = "Authorization: ApiKey {0}"' -f $safeKey))
        $process.StandardInput.Close()

        $waitMs = [Math]::Max(3000, ($RequestTimeoutSec + 2) * 1000)
        if (-not $process.WaitForExit($waitMs)) {
            try { $process.Kill() } catch { }
            throw ('curl.exe exceeded the {0}s Torn bulk metadata timeout.' -f $RequestTimeoutSec)
        }
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        if ($process.ExitCode -ne 0) {
            if ([string]::IsNullOrWhiteSpace($stderr)) { $stderr = 'curl.exe returned a non-zero exit code.' }
            throw ('Torn bulk metadata request failed: {0}' -f $stderr.Trim())
        }
        if ([string]::IsNullOrWhiteSpace($stdout)) { throw 'Torn bulk metadata request returned an empty response.' }
        $payload = $stdout | ConvertFrom-Json
        if ($null -ne $payload -and $payload.PSObject.Properties['error']) {
            $message = if ($payload.error.PSObject.Properties['error']) { [string]$payload.error.error } else { 'Torn returned an error envelope.' }
            throw ('Torn bulk metadata request returned an API error: {0}' -f $message)
        }
        return $payload
    } finally {
        $process.Dispose()
    }
}

function Get-MetadataCategories {
    param([object]$EngineState)
    $categories = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($property in @($EngineState.itemMetadata.PSObject.Properties)) {
        $entry = $property.Value
        if ($null -ne $entry -and $entry.PSObject.Properties['category'] -and -not [string]::IsNullOrWhiteSpace([string]$entry.category)) {
            [void]$categories.Add([string]$entry.category)
        }
    }
    return @($categories | Sort-Object)
}

function Write-MetadataError {
    param([object]$EngineState, [long]$Now, [string]$Message)
    $clean = ([string]$Message).Replace("`r", ' ').Replace("`n", ' ').Trim()
    if ($clean.Length -gt 600) { $clean = $clean.Substring(0, 600) }
    $EngineState.metadataCollection.lastAttemptAt = $Now
    $EngineState.metadataCollection.itemsResolved = @($EngineState.itemMetadata.PSObject.Properties).Count
    $EngineState.metadataCollection.categories = @(Get-MetadataCategories -EngineState $EngineState)
    $EngineState.metadataCollection.lastErrorAt = $Now
    $EngineState.metadataCollection.lastError = $clean
    try { [System.IO.File]::WriteAllText($ErrorFile, $clean, [System.Text.UTF8Encoding]::new($false)) } catch { }
}

if ($RefreshIntervalSeconds -lt 3600) { $RefreshIntervalSeconds = 3600 }
if ($TimeoutSec -lt 5) { $TimeoutSec = 5 }
if ($TimeoutSec -gt 30) { $TimeoutSec = 30 }

$now = Get-NowEpoch
$engineState = Get-EngineState
if ($null -eq $engineState) { return }
$itemIds = @(Get-ObservedItemIds -EngineState $engineState)
if ($itemIds.Count -eq 0) { return }

$itemsConfig = Read-JsonFile (Join-Path $ConfigDir 'items.json')
$seedCount = Import-ConfiguredMetadataSeeds -EngineState $engineState -ItemsConfig $itemsConfig -Now $now
$engineState.metadataCollection.distinctObservedItems = $itemIds.Count
$engineState.metadataCollection.itemsRequested = $itemIds.Count
$engineState.metadataCollection.itemsResolved = @($engineState.itemMetadata.PSObject.Properties).Count
$engineState.metadataCollection.categories = @(Get-MetadataCategories -EngineState $engineState)
if ($seedCount -gt 0 -and [string]::IsNullOrWhiteSpace([string]$engineState.metadataCollection.source)) {
    $engineState.metadataCollection.source = 'config_seed'
}
Write-JsonAtomic -Path $EngineStateFile -Value $engineState

$lastAttemptAt = [long]$engineState.metadataCollection.lastAttemptAt
if (-not $Force -and $lastAttemptAt -gt 0 -and ($now - $lastAttemptAt) -lt $RefreshIntervalSeconds) { return }

$engineState.metadataCollection.lastAttemptAt = $now
$apiKey = Get-ApiKey
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    Write-MetadataError -EngineState $engineState -Now $now -Message 'No local Torn API key is available for optional item metadata maintenance.'
    Write-JsonAtomic -Path $EngineStateFile -Value $engineState
    return
}

try {
    $payload = Invoke-TornBulkItemsJsonWithCurl -ApiKey $apiKey -RequestTimeoutSec $TimeoutSec
    if ($null -eq $payload -or -not $payload.PSObject.Properties['items'] -or $null -eq $payload.items) {
        throw 'Torn bulk item metadata response does not contain items.'
    }

    foreach ($itemId in $itemIds) {
        $item = Get-DynamicProperty $payload.items ([string]$itemId)
        if ($null -eq $item) { continue }
        $metadata = Convert-TornBulkItemMetadata -ItemId ([int]$itemId) -Item $item -Now $now
        if ($null -eq $metadata) { continue }
        Set-DynamicProperty $engineState.itemMetadata ([string]$itemId) $metadata
    }

    $engineState.metadataCollection.lastRefreshAt = $now
    $engineState.metadataCollection.lastAttemptAt = $now
    $engineState.metadataCollection.source = 'torn_items_bulk'
    $engineState.metadataCollection.distinctObservedItems = $itemIds.Count
    $engineState.metadataCollection.itemsRequested = $itemIds.Count
    $engineState.metadataCollection.itemsResolved = @($engineState.itemMetadata.PSObject.Properties).Count
    $engineState.metadataCollection.categories = @(Get-MetadataCategories -EngineState $engineState)
    $engineState.metadataCollection.lastErrorAt = 0
    $engineState.metadataCollection.lastError = ''
    if (Test-Path -LiteralPath $ErrorFile) { Remove-Item -LiteralPath $ErrorFile -Force -ErrorAction SilentlyContinue }
    Write-JsonAtomic -Path $EngineStateFile -Value $engineState
    return
} catch {
    Write-MetadataError -EngineState $engineState -Now $now -Message $_.Exception.Message
    Write-JsonAtomic -Path $EngineStateFile -Value $engineState
    return
}
