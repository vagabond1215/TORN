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
$FlagDir=Join-Path $ProjectRoot '@Resources\Images\Flags'
$logComponent='popup-filter-unified'

$ColorPanel=[System.Drawing.Color]::FromArgb(24,27,31)
$ColorCard=[System.Drawing.Color]::FromArgb(31,35,40)
$ColorInput=[System.Drawing.Color]::FromArgb(20,23,27)
$ColorBorder=[System.Drawing.Color]::FromArgb(58,64,73)
$ColorText=[System.Drawing.Color]::FromArgb(222,226,232)
$ColorMuted=[System.Drawing.Color]::FromArgb(145,152,164)
$ColorAccent=[System.Drawing.Color]::FromArgb(82,174,255)
$ColorSelected=[System.Drawing.Color]::FromArgb(37,46,55)

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
$countriesConfig=Read-PopupJson (Join-Path $ConfigDir 'countries.json')
$engine=Read-OptionalPopupJson $EngineStateFile
if($null -eq $countriesConfig -or -not $countriesConfig.PSObject.Properties['countries']) { throw 'countries.json is missing or invalid.' }

function Get-ActiveCatalogRows {
    $activeIds=@{}
    if($null -ne $engine -and $engine.PSObject.Properties['observedMarkets']) {
        foreach($p in $engine.observedMarkets.PSObject.Properties) {
            $market=$p.Value
            if($null -eq $market) { continue }
            if(($market.PSObject.Properties['catalogActive'] -and $market.catalogActive -eq $false) -or ($market.PSObject.Properties['catalogStatus'] -and [string]$market.catalogStatus -eq 'legacy_removed')) { continue }
            if($market.PSObject.Properties['itemId']) {
                $id=0
                if([int]::TryParse([string]$market.itemId,[ref]$id) -and $id -gt 0) { $activeIds[[string]$id]=$true }
            }
        }
    }

    $rows=@()
    if($null -ne $engine -and $engine.PSObject.Properties['itemMetadata']) {
        foreach($p in $engine.itemMetadata.PSObject.Properties) {
            $id=0
            if(-not [int]::TryParse([string]$p.Name,[ref]$id) -or $id -le 0) { continue }
            if($activeIds.Count -gt 0 -and -not $activeIds.ContainsKey([string]$id)) { continue }
            $value=$p.Value
            if($null -eq $value) { continue }
            $name=if($value.PSObject.Properties['name'] -and -not [string]::IsNullOrWhiteSpace([string]$value.name)){[string]$value.name}else{'Item '+$id}
            $category=if($value.PSObject.Properties['category'] -and -not [string]::IsNullOrWhiteSpace([string]$value.category)){[string]$value.category}else{'Unknown'}
            $rows += [pscustomobject]@{itemId=$id;name=$name;category=$category}
        }
    }

    if($rows.Count -eq 0 -and $null -ne $items -and $items.PSObject.Properties['items']) {
        foreach($item in @($items.items)) {
            if($item.PSObject.Properties['visible'] -and $item.visible -eq $false) { continue }
            $id=0
            if(-not [int]::TryParse([string]$item.itemId,[ref]$id) -or $id -le 0) { continue }
            if($activeIds.Count -gt 0 -and -not $activeIds.ContainsKey([string]$id)) { continue }
            $name=if(-not [string]::IsNullOrWhiteSpace([string]$item.name)){[string]$item.name}else{'Item '+$id}
            $category=if(-not [string]::IsNullOrWhiteSpace([string]$item.category)){[string]$item.category}else{'Unknown'}
            $rows += [pscustomobject]@{itemId=$id;name=$name;category=$category}
        }
    }
    return @($rows | Sort-Object name,itemId)
}

$catalog=@(Get-ActiveCatalogRows)
if($catalog.Count -eq 0) { throw 'No active item catalog rows are available for the unified filter panel.' }
$countries=@($countriesConfig.countries | Where-Object { $_.collect -eq $true })
$categories=@($catalog | ForEach-Object { [string]$_.category } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Sort-Object -Unique)

