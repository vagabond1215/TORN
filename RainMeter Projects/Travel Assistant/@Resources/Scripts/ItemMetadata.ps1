param(
    [int]$RefreshIntervalSeconds = 21600,
    [int]$MaxIdsPerRequest = 150,
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

function Split-ItemIds {
    param([int[]]$ItemIds, [int]$Maximum = 150)
    if ($Maximum -lt 1) { $Maximum = 150 }
    $chunks = New-Object System.Collections.Generic.List[object]
    $current = New-Object System.Collections.Generic.List[int]
    foreach ($id in @($ItemIds)) {
        if ([int]$id -le 0) { continue }
        $current.Add([int]$id)
        if ($current.Count -ge $Maximum) {
            $chunks.Add(@($current.ToArray()))
            $current = New-Object System.Collections.Generic.List[int]
        }
    }
    if ($current.Count -gt 0) { $chunks.Add(@($current.ToArray())) }
    return $chunks.ToArray()
}

function Get-CanonicalCategory {
    param([object]$Item)
    $type = if ($null -ne $Item -and $Item.PSObject.Properties['type']) { [string]$Item.type } else { '' }
    if ($type -eq 'Weapon') {
        $details = if ($Item.PSObject.Properties['details']) { $Item.details } else { $null }
        if ($null -ne $details -and $details.PSObject.Properties['category'] -and -not [string]::IsNullOrWhiteSpace([string]$details.category)) {
            return [pscustomobject]@{ category = [string]$details.category; resolved = $true }
        }
        return [pscustomobject]@{ category = 'Weapon'; resolved = $false }
    }
    if ([string]::IsNullOrWhiteSpace($type)) { return [pscustomobject]@{ category = 'Unknown'; resolved = $false } }
    return [pscustomobject]@{ category = $type; resolved = $true }
}

function Convert-TornItemMetadata {
    param([object]$Item, [long]$Now)
    if ($null -eq $Item -or -not $Item.PSObject.Properties['id'] -or -not $Item.PSObject.Properties['name']) { return $null }
    $id = [int]$Item.id
    if ($id -le 0) { return $null }

    $categoryResult = Get-CanonicalCategory -Item $Item
    $marketPrice = 0L
    $shops = New-Object System.Collections.Generic.List[object]
    if ($Item.PSObject.Properties['value'] -and $null -ne $Item.value) {
        if ($Item.value.PSObject.Properties['market_price']) { $marketPrice = [long]$Item.value.market_price }
        if ($Item.value.PSObject.Properties['shops']) {
            foreach ($shop in @($Item.value.shops)) {
                if ($null -eq $shop) { continue }
                $shops.Add([pscustomobject]@{
                    country = if ($shop.PSObject.Properties['country']) { [string]$shop.country } else { '' }
                    shop = if ($shop.PSObject.Properties['shop']) { [string]$shop.shop } else { '' }
                    buyPrice = if ($shop.PSObject.Properties['buy_price'] -and $null -ne $shop.buy_price) { [long]$shop.buy_price } else { $null }
                    sellPrice = if ($shop.PSObject.Properties['sell_price'] -and $null -ne $shop.sell_price) { [long]$shop.sell_price } else { $null }
                })
            }
        }
    }

    return [pscustomobject]@{
        schemaVersion = 1
        itemId = $id
        name = [string]$Item.name
        type = if ($Item.PSObject.Properties['type']) { [string]$Item.type } else { '' }
        subType = if ($Item.PSObject.Properties['sub_type'] -and $null -ne $Item.sub_type) { [string]$Item.sub_type } else { '' }
        category = [string]$categoryResult.category
        categoryResolved = [bool]$categoryResult.resolved
        isTradable = if ($Item.PSObject.Properties['is_tradable']) { [bool]$Item.is_tradable } else { $false }
        marketPrice = $marketPrice
        shops = $shops.ToArray()
        fetchedAt = $Now
        source = 'torn_items'
    }
}

function Invoke-TornItemsJsonWithCurl {
    param([int[]]$ItemIds, [string]$ApiKey, [int]$TimeoutSec = 20)
    if ($null -eq $ItemIds -or $ItemIds.Count -eq 0) { return $null }
    if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw 'A local Torn API key is required for item metadata enrichment.' }

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -eq $curl) { throw 'curl.exe is required for Torn item metadata requests on this Windows environment.' }
    if ($TimeoutSec -lt 1) { $TimeoutSec = 20 }
    $connectTimeout = [Math]::Min(5, $TimeoutSec)
    $ids = (@($ItemIds | ForEach-Object { [int]$_ }) -join ',')
    $uri = "https://api.torn.com/v2/torn/$ids/items?sort=ASC"

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
        $process.StandardInput.WriteLine(('max-time = {0}' -f $TimeoutSec))
        $process.StandardInput.WriteLine(('url = "{0}"' -f $uri))
        $process.StandardInput.WriteLine(('header = "Accept: application/json"'))
        $safeKey = $ApiKey.Replace("`r", '').Replace("`n", '').Replace('"', '\"')
        $process.StandardInput.WriteLine(('header = "Authorization: ApiKey {0}"' -f $safeKey))
        $process.StandardInput.Close()

        $waitMs = [Math]::Max(3000, ($TimeoutSec + 2) * 1000)
        if (-not $process.WaitForExit($waitMs)) {
            try { $process.Kill() } catch { }
            throw ('curl.exe exceeded the {0}s Torn metadata timeout.' -f $TimeoutSec)
        }
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        if ($process.ExitCode -ne 0) {
            if ([string]::IsNullOrWhiteSpace($stderr)) { $stderr = 'curl.exe returned a non-zero exit code.' }
            throw ('Torn metadata request failed: {0}' -f $stderr.Trim())
        }
        if ([string]::IsNullOrWhiteSpace($stdout)) { throw 'Torn metadata request returned an empty response.' }
        return ($stdout | ConvertFrom-Json)
    } finally {
        $process.Dispose()
    }
}

