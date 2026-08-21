$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. (Join-Path $PSScriptRoot 'TravelProfile.ps1')

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
    try {
        [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Travel Assistant Settings error', 'OK', 'Error') | Out-Null
    } catch { }
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
$form.Size = New-Object System.Drawing.Size(520, 555)
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

$title = New-Label -Text 'TRAVEL ASSISTANT' -X 16 -Y 14 -W 260 -H 28
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 14)

New-Label -Text 'Torn API key' -X 18 -Y 58 | Out-Null
$keyBox = New-Object System.Windows.Forms.TextBox
$keyBox.Location = New-Object System.Drawing.Point(190,55)
$keyBox.Size = New-Object System.Drawing.Size(250,24)
$keyBox.UseSystemPasswordChar = $true
if ($local.PSObject.Properties['tornApiKey']) { $keyBox.Text = [string]$local.tornApiKey }
Style-Input $keyBox
$form.Controls.Add($keyBox)

$showKey = New-Object System.Windows.Forms.CheckBox
$showKey.Text = 'Show'
$showKey.Location = New-Object System.Drawing.Point(448,57)
$showKey.Size = New-Object System.Drawing.Size(55,22)
$showKey.ForeColor = $form.ForeColor
$showKey.Add_CheckedChanged({ $keyBox.UseSystemPasswordChar = -not $showKey.Checked })
$form.Controls.Add($showKey)

New-Label -Text 'Travel mode' -X 18 -Y 101 | Out-Null
$modeCombo = New-Object System.Windows.Forms.ComboBox
$modeCombo.Location = New-Object System.Drawing.Point(190,98)
$modeCombo.Size = New-Object System.Drawing.Size(250,24)
$modeCombo.DropDownStyle = 'DropDownList'
Style-Input $modeCombo
$form.Controls.Add($modeCombo)

New-Label -Text 'Company' -X 18 -Y 144 | Out-Null
$companyCombo = New-Object System.Windows.Forms.ComboBox
$companyCombo.Location = New-Object System.Drawing.Point(190,141)
$companyCombo.Size = New-Object System.Drawing.Size(250,24)
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

New-Label -Text 'Company stars' -X 18 -Y 187 | Out-Null
$stars = New-Object System.Windows.Forms.NumericUpDown
$stars.Location = New-Object System.Drawing.Point(190,184)
$stars.Size = New-Object System.Drawing.Size(90,24)
$stars.Minimum = 0
$stars.Maximum = 10
$stars.Value = [decimal][int]$profile.companyStars
Style-Input $stars
$form.Controls.Add($stars)

New-Label -Text 'Faction: Excursion capacity' -X 18 -Y 230 -W 180 | Out-Null
$excursion = New-Object System.Windows.Forms.NumericUpDown
$excursion.Location = New-Object System.Drawing.Point(190,227)
$excursion.Size = New-Object System.Drawing.Size(90,24)
$excursion.Minimum = 0
$excursion.Maximum = 10
$excursion.Value = [decimal][int]$profile.factionExcursionLevel
Style-Input $excursion
$form.Controls.Add($excursion)
New-Label -Text '(+1 item per level)' -X 290 -Y 230 -W 170 | Out-Null

New-Label -Text 'Faction: Travel cost' -X 18 -Y 273 | Out-Null
$travelCostLevel = New-Object System.Windows.Forms.NumericUpDown
$travelCostLevel.Location = New-Object System.Drawing.Point(190,270)
$travelCostLevel.Size = New-Object System.Drawing.Size(90,24)
$travelCostLevel.Minimum = 0
$travelCostLevel.Maximum = 5
$travelCostLevel.Value = [decimal][int]$profile.factionTravelCostLevel
Style-Input $travelCostLevel
$form.Controls.Add($travelCostLevel)
New-Label -Text '(-15% fee per level)' -X 290 -Y 273 -W 170 | Out-Null

$summaryTitle = New-Label -Text 'Effective travel perks' -X 18 -Y 319 -W 240
$summaryTitle.Font = New-Object System.Drawing.Font('Segoe UI Semibold', 9)
$summary = New-Object System.Windows.Forms.Label
$summary.Location = New-Object System.Drawing.Point(18,344)
$summary.Size = New-Object System.Drawing.Size(475,74)
$summary.ForeColor = [System.Drawing.Color]::FromArgb(145,152,164)
$form.Controls.Add($summary)

