param(
    [switch]$SkipMain,
    [long]$Now = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'TravelProfile.ps1')

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$StateKvFile = Join-Path $GeneratedDir 'state.kv'

function Read-VisibleItemsJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Read-VisibleItemsStateKv {
    param([string]$Path)
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $index = $line.IndexOf('=')
        if ($index -lt 1) { continue }
        $key = $line.Substring(0, $index).Trim([char]0xFEFF).Trim()
        $values[$key] = $line.Substring($index + 1).Trim()
    }
    return $values
}

function Write-VisibleItemsStateKvAtomic {
    param([hashtable]$Values, [string]$Path)
    $tmp = $Path + '.tmp'
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in ($Values.Keys | Sort-Object)) {
        $value = ([string]$Values[$key]).Replace("`r", ' ').Replace("`n", ' ')
        $lines.Add("$key=$value")
    }
    [System.IO.File]::WriteAllLines($tmp, $lines.ToArray(), [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-VisibleItemsDynamicProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Test-VisibleItemCountry {
    param([object]$Item, [string]$CountryId)
    if ($null -eq $Item -or -not $Item.PSObject.Properties['countries']) { return $false }
    return (@($Item.countries | ForEach-Object { [string]$_ }) -contains $CountryId)
}

function Get-VisibleSecondaryItem {
    param([object]$ItemsConfig, [string]$CountryId, [int]$PrimaryItemId)
    if ($null -eq $ItemsConfig -or -not $ItemsConfig.PSObject.Properties['items']) { return $null }
    return @($ItemsConfig.items | Where-Object {
        [int]$_.itemId -ne $PrimaryItemId -and
        $_.PSObject.Properties['visible'] -and $_.visible -eq $true -and
        (Test-VisibleItemCountry -Item $_ -CountryId $CountryId)
    } | Select-Object -First 1)[0]
}

function Get-VisibleItemsProfitabilitySettings {
    param([object]$BaseSettings, [object]$LocalSettings)
    $base = $BaseSettings.profitability
    $copy = [pscustomobject]@{}
    foreach ($property in @($base.PSObject.Properties)) {
        $copy | Add-Member NoteProperty ([string]$property.Name) $property.Value
    }
    if ($null -ne $LocalSettings -and $LocalSettings.PSObject.Properties['profitability'] -and $null -ne $LocalSettings.profitability) {
        foreach ($property in @($LocalSettings.profitability.PSObject.Properties)) {
            $target = $copy.PSObject.Properties[$property.Name]
            if ($null -eq $target) { $copy | Add-Member NoteProperty ([string]$property.Name) $property.Value }
            else { $target.Value = $property.Value }
        }
    }
    return $copy
}

function Get-VisibleItemsResaleSnapshot {
    param([object]$EngineState, [int]$ItemId, [long]$NowEpoch, [int]$FreshSeconds = 21600)
    $cached = $null
    if ($null -ne $EngineState -and $EngineState.PSObject.Properties['resaleCache']) {
        $cached = Get-VisibleItemsDynamicProperty $EngineState.resaleCache ([string]$ItemId)
    }
    $price = 0L
    $fetchedAt = 0L
    $source = ''
    if ($null -ne $cached) {
        if ($cached.PSObject.Properties['price']) { $price = [long]$cached.price }
        if ($cached.PSObject.Properties['fetchedAt']) { $fetchedAt = [long]$cached.fetchedAt }
        if ($cached.PSObject.Properties['source']) { $source = [string]$cached.source }
    }
    $fresh = ($price -gt 0 -and $fetchedAt -gt 0 -and ($NowEpoch - $fetchedAt) -le $FreshSeconds)
    return [pscustomobject]@{ price = $price; fetchedAt = $fetchedAt; source = $source; fresh = $fresh }
}

function Get-VisibleSecondaryPresentation {
    param(
        [Parameter(Mandatory = $true)][object]$Country,
        [Parameter(Mandatory = $true)][object]$Item,
        [Parameter(Mandatory = $true)][object]$EngineState,
        [Parameter(Mandatory = $true)][object]$TravelProfile,
        [Parameter(Mandatory = $true)][object]$PerksConfig,
        [Parameter(Mandatory = $true)][object]$Profitability,
        [Parameter(Mandatory = $true)][string]$TravelMode,
        [Parameter(Mandatory = $true)][long]$NowEpoch,
        [int]$CapacityOverride = 0,
        [int]$ResaleFreshSeconds = 21600
    )

    $countryId = [string]$Country.id
    $itemId = [int]$Item.itemId
    $marketKey = $countryId + ':' + [string]$itemId
    $market = if ($EngineState.PSObject.Properties['observedMarkets']) { Get-VisibleItemsDynamicProperty $EngineState.observedMarkets $marketKey } else { $null }
    if ($null -eq $market) {
        return [pscustomobject]@{ visible = $false; itemId = $itemId; name = [string]$Item.name; category = [string]$Item.category }
    }
    if (($market.PSObject.Properties['catalogActive'] -and $market.catalogActive -eq $false) -or
        ($market.PSObject.Properties['catalogStatus'] -and [string]$market.catalogStatus -eq 'legacy_removed')) {
        return [pscustomobject]@{ visible = $false; itemId = $itemId; name = [string]$Item.name; category = [string]$Item.category }
    }

    $name = [string]$Item.name
    $category = [string]$Item.category
    if ($EngineState.PSObject.Properties['itemMetadata']) {
        $metadata = Get-VisibleItemsDynamicProperty $EngineState.itemMetadata ([string]$itemId)
        if ($null -ne $metadata) {
            if ($metadata.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$metadata.name)) { $name = [string]$metadata.name }
            if ($metadata.PSObject.Properties['category'] -and -not [string]::IsNullOrWhiteSpace([string]$metadata.category)) { $category = [string]$metadata.category }
        }
    }

    $foreignPrice = if ($market.PSObject.Properties['lastForeignPrice']) { [long]$market.lastForeignPrice } else { 0L }
    $stock = if ($market.PSObject.Properties['lastStock']) { [int]$market.lastStock } else { 0 }
    $sourceTimestamp = if ($market.PSObject.Properties['sourceTimestamp']) { [long]$market.sourceTimestamp } else { 0L }
    $source = if ($market.PSObject.Properties['source']) { [string]$market.source } else { '' }

    $lastSoldOutAt = 0L
    if ($EngineState.PSObject.Properties['destinations']) {
        $destination = Get-VisibleItemsDynamicProperty $EngineState.destinations $marketKey
        if ($null -ne $destination -and $destination.PSObject.Properties['lastSellOutAt']) { $lastSoldOutAt = [long]$destination.lastSellOutAt }
    }

    $resale = Get-VisibleItemsResaleSnapshot -EngineState $EngineState -ItemId $itemId -NowEpoch $NowEpoch -FreshSeconds $ResaleFreshSeconds
    $effects = Get-TravelProfileEffects -Profile $TravelProfile -PerksConfig $PerksConfig -Item $Item
    $economics = Get-EffectiveTravelEconomics -Country $Country -TravelMode $TravelMode -Effects $effects -CapacityOverride $CapacityOverride

    $priceClass = 'UNKNOWN'
    $tripProfit = 0L
    $tripMargin = 0.0
    $netProfitPerItem = 0L
    $netResalePrice = 0L
    $capacity = [int]$economics.capacity
    $travelCost = [long]$economics.travelCost
    $economicsReady = ([bool]$resale.fresh -and [bool]$economics.travelCostKnown -and [bool]$economics.capacityKnown -and $capacity -gt 0 -and $foreignPrice -gt 0)

    if ($economicsReady) {
        $feePercent = if ($Profitability.PSObject.Properties['itemMarketFeePercent']) { [double]$Profitability.itemMarketFeePercent } else { 5.0 }
        $feePercent = [Math]::Max(0.0, [Math]::Min(100.0, $feePercent))
        $netResalePrice = [long][Math]::Floor([long]$resale.price * (1.0 - ($feePercent / 100.0)))
        $netProfitPerItem = [long]($netResalePrice - $foreignPrice)
        $tripProfit = [long](($netProfitPerItem * $capacity) - $travelCost)
        $tripSpend = [long](($foreignPrice * $capacity) + $travelCost)
        if ($tripSpend -gt 0) { $tripMargin = 100.0 * $tripProfit / [double]$tripSpend }

        $minimumProfitPerItem = if ($Profitability.PSObject.Properties['minimumProfitPerItem']) { [double]$Profitability.minimumProfitPerItem } else { 0.0 }
        $minimumMarginPercent = if ($Profitability.PSObject.Properties['minimumMarginPercent']) { [double]$Profitability.minimumMarginPercent } else { 0.0 }
        $minimumTotalTripProfit = if ($Profitability.PSObject.Properties['minimumTotalTripProfit']) { [double]$Profitability.minimumTotalTripProfit } else { 0.0 }
        $requiredTripProfit = [Math]::Max($minimumTotalTripProfit, ($minimumProfitPerItem * $capacity))

        if ($tripProfit -lt 0) { $priceClass = 'UNPROFITABLE' }
        elseif ($tripProfit -lt $requiredTripProfit -or $tripMargin -lt $minimumMarginPercent) { $priceClass = 'LOW_MARGIN' }
        else { $priceClass = 'GOOD' }
    }

    return [pscustomobject]@{
        visible = $true
        itemId = $itemId
        name = $name
        category = $category
        stock = $stock
        foreignPrice = $foreignPrice
        marketValue = [long]$resale.price
        marketValueFetchedAt = [long]$resale.fetchedAt
        marketValueFresh = [bool]$resale.fresh
        sourceTimestamp = $sourceTimestamp
        source = $source
        lastSoldOutAt = $lastSoldOutAt
        capacity = $capacity
        capacityKnown = [bool]$economics.capacityKnown
        travelCost = $travelCost
        travelCostKnown = [bool]$economics.travelCostKnown
        netResalePrice = $netResalePrice
        netProfitPerItem = $netProfitPerItem
        tripProfit = $tripProfit
        tripMarginPercent = $tripMargin
        priceClass = $priceClass
    }
}

function Set-VisibleSecondaryState {
    param([hashtable]$State, [string]$Prefix, [object]$Presentation)
    $State[$Prefix + 'SecondaryVisible'] = if ($null -ne $Presentation -and [bool]$Presentation.visible) { 1 } else { 0 }
    if ($null -eq $Presentation) { return }
    $State[$Prefix + 'SecondaryItemId'] = [int]$Presentation.itemId
    $State[$Prefix + 'SecondaryName'] = [string]$Presentation.name
    $State[$Prefix + 'SecondaryCategory'] = [string]$Presentation.category
    if (-not [bool]$Presentation.visible) { return }
    $State[$Prefix + 'SecondaryStock'] = [int]$Presentation.stock
    $State[$Prefix + 'SecondaryForeignPrice'] = [long]$Presentation.foreignPrice
    $State[$Prefix + 'SecondaryMarketValue'] = [long]$Presentation.marketValue
    $State[$Prefix + 'SecondaryMarketValueFetchedAt'] = [long]$Presentation.marketValueFetchedAt
    $State[$Prefix + 'SecondaryMarketValueFresh'] = if ([bool]$Presentation.marketValueFresh) { 1 } else { 0 }
    $State[$Prefix + 'SecondarySourceTimestamp'] = [long]$Presentation.sourceTimestamp
    $State[$Prefix + 'SecondarySource'] = [string]$Presentation.source
    $State[$Prefix + 'SecondaryLastSoldOutAt'] = [long]$Presentation.lastSoldOutAt
    $State[$Prefix + 'SecondaryCapacity'] = [int]$Presentation.capacity
    $State[$Prefix + 'SecondaryCapacityKnown'] = if ([bool]$Presentation.capacityKnown) { 1 } else { 0 }
    $State[$Prefix + 'SecondaryTravelCost'] = if ([bool]$Presentation.travelCostKnown) { [long]$Presentation.travelCost } else { -1 }
    $State[$Prefix + 'SecondaryNetResalePrice'] = [long]$Presentation.netResalePrice
    $State[$Prefix + 'SecondaryNetProfitPerItem'] = [long]$Presentation.netProfitPerItem
    $State[$Prefix + 'SecondaryTripProfit'] = [long]$Presentation.tripProfit
    $State[$Prefix + 'SecondaryTripMarginPercent'] = ('{0:F4}' -f [double]$Presentation.tripMarginPercent)
    $State[$Prefix + 'SecondaryPriceClass'] = [string]$Presentation.priceClass
}

if ($SkipMain) { return }
if ($Now -le 0) { $Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

$settings = Read-VisibleItemsJson (Join-Path $ConfigDir 'settings.example.json')
$localSettings = Read-VisibleItemsJson (Join-Path $ConfigDir 'settings.local.json')
$itemsConfig = Read-VisibleItemsJson (Join-Path $ConfigDir 'items.json')
$countriesConfig = Read-VisibleItemsJson (Join-Path $ConfigDir 'countries.json')
$perksConfig = Read-VisibleItemsJson (Join-Path $ConfigDir 'travel-perks.json')
$engineState = Read-VisibleItemsJson $EngineStateFile
$state = Read-VisibleItemsStateKv $StateKvFile
if ($null -eq $settings -or $null -eq $itemsConfig -or $null -eq $countriesConfig -or $null -eq $perksConfig -or $null -eq $engineState -or $state.Count -eq 0) { return }

$primary = @($itemsConfig.items | Where-Object { $_.enabled -eq $true } | Select-Object -First 1)
if ($primary.Count -eq 0) { return }
$primaryItemId = [int]$primary[0].itemId
$primaryResale = Get-VisibleItemsResaleSnapshot -EngineState $engineState -ItemId $primaryItemId -NowEpoch $Now
$profitability = Get-VisibleItemsProfitabilitySettings -BaseSettings $settings -LocalSettings $localSettings
$capacityOverride = if ($profitability.PSObject.Properties['capacityOverride']) { [int]$profitability.capacityOverride } else { 0 }
if ($capacityOverride -lt 0) { $capacityOverride = 0 }
$profile = Get-TravelProfile -BaseSettings $settings -LocalSettings $localSettings
$mode = if ($state.ContainsKey('TravelMode') -and -not [string]::IsNullOrWhiteSpace([string]$state['TravelMode'])) { [string]$state['TravelMode'] } else { [string]$settings.travelMode }

foreach ($country in @($countriesConfig.countries | Where-Object { $_.enabled -eq $true })) {
    $prefix = if ([string]$country.id -eq 'united_kingdom') { 'UK' } elseif ([string]$country.id -eq 'japan') { 'JP' } else { ([string]$country.id).ToUpperInvariant() }
    $state[$prefix + 'MarketValue'] = [long]$primaryResale.price
    $state[$prefix + 'MarketValueFetchedAt'] = [long]$primaryResale.fetchedAt

    $secondary = Get-VisibleSecondaryItem -ItemsConfig $itemsConfig -CountryId ([string]$country.id) -PrimaryItemId $primaryItemId
    if ($null -eq $secondary) {
        $state[$prefix + 'SecondaryVisible'] = 0
        continue
    }
    $presentation = Get-VisibleSecondaryPresentation -Country $country -Item $secondary -EngineState $engineState -TravelProfile $profile -PerksConfig $perksConfig -Profitability $profitability -TravelMode $mode -NowEpoch $Now -CapacityOverride $capacityOverride
    Set-VisibleSecondaryState -State $state -Prefix $prefix -Presentation $presentation
}

Write-VisibleItemsStateKvAtomic -Values $state -Path $StateKvFile
return
