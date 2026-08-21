$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'

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

function Get-ObservedItemGroups {
    param([object]$ObservedMarkets)

    $groups = @{}
    if ($null -eq $ObservedMarkets) { return @() }

    foreach ($property in @($ObservedMarkets.PSObject.Properties)) {
        $entry = $property.Value
        if ($null -eq $entry) { continue }

        $itemId = 0
        if ($entry.PSObject.Properties['itemId']) {
            $itemId = [int]$entry.itemId
        } else {
            $parts = ([string]$property.Name).Split(':')
            if ($parts.Count -ge 2) { [void][int]::TryParse($parts[$parts.Count - 1], [ref]$itemId) }
        }
        if ($itemId -le 0) { continue }

        $key = [string]$itemId
        if (-not $groups.ContainsKey($key)) {
            $groups[$key] = [pscustomobject]@{
                itemId = $itemId
                names = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
                countries = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
            }
        }

        $group = $groups[$key]
        if ($entry.PSObject.Properties['providerName']) {
            $providerName = ([string]$entry.providerName).Trim()
            if (-not [string]::IsNullOrWhiteSpace($providerName)) { [void]$group.names.Add($providerName) }
        }
        if ($entry.PSObject.Properties['country']) {
            $country = ([string]$entry.country).Trim()
            if (-not [string]::IsNullOrWhiteSpace($country)) { [void]$group.countries.Add($country) }
        }
    }

    $result = New-Object System.Collections.Generic.List[object]
    foreach ($group in @($groups.Values | Sort-Object itemId)) {
        $result.Add([pscustomobject]@{
            itemId = [int]$group.itemId
            providerNames = @($group.names | Sort-Object)
            countries = @($group.countries | Sort-Object)
        })
    }
    return $result.ToArray()
}

function Get-SeedIndex {
    param([object]$ItemsConfig)
    $index = @{}
    if ($null -eq $ItemsConfig -or -not $ItemsConfig.PSObject.Properties['items']) { return $index }
    foreach ($item in @($ItemsConfig.items)) {
        if ($null -eq $item -or -not $item.PSObject.Properties['itemId']) { continue }
        $itemId = [int]$item.itemId
        if ($itemId -le 0) { continue }
        $index[[string]$itemId] = $item
    }
    return $index
}

function Get-CategoryIndex {
    param([object]$CategoryConfig)
    $index = @{}
    if ($null -eq $CategoryConfig -or -not $CategoryConfig.PSObject.Properties['categoriesByItemId']) { return $index }
    foreach ($property in @($CategoryConfig.categoriesByItemId.PSObject.Properties)) {
        $itemId = 0
        if (-not [int]::TryParse([string]$property.Name, [ref]$itemId) -or $itemId -le 0) { continue }
        $category = ([string]$property.Value).Trim()
        if ([string]::IsNullOrWhiteSpace($category)) { continue }
        $index[[string]$itemId] = $category
    }
    return $index
}

function New-LocalCatalogEntry {
    param(
        [object]$Group,
        [object]$Seed,
        [string]$OfflineCategory,
        [string]$OfflineCategorySource,
        [long]$Now
    )
    if ($null -eq $Group -or [int]$Group.itemId -le 0) { return $null }

    $names = @($Group.providerNames)
    $providerName = if ($names.Count -gt 0) { [string]$names[0] } else { '' }
    $nameConflict = $names.Count -gt 1

    $seedName = ''
    $seedCategory = ''
    if ($null -ne $Seed) {
        if ($Seed.PSObject.Properties['name']) { $seedName = ([string]$Seed.name).Trim() }
        if ($Seed.PSObject.Properties['category']) { $seedCategory = ([string]$Seed.category).Trim() }
    }

    $name = if (-not [string]::IsNullOrWhiteSpace($seedName)) { $seedName } elseif (-not [string]::IsNullOrWhiteSpace($providerName)) { $providerName } else { 'Item ' + [string]$Group.itemId }

    $category = 'Unknown'
    $categoryResolved = $false
    $source = 'provider_name'
    $categorySource = ''
    if (-not [string]::IsNullOrWhiteSpace($seedCategory)) {
        $category = $seedCategory
        $categoryResolved = $true
        $source = 'config_seed'
        $categorySource = 'config_seed'
    } elseif (-not [string]::IsNullOrWhiteSpace($OfflineCategory)) {
        $category = $OfflineCategory.Trim()
        $categoryResolved = $true
        $source = 'offline_yata_category'
        $categorySource = if ([string]::IsNullOrWhiteSpace($OfflineCategorySource)) { 'offline_snapshot' } else { $OfflineCategorySource.Trim() }
    }

    return [pscustomobject]@{
        schemaVersion = 1
        itemId = [int]$Group.itemId
        name = $name
        providerName = $providerName
        providerNames = @($names)
        nameConflict = $nameConflict
        countries = @($Group.countries)
        type = ''
        weaponType = ''
        category = $category
        categoryResolved = $categoryResolved
        categorySource = $categorySource
        tradabilityKnown = $false
        isTradable = $null
        marketPrice = 0L
        fetchedAt = 0L
        localUpdatedAt = $Now
        source = $source
    }
}

