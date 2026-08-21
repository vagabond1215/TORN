$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$ScriptPath = Join-Path $ProjectRoot '@Resources\Scripts\LocalCatalog.ps1'

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
if (@($parseErrors).Count -gt 0) { throw ('LocalCatalog.ps1 has parser errors: ' + ((@($parseErrors) | ForEach-Object { $_.Message }) -join '; ')) }

$wanted = @('Get-DynamicProperty','Set-DynamicProperty','Get-ObservedItemGroups','Get-SeedIndex','New-LocalCatalogEntry','Get-LocalCatalogSignature','Merge-RicherMetadata')
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

$observed = [pscustomobject]@{
    'united_kingdom:266' = [pscustomobject]@{ country='united_kingdom'; itemId=266; providerName='Nessie Plushie' }
    'japan:277' = [pscustomobject]@{ country='japan'; itemId=277; providerName='Cherry Blossom' }
    'japan:206' = [pscustomobject]@{ country='japan'; itemId=206; providerName='Xanax' }
    'united_kingdom:206' = [pscustomobject]@{ country='united_kingdom'; itemId=206; providerName='Xanax' }
    'mexico:999' = [pscustomobject]@{ country='mexico'; itemId=999; providerName='Fixture Item' }
    'canada:999' = [pscustomobject]@{ country='canada'; itemId=999; providerName='Fixture Item Renamed' }
}
$groups = @(Get-ObservedItemGroups -ObservedMarkets $observed)
Assert-Equal 'Observed market rows collapse to distinct items' $groups.Count 4
$xanaxGroup = @($groups | Where-Object { $_.itemId -eq 206 })[0]
Assert-Equal 'Xanax group keeps one provider name' @($xanaxGroup.providerNames).Count 1
Assert-Equal 'Xanax group keeps both countries' @($xanaxGroup.countries).Count 2
$conflictGroup = @($groups | Where-Object { $_.itemId -eq 999 })[0]
Assert-Equal 'Conflicting provider names remain visible' @($conflictGroup.providerNames).Count 2

$config = [pscustomobject]@{ items = @(
    [pscustomobject]@{ itemId=206; name='Xanax'; category='Drug' },
    [pscustomobject]@{ itemId=266; name='Nessie Plushie'; category='Plushie' },
    [pscustomobject]@{ itemId=277; name='Cherry Blossom'; category='Flower' }
)}
$seedIndex = Get-SeedIndex -ItemsConfig $config
Assert-Equal 'Seed index keeps three committed items' $seedIndex.Count 3

$nessieGroup = @($groups | Where-Object { $_.itemId -eq 266 })[0]
$nessie = New-LocalCatalogEntry -Group $nessieGroup -Seed $seedIndex['266'] -Now 1787345000
Assert-Equal 'Seeded Nessie keeps canonical name' $nessie.name 'Nessie Plushie'
Assert-Equal 'Seeded Nessie resolves Plushie category' $nessie.category 'Plushie'
Assert-True 'Seeded category is resolved' ([bool]$nessie.categoryResolved)
Assert-Equal 'Seed provenance is explicit' $nessie.source 'config_seed'

$unknown = New-LocalCatalogEntry -Group $conflictGroup -Seed $null -Now 1787345000
Assert-Equal 'Unseeded observed item uses provider-name provenance' $unknown.source 'provider_name'
Assert-Equal 'Unseeded observed item category stays Unknown' $unknown.category 'Unknown'
Assert-Equal 'Unseeded category stays unresolved' ([bool]$unknown.categoryResolved) $false
Assert-True 'Provider name disagreement is surfaced' ([bool]$unknown.nameConflict)
Assert-Equal 'Provider name disagreement retains both names' @($unknown.providerNames).Count 2

$sigA = Get-LocalCatalogSignature -Groups $groups -SeedIndex $seedIndex
$sigB = Get-LocalCatalogSignature -Groups $groups -SeedIndex $seedIndex
Assert-Equal 'Local catalog signature is deterministic' $sigA $sigB
$configChanged = [pscustomobject]@{ items = @([pscustomobject]@{ itemId=206; name='Xanax'; category='Drug Revised' }) }
$sigChanged = Get-LocalCatalogSignature -Groups $groups -SeedIndex (Get-SeedIndex -ItemsConfig $configChanged)
Assert-True 'Category override changes local catalog signature' ($sigChanged -ne $sigA)

$rich = [pscustomobject]@{
    itemId = 266
    name = 'Nessie Plushie'
    category = 'Plushie'
    categoryResolved = $true
    marketPrice = 123456
    source = 'torn_items_bulk'
}
$merged = Merge-RicherMetadata -Existing $rich -LocalEntry $nessie
Assert-Equal 'Richer Torn metadata source is preserved' $merged.source 'torn_items_bulk'
Assert-Equal 'Richer Torn market reference is preserved' ([long]$merged.marketPrice) 123456
Assert-Equal 'Richer metadata still receives provider country context' @($merged.countries).Count 1

Write-Host 'Local catalog normalization tests passed.' -ForegroundColor Green
exit 0
