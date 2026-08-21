$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$BuilderPath = Join-Path $ProjectRoot 'Build-Rmskin.ps1'
$OutputDir = Join-Path $ProjectRoot 'test-output\distribution'
$StageRoot = Join-Path $OutputDir '_rmskin-stage'
$StageSkin = Join-Path $StageRoot 'Skins\Travel Assistant'
$errors = New-Object System.Collections.Generic.List[string]

function Fail([string]$Message) { $script:errors.Add($Message) }

if (-not (Test-Path -LiteralPath $BuilderPath)) {
    Fail 'Build-Rmskin.ps1 is missing.'
} else {
    $tokens = $null
    $parseErrors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($BuilderPath, [ref]$tokens, [ref]$parseErrors)
    foreach ($parseError in @($parseErrors)) { Fail "PowerShell parse error in Build-Rmskin.ps1: $($parseError.Message)" }

    $text = Get-Content -LiteralPath $BuilderPath -Raw
    foreach ($required in @(
        'settings.local.example.json',
        'Assert-DistributionSafe',
        'MergeSkins=1',
        'Load=Travel Assistant\TravelAssistant.ini',
        'py -m pip install --user rmskin-builder',
        'Distribution safety check detected the local Torn API key'
    )) {
        if (-not $text.Contains($required)) { Fail "Build-Rmskin.ps1 is missing distribution contract text: $required" }
    }
    if ($text -match "Copy-Item[^\r\n]+\$ProjectRoot[^\r\n]+-Recurse") {
        Fail 'Build-Rmskin.ps1 must not recursively package the whole project root.'
    }
}

$templatePath = Join-Path $ProjectRoot 'config\settings.local.example.json'
if (-not (Test-Path -LiteralPath $templatePath)) {
    Fail 'settings.local.example.json is missing.'
} else {
    try {
        $template = Get-Content -LiteralPath $templatePath -Raw | ConvertFrom-Json
        if ($template.PSObject.Properties['tornApiKey'] -and -not [string]::IsNullOrWhiteSpace([string]$template.tornApiKey)) {
            Fail 'settings.local.example.json must keep tornApiKey blank for distribution.'
        }
    } catch {
        Fail "settings.local.example.json is invalid JSON: $($_.Exception.Message)"
    }
}

if ($errors.Count -eq 0) {
    if (Test-Path -LiteralPath $OutputDir) { Remove-Item -LiteralPath $OutputDir -Recurse -Force }
    try {
        & $BuilderPath -OutputDir $OutputDir -StageOnly
        if ($LASTEXITCODE -ne 0) { Fail "Build-Rmskin.ps1 -StageOnly exited with code $LASTEXITCODE." }

        foreach ($requiredRelative in @(
            'RMSKIN.ini',
            'Skins\Travel Assistant\TravelAssistant.ini',
            'Skins\Travel Assistant\@Resources\Scripts\RunUpdate.ps1',
            'Skins\Travel Assistant\config\settings.local.example.json',
            'Skins\Travel Assistant\data\seed\observations.jsonl',
            'Skins\Travel Assistant\data\seed\cycles.jsonl'
        )) {
            if (-not (Test-Path -LiteralPath (Join-Path $StageRoot $requiredRelative))) {
                Fail "Distribution stage is missing required file: $requiredRelative"
            }
        }

        foreach ($forbiddenRelative in @(
            'Skins\Travel Assistant\config\settings.local.json',
            'Skins\Travel Assistant\data\runtime',
            'Skins\Travel Assistant\@Resources\Generated',
            'Skins\Travel Assistant\@Resources\Cache'
        )) {
            if (Test-Path -LiteralPath (Join-Path $StageRoot $forbiddenRelative)) {
                Fail "Distribution stage contains forbidden local/runtime path: $forbiddenRelative"
            }
        }

        $manifestPath = Join-Path $StageRoot 'RMSKIN.ini'
        if (Test-Path -LiteralPath $manifestPath) {
            $manifest = Get-Content -LiteralPath $manifestPath -Raw
            if ($manifest -notmatch '(?im)^LoadType=Skin\s*$') { Fail 'RMSKIN.ini must load a skin after installation.' }
            if ($manifest -notmatch '(?im)^Load=Travel Assistant\\TravelAssistant\.ini\s*$') { Fail 'RMSKIN.ini must load TravelAssistant.ini.' }
            if ($manifest -notmatch '(?im)^MergeSkins=1\s*$') { Fail 'RMSKIN.ini must merge updates so recipient-local settings are preserved.' }
        }
    } catch {
        Fail "Distribution staging execution failed: $($_.Exception.Message)"
    } finally {
        if (Test-Path -LiteralPath $OutputDir) { Remove-Item -LiteralPath $OutputDir -Recurse -Force -ErrorAction SilentlyContinue }
    }
}

if ($errors.Count -gt 0) {
    foreach ($errorMessage in $errors) { Write-Host "FAIL: $errorMessage" -ForegroundColor Red }
    Write-Host "Distribution validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Distribution staging validation passed.' -ForegroundColor Green
Write-Host 'RMSKIN staging excludes local API settings/runtime state and preserves recipient settings on package updates.'
exit 0