$note = New-Label -Text 'Flower/Toy +5 capacity is item-specific and does not increase Xanax capacity.' -X 18 -Y 424 -W 475 -H 24
$note.ForeColor = [System.Drawing.Color]::FromArgb(232,178,72)

$script:modeIds = @()
function Update-ProfilePreview {
    $companyId = 'none'
    if ($companyCombo.SelectedIndex -ge 0 -and $companyCombo.SelectedIndex -lt $companyRows.Count) {
        $companyId = [string]$companyRows[$companyCombo.SelectedIndex].id
    }
    $previewProfile = [pscustomobject]@{
        companyType = $companyId
        companyStars = [int]$stars.Value
        factionExcursionLevel = [int]$excursion.Value
        factionTravelCostLevel = [int]$travelCostLevel.Value
    }
    $effects = Get-TravelProfileEffects -Profile $previewProfile -PerksConfig $perks -Item $item

    $wantedMode = $currentMode
    if ($modeCombo.SelectedIndex -ge 0 -and $modeCombo.SelectedIndex -lt $script:modeIds.Count) {
        $wantedMode = [string]$script:modeIds[$modeCombo.SelectedIndex]
    }

    $availableIds = @(Get-AvailableTravelModeIds -TravelModes $modes -Effects $effects)
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

    $businessText = if ([bool]$effects.freeBusinessClass) { 'Business: FREE / available' } else { 'Business: locked (10-star Lingerie)' }
    $summary.Text = ('General capacity +{0}   |   Xanax-specific +{1}' -f [int]$effects.generalCapacityBonus, [int]$effects.itemCapacityBonus) + [Environment]::NewLine + ('Faction capacity +{0}   |   Travel fees -{1}%' -f [int]$effects.factionCapacityBonus, [int]$effects.travelCostReductionPercent) + [Environment]::NewLine + $businessText
}

$companyCombo.Add_SelectedIndexChanged({ Update-ProfilePreview })
$stars.Add_ValueChanged({ Update-ProfilePreview })
$excursion.Add_ValueChanged({ Update-ProfilePreview })
$travelCostLevel.Add_ValueChanged({ Update-ProfilePreview })
Update-ProfilePreview

$save = New-Object System.Windows.Forms.Button
$save.Text = 'Save'
$save.Location = New-Object System.Drawing.Point(318,466)
$save.Size = New-Object System.Drawing.Size(82,30)
$save.BackColor = [System.Drawing.Color]::FromArgb(82,174,255)
$save.ForeColor = [System.Drawing.Color]::Black
$form.Controls.Add($save)

$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = 'Cancel'
$cancel.Location = New-Object System.Drawing.Point(410,466)
$cancel.Size = New-Object System.Drawing.Size(82,30)
$form.Controls.Add($cancel)
$cancel.Add_Click({ $form.Close() })

$save.Add_Click({
    try {
        $companyId = 'none'
        if ($companyCombo.SelectedIndex -ge 0 -and $companyCombo.SelectedIndex -lt $companyRows.Count) {
            $companyId = [string]$companyRows[$companyCombo.SelectedIndex].id
        }
        $selectedMode = 'airstrip'
        if ($modeCombo.SelectedIndex -ge 0 -and $modeCombo.SelectedIndex -lt $script:modeIds.Count) {
            $selectedMode = [string]$script:modeIds[$modeCombo.SelectedIndex]
        }

        Set-ObjectProperty -Object $local -Name 'schemaVersion' -Value 1
        Set-ObjectProperty -Object $local -Name 'tornApiKey' -Value ([string]$keyBox.Text.Trim())
        Set-ObjectProperty -Object $local -Name 'travelMode' -Value $selectedMode
        Set-ObjectProperty -Object $local -Name 'travelProfile' -Value ([pscustomobject]@{
            companyType = $companyId
            companyStars = [int]$stars.Value
            factionExcursionLevel = [int]$excursion.Value
            factionTravelCostLevel = [int]$travelCostLevel.Value
        })

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
