$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$SettingsPath = Join-Path $ProjectRoot 'config\settings.local.json'

function Read-JsonFile {
    param([Parameter(Mandatory = $true)][string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Get-ApiErrorText {
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

function Invoke-TornJson {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$ApiKey,
        [int]$TimeoutSec = 8
    )

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -eq $curl) { throw 'curl.exe is required for this probe on the target Windows environment.' }
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
            $message = Get-ApiErrorText -Payload $payload
            if ([string]::IsNullOrWhiteSpace($message)) { $message = 'HTTP request failed.' }
            return [pscustomobject]@{ Success = $false; HttpStatus = $status; Payload = $payload; Error = $message }
        }

        if ($null -eq $payload) { throw 'Torn returned HTTP success but the JSON response could not be parsed.' }
        return [pscustomobject]@{ Success = $true; HttpStatus = $status; Payload = $payload; Error = '' }
    } finally {
        $process.Dispose()
    }
}

function Write-ProbeFailure {
    param([string]$Label, [object]$Result)
    Write-Host ('{0}: UNAVAILABLE (HTTP {1}) - {2}' -f $Label, [int]$Result.HttpStatus, [string]$Result.Error) -ForegroundColor Yellow
}

function Get-FactionUpgradeRows {
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

$settings = Read-JsonFile $SettingsPath
if ($null -eq $settings -or -not $settings.PSObject.Properties['tornApiKey'] -or [string]::IsNullOrWhiteSpace([string]$settings.tornApiKey)) {
    Write-Host 'No Torn API key is present in config\settings.local.json.' -ForegroundColor Red
    exit 1
}
$apiKey = [string]$settings.tornApiKey

Write-Host 'Travel Assistant - Torn profile probe' -ForegroundColor Cyan
Write-Host 'API KEY: PRESENT (not displayed)'
Write-Host ''

$basic = Invoke-TornJson -Uri 'https://api.torn.com/v2/user/basic?comment=TravelAssistantProfileProbe' -ApiKey $apiKey
if ($basic.Success) {
    $row = $basic.Payload.basic
    if ($null -ne $row) {
        $name = if ($row.PSObject.Properties['name']) { [string]$row.name } else { '(unknown)' }
        $id = if ($row.PSObject.Properties['id']) { [string]$row.id } else { '?' }
        $level = if ($row.PSObject.Properties['level']) { [string]$row.level } else { '?' }
        Write-Host ('BASIC: OK - {0} [{1}], level {2}' -f $name, $id, $level) -ForegroundColor Green
    } else {
        Write-Host 'BASIC: OK' -ForegroundColor Green
    }
} else { Write-ProbeFailure -Label 'BASIC' -Result $basic }

$job = Invoke-TornJson -Uri 'https://api.torn.com/v2/user/job?comment=TravelAssistantProfileProbe' -ApiKey $apiKey
if ($job.Success) {
    $row = $job.Payload.job
    if ($null -eq $row) {
        Write-Host 'JOB: OK - no current job/company' -ForegroundColor Green
    } elseif ([string]$row.type -eq 'company') {
        Write-Host ('JOB: OK - company "{0}" | type_id={1} | rating={2}* | position="{3}" | days={4}' -f [string]$row.name, [string]$row.type_id, [string]$row.rating, [string]$row.position, [string]$row.days_in_company) -ForegroundColor Green
    } else {
        Write-Host ('JOB: OK - starter job "{0}" | position="{1}"' -f [string]$row.name, [string]$row.position) -ForegroundColor Green
    }
} else { Write-ProbeFailure -Label 'JOB' -Result $job }

$perks = Invoke-TornJson -Uri 'https://api.torn.com/v2/user/perks?comment=TravelAssistantProfileProbe' -ApiKey $apiKey
if ($perks.Success) {
    Write-Host 'PERKS: OK' -ForegroundColor Green
    $pattern = '(?i)travel|abroad|business|flight|flying|capacity|carry|destination|flower|plush|fee|ticket|stock'
    $matches = New-Object System.Collections.Generic.List[string]
    if ($perks.Payload.PSObject.Properties['perks'] -and $null -ne $perks.Payload.perks) {
        foreach ($bucket in @('job','faction')) {
            if (-not $perks.Payload.perks.PSObject.Properties[$bucket]) { continue }
            foreach ($text in @($perks.Payload.perks.$bucket)) {
                if (-not [string]::IsNullOrWhiteSpace([string]$text) -and [string]$text -match $pattern) {
                    $matches.Add(('{0}: {1}' -f $bucket, [string]$text))
                }
            }
        }
    }
    if ($matches.Count -eq 0) {
        Write-Host '  No travel-related job/faction perk strings matched the probe filter.'
    } else {
        foreach ($text in $matches) { Write-Host ('  ' + $text) }
    }
} else { Write-ProbeFailure -Label 'PERKS' -Result $perks }

$faction = Invoke-TornJson -Uri 'https://api.torn.com/v2/faction/upgrades?comment=TravelAssistantProfileProbe' -ApiKey $apiKey
if ($faction.Success) {
    Write-Host 'FACTION UPGRADES: OK' -ForegroundColor Green
    $pattern = '(?i)travel|excursion|abroad|flight|flying|capacity|carry|fee'
    $matches = @(Get-FactionUpgradeRows -Payload $faction.Payload | Where-Object {
        (([string]$_.name + ' ' + [string]$_.ability) -match $pattern)
    })
    if ($matches.Count -eq 0) {
        Write-Host '  No travel-related faction upgrade names/abilities matched the probe filter.'
    } else {
        foreach ($row in $matches) {
            Write-Host ('  {0} | level {1} | {2}' -f [string]$row.name, [string]$row.level, [string]$row.ability)
        }
    }
} else {
    Write-ProbeFailure -Label 'FACTION UPGRADES' -Result $faction
    Write-Host '  This endpoint specifically requires faction API access permission.' -ForegroundColor DarkYellow
}

Write-Host ''
Write-Host 'Probe complete. No API key value was printed or placed on the curl command line.' -ForegroundColor Cyan
exit 0
