$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. (Join-Path $PSScriptRoot 'TravelProfile.ps1')
. (Join-Path $PSScriptRoot 'TornProfileSync.ps1')
. (Join-Path $PSScriptRoot 'CurrentCapacity.ps1')
. (Join-Path $PSScriptRoot 'FilterPreferences.ps1') -SkipMain

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$LocalSettingsPath = Join-Path $ConfigDir 'settings.local.json'
$PreferencePath = Join-Path $RuntimeDir 'preferences.json'
$SettingsErrorFile = Join-Path $RuntimeDir 'settings-error.txt'
$UpdateLauncherPath = Join-Path $PSScriptRoot 'LaunchUpdate.ps1'
$FilterLauncherPath = Join-Path $PSScriptRoot 'LaunchFilterPopup.ps1'

New-Item -ItemType Directory -Force -Path $RuntimeDir | Out-Null
if (Test-Path -LiteralPath $SettingsErrorFile) { Remove-Item -LiteralPath $SettingsErrorFile -Force -ErrorAction SilentlyContinue }

function Write-SettingsError {
    param([object]$ErrorRecord)
    try {
        $message = if ($null -ne $ErrorRecord.Exception) { [string]$ErrorRecord.Exception.Message } else { [string]$ErrorRecord }
        $detail = @(
            ('Time: {0:o}' -f [DateTimeOffset]::Now),
            ('Message: {0}' -f $message),
            ('Position: {0}' -f [string]$ErrorRecord.InvocationInfo.PositionMessage)
        ) -join [Environment]::NewLine
        [System.IO.File]::WriteAllText($SettingsErrorFile, $detail, [System.Text.UTF8Encoding]::new($false))
    } catch { }
}

