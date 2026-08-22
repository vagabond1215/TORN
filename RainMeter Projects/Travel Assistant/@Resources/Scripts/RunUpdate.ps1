param(
    [ValidateSet('Update', 'CycleTravelMode')]
    [string]$Action = 'Update'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$Updater = Join-Path $PSScriptRoot 'UpdateTracker.ps1'
$ShadowCollector = Join-Path $PSScriptRoot 'ShadowCollector.ps1'
$LocalCatalog = Join-Path $PSScriptRoot 'LocalCatalog.ps1'
$TravelContext = Join-Path $PSScriptRoot 'TravelContext.ps1'
$VisibleItems = Join-Path $PSScriptRoot 'VisibleItems.ps1'
$ResalePriority = Join-Path $PSScriptRoot 'ResalePriority.ps1'
$ResaleQueue = Join-Path $PSScriptRoot 'ResaleQueue.ps1'
$Finalizer = Join-Path $PSScriptRoot 'FinalizeState.ps1'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$ShadowErrorFile = Join-Path $RuntimeDir 'shadow-collection-error.txt'
$LocalCatalogErrorFile = Join-Path $RuntimeDir 'local-catalog-error.txt'
$TravelContextErrorFile = Join-Path $RuntimeDir 'travel-context-error.txt'
$VisibleItemsErrorFile = Join-Path $RuntimeDir 'visible-items-error.txt'
$ResaleQueueErrorFile = Join-Path $RuntimeDir 'resale-queue-error.txt'
$GeneratedDir = Join-Path (Split-Path $PSScriptRoot -Parent) 'Generated'
$HeartbeatFile = Join-Path $GeneratedDir 'last-update.txt'
$mutex = New-Object System.Threading.Mutex($false, 'Local\TornTravelAssistantUpdater')
$acquired = $false

function Invoke-TornJsonWithCurl {
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [hashtable]$Headers,
        [int]$TimeoutSec = 15
    )

    $curl = Get-Command curl.exe -ErrorAction SilentlyContinue
    if ($null -eq $curl) { throw 'curl.exe is required for Torn Item Market requests on this Windows environment.' }
    if ($TimeoutSec -lt 1) { $TimeoutSec = 15 }
    $connectTimeout = [Math]::Min(5, $TimeoutSec)
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
        $process.StandardInput.WriteLine(('connect-timeout = {0}' -f $connectTimeout))
        $process.StandardInput.WriteLine(('max-time = {0}' -f $TimeoutSec))
        $process.StandardInput.WriteLine(('url = "{0}"' -f $Uri.Replace('"', '\"')))
        if ($null -ne $Headers) {
            foreach ($name in $Headers.Keys) {
                $value = ([string]$Headers[$name]).Replace("`r", ' ').Replace("`n", ' ')
                $header = ('{0}: {1}' -f [string]$name, $value).Replace('"', '\"')
                $process.StandardInput.WriteLine(('header = "{0}"' -f $header))
            }
        }
        $process.StandardInput.Close()
        $waitMs = [Math]::Max(2000, ($TimeoutSec + 2) * 1000)
        if (-not $process.WaitForExit($waitMs)) { try { $process.Kill() } catch { }; throw ('curl.exe exceeded the {0}s Torn request timeout.' -f $TimeoutSec) }
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        if ($process.ExitCode -ne 0) { if ([string]::IsNullOrWhiteSpace($stderr)) { $stderr = 'curl.exe returned a non-zero exit code.' }; throw ('Torn request failed: {0}' -f $stderr.Trim()) }
        if ([string]::IsNullOrWhiteSpace($stdout)) { throw 'Torn request returned an empty response.' }
        return ($stdout | ConvertFrom-Json)
    } finally { $process.Dispose() }
}

function Invoke-YataJsonNative {
    param([Parameter(Mandatory = $true)][string]$Uri, [hashtable]$Headers, [int]$TimeoutSec = 15)
    $attemptTimeout = [Math]::Min([Math]::Max($TimeoutSec, 1), 6)
    $lastError = $null
    for ($attempt = 1; $attempt -le 2; $attempt++) {
        try { return Microsoft.PowerShell.Utility\Invoke-RestMethod -Method Get -Uri $Uri -Headers $Headers -TimeoutSec $attemptTimeout }
        catch { $lastError = $_; if ($attempt -lt 2) { Start-Sleep -Milliseconds 500 } }
    }
    if ($null -ne $lastError) { throw $lastError }
    throw 'YATA live-stock request failed.'
}

function Invoke-RestMethod {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Uri, [string]$Method = 'Get', [hashtable]$Headers, [int]$TimeoutSec = 15)
    if ($Method -eq 'Get' -and $Uri -like 'https://api.torn.com/v2/market/*/itemmarket*') { return Invoke-TornJsonWithCurl -Uri $Uri -Headers $Headers -TimeoutSec $TimeoutSec }
    if ($Method -eq 'Get' -and $Uri -eq 'https://yata.yt/api/v1/travel/export/') { return Invoke-YataJsonNative -Uri $Uri -Headers $Headers -TimeoutSec $TimeoutSec }
    return Microsoft.PowerShell.Utility\Invoke-RestMethod @PSBoundParameters
}

