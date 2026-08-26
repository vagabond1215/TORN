$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

# Shared atomic-file writer for Travel Assistant state/config artifacts.
#
# Why this exists:
# - Rainmeter reads generated state continuously while PowerShell publishes updates.
# - the skin may live inside a OneDrive-synchronized directory;
# - UI preference actions can run in a separate PowerShell process from RunUpdate;
# - fixed <destination>.tmp names plus Move-Item -Force are vulnerable to stale temp
#   files, concurrent writers, and transient file-system/sync locks on Windows.
#
# Use a unique sibling temp file, a cross-process per-destination mutex, and a short
# retry loop around File.Replace/File.Move. Readers continue seeing either the old
# complete file or the new complete file; no partial destination is published.

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

function Publish-TravelAssistantAtomicTempFile {
    param(
        [Parameter(Mandatory = $true)][string]$TempPath,
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$RetryCount = 20,
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
            # The previous writer died while owning the mutex. Ownership is granted
            # to this process, so continue and repair the publication normally.
            $acquired = $true
        }
        if (-not $acquired) { throw ('Timed out waiting to publish atomic file: ' + $Path) }

        for ($attempt = 1; $attempt -le $RetryCount; $attempt++) {
            $backupPath = $null
            try {
                if (Test-Path -LiteralPath $Path) {
                    # Windows PowerShell 5.1/.NET Framework can reject a null backup
                    # argument to the four-argument File.Replace overload as an
                    # illegal path. Always supply a real unique sibling backup path.
                    $backupPath = New-TravelAssistantAtomicBackupPath -Path $Path
                    [System.IO.File]::Replace($TempPath, $Path, $backupPath, $true)
                    if (Test-Path -LiteralPath $backupPath) {
                        Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
                    }
                } else {
                    [System.IO.File]::Move($TempPath, $Path)
                }
                return
            } catch [System.IO.IOException] {
                if (-not (Test-Path -LiteralPath $Path) -and -not [string]::IsNullOrWhiteSpace($backupPath) -and (Test-Path -LiteralPath $backupPath)) {
                    try { [System.IO.File]::Move($backupPath, $Path) } catch { }
                }
                if (-not [string]::IsNullOrWhiteSpace($backupPath) -and (Test-Path -LiteralPath $backupPath)) {
                    Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
                }
                if ($attempt -ge $RetryCount) { throw }
                Start-Sleep -Milliseconds ($RetryDelayMilliseconds * [Math]::Min($attempt, 5))
            } catch [System.UnauthorizedAccessException] {
                if (-not (Test-Path -LiteralPath $Path) -and -not [string]::IsNullOrWhiteSpace($backupPath) -and (Test-Path -LiteralPath $backupPath)) {
                    try { [System.IO.File]::Move($backupPath, $Path) } catch { }
                }
                if (-not [string]::IsNullOrWhiteSpace($backupPath) -and (Test-Path -LiteralPath $backupPath)) {
                    Remove-Item -LiteralPath $backupPath -Force -ErrorAction SilentlyContinue
                }
                if ($attempt -ge $RetryCount) { throw }
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
        [int]$RetryCount = 20,
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
        [int]$RetryCount = 20,
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
        [int]$RetryCount = 20,
        [int]$RetryDelayMilliseconds = 50
    )

    $json = $Value | ConvertTo-Json -Depth $Depth
    Write-TravelAssistantAtomicText -Path $Path -Text $json -RetryCount $RetryCount -RetryDelayMilliseconds $RetryDelayMilliseconds
}
