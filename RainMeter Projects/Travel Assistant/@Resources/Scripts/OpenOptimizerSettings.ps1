$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'FilterPreferences.ps1') -SkipMain
. (Join-Path $PSScriptRoot 'RuntimeLog.ps1')

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$UpdateLauncher=Join-Path $PSScriptRoot 'LaunchUpdate.ps1'
$FilterLauncher=Join-Path $PSScriptRoot 'LaunchFilterPopup.ps1'
$ProfileLauncher=Join-Path $PSScriptRoot 'LaunchSettings.ps1'
$prefs=Read-UiPreferences
$logComponent='popup-optimizersettings'

$form=New-Object System.Windows.Forms.Form
$form.Text='Travel Assistant Settings'
$form.Size=New-Object System.Drawing.Size(520,470)
$form.StartPosition='CenterScreen'
$form.FormBorderStyle='FixedDialog'
$form.MaximizeBox=$false
$form.MinimizeBox=$false
$form.BackColor=[System.Drawing.Color]::FromArgb(31,35,40)
$form.ForeColor=[System.Drawing.Color]::FromArgb(222,226,232)
$form.Font=New-Object System.Drawing.Font('Segoe UI',9)

function Add-Label([string]$Text,[int]$X,[int]$Y,[int]$W=180,[int]$H=22) {
    $l=New-Object System.Windows.Forms.Label
    $l.Text=$Text; $l.Location=New-Object System.Drawing.Point($X,$Y); $l.Size=New-Object System.Drawing.Size($W,$H)
    $l.ForeColor=[System.Drawing.Color]::FromArgb(200,205,214); $form.Controls.Add($l); return $l
}
function Add-Combo([int]$X,[int]$Y,[int]$W=150) {
    $c=New-Object System.Windows.Forms.ComboBox
    $c.DropDownStyle='DropDownList'; $c.Location=New-Object System.Drawing.Point($X,$Y); $c.Size=New-Object System.Drawing.Size($W,26)
    $c.BackColor=[System.Drawing.Color]::FromArgb(20,23,27); $c.ForeColor=[System.Drawing.Color]::FromArgb(232,235,240)
    [void]$c.Items.Add('Allowed'); [void]$c.Items.Add('Forbidden'); [void]$c.Items.Add('Limited')
    $form.Controls.Add($c); return $c
}
function Set-ComboPolicy($Combo,[string]$Policy) {
    $p=$Policy.ToLowerInvariant(); if ($p -eq 'forbidden') { $Combo.SelectedIndex=1 } elseif ($p -eq 'limited') { $Combo.SelectedIndex=2 } else { $Combo.SelectedIndex=0 }
}
function Get-ComboPolicy($Combo) {
    if ($Combo.SelectedIndex -eq 1) { return 'forbidden' }
    if ($Combo.SelectedIndex -eq 2) { return 'limited' }
    return 'allowed'
}

$title=Add-Label 'OPPORTUNITY SETTINGS' 16 14 300 28
$title.Font=New-Object System.Drawing.Font('Segoe UI Semibold',14)

$profitable=New-Object System.Windows.Forms.CheckBox
$profitable.Text='Show profitable items only'; $profitable.Location=New-Object System.Drawing.Point(18,52); $profitable.Size=New-Object System.Drawing.Size(190,24); $profitable.Checked=[bool]$prefs.showProfitableOnly; $form.Controls.Add($profitable)

$mv95=New-Object System.Windows.Forms.CheckBox
$mv95.Text='Use 95% MV profit calculation'; $mv95.Location=New-Object System.Drawing.Point(250,52); $mv95.Size=New-Object System.Drawing.Size(220,24); $mv95.Checked=[bool]$prefs.use95PercentMarketValue; $form.Controls.Add($mv95)

Add-Label 'Energy Waste' 18 98 130 | Out-Null
$energyPolicy=Add-Combo 150 94 150; Set-ComboPolicy $energyPolicy ([string]$prefs.energyWastePolicy)
Add-Label 'Max Energy Loss' 318 98 110 | Out-Null
$energyMax=New-Object System.Windows.Forms.NumericUpDown
$energyMax.Location=New-Object System.Drawing.Point(425,94); $energyMax.Size=New-Object System.Drawing.Size(62,26); $energyMax.Minimum=0; $energyMax.Maximum=1000; $energyMax.Value=[decimal][int]$prefs.maxEnergyLoss; $form.Controls.Add($energyMax)

$energyNote=Add-Label 'If current energy is already above its natural maximum, energy waste restrictions are bypassed for opportunity ranking.' 18 127 468 38
$energyNote.ForeColor=[System.Drawing.Color]::FromArgb(145,152,164)