function Get-LocalCatalogSignature {
    param(
        [object[]]$Groups,
        [hashtable]$SeedIndex,
        [hashtable]$CategoryIndex,
        [string]$CategorySourceId
    )
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add(('categorySource={0}' -f [string]$CategorySourceId))
    foreach ($group in @($Groups)) {
        $names = @($group.providerNames) -join ','
        $countries = @($group.countries) -join ','
        $seedName = ''
        $seedCategory = ''
        $offlineCategory = ''
        $seed = $null
        if ($SeedIndex.ContainsKey([string]$group.itemId)) { $seed = $SeedIndex[[string]$group.itemId] }
        if ($null -ne $seed) {
            if ($seed.PSObject.Properties['name']) { $seedName = [string]$seed.name }
            if ($seed.PSObject.Properties['category']) { $seedCategory = [string]$seed.category }
        }
        if ($CategoryIndex.ContainsKey([string]$group.itemId)) { $offlineCategory = [string]$CategoryIndex[[string]$group.itemId] }
        $parts.Add(('{0}|{1}|{2}|{3}|{4}|{5}' -f [int]$group.itemId, $names, $countries, $seedName, $seedCategory, $offlineCategory))
    }

    $text = $parts -join "`n"
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($text)
        $hash = $sha.ComputeHash($bytes)
        return ([System.BitConverter]::ToString($hash)).Replace('-', '').ToLowerInvariant()
    } finally {
        $sha.Dispose()
    }
}

function Merge-RicherMetadata {
    param([object]$Existing, [object]$LocalEntry)
    if ($null -eq $Existing) { return $LocalEntry }
    if (-not $Existing.PSObject.Properties['source'] -or [string]$Existing.source -ne 'torn_items_bulk') { return $LocalEntry }

    foreach ($field in @('providerName','providerNames','nameConflict','countries','localUpdatedAt')) {
        Set-DynamicProperty $Existing $field (Get-DynamicProperty $LocalEntry $field)
    }
    return $Existing
}

$engineState = Read-JsonFile $EngineStateFile
if ($null -eq $engineState -or -not $engineState.PSObject.Properties['observedMarkets']) { return }
if (-not $engineState.PSObject.Properties['itemMetadata']) { $engineState | Add-Member NoteProperty itemMetadata ([pscustomobject]@{}) }
if (-not $engineState.PSObject.Properties['localCatalog']) {
    $engineState | Add-Member NoteProperty localCatalog ([pscustomobject]@{
        signature = ''
        lastBuildAt = 0
        observedItems = 0
        metadataItems = 0
        categoriesResolved = 0
        unresolvedItems = 0
        nameConflicts = 0
        offlineCategoryEntries = 0
        offlineMatchedItems = 0
    })
}
foreach ($name in @('signature','lastBuildAt','observedItems','metadataItems','categoriesResolved','unresolvedItems','nameConflicts','offlineCategoryEntries','offlineMatchedItems')) {
    if (-not $engineState.localCatalog.PSObject.Properties[$name]) {
        $default = if ($name -eq 'signature') { '' } else { 0 }
        $engineState.localCatalog | Add-Member NoteProperty $name $default
    }
}

$itemsConfig = Read-JsonFile (Join-Path $ConfigDir 'items.json')
$categoryConfig = Read-JsonFile (Join-Path $ConfigDir 'foreign-item-categories.json')
$groups = @(Get-ObservedItemGroups -ObservedMarkets $engineState.observedMarkets)
if ($groups.Count -eq 0) { return }
$seedIndex = Get-SeedIndex -ItemsConfig $itemsConfig
$categoryIndex = Get-CategoryIndex -CategoryConfig $categoryConfig
$categorySourceId = 'offline_snapshot'
if ($null -ne $categoryConfig -and $categoryConfig.PSObject.Properties['source'] -and $null -ne $categoryConfig.source -and $categoryConfig.source.PSObject.Properties['id']) {
    $candidateSourceId = ([string]$categoryConfig.source.id).Trim()
    if (-not [string]::IsNullOrWhiteSpace($candidateSourceId)) { $categorySourceId = $candidateSourceId }
}
$signature = Get-LocalCatalogSignature -Groups $groups -SeedIndex $seedIndex -CategoryIndex $categoryIndex -CategorySourceId $categorySourceId

$existingMetadataCount = @($engineState.itemMetadata.PSObject.Properties).Count
if ([string]$engineState.localCatalog.signature -eq $signature -and $existingMetadataCount -ge $groups.Count) { return }

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$resolved = 0
$unresolved = 0
$conflicts = 0
$offlineMatched = 0
foreach ($group in $groups) {
    $key = [string]$group.itemId
    $seed = $null
    if ($seedIndex.ContainsKey($key)) { $seed = $seedIndex[$key] }
    $offlineCategory = ''
    if ($categoryIndex.ContainsKey($key)) {
        $offlineCategory = [string]$categoryIndex[$key]
        $offlineMatched++
    }
    $localEntry = New-LocalCatalogEntry -Group $group -Seed $seed -OfflineCategory $offlineCategory -OfflineCategorySource $categorySourceId -Now $now
    if ($null -eq $localEntry) { continue }

    $existing = Get-DynamicProperty $engineState.itemMetadata $key
    $entry = Merge-RicherMetadata -Existing $existing -LocalEntry $localEntry
    Set-DynamicProperty $engineState.itemMetadata $key $entry

    if ($entry.PSObject.Properties['categoryResolved'] -and [bool]$entry.categoryResolved) { $resolved++ } else { $unresolved++ }
    if ($entry.PSObject.Properties['nameConflict'] -and [bool]$entry.nameConflict) { $conflicts++ }
}

$engineState.localCatalog.signature = $signature
$engineState.localCatalog.lastBuildAt = $now
$engineState.localCatalog.observedItems = $groups.Count
$engineState.localCatalog.metadataItems = @($engineState.itemMetadata.PSObject.Properties).Count
$engineState.localCatalog.categoriesResolved = $resolved
$engineState.localCatalog.unresolvedItems = $unresolved
$engineState.localCatalog.nameConflicts = $conflicts
$engineState.localCatalog.offlineCategoryEntries = $categoryIndex.Count
$engineState.localCatalog.offlineMatchedItems = $offlineMatched
Write-JsonAtomic -Path $EngineStateFile -Value $engineState