function Write-MetadataError {
    param([object]$EngineState, [long]$Now, [string]$Message)
    $clean = ([string]$Message).Replace("`r", ' ').Replace("`n", ' ').Trim()
    if ($clean.Length -gt 600) { $clean = $clean.Substring(0, 600) }
    $EngineState.metadataCollection.lastAttemptAt = $Now
    $EngineState.metadataCollection.lastErrorAt = $Now
    $EngineState.metadataCollection.lastError = $clean
    try { [System.IO.File]::WriteAllText($ErrorFile, $clean, [System.Text.UTF8Encoding]::new($false)) } catch { }
}

if ($RefreshIntervalSeconds -lt 3600) { $RefreshIntervalSeconds = 3600 }
if ($MaxIdsPerRequest -lt 1) { $MaxIdsPerRequest = 150 }
if ($MaxIdsPerRequest -gt 250) { $MaxIdsPerRequest = 250 }

$now = Get-NowEpoch
$engineState = Get-EngineState
if ($null -eq $engineState) { return }
$itemIds = @(Get-ObservedItemIds -EngineState $engineState)
if ($itemIds.Count -eq 0) { return }

$missingIds = @($itemIds | Where-Object { $null -eq (Get-DynamicProperty $engineState.itemMetadata ([string]$_)) })
$lastRefreshAt = [long]$engineState.metadataCollection.lastRefreshAt
if (-not $Force -and $missingIds.Count -eq 0 -and $lastRefreshAt -gt 0 -and ($now - $lastRefreshAt) -lt $RefreshIntervalSeconds) { return }

$engineState.metadataCollection.lastAttemptAt = $now
$engineState.metadataCollection.distinctObservedItems = $itemIds.Count
$apiKey = Get-ApiKey
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    Write-MetadataError -EngineState $engineState -Now $now -Message 'No local Torn API key is available for public item metadata enrichment.'
    Write-JsonAtomic -Path $EngineStateFile -Value $engineState
    return
}

try {
    $requested = 0
    $resolved = 0
    $categories = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($chunk in @(Split-ItemIds -ItemIds ([int[]]$itemIds) -Maximum $MaxIdsPerRequest)) {
        $requested += @($chunk).Count
        $payload = Invoke-TornItemsJsonWithCurl -ItemIds ([int[]]$chunk) -ApiKey $apiKey -TimeoutSec 20
        if ($null -eq $payload -or -not $payload.PSObject.Properties['items']) { throw 'Torn item metadata response does not contain items.' }
        foreach ($item in @($payload.items)) {
            $metadata = Convert-TornItemMetadata -Item $item -Now $now
            if ($null -eq $metadata) { continue }
            Set-DynamicProperty $engineState.itemMetadata ([string]$metadata.itemId) $metadata
            if (-not [string]::IsNullOrWhiteSpace([string]$metadata.category)) { [void]$categories.Add([string]$metadata.category) }
            $resolved++
        }
    }

    $engineState.metadataCollection.lastRefreshAt = $now
    $engineState.metadataCollection.lastAttemptAt = $now
    $engineState.metadataCollection.source = 'torn_items'
    $engineState.metadataCollection.distinctObservedItems = $itemIds.Count
    $engineState.metadataCollection.itemsRequested = $requested
    $engineState.metadataCollection.itemsResolved = $resolved
    $engineState.metadataCollection.categories = @($categories | Sort-Object)
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
