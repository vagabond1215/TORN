$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. (Join-Path $PSScriptRoot 'TravelProfile.ps1')
. (Join-Path $PSScriptRoot 'TornProfileSync.ps1')

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$LocalSettingsPath = Join-Path $ConfigDir 'settings.local.json'
$PreferencePath = Join-Path $RuntimeDir 'preferences.json'
$SettingsErrorFile = Join-Path $RuntimeDir 'settings-error.txt'
$RunUpdatePath = Join-Path $PSScriptRoot 'RunUpdate.ps1'

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
    if (-not (Test-Path -LiteralPath $RunUpdatePath)) { return }
    $arguments = '-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File "{0}" -Action Update' -f $RunUpdatePath.Replace('"', '\"')
    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden | Out-Null
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
$currentMode = if ($local.PSObject.Properties['travelMode']) { [string]$local.travelMode } else { [string]$base.travelMode }
$prefs = Read-JsonFile $PreferencePath
if ($null -ne $prefs -and $prefs.PSObject.Properties['travelMode']) { $currentMode = [string]$prefs.travelMode }

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Travel Assistant Settings'
$form.Size = New-Object System.Drawing.Size(560, 760)
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

function New-LevelControl {
    param([int]$X, [int]$Y, [int]$Maximum, [int]$Value)
    $control = New-Object System.Windows.Forms.NumericUpDown
    $control.Location = New-Object System.Drawing.Point($X,$Y)
    $control.Size = New-Object System.Drawing.Size(70,24)
    $control.Minimum = 0
    $control.Maximum = $Maximum
    $control.Value = [decimal][Math]::Max(0, [Math]::Min($Maximum, $Value))
    Style-Input $control
    $form.Controls.Add($control)
    return $control
}

$title = New-Label -Text 'TRAVEL ASSISTANT' -X 16 -Y 14 -W 280 -H 28
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 14)

New-Label -Text 'Torn API key' -X 18 -Y 58 | Out-Null
$keyBox = New-Object System.Windows.Forms.TextBox
$keyBox.Location = New-Object System.Drawing.Point(190,55)
$keyBox.Size = New-Object System.Drawing.Size(280,24)
$keyBox.UseSystemPasswordChar = $true
if ($local.PSObject.Properties['tornApiKey']) { $keyBox.Text = [string]$local.tornApiKey }
Style-Input $keyBox
$form.Controls.Add($keyBox)
$showKey = New-Object System.Windows.Forms.CheckBox
$showKey.Text = 'Show'
$showKey.Location = New-Object System.Drawing.Point(478,57)
$showKey.Size = New-Object System.Drawing.Size(60,22)
$showKey.ForeColor = $form.ForeColor
$showKey.Add_CheckedChanged({ $keyBox.UseSystemPasswordChar = -not $showKey.Checked })
$form.Controls.Add($showKey)

New-Label -Text 'Travel mode' -X 18 -Y 101 | Out-Null
$modeCombo = New-Object System.Windows.Forms.ComboBox
$modeCombo.Location = New-Object System.Drawing.Point(190,98)
$modeCombo.Size = New-Object System.Drawing.Size(280,24)
$modeCombo.DropDownStyle = 'DropDownList'
Style-Input $modeCombo
$form.Controls.Add($modeCombo)

New-Label -Text 'Company' -X 18 -Y 144 | Out-Null
$companyCombo = New-Object System.Windows.Forms.ComboBox
$companyCombo.Location = New-Object System.Drawing.Point(190,141)
$companyCombo.Size = New-Object System.Drawing.Size(280,24)
$companyCombo.DropDownStyle = 'DropDownList'
Style-Input $companyCombo
$form.Controls.Add($companyCombo)
$companyRows = @($perks.companies)
foreach ($company in $companyRows) { [void]$companyCombo.Items.Add([string]$company.label) }
$companyIndex = 0
for ($i = 0; $i -lt $companyRows.Count; $i++) { if ([string]$companyRows[$i].id -eq [string]$profile.companyType) { $companyIndex = $i; break } }
$companyCombo.SelectedIndex = $companyIndex

New-Label -Text 'Company stars' -X 18 -Y 187 | Out-Null
$stars = New-LevelControl -X 190 -Y 184 -Maximum 10 -Value ([int]$profile.companyStars)

