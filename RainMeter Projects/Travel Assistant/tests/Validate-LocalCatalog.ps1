$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$catalogPath = Join-Path $ProjectRoot '@Resources\Scripts\LocalCatalog.ps1'
$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

if (-not (Test-Path -LiteralPath $catalogPath)) {
    Fail 'Missing @Resources\Scripts\LocalCatalog.ps1.'
} else {
    $text = Get-Content -LiteralPath $catalogPath -Raw
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($catalogPath, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in LocalCatalog.ps1: $($parseError.Message)" }

    foreach ($functionName in @('Get-ObservedItemGroups','Get-SeedIndex','New-LocalCatalogEntry','Get-LocalCatalogSignature','Merge-RicherMetadata')) {
        if ($text -notmatch ('(?m)^function\s+' + [regex]::Escape($functionName) + '\s*\{')) { Fail "Missing local catalog function $functionName." }
    }
    foreach ($token in @('providerName','providerNames','nameConflict','countries','categoryResolved','localCatalog','config_seed','provider_name')) {
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
Write-Host 'Observed provider names become local metadata without adding catalog network work to the Rainmeter heartbeat.'
exit 0
