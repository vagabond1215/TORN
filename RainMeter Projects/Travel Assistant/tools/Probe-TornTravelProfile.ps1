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
    $codeText = ''
    if ($null -ne $Result -and $Result.PSObject.Properties['ApiErrorCode'] -and [int]$Result.ApiErrorCode -gt 0) {
        $codeText = (' / Torn code {0}' -f [int]$Result.ApiErrorCode)
    }
    Write-Host ('{0}: UNAVAILABLE (HTTP {1}{2}) - {3}' -f $Label, [int]$Result.HttpStatus, $codeText, [string]$Result.Error) -ForegroundColor Yellow
}

function Get-ShapeTypeName {
    param([object]$Value)
    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return 'string' }
    if ($Value -is [System.Collections.IDictionary]) { return 'dictionary' }
    if ($Value -is [System.Collections.IEnumerable] -and -not ($Value -is [pscustomobject])) {
        try { return ('array[{0}]' -f @($Value).Count) } catch { return 'enumerable' }
    }
    return $Value.GetType().Name
}

function Write-ObjectShape {
    param([string]$Label, [object]$Value, [int]$Indent = 2)
    $pad = ' ' * $Indent
    if ($null -eq $Value) {
        Write-Host ($pad + $Label + ': null')
        return
    }

    $typeName = Get-ShapeTypeName -Value $Value
    Write-Host ($pad + $Label + ': ' + $typeName)

    if ($Value -is [pscustomobject]) {
        foreach ($property in @($Value.PSObject.Properties)) {
            Write-Host ($pad + '  .' + $property.Name + ' = ' + (Get-ShapeTypeName -Value $property.Value))
        }
    }
}

function Write-FactionBranchDiagnostic {
    param([object]$Payload, [ValidateSet('peace','war')][string]$BranchName)

    if ($null -eq $Payload -or -not $Payload.PSObject.Properties['upgrades'] -or $null -eq $Payload.upgrades) {
        Write-Host ('  {0} raw: upgrades object unavailable' -f $BranchName) -ForegroundColor Yellow
        return
    }

    $prop = $Payload.upgrades.PSObject.Properties[$BranchName]
    if ($null -eq $prop) {
        Write-Host ('  {0} raw: property missing' -f $BranchName) -ForegroundColor Yellow
        return
    }

    $branches = @($prop.Value)
    Write-Host ('  {0} raw: {1} branch(es)' -f $BranchName, $branches.Count)
    foreach ($branch in $branches) {
        if ($null -eq $branch) { continue }
        $name = if ($branch.PSObject.Properties['name']) { [string]$branch.name } else { '(unnamed)' }
        $rows = if ($branch.PSObject.Properties['upgrades']) { @($branch.upgrades) } else { @() }
        Write-Host ('    {0}: {1} upgrade row(s)' -f $name, $rows.Count)

        $interesting = @($rows | Where-Object {
            $upgradeName = if ($_.PSObject.Properties['name']) { [string]$_.name } else { '' }
            $ability = if ($_.PSObject.Properties['ability']) { [string]$_.ability } else { '' }
            $name -match '(?i)excursion|travel' -or (($upgradeName + ' ' + $ability) -match '(?i)travel|abroad|capacity|fee')
        })
        foreach ($row in $interesting) {
            $upgradeName = if ($row.PSObject.Properties['name']) { [string]$row.name } else { '(unnamed)' }
            $level = if ($row.PSObject.Properties['level']) { [string]$row.level } else { '?' }
            $ability = if ($row.PSObject.Properties['ability']) { [string]$row.ability } else { '' }
            Write-Host ('      {0} | level {1} | {2}' -f $upgradeName, $level, $ability)
        }
    }
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
    $rawState = if ($faction.Payload.PSObject.Properties['state']) { [string]$faction.Payload.state } else { '(missing)' }
    Write-Host 'FACTION UPGRADES: OK' -ForegroundColor Green
    Write-Host ('  API state: {0}' -f $rawState)
    Write-Host ('  Mode:   {0}' -f ([string]$profile.State).ToUpperInvariant())
    Write-Host ('  Active: capacity {0}/10 | cost {1}/5' -f [int]$profile.ExcursionLevel, [int]$profile.TravelCostLevel)
    Write-Host ('  Peace:  capacity {0}/10 | cost {1}/5' -f [int]$profile.PeaceExcursionLevel, [int]$profile.PeaceTravelCostLevel)
    Write-Host ('  War:    capacity {0}/10 | cost {1}/5' -f [int]$profile.WarExcursionLevel, [int]$profile.WarTravelCostLevel)

    if ([int]$profile.PeaceExcursionLevel -eq 0 -and [int]$profile.WarExcursionLevel -eq 0) {
        Write-Host '  No travel-capacity row was recognized; showing redacted response shape:' -ForegroundColor Yellow
        Write-ObjectShape -Label 'exact endpoint payload' -Value $faction.Payload
        if ($faction.Payload.PSObject.Properties['upgrades']) {
            Write-ObjectShape -Label 'exact endpoint .upgrades' -Value $faction.Payload.upgrades -Indent 4
        }
        Write-FactionBranchDiagnostic -Payload $faction.Payload -BranchName 'peace'
        Write-FactionBranchDiagnostic -Payload $faction.Payload -BranchName 'war'

        Write-Host '  Probing generic v2 faction selection shape...' -ForegroundColor DarkYellow
        $genericFaction = Invoke-TornProfileJson -Uri 'https://api.torn.com/v2/faction?selections=upgrades&comment=TravelAssistantProfileProbe' -ApiKey $apiKey
        if ($genericFaction.Success) {
            Write-ObjectShape -Label 'generic faction payload' -Value $genericFaction.Payload
            if ($genericFaction.Payload.PSObject.Properties['upgrades']) {
                Write-ObjectShape -Label 'generic faction .upgrades' -Value $genericFaction.Payload.upgrades -Indent 4
            }
        } else {
            Write-ProbeFailure -Label 'GENERIC FACTION UPGRADES' -Result $genericFaction
        }
    }
    if (-not [bool]$profile.Resolved) {
        Write-Host '  Active mode was not recognized; no active faction perks should be assumed.' -ForegroundColor Yellow
    }
} else {
    Write-ProbeFailure -Label 'FACTION UPGRADES' -Result $faction
    Write-Host '  Torn returned an API error envelope instead of faction-upgrade data. A high-access key does not necessarily imply faction API permission.' -ForegroundColor DarkYellow
}

Write-Host ''
Write-Host 'Probe complete. No API key value was printed or placed on the curl command line.' -ForegroundColor Cyan
exit 0