$section = New-Label -Text 'FACTION TRAVEL LOADOUTS' -X 18 -Y 225 -W 260
$section.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)

New-Label -Text 'Faction mode' -X 18 -Y 257 | Out-Null
$factionStateCombo = New-Object System.Windows.Forms.ComboBox
$factionStateCombo.Location = New-Object System.Drawing.Point(190,254)
$factionStateCombo.Size = New-Object System.Drawing.Size(140,24)
$factionStateCombo.DropDownStyle = 'DropDownList'
Style-Input $factionStateCombo
[void]$factionStateCombo.Items.Add('Manual')
[void]$factionStateCombo.Items.Add('Peace')
[void]$factionStateCombo.Items.Add('War')
$factionStateCombo.SelectedIndex = if ([string]$profile.factionState -eq 'peace') { 1 } elseif ([string]$profile.factionState -eq 'war') { 2 } else { 0 }
$form.Controls.Add($factionStateCombo)

New-Label -Text 'Loadout' -X 18 -Y 295 -W 135 | Out-Null
New-Label -Text 'Capacity' -X 190 -Y 295 -W 70 | Out-Null
New-Label -Text 'Cost' -X 290 -Y 295 -W 60 | Out-Null
New-Label -Text 'Manual active' -X 18 -Y 322 -W 150 | Out-Null
$manualExcursion = New-LevelControl -X 190 -Y 319 -Maximum 10 -Value ([int]$profile.factionExcursionLevel)
$manualCost = New-LevelControl -X 290 -Y 319 -Maximum 5 -Value ([int]$profile.factionTravelCostLevel)
New-Label -Text 'Peace' -X 18 -Y 359 -W 150 | Out-Null
$peaceExcursion = New-LevelControl -X 190 -Y 356 -Maximum 10 -Value ([int]$profile.factionPeaceExcursionLevel)
$peaceCost = New-LevelControl -X 290 -Y 356 -Maximum 5 -Value ([int]$profile.factionPeaceTravelCostLevel)
New-Label -Text 'War' -X 18 -Y 396 -W 150 | Out-Null
$warExcursion = New-LevelControl -X 190 -Y 393 -Maximum 10 -Value ([int]$profile.factionWarExcursionLevel)
$warCost = New-LevelControl -X 290 -Y 393 -Maximum 5 -Value ([int]$profile.factionWarTravelCostLevel)
New-Label -Text 'Capacity: +1 item/level (max 10)' -X 370 -Y 350 -W 170 -H 34 | Out-Null
New-Label -Text 'Cost: -15%/level (max 5)' -X 370 -Y 391 -W 170 -H 34 | Out-Null

$sync = New-Object System.Windows.Forms.Button
$sync.Text = 'Sync from Torn'
$sync.Location = New-Object System.Drawing.Point(18,442)
$sync.Size = New-Object System.Drawing.Size(112,30)
$form.Controls.Add($sync)
$syncStatus = New-Object System.Windows.Forms.Label
$syncStatus.Location = New-Object System.Drawing.Point(142,438)
$syncStatus.Size = New-Object System.Drawing.Size(390,50)
$syncStatus.ForeColor = [System.Drawing.Color]::FromArgb(145,152,164)
$syncStatus.Text = 'Populate company/stars, active faction mode, and both faction loadouts. Save remains explicit.'
$form.Controls.Add($syncStatus)

$summaryTitle = New-Label -Text 'Effective travel perks' -X 18 -Y 500 -W 240
$summaryTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$summary = New-Object System.Windows.Forms.Label
$summary.Location = New-Object System.Drawing.Point(18,525)
$summary.Size = New-Object System.Drawing.Size(515,90)
$summary.ForeColor = [System.Drawing.Color]::FromArgb(145,152,164)
$form.Controls.Add($summary)
$note = New-Label -Text 'Flower/Toy +5 capacity is item-specific and does not increase Xanax capacity.' -X 18 -Y 620 -W 515 -H 24
$note.ForeColor = [System.Drawing.Color]::FromArgb(232,178,72)

