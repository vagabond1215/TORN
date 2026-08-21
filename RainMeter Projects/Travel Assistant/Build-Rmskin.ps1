param(
    [string]$OutputDir = (Join-Path $PSScriptRoot 'dist'),
    [string]$BuilderCommand = '',
    [switch]$StageOnly
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path $PSScriptRoot).Path
$SkinName = 'Travel Assistant'
$SkinIni = Join-Path $ProjectRoot 'TravelAssistant.ini'
$StageRoot = Join-Path $OutputDir '_rmskin-stage'
$StageSkin = Join-Path $StageRoot ('Skins\' + $SkinName)

function Copy-RequiredFile {
    param([Parameter(Mandatory = $true)][string]$RelativePath)
    $source = Join-Path $ProjectRoot $RelativePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required distribution file is missing: $RelativePath"
    }
    $destination = Join-Path $StageSkin $RelativePath
    $destinationDir = Split-Path $destination -Parent
    New-Item -ItemType Directory -Force -Path $destinationDir | Out-Null
    Copy-Item -LiteralPath $source -Destination $destination -Force
}

function Get-SkinVersion {
    if (-not (Test-Path -LiteralPath $SkinIni)) { throw 'TravelAssistant.ini is missing.' }
    $text = Get-Content -LiteralPath $SkinIni -Raw
    $match = [regex]::Match($text, '(?ms)^\[Metadata\].*?^Version=([^\r\n]+)')
    if (-not $match.Success) { throw 'TravelAssistant.ini [Metadata] Version could not be read.' }
    return $match.Groups[1].Value.Trim()
}

function Get-LocalApiKey {
    $localPath = Join-Path $ProjectRoot 'config\settings.local.json'
    if (-not (Test-Path -LiteralPath $localPath)) { return '' }
    try {
        $local = Get-Content -LiteralPath $localPath -Raw | ConvertFrom-Json
        if ($null -ne $local -and $local.PSObject.Properties['tornApiKey']) {
            return [string]$local.tornApiKey
        }
    } catch { }
    return ''
}

function Assert-DistributionSafe {
    param([string]$Root)

    $forbiddenNames = @(
        'settings.local.json',
        'secrets.json',
        '.env',
        'engine-state.json',
        'observations.jsonl',
        'cycles.jsonl',
        'shadow-collection-error.txt',
        'item-metadata-error.txt',
        'state.kv',
        'last-update.txt'
    )

    $forbidden = @(
        Get-ChildItem -LiteralPath $Root -Recurse -File -Force |
            Where-Object { $forbiddenNames -contains $_.Name }
    )
    if ($forbidden.Count -gt 0) {
        throw ('Distribution staging contains forbidden local/runtime files: ' + (($forbidden | ForEach-Object { $_.FullName }) -join '; '))
    }

    $templatePath = Join-Path $StageSkin 'config\settings.local.example.json'
    $template = Get-Content -LiteralPath $templatePath -Raw | ConvertFrom-Json
    if ($template.PSObject.Properties['tornApiKey'] -and -not [string]::IsNullOrWhiteSpace([string]$template.tornApiKey)) {
        throw 'settings.local.example.json must contain a blank Torn API key before packaging.'
    }

    $localKey = Get-LocalApiKey
    if (-not [string]::IsNullOrWhiteSpace($localKey)) {
        foreach ($file in Get-ChildItem -LiteralPath $Root -Recurse -File -Force) {
            if ($file.Length -gt 5MB) { continue }
            try {
                $text = Get-Content -LiteralPath $file.FullName -Raw -ErrorAction Stop
                if ($text.Contains($localKey)) {
                    throw 'Distribution safety check detected the local Torn API key in staged content. Packaging was stopped.'
                }
            } catch {
                if ($_.Exception.Message -like 'Distribution safety check detected*') { throw }
            }
        }
    }
}

function Resolve-RmskinBuilder {
    param([string]$ExplicitCommand)

    if (-not [string]::IsNullOrWhiteSpace($ExplicitCommand)) {
        $explicit = Get-Command $ExplicitCommand -ErrorAction SilentlyContinue
        if ($null -eq $explicit) { throw "RMSKIN builder command was not found: $ExplicitCommand" }
        return $explicit.Source
    }

    foreach ($candidate in @('rmskin-builder.exe', 'rmskin-build.exe', 'rmskin-build')) {
        $command = Get-Command $candidate -ErrorAction SilentlyContinue
        if ($null -ne $command) { return $command.Source }
    }
    return ''
}

