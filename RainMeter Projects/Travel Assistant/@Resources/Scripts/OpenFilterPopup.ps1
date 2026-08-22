param(
    [ValidateSet('Item','Country','Category','Ignore')]
    [string]$Filter = 'Item'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

. (Join-Path $PSScriptRoot 'FilterPreferences.ps1') -SkipMain

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$RuntimeDir = Join-Path $ProjectRoot 'data\runtime'
$EngineStateFile = Join-Path $RuntimeDir 'engine-state.json'

function Read-PopupJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function New-PopupRow {
    param([string]$Id, [string]$Label, [bool]$Checked)
    return [pscustomobject]@{ Id=$Id; Label=$Label; Checked=$Checked }
}

$prefs = Read-UiPreferences
$items = Read-PopupJson (Join-Path $ConfigDir 'items.json')
$countries = Read-PopupJson (Join-Path $ConfigDir 'countries.json')
$engine = Read-PopupJson $EngineStateFile

$rows = New-Object System.Collections.Generic.List[object]
$titleText = ''
$allLabel = 'All'
$showAllToggle = $true

if ($Filter -eq 'Item') {
    $titleText = 'Item filter'
    $allLabel = 'All visible items'
    $selected = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($id in @($prefs.selectedItemIds)) { [void]$selected.Add([int]$id) }
    foreach ($item in @($items.items | Where-Object { $_.visible -eq $true } | Sort-Object name)) {
        $checked = [bool]$prefs.itemFilterAll -or $selected.Contains([int]$item.itemId)
        $rows.Add((New-PopupRow -Id ([string][int]$item.itemId) -Label ('{0}  [{1}]' -f [string]$item.name,[string]$item.category) -Checked $checked))
    }
} elseif ($Filter -eq 'Category') {
    $titleText = 'Category filter'
    $allLabel = 'All visible categories'
    $selected = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($value in @($prefs.selectedCategories)) { [void]$selected.Add([string]$value) }
    $categories = @($items.items | Where-Object { $_.visible -eq $true } | ForEach-Object { [string]$_.category } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)
    foreach ($category in $categories) {
        $checked = [bool]$prefs.categoryFilterAll -or $selected.Contains($category)
        $rows.Add((New-PopupRow -Id $category -Label $category -Checked $checked))
    }
} elseif ($Filter -eq 'Country') {
    $titleText = 'Countries in selected trip bands'
    $allLabel = 'All countries in selected bands'
    $bandSet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($band in @($prefs.selectedTripBands)) { [void]$bandSet.Add([string]$band) }
    $countrySet = New-Object 'System.Collections.Generic.HashSet[string]'
    foreach ($id in @($prefs.selectedCountryIds)) { [void]$countrySet.Add([string]$id) }
    foreach ($country in @($countries.countries | Where-Object { $_.collect -eq $true -and $bandSet.Contains([string]$_.tripBand) } | Sort-Object tripBand,name)) {
        $label = '{0}  [{1}]' -f [string]$country.name, (([string]$country.tripBand).Substring(0,1).ToUpperInvariant() + ([string]$country.tripBand).Substring(1))
        $rows.Add((New-PopupRow -Id ([string]$country.id) -Label $label -Checked ($countrySet.Contains([string]$country.id))))
    }
} else {
    $titleText = 'Ignore List'
    $showAllToggle = $false
    $ignored = New-Object 'System.Collections.Generic.HashSet[int]'
    foreach ($id in @($prefs.ignoredItemIds)) { [void]$ignored.Add([int]$id) }

    $metadataRows = @()
    if ($null -ne $engine -and $engine.PSObject.Properties['itemMetadata']) {
        $metadataRows = @($engine.itemMetadata.PSObject.Properties | ForEach-Object {
            [pscustomobject]@{
                itemId = [int]$_.Name
                name = if ($_.Value.PSObject.Properties['name']) { [string]$_.Value.name } else { ('Item {0}' -f $_.Name) }
                category = if ($_.Value.PSObject.Properties['category']) { [string]$_.Value.category } else { 'Unknown' }
            }
        } | Sort-Object name,itemId)
    }
    if ($metadataRows.Count -eq 0) {
        $metadataRows = @($items.items | ForEach-Object { [pscustomobject]@{ itemId=[int]$_.itemId; name=[string]$_.name; category=[string]$_.category } } | Sort-Object name,itemId)
    }
    foreach ($item in $metadataRows) {
        $rows.Add((New-PopupRow -Id ([string]$item.itemId) -Label ('{0}  [{1}]  #{2}' -f $item.name,$item.category,$item.itemId) -Checked ($ignored.Contains([int]$item.itemId))))
    }
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'Travel Assistant - ' + $titleText
$form.Size = New-Object System.Drawing.Size(500,610)
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = 'FixedDialog'
$form.MaximizeBox = $false
$form.MinimizeBox = $false
$form.BackColor = [System.Drawing.Color]::FromArgb(31,35,40)
$form.ForeColor = [System.Drawing.Color]::FromArgb(222,226,232)
$form.Font = New-Object System.Drawing.Font('Segoe UI',9)

$title = New-Object System.Windows.Forms.Label
$title.Text = $titleText.ToUpperInvariant()
$title.Location = New-Object System.Drawing.Point(16,14)
$title.Size = New-Object System.Drawing.Size(450,26)
$title.Font = New-Object System.Drawing.Font('Segoe UI Semibold',12)
$form.Controls.Add($title)

$note = New-Object System.Windows.Forms.Label
$note.Location = New-Object System.Drawing.Point(16,42)
$note.Size = New-Object System.Drawing.Size(450,36)
$note.ForeColor = [System.Drawing.Color]::FromArgb(145,152,164)
if ($Filter -eq 'Ignore') {
    $note.Text = 'Checked items are hidden and excluded from broad per-item Torn market-price requests. A favorite is preserved and returns when unignored.'
} elseif ($Filter -eq 'Country') {
    $note.Text = 'The main Short / Medium / Long toggles choose bands. Use this list for country-level exceptions inside those bands.'
} else {
    $note.Text = 'Selection is local and persistent. It changes presentation only and does not erase collected market history.'
}
$form.Controls.Add($note)

$allCheck = New-Object System.Windows.Forms.CheckBox
$allCheck.Text = $allLabel
$allCheck.Location = New-Object System.Drawing.Point(18,82)
$allCheck.Size = New-Object System.Drawing.Size(300,24)
$allCheck.ForeColor = $form.ForeColor
$allCheck.Visible = $showAllToggle
$form.Controls.Add($allCheck)

$list = New-Object System.Windows.Forms.CheckedListBox
$list.Location = New-Object System.Drawing.Point(16,112)
$list.Size = New-Object System.Drawing.Size(450,390)
$list.BackColor = [System.Drawing.Color]::FromArgb(20,23,27)
$list.ForeColor = [System.Drawing.Color]::FromArgb(232,235,240)
$list.CheckOnClick = $true
$list.HorizontalScrollbar = $true
$form.Controls.Add($list)

foreach ($row in @($rows)) {
    $index = $list.Items.Add([string]$row.Label)
    $list.SetItemChecked($index,[bool]$row.Checked)
}

$script:updatingAll = $false
function Refresh-AllCheck {
    if (-not $showAllToggle) { return }
    $all = $list.Items.Count -gt 0
    for ($i=0; $i -lt $list.Items.Count; $i++) { if (-not $list.GetItemChecked($i)) { $all=$false; break } }
    $script:updatingAll = $true
    try { $allCheck.Checked = $all } finally { $script:updatingAll = $false }
}

$allCheck.Add_CheckedChanged({
    if ($script:updatingAll) { return }
    for ($i=0; $i -lt $list.Items.Count; $i++) { $list.SetItemChecked($i,$allCheck.Checked) }
})
$list.Add_ItemCheck({ $form.BeginInvoke([Action]{ Refresh-AllCheck }) | Out-Null })
Refresh-AllCheck

if ($Filter -eq 'Country' -and $rows.Count -eq 0) {
    $note.Text = 'No trip bands are enabled. Turn on Short, Medium, or Long in the Travel data bar first.'
}

$selectAll = New-Object System.Windows.Forms.Button
$selectAll.Text = if ($Filter -eq 'Ignore') { 'Clear ignore list' } else { 'Reset / select all' }
$selectAll.Location = New-Object System.Drawing.Point(16,518)
$selectAll.Size = New-Object System.Drawing.Size(130,30)
$form.Controls.Add($selectAll)
$selectAll.Add_Click({
    $target = $Filter -ne 'Ignore'
    for ($i=0; $i -lt $list.Items.Count; $i++) { $list.SetItemChecked($i,$target) }
    Refresh-AllCheck
})

$save = New-Object System.Windows.Forms.Button
$save.Text = 'Save'
$save.Location = New-Object System.Drawing.Point(292,518)
$save.Size = New-Object System.Drawing.Size(82,30)
$save.BackColor = [System.Drawing.Color]::FromArgb(82,174,255)
$save.ForeColor = [System.Drawing.Color]::Black
$form.Controls.Add($save)

$cancel = New-Object System.Windows.Forms.Button
$cancel.Text = 'Cancel'
$cancel.Location = New-Object System.Drawing.Point(384,518)
$cancel.Size = New-Object System.Drawing.Size(82,30)
$form.Controls.Add($cancel)
$cancel.Add_Click({ $form.Close() })

$save.Add_Click({
    $selectedIds = New-Object System.Collections.Generic.List[string]
    for ($i=0; $i -lt $rows.Count; $i++) { if ($list.GetItemChecked($i)) { $selectedIds.Add([string]$rows[$i].Id) } }

    if ($Filter -eq 'Item') {
        Set-FilterProperty $prefs 'itemFilterAll' ($rows.Count -gt 0 -and $selectedIds.Count -eq $rows.Count)
        Set-FilterProperty $prefs 'selectedItemIds' ([int[]]@($selectedIds | ForEach-Object { [int]$_ }))
    } elseif ($Filter -eq 'Category') {
        Set-FilterProperty $prefs 'categoryFilterAll' ($rows.Count -gt 0 -and $selectedIds.Count -eq $rows.Count)
        Set-FilterProperty $prefs 'selectedCategories' ([string[]]@($selectedIds))
    } elseif ($Filter -eq 'Country') {
        $displayedSet = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($row in @($rows)) { [void]$displayedSet.Add([string]$row.Id) }
        $result = New-Object 'System.Collections.Generic.HashSet[string]'
        foreach ($id in @($prefs.selectedCountryIds)) { if (-not $displayedSet.Contains([string]$id)) { [void]$result.Add([string]$id) } }
        foreach ($id in @($selectedIds)) { [void]$result.Add([string]$id) }
        Set-FilterProperty $prefs 'selectedCountryIds' ([string[]]@($result | Sort-Object))
    } else {
        # Ignore List outranks pin for visibility/API work but does not destroy
        # the favorite. If the item is later unignored the same pin returns.
        Set-FilterProperty $prefs 'ignoredItemIds' ([int[]]@($selectedIds | ForEach-Object { [int]$_ } | Sort-Object -Unique))
    }

    [void](Save-UiPreferences -Preferences $prefs)
    $filterState = Join-Path $PSScriptRoot 'FilterState.ps1'
    if (Test-Path -LiteralPath $filterState) { try { & $filterState } catch { } }
    $form.Close()
})

$form.AcceptButton = $save
$form.CancelButton = $cancel
[void]$form.ShowDialog()
