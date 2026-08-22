param(
    [switch]$SkipMain,
    [long]$Now = 0
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'FilterPreferences.ps1') -SkipMain

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$RuntimeCycleFile = Join-Path $RuntimeDir 'cycles.jsonl'
$SeedCycleFile = Join-Path $ProjectRoot 'data\seed\cycles.jsonl'
$OutputFile = Join-Path $RuntimeDir 'browser-notifications.json'

function Read-BrowserNotificationJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Get-BrowserNotificationProperty {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Write-BrowserNotificationJsonAtomic {
    param([string]$Path,[object]$Value)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $tmp = $Path + '.tmp'
    $json = $Value | ConvertTo-Json -Depth 16
    [System.IO.File]::WriteAllText($tmp,$json,[System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Add-BrowserDelta {
    param([hashtable]$Map,[long]$At,[int]$Delta)
    $key = [string]$At
    if (-not $Map.ContainsKey($key)) { $Map[$key] = 0 }
    $Map[$key] = [int]$Map[$key] + $Delta
}

function Get-BrowserNotificationIntervals {
    param(
        [object[]]$Cycles,
        [int]$MinimumProbabilityPercent = 50
    )

    $minimum = [Math]::Max(1,[Math]::Min(100,$MinimumProbabilityPercent))
    $usable = @($Cycles | Where-Object {
        $null -ne $_ -and
        $_.PSObject.Properties['restockDelaySeconds'] -and [long]$_.restockDelaySeconds -ge 0 -and
        $_.PSObject.Properties['availabilitySeconds'] -and [long]$_.availabilitySeconds -gt 0
    })
    if ($usable.Count -eq 0) { return @() }

    $deltas = @{}
    foreach ($cycle in $usable) {
        $start = [long]$cycle.restockDelaySeconds
        $end = $start + [long]$cycle.availabilitySeconds
        if ($end -le $start) { continue }
        Add-BrowserDelta -Map $deltas -At $start -Delta 1
        Add-BrowserDelta -Map $deltas -At $end -Delta -1
    }
    if ($deltas.Count -lt 2) { return @() }

    $times = [long[]]@($deltas.Keys | ForEach-Object { [long]$_ } | Sort-Object -Unique)
    $thresholdHits = [int][Math]::Ceiling($usable.Count * ($minimum / 100.0))
    if ($thresholdHits -lt 1) { $thresholdHits = 1 }

    $rows = New-Object System.Collections.Generic.List[object]
    $active = 0
    $windowStart = $null
    $windowMinHits = 0

    for ($i=0; $i -lt ($times.Count - 1); $i++) {
        $at = [long]$times[$i]
        $active += [int]$deltas[[string]$at]
        $next = [long]$times[$i+1]
        $qualified = ($next -gt $at -and $active -ge $thresholdHits)

        if ($qualified) {
            if ($null -eq $windowStart) {
                $windowStart = $at
                $windowMinHits = $active
            } else {
                $windowMinHits = [Math]::Min($windowMinHits,$active)
            }
        } elseif ($null -ne $windowStart) {
            $rows.Add([pscustomobject]@{
                startAgeSeconds = [long]$windowStart
                endAgeSeconds = $at
                probability = ($windowMinHits / [double]$usable.Count)
                sampleCount = $usable.Count
            })
            $windowStart = $null
            $windowMinHits = 0
        }
    }

    if ($null -ne $windowStart) {
        $rows.Add([pscustomobject]@{
            startAgeSeconds = [long]$windowStart
            endAgeSeconds = [long]$times[$times.Count-1]
            probability = ($windowMinHits / [double]$usable.Count)
            sampleCount = $usable.Count
        })
    }

    return $rows.ToArray()
}

function Test-BrowserNotificationFilters {
    param([object]$Preferences,[string]$CountryId,[string]$TripBand,[int]$ItemId,[string]$Category)
    if (@($Preferences.ignoredItemIds) -contains $ItemId) { return $false }
    if (-not [bool]$Preferences.itemFilterAll -and -not (@($Preferences.selectedItemIds) -contains $ItemId)) { return $false }
    if (-not (@($Preferences.selectedTripBands) -contains $TripBand)) { return $false }
    if (-not (@($Preferences.selectedCountryIds) -contains $CountryId)) { return $false }
    if (-not [bool]$Preferences.categoryFilterAll -and -not (@($Preferences.selectedCategories) -contains $Category)) { return $false }
    return $true
}

function Format-BrowserNotificationMoney {
    param([long]$Value)
    if ($Value -lt 0) { return ('-${0:N0}' -f [Math]::Abs($Value)) }
    return ('${0:N0}' -f $Value)
}

if ($SkipMain) { return }
if ($Now -le 0) { $Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }

$preferences = Read-UiPreferences
$enabled = [bool]$preferences.browserNotificationsEnabled
$leadMinutes = [Math]::Max(1,[Math]::Min(120,[int]$preferences.notificationLeadMinutes))
$minimumProbabilityPercent = [Math]::Max(25,[Math]::Min(100,[int]$preferences.notificationMinProbabilityPercent))
$leadSeconds = [long]$leadMinutes * 60

$result = [pscustomobject]@{
    schemaVersion = 1
    generatedAt = $Now
    enabled = $enabled
    leadMinutes = $leadMinutes
    minimumProbabilityPercent = $minimumProbabilityPercent
    eventCount = 0
    events = @()
}

if (-not $enabled) {
    Write-BrowserNotificationJsonAtomic -Path $OutputFile -Value $result
    return
}

$engine = Read-BrowserNotificationJson $EngineStateFile
$settings = Read-BrowserNotificationJson (Join-Path $ConfigDir 'settings.example.json')
$countries = Read-BrowserNotificationJson (Join-Path $ConfigDir 'countries.json')
if ($null -eq $engine -or $null -eq $settings -or $null -eq $countries -or -not $engine.PSObject.Properties['observedMarkets']) {
    Write-BrowserNotificationJsonAtomic -Path $OutputFile -Value $result
    return
}

$minimumSamples = 3
if ($settings.PSObject.Properties['optimizer'] -and $settings.optimizer.PSObject.Properties['minimumAvailabilitySamples']) {
    $minimumSamples = [Math]::Max(1,[int]$settings.optimizer.minimumAvailabilitySamples)
}
$staleAfter = [Math]::Max(60,[long]$settings.staleAfterSeconds)
$resaleFresh = 21600L
if ($settings.PSObject.Properties['profitability'] -and $settings.profitability.PSObject.Properties['resaleStaleAfterSeconds']) {
    $resaleFresh = [Math]::Max(3600,[long]$settings.profitability.resaleStaleAfterSeconds)
}
$basisPercent = if ([bool]$preferences.use95PercentMarketValue) { 95 } else { 100 }

$countryIndex = @{}
foreach ($country in @($countries.countries | Where-Object { $_.collect -eq $true })) { $countryIndex[[string]$country.id] = $country }

$cycleMap = @{}
foreach ($path in @($SeedCycleFile,$RuntimeCycleFile)) {
    if (-not (Test-Path -LiteralPath $path)) { continue }
    foreach ($line in Get-Content -LiteralPath $path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $cycle = $line | ConvertFrom-Json
            $countryId = [string](Get-BrowserNotificationProperty $cycle 'country')
            $itemId = [int](Get-BrowserNotificationProperty $cycle 'itemId')
            if ([string]::IsNullOrWhiteSpace($countryId) -or $itemId -le 0) { continue }
            $key = $countryId + ':' + [string]$itemId
            if (-not $cycleMap.ContainsKey($key)) { $cycleMap[$key] = New-Object System.Collections.Generic.List[object] }
            $cycleMap[$key].Add($cycle)
        } catch { }
    }
}

$fixedCountry = ''
$travelContext = Get-BrowserNotificationProperty $engine 'travelContext'
if ($null -ne $travelContext -and [bool](Get-BrowserNotificationProperty $travelContext 'filterActive')) {
    $fixedCountry = [string](Get-BrowserNotificationProperty $travelContext 'destinationCountryId')
}

$events = New-Object System.Collections.Generic.List[object]
foreach ($property in @($engine.observedMarkets.PSObject.Properties)) {
    $market = $property.Value
    if ($null -eq $market) { continue }
    if (($market.PSObject.Properties['catalogActive'] -and $market.catalogActive -eq $false) -or ($market.PSObject.Properties['catalogStatus'] -and [string]$market.catalogStatus -eq 'legacy_removed')) { continue }

    $countryId = [string](Get-BrowserNotificationProperty $market 'country')
    $itemId = [int](Get-BrowserNotificationProperty $market 'itemId')
    if ([string]::IsNullOrWhiteSpace($countryId) -or $itemId -le 0 -or -not $countryIndex.ContainsKey($countryId)) { continue }
    if (-not [string]::IsNullOrWhiteSpace($fixedCountry) -and $countryId -ne $fixedCountry) { continue }
    if ([long](Get-BrowserNotificationProperty $market 'lastStock') -gt 0) { continue }

    $sourceTimestamp = [long](Get-BrowserNotificationProperty $market 'sourceTimestamp')
    if ($sourceTimestamp -le 0 -or ($Now - $sourceTimestamp) -gt $staleAfter) { continue }

    $country = $countryIndex[$countryId]
    $name = 'Item ' + $itemId
    if ($market.PSObject.Properties['providerName'] -and -not [string]::IsNullOrWhiteSpace([string]$market.providerName)) { $name = [string]$market.providerName }
    $category = 'Unknown'
    if ($engine.PSObject.Properties['itemMetadata']) {
        $metadata = Get-BrowserNotificationProperty $engine.itemMetadata ([string]$itemId)
        if ($null -ne $metadata) {
            if ($metadata.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$metadata.name)) { $name = [string]$metadata.name }
            if ($metadata.PSObject.Properties['category'] -and -not [string]::IsNullOrWhiteSpace([string]$metadata.category)) { $category = [string]$metadata.category }
        }
    }
    if (-not (Test-BrowserNotificationFilters -Preferences $preferences -CountryId $countryId -TripBand ([string]$country.tripBand) -ItemId $itemId -Category $category)) { continue }

    $resale = $null
    if ($engine.PSObject.Properties['resaleCache']) { $resale = Get-BrowserNotificationProperty $engine.resaleCache ([string]$itemId) }
    if ($null -eq $resale -or -not $resale.PSObject.Properties['average'] -or -not $resale.PSObject.Properties['fetchedAt']) { continue }
    $marketValue = [long]$resale.average
    $resaleFetchedAt = [long]$resale.fetchedAt
    if ($marketValue -le 0 -or $resaleFetchedAt -le 0 -or ($Now - $resaleFetchedAt) -gt $resaleFresh) { continue }

    $foreignPrice = [long](Get-BrowserNotificationProperty $market 'lastForeignPrice')
    if ($foreignPrice -le 0) { continue }
    $sellBasis = [long][Math]::Floor($marketValue * ($basisPercent / 100.0))
    $profitPerItem = $sellBasis - $foreignPrice
    if ($profitPerItem -le 0) { continue }

    $marketKey = $countryId + ':' + [string]$itemId
    if (-not $cycleMap.ContainsKey($marketKey) -or $cycleMap[$marketKey].Count -lt $minimumSamples) { continue }
    $destination = $null
    if ($engine.PSObject.Properties['destinations']) { $destination = Get-BrowserNotificationProperty $engine.destinations $marketKey }
    $lastSellOutAt = 0L
    if ($null -ne $destination -and $destination.PSObject.Properties['lastSellOutAt']) { $lastSellOutAt = [long]$destination.lastSellOutAt }
    if ($lastSellOutAt -le 0 -or $lastSellOutAt -gt $Now) { continue }

    $intervals = @(Get-BrowserNotificationIntervals -Cycles @($cycleMap[$marketKey]) -MinimumProbabilityPercent $minimumProbabilityPercent)
    if ($intervals.Count -eq 0) { continue }
    $currentAge = [Math]::Max(0L,$Now - $lastSellOutAt)
    $chosen = $null
    foreach ($interval in $intervals) {
        $windowStartAt = $lastSellOutAt + [long]$interval.startAgeSeconds
        $windowEndAt = $lastSellOutAt + [long]$interval.endAgeSeconds
        if ($windowEndAt -le $Now) { continue }
        if ($windowStartAt -gt ($Now + $leadSeconds)) { break }
        $chosen = [pscustomobject]@{ interval=$interval; startAt=$windowStartAt; endAt=$windowEndAt }
        break
    }
    if ($null -eq $chosen) { continue }

    $secondsUntil = [Math]::Max(0L,[long]$chosen.startAt - $Now)
    $probabilityPercent = [int][Math]::Round(100.0 * [double]$chosen.interval.probability)
    $state = if ($secondsUntil -le 0) { 'open' } else { 'upcoming' }
    $title = if ($state -eq 'open') { 'Modeled stock window open' } else { 'Modeled stock window upcoming' }
    $timeText = if ($state -eq 'open') { 'modeled open now' } else { ('starts in {0}m' -f [Math]::Max(1,[Math]::Ceiling($secondsUntil / 60.0))) }
    $message = ('{0} - {1}: {2}, {3}% support, {4}/ea.' -f $name,[string]$country.name,$timeText,$probabilityPercent,(Format-BrowserNotificationMoney $profitPerItem))
    $eventId = ('{0}-{1}-{2}-{3}-{4}' -f $countryId,$itemId,$lastSellOutAt,[long]$chosen.interval.startAgeSeconds,$minimumProbabilityPercent)

    $events.Add([pscustomobject]@{
        id = $eventId
        state = $state
        title = $title
        message = $message
        countryId = $countryId
        countryName = [string]$country.name
        itemId = $itemId
        itemName = $name
        category = $category
        profitPerItem = [long]$profitPerItem
        marketValueBasisPercent = $basisPercent
        probabilityPercent = $probabilityPercent
        sampleCount = [int]$chosen.interval.sampleCount
        windowStartAt = [long]$chosen.startAt
        windowEndAt = [long]$chosen.endAt
        expiresAt = [long]$chosen.endAt
        url = 'https://www.torn.com/page.php?sid=travel'
    })
}

$selectedEvents = @($events | Sort-Object @{Expression='windowStartAt';Ascending=$true}, @{Expression='profitPerItem';Descending=$true} | Select-Object -First 5)
$result.eventCount = $selectedEvents.Count
$result.events = $selectedEvents
Write-BrowserNotificationJsonAtomic -Path $OutputFile -Value $result
