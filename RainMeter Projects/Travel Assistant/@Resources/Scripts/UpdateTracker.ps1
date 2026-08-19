param(
    [ValidateSet('Update', 'CycleTravelMode')]
    [string]$Action = 'Update'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$ObservationFile = Join-Path $RuntimeDir 'observations.jsonl'
$CycleFile = Join-Path $RuntimeDir 'cycles.jsonl'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$PreferenceFile = Join-Path $RuntimeDir 'preferences.json'
$StateKvFile = Join-Path $GeneratedDir 'state.kv'

New-Item -ItemType Directory -Force -Path $RuntimeDir, $GeneratedDir | Out-Null

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-JsonAtomic {
    param([string]$Path, [object]$Value, [int]$Depth = 12)
    $tmp = $Path + '.tmp'
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-DynamicProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { return $null }
    return $prop.Value
}

function Set-DynamicProperty {
    param([object]$Object, [string]$Name, [object]$Value)
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) {
        $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value
    } else {
        $prop.Value = $Value
    }
}

function Get-NowEpoch {
    return [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
}

function Get-Median {
    param([double[]]$Values)
    if ($null -eq $Values -or $Values.Count -eq 0) { return 0 }
    $sorted = @($Values | Sort-Object)
    $count = $sorted.Count
    if (($count % 2) -eq 1) { return [double]$sorted[[int][Math]::Floor($count / 2)] }
    $a = [double]$sorted[($count / 2) - 1]
    $b = [double]$sorted[$count / 2]
    return (($a + $b) / 2.0)
}

function Load-Settings {
    $settings = Read-JsonFile (Join-Path $ConfigDir 'settings.example.json')
    if ($null -eq $settings) { throw 'config/settings.example.json is missing or invalid.' }

    $localPath = Join-Path $ConfigDir 'settings.local.json'
    $local = Read-JsonFile $localPath
    if ($null -ne $local) {
        if ($local.PSObject.Properties['travelMode']) { $settings.travelMode = [string]$local.travelMode }
        if ($local.PSObject.Properties['tornApiKey']) {
            if ($settings.PSObject.Properties['tornApiKey']) { $settings.tornApiKey = [string]$local.tornApiKey }
            else { $settings | Add-Member NoteProperty tornApiKey ([string]$local.tornApiKey) }
        }
        if ($local.PSObject.Properties['profitability'] -and $null -ne $local.profitability) {
            foreach ($name in @('sellTarget','itemMarketFeePercent','minimumProfitPerItem','minimumMarginPercent')) {
                $localProp = $local.profitability.PSObject.Properties[$name]
                if ($null -ne $localProp) {
                    $targetProp = $settings.profitability.PSObject.Properties[$name]
                    if ($null -eq $targetProp) { $settings.profitability | Add-Member NoteProperty $name $localProp.Value }
                    else { $targetProp.Value = $localProp.Value }
                }
            }
        }
    }
    return $settings
}

function Get-TravelMode {
    param([object]$Settings, [object]$TravelModes)
    $mode = [string]$Settings.travelMode
    $prefs = Read-JsonFile $PreferenceFile
    if ($null -ne $prefs -and $prefs.PSObject.Properties['travelMode']) { $mode = [string]$prefs.travelMode }
    $valid = @($TravelModes.modes | Where-Object { $_.enabled -eq $true } | ForEach-Object { [string]$_.id })
    if ($valid -notcontains $mode) { $mode = [string]$TravelModes.defaultMode }
    return $mode
}

function Cycle-TravelMode {
    param([string]$CurrentMode, [object]$TravelModes)
    $enabled = @($TravelModes.modes | Where-Object { $_.enabled -eq $true })
    if ($enabled.Count -eq 0) { return $CurrentMode }
    $index = 0
    for ($i = 0; $i -lt $enabled.Count; $i++) {
        if ([string]$enabled[$i].id -eq $CurrentMode) { $index = $i; break }
    }
    $next = [string]$enabled[(($index + 1) % $enabled.Count)].id
    Write-JsonAtomic -Path $PreferenceFile -Value ([pscustomobject]@{ schemaVersion = 1; travelMode = $next })
    return $next
}

function Get-EngineState {
    $state = Read-JsonFile $EngineStateFile
    if ($null -eq $state) {
        $state = [pscustomobject]@{
            schemaVersion = 1
            lastPruneAt = 0
            destinations = [pscustomobject]@{}
            resaleCache = [pscustomobject]@{}
        }
    }
    if (-not $state.PSObject.Properties['destinations']) { $state | Add-Member NoteProperty destinations ([pscustomobject]@{}) }
    if (-not $state.PSObject.Properties['resaleCache']) { $state | Add-Member NoteProperty resaleCache ([pscustomobject]@{}) }
    if (-not $state.PSObject.Properties['lastPruneAt']) { $state | Add-Member NoteProperty lastPruneAt 0 }
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

function Get-YataPayload {
    $uri = 'https://yata.yt/api/v1/travel/export/'
    return Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Accept = 'application/json' } -TimeoutSec 15
}

function Get-YataObservation {
    param([object]$Payload, [object]$Country, [object]$Item, [long]$Now)
    if ($null -eq $Payload -or $null -eq $Payload.stocks) { return $null }
    $code = [string]$Country.providerCodes.yata
    $countryObj = Get-DynamicProperty $Payload.stocks $code
    if ($null -eq $countryObj) { return $null }
    $row = @($countryObj.stocks | Where-Object { [int]$_.id -eq [int]$Item.itemId } | Select-Object -First 1)
    if ($row.Count -eq 0) { return $null }
    $row = $row[0]
    $sourceTimestamp = 0
    if ($countryObj.PSObject.Properties['update']) { $sourceTimestamp = [long]$countryObj.update }
    $timestamp = $sourceTimestamp
    if ($timestamp -le 0) { $timestamp = $Now }
    return [pscustomobject]@{
        schemaVersion = 1
        timestamp = $timestamp
        country = [string]$Country.id
        itemId = [int]$Item.itemId
        stock = [int]$row.quantity
        foreignPrice = [long]$row.cost
        source = 'yata'
        sourceTimestamp = $sourceTimestamp
    }
}

function Get-TornResalePrice {
    param([object]$Settings, [object]$EngineState, [int]$ItemId, [long]$Now)
    $cacheKey = [string]$ItemId
    $cached = Get-DynamicProperty $EngineState.resaleCache $cacheKey
    if ($null -ne $cached -and ([long]$cached.fetchedAt + 300) -gt $Now -and [long]$cached.price -gt 0) {
        return $cached
    }

    $apiKey = $null
    if ($Settings.PSObject.Properties['tornApiKey'] -and -not [string]::IsNullOrWhiteSpace([string]$Settings.tornApiKey)) {
        $apiKey = [string]$Settings.tornApiKey
    } elseif (-not [string]::IsNullOrWhiteSpace($env:TORN_API_KEY)) {
        $apiKey = [string]$env:TORN_API_KEY
    }
    if ([string]::IsNullOrWhiteSpace($apiKey)) { return $cached }

    try {
        $uri = "https://api.torn.com/v2/market/$ItemId/itemmarket?limit=1"
        $payload = Invoke-RestMethod -Method Get -Uri $uri -Headers @{ Accept = 'application/json'; Authorization = "ApiKey $apiKey" } -TimeoutSec 15
        $average = 0
        $lowest = 0
        if ($payload.itemmarket -and $payload.itemmarket.item -and $payload.itemmarket.item.PSObject.Properties['average_price']) {
            $average = [long]$payload.itemmarket.item.average_price
        }
        if ($payload.itemmarket -and $payload.itemmarket.listings -and @($payload.itemmarket.listings).Count -gt 0) {
            $candidate = $payload.itemmarket.listings[0]
            if ($candidate.PSObject.Properties['price']) { $lowest = [long]$candidate.price }
        }
        $price = $lowest
        if ($price -le 0) { $price = $average }
        if ($price -gt 0) {
            $result = [pscustomobject]@{ price = $price; lowest = $lowest; average = $average; fetchedAt = $Now; source = 'torn_itemmarket' }
            Set-DynamicProperty $EngineState.resaleCache $cacheKey $result
            return $result
        }
    } catch {
        return $cached
    }
    return $cached
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
                $delay = 0
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
                    restockDelaySeconds = [long]$delay
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

function Load-Cycles {
    param([string]$Country, [int]$ItemId, [long]$Cutoff)
    if (-not (Test-Path -LiteralPath $CycleFile)) { return @() }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($line in Get-Content -LiteralPath $CycleFile) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $row = $line | ConvertFrom-Json
            if ([string]$row.country -eq $Country -and [int]$row.itemId -eq $ItemId -and [long]$row.soldOutAt -ge $Cutoff) { $rows.Add($row) }
        } catch { }
    }
    return @($rows)
}

