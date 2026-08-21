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

$wanted = @('Get-DynamicProperty','Set-DynamicProperty','Get-ObservedItemGroups','Get-SeedIndex','Get-CategoryIndex','New-LocalCatalogEntry','Get-LocalCatalogSignature','Merge-RicherMetadata')
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
    'hawaii:1000' = [pscustomobject]@{ country='hawaii'; itemId=1000; providerName='Unmapped Fixture' }
}
$groups = @(Get-ObservedItemGroups -ObservedMarkets $observed)
Assert-Equal 'Observed market rows collapse to distinct items' $groups.Count 5
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

$categoryConfig = [pscustomobject]@{
    categoriesByItemId = [pscustomobject]@{
        '266' = 'OfflinePlushie'
        '999' = 'Tool'
    }
}
$categoryIndex = Get-CategoryIndex -CategoryConfig $categoryConfig
Assert-Equal 'Offline category index keeps mapped items' $categoryIndex.Count 2
Assert-Equal 'Offline category index keeps fixture category' $categoryIndex['999'] 'Tool'

$nessieGroup = @($groups | Where-Object { $_.itemId -eq 266 })[0]
$nessie = New-LocalCatalogEntry -Group $nessieGroup -Seed $seedIndex['266'] -OfflineCategory $categoryIndex['266'] -OfflineCategorySource 'yata_abroad_snapshot' -Now 1787345000
Assert-Equal 'Seeded Nessie keeps canonical name' $nessie.name 'Nessie Plushie'
Assert-Equal 'Seeded Nessie category overrides offline snapshot' $nessie.category 'Plushie'
Assert-True 'Seeded category is resolved' ([bool]$nessie.categoryResolved)
Assert-Equal 'Seed provenance is explicit' $nessie.source 'config_seed'
Assert-Equal 'Seed category provenance is explicit' $nessie.categorySource 'config_seed'

$mapped = New-LocalCatalogEntry -Group $conflictGroup -Seed $null -OfflineCategory $categoryIndex['999'] -OfflineCategorySource 'yata_abroad_snapshot' -Now 1787345000
Assert-Equal 'Offline mapped item uses offline category provenance' $mapped.source 'offline_yata_category'
Assert-Equal 'Offline mapped item resolves category' $mapped.category 'Tool'
Assert-True 'Offline mapped category is resolved' ([bool]$mapped.categoryResolved)
Assert-Equal 'Offline category source is retained' $mapped.categorySource 'yata_abroad_snapshot'
Assert-True 'Provider name disagreement remains surfaced after category resolution' ([bool]$mapped.nameConflict)
Assert-Equal 'Provider name disagreement retains both names' @($mapped.providerNames).Count 2

$unmappedGroup = @($groups | Where-Object { $_.itemId -eq 1000 })[0]
$unknown = New-LocalCatalogEntry -Group $unmappedGroup -Seed $null -OfflineCategory '' -OfflineCategorySource 'yata_abroad_snapshot' -Now 1787345000
Assert-Equal 'Unmapped observed item uses provider-name provenance' $unknown.source 'provider_name'
Assert-Equal 'Unmapped observed item category stays Unknown' $unknown.category 'Unknown'
Assert-Equal 'Unmapped category stays unresolved' ([bool]$unknown.categoryResolved) $false
Assert-Equal 'Unmapped category provenance stays empty' $unknown.categorySource ''

$sigA = Get-LocalCatalogSignature -Groups $groups -SeedIndex $seedIndex -CategoryIndex $categoryIndex -CategorySourceId 'yata_abroad_snapshot'
$sigB = Get-LocalCatalogSignature -Groups $groups -SeedIndex $seedIndex -CategoryIndex $categoryIndex -CategorySourceId 'yata_abroad_snapshot'
Assert-Equal 'Local catalog signature is deterministic' $sigA $sigB
$configChanged = [pscustomobject]@{ items = @([pscustomobject]@{ itemId=206; name='Xanax'; category='Drug Revised' }) }
$sigSeedChanged = Get-LocalCatalogSignature -Groups $groups -SeedIndex (Get-SeedIndex -ItemsConfig $configChanged) -CategoryIndex $categoryIndex -CategorySourceId 'yata_abroad_snapshot'
Assert-True 'Seed category override changes local catalog signature' ($sigSeedChanged -ne $sigA)
$categoryConfigChanged = [pscustomobject]@{ categoriesByItemId = [pscustomobject]@{ '266'='OfflinePlushie'; '999'='Material' } }
$sigCategoryChanged = Get-LocalCatalogSignature -Groups $groups -SeedIndex $seedIndex -CategoryIndex (Get-CategoryIndex -CategoryConfig $categoryConfigChanged) -CategorySourceId 'yata_abroad_snapshot'
Assert-True 'Offline category change alters local catalog signature' ($sigCategoryChanged -ne $sigA)

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

Write-Host 'Local catalog category precedence/normalization tests passed.' -ForegroundColor Green
exit 0
