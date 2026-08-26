param(
    [ValidateRange(0,8)]
    [int]$Row = 0,
    [string]$MarketKey = ''
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$runtimeLog = Join-Path $PSScriptRoot 'RuntimeLog.ps1'
if (Test-Path -LiteralPath $runtimeLog) { . $runtimeLog }

try {
    $inlinePrefix = 'inline_'
    if (-not [string]::IsNullOrWhiteSpace($MarketKey) -and $MarketKey.StartsWith($inlinePrefix,[System.StringComparison]::OrdinalIgnoreCase)) {
        # Legacy compatibility only. The live Rainmeter inline graph uses the dedicated
        # MeasureInlineGraph path and does not route through this popup launcher.
        $actualKey = $MarketKey.Substring($inlinePrefix.Length)
        if ($actualKey -notmatch '^[a-z0-9_]+:[1-9][0-9]*$') { throw 'Inline MarketKey must be country:itemId.' }
        $renderer = Join-Path $PSScriptRoot 'RenderInlineGraph.ps1'
        if (-not (Test-Path -LiteralPath $renderer)) { throw 'RenderInlineGraph.ps1 is missing.' }
        & $renderer -MarketKey $actualKey
        return
    }

    $hostScript = Join-Path $PSScriptRoot 'PopupHost.ps1'
    if (-not (Test-Path -LiteralPath $hostScript)) { throw 'PopupHost.ps1 is missing.' }
    if (-not [string]::IsNullOrWhiteSpace($MarketKey) -and $MarketKey -notmatch '^[a-z0-9_]+:[1-9][0-9]*$') { throw 'MarketKey must be country:itemId.' }

    $arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -STA -File "{0}" -Popup ItemViewer -Row {1}' -f $hostScript,$Row
    if (-not [string]::IsNullOrWhiteSpace($MarketKey)) { $arguments += (' -MarketKey "{0}"' -f $MarketKey) }
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = 'powershell.exe'
    $psi.Arguments = $arguments
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $process = [System.Diagnostics.Process]::Start($psi)
    if ($null -eq $process) { throw 'Failed to start item viewer popup host.' }
    $process.Dispose()
    return
} catch {
    if (Get-Command Write-TravelAssistantLog -ErrorAction SilentlyContinue) {
        Write-TravelAssistantLog -Level ERROR -Component 'popup-launcher-itemviewer' -Message (Format-TravelAssistantErrorRecord $_)
    }
    throw
}