function Get-LiveStockoutEstimate {
    param([object[]]$Rows, [long]$RestockAt)
    if ($RestockAt -le 0 -or $null -eq $Rows) { return 0 }
    $positive = @($Rows | Where-Object { [long]$_.timestamp -ge $RestockAt -and [int]$_.stock -gt 0 } | Sort-Object timestamp)
    if ($positive.Count -lt 3) { return 0 }
    $first = $positive[0]
    $last = $positive[$positive.Count - 1]
    $elapsed = [long]$last.timestamp - [long]$first.timestamp
    $drop = [double]$first.stock - [double]$last.stock
    if ($elapsed -lt 120 -or $drop -le 0) { return 0 }
    $rate = $drop / [double]$elapsed
    if ($rate -le 0) { return 0 }
    $remaining = [long][Math]::Round([double]$last.stock / $rate)
    if ($remaining -lt 0) { return 0 }
    return ([long]$last.timestamp + $remaining)
}

function Get-Recommendation {
    param(
        [object]$Settings,
        [object]$Country,
        [object]$Observation,
        [object]$DestState,
        [long]$ResalePrice,
        [string]$TravelMode,
        [long]$Now,
        [object[]]$RecentObservations
    )

    $result = [ordered]@{
        Status = 'INSUFFICIENT_HISTORY'
        Message = 'Learning — no departure recommendation'
        RestockEstimateAt = 0
        WindowOpenAt = 0
        WindowCloseAt = 0
        BestDepartureAt = 0
        HitRate = 0.0
    }

    $sourceTs = [long]$Observation.sourceTimestamp
    if ($sourceTs -gt 0 -and ($Now - $sourceTs) -gt [long]$Settings.staleAfterSeconds) {
        $result.Status = 'STALE_DATA'
        $result.Message = 'Stock source is stale — check Weav3r'
        return [pscustomobject]$result
    }

    if ($ResalePrice -le 0) {
        $result.Status = 'CHECK_EXTERNAL'
        $result.Message = 'Add a local Torn API key to enable profitability gating'
        return [pscustomobject]$result
    }

    $feePercent = 5.0
    if ($Settings.profitability.PSObject.Properties['itemMarketFeePercent']) { $feePercent = [double]$Settings.profitability.itemMarketFeePercent }
    if ($feePercent -lt 0) { $feePercent = 0 }
    if ($feePercent -gt 100) { $feePercent = 100 }
    $netResalePrice = [long][Math]::Floor($ResalePrice * (1.0 - ($feePercent / 100.0)))
    $profit = $netResalePrice - [long]$Observation.foreignPrice
    $margin = 0.0
    if ([long]$Observation.foreignPrice -gt 0) { $margin = (100.0 * $profit / [double]$Observation.foreignPrice) }
    if ($profit -lt 0) {
        $result.Status = 'UNPROFITABLE'
        $result.Message = ('Net resale after {0:N1}% fee is below foreign price' -f $feePercent)
        return [pscustomobject]$result
    }
    if ($profit -lt [double]$Settings.profitability.minimumProfitPerItem -or $margin -lt [double]$Settings.profitability.minimumMarginPercent) {
        $result.Status = 'LOW_MARGIN'
        $result.Message = ('Net margin too low: ${0:N0}/ea · {1:N1}%' -f $profit, $margin)
        return [pscustomobject]$result
    }

    $cutoff = $Now - ([long]$Settings.cycleRetentionDays * 86400)
    $cycles = @(Load-Cycles -Country ([string]$Observation.country) -ItemId ([int]$Observation.itemId) -Cutoff $cutoff | Where-Object {
        [long]$_.availabilitySeconds -gt 0 -and [long]$_.restockDelaySeconds -gt 0
    })
    $minComparable = [int]$Settings.recommendation.minimumComparableCycles
    if ($cycles.Count -lt $minComparable) { return [pscustomobject]$result }

    $price = [double]$Observation.foreignPrice
    $band = [Math]::Max(50000.0, $price * 0.08)
    $similar = @($cycles | Where-Object { [Math]::Abs([double]$_.foreignPrice - $price) -le $band })
    if ($similar.Count -lt $minComparable) {
        $result.Status = 'PRICE_REGIME_UNVERIFIED'
        $result.Message = 'Current foreign price is outside well-trained history'
        return [pscustomobject]$result
    }

    $travelSeconds = [long](Get-DynamicProperty $Country.travelSeconds $TravelMode)
    if ($travelSeconds -le 0) { return [pscustomobject]$result }
    $buffer = [long]$Settings.recommendation.arrivalBufferSeconds

    # If a restock is currently live, exact restock timing is known. In this state,
    # current depletion can only shorten a historical safe window; it never extends one.
    if ([int]$Observation.stock -gt 0 -and $null -ne $DestState.activeCycle) {
        $activeRestockAt = [long]$DestState.activeCycle.restockAt
        if ($activeRestockAt -gt 0) {
            $result.RestockEstimateAt = $activeRestockAt
            $availabilityValues = [double[]]@($similar | ForEach-Object { [double]$_.availabilitySeconds })
            $earliestAvailability = [long](($availabilityValues | Measure-Object -Minimum).Minimum)
            $safeCloseAt = $activeRestockAt + $earliestAvailability - $travelSeconds - $buffer
            $liveStockoutAt = Get-LiveStockoutEstimate -Rows $RecentObservations -RestockAt $activeRestockAt
            if ($liveStockoutAt -gt 0) {
                $liveCloseAt = $liveStockoutAt - $travelSeconds - $buffer
                if ($liveCloseAt -lt $safeCloseAt) { $safeCloseAt = $liveCloseAt }
            }

            if ($similar.Count -ge [int]$Settings.recommendation.minimumSafeCycles -and $safeCloseAt -ge ($Now - 60)) {
                $result.Status = 'SAFE_WINDOW'
                $result.Message = 'Stock is live; conservative availability still covers arrival'
                $result.WindowOpenAt = $Now - 1
                $result.WindowCloseAt = $safeCloseAt
                return [pscustomobject]$result
            }

            $arrivalOffset = ($Now - $activeRestockAt) + $travelSeconds
            $hits = 0
            foreach ($c in $similar) {
                if ($arrivalOffset -ge 0 -and $arrivalOffset -le [long]$c.availabilitySeconds) { $hits++ }
            }
            $hitRate = $hits / [double]$similar.Count
            if ($liveStockoutAt -gt 0 -and ($Now + $travelSeconds) -gt $liveStockoutAt) { $hitRate = 0.0 }
            if ($hitRate -gt 0) {
                $result.Status = 'BEST_ODDS'
                $result.Message = 'Stock is live; leaving now has the strongest remaining modeled chance'
                $result.BestDepartureAt = $Now
                $result.HitRate = $hitRate
                return [pscustomobject]$result
            }

            $result.Status = 'WINDOW_CLOSED'
            $result.Message = 'Current live stock is unlikely to survive until arrival'
            return [pscustomobject]$result
        }
    }

    $lastSellOut = [long]$DestState.lastSellOutAt
    if ($lastSellOut -le 0) { return [pscustomobject]$result }

    $restockDelays = [double[]]@($similar | ForEach-Object { [double]$_.restockDelaySeconds })
    $medianRestock = [long][Math]::Round((Get-Median $restockDelays))
    $result.RestockEstimateAt = $lastSellOut + $medianRestock

    $lowers = New-Object System.Collections.Generic.List[double]
    $uppers = New-Object System.Collections.Generic.List[double]
    foreach ($c in $similar) {
        $restock = [double]$c.restockDelaySeconds
        $stockout = $restock + [double]$c.availabilitySeconds
        $lowers.Add($restock - $travelSeconds + $buffer)
        $uppers.Add($stockout - $travelSeconds - $buffer)
    }

    if ($similar.Count -ge [int]$Settings.recommendation.minimumSafeCycles) {
        $safeLower = [double](($lowers | Measure-Object -Maximum).Maximum)
        $safeUpper = [double](($uppers | Measure-Object -Minimum).Minimum)
        if ($safeUpper -ge $safeLower) {
            $openAt = $lastSellOut + [long][Math]::Round($safeLower)
            $closeAt = $lastSellOut + [long][Math]::Round($safeUpper)
            if ($closeAt -ge ($Now - 60)) {
                $result.Status = 'SAFE_WINDOW'
                $result.Message = 'Conservative historical overlap'
                $result.WindowOpenAt = $openAt
                $result.WindowCloseAt = $closeAt
                return [pscustomobject]$result
            }
        }
    }

    $candidateStart = [long][Math]::Max(0, [Math]::Floor((($lowers | Measure-Object -Minimum).Minimum) - $buffer))
    $candidateEnd = [long][Math]::Max($candidateStart, [Math]::Ceiling((($uppers | Measure-Object -Maximum).Maximum) + $buffer))
    $step = [long]$Settings.recommendation.candidateStepSeconds
    if ($step -lt 10) { $step = 10 }
    $bestOffset = -1
    $bestHits = -1
    for ($candidate = $candidateStart; $candidate -le $candidateEnd; $candidate += $step) {
        $arrival = $candidate + $travelSeconds
        $hits = 0
        foreach ($c in $similar) {
            $restock = [long]$c.restockDelaySeconds
            $stockout = $restock + [long]$c.availabilitySeconds
            if ($arrival -ge $restock -and $arrival -le $stockout) { $hits++ }
        }
        if ($hits -gt $bestHits) {
            $bestHits = $hits
            $bestOffset = $candidate
        }
    }

    if ($bestOffset -ge 0 -and $bestHits -gt 0) {
        $bestAt = $lastSellOut + $bestOffset
        if ($bestAt -ge ($Now - 60)) {
            $result.Status = 'BEST_ODDS'
            $result.Message = 'No conservative overlap; using the strongest historical departure point'
            $result.BestDepartureAt = $bestAt
            $result.HitRate = $bestHits / [double]$similar.Count
            return [pscustomobject]$result
        }
    }

    $result.Status = 'WINDOW_CLOSED'
    $result.Message = 'Current modeled departure opportunity has passed'
    return [pscustomobject]$result
}

