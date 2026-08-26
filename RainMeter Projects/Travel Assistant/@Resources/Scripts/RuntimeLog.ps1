$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$TravelAssistantProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$TravelAssistantLogDir = Join-Path $TravelAssistantProjectRoot 'data\runtime\logs'
$TravelAssistantLogFile = Join-Path $TravelAssistantLogDir 'travel-assistant.log'
$TravelAssistantLogRetentionDays = 7
$TravelAssistantLogMaxBytes = 262144

function Read-TravelAssistantLogTailText {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$MaxBytes = $TravelAssistantLogMaxBytes
    )
    if ($MaxBytes -lt 4096) { $MaxBytes = 4096 }

    # Get-Content -Tail scans for line boundaries and can consume a full CPU core
    # when a damaged log contains multi-megabyte lines. Read a fixed byte window so
    # maintenance cost is bounded by the configured log cap, not the current file size.
    $share = [System.IO.FileShare]::ReadWrite -bor [System.IO.FileShare]::Delete
    $stream = New-Object System.IO.FileStream($Path,[System.IO.FileMode]::Open,[System.IO.FileAccess]::Read,$share)
    try {
        $length = [long]$stream.Length
        $count = [int][Math]::Min($length,[long]$MaxBytes)
        if ($count -le 0) { return '' }
        [void]$stream.Seek(-$count,[System.IO.SeekOrigin]::End)
        $buffer = New-Object byte[] $count
        $read = 0
        while ($read -lt $count) {
            $current = $stream.Read($buffer,$read,$count-$read)
            if ($current -le 0) { break }
            $read += $current
        }
        $text = [System.Text.Encoding]::UTF8.GetString($buffer,0,$read).TrimStart([char]0xFEFF)
        if ($length -gt $count) {
            $newline = $text.IndexOf("`n")
            if ($newline -ge 0 -and $newline + 1 -lt $text.Length) { $text = $text.Substring($newline + 1) }
            else { $text = '[older log content truncated] ' + $text }
        }
        return $text
    } finally { $stream.Dispose() }
}

function Get-TravelAssistantSafeComponentName {
    param([string]$Component)
    $name = ([string]$Component).Trim()
    if ([string]::IsNullOrWhiteSpace($name)) { $name = 'general' }
    return ($name -replace '[^A-Za-z0-9_.-]','_')
}

function Protect-TravelAssistantLogText {
    param([string]$Text)
    $value = ([string]$Text).Replace("`r",' ').Replace("`n",' ').Trim()
    $value = [regex]::Replace($value,'(?i)(api[_-]?key|key|token)(\s*[=:]\s*)[^\s&;]+','$1$2<redacted>')
    if ($value.Length -gt 4000) { $value = $value.Substring(0,4000) }
    return $value
}

function Format-TravelAssistantErrorRecord {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)
    if ($null -eq $ErrorRecord) { return 'Unknown PowerShell error.' }
    $parts = @()
    if ($null -ne $ErrorRecord.Exception) { $parts += $ErrorRecord.Exception.ToString() }
    if ($null -ne $ErrorRecord.InvocationInfo) {
        $scriptName = [string]$ErrorRecord.InvocationInfo.ScriptName
        $line = [int]$ErrorRecord.InvocationInfo.ScriptLineNumber
        $position = ([string]$ErrorRecord.InvocationInfo.PositionMessage).Trim()
        if (-not [string]::IsNullOrWhiteSpace($scriptName) -or $line -gt 0) { $parts += ('source={0}:{1}' -f $scriptName,$line) }
        if (-not [string]::IsNullOrWhiteSpace($position)) { $parts += $position }
    }
    $stack = ([string]$ErrorRecord.ScriptStackTrace).Trim()
    if (-not [string]::IsNullOrWhiteSpace($stack)) { $parts += ('stack=' + $stack) }
    return ($parts -join ' | ')
}

function Invoke-TravelAssistantLogMaintenance {
    try {
        New-Item -ItemType Directory -Force -Path $TravelAssistantLogDir | Out-Null
        $cutoff = [DateTime]::UtcNow.AddDays(-$TravelAssistantLogRetentionDays)
        foreach ($marker in @(Get-ChildItem -LiteralPath $TravelAssistantLogDir -Filter '*-error.txt' -File -ErrorAction SilentlyContinue)) {
            if ($marker.LastWriteTimeUtc -lt $cutoff) { Remove-Item -LiteralPath $marker.FullName -Force -ErrorAction SilentlyContinue }
        }
        if (-not (Test-Path -LiteralPath $TravelAssistantLogFile)) { return }
        $item = Get-Item -LiteralPath $TravelAssistantLogFile -ErrorAction Stop
        if ($item.LastWriteTimeUtc -lt $cutoff) {
            Remove-Item -LiteralPath $TravelAssistantLogFile -Force -ErrorAction SilentlyContinue
            return
        }
        if ($item.Length -le $TravelAssistantLogMaxBytes) { return }
        $tail = Read-TravelAssistantLogTailText -Path $TravelAssistantLogFile -MaxBytes $TravelAssistantLogMaxBytes
        [System.IO.File]::WriteAllText($TravelAssistantLogFile,$tail,[System.Text.UTF8Encoding]::new($false))
    } catch { }
}

function Get-TravelAssistantLatestErrorPath {
    param([string]$Component)
    $safe = Get-TravelAssistantSafeComponentName $Component
    return (Join-Path $TravelAssistantLogDir ($safe + '-error.txt'))
}

function Clear-TravelAssistantLatestError {
    param([string]$Component)
    try {
        $path = Get-TravelAssistantLatestErrorPath $Component
        if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force -ErrorAction SilentlyContinue }
    } catch { }
}

function Write-TravelAssistantLog {
    param(
        [ValidateSet('ERROR','WARN','INFO')][string]$Level = 'ERROR',
        [string]$Component = 'general',
        [string]$Message
    )
    try {
        Invoke-TravelAssistantLogMaintenance
        New-Item -ItemType Directory -Force -Path $TravelAssistantLogDir | Out-Null
        $safeComponent = Get-TravelAssistantSafeComponentName $Component
        $clean = Protect-TravelAssistantLogText $Message
        $timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffZ',[System.Globalization.CultureInfo]::InvariantCulture)
        $line = ('{0} [{1}] [{2}] {3}' -f $timestamp,$Level,$safeComponent,$clean)
        Add-Content -LiteralPath $TravelAssistantLogFile -Value $line -Encoding UTF8
        if ($Level -eq 'ERROR') {
            $latest = Get-TravelAssistantLatestErrorPath $safeComponent
            [System.IO.File]::WriteAllText($latest,$line,[System.Text.UTF8Encoding]::new($false))
        }
    } catch { }
}