$selectedCountrySet=New-StringSet @($prefs.selectedCountryIds)
$displayBandSet=New-StringSet @($prefs.displayTripBands)
$script:countrySelection=@{}
foreach($country in $countries) {
    $id=[string]$country.id
    $band=[string]$country.tripBand
    $script:countrySelection[$id]=($selectedCountrySet.ContainsKey($id) -and $displayBandSet.ContainsKey($band))
}

$selectedCategorySet=New-StringSet @($prefs.selectedCategories)
$script:categorySelection=@{}
foreach($category in $categories) {
    $script:categorySelection[$category]=([bool]$prefs.categoryFilterAll -or $selectedCategorySet.ContainsKey($category))
}

$selectedItemSet=New-IntSet @($prefs.selectedItemIds)
$script:itemSelection=@{}
foreach($item in $catalog) {
    $id=[string][int]$item.itemId
    $script:itemSelection[$id]=([bool]$prefs.itemFilterAll -or $selectedItemSet.ContainsKey($id))
}

$script:countryChips=@{}
$script:categoryChips=@{}
$script:itemRowsByIndex=@()
$script:itemListRefreshing=$false
$script:resetProfitable=$false
$script:ownedImages=New-Object System.Collections.Generic.List[System.Drawing.Image]

$flagCodes=@{
    mexico='MX'; cayman_islands='KY'; canada='CA'; hawaii='US'; united_kingdom='GB'; argentina='AR'; switzerland='CH';
    japan='JP'; china='CN'; united_arab_emirates='AE'; south_africa='ZA'
}

function Get-CountryFlagImage([string]$CountryId) {
    if(-not $flagCodes.ContainsKey($CountryId)) { return $null }
    $path=Join-Path $FlagDir ($flagCodes[$CountryId]+'@3x.png')
    if(-not (Test-Path -LiteralPath $path)) { return $null }
    try {
        $source=[System.Drawing.Image]::FromFile($path)
        try {
            $bitmap=New-Object System.Drawing.Bitmap($source,24,16)
            $script:ownedImages.Add($bitmap)
            return $bitmap
        } finally { $source.Dispose() }
    } catch { return $null }
}

function Set-ChipStyle($Chip) {
    if([bool]$Chip.Checked) {
        $Chip.BackColor=$ColorSelected
        $Chip.ForeColor=$ColorText
        $Chip.FlatAppearance.BorderColor=$ColorAccent
    } else {
        $Chip.BackColor=$ColorCard
        $Chip.ForeColor=$ColorMuted
        $Chip.FlatAppearance.BorderColor=$ColorBorder
    }
}

function New-Chip([string]$Text,[int]$Width,[bool]$Checked,[System.Drawing.Image]$Image=$null) {
    $chip=New-Object System.Windows.Forms.CheckBox
    $chip.Appearance=[System.Windows.Forms.Appearance]::Button
    $chip.AutoSize=$false
    $chip.Size=New-Object System.Drawing.Size($Width,30)
    $chip.Text=$Text
    $chip.Checked=$Checked
    $chip.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat
    $chip.FlatAppearance.BorderSize=1
    $chip.TextAlign=[System.Drawing.ContentAlignment]::MiddleCenter
    $chip.Font=New-Object System.Drawing.Font('Segoe UI Semibold',8)
    $chip.Margin=New-Object System.Windows.Forms.Padding(0,0,6,6)
    $chip.Padding=New-Object System.Windows.Forms.Padding(4,0,4,0)
    if($null -ne $Image) {
        $chip.Image=$Image
        $chip.ImageAlign=[System.Drawing.ContentAlignment]::MiddleLeft
        $chip.TextImageRelation=[System.Windows.Forms.TextImageRelation]::ImageBeforeText
    }
    Set-ChipStyle $chip
    return $chip
}

function New-SectionHeader([string]$Text,[int]$Y,[System.Windows.Forms.Control]$Parent) {
    $label=New-Object System.Windows.Forms.Label
    $label.Text=$Text
    $label.Location=New-Object System.Drawing.Point(0,$Y)
    $label.Size=New-Object System.Drawing.Size(220,22)
    $label.Font=New-Object System.Drawing.Font('Segoe UI Semibold',9)
    $label.ForeColor=$ColorMuted
    $Parent.Controls.Add($label)
    return $label
}