$script:modeIds = @()
function Get-SelectedFactionState {
    if ($factionStateCombo.SelectedIndex -eq 1) { return 'peace' }
    if ($factionStateCombo.SelectedIndex -eq 2) { return 'war' }
    return 'manual'
}

function Get-PreviewProfile {
    $companyId = 'none'
    if ($companyCombo.SelectedIndex -ge 0 -and $companyCombo.SelectedIndex -lt $companyRows.Count) { $companyId = [string]$companyRows[$companyCombo.SelectedIndex].id }
    $state = Get-SelectedFactionState
    $activeExcursion = [int]$manualExcursion.Value
    $activeCost = [int]$manualCost.Value
    if ($state -eq 'peace') { $activeExcursion = [int]$peaceExcursion.Value; $activeCost = [int]$peaceCost.Value }
    elseif ($state -eq 'war') { $activeExcursion = [int]$warExcursion.Value; $activeCost = [int]$warCost.Value }
    return [pscustomobject]@{
        companyType = $companyId; companyStars = [int]$stars.Value; factionState = $state
        factionExcursionLevel = $activeExcursion; factionTravelCostLevel = $activeCost
        factionPeaceExcursionLevel = [int]$peaceExcursion.Value; factionPeaceTravelCostLevel = [int]$peaceCost.Value
        factionWarExcursionLevel = [int]$warExcursion.Value; factionWarTravelCostLevel = [int]$warCost.Value
    }
}

function Update-ProfilePreview {
    $previewProfile = Get-PreviewProfile
    $effects = Get-TravelProfileEffects -Profile $previewProfile -PerksConfig $perks -Item $item

    $wantedMode = $currentMode
    if ($modeCombo.SelectedIndex -ge 0 -and $modeCombo.SelectedIndex -lt $script:modeIds.Count) { $wantedMode = [string]$script:modeIds[$modeCombo.SelectedIndex] }
    $availableIds = @(Get-AvailableTravelModeIds -TravelModes $modes -Effects $effects)
    $modeCombo.Items.Clear(); $script:modeIds = @()
    foreach ($id in $availableIds) {
        $row = @($modes.modes | Where-Object { [string]$_.id -eq $id } | Select-Object -First 1)
        if ($row.Count -eq 0) { continue }
        [void]$modeCombo.Items.Add([string]$row[0].label); $script:modeIds += $id
    }
    $selectIndex = [Array]::IndexOf([string[]]$script:modeIds, [string]$wantedMode)
    if ($selectIndex -lt 0) { $selectIndex = [Array]::IndexOf([string[]]$script:modeIds, 'airstrip') }
    if ($selectIndex -lt 0 -and $script:modeIds.Count -gt 0) { $selectIndex = 0 }
    if ($selectIndex -ge 0) { $modeCombo.SelectedIndex = $selectIndex }

    $manualEnabled = ([string]$previewProfile.factionState -eq 'manual')
    $manualExcursion.Enabled = $manualEnabled; $manualCost.Enabled = $manualEnabled
    $businessText = if ([bool]$effects.freeBusinessClass) { 'Business: FREE / available' } else { 'Business: locked (10-star Lingerie)' }
    $stateText = ([string]$previewProfile.factionState).ToUpperInvariant()
    $summary.Text = ('Faction mode {0}: active +{1} capacity | fees -{2}%' -f $stateText, [int]$effects.factionCapacityBonus, [int]$effects.travelCostReductionPercent) + [Environment]::NewLine + ('Peace {0}/10 cap, {1}/5 cost | War {2}/10 cap, {3}/5 cost' -f [int]$peaceExcursion.Value, [int]$peaceCost.Value, [int]$warExcursion.Value, [int]$warCost.Value) + [Environment]::NewLine + ('Company +{0} | Xanax-specific +{1} | {2}' -f [int]$effects.generalCapacityBonus, [int]$effects.itemCapacityBonus, $businessText)
}

foreach ($control in @($companyCombo,$stars,$factionStateCombo,$manualExcursion,$manualCost,$peaceExcursion,$peaceCost,$warExcursion,$warCost)) {
    if ($control -is [System.Windows.Forms.ComboBox]) { $control.Add_SelectedIndexChanged({ Update-ProfilePreview }) }
    else { $control.Add_ValueChanged({ Update-ProfilePreview }) }
}
Update-ProfilePreview

