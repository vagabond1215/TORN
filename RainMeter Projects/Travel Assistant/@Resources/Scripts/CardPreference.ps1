param(
    [string]$PinnedMarket = '',
    [switch]$SkipMain
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$PreferenceFile = Join-Path $RuntimeDir 'preferences.json'

function Test-PinnedMarketIdentity {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return $true }
    return $Value -match '^[a-z0-9_]+:[1-9][0-9]*$'
}

function Set-PinnedMarketPreferenceObject {
    param([object]$Preferences, [string]$Value)

    if (-not (Test-PinnedMarketIdentity -Value $Value)) {
        throw 'Pinned market must be empty or use country:itemId identity.'
    }

    if ($null -eq $Preferences) {
        $Preferences = [pscustomobject]@{ schemaVersion = 1 }
    }
    if (-not $Preferences.PSObject.Properties['schemaVersion']) {
        $Preferences | Add-Member NoteProperty schemaVersion 1
    }

    $property = $Preferences.PSObject.Properties['pinnedMarket']
    if ($null -eq $property) {
        $Preferences | Add-Member NoteProperty pinnedMarket ([string]$Value)
    } else {
        $property.Value = [string]$Value
    }
    return $Preferences
}

function Read-PinJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-PinJsonAtomic {
    param([string]$Path, [object]$Value)
    $dir = Split-Path $Path -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $tmp = $Path + '.tmp'
    $Value | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

if ($SkipMain) { return }

$preferences = Read-PinJson -Path $PreferenceFile
$preferences = Set-PinnedMarketPreferenceObject -Preferences $preferences -Value $PinnedMarket
Write-PinJsonAtomic -Path $PreferenceFile -Value $preferences