function New-ActionLink([string]$Text,[int]$X,[int]$Y,[System.Windows.Forms.Control]$Parent) {
    $link=New-Object System.Windows.Forms.LinkLabel
    $link.Text=$Text
    $link.Location=New-Object System.Drawing.Point($X,$Y)
    $link.Size=New-Object System.Drawing.Size(42,20)
    $link.TextAlign=[System.Drawing.ContentAlignment]::MiddleRight
    $link.Font=New-Object System.Drawing.Font('Segoe UI Semibold',8)
    $link.LinkColor=$ColorMuted
    $link.ActiveLinkColor=$ColorAccent
    $link.VisitedLinkColor=$ColorMuted
    $link.LinkBehavior=[System.Windows.Forms.LinkBehavior]::NeverUnderline
    $Parent.Controls.Add($link)
    return $link
}

function Set-CountrySelection([string]$CountryId,[bool]$Value) {
    $script:countrySelection[$CountryId]=$Value
    if($script:countryChips.ContainsKey($CountryId)) {
        $chip=$script:countryChips[$CountryId]
        if($chip.Checked -ne $Value) { $chip.Checked=$Value }
        Set-ChipStyle $chip
    }
}
function Set-BandSelection([string]$Band,[bool]$Value) {
    foreach($country in $countries) {
        if([string]$country.tripBand -eq $Band) { Set-CountrySelection -CountryId ([string]$country.id) -Value $Value }
    }
}
function Set-AllCountries([bool]$Value) {
    foreach($country in $countries) { Set-CountrySelection -CountryId ([string]$country.id) -Value $Value }
}
function Set-CategorySelection([string]$Category,[bool]$Value) {
    $script:categorySelection[$Category]=$Value
    if($script:categoryChips.ContainsKey($Category)) {
        $chip=$script:categoryChips[$Category]
        if($chip.Checked -ne $Value) { $chip.Checked=$Value }
        Set-ChipStyle $chip
    }
}
function Set-AllCategories([bool]$Value) {
    foreach($category in $categories) { Set-CategorySelection -Category $category -Value $Value }
}

$form=New-Object System.Windows.Forms.Form
$form.Text='Travel Assistant - Trip & Filters'
$form.ClientSize=New-Object System.Drawing.Size(442,748)
$form.StartPosition='CenterScreen'
$form.FormBorderStyle='FixedDialog'
$form.MaximizeBox=$false
$form.MinimizeBox=$false
$form.BackColor=$ColorPanel
$form.ForeColor=$ColorText
$form.Font=New-Object System.Drawing.Font('Segoe UI',9)
$form.Add_Shown({$form.Activate()})
$form.Add_FormClosed({ foreach($image in $script:ownedImages) { try { $image.Dispose() } catch { } } })

$title=New-Object System.Windows.Forms.Label
$title.Text='TRIP & FILTERS'
$title.Location=New-Object System.Drawing.Point(16,13)
$title.Size=New-Object System.Drawing.Size(240,28)
$title.Font=New-Object System.Drawing.Font('Segoe UI Semibold',13)
$title.ForeColor=$ColorText
$form.Controls.Add($title)

$reset=New-Object System.Windows.Forms.Button
$reset.Text='Reset'
$reset.Location=New-Object System.Drawing.Point(354,10)
$reset.Size=New-Object System.Drawing.Size(70,28)
$reset.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat
$reset.FlatAppearance.BorderColor=$ColorBorder
$reset.BackColor=$ColorCard
$reset.ForeColor=$ColorMuted
$form.Controls.Add($reset)

$content=New-Object System.Windows.Forms.Panel
$content.Location=New-Object System.Drawing.Point(14,47)
$content.Size=New-Object System.Drawing.Size(414,630)
$content.AutoScroll=$true
$content.BackColor=$ColorPanel
$form.Controls.Add($content)