$sync.Add_Click({
    $sync.Enabled = $false; $sync.Text = 'Syncing...'
    $syncStatus.ForeColor = [System.Drawing.Color]::FromArgb(145,152,164)
    $syncStatus.Text = 'Reading Torn job and faction upgrades...'
    [System.Windows.Forms.Application]::DoEvents()
    try {
        $apiKey = [string]$keyBox.Text.Trim()
        if ([string]::IsNullOrWhiteSpace($apiKey)) { throw 'Enter a Torn API key before syncing.' }
        $result = Get-TornTravelProfileSync -ApiKey $apiKey -PerksConfig $perks
        $partial = $false
        if ($result.CompanyResolved) {
            $idx = -1
            for ($i = 0; $i -lt $companyRows.Count; $i++) { if ([string]$companyRows[$i].id -eq [string]$result.CompanyType) { $idx = $i; break } }
            if ($idx -ge 0) { $companyCombo.SelectedIndex = $idx; $stars.Value = [decimal][int]$result.CompanyStars } else { $partial = $true }
        } else { $partial = $true }

        if ($result.FactionResolved) {
            $factionStateCombo.SelectedIndex = if ([string]$result.FactionState -eq 'peace') { 1 } elseif ([string]$result.FactionState -eq 'war') { 2 } else { 0 }
            $peaceExcursion.Value = [decimal][int]$result.FactionPeaceExcursionLevel
            $peaceCost.Value = [decimal][int]$result.FactionPeaceTravelCostLevel
            $warExcursion.Value = [decimal][int]$result.FactionWarExcursionLevel
            $warCost.Value = [decimal][int]$result.FactionWarTravelCostLevel
            $manualExcursion.Value = [decimal][int]$result.FactionExcursionLevel
            $manualCost.Value = [decimal][int]$result.FactionTravelCostLevel
        } else { $partial = $true }
        Update-ProfilePreview
        $syncStatus.Text = ([string]$result.CompanySummary + ' | ' + [string]$result.FactionSummary)
        if ($partial) { $syncStatus.ForeColor = [System.Drawing.Color]::FromArgb(232,178,72) }
        else { $syncStatus.ForeColor = [System.Drawing.Color]::FromArgb(86,190,116) }
    } catch {
        Write-SettingsError $_
        $syncStatus.ForeColor = [System.Drawing.Color]::FromArgb(224,90,90)
        $syncStatus.Text = $_.Exception.Message
    } finally {
        $sync.Enabled = $true; $sync.Text = 'Sync from Torn'
    }
})

$save = New-Object System.Windows.Forms.Button
$save.Text = 'Save'; $save.Location = New-Object System.Drawing.Point(354,665); $save.Size = New-Object System.Drawing.Size(82,30)
$save.BackColor = [System.Drawing.Color]::FromArgb(82,174,255); $save.ForeColor = [System.Drawing.Color]::Black
$form.Controls.Add($save)
$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = 'Cancel'; $cancel.Location = New-Object System.Drawing.Point(446,665); $cancel.Size = New-Object System.Drawing.Size(82,30)
$form.Controls.Add($cancel); $cancel.Add_Click({ $form.Close() })

$save.Add_Click({
    try {
        $preview = Get-PreviewProfile
        $selectedMode = 'airstrip'
        if ($modeCombo.SelectedIndex -ge 0 -and $modeCombo.SelectedIndex -lt $script:modeIds.Count) { $selectedMode = [string]$script:modeIds[$modeCombo.SelectedIndex] }
        Set-ObjectProperty -Object $local -Name 'schemaVersion' -Value 1
        Set-ObjectProperty -Object $local -Name 'tornApiKey' -Value ([string]$keyBox.Text.Trim())
        Set-ObjectProperty -Object $local -Name 'travelMode' -Value $selectedMode
        Set-ObjectProperty -Object $local -Name 'travelProfile' -Value $preview
        Write-JsonAtomic -Path $LocalSettingsPath -Value $local
        Write-JsonAtomic -Path $PreferencePath -Value ([pscustomobject]@{ schemaVersion = 1; travelMode = $selectedMode })
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
