param(
    [ValidateSet('Item','Country','Category','Ignore')]
    [string]$Filter='Item'
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
. (Join-Path $PSScriptRoot 'FilterPreferences.ps1') -SkipMain
. (Join-Path $PSScriptRoot 'RuntimeLog.ps1')

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir=Join-Path $ProjectRoot 'config'
$RuntimeDir=Join-Path $ProjectRoot 'data\runtime'
$EngineStateFile=Join-Path $RuntimeDir 'engine-state.json'
$logComponent='popup-filter-'+$Filter.ToLowerInvariant()

function Read-PopupJson([string]$Path) {
    try { return (Read-FilterJson -Path $Path) }
    catch { throw ("Failed to read popup JSON '{0}': {1}" -f $Path,$_.Exception.Message) }
}
function Read-OptionalPopupJson([string]$Path) {
    $lastError=$null
    foreach($attempt in 1..3) {
        try { return (Read-FilterJson -Path $Path) }
        catch {
            $lastError=$_
            if($attempt -lt 3) { Start-Sleep -Milliseconds 75 }
        }
    }
    if($null -ne $lastError) {
        try { Write-TravelAssistantLog -Level WARN -Component $logComponent -Message ("Optional engine-state read failed; using committed catalog fallback: {0}" -f $lastError.Exception.Message) } catch { }
    }
    return $null
}
function New-PopupRow([string]$Id,[string]$Label,[bool]$Checked) { return [pscustomobject]@{Id=$Id;Label=$Label;Checked=$Checked} }
function New-StringSet([object[]]$Values) {
    $set=@{}
    foreach($value in @($Values)) {
        $key=[string]$value
        if(-not [string]::IsNullOrWhiteSpace($key)) { $set[$key]=$true }
    }
    return $set
}
function New-IntSet([object[]]$Values) {
    $set=@{}
    foreach($value in @($Values)) {
        $n=0
        if([int]::TryParse([string]$value,[ref]$n) -and $n -gt 0) { $set[[string]$n]=$true }
    }
    return $set
}

$prefs=Read-UiPreferences
$items=Read-PopupJson (Join-Path $ConfigDir 'items.json')
$countries=Read-PopupJson (Join-Path $ConfigDir 'countries.json')
# The filter UI must remain usable while the long-running updater rewrites engine state.
# Engine metadata enriches the popup, but committed catalog data is a valid fallback.
$engine=Read-OptionalPopupJson $EngineStateFile

function Get-ActiveCatalogRows {
    $activeIds=@{}
    if ($null -ne $engine -and $engine.PSObject.Properties['observedMarkets']) {
        foreach ($p in $engine.observedMarkets.PSObject.Properties) {
            $m=$p.Value
            if ($null -eq $m) { continue }
            if (($m.PSObject.Properties['catalogActive'] -and $m.catalogActive -eq $false) -or ($m.PSObject.Properties['catalogStatus'] -and [string]$m.catalogStatus -eq 'legacy_removed')) { continue }
            if ($m.PSObject.Properties['itemId']) {
                $id=0
                if([int]::TryParse([string]$m.itemId,[ref]$id) -and $id -gt 0) { $activeIds[[string]$id]=$true }
            }
        }
    }

    $resultRows=@()
    if ($null -ne $engine -and $engine.PSObject.Properties['itemMetadata']) {
        foreach ($p in $engine.itemMetadata.PSObject.Properties) {
            $id=0
            if(-not [int]::TryParse([string]$p.Name,[ref]$id) -or $id -le 0) { continue }
            if ($activeIds.Count -gt 0 -and -not $activeIds.ContainsKey([string]$id)) { continue }
            $v=$p.Value
            if($null -eq $v) { continue }
            $name=if ($v.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$v.name)) { [string]$v.name } else { 'Item '+$id }
            $category=if ($v.PSObject.Properties['category'] -and -not [string]::IsNullOrWhiteSpace([string]$v.category)) { [string]$v.category } else { 'Unknown' }
            $resultRows += [pscustomobject]@{itemId=$id;name=$name;category=$category}
        }
    }

    if ($resultRows.Count -eq 0 -and $null -ne $items -and $items.PSObject.Properties['items']) {
        foreach ($item in @($items.items)) {
            if($item.PSObject.Properties['visible'] -and $item.visible -eq $false) { continue }
            $id=0
            if(-not [int]::TryParse([string]$item.itemId,[ref]$id) -or $id -le 0) { continue }
            if($activeIds.Count -gt 0 -and -not $activeIds.ContainsKey([string]$id)) { continue }
            $name=if(-not [string]::IsNullOrWhiteSpace([string]$item.name)){[string]$item.name}else{'Item '+$id}
            $category=if(-not [string]::IsNullOrWhiteSpace([string]$item.category)){[string]$item.category}else{'Unknown'}
            $resultRows += [pscustomobject]@{itemId=$id;name=$name;category=$category}
        }
    }
    return @($resultRows | Sort-Object name,itemId)
}