function Prune-RuntimeData {
    param([object]$Settings, [object]$EngineState, [long]$Now)
    if (($Now - [long]$EngineState.lastPruneAt) -lt 3600) { return }

    if (Test-Path -LiteralPath $ObservationFile) {
        $cutoff = $Now - ([long]$Settings.highResolutionRetentionHours * 3600)
        $tmp = $ObservationFile + '.tmp'
        $writer = New-Object System.IO.StreamWriter($tmp, $false, [System.Text.Encoding]::UTF8)
        try {
            foreach ($line in Get-Content -LiteralPath $ObservationFile) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                try {
                    $row = $line | ConvertFrom-Json
                    if ([long]$row.timestamp -ge $cutoff) { $writer.WriteLine($line) }
                } catch { }
            }
        } finally { $writer.Dispose() }
        Move-Item -LiteralPath $tmp -Destination $ObservationFile -Force
    }

    if (Test-Path -LiteralPath $CycleFile) {
        $cutoff = $Now - ([long]$Settings.cycleRetentionDays * 86400)
        $tmp = $CycleFile + '.tmp'
        $writer = New-Object System.IO.StreamWriter($tmp, $false, [System.Text.Encoding]::UTF8)
        try {
            foreach ($line in Get-Content -LiteralPath $CycleFile) {
                if ([string]::IsNullOrWhiteSpace($line)) { continue }
                try {
                    $row = $line | ConvertFrom-Json
                    if ([long]$row.soldOutAt -ge $cutoff) { $writer.WriteLine($line) }
                } catch { }
            }
        } finally { $writer.Dispose() }
        Move-Item -LiteralPath $tmp -Destination $CycleFile -Force
    }

    $EngineState.lastPruneAt = $Now
}

