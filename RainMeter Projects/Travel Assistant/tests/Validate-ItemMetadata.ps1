$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$metadataPath = Join-Path $ProjectRoot '@Resources\Scripts\ItemMetadata.ps1'
$wrapperPath = Join-Path $ProjectRoot '@Resources\Scripts\RunUpdate.ps1'
$errors = New-Object System.Collections.Generic.List[string]

function Fail([string]$Message) { $script:errors.Add($Message) }

if (-not (Test-Path -LiteralPath $metadataPath)) {
    Fail 'Missing @Resources\Scripts\ItemMetadata.ps1.'
} else {
    $text = Get-Content -LiteralPath $metadataPath -Raw
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($metadataPath, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in ItemMetadata.ps1: $($parseError.Message)" }

    if ($text -notmatch '(?m)^\s*\[int\]\$RefreshIntervalSeconds\s*=\s*21600') { Fail 'Item metadata default refresh interval must be 6 hours.' }
    if ($text -notmatch '(?m)^\s*\[int\]\$MaxIdsPerRequest\s*=\s*40') { Fail 'Item metadata requests must default to bounded 40-ID batches.' }
    if ($text -notmatch '(?m)Invoke-TornItemsJsonWithCurl[^\r\n]+TimeoutSec\s*=\s*30') { Fail 'Item metadata curl helper must default to a bounded 30-second timeout.' }
    if (-not $text.Contains('https://api.torn.com/v2/torn/$ids/items?sort=ASC')) { Fail 'Item metadata must use Torn v2 specific-items endpoint.' }
    if (-not $text.Contains('$psi.Arguments = ''-q --config -''')) { Fail 'Torn item metadata curl must receive its config through stdin.' }
    if (-not $text.Contains('Authorization: ApiKey {0}')) { Fail 'Torn item metadata must authenticate through an Authorization header.' }
    if ($text -match '(?i)[?&]key=') { Fail 'Torn API key must never be placed in the metadata request URL.' }
    foreach ($functionName in @('Get-ObservedItemIds','Split-ItemIds','Get-CanonicalCategory','Convert-TornItemMetadata','Get-MetadataCategories')) {
        if ($text -notmatch ('(?m)^function\s+' + [regex]::Escape($functionName) + '\s*\{')) { Fail "Missing metadata function $functionName." }
    }
    foreach ($stateField in @('itemMetadata','metadataCollection','categoryResolved','marketPrice','shops','itemsRequested','itemsResolved')) {
        if (-not $text.Contains($stateField)) { Fail "Item metadata runtime contract is missing '$stateField'." }
    }
    if ($text -notmatch "if \(\`$type -eq 'Weapon'\)") { Fail 'Weapon metadata must use detailed category handling.' }
    if ($text -notmatch "category\s*=\s*'Weapon';\s*resolved\s*=\s*\`$false") { Fail 'Unresolved weapon categories must remain unresolved rather than guessed.' }
    if (-not $text.Contains("source = 'torn_items'")) { Fail 'Canonical item metadata must retain Torn provenance.' }
    if ($text -notmatch '(?m)\$chunks\.Add\(\[pscustomobject\]@\{ ids = \[int\[\]\]') { Fail 'Metadata batches must use explicit ids objects to avoid Windows PowerShell array flattening.' }
    if (-not $text.Contains('Checkpoint after each successful batch')) { Fail 'Metadata enrichment must checkpoint successful batches before continuing.' }
    if ($text -notmatch '(?s)foreach \(\$batch.*?Write-JsonAtomic -Path \$EngineStateFile -Value \$engineState') { Fail 'Metadata enrichment must persist state inside the batch loop.' }
}

if (-not (Test-Path -LiteralPath $wrapperPath)) {
    Fail 'Missing RunUpdate.ps1.'
} else {
    $wrapper = Get-Content -LiteralPath $wrapperPath -Raw
    foreach ($token in @('ShadowCollector.ps1','ItemMetadata.ps1','FinalizeState.ps1')) {
        if (-not $wrapper.Contains($token)) { Fail "RunUpdate.ps1 is missing $token." }
    }
    $shadowIndex = $wrapper.IndexOf('try { & $ShadowCollector }')
    $metadataIndex = $wrapper.IndexOf('try { & $ItemMetadata }')
    $finalizerIndex = $wrapper.IndexOf('& $Finalizer')
    if ($shadowIndex -lt 0 -or $metadataIndex -lt 0 -or $finalizerIndex -lt 0 -or -not ($shadowIndex -lt $metadataIndex -and $metadataIndex -lt $finalizerIndex)) {
        Fail 'RunUpdate.ps1 must run shadow collection, then metadata enrichment, then finalization.'
    }
    if (-not $wrapper.Contains('Write-MetadataFailure')) { Fail 'Metadata enrichment must remain fail-soft in the production wrapper.' }
}

if ($errors.Count -gt 0) {
    foreach ($errorMessage in $errors) { Write-Host "FAIL: $errorMessage" -ForegroundColor Red }
    Write-Host "Item metadata validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Item metadata configuration validation passed.' -ForegroundColor Green
Write-Host 'Observed item IDs use 40-ID/30s bounded Torn batches with per-batch checkpoints and no change to visible recommendation economics.'
exit 0
