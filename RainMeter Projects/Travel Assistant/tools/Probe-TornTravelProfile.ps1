$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$SettingsPath = Join-Path $ProjectRoot 'config\settings.local.json'
. (Join-Path $ProjectRoot '@Resources\Scripts\TornProfileSync.ps1')

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-ProbeFailure {
    param([string]$Label, [object]$Result)
    Write-Host ('{0}: UNAVAILABLE (HTTP {1}) - {2}' -f $Label, [int]$Result.HttpStatus, [string]$Result.Error) -ForegroundColor Yellow
}

$settings = Read-JsonFile $SettingsPath
if ($null -eq $settings -or -not $settings.PSObject.Properties['tornApiKey'] -or [string]::IsNullOrWhiteSpace([string]$settings.tornApiKey)) {
    Write-Host 'No Torn API key is present in config\settings.local.json.' -ForegroundColor Red
    exit 1
}
$apiKey = [string]$settings.tornApiKey

Write-Host 'Travel Assistant - Torn profile probe' -ForegroundColor Cyan
Write-Host 'API KEY: PRESENT (not displayed)'
Write-Host ''

$basic = Invoke-TornProfileJson -Uri 'https://api.torn.com/v2/user/basic?comment=TravelAssistantProfileProbe' -ApiKey $apiKey
if ($basic.Success) {
    $row = if ($basic.Payload.PSObject.Properties['profile']) { $basic.Payload.profile } else { $null }
    if ($null -ne $row) {
        $name = if ($row.PSObject.Properties['name']) { [string]$row.name } else { '(unknown)' }
        $id = if ($row.PSObject.Properties['id']) { [string]$row.id } else { '?' }
        $level = if ($row.PSObject.Properties['level']) { [string]$row.level } else { '?' }
        Write-Host ('BASIC: OK - {0} [{1}], level {2}' -f $name, $id, $level) -ForegroundColor Green
    } else { Write-Host 'BASIC: OK - no expected profile object' -ForegroundColor Yellow }
} else { Write-ProbeFailure -Label 'BASIC' -Result $basic }

$job = Invoke-TornProfileJson -Uri 'https://api.torn.com/v2/user/job?comment=TravelAssistantProfileProbe' -ApiKey $apiKey
if ($job.Success) {
    $row = if ($job.Payload.PSObject.Properties['job']) { $job.Payload.job } else { $null }
    if ($null -eq $row) { Write-Host 'JOB: OK - no current job/company' -ForegroundColor Green }
    elseif ([string]$row.type -eq 'company') {
        Write-Host ('JOB: OK - company "{0}" | type_id={1} | rating={2}*' -f [string]$row.name, [string]$row.type_id, [string]$row.rating) -ForegroundColor Green
    } else {
        Write-Host ('JOB: OK - starter job "{0}" | position="{1}"' -f [string]$row.name, [string]$row.position) -ForegroundColor Green
    }
} else { Write-ProbeFailure -Label 'JOB' -Result $job }

$faction = Invoke-TornProfileJson -Uri 'https://api.torn.com/v2/faction/upgrades?comment=TravelAssistantProfileProbe' -ApiKey $apiKey
if ($faction.Success) {
    $profile = Get-TornFactionTravelProfile -FactionPayload $faction.Payload
    Write-Host 'FACTION UPGRADES: OK' -ForegroundColor Green
    Write-Host ('  Mode:   {0}' -f ([string]$profile.State).ToUpperInvariant())
    Write-Host ('  Active: capacity {0}/10 | cost {1}/5' -f [int]$profile.ExcursionLevel, [int]$profile.TravelCostLevel)
    Write-Host ('  Peace:  capacity {0}/10 | cost {1}/5' -f [int]$profile.PeaceExcursionLevel, [int]$profile.PeaceTravelCostLevel)
    Write-Host ('  War:    capacity {0}/10 | cost {1}/5' -f [int]$profile.WarExcursionLevel, [int]$profile.WarTravelCostLevel)
    if (-not [bool]$profile.Resolved) {
        Write-Host '  Active mode was not recognized; no active faction perks should be assumed.' -ForegroundColor Yellow
    }
} else {
    Write-ProbeFailure -Label 'FACTION UPGRADES' -Result $faction
    Write-Host '  This endpoint specifically requires faction API access permission.' -ForegroundColor DarkYellow
}

Write-Host ''
Write-Host 'Probe complete. No API key value was printed or placed on the curl command line.' -ForegroundColor Cyan
exit 0