function Get-RecentObservations {
    param([string]$Country, [int]$ItemId, [long]$Cutoff)
    if (-not (Test-Path -LiteralPath $ObservationFile)) { return @() }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($line in Get-Content -LiteralPath $ObservationFile) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try {
            $row = $line | ConvertFrom-Json
            if ([string]$row.country -eq $Country -and [int]$row.itemId -eq $ItemId -and [long]$row.timestamp -ge $Cutoff) { $rows.Add($row) }
        } catch { }
    }
    return @($rows | Sort-Object timestamp)
}

function Write-StockGraph {
    param([object[]]$Rows, [string]$Path, [long]$Now, [int]$WindowHours = 24)
    Add-Type -AssemblyName System.Drawing
    $width = 520
    $height = 118
    $padX = 8
    $padY = 8
    $bitmap = New-Object System.Drawing.Bitmap($width, $height)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $g.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    $g.Clear([System.Drawing.Color]::FromArgb(24, 27, 31))
    $gridPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(48, 53, 60), 1)
    for ($i = 1; $i -le 3; $i++) {
        $y = [single]($padY + (($height - 2 * $padY) * $i / 4.0))
        $g.DrawLine($gridPen, $padX, $y, $width - $padX, $y)
    }

    if ($Rows.Count -gt 0) {
        $windowStart = $Now - ($WindowHours * 3600)
        $maxStock = [double](($Rows | Measure-Object stock -Maximum).Maximum)
        if ($maxStock -lt 1) { $maxStock = 1 }
        $linePen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(82, 174, 255), 2)
        $restockPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(86, 190, 116), 1)
        $selloutPen = New-Object System.Drawing.Pen([System.Drawing.Color]::FromArgb(224, 90, 90), 1)
        $plotW = $width - 2 * $padX
        $plotH = $height - 2 * $padY
        $prev = $null
        foreach ($row in $Rows) {
            $x = [single]($padX + (($row.timestamp - $windowStart) / [double]($WindowHours * 3600)) * $plotW)
            if ($x -lt $padX) { $x = $padX }
            if ($x -gt ($width - $padX)) { $x = $width - $padX }
            $y = [single]($padY + $plotH - (([double]$row.stock / $maxStock) * $plotH))
            if ($null -ne $prev) {
                $px = [single]$prev.x
                $py = [single]$prev.y
                $g.DrawLine($linePen, $px, $py, $x, $py)
                $g.DrawLine($linePen, $x, $py, $x, $y)
                if ([int]$prev.stock -eq 0 -and [int]$row.stock -gt 0) { $g.DrawLine($restockPen, $x, $padY, $x, $height - $padY) }
                if ([int]$prev.stock -gt 0 -and [int]$row.stock -eq 0) { $g.DrawLine($selloutPen, $x, $padY, $x, $height - $padY) }
            }
            $prev = [pscustomobject]@{ x = $x; y = $y; stock = [int]$row.stock }
        }
        $linePen.Dispose(); $restockPen.Dispose(); $selloutPen.Dispose()
    }

    $gridPen.Dispose()
    $g.Dispose()
    $tmp = $Path + '.tmp.png'
    $bitmap.Save($tmp, [System.Drawing.Imaging.ImageFormat]::Png)
    $bitmap.Dispose()
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Write-StateKv {
    param([hashtable]$Values)
    $tmp = $StateKvFile + '.tmp'
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in ($Values.Keys | Sort-Object)) {
        $value = [string]$Values[$key]
        $value = $value.Replace("`r", ' ').Replace("`n", ' ')
        $lines.Add("$key=$value")
    }
    $lines | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $StateKvFile -Force
}

