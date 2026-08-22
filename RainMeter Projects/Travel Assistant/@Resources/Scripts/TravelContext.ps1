param(
    [switch]$SkipMain,
    [long]$Now = 0,
    [int]$RequestTimeoutSeconds = 5
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'
$StateKvFile = Join-Path $GeneratedDir 'state.kv'
$ErrorFile = Join-Path $RuntimeDir 'travel-context-error.txt'

function Read-TravelJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-TravelJsonAtomic {
    param([string]$Path, [object]$Value, [int]$Depth = 20)
    $dir = Split-Path $Path -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $tmp = $Path + '.tmp'
    $Value | ConvertTo-Json -Depth $Depth | Set-Content -LiteralPath $tmp -Encoding UTF8
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Read-TravelStateKv {
    param([string]$Path)
    $values = @{}
    if (-not (Test-Path -LiteralPath $Path)) { return $values }
    foreach ($line in Get-Content -LiteralPath $Path) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        $index = $line.IndexOf('=')
        if ($index -lt 1) { continue }
        $key = $line.Substring(0,$index).Trim([char]0xFEFF).Trim()
        $values[$key] = $line.Substring($index + 1).Trim()
    }
    return $values
}

function Write-TravelStateKvAtomic {
    param([hashtable]$Values, [string]$Path)
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $tmp = $Path + '.tmp'
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($key in ($Values.Keys | Sort-Object)) {
        $value = ([string]$Values[$key]).Replace("`r",' ').Replace("`n",' ')
        $lines.Add("$key=$value")
    }
    [System.IO.File]::WriteAllLines($tmp, $lines.ToArray(), [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Get-TravelDynamicProperty {
    param([object]$Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Set-TravelDynamicProperty {
    param([object]$Object, [string]$Name, [object]$Value)
    $property = $Object.PSObject.Properties[$Name]
    if ($null -eq $property) { $Object | Add-Member NoteProperty $Name $Value }
    else { $property.Value = $Value }
}

function Get-TravelDestinationText {
    param([object]$Destination)
    if ($null -eq $Destination) { return '' }
    if ($Destination -is [string]) { return ([string]$Destination).Trim() }
    foreach ($name in @('name','country','destination','label','id')) {
        $value = Get-TravelDynamicProperty $Destination $name
        if ($null -ne $value -and -not [string]::IsNullOrWhiteSpace([string]$value)) { return ([string]$value).Trim() }
    }
    return ''
}

function Resolve-TravelCountryId {
    param([string]$DestinationText, [object]$CountriesConfig)
    if ([string]::IsNullOrWhiteSpace($DestinationText) -or $null -eq $CountriesConfig) { return '' }
    $needle = $DestinationText.Trim().ToLowerInvariant()
    if ($needle -in @('torn','torn city','home')) { return '' }

    foreach ($country in @($CountriesConfig.countries)) {
        foreach ($candidate in @([string]$country.id, [string]$country.name, [string](Get-TravelDynamicProperty $country 'city'))) {
            if (-not [string]::IsNullOrWhiteSpace($candidate) -and $candidate.Trim().ToLowerInvariant() -eq $needle) { return [string]$country.id }
        }
    }

    $aliases = @{ 'uk'='united_kingdom'; 'u.k.'='united_kingdom'; 'uae'='united_arab_emirates'; 'u.a.e.'='united_arab_emirates'; 'cayman'='cayman_islands' }
    if ($aliases.ContainsKey($needle)) { return [string]$aliases[$needle] }
    return ''
}

function Get-TravelStatusState {
    param([object]$Payload)
    foreach ($candidate in @(
        (Get-TravelDynamicProperty (Get-TravelDynamicProperty $Payload 'status') 'state'),
        (Get-TravelDynamicProperty (Get-TravelDynamicProperty (Get-TravelDynamicProperty $Payload 'basic') 'status') 'state'),
        (Get-TravelDynamicProperty (Get-TravelDynamicProperty $Payload 'basic') 'state')
    )) {
        if ($null -ne $candidate -and -not [string]::IsNullOrWhiteSpace([string]$candidate)) { return [string]$candidate }
    }
    return ''
}

function Convert-TornTravelContext {
    param([object]$Payload, [object]$CountriesConfig, [long]$NowEpoch)

    $travel = Get-TravelDynamicProperty $Payload 'travel'
    if ($null -eq $travel) { $travel = $Payload }
    $destinationText = Get-TravelDestinationText (Get-TravelDynamicProperty $travel 'destination')
    $destinationCountryId = Resolve-TravelCountryId -DestinationText $destinationText -CountriesConfig $CountriesConfig
    $method = [string](Get-TravelDynamicProperty $travel 'method')
    $departedAt = 0L; $arrivalAt = 0L; $timeLeft = 0L
    foreach ($pair in @(@('departed_at','departedAt'),@('arrival_at','arrivalAt'),@('time_left','timeLeft'))) {
        $value = Get-TravelDynamicProperty $travel $pair[0]
        if ($null -eq $value) { $value = Get-TravelDynamicProperty $travel $pair[1] }
        if ($null -ne $value) {
            if ($pair[0] -eq 'departed_at') { $departedAt = [long]$value }
            elseif ($pair[0] -eq 'arrival_at') { $arrivalAt = [long]$value }
            else { $timeLeft = [long]$value }
        }
    }

    $statusState = Get-TravelStatusState -Payload $Payload
    $statusLower = $statusState.Trim().ToLowerInvariant()
    $destLower = $destinationText.Trim().ToLowerInvariant()
    $state = 'home'; $filterActive = $false
    if ($destLower -in @('torn','torn city','home')) {
        $state = 'returning'
    } elseif (-not [string]::IsNullOrWhiteSpace($destinationCountryId)) {
        $filterActive = $true
        if ($timeLeft -gt 0 -or $arrivalAt -gt $NowEpoch -or $statusLower -like '*travel*') { $state = 'traveling' }
        elseif ($statusLower -like '*abroad*') { $state = 'abroad' }
        else { $state = 'foreign' }
    } elseif ($statusLower -like '*travel*') {
        $state = 'traveling_unknown'
    } elseif ($statusLower -like '*abroad*') {
        $state = 'abroad_unknown'
    }

    return [pscustomobject]@{ state=$state; destination=$destinationText; destinationCountryId=$destinationCountryId; filterActive=[bool]$filterActive; method=$method; departedAt=$departedAt; arrivalAt=$arrivalAt; timeLeft=$timeLeft; statusState=$statusState }
}

function Get-TravelApiKey {
    $local = Read-TravelJson (Join-Path $ConfigDir 'settings.local.json')
    if ($null -ne $local -and $local.PSObject.Properties['tornApiKey'] -and -not [string]::IsNullOrWhiteSpace([string]$local.tornApiKey)) { return [string]$local.tornApiKey }
    if (-not [string]::IsNullOrWhiteSpace($env:TORN_API_KEY)) { return [string]$env:TORN_API_KEY }
    return ''
}

function Invoke-TornTravelCurl {
    param([string]$ApiKey, [int]$TimeoutSec = 5)
    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -eq $curl) { throw 'curl.exe is required for Torn travel-context sync.' }
    if ($TimeoutSec -lt 2) { $TimeoutSec = 2 }
    if ($TimeoutSec -gt 8) { $TimeoutSec = 8 }
    $uri = 'https://api.torn.com/v2/user?selections=travel,basic'
    $connectTimeout = [Math]::Min(3,$TimeoutSec)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $curl.Source; $psi.Arguments = '-q --config -'; $psi.UseShellExecute = $false; $psi.CreateNoWindow = $true
    $psi.RedirectStandardInput = $true; $psi.RedirectStandardOutput = $true; $psi.RedirectStandardError = $true
    $process = New-Object System.Diagnostics.Process; $process.StartInfo = $psi
    try {
        if (-not $process.Start()) { throw 'Failed to start curl.exe.' }
        $process.StandardInput.WriteLine('silent'); $process.StandardInput.WriteLine('show-error'); $process.StandardInput.WriteLine('fail')
        $process.StandardInput.WriteLine(('connect-timeout = {0}' -f $connectTimeout)); $process.StandardInput.WriteLine(('max-time = {0}' -f $TimeoutSec))
        $process.StandardInput.WriteLine(('url = "{0}"' -f $uri)); $process.StandardInput.WriteLine('header = "Accept: application/json"')
        $process.StandardInput.WriteLine(('header = "Authorization: ApiKey {0}"' -f $ApiKey.Replace('"','')))
        $process.StandardInput.WriteLine('header = "User-Agent: TornTravelAssistant/0.3"'); $process.StandardInput.Close()
        $waitMs = [Math]::Max(3000,($TimeoutSec+2)*1000)
        if (-not $process.WaitForExit($waitMs)) { try { $process.Kill() } catch { }; throw ('curl.exe exceeded the {0}s Torn travel-context timeout.' -f $TimeoutSec) }
        $stdout = $process.StandardOutput.ReadToEnd(); $stderr = $process.StandardError.ReadToEnd()
        if ($process.ExitCode -ne 0) { if ([string]::IsNullOrWhiteSpace($stderr)) { $stderr='curl.exe returned a non-zero exit code.' }; throw ('Torn travel-context request failed: {0}' -f $stderr.Trim()) }
        if ([string]::IsNullOrWhiteSpace($stdout)) { throw 'Torn travel-context request returned an empty response.' }
        return ($stdout | ConvertFrom-Json)
    } finally { $process.Dispose() }
}

function Write-TravelContextError {
    param([string]$Message)
    New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
    $clean = ([string]$Message).Replace("`r",' ').Replace("`n",' ').Trim(); if ($clean.Length -gt 600) { $clean=$clean.Substring(0,600) }
    [System.IO.File]::WriteAllText($ErrorFile,$clean,[System.Text.UTF8Encoding]::new($false))
}

function Project-TravelContextToState {
    param([object]$Context)
    $state = Read-TravelStateKv $StateKvFile
    if ($state.Count -eq 0 -or $null -eq $Context) { return }
    $state['TravelState'] = [string](Get-TravelDynamicProperty $Context 'state')
    $state['TravelDestination'] = [string](Get-TravelDynamicProperty $Context 'destination')
    $state['TravelDestinationCountryId'] = [string](Get-TravelDynamicProperty $Context 'destinationCountryId')
    $state['TravelFilterActive'] = if ([bool](Get-TravelDynamicProperty $Context 'filterActive')) { 1 } else { 0 }
    $state['TravelMethod'] = [string](Get-TravelDynamicProperty $Context 'method')
    $state['TravelDepartedAt'] = [long](Get-TravelDynamicProperty $Context 'departedAt')
    $state['TravelArrivalAt'] = [long](Get-TravelDynamicProperty $Context 'arrivalAt')
    $state['TravelTimeLeft'] = [long](Get-TravelDynamicProperty $Context 'timeLeft')
    $state['TravelContextLastSuccessAt'] = [long](Get-TravelDynamicProperty $Context 'lastSuccessAt')
    Write-TravelStateKvAtomic -Values $state -Path $StateKvFile
}

if ($SkipMain) { return }
if ($Now -le 0) { $Now=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds() }
if ($RequestTimeoutSeconds -lt 2) { $RequestTimeoutSeconds=2 }; if ($RequestTimeoutSeconds -gt 8) { $RequestTimeoutSeconds=8 }
$engineState = Read-TravelJson $EngineStateFile; if ($null -eq $engineState) { return }
$countries = Read-TravelJson (Join-Path $ConfigDir 'countries.json'); if ($null -eq $countries) { return }
if (-not $engineState.PSObject.Properties['travelContext']) {
    $engineState | Add-Member NoteProperty travelContext ([pscustomobject]@{ state='unknown'; destination=''; destinationCountryId=''; filterActive=$false; method=''; departedAt=0; arrivalAt=0; timeLeft=0; statusState=''; lastAttemptAt=0; lastSuccessAt=0; lastErrorAt=0; lastError='' })
}
$contextState=$engineState.travelContext; Set-TravelDynamicProperty $contextState 'lastAttemptAt' $Now
$apiKey=Get-TravelApiKey
if ([string]::IsNullOrWhiteSpace($apiKey)) {
    Set-TravelDynamicProperty $contextState 'lastErrorAt' $Now; Set-TravelDynamicProperty $contextState 'lastError' 'No local Torn API key is available for travel-context sync.'
    Write-TravelJsonAtomic -Path $EngineStateFile -Value $engineState; Project-TravelContextToState -Context $contextState; return
}
try {
    $payload=Invoke-TornTravelCurl -ApiKey $apiKey -TimeoutSec $RequestTimeoutSeconds
    $normalized=Convert-TornTravelContext -Payload $payload -CountriesConfig $countries -NowEpoch $Now
    foreach ($name in @('state','destination','destinationCountryId','filterActive','method','departedAt','arrivalAt','timeLeft','statusState')) { Set-TravelDynamicProperty $contextState $name (Get-TravelDynamicProperty $normalized $name) }
    Set-TravelDynamicProperty $contextState 'lastSuccessAt' $Now; Set-TravelDynamicProperty $contextState 'lastErrorAt' 0; Set-TravelDynamicProperty $contextState 'lastError' ''
    if (Test-Path -LiteralPath $ErrorFile) { Remove-Item -LiteralPath $ErrorFile -Force -ErrorAction SilentlyContinue }
} catch {
    $message=([string]$_.Exception.Message).Replace("`r",' ').Replace("`n",' ').Trim()
    Set-TravelDynamicProperty $contextState 'lastErrorAt' $Now; Set-TravelDynamicProperty $contextState 'lastError' $message
    try { Write-TravelContextError -Message $message } catch { }
}
Write-TravelJsonAtomic -Path $EngineStateFile -Value $engineState
Project-TravelContextToState -Context $contextState