$version = Get-SkinVersion
New-Item -ItemType Directory -Force -Path $OutputDir | Out-Null
if (Test-Path -LiteralPath $StageRoot) { Remove-Item -LiteralPath $StageRoot -Recurse -Force }
New-Item -ItemType Directory -Force -Path $StageSkin | Out-Null

# Distribution is intentionally whitelist-based. Never package the project tree
# wholesale: ignored local settings/runtime files may exist beside source files.
foreach ($relative in @(
    'TravelAssistant.ini',
    'Readme.md',
    'config\countries.json',
    'config\items.json',
    'config\providers.json',
    'config\settings.example.json',
    'config\settings.local.example.json',
    'config\travel-modes.json',
    'config\travel-perks.json',
    'data\seed\metadata.json',
    'data\seed\observations.jsonl',
    'data\seed\cycles.jsonl'
)) {
    Copy-RequiredFile -RelativePath $relative
}

$scriptsSource = Join-Path $ProjectRoot '@Resources\Scripts'
if (-not (Test-Path -LiteralPath $scriptsSource -PathType Container)) { throw '@Resources\Scripts is missing.' }
$scriptsDestination = Join-Path $StageSkin '@Resources\Scripts'
New-Item -ItemType Directory -Force -Path $scriptsDestination | Out-Null
foreach ($file in Get-ChildItem -LiteralPath $scriptsSource -File) {
    if ($file.Extension -notin @('.ps1', '.lua')) { continue }
    Copy-Item -LiteralPath $file.FullName -Destination (Join-Path $scriptsDestination $file.Name) -Force
}

$manifest = @"
[rmskin]
Name=Travel Assistant
Author=vagabond1215
Version=$version
LoadType=Skin
Load=Travel Assistant\TravelAssistant.ini
MergeSkins=1
MinimumRainmeter=4.5
MinimumWindows=10.0
"@
[System.IO.File]::WriteAllText((Join-Path $StageRoot 'RMSKIN.ini'), $manifest, [System.Text.UTF8Encoding]::new($false))

Assert-DistributionSafe -Root $StageRoot

Write-Host "Safe RMSKIN staging created:`n  $StageRoot" -ForegroundColor Green
Write-Host 'Local API settings, runtime history, generated graphs/state, logs, and credentials were not staged.' -ForegroundColor Green

if ($StageOnly) {
    Write-Host 'StageOnly requested; package build skipped.' -ForegroundColor Yellow
    exit 0
}

$builder = Resolve-RmskinBuilder -ExplicitCommand $BuilderCommand
if ([string]::IsNullOrWhiteSpace($builder)) {
    Write-Host ''
    Write-Host 'No rmskin-builder executable was found.' -ForegroundColor Yellow
    Write-Host 'Install the optional builder once with:' -ForegroundColor Cyan
    Write-Host '  py -m pip install --user rmskin-builder'
    Write-Host 'Then rerun this script. The recipient does NOT need this builder; they only receive the generated .rmskin file.'
    exit 2
}

$existing = @{}
foreach ($file in Get-ChildItem -LiteralPath $OutputDir -Filter '*.rmskin' -File -ErrorAction SilentlyContinue) {
    $existing[$file.FullName] = $file.LastWriteTimeUtc
}

& $builder --path $StageRoot --dir-out $OutputDir --version $version --title 'Travel Assistant' --author 'vagabond1215'
if ($LASTEXITCODE -ne 0) { throw "rmskin builder exited with code $LASTEXITCODE." }

$packages = @(Get-ChildItem -LiteralPath $OutputDir -Filter '*.rmskin' -File | Sort-Object LastWriteTimeUtc -Descending)
if ($packages.Count -eq 0) { throw 'RMSKIN builder completed but no .rmskin package was found.' }

$package = $packages[0]
Write-Host ''
Write-Host "Created distribution package:`n  $($package.FullName)" -ForegroundColor Green
Write-Host 'Share this .rmskin file. Each recipient enters their own Torn API key from SETTINGS after installation.' -ForegroundColor Cyan
