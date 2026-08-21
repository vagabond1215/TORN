$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$CollectorPath = Join-Path $ProjectRoot '@Resources\Scripts\ShadowCollector.ps1'

function Assert-Equal {
    param([string]$Name, $Actual, $Expected)
    if ($Actual -ne $Expected) { throw "$Name - expected '$Expected', got '$Actual'." }
    Write-Host "PASS $Name" -ForegroundColor DarkGreen
}

function Assert-True {
    param([string]$Name, [bool]$Value)
    if (-not $Value) { throw "$Name - expected true." }
    Write-Host "PASS $Name" -ForegroundColor DarkGreen
}

$tokens = $null
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($CollectorPath, [ref]$tokens, [ref]$parseErrors)
if (@($parseErrors).Count -gt 0) {
    throw ('ShadowCollector.ps1 has parser errors: ' + ((@($parseErrors) | ForEach-Object { $_.Message }) -join '; '))
}

$wanted = @('Get-DynamicProperty','Set-DynamicProperty','Get-LiveStockObservationsForCountry','Update-CycleState','Test-IsPrimaryMarket','Test-ObservationChanged','Update-ObservedMarketMetadata')
$definitions = @($ast.FindAll({
    param($node)
    $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and $wanted -contains $node.Name
}, $true))

foreach ($name in $wanted) {
    $definition = @($definitions | Where-Object { $_.Name -eq $name } | Select-Object -First 1)
    if ($definition.Count -ne 1) { throw "Could not locate production function '$name'." }
    $source = [string]$definition[0].Extent.Text
    $scoped = $source -replace ('^function\s+' + [regex]::Escape($name)), ('function script:' + $name)
    Invoke-Expression $scoped
}

$payload = [pscustomobject]@{
    stocks = [pscustomobject]@{
        uni = [pscustomobject]@{
            update = 1787327048
            stocks = @(
                [pscustomobject]@{ id = 206; name = 'Xanax'; quantity = 123; cost = 767000 },
                [pscustomobject]@{ id = 266; name = 'Nessie Plushie'; quantity = 450; cost = 200 },
                [pscustomobject]@{ id = 268; name = 'Red Fox Plushie'; quantity = 20; cost = 1000 },
                [pscustomobject]@{ id = 999; name = 'Malformed'; quantity = 1 }
            )
        }
    }
}
$country = [pscustomobject]@{
    id = 'united_kingdom'
    providerCodes = [pscustomobject]@{ prometheus = 'uni'; yata = 'uni' }
}

$rows = @(Get-LiveStockObservationsForCountry -Payload $payload -Country $country -Now 1787327100 -Source 'prometheus')
Assert-Equal 'All valid provider rows normalize' $rows.Count 3
Assert-Equal 'Shadow normalization keeps country' ([string]$rows[1].country) 'united_kingdom'
Assert-Equal 'Shadow normalization keeps item id' ([int]$rows[1].itemId) 266
Assert-Equal 'Shadow normalization keeps provider item name' ([string]$rows[1].itemName) 'Nessie Plushie'
Assert-Equal 'Shadow normalization keeps stock' ([int]$rows[1].stock) 450
Assert-Equal 'Shadow normalization keeps foreign price' ([long]$rows[1].foreignPrice) 200
Assert-Equal 'Shadow normalization keeps provider timestamp' ([long]$rows[1].sourceTimestamp) 1787327048

$catalogState = [pscustomobject]@{ observedMarkets = [pscustomobject]@{} }
Update-ObservedMarketMetadata -EngineState $catalogState -Observation $rows[1] -Now 1787327100
$catalogEntry = $catalogState.observedMarkets.PSObject.Properties['united_kingdom:266'].Value
Assert-Equal 'Observed market stores provider item name' ([string]$catalogEntry.providerName) 'Nessie Plushie'