$catalog=@(Get-ActiveCatalogRows)
$rows=@()
$titleText=''; $allLabel='All'; $showAllToggle=$true

if ($Filter -eq 'Item') {
    $titleText='Item filter'; $allLabel='All active items'
    if($catalog.Count -eq 0) { throw 'No active item catalog rows are available for the Item filter.' }
    $selected=New-IntSet @($prefs.selectedItemIds)
    foreach ($item in $catalog) {
        $checked=([bool]$prefs.itemFilterAll -or $selected.ContainsKey([string][int]$item.itemId))
        $rows += (New-PopupRow ([string]$item.itemId) ('{0}  [{1}]' -f $item.name,$item.category) $checked)
    }
} elseif ($Filter -eq 'Category') {
    $titleText='Category filter'; $allLabel='All active categories'
    $selected=New-StringSet @($prefs.selectedCategories)
    foreach ($category in @($catalog | ForEach-Object { [string]$_.category } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)) {
        $rows += (New-PopupRow $category $category ([bool]$prefs.categoryFilterAll -or $selected.ContainsKey($category)))
    }
} elseif ($Filter -eq 'Country') {
    if ($null -eq $countries -or -not $countries.PSObject.Properties['countries']) { throw 'countries.json is missing or invalid.' }
    $titleText='Countries in selected trip bands'; $allLabel='All countries in selected bands'
    $bands=New-StringSet @($prefs.selectedTripBands)
    $selected=New-StringSet @($prefs.selectedCountryIds)
    foreach ($country in @($countries.countries | Where-Object { $_.collect -eq $true -and $bands.ContainsKey([string]$_.tripBand) } | Sort-Object tripBand,name)) {
        $band=[string]$country.tripBand
        $label='{0}  [{1}]' -f [string]$country.name,($band.Substring(0,1).ToUpperInvariant()+$band.Substring(1))
        $rows += (New-PopupRow ([string]$country.id) $label ($selected.ContainsKey([string]$country.id)))
    }
} else {
    $titleText='Ignore List'; $showAllToggle=$false
    $ignored=New-IntSet @($prefs.ignoredItemIds)
    $allMetadata=@()
    if ($null -ne $engine -and $engine.PSObject.Properties['itemMetadata']) {
        foreach ($p in $engine.itemMetadata.PSObject.Properties) {
            $id=0
            if(-not [int]::TryParse([string]$p.Name,[ref]$id) -or $id -le 0) { continue }
            $v=$p.Value
            if($null -eq $v) { continue }
            $name=if ($v.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$v.name)){[string]$v.name}else{'Item '+$id}
            $category=if($v.PSObject.Properties['category']){[string]$v.category}else{'Unknown'}
            $allMetadata += [pscustomobject]@{itemId=$id;name=$name;category=$category}
        }
    }
    if ($allMetadata.Count -eq 0) { foreach ($item in $catalog) { $allMetadata += $item } }
    foreach ($item in @($allMetadata | Sort-Object name,itemId)) {
        $rows += (New-PopupRow ([string]$item.itemId) ('{0}  [{1}]  #{2}' -f $item.name,$item.category,$item.itemId) ($ignored.ContainsKey([string][int]$item.itemId)))
    }
}

$form=New-Object System.Windows.Forms.Form
$form.Text='Travel Assistant - '+$titleText
$form.Size=New-Object System.Drawing.Size(500,610)
$form.StartPosition='CenterScreen'
$form.FormBorderStyle='FixedDialog'
$form.MaximizeBox=$false
$form.MinimizeBox=$false
$form.BackColor=[System.Drawing.Color]::FromArgb(31,35,40)
$form.ForeColor=[System.Drawing.Color]::FromArgb(222,226,232)
$form.Font=New-Object System.Drawing.Font('Segoe UI',9)
$form.Add_Shown({$form.Activate()})

$title=New-Object System.Windows.Forms.Label
$title.Text=$titleText.ToUpperInvariant(); $title.Location=New-Object System.Drawing.Point(16,14); $title.Size=New-Object System.Drawing.Size(450,26); $title.Font=New-Object System.Drawing.Font('Segoe UI Semibold',12); $form.Controls.Add($title)
$note=New-Object System.Windows.Forms.Label; $note.Location=New-Object System.Drawing.Point(16,42); $note.Size=New-Object System.Drawing.Size(450,42); $note.ForeColor=[System.Drawing.Color]::FromArgb(145,152,164)
if ($Filter -eq 'Ignore') { $note.Text='Checked items are hidden and excluded from broad per-item Torn market-price requests. Stock/history collection continues.' }
elseif ($Filter -eq 'Country') { $note.Text='Short / Medium / Long choose bands. Use this list for country-level exceptions within enabled bands.' }
else { $note.Text='Persistent opportunity filter. It changes ranked candidates only; collected stock/history is retained.' }
$form.Controls.Add($note)