trap {
    Write-SettingsError $_
    try { [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Travel Assistant Settings error', 'OK', 'Error') | Out-Null } catch { }
    exit 1
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Write-JsonAtomic {
    param([string]$Path, [object]$Value, [int]$Depth = 12)
    $dir = Split-Path $Path -Parent
    New-Item -ItemType Directory -Force -Path $dir | Out-Null
    $tmp = $Path + '.tmp'
    $json = $Value | ConvertTo-Json -Depth $Depth
    [System.IO.File]::WriteAllText($tmp, $json, [System.Text.UTF8Encoding]::new($false))
    Move-Item -LiteralPath $tmp -Destination $Path -Force
}

function Set-ObjectProperty {
    param([object]$Object, [string]$Name, [object]$Value)
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop) { $Object | Add-Member -MemberType NoteProperty -Name $Name -Value $Value }
    else { $prop.Value = $Value }
}

function Start-BackgroundUpdate {
    if (-not (Test-Path -LiteralPath $UpdateLauncherPath)) { throw 'LaunchUpdate.ps1 is required to refresh saved profile settings.' }
    & $UpdateLauncherPath -Action Update
}

$base = Read-JsonFile (Join-Path $ConfigDir 'settings.example.json')
$local = Read-JsonFile $LocalSettingsPath
$perks = Read-JsonFile (Join-Path $ConfigDir 'travel-perks.json')
$modes = Read-JsonFile (Join-Path $ConfigDir 'travel-modes.json')
$items = Read-JsonFile (Join-Path $ConfigDir 'items.json')
if ($null -eq $base -or $null -eq $perks -or $null -eq $modes -or $null -eq $items) {
    [System.Windows.Forms.MessageBox]::Show('Travel Assistant configuration is incomplete.', 'Travel Assistant Settings', 'OK', 'Error') | Out-Null
    exit 1
}
if ($null -eq $local) {
    $local = Read-JsonFile (Join-Path $ConfigDir 'settings.local.example.json')
    if ($null -eq $local) { $local = [pscustomobject]@{ schemaVersion = 1; tornApiKey = ''; travelMode = 'airstrip' } }
}

$profile = Get-TravelProfile -BaseSettings $base -LocalSettings $local
$enabledItem = @($items.items | Where-Object { $_.enabled -eq $true } | Select-Object -First 1)
$item = if ($enabledItem.Count -gt 0) { $enabledItem[0] } else { $null }
$prefs = Read-UiPreferences
$currentMode = if ($local.PSObject.Properties['travelMode']) { [string]$local.travelMode } else { [string]$base.travelMode }
if ($null -ne $prefs -and $prefs.PSObject.Properties['travelMode']) { $currentMode = [string]$prefs.travelMode }
if ($currentMode -notin @('standard','airstrip','wlt','business')) { $currentMode = 'airstrip' }

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Travel Assistant Settings'
$form.Size = New-Object System.Drawing.Size(560, 800)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(31,35,40)
$form.ForeColor = [System.Drawing.Color]::FromArgb(222,226,232)
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

function New-Label {
    param([string]$Text, [int]$X, [int]$Y, [int]$W = 170, [int]$H = 22)
    $control = New-Object System.Windows.Forms.Label
    $control.Text = $Text
    $control.Location = New-Object System.Drawing.Point($X,$Y)
    $control.Size = New-Object System.Drawing.Size($W,$H)
    $control.ForeColor = [System.Drawing.Color]::FromArgb(200,205,214)
    $form.Controls.Add($control)
    return $control
}

function Style-Input {
    param([System.Windows.Forms.Control]$Control)
    $Control.BackColor = [System.Drawing.Color]::FromArgb(20,23,27)
    $Control.ForeColor = [System.Drawing.Color]::FromArgb(232,235,240)
}
function Get-GraphVisualValue {
    param([string]$Name,[bool]$Default=$true)
    $value=$Default
    if($null -ne $base -and $base.PSObject.Properties['graphVisuals']){
        $visuals=$base.graphVisuals
        if($null -ne $visuals.PSObject.Properties[$Name]){$value=[bool]$visuals.PSObject.Properties[$Name].Value}
    }
    if($null -ne $local -and $local.PSObject.Properties['graphVisuals']){
        $visuals=$local.graphVisuals
        if($null -ne $visuals.PSObject.Properties[$Name]){$value=[bool]$visuals.PSObject.Properties[$Name].Value}
    }
    return [bool]$value
}

function New-GraphCheckBox {
    param([string]$Text,[string]$SettingName,[int]$X,[int]$Y,[int]$W=245)
    $control=New-Object System.Windows.Forms.CheckBox
    $control.Text=$Text
    $control.Location=New-Object System.Drawing.Point($X,$Y)
    $control.Size=New-Object System.Drawing.Size($W,24)
    $control.ForeColor=$form.ForeColor
    $control.Checked=Get-GraphVisualValue -Name $SettingName -Default $true
    $form.Controls.Add($control)
    return $control
}

$title = New-Label -Text 'TRAVEL ASSISTANT' -X 16 -Y 14 -W 280 -H 28
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 14)

$profitableOnly = New-Object System.Windows.Forms.CheckBox
$profitableOnly.Text = 'Show profitable items only'
$profitableOnly.Location = New-Object System.Drawing.Point(18,48)
$profitableOnly.Size = New-Object System.Drawing.Size(180,24)
$profitableOnly.ForeColor = $form.ForeColor
$profitableOnly.Checked = [bool]$prefs.showProfitableOnly
$form.Controls.Add($profitableOnly)

$ignoreButton = New-Object System.Windows.Forms.Button
$ignoreButton.Text = 'Ignore List...'
$ignoreButton.Location = New-Object System.Drawing.Point(210,44)
$ignoreButton.Size = New-Object System.Drawing.Size(105,30)
$form.Controls.Add($ignoreButton)
$ignoreNote = New-Label -Text 'Ignored items are hidden and skip broad per-item market pricing.' -X 325 -Y 49 -W 215 -H 32
$ignoreNote.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$ignoreNote.ForeColor = [System.Drawing.Color]::FromArgb(145,152,164)
$ignoreButton.Add_Click({
    try {
        if (Test-Path -LiteralPath $FilterLauncherPath) { & $FilterLauncherPath -Filter Ignore }
    } catch { Write-SettingsError $_ }
})

New-Label -Text 'Torn API key' -X 18 -Y 92 | Out-Null
$keyBox = New-Object System.Windows.Forms.TextBox
$keyBox.Location = New-Object System.Drawing.Point(190,89)
$keyBox.Size = New-Object System.Drawing.Size(280,24)
$keyBox.UseSystemPasswordChar = $true
if ($local.PSObject.Properties['tornApiKey']) { $keyBox.Text = [string]$local.tornApiKey }
Style-Input $keyBox
$form.Controls.Add($keyBox)
$showKey = New-Object System.Windows.Forms.CheckBox
$showKey.Text = 'Show'
$showKey.Location = New-Object System.Drawing.Point(478,91)
$showKey.Size = New-Object System.Drawing.Size(60,22)
$showKey.ForeColor = $form.ForeColor
$showKey.Add_CheckedChanged({ $keyBox.UseSystemPasswordChar = -not $showKey.Checked })
$form.Controls.Add($showKey)
$keyNote = New-Label -Text 'Stored only in ignored local settings; never committed to Git.' -X 190 -Y 114 -W 330 -H 18
$keyNote.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$keyNote.ForeColor = [System.Drawing.Color]::FromArgb(145,152,164)

New-Label -Text 'Travel mode' -X 18 -Y 145 | Out-Null
$modeCombo = New-Object System.Windows.Forms.ComboBox
$modeCombo.Location = New-Object System.Drawing.Point(190,142)
$modeCombo.Size = New-Object System.Drawing.Size(280,24)
$modeCombo.DropDownStyle = 'DropDownList'
Style-Input $modeCombo
$form.Controls.Add($modeCombo)

New-Label -Text 'Company' -X 18 -Y 188 | Out-Null
$companyCombo = New-Object System.Windows.Forms.ComboBox
$companyCombo.Location = New-Object System.Drawing.Point(190,185)
$companyCombo.Size = New-Object System.Drawing.Size(280,24)
$companyCombo.DropDownStyle = 'DropDownList'
Style-Input $companyCombo
$form.Controls.Add($companyCombo)
$companyRows = @($perks.companies)
foreach ($company in $companyRows) { [void]$companyCombo.Items.Add([string]$company.label) }
$companyIndex = 0
for ($i = 0; $i -lt $companyRows.Count; $i++) {
    if ([string]$companyRows[$i].id -eq [string]$profile.companyType) { $companyIndex = $i; break }
}
$companyCombo.SelectedIndex = $companyIndex

New-Label -Text 'Company stars' -X 18 -Y 231 | Out-Null
$stars = New-Object System.Windows.Forms.NumericUpDown
$stars.Location = New-Object System.Drawing.Point(190,228)
$stars.Size = New-Object System.Drawing.Size(90,24)
$stars.Minimum = 0
$stars.Maximum = 10
$stars.Value = [decimal][int]$profile.companyStars
Style-Input $stars
$form.Controls.Add($stars)

$capacityTitle = New-Label -Text 'CURRENT TRAVEL CAPACITY' -X 18 -Y 273 -W 260
$capacityTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
New-Label -Text 'Current Xanax capacity' -X 18 -Y 304 -W 165 | Out-Null
$capacity = New-Object System.Windows.Forms.NumericUpDown
$capacity.Location = New-Object System.Drawing.Point(190,301)
$capacity.Size = New-Object System.Drawing.Size(90,24)
$capacity.Minimum = 0
$capacity.Maximum = 99
Style-Input $capacity
$form.Controls.Add($capacity)
$capacityDetail = New-Object System.Windows.Forms.Label
$capacityDetail.Location = New-Object System.Drawing.Point(290,297)
$capacityDetail.Size = New-Object System.Drawing.Size(240,38)
$capacityDetail.ForeColor = [System.Drawing.Color]::FromArgb(145,152,164)
$form.Controls.Add($capacityDetail)

$sync = New-Object System.Windows.Forms.Button
$sync.Text = 'Sync from Torn'
$sync.Location = New-Object System.Drawing.Point(18,349)
$sync.Size = New-Object System.Drawing.Size(112,30)
$form.Controls.Add($sync)
$syncStatus = New-Object System.Windows.Forms.Label
$syncStatus.Location = New-Object System.Drawing.Point(142,343)
$syncStatus.Size = New-Object System.Drawing.Size(390,48)
$syncStatus.ForeColor = [System.Drawing.Color]::FromArgb(145,152,164)
$syncStatus.Text = 'Reads current /user/perks and job data. No faction API permission required.'
$form.Controls.Add($syncStatus)

$summaryTitle = New-Label -Text 'Effective travel profile' -X 18 -Y 404 -W 240
$summaryTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$summary = New-Object System.Windows.Forms.Label
$summary.Location = New-Object System.Drawing.Point(18,429)
$summary.Size = New-Object System.Drawing.Size(515,82)
$summary.ForeColor = [System.Drawing.Color]::FromArgb(145,152,164)
$form.Controls.Add($summary)
$note = New-Label -Text 'Current capacity uses active perks only. Flower/Toy item-specific bonuses do not increase Xanax capacity.' -X 18 -Y 515 -W 515 -H 36
$note.ForeColor = [System.Drawing.Color]::FromArgb(232,178,72)
$chartTitle = New-Label -Text 'CHART VISUALS' -X 18 -Y 557 -W 220
$chartTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$chartNote = New-Label -Text 'Stock quantity is always shown. These options control additional graph overlays.' -X 150 -Y 557 -W 385 -H 22
$chartNote.Font = New-Object System.Drawing.Font('Segoe UI', 8)
$chartNote.ForeColor = [System.Drawing.Color]::FromArgb(145,152,164)

$showGridCheck = New-GraphCheckBox -Text 'Grid' -SettingName 'showGrid' -X 18 -Y 582
$showTransitionsCheck = New-GraphCheckBox -Text 'Restock / OoS markers' -SettingName 'showTransitions' -X 278 -Y 582
$showChanceCheck = New-GraphCheckBox -Text 'Live Chance to Hit' -SettingName 'showChance' -X 18 -Y 608
$showHindsightCheck = New-GraphCheckBox -Text 'Hindsight departure windows' -SettingName 'showHindsightWindows' -X 278 -Y 608
$showAccuracyCheck = New-GraphCheckBox -Text 'Forecast accuracy markers' -SettingName 'showAccuracyMarkers' -X 18 -Y 634
$showTooltipsCheck = New-GraphCheckBox -Text 'Graph tooltips' -SettingName 'showTooltips' -X 278 -Y 634
$showRestockBoundsCheck = New-GraphCheckBox -Text 'Restock window bounds' -SettingName 'showRestockWindowBounds' -X 18 -Y 660

$script:modeIds = @()
$script:updatingUi = $false
$script:capacityKnown = [bool]$profile.currentCapacityKnown
$script:capacityBonus = [int]$profile.currentCapacityBonus
$script:capacitySyncedAt = [long]$profile.currentCapacitySyncedAt

function Get-SelectedCompanyId {
    if ($companyCombo.SelectedIndex -ge 0 -and $companyCombo.SelectedIndex -lt $companyRows.Count) {
        return [string]$companyRows[$companyCombo.SelectedIndex].id
    }
    return 'none'
}

function Get-SelectedModeId {
    if ($modeCombo.SelectedIndex -ge 0 -and $modeCombo.SelectedIndex -lt $script:modeIds.Count) {
        return [string]$script:modeIds[$modeCombo.SelectedIndex]
    }
    return $currentMode
}

function Get-PreviewProfile {
    $selectedMode = Get-SelectedModeId
    $currentValue = if ($script:capacityKnown) { [int]$capacity.Value } else { 0 }
    return [pscustomobject]@{
        companyType = Get-SelectedCompanyId
        companyStars = [int]$stars.Value
        currentCapacityKnown = [bool]$script:capacityKnown
        currentCapacityMode = if ($script:capacityKnown) { $selectedMode } else { '' }
        currentCapacity = $currentValue
        currentCapacityBonus = if ($script:capacityKnown) { [int]$script:capacityBonus } else { 0 }
        currentCapacitySyncedAt = if ($script:capacityKnown) { [long]$script:capacitySyncedAt } else { 0 }
        factionState = [string]$profile.factionState
        factionExcursionLevel = [int]$profile.factionExcursionLevel
        factionTravelCostLevel = [int]$profile.factionTravelCostLevel
        factionPeaceExcursionLevel = [int]$profile.factionPeaceExcursionLevel
        factionPeaceTravelCostLevel = [int]$profile.factionPeaceTravelCostLevel
        factionWarExcursionLevel = [int]$profile.factionWarExcursionLevel
        factionWarTravelCostLevel = [int]$profile.factionWarTravelCostLevel
    }
}

function Set-CapacityFromBonus {
    if (-not $script:capacityKnown) { return }
    $mode = Get-SelectedModeId
    $baseCapacity = Get-TornTravelModeBaseCapacity -TravelMode $mode
    $total = [Math]::Max($baseCapacity, [Math]::Min(99, $baseCapacity + [int]$script:capacityBonus))
    $script:updatingUi = $true
    try { $capacity.Value = [decimal]$total } finally { $script:updatingUi = $false }
}

function Refresh-ModeChoices {
    $wantedMode = Get-SelectedModeId
    if ([string]::IsNullOrWhiteSpace($wantedMode)) { $wantedMode = $currentMode }

    $preview = Get-PreviewProfile
    $effects = Get-TravelProfileEffects -Profile $preview -PerksConfig $perks -Item $item
    $availableIds = @(Get-AvailableTravelModeIds -TravelModes $modes -Effects $effects)

    $script:updatingUi = $true
    try {
        $modeCombo.Items.Clear()
        $script:modeIds = @()
        foreach ($id in $availableIds) {
            $row = @($modes.modes | Where-Object { [string]$_.id -eq $id } | Select-Object -First 1)
            if ($row.Count -eq 0) { continue }
            [void]$modeCombo.Items.Add([string]$row[0].label)
            $script:modeIds += $id
        }
        $selectIndex = [Array]::IndexOf([string[]]$script:modeIds, [string]$wantedMode)
        if ($selectIndex -lt 0) { $selectIndex = [Array]::IndexOf([string[]]$script:modeIds, 'airstrip') }
        if ($selectIndex -lt 0 -and $script:modeIds.Count -gt 0) { $selectIndex = 0 }
        if ($selectIndex -ge 0) { $modeCombo.SelectedIndex = $selectIndex }
    } finally { $script:updatingUi = $false }

    Set-CapacityFromBonus
}

function Update-Summary {
    $preview = Get-PreviewProfile
    $effects = Get-TravelProfileEffects -Profile $preview -PerksConfig $perks -Item $item
    $mode = Get-SelectedModeId
    $baseCapacity = Get-TornTravelModeBaseCapacity -TravelMode $mode

    if ($script:capacityKnown) {
        $capacityDetail.Text = ('base {0} + active {1:+0;-0;0}' -f $baseCapacity, [int]$script:capacityBonus)
    } else {
        $capacityDetail.Text = 'not synced; enter manually or Sync from Torn'
    }

    $companyLabel = 'None / Other'
    if ($companyCombo.SelectedIndex -ge 0) { $companyLabel = [string]$companyCombo.SelectedItem }
    $businessText = if ([bool]$effects.freeBusinessClass) { 'Business: FREE / available' } else { 'Business: locked (10-star Lingerie)' }
    $capacityText = if ($script:capacityKnown) { ('Current {0}: {1} items' -f $mode, [int]$capacity.Value) } else { 'Current capacity: unresolved' }
    $summary.Text = $capacityText + [Environment]::NewLine + ('Company: {0} ({1}*)' -f $companyLabel, [int]$stars.Value) + [Environment]::NewLine + $businessText
}

$companyCombo.Add_SelectedIndexChanged({
    if ($script:updatingUi) { return }
    Refresh-ModeChoices
    Update-Summary
})
$stars.Add_ValueChanged({
    if ($script:updatingUi) { return }
    Refresh-ModeChoices
    Update-Summary
})
$modeCombo.Add_SelectedIndexChanged({
    if ($script:updatingUi) { return }
    Set-CapacityFromBonus
    Update-Summary
})
$capacity.Add_ValueChanged({
    if ($script:updatingUi) { return }
    $mode = Get-SelectedModeId
    $baseCapacity = Get-TornTravelModeBaseCapacity -TravelMode $mode
    $entered = [int]$capacity.Value
    if ($entered -le 0) {
        $script:capacityKnown = $false
        $script:capacityBonus = 0
        $script:capacitySyncedAt = 0
    } else {
        if ($entered -lt $baseCapacity) {
            $script:updatingUi = $true
            try { $capacity.Value = [decimal]$baseCapacity } finally { $script:updatingUi = $false }
            $entered = $baseCapacity
        }
        $script:capacityKnown = $true
        $script:capacityBonus = [Math]::Max(0, $entered - $baseCapacity)
        $script:capacitySyncedAt = 0
    }
    Update-Summary
})

Refresh-ModeChoices
if ($script:capacityKnown) { Set-CapacityFromBonus } else { $capacity.Value = 0 }
Update-Summary

$sync.Add_Click({
    $sync.Enabled = $false
    $sync.Text = 'Syncing...'
    $syncStatus.ForeColor = [System.Drawing.Color]::FromArgb(145,152,164)
    $syncStatus.Text = 'Reading current Torn job and perks...'
    [System.Windows.Forms.Application]::DoEvents()

    try {
        $apiKey = [string]$keyBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'Enter a Torn API key before syncing.' }
        $mode = Get-SelectedModeId

        $jobResult = Invoke-TornProfileJson -Uri 'https://api.torn.com/v2/user/job?comment=TravelAssistantSettingsSync' -ApiKey $apiKey
        $perksResult = Invoke-TornProfileJson -Uri 'https://api.torn.com/v2/user/perks?comment=TravelAssistantSettingsSync' -ApiKey $apiKey
        $messages = New-Object System.Collections.Generic.List[string]
        $partial = $false

        if ($jobResult.Success) {
            $companyResult = Get-TornCompanyTravelProfile -JobPayload $jobResult.Payload -PerksConfig $perks
            if ($companyResult.Resolved) {
                $idx = -1
                for ($i = 0; $i -lt $companyRows.Count; $i++) {
                    if ([string]$companyRows[$i].id -eq [string]$companyResult.CompanyType) { $idx = $i; break }
                }
                if ($idx -ge 0) {
                    $companyCombo.SelectedIndex = $idx
                    $stars.Value = [decimal][int]$companyResult.CompanyStars
                } else { $partial = $true }
                $messages.Add([string]$companyResult.Summary)
            } else {
                $partial = $true
                $messages.Add([string]$companyResult.Summary)
            }
        } else {
            $partial = $true
            $messages.Add(('Job unavailable: {0}' -f [string]$jobResult.Error))
        }

        if ($perksResult.Success) {
            $capacityResult = Get-TornEffectiveXanaxCapacity -TravelMode $mode -PerksPayload $perksResult.Payload
            if ($capacityResult.Resolved) {
                $script:capacityKnown = $true
                $script:capacityBonus = [int]$capacityResult.SuitcaseBonus + [int]$capacityResult.ActivePerkBonus
                $script:capacitySyncedAt = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                Set-CapacityFromBonus
                $messages.Add(('Capacity {0}: {1} items (base {2} + active {3})' -f $mode, [int]$capacityResult.Capacity, [int]$capacityResult.BaseCapacity, [int]$script:capacityBonus))
            } else {
                $partial = $true
                $messages.Add(('Capacity unresolved: {0}' -f [string]$capacityResult.PerkSummary))
            }
        } else {
            $partial = $true
            $messages.Add(('Current perks unavailable: {0}' -f [string]$perksResult.Error))
        }

        Refresh-ModeChoices
        Set-CapacityFromBonus
        Update-Summary
        $syncStatus.Text = ($messages -join ' | ')
        $syncStatus.ForeColor = if ($partial) { [System.Drawing.Color]::FromArgb(232,178,72) } else { [System.Drawing.Color]::FromArgb(86,190,116) }
    } catch {
        Write-SettingsError $_
        $syncStatus.ForeColor = [System.Drawing.Color]::FromArgb(224,90,90)
        $syncStatus.Text = $_.Exception.Message
    } finally {
        $sync.Enabled = $true
        $sync.Text = 'Sync from Torn'
    }
})

