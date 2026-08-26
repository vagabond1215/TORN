$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# Shared atomic-file writer for Travel Assistant state/config artifacts.
#
# Rainmeter and other Windows processes can briefly hold generated files open while
# a PowerShell update publishes the next complete generation. PowerShell wraps
# exceptions from static .NET calls such as File.Replace in MethodInvocationException,
# so retry classification must walk InnerException rather than catch IOException only.

function Get-TravelAssistantAtomicMutexName {
    param([Parameter(Mandatory = $true)][string]$Path)

    $full = [System.IO.Path]::GetFullPath($Path).ToLowerInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($full)
        $hash = $sha.ComputeHash($bytes)
        $hex = ([System.BitConverter]::ToString($hash)).Replace('-', '')
        return ('Local\TornTravelAssistantAtomic_' + $hex.Substring(0,24))
    } finally {
        $sha.Dispose()
    }
}

function New-TravelAssistantAtomicSiblingPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Suffix
    )

    $directory = Split-Path $Path -Parent
    if ([string]::IsNullOrWhiteSpace($directory)) { $directory = (Get-Location).Path }
    New-Item -ItemType Directory -Force -Path $directory | Out-Null
    $name = [System.IO.Path]::GetFileName($Path)
    return (Join-Path $directory ('.' + $name + '.' + [string]$PID + '.' + [Guid]::NewGuid().ToString('N') + $Suffix))
}

function New-TravelAssistantAtomicTempPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (New-TravelAssistantAtomicSiblingPath -Path $Path -Suffix '.tmp')
}

function New-TravelAssistantAtomicBackupPath {
    param([Parameter(Mandatory = $true)][string]$Path)
    return (New-TravelAssistantAtomicSiblingPath -Path $Path -Suffix '.bak')
}

function Test-TravelAssistantAtomicRetryableException {
    param([System.Exception]$Exception)

    $current = $Exception
    while ($null -ne $current) {
        if ($current -is [System.IO.IOException] -or $current -is [System.UnauthorizedAccessException]) {
            return $true
        }
        $current = $current.InnerException
    }
    return $false
}

function Remove-TravelAssistantAtomicBackup {
    param([string]$BackupPath)
    if (-not [string]::IsNullOrWhiteSpace([string]$BackupPath) -and (Test-Path -LiteralPath $BackupPath)) {
        Remove-Item -LiteralPath $BackupPath -Force -ErrorAction SilentlyContinue
    }
}

function Repair-TravelAssistantAtomicDestination {
    param([string]$BackupPath,[string]$Path)
    if ((-not (Test-Path -LiteralPath $Path)) -and
        -not [string]::IsNullOrWhiteSpace([string]$BackupPath) -and
        (Test-Path -LiteralPath $BackupPath)) {
        try { [System.IO.File]::Move($BackupPath, $Path) } catch { }
    }
}

function Publish-TravelAssistantAtomicTempFile {
    param(
        [Parameter(Mandatory = $true)][string]$TempPath,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$RetryCount = 40,
        [int]$RetryDelayMilliseconds = 50,
        [int]$MutexTimeoutMilliseconds = 5000
    )

    if ($RetryCount -lt 1) { $RetryCount = 1 }
    if ($RetryDelayMilliseconds -lt 1) { $RetryDelayMilliseconds = 1 }
    if ($MutexTimeoutMilliseconds -lt 100) { $MutexTimeoutMilliseconds = 100 }

    $mutex = New-Object System.Threading.Mutex($false, (Get-TravelAssistantAtomicMutexName -Path $Path))
    $acquired = $false
    try {
        try {
            $acquired = $mutex.WaitOne($MutexTimeoutMilliseconds)
        } catch [System.Threading.AbandonedMutexException] {
            $acquired = $true
        }
        if (-not $acquired) { throw ('Timed out waiting to publish atomic file: ' + $Path) }

        for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
            $backupPath = $null
            try {
                if (Test-Path -LiteralPath $Path) {
                    # Three-argument overload works across Windows PowerShell 5.1
                    # and PowerShell 7. A real sibling backup avoids null-path issues.
                    $backupPath = New-TravelAssistantAtomicBackupPath -Path $Path
                    if ([string]::IsNullOrWhiteSpace([string]$backupPath)) {
                        throw 'Atomic backup path generation returned an empty path.'
                    }
                    [System.IO.File]::Replace($TempPath, $Path, $backupPath)
                    Remove-TravelAssistantAtomicBackup -BackupPath $backupPath
                } else {
                    [System.IO.File]::Move($TempPath, $Path)
                }
                return
            } catch {
                $exception = $_.Exception
                $retryable = Test-TravelAssistantAtomicRetryableException -Exception $exception
                Repair-TravelAssistantAtomicDestination -BackupPath $backupPath -Path $Path
                Remove-TravelAssistantAtomicBackup -BackupPath $backupPath

                if (-not $retryable -or $attempt -ge $RetryCount) { throw }

                # Bounded backoff: 50,100,150,200, then 250 ms per retry by default.
                # Forty attempts gives transient readers/sync/AV locks about nine
                # seconds to clear without making a permanently locked file hang forever.
                Start-Sleep -Milliseconds ($RetryDelayMilliseconds * [Math]::Min($attempt, 5))
            }
        }
    } finally {
        if ($acquired) { try { $mutex.ReleaseMutex() } catch { } }
        $mutex.Dispose()
    }
}

function Write-TravelAssistantAtomicText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyString()][string]$Text = '',
        [int]$RetryCount = 40,
        [int]$RetryDelayMilliseconds = 50
    )

    $temp = New-TravelAssistantAtomicTempPath -Path $Path
    try {
        [System.IO.File]::WriteAllText($temp, [string]$Text, [System.Text.UTF8Encoding]::new($false))
        Publish-TravelAssistantAtomicTempFile -TempPath $temp -Path $Path -RetryCount $RetryCount -RetryDelayMilliseconds $RetryDelayMilliseconds
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Write-TravelAssistantAtomicLines {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowEmptyCollection()][string[]]$Lines = @(),
        [int]$RetryCount = 40,
        [int]$RetryDelayMilliseconds = 50
    )

    $temp = New-TravelAssistantAtomicTempPath -Path $Path
    try {
        [System.IO.File]::WriteAllLines($temp, [string[]]$Lines, [System.Text.UTF8Encoding]::new($false))
        Publish-TravelAssistantAtomicTempFile -TempPath $temp -Path $Path -RetryCount $RetryCount -RetryDelayMilliseconds $RetryDelayMilliseconds
    } finally {
        if (Test-Path -LiteralPath $temp) { Remove-Item -LiteralPath $temp -Force -ErrorAction SilentlyContinue }
    }
}

function Write-TravelAssistantAtomicJson {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object]$Value,
        [int]$Depth = 24,
        [int]$RetryCount = 40,
        [int]$RetryDelayMilliseconds = 50
    )

    $json = $Value | ConvertTo-Json -Depth $Depth
    Write-TravelAssistantAtomicText -Path $Path -Text $json -RetryCount $RetryCount -RetryDelayMilliseconds $RetryDelayMilliseconds
}
