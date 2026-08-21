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

function Get-TornFactionUpgradeRows {
    param([object]$Payload)
    $rows = New-Object System.Collections.Generic.List[object]
    if ($null -eq $Payload -or -not $Payload.PSObject.Properties['upgrades']) { return $rows.ToArray() }
    $upgrades = $Payload.upgrades

    if ($upgrades.PSObject.Properties['core'] -and $null -ne $upgrades.core -and $upgrades.core.PSObject.Properties['upgrades']) {
        foreach ($row in @($upgrades.core.upgrades)) { if ($null -ne $row) { $rows.Add($row) } }
    }
    foreach ($branchName in @('peace','war')) {
        if (-not $upgrades.PSObject.Properties[$branchName]) { continue }
        foreach ($branch in @($upgrades.$branchName)) {
            if ($null -eq $branch -or -not $branch.PSObject.Properties['upgrades']) { continue }
            foreach ($row in @($branch.upgrades)) { if ($null -ne $row) { $rows.Add($row) } }
        }
    }
    return $rows.ToArray()
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

    $typeId = 0
    if ($job.PSObject.Properties['type_id']) { $typeId = [int]$job.type_id }
    $rating = 0
    if ($job.PSObject.Properties['rating']) { $rating = [int]$job.rating }
    if ($rating -lt 0) { $rating = 0 }
    if ($rating -gt 10) { $rating = 10 }

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

    $rows = @(Get-TornFactionUpgradeRows -Payload $FactionPayload)
    $capacityLevel = 0
    $costLevel = 0

    foreach ($row in $rows) {
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

    if ($capacityLevel -lt 0) { $capacityLevel = 0 }
    if ($capacityLevel -gt 10) { $capacityLevel = 10 }
    if ($costLevel -lt 0) { $costLevel = 0 }
    if ($costLevel -gt 5) { $costLevel = 5 }

    return [pscustomobject]@{
        Resolved = $true
        ExcursionLevel = $capacityLevel
        TravelCostLevel = $costLevel
        Summary = ('Excursion {0}/10, Travel Cost {1}/5' -f $capacityLevel, $costLevel)
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

    $company = $null
    if ($jobResult.Success) {
        $company = Get-TornCompanyTravelProfile -JobPayload $jobResult.Payload -PerksConfig $PerksConfig
    } else {
        $company = [pscustomobject]@{ Resolved = $false; CompanyType = ''; CompanyStars = 0; Summary = ('Job unavailable: {0}' -f [string]$jobResult.Error) }
    }

    $faction = $null
    if ($factionResult.Success) {
        $faction = Get-TornFactionTravelProfile -FactionPayload $factionResult.Payload
    } else {
        $faction = [pscustomobject]@{ Resolved = $false; ExcursionLevel = 0; TravelCostLevel = 0; Summary = ('Faction upgrades unavailable: {0}' -f [string]$factionResult.Error) }
    }

    return [pscustomobject]@{
        CompanyResolved = [bool]$company.Resolved
        CompanyType = [string]$company.CompanyType
        CompanyStars = [int]$company.CompanyStars
        CompanySummary = [string]$company.Summary
        FactionResolved = [bool]$faction.Resolved
        FactionExcursionLevel = [int]$faction.ExcursionLevel
        FactionTravelCostLevel = [int]$faction.TravelCostLevel
        FactionSummary = [string]$faction.Summary
    }
}