$save = New-Object System.Windows.Forms.Button
$save.Text = 'Save'
$save.Location = New-Object System.Drawing.Point(354,720)
$save.Size = New-Object System.Drawing.Size(82,30)
$save.BackColor = [System.Drawing.Color]::FromArgb(82,174,255)
$save.ForeColor = [System.Drawing.Color]::Black
$form.Controls.Add($save)
$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = 'Cancel'
$cancel.Location = New-Object System.Drawing.Point(446,720)
$cancel.Size = New-Object System.Drawing.Size(82,30)
$form.Controls.Add($cancel)
$cancel.Add_Click({ $form.Close() })

$save.Add_Click({
    try {
        $selectedMode = Get-SelectedModeId
        $preview = Get-PreviewProfile
        Set-ObjectProperty -Object $local -Name 'schemaVersion' -Value 1
        Set-ObjectProperty -Object $local -Name 'tornApiKey' -Value ([string]$keyBox.Text.Trim())
        Set-ObjectProperty -Object $local -Name 'travelMode' -Value $selectedMode
        Set-ObjectProperty -Object $local -Name 'travelProfile' -Value $preview
        $graphVisuals=[pscustomobject]@{
            showGrid=[bool]$showGridCheck.Checked
            showTransitions=[bool]$showTransitionsCheck.Checked
            showRestockWindowBounds=[bool]$showRestockBoundsCheck.Checked
            showChance=[bool]$showChanceCheck.Checked
            showHindsightWindows=[bool]$showHindsightCheck.Checked
            showAccuracyMarkers=[bool]$showAccuracyCheck.Checked
            showTooltips=[bool]$showTooltipsCheck.Checked
        }
        Set-ObjectProperty -Object $local -Name 'graphVisuals' -Value $graphVisuals
        Write-JsonAtomic -Path $LocalSettingsPath -Value $local
        $graphVisualPreferenceScript=Join-Path $PSScriptRoot 'GraphVisualPreferences.ps1'
        if(Test-Path -LiteralPath $graphVisualPreferenceScript){
            & $graphVisualPreferenceScript -Action Read -Value Hindsight
        }

        # Re-read immediately so an Ignore List popup opened while Settings was
        # visible cannot be overwritten by a stale in-memory preference object.
        $currentPrefs = Read-UiPreferences
        Set-FilterProperty $currentPrefs 'travelMode' $selectedMode
        Set-FilterProperty $currentPrefs 'showProfitableOnly' ([bool]$profitableOnly.Checked)
        [void](Save-UiPreferences -Preferences $currentPrefs)

        Start-BackgroundUpdate
        $form.Close()
    } catch {
        Write-SettingsError $_
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Unable to save Travel Assistant settings', 'OK', 'Error') | Out-Null
    }
})

$form.AcceptButton = $save
$form.CancelButton = $cancel
[void]$form.ShowDialog()