function Write-UpdateHeartbeat {
    New-Item -ItemType Directory -Force -Path $GeneratedDir | Out-Null
    $tmp = $HeartbeatFile + '.tmp'
    $epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds().ToString([System.Globalization.CultureInfo]::InvariantCulture)
    [System.IO.File]::WriteAllText($tmp, $epoch, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $HeartbeatFile -Force
}

function Write-CompactFailure {
    param([string]$Path, [string]$Message)
    try {
        New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
        $clean = ([string]$Message).Replace("`r", ' ').Replace("`n", ' ').Trim()
        if ($clean.Length -gt 600) { $clean = $clean.Substring(0, 600) }
        [System.IO.File]::WriteAllText($Path, $clean, [System.Text.UTF8Encoding]::new($false))
    } catch { }
}

function Write-ShadowFailure { param([string]$Message) Write-CompactFailure -Path $ShadowErrorFile -Message $Message }
function Write-LocalCatalogFailure { param([string]$Message) Write-CompactFailure -Path $LocalCatalogErrorFile -Message $Message }
function Write-TravelContextFailure { param([string]$Message) Write-CompactFailure -Path $TravelContextErrorFile -Message $Message }
function Write-VisibleItemsFailure { param([string]$Message) Write-CompactFailure -Path $VisibleItemsErrorFile -Message $Message }
function Write-ResaleQueueFailure { param([string]$Message) Write-CompactFailure -Path $ResaleQueueErrorFile -Message $Message }

try {
    $acquired = $mutex.WaitOne(0)
    if (-not $acquired) { exit 0 }

    & $Updater -Action $Action
    if (-not $?) { exit 1 }

    if (Test-Path -LiteralPath $ShadowCollector) {
        try { & $ShadowCollector } catch { Write-ShadowFailure -Message $_.Exception.Message }
    }

    if (Test-Path -LiteralPath $LocalCatalog) {
        try {
            & $LocalCatalog
            if (Test-Path -LiteralPath $LocalCatalogErrorFile) { Remove-Item -LiteralPath $LocalCatalogErrorFile -Force -ErrorAction SilentlyContinue }
        } catch { Write-LocalCatalogFailure -Message $_.Exception.Message }
    }

    # Network catalog maintenance is intentionally NOT part of this heartbeat.
    # ItemMetadata.ps1 remains explicit/manual maintenance only.

    & $Finalizer
    if (-not $?) { exit 1 }

    if ($Action -eq 'Update' -and (Test-Path -LiteralPath $TravelContext)) {
        try {
            & $TravelContext
            if (Test-Path -LiteralPath $TravelContextErrorFile) {
                try {
                    $travelState = Get-Content -LiteralPath (Join-Path $RuntimeDir 'engine-state.json') -Raw | ConvertFrom-Json
                    if ($travelState.PSObject.Properties['travelContext'] -and [string]::IsNullOrWhiteSpace([string]$travelState.travelContext.lastError)) { Remove-Item -LiteralPath $TravelContextErrorFile -Force -ErrorAction SilentlyContinue }
                } catch { }
            }
        } catch { Write-TravelContextFailure -Message $_.Exception.Message }
    }

    if (Test-Path -LiteralPath $VisibleItems) {
        try {
            & $VisibleItems
            if (Test-Path -LiteralPath $VisibleItemsErrorFile) { Remove-Item -LiteralPath $VisibleItemsErrorFile -Force -ErrorAction SilentlyContinue }
        } catch { Write-VisibleItemsFailure -Message $_.Exception.Message }
    }

    Write-UpdateHeartbeat

    if ($Action -eq 'Update' -and (Test-Path -LiteralPath $ResaleQueue)) {
        try {
            # This is local-only queue policy. It never performs a request.
            if (Test-Path -LiteralPath $ResalePriority) { & $ResalePriority }
            & $ResaleQueue
            if (Test-Path -LiteralPath $ResaleQueueErrorFile) {
                try {
                    $queueState = Get-Content -LiteralPath (Join-Path $RuntimeDir 'engine-state.json') -Raw | ConvertFrom-Json
                    if ($queueState.PSObject.Properties['resaleQueue'] -and [string]$queueState.resaleQueue.status -ne 'ERROR') { Remove-Item -LiteralPath $ResaleQueueErrorFile -Force -ErrorAction SilentlyContinue }
                } catch { }
            }
        } catch { Write-ResaleQueueFailure -Message $_.Exception.Message }
    }

    exit 0
} finally {
    if ($acquired) { try { $mutex.ReleaseMutex() } catch { } }
    $mutex.Dispose()
}