Add-Label 'Nerve Waste' 18 180 130 | Out-Null
$nervePolicy=Add-Combo 150 176 150; Set-ComboPolicy $nervePolicy ([string]$prefs.nerveWastePolicy)
Add-Label 'Max Nerve Loss' 318 180 110 | Out-Null
$nerveMax=New-Object System.Windows.Forms.NumericUpDown
$nerveMax.Location=New-Object System.Drawing.Point(425,176); $nerveMax.Size=New-Object System.Drawing.Size(62,26); $nerveMax.Minimum=0; $nerveMax.Maximum=32767; $nerveMax.Value=[decimal][int]$prefs.maxNerveLoss; $form.Controls.Add($nerveMax)

$nerveNote=Add-Label 'Nerve restrictions remain active even when nerve is stacked above its natural maximum.' 18 209 468 28
$nerveNote.ForeColor=[System.Drawing.Color]::FromArgb(145,152,164)

function Refresh-Limits {
    $energyMax.Enabled=($energyPolicy.SelectedIndex -eq 2)
    $nerveMax.Enabled=($nervePolicy.SelectedIndex -eq 2)
}
$energyPolicy.Add_SelectedIndexChanged({ Refresh-Limits })
$nervePolicy.Add_SelectedIndexChanged({ Refresh-Limits })
Refresh-Limits

$ignore=New-Object System.Windows.Forms.Button
$ignore.Text='Ignore List...'; $ignore.Location=New-Object System.Drawing.Point(18,260); $ignore.Size=New-Object System.Drawing.Size(120,32); $form.Controls.Add($ignore)
$ignore.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath $FilterLauncher)) { throw 'LaunchFilterPopup.ps1 is missing.' }
        & $FilterLauncher -Filter 'Ignore'
    } catch { Write-TravelAssistantLog -Level ERROR -Component $logComponent -Message $_.Exception.ToString() }
})

$profile=New-Object System.Windows.Forms.Button
$profile.Text='Profile / API...'; $profile.Location=New-Object System.Drawing.Point(154,260); $profile.Size=New-Object System.Drawing.Size(120,32); $form.Controls.Add($profile)
$profile.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath $ProfileLauncher)) { throw 'LaunchSettings.ps1 is missing.' }
        & $ProfileLauncher
    } catch { Write-TravelAssistantLog -Level ERROR -Component $logComponent -Message $_.Exception.ToString() }
})

$info=Add-Label 'Main sort choices are UPCOMING, GROSS PROFIT, and PROFIT/HR. Hit likelihood stays visible as a separate percentage and is not hidden inside the sort score.' 18 310 468 50
$info.ForeColor=[System.Drawing.Color]::FromArgb(145,152,164)

$save=New-Object System.Windows.Forms.Button
$save.Text='Save'; $save.Location=New-Object System.Drawing.Point(326,372); $save.Size=New-Object System.Drawing.Size(78,30); $save.BackColor=[System.Drawing.Color]::FromArgb(82,174,255); $save.ForeColor=[System.Drawing.Color]::Black; $form.Controls.Add($save)
$cancel=New-Object System.Windows.Forms.Button
$cancel.Text='Cancel'; $cancel.Location=New-Object System.Drawing.Point(412,372); $cancel.Size=New-Object System.Drawing.Size(78,30); $form.Controls.Add($cancel)
$cancel.Add_Click({ $form.Close() })

$save.Add_Click({
    try {
        $current=Read-UiPreferences
        Set-FilterProperty $current 'showProfitableOnly' ([bool]$profitable.Checked)
        Set-FilterProperty $current 'use95PercentMarketValue' ([bool]$mv95.Checked)
        Set-FilterProperty $current 'energyWastePolicy' (Get-ComboPolicy $energyPolicy)
        Set-FilterProperty $current 'maxEnergyLoss' ([int]$energyMax.Value)
        Set-FilterProperty $current 'nerveWastePolicy' (Get-ComboPolicy $nervePolicy)
        Set-FilterProperty $current 'maxNerveLoss' ([int]$nerveMax.Value)
        [void](Save-UiPreferences $current)
        if (-not (Test-Path -LiteralPath $UpdateLauncher)) { throw 'LaunchUpdate.ps1 is missing.' }
        & $UpdateLauncher -Action Update
        Clear-TravelAssistantLatestError -Component $logComponent
        $form.Close()
    } catch {
        Write-TravelAssistantLog -Level ERROR -Component $logComponent -Message (Format-TravelAssistantErrorRecord $_)
    }
})

$form.AcceptButton=$save; $form.CancelButton=$cancel
[void]$form.ShowDialog()
