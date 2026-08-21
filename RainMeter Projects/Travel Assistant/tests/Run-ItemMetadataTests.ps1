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

$wanted = @('Get-DynamicProperty','Get-ObservedItemIds','Split-ItemIds','Get-CanonicalCategory','Convert-TornItemMetadata')
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
}
$ids = @(Get-ObservedItemIds -EngineState $state)
Assert-Equal 'Observed item IDs are distinct' $ids.Count 3
Assert-Equal 'Observed IDs sort ascending first' $ids[0] 206
Assert-Equal 'Observed IDs include Nessie' $ids[1] 266
Assert-Equal 'Observed IDs include Cherry Blossom' $ids[2] 277

$chunks = @(Split-ItemIds -ItemIds ([int[]](1..305)) -Maximum 150)
Assert-Equal 'Metadata requests are bounded into three chunks' $chunks.Count 3
Assert-Equal 'First metadata chunk size' @($chunks[0]).Count 150
Assert-Equal 'Second metadata chunk size' @($chunks[1]).Count 150
Assert-Equal 'Final metadata chunk size' @($chunks[2]).Count 5

$flower = [pscustomobject]@{
    id = 277
    name = 'Cherry Blossom'
    type = 'Flower'
    sub_type = $null
    is_tradable = $true
    value = [pscustomobject]@{
        market_price = 85000
        shops = @(
            [pscustomobject]@{ country = 'Japan'; shop = 'Bits n Bob'; buy_price = 500; sell_price = 250 }
        )
    }
    details = $null
}
$flowerMeta = Convert-TornItemMetadata -Item $flower -Now 1787342000
Assert-Equal 'Flower canonical category' $flowerMeta.category 'Flower'
Assert-True 'Flower category resolves directly' ([bool]$flowerMeta.categoryResolved)
Assert-Equal 'Flower metadata keeps item name' $flowerMeta.name 'Cherry Blossom'
Assert-Equal 'Flower metadata keeps market reference' ([long]$flowerMeta.marketPrice) 85000
Assert-Equal 'Flower metadata keeps shop country' $flowerMeta.shops[0].country 'Japan'

$weapon = [pscustomobject]@{
    id = 999
    name = 'Fixture Rifle'
    type = 'Weapon'
    sub_type = 'Rifle'
    is_tradable = $true
    value = [pscustomobject]@{ market_price = 1000000; shops = @() }
    details = [pscustomobject]@{ category = 'Primary' }
}
$weaponMeta = Convert-TornItemMetadata -Item $weapon -Now 1787342000
Assert-Equal 'Weapon uses detailed canonical category' $weaponMeta.category 'Primary'
Assert-True 'Detailed weapon category is resolved' ([bool]$weaponMeta.categoryResolved)
Assert-Equal 'Weapon retains broad Torn type' $weaponMeta.type 'Weapon'
Assert-Equal 'Weapon retains Torn subtype' $weaponMeta.subType 'Rifle'

$unknownWeapon = [pscustomobject]@{
    id = 1000
    name = 'Fixture Weapon'
    type = 'Weapon'
    sub_type = $null
    is_tradable = $true
    value = [pscustomobject]@{ market_price = 1; shops = @() }
    details = $null
}
$unknownMeta = Convert-TornItemMetadata -Item $unknownWeapon -Now 1787342000
Assert-Equal 'Unresolved weapon stays broad instead of guessing' $unknownMeta.category 'Weapon'
Assert-Equal 'Unresolved weapon category is marked unresolved' ([bool]$unknownMeta.categoryResolved) $false

Write-Host 'Item metadata normalization tests passed.' -ForegroundColor Green
exit 0
