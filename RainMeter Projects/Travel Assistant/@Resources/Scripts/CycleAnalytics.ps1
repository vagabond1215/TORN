param(
    [Alias('SkipMain')]
    [switch]$CycleAnalyticsSkipMain
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$CycleFile = Join-Path $RuntimeDir 'cycles.jsonl'
$StateKvFile = Join-Path $ProjectRoot '@Resources\Generated\state.kv'

function Read-CycleAnalyticsJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-CycleAnalyticsJsonAtomic {
    param([string]$Path,[object]$Value,[int]$Depth=32)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $tmp = $Path + '.tmp'
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-CycleAnalyticsProperty {
    param([object]$Object,[string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Set-CycleAnalyticsProperty {
    param([object]$Object,[string]$Name,[object]$Value)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { $Object | Add-Member NoteProperty $Name $Value }
    else { $property.Value = $Value }
}

function New-CycleRunningStats {
    return [pscustomobject]@{
        count = 0
        min = 0.0
        max = 0.0
        mean = 0.0
        m2 = 0.0
        stdDev = 0.0
    }
}

function Update-CycleRunningStats {
    param([object]$Stats,[double]$Value)
    if ($null -eq $Stats) { return }
    $count = [int](Get-CycleAnalyticsProperty $Stats 'count')
    if ($count -le 0) {
        $Stats.count = 1
        $Stats.min = $Value
        $Stats.max = $Value
        $Stats.mean = $Value
        $Stats.m2 = 0.0
        $Stats.stdDev = 0.0
        return
    }
    $nextCount = $count + 1
    if ($Value -lt [double]$Stats.min) { $Stats.min = $Value }
    if ($Value -gt [double]$Stats.max) { $Stats.max = $Value }
    $delta = $Value - [double]$Stats.mean
    $mean = [double]$Stats.mean + ($delta / [double]$nextCount)
    $delta2 = $Value - $mean
    $m2 = [double]$Stats.m2 + ($delta * $delta2)
    $Stats.count = $nextCount
    $Stats.mean = $mean
    $Stats.m2 = $m2
    $Stats.stdDev = if ($nextCount -gt 1) { [Math]::Sqrt($m2 / [double]($nextCount - 1)) } else { 0.0 }
}

function Get-CycleAnalyticsConfig {
    param([object]$Settings)
    $node = Get-CycleAnalyticsProperty $Settings 'cycleAnalytics'
    $pricePct = 5.0
    $selloutPct = 15.0
    $selloutSeconds = 300
    $maxRecent = 96
    $maxRegimes = 24
    $maxPriceEvents = 48
    if ($null -ne $node) {
        if ($node.PSObject.Properties['significantPriceChangePercent']) { $pricePct = [Math]::Max(0.5,[double]$node.significantPriceChangePercent) }
        if ($node.PSObject.Properties['significantSelloutChangePercent']) { $selloutPct = [Math]::Max(1.0,[double]$node.significantSelloutChangePercent) }
        if ($node.PSObject.Properties['significantSelloutChangeSeconds']) { $selloutSeconds = [Math]::Max(60,[int]$node.significantSelloutChangeSeconds) }
        if ($node.PSObject.Properties['maxRecentSamplesPerMarket']) { $maxRecent = [Math]::Max(12,[Math]::Min(256,[int]$node.maxRecentSamplesPerMarket)) }
        if ($node.PSObject.Properties['maxRegimesPerMarket']) { $maxRegimes = [Math]::Max(4,[Math]::Min(64,[int]$node.maxRegimesPerMarket)) }
        if ($node.PSObject.Properties['maxPriceEventsPerMarket']) { $maxPriceEvents = [Math]::Max(8,[Math]::Min(128,[int]$node.maxPriceEventsPerMarket)) }
    }
    return [pscustomobject]@{
        significantPriceChangePercent = $pricePct
        significantSelloutChangePercent = $selloutPct
        significantSelloutChangeSeconds = $selloutSeconds
        maxRecentSamplesPerMarket = $maxRecent
        maxRegimesPerMarket = $maxRegimes
        maxPriceEventsPerMarket = $maxPriceEvents
    }
}

function Get-CycleAnalyticsConfigSignature {
    param([object]$Config)
    return ('{0:R}|{1:R}|{2}|{3}|{4}|{5}' -f [double]$Config.significantPriceChangePercent,[double]$Config.significantSelloutChangePercent,[int]$Config.significantSelloutChangeSeconds,[int]$Config.maxRecentSamplesPerMarket,[int]$Config.maxRegimesPerMarket,[int]$Config.maxPriceEventsPerMarket)
}

function New-CycleAnalyticsRoot {
    param([object]$Config)
    return [pscustomobject]@{
        schemaVersion = 1
        configSignature = Get-CycleAnalyticsConfigSignature -Config $Config
        sourceLength = 0L
        sourceLastWriteUtcTicks = 0L
        lastProcessedAt = 0L
        lastRebuildAt = 0L
        marketCount = 0
        markets = [pscustomobject]@{}
    }
}

function New-CycleMarketAnalytics {
    return [pscustomobject]@{
        sampleCount = 0
        restockDelay = New-CycleRunningStats
        selloutDuration = New-CycleRunningStats
        foreignPrice = New-CycleRunningStats
        priceToMvRatioBps = New-CycleRunningStats
        lastForeignPrice = 0L
        lastSelloutSeconds = 0L
        lastRestockDelaySeconds = 0L
        lastCycleAt = 0L
        currentForeignPrice = 0L
        currentMarketValue = 0L
        currentPriceToMvRatioBps = 0
        priceEventAnchor = 0L
        recentSamples = [object[]]@()
        regimes = [object[]]@()
        priceEvents = [object[]]@()
    }
}

function Get-OrCreateCycleMarketAnalytics {
    param([object]$Root,[string]$Key)
    $property = $Root.markets.PSObject.Properties[$Key]
    if ($null -ne $property) { return $property.Value }
    $market = New-CycleMarketAnalytics
    $Root.markets | Add-Member NoteProperty $Key $market
    return $market
}

function Get-RelativeChangePercent {
    param([double]$Previous,[double]$Current)
    if ($Previous -le 0) { return 0.0 }
    return (100.0 * [Math]::Abs($Current-$Previous) / [Math]::Abs($Previous))
}

function Test-SignificantSelloutChange {
    param([long]$Previous,[long]$Current,[object]$Config)
    if ($Previous -le 0 -or $Current -le 0) { return $false }
    $relativeFloor = [Math]::Abs([double]$Previous) * ([double]$Config.significantSelloutChangePercent / 100.0)
    $threshold = [Math]::Max([double]$Config.significantSelloutChangeSeconds,$relativeFloor)
    return [Math]::Abs([double]$Current-[double]$Previous) -ge $threshold
}

function New-CyclePriceRegime {
    param([long]$CycleAt,[long]$ForeignPrice,[long]$SelloutSeconds,[string]$Reason)
    return [pscustomobject]@{
        reason = $Reason
        startedAt = $CycleAt
        lastCycleAt = $CycleAt
        anchorForeignPrice = $ForeignPrice
        anchorSelloutSeconds = $SelloutSeconds
        sampleCount = 0
        restockDelay = New-CycleRunningStats
        selloutDuration = New-CycleRunningStats
        foreignPrice = New-CycleRunningStats
        priceToMvRatioBps = New-CycleRunningStats
    }
}

function Update-CyclePriceRegime {
    param([object]$Regime,[long]$CycleAt,[long]$RestockDelay,[long]$SelloutSeconds,[long]$ForeignPrice,[int]$RatioBps)
    $Regime.sampleCount = [int]$Regime.sampleCount + 1
    $Regime.lastCycleAt = $CycleAt
    Update-CycleRunningStats -Stats $Regime.restockDelay -Value $RestockDelay
    Update-CycleRunningStats -Stats $Regime.selloutDuration -Value $SelloutSeconds
    if ($ForeignPrice -gt 0) { Update-CycleRunningStats -Stats $Regime.foreignPrice -Value $ForeignPrice }
    if ($RatioBps -gt 0) { Update-CycleRunningStats -Stats $Regime.priceToMvRatioBps -Value $RatioBps }
}

function Add-BoundedCycleArrayValue {
    param([object[]]$Values,[object]$Value,[int]$Maximum)
    $next = [object[]](@($Values) + @($Value))
    if ($next.Count -le $Maximum) { return $next }
    return [object[]]@($next | Select-Object -Last $Maximum)
}

function Update-CycleMarketAnalytics {
    param(
        [object]$Root,
        [object]$Cycle,
        [object]$Config,
        [long]$MarketValue = 0L
    )
    $country = [string](Get-CycleAnalyticsProperty $Cycle 'country')
    $itemId = [int](Get-CycleAnalyticsProperty $Cycle 'itemId')
    $restockDelay = [long](Get-CycleAnalyticsProperty $Cycle 'restockDelaySeconds')
    $selloutSeconds = [long](Get-CycleAnalyticsProperty $Cycle 'availabilitySeconds')
    $foreignPrice = [long](Get-CycleAnalyticsProperty $Cycle 'foreignPrice')
    $cycleAt = [long](Get-CycleAnalyticsProperty $Cycle 'soldOutAt')
    if ([string]::IsNullOrWhiteSpace($country) -or $itemId -le 0 -or $selloutSeconds -le 0 -or $restockDelay -lt 0) { return $false }
    if ($cycleAt -le 0) { $cycleAt = [long](Get-CycleAnalyticsProperty $Cycle 'restockAt') + $selloutSeconds }

    $key = ($country + ':' + $itemId).ToLowerInvariant()
    $market = Get-OrCreateCycleMarketAnalytics -Root $Root -Key $key
    $previousPrice = [long]$market.lastForeignPrice
    $previousSellout = [long]$market.lastSelloutSeconds
    $priceChangePct = Get-RelativeChangePercent -Previous $previousPrice -Current $foreignPrice
    $priceSignificant = ($previousPrice -gt 0 -and $foreignPrice -gt 0 -and $priceChangePct -ge [double]$Config.significantPriceChangePercent)
    $selloutSignificant = Test-SignificantSelloutChange -Previous $previousSellout -Current $selloutSeconds -Config $Config

    $reason = ''
    if ($priceSignificant -and $selloutSignificant) { $reason = 'price+sellout' }
    elseif ($priceSignificant) { $reason = 'price' }
    elseif ($selloutSignificant) { $reason = 'sellout' }

    $ratioBps = 0
    if ($foreignPrice -gt 0 -and $MarketValue -gt 0) {
        $ratioBps = [int][Math]::Round((10000.0 * [double]$foreignPrice) / [double]$MarketValue)
    }

    $regimes = [object[]]@($market.regimes)
    if ($regimes.Count -eq 0 -or -not [string]::IsNullOrWhiteSpace($reason)) {
        if ([string]::IsNullOrWhiteSpace($reason)) { $reason = 'initial' }
        $regime = New-CyclePriceRegime -CycleAt $cycleAt -ForeignPrice $foreignPrice -SelloutSeconds $selloutSeconds -Reason $reason
        $regimes = Add-BoundedCycleArrayValue -Values $regimes -Value $regime -Maximum ([int]$Config.maxRegimesPerMarket)
        $market.regimes = $regimes
    }
    $activeRegime = @($market.regimes | Select-Object -Last 1)[0]
    Update-CyclePriceRegime -Regime $activeRegime -CycleAt $cycleAt -RestockDelay $restockDelay -SelloutSeconds $selloutSeconds -ForeignPrice $foreignPrice -RatioBps $ratioBps

    $market.sampleCount = [int]$market.sampleCount + 1
    Update-CycleRunningStats -Stats $market.restockDelay -Value $restockDelay
    Update-CycleRunningStats -Stats $market.selloutDuration -Value $selloutSeconds
    if ($foreignPrice -gt 0) { Update-CycleRunningStats -Stats $market.foreignPrice -Value $foreignPrice }
    if ($ratioBps -gt 0) { Update-CycleRunningStats -Stats $market.priceToMvRatioBps -Value $ratioBps }

    $sample = [pscustomobject]@{
        soldOutAt = $cycleAt
        restockDelaySeconds = $restockDelay
        availabilitySeconds = $selloutSeconds
        foreignPrice = $foreignPrice
        marketValue = $MarketValue
        priceToMvRatioBps = $ratioBps
    }
    $market.recentSamples = Add-BoundedCycleArrayValue -Values ([object[]]@($market.recentSamples)) -Value $sample -Maximum ([int]$Config.maxRecentSamplesPerMarket)
    $market.lastForeignPrice = $foreignPrice
    $market.lastSelloutSeconds = $selloutSeconds
    $market.lastRestockDelaySeconds = $restockDelay
    $market.lastCycleAt = $cycleAt
    return $true
}

function Read-CycleAnalyticsStateKv {
    param([string]$Path)
    $state=@{}
    if (-not (Test-Path -LiteralPath $Path)) { return $state }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $at=$line.IndexOf('=')
        if ($at -lt 1) { continue }
        $state[$line.Substring(0,$at).Trim([char]0xFEFF).Trim()]=$line.Substring($at+1).Trim()
    }
    return $state
}

function Get-CycleAnalyticsActiveMarketScope {
    param([hashtable]$State)
    $wanted=@{}
    if ($null -eq $State -or $State.Count -eq 0) { return $wanted }
    $count=0
    if ($State.ContainsKey('OpportunityCount')) { [void][int]::TryParse([string]$State['OpportunityCount'],[ref]$count) }
    $count=[Math]::Min(256,[Math]::Max(0,$count))
    for ($i=1; $i -le $count; $i++) {
        $prefix='Opportunity'+$i
        $key=([string]$State[$prefix+'Key']).Trim().ToLowerInvariant()
        $mode=([string]$State[$prefix+'ForecastMode']).Trim().ToLowerInvariant()
        if ($key -match '^[a-z0-9_]+:[1-9][0-9]*
    param([object]$EngineState,[int]$ItemId)
    if ($null -eq $EngineState -or -not $EngineState.PSObject.Properties['resaleCache']) { return 0L }
    $entry = Get-CycleAnalyticsProperty $EngineState.resaleCache ([string]$ItemId)
    if ($null -eq $entry) { return 0L }
    if ($entry.PSObject.Properties['average'] -and [long]$entry.average -gt 0) { return [long]$entry.average }
    return 0L
}

function Update-CurrentCycleMarketSnapshots {
    param([object]$Root,[object]$EngineState,[object]$Config,[long]$NowEpoch,[hashtable]$WantedKeys=$null)
    if ($null -eq $EngineState -or -not $EngineState.PSObject.Properties['observedMarkets']) { return $false }
    $changed = $false
    foreach ($property in @($EngineState.observedMarkets.PSObject.Properties)) {
        $key = ([string]$property.Name).ToLowerInvariant()
        if ($null -ne $WantedKeys -and -not $WantedKeys.ContainsKey($key)) { continue }
        $observed = $property.Value
        if ($null -eq $observed) { continue }
        $itemId = [int](Get-CycleAnalyticsProperty $observed 'itemId')
        $foreignPrice = [long](Get-CycleAnalyticsProperty $observed 'lastForeignPrice')
        if ($itemId -le 0 -or $foreignPrice -le 0) { continue }
        $market = Get-OrCreateCycleMarketAnalytics -Root $Root -Key $key
        $marketValue = Get-CurrentCycleMarketValue -EngineState $EngineState -ItemId $itemId
        $ratioBps = if ($marketValue -gt 0) { [int][Math]::Round((10000.0 * [double]$foreignPrice) / [double]$marketValue) } else { 0 }

        if ([long]$market.currentForeignPrice -ne $foreignPrice -or [long]$market.currentMarketValue -ne $marketValue -or [int]$market.currentPriceToMvRatioBps -ne $ratioBps) {
            $market.currentForeignPrice = $foreignPrice
            $market.currentMarketValue = $marketValue
            $market.currentPriceToMvRatioBps = $ratioBps
            $changed = $true
        }

        $anchor = [long]$market.priceEventAnchor
        if ($anchor -le 0) {
            $market.priceEventAnchor = $foreignPrice
            $changed = $true
            continue
        }
        $changePct = Get-RelativeChangePercent -Previous $anchor -Current $foreignPrice
        if ($changePct -lt [double]$Config.significantPriceChangePercent) { continue }
        $event = [pscustomobject]@{
            at = $NowEpoch
            fromPrice = $anchor
            toPrice = $foreignPrice
            changePercent = $changePct
            stock = [long](Get-CycleAnalyticsProperty $observed 'lastStock')
            marketValue = $marketValue
            priceToMvRatioBps = $ratioBps
        }
        $market.priceEvents = Add-BoundedCycleArrayValue -Values ([object[]]@($market.priceEvents)) -Value $event -Maximum ([int]$Config.maxPriceEventsPerMarket)
        $market.priceEventAnchor = $foreignPrice
        $changed = $true
    }
    return $changed
}

function Get-CycleFileInfo {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{ length=0L; ticks=0L } }
    $info = Get-Item -LiteralPath $Path -ErrorAction Stop
    return [pscustomobject]@{ length=[long]$info.Length; ticks=[long]$info.LastWriteTimeUtc.Ticks }
}

function Read-CycleLinesFromOffset {
    param([string]$Path,[long]$Offset)
    $lines = [string[]]@()
    if (-not (Test-Path -LiteralPath $Path)) { return $lines }
    $stream = $null
    $reader = $null
    try {
        $stream = New-Object System.IO.FileStream($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite)
        if ($Offset -gt 0) { [void]$stream.Seek($Offset,[System.IO.SeekOrigin]::Begin) }
        $reader = New-Object System.IO.StreamReader($stream,[System.Text.UTF8Encoding]::new($false),$true,4096,$true)
        $buffer = @()
        while (-not $reader.EndOfStream) { $buffer += [string]$reader.ReadLine() }
        return [string[]]$buffer
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Process-CycleAnalyticsLines {
    param([object]$Root,[string[]]$Lines,[object]$Config,[object]$EngineState,[long]$NowEpoch,[switch]$AllowCurrentMarketValue)
    $changed = $false
    foreach ($line in @($Lines)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $cycle = $line | ConvertFrom-Json } catch { continue }
        $marketValue = 0L
        if ($AllowCurrentMarketValue) {
            $soldOutAt = [long](Get-CycleAnalyticsProperty $cycle 'soldOutAt')
            if ($soldOutAt -gt 0 -and [Math]::Abs($NowEpoch-$soldOutAt) -le 900) {
                $marketValue = Get-CurrentCycleMarketValue -EngineState $EngineState -ItemId ([int](Get-CycleAnalyticsProperty $cycle 'itemId'))
            }
        }
        if (Update-CycleMarketAnalytics -Root $Root -Cycle $cycle -Config $Config -MarketValue $marketValue) { $changed = $true }
    }
    return $changed
}

if ($CycleAnalyticsSkipMain) { return }

$engineState = Read-CycleAnalyticsJson $EngineStateFile
if ($null -eq $engineState) { return }
$settings = Read-CycleAnalyticsJson (Join-Path $ConfigDir 'settings.example.json')
$config = Get-CycleAnalyticsConfig -Settings $settings
$configSignature = Get-CycleAnalyticsConfigSignature -Config $config
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$fileInfo = Get-CycleFileInfo -Path $CycleFile
$root = Get-CycleAnalyticsProperty $engineState 'cycleAnalytics'
$rebuild = $false
if ($null -eq $root -or -not $root.PSObject.Properties['schemaVersion'] -or [int]$root.schemaVersion -ne 1) { $rebuild = $true }
elseif ([string](Get-CycleAnalyticsProperty $root 'configSignature') -ne $configSignature) { $rebuild = $true }
elseif ([long](Get-CycleAnalyticsProperty $root 'sourceLength') -gt [long]$fileInfo.length) { $rebuild = $true }
elseif ([long](Get-CycleAnalyticsProperty $root 'sourceLastWriteUtcTicks') -ne [long]$fileInfo.ticks -and [long]$fileInfo.length -le [long](Get-CycleAnalyticsProperty $root 'sourceLength')) { $rebuild = $true }

$changed = $false
if ($rebuild) {
    $root = New-CycleAnalyticsRoot -Config $config
    $lines = Read-CycleLinesFromOffset -Path $CycleFile -Offset 0
    [void](Process-CycleAnalyticsLines -Root $root -Lines $lines -Config $config -EngineState $engineState -NowEpoch $now)
    $root.lastRebuildAt = $now
    $changed = $true
} else {
    $previousLength = [long](Get-CycleAnalyticsProperty $root 'sourceLength')
    if ([long]$fileInfo.length -gt $previousLength) {
        $lines = Read-CycleLinesFromOffset -Path $CycleFile -Offset $previousLength
        if (Process-CycleAnalyticsLines -Root $root -Lines $lines -Config $config -EngineState $engineState -NowEpoch $now -AllowCurrentMarketValue) { $changed = $true }
    }
}

$currentSnapshotScope=Get-CycleAnalyticsActiveMarketScope -State (Read-CycleAnalyticsStateKv $StateKvFile)
if (Update-CurrentCycleMarketSnapshots -Root $root -EngineState $engineState -Config $config -NowEpoch $now -WantedKeys $currentSnapshotScope) { $changed = $true }
$root.sourceLength = [long]$fileInfo.length
$root.sourceLastWriteUtcTicks = [long]$fileInfo.ticks
$root.lastProcessedAt = $now
$root.marketCount = @($root.markets.PSObject.Properties).Count
Set-CycleAnalyticsProperty -Object $engineState -Name 'cycleAnalytics' -Value $root
if ($changed -or $rebuild) { Write-CycleAnalyticsJsonAtomic -Path $EngineStateFile -Value $engineState }
 -and $mode -ne 'sleeping_oos') {
            $wanted[$key]=$true
        }
    }
    return $wanted
}

function Get-CurrentCycleMarketValue {
    param([object]$EngineState,[int]$ItemId)
    if ($null -eq $EngineState -or -not $EngineState.PSObject.Properties['resaleCache']) { return 0L }
    $entry = Get-CycleAnalyticsProperty $EngineState.resaleCache ([string]$ItemId)
    if ($null -eq $entry) { return 0L }
    if ($entry.PSObject.Properties['average'] -and [long]$entry.average -gt 0) { return [long]$entry.average }
    return 0L
}

function Update-CurrentCycleMarketSnapshots {
    param([object]$Root,[object]$EngineState,[object]$Config,[long]$NowEpoch)
    if ($null -eq $EngineState -or -not $EngineState.PSObject.Properties['observedMarkets']) { return $false }
    $changed = $false
    foreach ($property in @($EngineState.observedMarkets.PSObject.Properties)) {
        $key = ([string]$property.Name).ToLowerInvariant()
        $observed = $property.Value
        if ($null -eq $observed) { continue }
        $itemId = [int](Get-CycleAnalyticsProperty $observed 'itemId')
        $foreignPrice = [long](Get-CycleAnalyticsProperty $observed 'lastForeignPrice')
        if ($itemId -le 0 -or $foreignPrice -le 0) { continue }
        $market = Get-OrCreateCycleMarketAnalytics -Root $Root -Key $key
        $marketValue = Get-CurrentCycleMarketValue -EngineState $EngineState -ItemId $itemId
        $ratioBps = if ($marketValue -gt 0) { [int][Math]::Round((10000.0 * [double]$foreignPrice) / [double]$marketValue) } else { 0 }

        if ([long]$market.currentForeignPrice -ne $foreignPrice -or [long]$market.currentMarketValue -ne $marketValue -or [int]$market.currentPriceToMvRatioBps -ne $ratioBps) {
            $market.currentForeignPrice = $foreignPrice
            $market.currentMarketValue = $marketValue
            $market.currentPriceToMvRatioBps = $ratioBps
            $changed = $true
        }

        $anchor = [long]$market.priceEventAnchor
        if ($anchor -le 0) {
            $market.priceEventAnchor = $foreignPrice
            $changed = $true
            continue
        }
        $changePct = Get-RelativeChangePercent -Previous $anchor -Current $foreignPrice
        if ($changePct -lt [double]$Config.significantPriceChangePercent) { continue }
        $event = [pscustomobject]@{
            at = $NowEpoch
            fromPrice = $anchor
            toPrice = $foreignPrice
            changePercent = $changePct
            stock = [long](Get-CycleAnalyticsProperty $observed 'lastStock')
            marketValue = $marketValue
            priceToMvRatioBps = $ratioBps
        }
        $market.priceEvents = Add-BoundedCycleArrayValue -Values ([object[]]@($market.priceEvents)) -Value $event -Maximum ([int]$Config.maxPriceEventsPerMarket)
        $market.priceEventAnchor = $foreignPrice
        $changed = $true
    }
    return $changed
}

function Get-CycleFileInfo {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return [pscustomobject]@{ length=0L; ticks=0L } }
    $info = Get-Item -LiteralPath $Path -ErrorAction Stop
    return [pscustomobject]@{ length=[long]$info.Length; ticks=[long]$info.LastWriteTimeUtc.Ticks }
}

function Read-CycleLinesFromOffset {
    param([string]$Path,[long]$Offset)
    $lines = [string[]]@()
    if (-not (Test-Path -LiteralPath $Path)) { return $lines }
    $stream = $null
    $reader = $null
    try {
        $stream = New-Object System.IO.FileStream($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,[System.IO.FileShare]::ReadWrite)
        if ($Offset -gt 0) { [void]$stream.Seek($Offset,[System.IO.SeekOrigin]::Begin) }
        $reader = New-Object System.IO.StreamReader($stream,[System.Text.UTF8Encoding]::new($false),$true,4096,$true)
        $buffer = @()
        while (-not $reader.EndOfStream) { $buffer += [string]$reader.ReadLine() }
        return [string[]]$buffer
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Process-CycleAnalyticsLines {
    param([object]$Root,[string[]]$Lines,[object]$Config,[object]$EngineState,[long]$NowEpoch,[switch]$AllowCurrentMarketValue)
    $changed = $false
    foreach ($line in @($Lines)) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $cycle = $line | ConvertFrom-Json } catch { continue }
        $marketValue = 0L
        if ($AllowCurrentMarketValue) {
            $soldOutAt = [long](Get-CycleAnalyticsProperty $cycle 'soldOutAt')
            if ($soldOutAt -gt 0 -and [Math]::Abs($NowEpoch-$soldOutAt) -le 900) {
                $marketValue = Get-CurrentCycleMarketValue -EngineState $EngineState -ItemId ([int](Get-CycleAnalyticsProperty $cycle 'itemId'))
            }
        }
        if (Update-CycleMarketAnalytics -Root $Root -Cycle $cycle -Config $Config -MarketValue $marketValue) { $changed = $true }
    }
    return $changed
}

if ($CycleAnalyticsSkipMain) { return }

$engineState = Read-CycleAnalyticsJson $EngineStateFile
if ($null -eq $engineState) { return }
$settings = Read-CycleAnalyticsJson (Join-Path $ConfigDir 'settings.example.json')
$config = Get-CycleAnalyticsConfig -Settings $settings
$configSignature = Get-CycleAnalyticsConfigSignature -Config $config
$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$fileInfo = Get-CycleFileInfo -Path $CycleFile
$root = Get-CycleAnalyticsProperty $engineState 'cycleAnalytics'
$rebuild = $false
if ($null -eq $root -or -not $root.PSObject.Properties['schemaVersion'] -or [int]$root.schemaVersion -ne 1) { $rebuild = $true }
elseif ([string](Get-CycleAnalyticsProperty $root 'configSignature') -ne $configSignature) { $rebuild = $true }
elseif ([long](Get-CycleAnalyticsProperty $root 'sourceLength') -gt [long]$fileInfo.length) { $rebuild = $true }
elseif ([long](Get-CycleAnalyticsProperty $root 'sourceLastWriteUtcTicks') -ne [long]$fileInfo.ticks -and [long]$fileInfo.length -le [long](Get-CycleAnalyticsProperty $root 'sourceLength')) { $rebuild = $true }

$changed = $false
if ($rebuild) {
    $root = New-CycleAnalyticsRoot -Config $config
    $lines = Read-CycleLinesFromOffset -Path $CycleFile -Offset 0
    [void](Process-CycleAnalyticsLines -Root $root -Lines $lines -Config $config -EngineState $engineState -NowEpoch $now)
    $root.lastRebuildAt = $now
    $changed = $true
} else {
    $previousLength = [long](Get-CycleAnalyticsProperty $root 'sourceLength')
    if ([long]$fileInfo.length -gt $previousLength) {
        $lines = Read-CycleLinesFromOffset -Path $CycleFile -Offset $previousLength
        if (Process-CycleAnalyticsLines -Root $root -Lines $lines -Config $config -EngineState $engineState -NowEpoch $now -AllowCurrentMarketValue) { $changed = $true }
    }
}

if (Update-CurrentCycleMarketSnapshots -Root $root -EngineState $engineState -Config $config -NowEpoch $now) { $changed = $true }
$root.sourceLength = [long]$fileInfo.length
$root.sourceLastWriteUtcTicks = [long]$fileInfo.ticks
$root.lastProcessedAt = $now
$root.marketCount = @($root.markets.PSObject.Properties).Count
Set-CycleAnalyticsProperty -Object $engineState -Name 'cycleAnalytics' -Value $root
if ($changed -or $rebuild) { Write-CycleAnalyticsJsonAtomic -Path $EngineStateFile -Value $engineState }