$y=0
[void](New-SectionHeader 'COUNTRIES' $y $content)
$countryAll=New-ActionLink 'All' 318 $y $content
$countryNone=New-ActionLink 'None' 360 $y $content
$countryAll.Add_Click({ Set-AllCountries $true })
$countryNone.Add_Click({ Set-AllCountries $false })
$y+=24

$bandOrder=@('short','medium','long')
$bandLabels=@{short='SHORT';medium='MEDIUM';long='LONG'}
foreach($band in $bandOrder) {
    $panel=New-Object System.Windows.Forms.Panel
    $panel.Location=New-Object System.Drawing.Point(0,$y)
    $panel.Size=New-Object System.Drawing.Size(394,88)
    $panel.BackColor=$ColorPanel
    $content.Controls.Add($panel)

    $label=New-Object System.Windows.Forms.Label
    $label.Text=$bandLabels[$band]
    $label.Location=New-Object System.Drawing.Point(4,1)
    $label.Size=New-Object System.Drawing.Size(150,20)
    $label.Font=New-Object System.Drawing.Font('Segoe UI Semibold',8)
    $label.ForeColor=$ColorMuted
    $panel.Controls.Add($label)

    $all=New-ActionLink 'All' 306 0 $panel
    $none=New-ActionLink 'None' 348 0 $panel
    $all.Add_Click(({ Set-BandSelection -Band $band -Value $true }).GetNewClosure())
    $none.Add_Click(({ Set-BandSelection -Band $band -Value $false }).GetNewClosure())

    $flow=New-Object System.Windows.Forms.FlowLayoutPanel
    $flow.Location=New-Object System.Drawing.Point(4,23)
    $flow.Size=New-Object System.Drawing.Size(386,62)
    $flow.WrapContents=$true
    $flow.FlowDirection=[System.Windows.Forms.FlowDirection]::LeftToRight
    $flow.BackColor=$ColorPanel
    $panel.Controls.Add($flow)

    foreach($country in @($countries | Where-Object { [string]$_.tripBand -eq $band } | Sort-Object name)) {
        $id=[string]$country.id
        $name=[string]$country.name
        $textWidth=[System.Windows.Forms.TextRenderer]::MeasureText($name,(New-Object System.Drawing.Font('Segoe UI Semibold',8))).Width
        $chipWidth=[Math]::Min(180,[Math]::Max(96,$textWidth+44))
        $chip=New-Chip -Text $name -Width $chipWidth -Checked ([bool]$script:countrySelection[$id]) -Image (Get-CountryFlagImage $id)
        $script:countryChips[$id]=$chip
        $chip.Add_CheckedChanged(({ $script:countrySelection[$id]=[bool]$chip.Checked; Set-ChipStyle $chip }).GetNewClosure())
        $flow.Controls.Add($chip)
    }
    $y+=88
}

$separator1=New-Object System.Windows.Forms.Label
$separator1.Location=New-Object System.Drawing.Point(0,$y+2)
$separator1.Size=New-Object System.Drawing.Size(394,1)
$separator1.BackColor=$ColorBorder
$content.Controls.Add($separator1)
$y+=15

[void](New-SectionHeader 'CATEGORIES' $y $content)
$categoryAll=New-ActionLink 'All' 318 $y $content
$categoryNone=New-ActionLink 'None' 360 $y $content
$categoryAll.Add_Click({ Set-AllCategories $true })
$categoryNone.Add_Click({ Set-AllCategories $false })
$y+=24

$categoryFlow=New-Object System.Windows.Forms.FlowLayoutPanel
$categoryFlow.Location=New-Object System.Drawing.Point(4,$y)
$categoryFlow.Size=New-Object System.Drawing.Size(390,126)
$categoryFlow.WrapContents=$true
$categoryFlow.FlowDirection=[System.Windows.Forms.FlowDirection]::LeftToRight
$categoryFlow.BackColor=$ColorPanel
$content.Controls.Add($categoryFlow)
foreach($category in $categories) {
    $textWidth=[System.Windows.Forms.TextRenderer]::MeasureText($category,(New-Object System.Drawing.Font('Segoe UI Semibold',8))).Width
    $chipWidth=[Math]::Min(150,[Math]::Max(86,$textWidth+24))
    $chip=New-Chip -Text $category -Width $chipWidth -Checked ([bool]$script:categorySelection[$category])
    $script:categoryChips[$category]=$chip
    $chip.Add_CheckedChanged(({ $script:categorySelection[$category]=[bool]$chip.Checked; Set-ChipStyle $chip }).GetNewClosure())
    $categoryFlow.Controls.Add($chip)
}
$y+=132

