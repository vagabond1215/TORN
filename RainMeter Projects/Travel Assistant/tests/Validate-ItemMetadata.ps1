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
    if ($text -notmatch '(?m)^\s*\[int\]\$TimeoutSec\s*=\s*12') { Fail 'Item metadata default timeout must be 12 seconds.' }
    if (-not $text.Contains("https://api.torn.com/torn/?selections=items")) { Fail 'Item metadata must use the single bulk Torn items selection.' }
    if ($text.Contains('/v2/torn/$ids/items')) { Fail 'Item metadata must not use the timed-out v2 multi-ID path.' }
    if (-not $text.Contains('$psi.Arguments = ''-q --config -''')) { Fail 'Torn item metadata curl must receive its config through stdin.' }
    if (-not $text.Contains('Authorization: ApiKey {0}')) { Fail 'Torn item metadata must authenticate through an Authorization header.' }
    if (-not $text.Contains('User-Agent: TravelAssistant-Rainmeter/1.0')) { Fail 'Torn metadata request must identify itself with a custom User-Agent.' }
    if ($text -match '(?i)[?&]key=') { Fail 'Torn API key must never be placed in the metadata request URL.' }

    foreach ($functionName in @('Get-ObservedItemIds','Get-CanonicalCategory','Convert-TornBulkItemMetadata','Invoke-TornBulkItemsJsonWithCurl','Get-MetadataCategories')) {
        if ($text -notmatch ('(?m)^function\s+' + [regex]::Escape($functionName) + '\s*\{')) { Fail "Missing metadata function $functionName." }
    }
    foreach ($stateField in @('itemMetadata','metadataCollection','categoryResolved','marketPrice','itemsRequested','itemsResolved','tradabilityKnown')) {
        if (-not $text.Contains($stateField)) { Fail "Item metadata runtime contract is missing '$stateField'." }
    }
    if (-not $text.Contains("source = 'torn_items_bulk'")) { Fail 'Canonical item metadata must retain bulk Torn provenance.' }
    if ($text.Contains('Split-ItemIds')) { Fail 'Obsolete multi-ID batching helper must be removed from metadata enrichment.' }
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
Write-Host 'Observed item IDs use one 12-second bulk Torn items request with Authorization-header key handling and local filtering.'
exit 0
