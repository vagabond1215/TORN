$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

function Get-TornProfileApiErrorText {
    param([object]$Payload)
    if ($null -eq $Payload) { return '' }
    if ($Payload.PSObject.Properties['error']) {
        $err = $Payload.error
        if ($err -is [string]) { return [string]$err }
        foreach ($name in @('error','message','description')) {
            if ($null -ne $err -and $err.PSObject.Properties[$name]) { return [string]$err.$name }
        }
    }
    foreach ($name in @('message','description')) {
        if ($Payload.PSObject.Properties[$name]) { return [string]$Payload.$name }
    }
    return ''
}

function Invoke-TornProfileJson {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$ApiKey,
        [int]$TimeoutSec = 8
    )

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -eq $curl) { throw 'curl.exe is required for Torn profile sync on this Windows environment.' }
    if ($TimeoutSec -lt 1) { $TimeoutSec = 8 }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $curl.Source
    $psi.Arguments = '-q --config -'
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $psi

    try {
        if (-not $process.Start()) { throw 'Failed to start curl.exe.' }

        $process.StandardInput.WriteLine('silent')
        $process.StandardInput.WriteLine('show-error')
        $process.StandardInput.WriteLine(('connect-timeout = {0}' -f [Math]::Min(5, $TimeoutSec)))
        $process.StandardInput.WriteLine(('max-time = {0}' -f $TimeoutSec))
        $process.StandardInput.WriteLine(('url = "{0}"' -f $Uri.Replace('"', '\"')))
        $process.StandardInput.WriteLine('header = "Accept: application/json"')
        $safeKey = $ApiKey.Replace("`r", '').Replace("`n", '')
        $process.StandardInput.WriteLine(('header = "Authorization: ApiKey {0}"' -f $safeKey.Replace('"', '\"')))
        $process.StandardInput.WriteLine('write-out = "\n__TRAVEL_ASSISTANT_HTTP__:%{http_code}"')
        $process.StandardInput.Close()

        $waitMs = [Math]::Max(2000, ($TimeoutSec + 2) * 1000)
        if (-not $process.WaitForExit($waitMs)) {
            try { $process.Kill() } catch { }
            throw ('Torn request exceeded the {0}s timeout.' -f $TimeoutSec)
        }

        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        if ($process.ExitCode -ne 0) {
            $detail = if ([string]::IsNullOrWhiteSpace($stderr)) { 'curl.exe returned a non-zero exit code.' } else { $stderr.Trim() }
            throw ('Torn transport failed: {0}' -f $detail)
        }

        $marker = [regex]::Match($stdout, '(?s)^(.*)\r?\n__TRAVEL_ASSISTANT_HTTP__:(\d{3})\s*$')
        if (-not $marker.Success) { throw 'Torn response did not include a parseable HTTP status marker.' }

        $body = $marker.Groups[1].Value
        $status = [int]$marker.Groups[2].Value
        $payload = $null
        if (-not [string]::IsNullOrWhiteSpace($body)) {
            try { $payload = $body | ConvertFrom-Json } catch { }
        }

        if ($status -lt 200 -or $status -ge 300) {
            $message = Get-TornProfileApiErrorText -Payload $payload
            if ([string]::IsNullOrWhiteSpace($message)) { $message = 'HTTP request failed.' }
            return [pscustomobject]@{ Success = $false; HttpStatus = $status; Payload = $payload; Error = $message }
        }

        if ($null -eq $payload) { throw 'Torn returned HTTP success but the JSON response could not be parsed.' }
        return [pscustomobject]@{ Success = $true; HttpStatus = $status; Payload = $payload; Error = '' }
    } finally {
        $process.Dispose()
    }
}

function Get-TornFactionState {
    param([object]$Payload)
    if ($null -eq $Payload -or -not $Payload.PSObject.Properties['upgrades'] -or $null -eq $Payload.upgrades) { return 'unknown' }
    $upgrades = $Payload.upgrades
    if ($upgrades.PSObject.Properties['state']) {
        $state = ([string]$upgrades.state).ToLowerInvariant()
        if ($state -in @('peace','war')) { return $state }
    }
    return 'unknown'
}