$allCheck=New-Object System.Windows.Forms.CheckBox; $allCheck.Text=$allLabel; $allCheck.Location=New-Object System.Drawing.Point(18,86); $allCheck.Size=New-Object System.Drawing.Size(320,24); $allCheck.Visible=$showAllToggle; $form.Controls.Add($allCheck)
$list=New-Object System.Windows.Forms.CheckedListBox; $list.Location=New-Object System.Drawing.Point(16,116); $list.Size=New-Object System.Drawing.Size(450,386); $list.BackColor=[System.Drawing.Color]::FromArgb(20,23,27); $list.ForeColor=[System.Drawing.Color]::FromArgb(232,235,240); $list.CheckOnClick=$true; $list.HorizontalScrollbar=$true; $form.Controls.Add($list)
foreach ($row in $rows) { $idx=$list.Items.Add([string]$row.Label); $list.SetItemChecked($idx,[bool]$row.Checked) }
$script:updating=$false
function Refresh-All { if(-not $showAllToggle){return}; $all=$list.Items.Count -gt 0; for($i=0;$i-lt$list.Items.Count;$i++){if(-not $list.GetItemChecked($i)){$all=$false;break}}; $script:updating=$true; try{$allCheck.Checked=$all}finally{$script:updating=$false} }
$allCheck.Add_CheckedChanged({ if($script:updating){return}; for($i=0;$i-lt$list.Items.Count;$i++){$list.SetItemChecked($i,$allCheck.Checked)} })
$list.Add_ItemCheck({ $form.BeginInvoke([Action]{Refresh-All})|Out-Null }); Refresh-All
if($Filter -eq 'Country' -and $rows.Count -eq 0){$note.Text='No trip bands are enabled. Turn on Short, Medium, or Long first.'}

$select=New-Object System.Windows.Forms.Button; $select.Text=if($Filter -eq 'Ignore'){'Clear ignore list'}else{'Reset / select all'}; $select.Location=New-Object System.Drawing.Point(16,518); $select.Size=New-Object System.Drawing.Size(135,30); $form.Controls.Add($select)
$select.Add_Click({$target=$Filter -ne 'Ignore';for($i=0;$i-lt$list.Items.Count;$i++){$list.SetItemChecked($i,$target)};Refresh-All})
$save=New-Object System.Windows.Forms.Button; $save.Text='Save'; $save.Location=New-Object System.Drawing.Point(292,518); $save.Size=New-Object System.Drawing.Size(82,30); $save.BackColor=[System.Drawing.Color]::FromArgb(82,174,255); $save.ForeColor=[System.Drawing.Color]::Black; $form.Controls.Add($save)
$cancel=New-Object System.Windows.Forms.Button; $cancel.Text='Cancel'; $cancel.Location=New-Object System.Drawing.Point(384,518); $cancel.Size=New-Object System.Drawing.Size(82,30); $form.Controls.Add($cancel); $cancel.Add_Click({$form.Close()})

$save.Add_Click({
    try {
        $selected=@(); for($i=0;$i-lt$rows.Count;$i++){if($list.GetItemChecked($i)){$selected += [string]$rows[$i].Id}}
        if($Filter -eq 'Item') {
            Set-FilterProperty $prefs 'itemFilterAll' ($rows.Count -gt 0 -and $selected.Count -eq $rows.Count)
            Set-FilterProperty $prefs 'selectedItemIds' ([int[]]@($selected|ForEach-Object{[int]$_}))
        } elseif($Filter -eq 'Category') {
            Set-FilterProperty $prefs 'categoryFilterAll' ($rows.Count -gt 0 -and $selected.Count -eq $rows.Count)
            Set-FilterProperty $prefs 'selectedCategories' ([string[]]$selected)
        } elseif($Filter -eq 'Country') {
            $displayed=@($rows | ForEach-Object {[string]$_.Id})
            $result=@()
            foreach($id in @($prefs.selectedCountryIds)){if($displayed -notcontains [string]$id){$result += [string]$id}}
            foreach($id in $selected){if($result -notcontains [string]$id){$result += [string]$id}}
            Set-FilterProperty $prefs 'selectedCountryIds' ([string[]]@($result|Sort-Object -Unique))
        } else {
            Set-FilterProperty $prefs 'ignoredItemIds' ([int[]]@($selected|ForEach-Object{[int]$_}|Sort-Object -Unique))
        }
        [void](Save-UiPreferences $prefs)
        Start-FilterProjectionRefresh
        Clear-TravelAssistantLatestError -Component $logComponent
        $form.Close()
    } catch {
        Write-TravelAssistantLog -Level ERROR -Component $logComponent -Message (Format-TravelAssistantErrorRecord $_)
        [System.Windows.Forms.MessageBox]::Show(('Unable to save the {0} filter. See the Travel Assistant runtime log for details.' -f $Filter),'Travel Assistant','OK','Error') | Out-Null
    }
})
$form.AcceptButton=$save; $form.CancelButton=$cancel; [void]$form.ShowDialog()
