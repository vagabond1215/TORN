$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ScriptPath = Join-Path $ProjectRoot '@Resources\Scripts\ItemMetadata.ps1'

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
$ast = [System.Management.Automation.Language.Parser]::ParseFile($ScriptPath, [ref]$tokens, [ref]$parseErrors)
if (@($parseErrors).Count -gt 0) {
    throw ('ItemMetadata.ps1 has parser errors: ' + ((@($parseErrors) | ForEach-Object { $_.Message }) -join '; '))
}

$wanted = @('Get-DynamicProperty','Set-DynamicProperty','Get-ObservedItemIds','Import-ConfiguredMetadataSeeds','Get-CanonicalCategory','Convert-TornBulkItemMetadata')
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

$state = [pscustomobject]@{
    observedMarkets = [pscustomobject]@{
        'united_kingdom:266' = [pscustomobject]@{ country = 'united_kingdom'; itemId = 266 }
        'japan:277' = [pscustomobject]@{ country = 'japan'; itemId = 277 }
        'japan:206' = [pscustomobject]@{ country = 'japan'; itemId = 206 }
        'south_africa:206' = [pscustomobject]@{ country = 'south_africa'; itemId = 206 }
    }
    itemMetadata = [pscustomobject]@{}
}
$ids = @(Get-ObservedItemIds -EngineState $state)
Assert-Equal 'Observed item IDs are distinct' $ids.Count 3
Assert-Equal 'Observed IDs sort ascending first' $ids[0] 206
Assert-Equal 'Observed IDs include Nessie' $ids[1] 266
Assert-Equal 'Observed IDs include Cherry Blossom' $ids[2] 277

$seedConfig = [pscustomobject]@{
    items = @(
        [pscustomobject]@{ itemId = 206; name = 'Xanax'; category = 'Drug' },
        [pscustomobject]@{ itemId = 266; name = 'Nessie Plushie'; category = 'Plushie' },
        [pscustomobject]@{ itemId = 277; name = 'Cherry Blossom'; category = 'Flower' }
    )
}
$seeded = Import-ConfiguredMetadataSeeds -EngineState $state -ItemsConfig $seedConfig -Now 1787344000
Assert-Equal 'Committed metadata seeds populate three entries' $seeded 3
Assert-Equal 'Seed Xanax category' $state.itemMetadata.'206'.category 'Drug'
Assert-Equal 'Seed Nessie category' $state.itemMetadata.'266'.category 'Plushie'
Assert-Equal 'Seed Cherry category' $state.itemMetadata.'277'.category 'Flower'
Assert-Equal 'Seed provenance is explicit' $state.itemMetadata.'266'.source 'config_seed'
Assert-Equal 'Seed market value remains unknown' ([long]$state.itemMetadata.'277'.marketPrice) 0
Assert-Equal 'Seed tradability remains unknown' ([bool]$state.itemMetadata.'206'.tradabilityKnown) $false

$xanax = [pscustomobject]@{
    name = 'Xanax'
    type = 'Drug'
    weapon_type = $null
    market_value = 841051
    tradeable = $true
}
$xanaxMeta = Convert-TornBulkItemMetadata -ItemId 206 -Item $xanax -Now 1787344000
Assert-Equal 'Bulk metadata keeps item ID' $xanaxMeta.itemId 206
Assert-Equal 'Bulk metadata keeps item name' $xanaxMeta.name 'Xanax'
Assert-Equal 'Bulk metadata uses Torn type as category' $xanaxMeta.category 'Drug'
Assert-True 'Bulk metadata resolves non-empty category' ([bool]$xanaxMeta.categoryResolved)
Assert-Equal 'Bulk metadata keeps market reference' ([long]$xanaxMeta.marketPrice) 841051
Assert-True 'Bulk metadata detects tradability field' ([bool]$xanaxMeta.tradabilityKnown)
Assert-True 'Bulk metadata keeps tradable status' ([bool]$xanaxMeta.isTradable)
Assert-Equal 'Bulk metadata retains source provenance' $xanaxMeta.source 'torn_items_bulk'

$weapon = [pscustomobject]@{
    name = 'Fixture Rifle'
    type = 'Primary'
    weapon_type = 'Rifle'
    market_value = 1000000
    tradable = $true
}
$weaponMeta = Convert-TornBulkItemMetadata -ItemId 999 -Item $weapon -Now 1787344000
Assert-Equal 'Bulk weapon category stays Primary' $weaponMeta.category 'Primary'
Assert-Equal 'Bulk weapon type detail is retained' $weaponMeta.weaponType 'Rifle'
Assert-True 'Bulk weapon category resolves directly' ([bool]$weaponMeta.categoryResolved)

$unknown = [pscustomobject]@{
    name = 'Fixture Unknown'
    type = ''
    weapon_type = $null
    market_value = 1
}
$unknownMeta = Convert-TornBulkItemMetadata -ItemId 1000 -Item $unknown -Now 1787344000
Assert-Equal 'Missing type stays Unknown' $unknownMeta.category 'Unknown'
Assert-Equal 'Missing type is marked unresolved' ([bool]$unknownMeta.categoryResolved) $false
Assert-Equal 'Missing tradability stays unknown' ([bool]$unknownMeta.tradabilityKnown) $false

Write-Host 'Item metadata fallback/normalization tests passed.' -ForegroundColor Green
exit 0
