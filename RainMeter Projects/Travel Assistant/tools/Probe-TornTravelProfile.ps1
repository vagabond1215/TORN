$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$SettingsPath = Join-Path $ProjectRoot 'config\settings.local.json'
. (Join-Path $ProjectRoot '@Resources\Scripts\TornProfileSync.ps1')
. (Join-Path $ProjectRoot '@Resources\Scripts\CurrentCapacity.ps1')

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-ProbeFailure {
    param([string]$Label, [object]$Result)
    $codeText = ''
    if ($null -ne $Result -and $Result.PSObject.Properties['ApiErrorCode'] -and [int]$Result.ApiErrorCode -gt 0) {
        $codeText = (' / Torn code {0}' -f [int]$Result.ApiErrorCode)
    }
    Write-Host ('{0}: UNAVAILABLE (HTTP {1}{2}) - {3}' -f $Label, [int]$Result.HttpStatus, $codeText, [string]$Result.Error) -ForegroundColor Yellow
}

$settings = Read-JsonFile $SettingsPath
if ($null -eq $settings -or -not $settings.PSObject.Properties['tornApiKey'] -or [string]::IsNullOrWhiteSpace([string]$settings.tornApiKey)) {
    Write-Host 'No Torn API key is present in config\settings.local.json.' -ForegroundColor Red
    exit 1
}
$apiKey = [string]$settings.tornApiKey
$travelMode = if ($settings.PSObject.Properties['travelMode'] -and -not [string]::IsNullOrWhiteSpace([string]$settings.travelMode)) { [string]$settings.travelMode } else { 'airstrip' }

Write-Host 'Travel Assistant - effective capacity probe' -ForegroundColor Cyan
Write-Host 'API KEY: PRESENT (not displayed)'
Write-Host ('Selected travel mode: {0}' -f $travelMode)
Write-Host ''

$basic = Invoke-TornProfileJson -Uri 'https://api.torn.com/v2/user/basic?comment=TravelAssistantCapacityProbe' -ApiKey $apiKey
if ($basic.Success) {
    $row = if ($basic.Payload.PSObject.Properties['profile']) { $basic.Payload.profile } else { $null }
    if ($null -ne $row) {
        $name = if ($row.PSObject.Properties['name']) { [string]$row.name } else { '(unknown)' }
        $id = if ($row.PSObject.Properties['id']) { [string]$row.id } else { '?' }
        Write-Host ('USER: OK - {0} [{1}]' -f $name, $id) -ForegroundColor Green
    } else { Write-Host 'USER: OK - profile object unavailable' -ForegroundColor Yellow }
} else { Write-ProbeFailure -Label 'USER' -Result $basic }

$job = Invoke-TornProfileJson -Uri 'https://api.torn.com/v2/user/job?comment=TravelAssistantCapacityProbe' -ApiKey $apiKey
if ($job.Success) {
    $row = if ($job.Payload.PSObject.Properties['job']) { $job.Payload.job } else { $null }
    if ($null -eq $row) { Write-Host 'JOB: OK - no current job/company' -ForegroundColor Green }
    elseif ([string]$row.type -eq 'company') {
        Write-Host ('JOB: OK - company "{0}" | type_id={1} | rating={2}*' -f [string]$row.name, [string]$row.type_id, [string]$row.rating) -ForegroundColor Green
    } else {
        Write-Host ('JOB: OK - starter job "{0}" | position="{1}"' -f [string]$row.name, [string]$row.position) -ForegroundColor Green
    }
} else { Write-ProbeFailure -Label 'JOB' -Result $job }

$perks = Invoke-TornProfileJson -Uri 'https://api.torn.com/v2/user/perks?comment=TravelAssistantCapacityProbe' -ApiKey $apiKey
if (-not $perks.Success) { Write-ProbeFailure -Label 'CURRENT PERKS' -Result $perks }

if ($perks.Success) {
    $capacity = Get-TornEffectiveXanaxCapacity -TravelMode $travelMode -PerksPayload $perks.Payload
    Write-Host ''
    Write-Host 'CURRENT XANAX CAPACITY' -ForegroundColor Cyan
    Write-Host ('  Base ({0}): {1}' -f $capacity.TravelMode, [int]$capacity.BaseCapacity)
    Write-Host ('  Suitcase/enhancer: +{0}  ({1})' -f [int]$capacity.SuitcaseBonus, [string]$capacity.SuitcaseSummary)
    Write-Host ('  Other active perks: +{0}' -f [int]$capacity.ActivePerkBonus)

    if (@($capacity.RecognizedPerks).Count -gt 0) {
        Write-Host '  Recognized current capacity perks:'
        foreach ($row in @($capacity.RecognizedPerks)) {
            Write-Host ('    {0}: +{1} | {2}' -f [string]$row.Bucket, [int]$row.Bonus, [string]$row.Text)
        }
    } else {
        Write-Host '  Recognized current capacity perks: none'
    }

    if (@($capacity.UnparsedPerks).Count -gt 0) {
        Write-Host '  UNPARSED travel-capacity strings:' -ForegroundColor Yellow
        foreach ($row in @($capacity.UnparsedPerks)) {
            Write-Host ('    {0}: {1}' -f [string]$row.Bucket, [string]$row.Text) -ForegroundColor Yellow
        }
    }

    if ($capacity.Resolved) {
        Write-Host ('  EFFECTIVE CAPACITY: {0} items' -f [int]$capacity.Capacity) -ForegroundColor Green
        Write-Host '  Uses current /user/perks only, so it remains available while traveling and does not need faction API permission.' -ForegroundColor DarkGreen
    } else {
        Write-Host ('  TENTATIVE CAPACITY: {0} items (not authoritative yet)' -f [int]$capacity.Capacity) -ForegroundColor Yellow
        Write-Host '  One or more current travel-capacity strings were not recognized, so Settings should not auto-save this value yet.' -ForegroundColor Yellow
    }
}

Write-Host ''
Write-Host 'Probe complete. No API key value was printed or placed on the curl command line.' -ForegroundColor Cyan
exit 0
