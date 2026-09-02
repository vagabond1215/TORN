$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'FilterPreferences.ps1') -SkipMain
. (Join-Path $PSScriptRoot 'RuntimeLog.ps1')

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$FilterLauncher=Join-Path $PSScriptRoot 'LaunchFilterPopup.ps1'
$ProfileLauncher=Join-Path $PSScriptRoot 'LaunchSettings.ps1'
$prefs=Read-UiPreferences
$logComponent='popup-optimizersettings'

$form=New-Object System.Windows.Forms.Form
$form.Text='Travel Assistant Settings'
$form.Size=New-Object System.Drawing.Size(520,398)
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

$profitable=New-Object System.Windows.Forms.CheckBox
$profitable.Text='Show profitable items only'; $profitable.Location=New-Object System.Drawing.Point(18,18); $profitable.Size=New-Object System.Drawing.Size(190,24); $profitable.Checked=[bool]$prefs.showProfitableOnly; $form.Controls.Add($profitable)

Add-Label 'Tax / trader rate' 250 50 110 | Out-Null
$marketTax=New-Object System.Windows.Forms.ComboBox
$marketTax.DropDownStyle='DropDownList'; $marketTax.Location=New-Object System.Drawing.Point(366,46); $marketTax.Size=New-Object System.Drawing.Size(104,26)
$marketTax.BackColor=[System.Drawing.Color]::FromArgb(20,23,27); $marketTax.ForeColor=[System.Drawing.Color]::FromArgb(232,235,240)
foreach($rate in 0..5){[void]$marketTax.Items.Add(([string]$rate+'%'))}
$marketTax.SelectedIndex=[Math]::Max(0,[Math]::Min(5,[int]$prefs.itemMarketFeePercent))
$form.Controls.Add($marketTax)

Add-Label 'Energy Waste' 18 90 130 | Out-Null
$energyPolicy=Add-Combo 150 86 150; Set-ComboPolicy $energyPolicy ([string]$prefs.energyWastePolicy)
Add-Label 'Max Energy Loss' 318 90 110 | Out-Null
$energyMax=New-Object System.Windows.Forms.NumericUpDown
$energyMax.Location=New-Object System.Drawing.Point(425,86); $energyMax.Size=New-Object System.Drawing.Size(62,26); $energyMax.Minimum=0; $energyMax.Maximum=1000; $energyMax.Value=[decimal][int]$prefs.maxEnergyLoss; $form.Controls.Add($energyMax)

$energyNote=Add-Label 'If current energy is already above its natural maximum, energy waste restrictions are bypassed for opportunity ranking.' 18 119 468 38
$energyNote.ForeColor=[System.Drawing.Color]::FromArgb(145,152,164)

Add-Label 'Nerve Waste' 18 172 130 | Out-Null
$nervePolicy=Add-Combo 150 168 150; Set-ComboPolicy $nervePolicy ([string]$prefs.nerveWastePolicy)
Add-Label 'Max Nerve Loss' 318 172 110 | Out-Null
$nerveMax=New-Object System.Windows.Forms.NumericUpDown
$nerveMax.Location=New-Object System.Drawing.Point(425,168); $nerveMax.Size=New-Object System.Drawing.Size(62,26); $nerveMax.Minimum=0; $nerveMax.Maximum=32767; $nerveMax.Value=[decimal][int]$prefs.maxNerveLoss; $form.Controls.Add($nerveMax)

$nerveNote=Add-Label 'Nerve restrictions remain active even when nerve is stacked above its natural maximum.' 18 201 468 28
$nerveNote.ForeColor=[System.Drawing.Color]::FromArgb(145,152,164)

function Refresh-Limits {
    $energyMax.Enabled=($energyPolicy.SelectedIndex -eq 2)
    $nerveMax.Enabled=($nervePolicy.SelectedIndex -eq 2)
}
$energyPolicy.Add_SelectedIndexChanged({ Refresh-Limits })
$nervePolicy.Add_SelectedIndexChanged({ Refresh-Limits })
Refresh-Limits

$ignore=New-Object System.Windows.Forms.Button
$ignore.Text='Ignore List...'; $ignore.Location=New-Object System.Drawing.Point(18,252); $ignore.Size=New-Object System.Drawing.Size(120,32); $form.Controls.Add($ignore)
$ignore.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath $FilterLauncher)) { throw 'LaunchFilterPopup.ps1 is missing.' }
        & $FilterLauncher -Filter 'Ignore'
    } catch { Write-TravelAssistantLog -Level ERROR -Component $logComponent -Message $_.Exception.ToString() }
})

$profile=New-Object System.Windows.Forms.Button
$profile.Text='Profile / API...'; $profile.Location=New-Object System.Drawing.Point(154,252); $profile.Size=New-Object System.Drawing.Size(120,32); $form.Controls.Add($profile)
$profile.Add_Click({
    try {
        if (-not (Test-Path -LiteralPath $ProfileLauncher)) { throw 'LaunchSettings.ps1 is missing.' }
        & $ProfileLauncher
    } catch { Write-TravelAssistantLog -Level ERROR -Component $logComponent -Message $_.Exception.ToString() }
})

$save=New-Object System.Windows.Forms.Button
$save.Text='Save'; $save.Location=New-Object System.Drawing.Point(326,312); $save.Size=New-Object System.Drawing.Size(78,30); $save.BackColor=[System.Drawing.Color]::FromArgb(126,190,73); $save.ForeColor=[System.Drawing.Color]::Black; $form.Controls.Add($save)
$cancel=New-Object System.Windows.Forms.Button
$cancel.Text='Cancel'; $cancel.Location=New-Object System.Drawing.Point(412,312); $cancel.Size=New-Object System.Drawing.Size(78,30); $form.Controls.Add($cancel)
$cancel.Add_Click({ $form.Close() })

$save.Add_Click({
    try {
        $current=Read-UiPreferences
        Set-FilterProperty $current 'showProfitableOnly' ([bool]$profitable.Checked)
        $marketTaxPercent=[Math]::Max(0,[Math]::Min(5,[int]$marketTax.SelectedIndex))
        Set-FilterProperty $current 'itemMarketFeePercent' $marketTaxPercent
        Set-FilterProperty $current 'energyWastePolicy' (Get-ComboPolicy $energyPolicy)
        Set-FilterProperty $current 'maxEnergyLoss' ([int]$energyMax.Value)
        Set-FilterProperty $current 'nerveWastePolicy' (Get-ComboPolicy $nervePolicy)
        Set-FilterProperty $current 'maxNerveLoss' ([int]$nerveMax.Value)
        [void](Save-UiPreferences $current)
        # Settings are projection inputs just like filters. Recompute from retained
        # market state so the saved tax/waste choices reach the next UI generation
        # without issuing another foreign-stock collection request.
        Start-FilterProjectionRefresh -Action RefreshFilters
        Clear-TravelAssistantLatestError -Component $logComponent
        $form.Close()
    } catch {
        Write-TravelAssistantLog -Level ERROR -Component $logComponent -Message (Format-TravelAssistantErrorRecord $_)
    }
})

$form.AcceptButton=$save; $form.CancelButton=$cancel
[void]$form.ShowDialog()