$separator2=New-Object System.Windows.Forms.Label
$separator2.Location=New-Object System.Drawing.Point(0,$y+2)
$separator2.Size=New-Object System.Drawing.Size(394,1)
$separator2.BackColor=$ColorBorder
$content.Controls.Add($separator2)
$y+=15

[void](New-SectionHeader 'ITEMS' $y $content)
$itemAll=New-ActionLink 'All' 318 $y $content
$itemNone=New-ActionLink 'None' 360 $y $content
$y+=25

$search=New-Object System.Windows.Forms.TextBox
$search.Location=New-Object System.Drawing.Point(4,$y)
$search.Size=New-Object System.Drawing.Size(386,27)
$search.BackColor=$ColorInput
$search.ForeColor=$ColorText
$search.BorderStyle=[System.Windows.Forms.BorderStyle]::FixedSingle
$content.Controls.Add($search)
$y+=32

$itemCount=New-Object System.Windows.Forms.Label
$itemCount.Location=New-Object System.Drawing.Point(4,$y)
$itemCount.Size=New-Object System.Drawing.Size(386,18)
$itemCount.Font=New-Object System.Drawing.Font('Segoe UI',8)
$itemCount.ForeColor=$ColorMuted
$content.Controls.Add($itemCount)
$y+=20

$itemList=New-Object System.Windows.Forms.CheckedListBox
$itemList.Location=New-Object System.Drawing.Point(4,$y)
$itemList.Size=New-Object System.Drawing.Size(386,230)
$itemList.BackColor=$ColorInput
$itemList.ForeColor=$ColorText
$itemList.BorderStyle=[System.Windows.Forms.BorderStyle]::FixedSingle
$itemList.CheckOnClick=$true
$itemList.IntegralHeight=$false
$itemList.HorizontalScrollbar=$true
$content.Controls.Add($itemList)
$y+=238
$content.AutoScrollMinSize=New-Object System.Drawing.Size(0,$y+8)

function Update-ItemCount {
    $selected=0
    foreach($item in $catalog) { if([bool]$script:itemSelection[[string][int]$item.itemId]) { $selected++ } }
    $itemCount.Text=('Search items  |  {0} of {1} selected' -f $selected,$catalog.Count)
}
function Refresh-ItemList {
    $query=([string]$search.Text).Trim().ToLowerInvariant()
    $script:itemListRefreshing=$true
    try {
        $itemList.Items.Clear()
        $visible=@()
        foreach($item in $catalog) {
            $id=[string][int]$item.itemId
            $haystack=(([string]$item.name)+' '+([string]$item.category)+' '+$id).ToLowerInvariant()
            if($query -ne '' -and -not $haystack.Contains($query)) { continue }
            $visible += $item
            $index=$itemList.Items.Add(('{0}  [{1}]' -f [string]$item.name,[string]$item.category))
            $itemList.SetItemChecked($index,[bool]$script:itemSelection[$id])
        }
        $script:itemRowsByIndex=@($visible)
    } finally { $script:itemListRefreshing=$false }
    Update-ItemCount
}
$itemList.Add_ItemCheck({
    param($sender,$eventArgs)
    if($script:itemListRefreshing) { return }
    if($eventArgs.Index -lt 0 -or $eventArgs.Index -ge $script:itemRowsByIndex.Count) { return }
    $row=$script:itemRowsByIndex[$eventArgs.Index]
    $id=[string][int]$row.itemId
    $script:itemSelection[$id]=($eventArgs.NewValue -eq [System.Windows.Forms.CheckState]::Checked)
    $form.BeginInvoke([Action]{ Update-ItemCount }) | Out-Null
})
$search.Add_TextChanged({ Refresh-ItemList })
$itemAll.Add_Click({ foreach($item in $catalog) { $script:itemSelection[[string][int]$item.itemId]=$true }; Refresh-ItemList })
$itemNone.Add_Click({ foreach($item in $catalog) { $script:itemSelection[[string][int]$item.itemId]=$false }; Refresh-ItemList })
Refresh-ItemList