function Get-TornFactionCoreRows {
    param([object]$Payload)
    $rows = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Payload -or -not $Payload.PSObject.Properties['upgrades'] -or $null -eq $Payload.upgrades) { return $rows.ToArray() }
    $upgrades = $Payload.upgrades
    if ($upgrades.PSObject.Properties['core'] -and $null -ne $upgrades.core -and $upgrades.core.PSObject.Properties['upgrades']) {
        foreach ($row in @($upgrades.core.upgrades)) { if ($null -ne $row) { $rows.Add($row) } }
    }
    return $rows.ToArray()
}

function Get-TornFactionBranchRows {
    param([object]$Payload, [ValidateSet('peace','war')][string]$BranchName)
    $rows = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Payload -or -not $Payload.PSObject.Properties['upgrades'] -or $null -eq $Payload.upgrades) { return $rows.ToArray() }
    $upgrades = $Payload.upgrades
    if (-not $upgrades.PSObject.Properties[$BranchName]) { return $rows.ToArray() }
    foreach ($branch in @($upgrades.$BranchName)) {
        if ($null -eq $branch -or -not $branch.PSObject.Properties['upgrades']) { continue }
        foreach ($row in @($branch.upgrades)) { if ($null -ne $row) { $rows.Add($row) } }
    }
    return $rows.ToArray()
}

function Get-TornFactionTravelLevelsFromRows {
    param([object[]]$Rows)
    $capacityLevel = 0
    $costLevel = 0
    foreach ($row in @($Rows)) {
        if ($null -eq $row) { continue }
        $name = if ($row.PSObject.Properties['name']) { [string]$row.name } else { '' }
        $ability = if ($row.PSObject.Properties['ability']) { [string]$row.ability } else { '' }
        $level = if ($row.PSObject.Properties['level']) { [int]$row.level } else { 0 }
        if ($name -match '(?i)^Travel capacity$' -or $ability -match '(?i)travel capacity') {
            if ($level -gt $capacityLevel) { $capacityLevel = $level }
        }
        if ($name -match '(?i)^Travel cost$' -or $ability -match '(?i)travel.*fee') {
            if ($level -gt $costLevel) { $costLevel = $level }
        }
    }
    $capacityLevel = [Math]::Max(0, [Math]::Min(10, $capacityLevel))
    $costLevel = [Math]::Max(0, [Math]::Min(5, $costLevel))
    return [pscustomobject]@{ ExcursionLevel = $capacityLevel; TravelCostLevel = $costLevel }
}

function Get-TornCompanyTravelProfile {
    param([object]$JobPayload, [object]$PerksConfig)

    if ($null -eq $JobPayload -or -not $JobPayload.PSObject.Properties['job']) {
        return [pscustomobject]@{ Resolved = $false; CompanyType = ''; CompanyStars = 0; Summary = 'Job response did not contain a job object.' }
    }

    $job = $JobPayload.job
    if ($null -eq $job) {
        return [pscustomobject]@{ Resolved = $true; CompanyType = 'none'; CompanyStars = 0; Summary = 'No current job/company.' }
    }

    if ([string]$job.type -ne 'company') {
        $label = if ($job.PSObject.Properties['name']) { [string]$job.name } else { 'starter job' }
        return [pscustomobject]@{ Resolved = $true; CompanyType = 'none'; CompanyStars = 0; Summary = ('Starter job: {0}' -f $label) }
    }

    $typeId = if ($job.PSObject.Properties['type_id']) { [int]$job.type_id } else { 0 }
    $rating = if ($job.PSObject.Properties['rating']) { [int]$job.rating } else { 0 }
    $rating = [Math]::Max(0, [Math]::Min(10, $rating))

    $match = @($PerksConfig.companies | Where-Object {
        $_.PSObject.Properties['tornCompanyTypeId'] -and $null -ne $_.tornCompanyTypeId -and [int]$_.tornCompanyTypeId -eq $typeId
    } | Select-Object -First 1)

    if ($match.Count -eq 0) {
        return [pscustomobject]@{ Resolved = $false; CompanyType = ''; CompanyStars = $rating; Summary = ('Company type_id {0} is not mapped to a Travel Assistant travel company.' -f $typeId) }
    }

    return [pscustomobject]@{
        Resolved = $true
        CompanyType = [string]$match[0].id
        CompanyStars = $rating
        Summary = ('{0} ({1}*)' -f [string]$match[0].label, $rating)
    }
}