$settings = Load-Settings
$itemsConfig = Read-JsonFile (Join-Path $ConfigDir 'items.json')
$countriesConfig = Read-JsonFile (Join-Path $ConfigDir 'countries.json')
$travelModes = Read-JsonFile (Join-Path $ConfigDir 'travel-modes.json')
if ($null -eq $itemsConfig -or $null -eq $countriesConfig -or $null -eq $travelModes) { throw 'Required Travel Assistant configuration is missing.' }

$travelMode = Get-TravelMode -Settings $settings -TravelModes $travelModes
if ($Action -eq 'CycleTravelMode') { $travelMode = Cycle-TravelMode -CurrentMode $travelMode -TravelModes $travelModes }
$modeRow = @($travelModes.modes | Where-Object { [string]$_.id -eq $travelMode } | Select-Object -First 1)
$modeLabel = if ($modeRow.Count -gt 0) { [string]$modeRow[0].label } else { $travelMode }

$now = Get-NowEpoch
$engineState = Get-EngineState
$stateValues = @{
    TravelMode = $travelMode
    TravelModeLabel = $modeLabel
    UpdatedText = 'YATA live stock · 60s polling'
}

$yataPayload = $null
$yataError = $null
try { $yataPayload = Get-YataPayload } catch { $yataError = $_.Exception.Message }

