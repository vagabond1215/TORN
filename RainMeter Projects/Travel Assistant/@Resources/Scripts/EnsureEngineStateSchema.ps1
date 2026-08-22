$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'

if (-not (Test-Path -LiteralPath $EngineStateFile)) { return }
$raw = Get-Content -LiteralPath $EngineStateFile -Raw -ErrorAction Stop
if ([string]::IsNullOrWhiteSpace($raw)) { return }
$state = $raw | ConvertFrom-Json
$changed = $false

function Ensure-StateProperty {
    param([object]$Object,[string]$Name,[object]$DefaultValue)
    if (-not $Object.PSObject.Properties[$Name]) {
        $Object | Add-Member NoteProperty $Name $DefaultValue
        $script:changed = $true
    }
}

Ensure-StateProperty -Object $state -Name 'destinations' -DefaultValue ([pscustomobject]@{})
Ensure-StateProperty -Object $state -Name 'resaleCache' -DefaultValue ([pscustomobject]@{})
Ensure-StateProperty -Object $state -Name 'observedMarkets' -DefaultValue ([pscustomobject]@{})
Ensure-StateProperty -Object $state -Name 'shadowCollection' -DefaultValue ([pscustomobject]@{
    lastPollAt = 0
    lastProvider = ''
    countriesSeen = 0
    marketsSeen = 0
    legacyMarketsSeen = 0
    observationsWritten = 0
    cyclesCompleted = 0
    lastErrorAt = 0
    lastError = ''
})

foreach ($name in @('lastPollAt','lastProvider','countriesSeen','marketsSeen','legacyMarketsSeen','observationsWritten','cyclesCompleted','lastErrorAt','lastError')) {
    $default = if ($name -in @('lastProvider','lastError')) { '' } else { 0 }
    Ensure-StateProperty -Object $state.shadowCollection -Name $name -DefaultValue $default
}

if (-not $changed) { return }
New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
$tmp = $EngineStateFile + '.tmp'
$state | ConvertTo-Json -Depth 24 | Set-Content -LiteralPath $tmp -Encoding UTF8
Move-Item -LiteralPath $tmp -Destination $EngineStateFile -Force