$reset.Add_Click({
    Set-AllCountries $true
    Set-AllCategories $true
    foreach($item in $catalog) { $script:itemSelection[[string][int]$item.itemId]=$true }
    $script:resetProfitable=$true
    $search.Text=''
    Refresh-ItemList
})

$save=New-Object System.Windows.Forms.Button
$save.Text='Save'
$save.Location=New-Object System.Drawing.Point(254,695)
$save.Size=New-Object System.Drawing.Size(82,32)
$save.BackColor=$ColorAccent
$save.ForeColor=[System.Drawing.Color]::Black
$save.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat
$save.FlatAppearance.BorderColor=$ColorAccent
$form.Controls.Add($save)

$cancel=New-Object System.Windows.Forms.Button
$cancel.Text='Cancel'
$cancel.Location=New-Object System.Drawing.Point(344,695)
$cancel.Size=New-Object System.Drawing.Size(82,32)
$cancel.BackColor=$ColorCard
$cancel.ForeColor=$ColorText
$cancel.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat
$cancel.FlatAppearance.BorderColor=$ColorBorder
$form.Controls.Add($cancel)
$cancel.Add_Click({$form.Close()})

$save.Add_Click({
    try {
        $current=Read-UiPreferences

        $selectedCountries=@()
        $selectedBands=@()
        foreach($band in $bandOrder) {
            $bandSelected=$false
            foreach($country in $countries) {
                if([string]$country.tripBand -ne $band) { continue }
                $id=[string]$country.id
                if([bool]$script:countrySelection[$id]) {
                    $selectedCountries += $id
                    $bandSelected=$true
                }
            }
            if($bandSelected) { $selectedBands += $band }
        }

        $selectedCategories=@()
        foreach($category in $categories) { if([bool]$script:categorySelection[$category]) { $selectedCategories += $category } }

        $selectedItems=@()
        foreach($item in $catalog) {
            $id=[string][int]$item.itemId
            if([bool]$script:itemSelection[$id]) { $selectedItems += [int]$item.itemId }
        }

        Set-FilterProperty $current 'selectedTripBands' ([string[]]@('short','medium','long'))
        Set-FilterProperty $current 'displayTripBands' ([string[]]@($selectedBands))
        Set-FilterProperty $current 'selectedCountryIds' ([string[]]@($selectedCountries | Sort-Object -Unique))
        Set-FilterProperty $current 'categoryFilterAll' ($categories.Count -gt 0 -and $selectedCategories.Count -eq $categories.Count)
        Set-FilterProperty $current 'selectedCategories' ([string[]]@($selectedCategories | Sort-Object -Unique))
        Set-FilterProperty $current 'itemFilterAll' ($catalog.Count -gt 0 -and $selectedItems.Count -eq $catalog.Count)
        Set-FilterProperty $current 'selectedItemIds' ([int[]]@($selectedItems | Sort-Object -Unique))
        if($script:resetProfitable) { Set-FilterProperty $current 'showProfitableOnly' $false }

        [void](Save-UiPreferences $current)
        Start-FilterProjectionRefresh
        Clear-TravelAssistantLatestError -Component $logComponent
        $form.Close()
    } catch {
        Write-TravelAssistantLog -Level ERROR -Component $logComponent -Message (Format-TravelAssistantErrorRecord $_)
        [System.Windows.Forms.MessageBox]::Show('Unable to save filters. See the Travel Assistant runtime log for details.','Travel Assistant','OK','Error') | Out-Null
    }
})

$form.AcceptButton=$save
$form.CancelButton=$cancel
[void]$form.ShowDialog()
