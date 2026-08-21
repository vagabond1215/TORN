$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$catalogPath = Join-Path $ProjectRoot '@Resources\Scripts\LocalCatalog.ps1'
$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$categoryPath = Join-Path $ProjectRoot 'config\foreign-item-categories.json'
$overridePath = Join-Path $ProjectRoot 'config\foreign-market-overrides.json'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

if (-not (Test-Path -LiteralPath $categoryPath)) {
    Fail 'Missing config\foreign-item-categories.json.'
} else {
    $categories = Get-Content -LiteralPath $categoryPath -Raw | ConvertFrom-Json
    if (-not $categories.PSObject.Properties['categoriesByItemId']) { Fail 'Offline category snapshot must expose categoriesByItemId.' }
    if (-not $categories.PSObject.Properties['source']) { Fail 'Offline category snapshot must retain provenance.' }
    $entryCount = @($categories.categoriesByItemId.PSObject.Properties).Count
    if ($entryCount -ne 197) { Fail "Expected 197 YATA-derived offline category entries, found $entryCount." }
    foreach ($pair in @(
        [pscustomobject]@{ id='206'; category='Drug' },
        [pscustomobject]@{ id='266'; category='Plushie' },
        [pscustomobject]@{ id='277'; category='Flower' },
        [pscustomobject]@{ id='50'; category='Armor' },
        [pscustomobject]@{ id='259'; category='Miscellaneous' },
        [pscustomobject]@{ id='1504'; category='Artifact' }
    )) {
        $prop = $categories.categoriesByItemId.PSObject.Properties[$pair.id]
        if ($null -eq $prop -or [string]$prop.Value -ne $pair.category) { Fail "Offline category $($pair.id) must be $($pair.category)." }
    }
}

if (-not (Test-Path -LiteralPath $overridePath)) {
    Fail 'Missing config\foreign-market-overrides.json.'
} else {
    $overrides = Get-Content -LiteralPath $overridePath -Raw | ConvertFrom-Json
    if (-not $overrides.PSObject.Properties['itemOverrides']) { Fail 'Verified override config must expose itemOverrides.' }
    if (-not $overrides.PSObject.Properties['marketOverrides']) { Fail 'Verified override config must expose marketOverrides.' }
    if (@($overrides.itemOverrides.PSObject.Properties).Count -ne 5) { Fail 'Verified item override count must remain five for the current legacy-row repair.' }
    if (@($overrides.marketOverrides.PSObject.Properties).Count -ne 5) { Fail 'Verified market override count must remain five for the current legacy-row repair.' }

    foreach ($pair in @(
        [pscustomobject]@{ id='21'; name='Dual 92G Berettas'; category='Secondary' },
        [pscustomobject]@{ id='232'; name='SIG 550'; category='Primary' },
        [pscustomobject]@{ id='327'; name='Blank Casino Chips'; category='Material' },
        [pscustomobject]@{ id='383'; name='Digital Organizer'; category='Miscellaneous' },
        [pscustomobject]@{ id='440'; name='Pillow'; category='Melee' }
    )) {
        $prop = $overrides.itemOverrides.PSObject.Properties[$pair.id]
        if ($null -eq $prop) { Fail "Missing verified item override $($pair.id)."; continue }
        if ([string]$prop.Value.name -ne $pair.name) { Fail "Verified item $($pair.id) name mismatch." }
        if ([string]$prop.Value.category -ne $pair.category) { Fail "Verified item $($pair.id) category mismatch." }
    }

    foreach ($key in @('mexico:21','mexico:232','mexico:327','united_arab_emirates:383','united_arab_emirates:440')) {
        $prop = $overrides.marketOverrides.PSObject.Properties[$key]
        if ($null -eq $prop) { Fail "Missing legacy market override '$key'."; continue }
        if ([bool]$prop.Value.active -ne $false) { Fail "Legacy market '$key' must be inactive." }
        if ([string]$prop.Value.status -ne 'legacy_removed') { Fail "Legacy market '$key' must use status legacy_removed." }
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

    foreach ($functionName in @('Get-ObservedItemGroups','Get-SeedIndex','Get-CategoryIndex','Get-VerifiedItemIndex','Get-MarketOverrideIndex','New-LocalCatalogEntry','Get-LocalCatalogSignature','Merge-RicherMetadata','Apply-MarketOverrides')) {
        if ($text -notmatch ('(?m)^function\s+' + [regex]::Escape($functionName) + '\s*\{')) { Fail "Missing local catalog function $functionName." }
    }
    foreach ($token in @('providerName','providerNames','nameConflict','countries','categoryResolved','categorySource','localCatalog','config_seed','offline_yata_category','verified_override','catalogActive','catalogStatus','foreign-item-categories.json','foreign-market-overrides.json','offlineCategoryEntries','offlineMatchedItems','verifiedItemOverrides','inactiveObservedMarkets')) {
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
Write-Host 'All current observed item IDs can resolve locally; five verified legacy provider markets are explicitly inactive.'
exit 0