function Get-TornFactionTravelProfile {
    param([object]$FactionPayload)

    $state = Get-TornFactionState -Payload $FactionPayload
    $coreRows = @(Get-TornFactionCoreRows -Payload $FactionPayload)
    $peaceRows = @($coreRows) + @(Get-TornFactionBranchRows -Payload $FactionPayload -BranchName 'peace')
    $warRows = @($coreRows) + @(Get-TornFactionBranchRows -Payload $FactionPayload -BranchName 'war')
    $peace = Get-TornFactionTravelLevelsFromRows -Rows $peaceRows
    $war = Get-TornFactionTravelLevelsFromRows -Rows $warRows

    $active = $null
    if ($state -eq 'peace') { $active = $peace }
    elseif ($state -eq 'war') { $active = $war }

    $resolved = ($null -ne $active)
    $activeExcursion = if ($resolved) { [int]$active.ExcursionLevel } else { 0 }
    $activeCost = if ($resolved) { [int]$active.TravelCostLevel } else { 0 }
    $summary = if ($resolved) {
        ('Mode {0}: active {1}/10 capacity, {2}/5 cost | Peace {3}/10,{4}/5 | War {5}/10,{6}/5' -f $state.ToUpperInvariant(), $activeExcursion, $activeCost, [int]$peace.ExcursionLevel, [int]$peace.TravelCostLevel, [int]$war.ExcursionLevel, [int]$war.TravelCostLevel)
    } else {
        ('Faction mode unknown | Peace {0}/10,{1}/5 | War {2}/10,{3}/5' -f [int]$peace.ExcursionLevel, [int]$peace.TravelCostLevel, [int]$war.ExcursionLevel, [int]$war.TravelCostLevel)
    }

    return [pscustomobject]@{
        Resolved = $resolved
        State = $state
        ExcursionLevel = $activeExcursion
        TravelCostLevel = $activeCost
        PeaceExcursionLevel = [int]$peace.ExcursionLevel
        PeaceTravelCostLevel = [int]$peace.TravelCostLevel
        WarExcursionLevel = [int]$war.ExcursionLevel
        WarTravelCostLevel = [int]$war.TravelCostLevel
        Summary = $summary
    }
}

function Get-TornTravelProfileSync {
    param(
        [Parameter(Mandatory = $true)][string]$ApiKey,
        [Parameter(Mandatory = $true)][object]$PerksConfig
    )

    if ([string]::IsNullOrWhiteSpace($ApiKey)) { throw 'Enter a Torn API key before syncing.' }

    $jobResult = Invoke-TornProfileJson -Uri 'https://api.torn.com/v2/user/job?comment=TravelAssistantSettingsSync' -ApiKey $ApiKey
    $factionResult = Invoke-TornProfileJson -Uri 'https://api.torn.com/v2/faction/upgrades?comment=TravelAssistantSettingsSync' -ApiKey $ApiKey

    $company = if ($jobResult.Success) {
        Get-TornCompanyTravelProfile -JobPayload $jobResult.Payload -PerksConfig $PerksConfig
    } else {
        [pscustomobject]@{ Resolved = $false; CompanyType = ''; CompanyStars = 0; Summary = ('Job unavailable: {0}' -f [string]$jobResult.Error) }
    }

    $faction = if ($factionResult.Success) {
        Get-TornFactionTravelProfile -FactionPayload $factionResult.Payload
    } else {
        [pscustomobject]@{
            Resolved = $false; State = 'unknown'; ExcursionLevel = 0; TravelCostLevel = 0
            PeaceExcursionLevel = 0; PeaceTravelCostLevel = 0; WarExcursionLevel = 0; WarTravelCostLevel = 0
            Summary = ('Faction upgrades unavailable: {0}' -f [string]$factionResult.Error)
        }
    }

    return [pscustomobject]@{
        CompanyResolved = [bool]$company.Resolved
        CompanyType = [string]$company.CompanyType
        CompanyStars = [int]$company.CompanyStars
        CompanySummary = [string]$company.Summary
        FactionResolved = [bool]$faction.Resolved
        FactionState = [string]$faction.State
        FactionExcursionLevel = [int]$faction.ExcursionLevel
        FactionTravelCostLevel = [int]$faction.TravelCostLevel
        FactionPeaceExcursionLevel = [int]$faction.PeaceExcursionLevel
        FactionPeaceTravelCostLevel = [int]$faction.PeaceTravelCostLevel
        FactionWarExcursionLevel = [int]$faction.WarExcursionLevel
        FactionWarTravelCostLevel = [int]$faction.WarTravelCostLevel
        FactionSummary = [string]$faction.Summary
    }
}
