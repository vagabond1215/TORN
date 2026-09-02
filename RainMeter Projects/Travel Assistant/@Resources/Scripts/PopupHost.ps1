param(
    [Parameter(Mandatory=$true)]
    [ValidateSet('Filter','OptimizerSettings')]
    [string]$Popup,
    [ValidateSet('Filters','Item','Country','Category','Ignore')]
    [string]$Filter = 'Filters'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

. (Join-Path $PSScriptRoot 'RuntimeLog.ps1')

$component = 'popup-' + $Popup.ToLowerInvariant()
Clear-TravelAssistantLatestError -Component $component

try {
    switch ($Popup) {
        'Filter' {
            if ($Filter -eq 'Ignore') {
                $target = Join-Path $PSScriptRoot 'OpenFilterPopup.ps1'
                if (-not (Test-Path -LiteralPath $target)) { throw 'OpenFilterPopup.ps1 is missing.' }
                & $target -Filter 'Ignore'
            } else {
                # Item/Country/Category are retained as backward-compatible launcher
                # values, but all three now open the same staged unified panel.
                $target = Join-Path $PSScriptRoot 'OpenUnifiedFilterPopup.ps1'
                if (-not (Test-Path -LiteralPath $target)) { throw 'OpenUnifiedFilterPopup.ps1 is missing.' }
                & $target
            }
        }
        'OptimizerSettings' {
            $target = Join-Path $PSScriptRoot 'OpenOptimizerSettings.ps1'
            if (-not (Test-Path -LiteralPath $target)) { throw 'OpenOptimizerSettings.ps1 is missing.' }
            & $target
        }
    }
    Clear-TravelAssistantLatestError -Component $component
} catch {
    $detail = Format-TravelAssistantErrorRecord $_
    Write-TravelAssistantLog -Level ERROR -Component $component -Message $detail
    try {
        Add-Type -AssemblyName System.Windows.Forms
        $message = "Travel Assistant popup failed.`r`n`r`nThe error was written to:`r`n$TravelAssistantLogFile"
        [System.Windows.Forms.MessageBox]::Show($message,'Travel Assistant','OK','Error') | Out-Null
    } catch { }
    exit 1
}