$renamedObservation = [pscustomobject]@{
    country = 'united_kingdom'
    itemId = 266
    itemName = 'Nessie Plushie'
    stock = 400
    foreignPrice = 200
    source = 'yata'
    sourceTimestamp = 1787327200
}
Update-ObservedMarketMetadata -EngineState $catalogState -Observation $renamedObservation -Now 1787327200
Assert-Equal 'Observed market keeps provider name across refresh' ([string]$catalogEntry.providerName) 'Nessie Plushie'
Assert-Equal 'Observed market refresh still updates stock' ([int]$catalogEntry.lastStock) 400

$primaryCountries = New-Object 'System.Collections.Generic.HashSet[string]'
[void]$primaryCountries.Add('united_kingdom')
[void]$primaryCountries.Add('japan')
$primaryItems = New-Object 'System.Collections.Generic.HashSet[int]'
[void]$primaryItems.Add(206)
Assert-True 'UK Xanax is protected primary market' (Test-IsPrimaryMarket -CountryId 'united_kingdom' -ItemId 206 -PrimaryCountryIds $primaryCountries -PrimaryItemIds $primaryItems)
Assert-Equal 'UK Nessie remains shadow-collected' (Test-IsPrimaryMarket -CountryId 'united_kingdom' -ItemId 266 -PrimaryCountryIds $primaryCountries -PrimaryItemIds $primaryItems) $false
Assert-Equal 'Non-primary country Xanax remains shadow-collected' (Test-IsPrimaryMarket -CountryId 'mexico' -ItemId 206 -PrimaryCountryIds $primaryCountries -PrimaryItemIds $primaryItems) $false

$unchangedState = [pscustomobject]@{
    lastStock = 450
    lastForeignPrice = 200
    lastSourceTimestamp = 100
    lastSellOutAt = 0
    activeCycle = $null
}
$timestampOnlyRefresh = [pscustomobject]@{
    stock = 450
    foreignPrice = 200
    sourceTimestamp = 200
}
Assert-Equal 'Provider timestamp alone does not create raw history' (Test-ObservationChanged -DestState $unchangedState -Observation $timestampOnlyRefresh) $false
$stockChange = [pscustomobject]@{ stock = 449; foreignPrice = 200; sourceTimestamp = 200 }
Assert-True 'Stock change creates raw history' (Test-ObservationChanged -DestState $unchangedState -Observation $stockChange)
$priceChange = [pscustomobject]@{ stock = 450; foreignPrice = 250; sourceTimestamp = 200 }
Assert-True 'Foreign-price change creates raw history' (Test-ObservationChanged -DestState $unchangedState -Observation $priceChange)

$destState = [pscustomobject]@{
    lastStock = 0
    lastForeignPrice = 200
    lastSourceTimestamp = 100
    lastSellOutAt = 100
    activeCycle = $null
}
$restockObservation = [pscustomobject]@{
    timestamp = 200
    country = 'united_kingdom'
    itemId = 266
    stock = 450
    foreignPrice = 200
    source = 'prometheus'
    sourceTimestamp = 200
}
$null = Update-CycleState -DestState $destState -Observation $restockObservation
Assert-Equal 'Shadow cycle records restock transition' ([long]$destState.activeCycle.restockAt) 200

$soldOutObservation = [pscustomobject]@{
    timestamp = 260
    country = 'united_kingdom'
    itemId = 266
    stock = 0
    foreignPrice = 200
    source = 'prometheus'
    sourceTimestamp = 260
}
$completed = Update-CycleState -DestState $destState -Observation $soldOutObservation
Assert-Equal 'Completed cycle keeps item identity' ([int]$completed.itemId) 266
Assert-Equal 'Completed cycle keeps country identity' ([string]$completed.country) 'united_kingdom'
Assert-Equal 'Completed cycle availability is isolated' ([long]$completed.availabilitySeconds) 60
Assert-Equal 'Completed cycle restock delay is isolated' ([long]$completed.restockDelaySeconds) 100

Write-Host 'Shadow collection tests passed.' -ForegroundColor Green
exit 0
