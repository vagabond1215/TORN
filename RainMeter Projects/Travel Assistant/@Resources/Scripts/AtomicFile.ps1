$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# Shared atomic-file writer for Travel Assistant state/config artifacts.
#
# Rainmeter and other Windows processes can briefly hold generated files open while
# a PowerShell update publishes the next complete generation. PowerShell wraps
# exceptions from static .NET calls such as File.Replace in MethodInvocationException,
# so retry classification must walk InnerException rather than catch IOException only.
#
# State readers that run inside the updater must also grant FileShare.Delete. Windows
# File.Replace needs delete/rename sharing on the destination; a short read that omits
# that share flag can otherwise make the updater block its own atomic publication.
#
# The main updater can isolate all intermediate state mutations by setting
# TORN_TRAVEL_STATE_KV to a private build file. Standalone scripts keep using the
# generated Rainmeter state when no override is present.

function Get-TravelAssistantStateFilePath {
    param([Parameter(Mandatory = $true)][string]$ProjectRoot)

    if (-not [string]::IsNullOrWhiteSpace([string]$env:TORN_TRAVEL_STATE_KV)) {
        return [System.IO.Path]::GetFullPath([string]$env:TORN_TRAVEL_STATE_KV)
    }
    return (Join-Path $ProjectRoot '@Resources\Generated\state.kv')
}

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

function Open-TravelAssistantSharedReadStream {
    param([Parameter(Mandatory = $true)][string]$Path)

    $shareValue = ([int][System.IO.FileShare]::ReadWrite -bor [int][System.IO.FileShare]::Delete)
    $share = [System.IO.FileShare]$shareValue
    return [System.IO.File]::Open(
        $Path,
        [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read,
        $share
    )
}

function Read-TravelAssistantSharedText {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) { return '' }
    $stream = $null
    $reader = $null
    try {
        $stream = Open-TravelAssistantSharedReadStream -Path $Path
        $reader = [System.IO.StreamReader]::new($stream, [System.Text.Encoding]::UTF8, $true)
        return $reader.ReadToEnd()
    } finally {
        if ($null -ne $reader) { $reader.Dispose() }
        elseif ($null -ne $stream) { $stream.Dispose() }
    }
}

function Read-TravelAssistantSharedLines {
    param([Parameter(Mandatory = $true)][string]$Path)

    $text = Read-TravelAssistantSharedText -Path $Path
    if ([string]::IsNullOrEmpty($text)) { return [string[]]@() }
    return [string[]]([System.Text.RegularExpressions.Regex]::Split($text, "`r`n|`n|`r"))
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
