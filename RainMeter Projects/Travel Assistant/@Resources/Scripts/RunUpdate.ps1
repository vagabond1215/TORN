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
$OptimalRoute = Join-Path $PSScriptRoot 'OptimalRoute.ps1'
$FilterState = Join-Path $PSScriptRoot 'FilterState.ps1'
$ResalePriority = Join-Path $PSScriptRoot 'ResalePriority.ps1'
$ResaleQueue = Join-Path $PSScriptRoot 'ResaleQueue.ps1'
$Finalizer = Join-Path $PSScriptRoot 'FinalizeState.ps1'
$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$ShadowErrorFile = Join-Path $RuntimeDir 'shadow-collection-error.txt'
$LocalCatalogErrorFile = Join-Path $RuntimeDir 'local-catalog-error.txt'
$TravelContextErrorFile = Join-Path $RuntimeDir 'travel-context-error.txt'
$OptimalRouteErrorFile = Join-Path $RuntimeDir 'optimal-route-error.txt'
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

function Invoke-FailSoftScript {
    param(
        [string]$Path,
        [string]$ErrorPath,
        [bool]$ClearErrorOnSuccess = $true
    )
    if (-not (Test-Path -LiteralPath $Path)) { return }
    try {
        & $Path
        if ($ClearErrorOnSuccess -and (Test-Path -LiteralPath $ErrorPath)) { Remove-Item -LiteralPath $ErrorPath -Force -ErrorAction SilentlyContinue }
    } catch { Write-CompactFailure -Path $ErrorPath -Message $_.Exception.Message }
}

try {
    $acquired = $mutex.WaitOne(0)
    if (-not $acquired) { exit 0 }

    & $Updater -Action $Action
    if (-not $?) { exit 1 }

    Invoke-FailSoftScript -Path $ShadowCollector -ErrorPath $ShadowErrorFile
    Invoke-FailSoftScript -Path $LocalCatalog -ErrorPath $LocalCatalogErrorFile

    # Legacy Xanax post-processing is retained as background compatibility data,
    # but the 0.5 minimalist UI does not use profitability statuses as route gates.
    & $Finalizer
    if (-not $?) { exit 1 }

    # TravelContext owns its diagnostic file because it catches transient API failures
    # internally while preserving the last successful destination/bar context.
    if ($Action -eq 'Update') { Invoke-FailSoftScript -Path $TravelContext -ErrorPath $TravelContextErrorFile -ClearErrorOnSuccess $false }

    # OptimalRoute is local-only. It reads retained stock/history, current bars,
    # local preferences, capacity, and cached MV. It performs no network calls.
    Invoke-FailSoftScript -Path $OptimalRoute -ErrorPath $OptimalRouteErrorFile

    if (Test-Path -LiteralPath $FilterState) { try { & $FilterState } catch { } }

    # User-visible freshness is committed before the lower-priority broad market queue.
    Write-UpdateHeartbeat

    if ($Action -eq 'Update' -and (Test-Path -LiteralPath $ResaleQueue)) {
        try {
            if (Test-Path -LiteralPath $ResalePriority) { & $ResalePriority }
            & $ResaleQueue
            if (Test-Path -LiteralPath $ResaleQueueErrorFile) {
                try {
                    $queueState = Get-Content -LiteralPath (Join-Path $RuntimeDir 'engine-state.json') -Raw | ConvertFrom-Json
                    if ($queueState.PSObject.Properties['resaleQueue'] -and [string]$queueState.resaleQueue.status -ne 'ERROR') { Remove-Item -LiteralPath $ResaleQueueErrorFile -Force -ErrorAction SilentlyContinue }
                } catch { }
            }
        } catch { Write-CompactFailure -Path $ResaleQueueErrorFile -Message $_.Exception.Message }
    }

    exit 0
} finally {
    if ($acquired) { try { $mutex.ReleaseMutex() } catch { } }
    $mutex.Dispose()
}
