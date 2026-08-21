$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$catalogPath = Join-Path $ProjectRoot '@Resources\Scripts\LocalCatalog.ps1'
$categoryPath = Join-Path $ProjectRoot 'config\foreign-item-categories.json'
$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

if (-not (Test-Path -LiteralPath $categoryPath)) {
    Fail 'Missing config\foreign-item-categories.json.'
} else {
    try {
        $categoryConfig = Get-Content -LiteralPath $categoryPath -Raw | ConvertFrom-Json
        if ([int]$categoryConfig.schemaVersion -ne 1) { Fail 'Offline foreign-item category snapshot schemaVersion must be 1.' }
        if ($null -eq $categoryConfig.source -or [string]$categoryConfig.source.id -ne 'yata_abroad_snapshot') { Fail 'Offline category snapshot must retain yata_abroad_snapshot provenance.' }
        if ([int]$categoryConfig.source.entryCount -ne 197) { Fail 'Offline category snapshot provenance must record 197 source entries.' }
        $categoryRows = @($categoryConfig.categoriesByItemId.PSObject.Properties)
        if ($categoryRows.Count -ne 197) { Fail "Expected 197 offline category entries, found $($categoryRows.Count)." }
        if ([string]$categoryConfig.normalization.Defensive -ne 'Armor') { Fail 'Defensive categories must normalize to Armor.' }
        if ([string]$categoryConfig.normalization.Other -ne 'Miscellaneous') { Fail 'Other categories must normalize to Miscellaneous.' }

        $expectedCategories = @('Alcohol','Artifact','Armor','Clothing','Drug','Enhancer','Flower','Material','Medical','Melee','Miscellaneous','Plushie','Primary','Secondary','Temporary','Tool')
        $actualCategories = @($categoryRows | ForEach-Object { [string]$_.Value } | Sort-Object -Unique)
        foreach ($category in $expectedCategories) {
            if ($actualCategories -notcontains $category) { Fail "Offline category snapshot is missing canonical category '$category'." }
        }
        foreach ($category in $actualCategories) {
            if ($expectedCategories -notcontains $category) { Fail "Offline category snapshot contains unexpected category '$category'." }
        }

        $spotChecks = [ordered]@{
            '206' = 'Drug'
            '266' = 'Plushie'
            '277' = 'Flower'
            '50' = 'Armor'
            '259' = 'Miscellaneous'
            '419' = 'Enhancer'
            '159' = 'Tool'
            '361' = 'Medical'
            '1246' = 'Material'
            '1499' = 'Artifact'
        }
        foreach ($itemId in $spotChecks.Keys) {
            $property = $categoryConfig.categoriesByItemId.PSObject.Properties[[string]$itemId]
            if ($null -eq $property -or [string]$property.Value -ne [string]$spotChecks[$itemId]) {
                Fail "Offline category snapshot item $itemId must resolve to '$($spotChecks[$itemId])'."
            }
        }
    } catch {
        Fail ('Offline category snapshot JSON validation failed: ' + $_.Exception.Message)
    }
}

if (-not (Test-Path -LiteralPath $catalogPath)) {
    Fail 'Missing @Resources\Scripts\LocalCatalog.ps1.'
} else {
    $text = Get-Content -LiteralPath $catalogPath -Raw
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($catalogPath, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in LocalCatalog.ps1: $($parseError.Message)" }

    foreach ($functionName in @('Get-ObservedItemGroups','Get-SeedIndex','Get-CategoryIndex','New-LocalCatalogEntry','Get-LocalCatalogSignature','Merge-RicherMetadata')) {
        if ($text -notmatch ('(?m)^function\s+' + [regex]::Escape($functionName) + '\s*\{')) { Fail "Missing local catalog function $functionName." }
    }
    foreach ($token in @('providerName','providerNames','nameConflict','countries','categoryResolved','categorySource','localCatalog','config_seed','offline_yata_category','provider_name','foreign-item-categories.json','offlineCategoryEntries','offlineMatchedItems')) {
        if (-not $text.Contains($token)) { Fail "Local catalog contract is missing '$token'." }
    }
    if ($text -match '(?i)https?://|Invoke-RestMethod|curl\.exe') { Fail 'Local catalog enrichment must not perform network access.' }
    if (-not $text.Contains('[string]$Existing.source -ne ''torn_items_bulk''')) { Fail 'Local catalog must preserve richer manually fetched Torn metadata.' }
    if (-not $text.Contains('Get-LocalCatalogSignature')) { Fail 'Local catalog must avoid needless rewrites through a stable signature.' }
}

if (-not (Test-Path -LiteralPath $wrapperPath)) {
    Fail 'Missing RunUpdate.ps1.'
} else {
    $wrapper = Get-Content -LiteralPath $wrapperPath -Raw
    foreach ($token in @('ShadowCollector.ps1','LocalCatalog.ps1','FinalizeState.ps1','Write-LocalCatalogFailure')) {
        if (-not $wrapper.Contains($token)) { Fail "RunUpdate.ps1 is missing $token." }
    }
    if ($wrapper.Contains("Join-Path `$PSScriptRoot 'ItemMetadata.ps1'")) { Fail 'Network ItemMetadata.ps1 must remain outside the heartbeat path.' }
    $shadowIndex = $wrapper.IndexOf('& $ShadowCollector')
    $catalogIndex = $wrapper.IndexOf('& $LocalCatalog')
    $finalizerIndex = $wrapper.IndexOf('& $Finalizer')
    if ($shadowIndex -lt 0 -or $catalogIndex -lt 0 -or $finalizerIndex -lt 0 -or -not ($shadowIndex -lt $catalogIndex -and $catalogIndex -lt $finalizerIndex)) {
        Fail 'RunUpdate.ps1 must run shadow collection, then local catalog enrichment, then finalization.'
    }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Local catalog validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Local catalog configuration validation passed.' -ForegroundColor Green
Write-Host 'The 197-ID offline category snapshot enriches only observed items; unmatched items remain explicitly unresolved.'
exit 0