$enabledItem = @($itemsConfig.items | Where-Object { $_.enabled -eq $true } | Select-Object -First 1)
if ($enabledItem.Count -eq 0) { throw 'No enabled item is configured.' }
$item = $enabledItem[0]
$resale = Get-TornResalePrice -Settings $settings -EngineState $engineState -ItemId ([int]$item.itemId) -Now $now
$resalePrice = 0
if ($null -ne $resale -and $resale.PSObject.Properties['price']) { $resalePrice = [long]$resale.price }

foreach ($country in @($countriesConfig.countries | Where-Object { $_.enabled -eq $true })) {
    $prefix = if ([string]$country.id -eq 'united_kingdom') { 'UK' } elseif ([string]$country.id -eq 'japan') { 'JP' } else { ([string]$country.id).ToUpperInvariant() }
    $travelSeconds = [long](Get-DynamicProperty $country.travelSeconds $travelMode)
    $stateValues[$prefix + 'TravelSeconds'] = $travelSeconds
    $stateValues[$prefix + 'Stock'] = 0
    $stateValues[$prefix + 'ForeignPrice'] = 0
    $stateValues[$prefix + 'LastSoldOutAt'] = 0
    $stateValues[$prefix + 'RestockEstimateAt'] = 0
    $stateValues[$prefix + 'WindowOpenAt'] = 0
    $stateValues[$prefix + 'WindowCloseAt'] = 0
    $stateValues[$prefix + 'BestDepartureAt'] = 0
    $stateValues[$prefix + 'HitRate'] = 0
    $stateValues[$prefix + 'Status'] = 'STALE_DATA'
    $stateValues[$prefix + 'Message'] = 'Unable to read live stock source'

    $destKey = ([string]$country.id) + ':' + ([string]$item.itemId)
    $destState = Get-DestinationState -EngineState $engineState -Key $destKey
    $cachedStock = [int]$destState.lastStock
    if ($cachedStock -lt 0) { $cachedStock = 0 }
    $stateValues[$prefix + 'Stock'] = $cachedStock
    $stateValues[$prefix + 'ForeignPrice'] = [long]$destState.lastForeignPrice
    $stateValues[$prefix + 'LastSoldOutAt'] = [long]$destState.lastSellOutAt

    if ($null -eq $yataPayload) { continue }
    $observation = Get-YataObservation -Payload $yataPayload -Country $country -Item $item -Now $now
    if ($null -eq $observation) {
        $stateValues[$prefix + 'Status'] = 'SOURCE_DISAGREEMENT'
        $stateValues[$prefix + 'Message'] = 'Xanax row missing from live stock export; showing cached values'
        continue
    }

    $stateValues[$prefix + 'Stock'] = [int]$observation.stock
    $stateValues[$prefix + 'ForeignPrice'] = [long]$observation.foreignPrice

    $sameSource = ([long]$destState.lastSourceTimestamp -eq [long]$observation.sourceTimestamp -and [long]$observation.sourceTimestamp -gt 0)
    $sameValues = ([int]$destState.lastStock -eq [int]$observation.stock -and [long]$destState.lastForeignPrice -eq [long]$observation.foreignPrice)
    if (-not ($sameSource -and $sameValues)) {
        Append-JsonLine -Path $ObservationFile -Value $observation
        $completed = Update-CycleState -DestState $destState -Observation $observation
        if ($null -ne $completed -and [long]$completed.availabilitySeconds -gt 0) { Append-JsonLine -Path $CycleFile -Value $completed }
    }

    $stateValues[$prefix + 'LastSoldOutAt'] = [long]$destState.lastSellOutAt
    $graphCutoff = $now - ([long]$settings.graphWindowHours * 3600)
    $graphRows = @(Get-RecentObservations -Country ([string]$country.id) -ItemId ([int]$item.itemId) -Cutoff $graphCutoff)

    $rec = Get-Recommendation -Settings $settings -Country $country -Observation $observation -DestState $destState -ResalePrice $resalePrice -TravelMode $travelMode -Now $now -RecentObservations $graphRows
    $stateValues[$prefix + 'Status'] = [string]$rec.Status
    $stateValues[$prefix + 'Message'] = [string]$rec.Message
    $stateValues[$prefix + 'RestockEstimateAt'] = [long]$rec.RestockEstimateAt
    $stateValues[$prefix + 'WindowOpenAt'] = [long]$rec.WindowOpenAt
    $stateValues[$prefix + 'WindowCloseAt'] = [long]$rec.WindowCloseAt
    $stateValues[$prefix + 'BestDepartureAt'] = [long]$rec.BestDepartureAt
    $stateValues[$prefix + 'HitRate'] = [double]$rec.HitRate

    $graphPath = Join-Path $GeneratedDir (($prefix.ToLowerInvariant()) + '-stock.png')
    try { Write-StockGraph -Rows $graphRows -Path $graphPath -Now $now -WindowHours ([int]$settings.graphWindowHours) } catch { }
}

if ($null -ne $yataError) { $stateValues.UpdatedText = 'Live stock request failed; showing cached/local state where available' }
Prune-RuntimeData -Settings $settings -EngineState $engineState -Now $now
Write-JsonAtomic -Path $EngineStateFile -Value $engineState
Write-StateKv -Values $stateValues
