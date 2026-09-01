param(
    [switch]$SkipMain,
    [long]$Now = 0,
    [int]$RequestTimeoutSeconds = 5
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'CurrentCapacity.ps1')

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$BaseSettingsFile = Join-Path $ConfigDir 'settings.example.json'
$LocalSettingsFile = Join-Path $ConfigDir 'settings.local.json'
$PreferencesFile = Join-Path $RuntimeDir 'preferences.json'

function Read-CapacityJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-CapacityJsonAtomic {
    param([string]$Path,[object]$Value,[int]$Depth = 20)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $tmp = $Path + '.tmp'
    $json = $Value | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($tmp,$json,[System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Set-CapacityProperty {
    param([object]$Object,[string]$Name,[object]$Value)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { $Object | Add-Member NoteProperty $Name $Value }
    else { $property.Value = $Value }
}

function Get-CapacityApiKey {
    param([object]$Local)
    if ($null -ne $Local -and $Local.PSObject.Properties['tornApiKey'] -and -not [string]::IsNullOrWhiteSpace([string]$Local.tornApiKey)) {
        return ([string]$Local.tornApiKey).Trim()
    }
    if (-not [string]::IsNullOrWhiteSpace($env:TORN_API_KEY)) { return $env:TORN_API_KEY.Trim() }
    return ''
}

function Get-CapacityTravelMode {
    param([object]$Base,[object]$Local,[object]$Preferences)
    $mode = ''
    if ($null -ne $Base -and $Base.PSObject.Properties['travelMode']) { $mode = [string]$Base.travelMode }
    if ($null -ne $Local -and $Local.PSObject.Properties['travelMode']) { $mode = [string]$Local.travelMode }
    if ($null -ne $Preferences -and $Preferences.PSObject.Properties['travelMode']) { $mode = [string]$Preferences.travelMode }
    $mode = $mode.Trim().ToLowerInvariant()
    if ($mode -notin @('standard','airstrip','wlt','business')) { $mode = 'airstrip' }
    return $mode
}

function Invoke-TornCurrentPerks {
    param([string]$ApiKey,[int]$TimeoutSec = 5)
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -eq $curl) { throw 'curl.exe is required for Torn current-capacity refresh.' }
    $TimeoutSec = [Math]::Max(2,[Math]::Min(8,$TimeoutSec))
    $uri = 'https://api.torn.com/v2/user/perks?comment=TravelAssistantHeartbeat'
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
        $process.StandardInput.WriteLine('fail')
        $process.StandardInput.WriteLine(('connect-timeout = {0}' -f [Math]::Min(3,$TimeoutSec)))
        $process.StandardInput.WriteLine(('max-time = {0}' -f $TimeoutSec))
        $process.StandardInput.WriteLine(('url = "{0}"' -f $uri))
        $process.StandardInput.WriteLine('header = "Accept: application/json"')
        $process.StandardInput.WriteLine(('header = "Authorization: ApiKey {0}"' -f $ApiKey.Replace('"','')))
        $process.StandardInput.WriteLine('header = "User-Agent: TornTravelAssistant/0.6"')
        $process.StandardInput.Close()
        $waitMs = [Math]::Max(3000,($TimeoutSec+2)*1000)
        if (-not $process.WaitForExit($waitMs)) {
            try { $process.Kill() } catch { }
            throw ('curl.exe exceeded the {0}s Torn current-capacity timeout.' -f $TimeoutSec)
        }
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        if ($process.ExitCode -ne 0) {
            if ([string]::IsNullOrWhiteSpace($stderr)) { $stderr = 'curl.exe returned a non-zero exit code.' }
            throw ('Torn current-perks request failed: {0}' -f $stderr.Trim())
        }
        if ([string]::IsNullOrWhiteSpace($stdout)) { throw 'Torn current-perks request returned an empty response.' }
        $payload = $stdout | ConvertFrom-Json
        if ($payload.PSObject.Properties['error']) {
            $message = [string]$payload.error
            if ($null -ne $payload.error -and -not ($payload.error -is [string])) {
                foreach ($name in @('error','message','description')) {
                    if ($payload.error.PSObject.Properties[$name]) { $message = [string]$payload.error.$name; break }
                }
            }
            if ([string]::IsNullOrWhiteSpace($message)) { $message = 'Torn returned an API error response.' }
            throw $message
        }
        return $payload
    } finally { $process.Dispose() }
}

if ($SkipMain) { return }
if ($Now -le 0) { $Now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
$RequestTimeoutSeconds = [Math]::Max(2,[Math]::Min(8,$RequestTimeoutSeconds))

$base = Read-CapacityJson $BaseSettingsFile
$local = Read-CapacityJson $LocalSettingsFile
$preferences = Read-CapacityJson $PreferencesFile
if ($null -eq $local) { return }
$apiKey = Get-CapacityApiKey -Local $local
if ([string]::IsNullOrWhiteSpace($apiKey)) { return }
$mode = Get-CapacityTravelMode -Base $base -Local $local -Preferences $preferences
$payload = Invoke-TornCurrentPerks -ApiKey $apiKey -TimeoutSec $RequestTimeoutSeconds
$result = Get-TornEffectiveXanaxCapacity -TravelMode $mode -PerksPayload $payload
if (-not [bool]$result.Resolved) {
    $detail = @($result.UnparsedPerks | ForEach-Object { [string]$_.Text }) -join ' | '
    if ([string]::IsNullOrWhiteSpace($detail)) { $detail = [string]$result.PerkSummary }
    throw ('Current travel capacity could not be resolved safely: {0}' -f $detail)
}

if (-not $local.PSObject.Properties['travelProfile'] -or $null -eq $local.travelProfile) {
    $local | Add-Member NoteProperty travelProfile ([pscustomobject]@{})
}
$profile = $local.travelProfile
$generalBonus = [int]$result.SuitcaseBonus + [int]$result.ActivePerkBonus
Set-CapacityProperty -Object $profile -Name 'currentCapacityKnown' -Value $true
Set-CapacityProperty -Object $profile -Name 'currentCapacityMode' -Value $mode
Set-CapacityProperty -Object $profile -Name 'currentCapacity' -Value ([int]$result.Capacity)
Set-CapacityProperty -Object $profile -Name 'currentCapacityBonus' -Value $generalBonus
Set-CapacityProperty -Object $profile -Name 'currentCapacitySyncedAt' -Value $Now
Write-CapacityJsonAtomic -Path $LocalSettingsFile -Value $local
return
