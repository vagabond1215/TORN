$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$rowsPath=Join-Path $ProjectRoot '@Resources\Includes\OpportunityRows.inc'
$readerPath=Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
$presenterPath=Join-Path $ProjectRoot '@Resources\Scripts\CardPresenter.lua'
$tweaksPath=Join-Path $ProjectRoot '@Resources\Scripts\CardTweaks.lua'
$polishPath=Join-Path $ProjectRoot '@Resources\Scripts\FinalCardPolish.lua'
$headerPath=Join-Path $ProjectRoot '@Resources\Scripts\HeaderLayout.lua'
$iniPath=Join-Path $ProjectRoot 'TravelAssistant.ini'

$errors=New-Object System.Collections.Generic.List[string]
function Fail([string]$Message){$script:errors.Add($Message)}

foreach($path in @($rowsPath,$readerPath,$presenterPath,$tweaksPath,$polishPath,$headerPath,$iniPath)){
    if(-not(Test-Path -LiteralPath $path)){Fail "Missing compact-card asset: $path"}
}

if($errors.Count -eq 0){
    $rows=Get-Content -LiteralPath $rowsPath -Raw
    $reader=Get-Content -LiteralPath $readerPath -Raw
    $presenter=Get-Content -LiteralPath $presenterPath -Raw
    $tweaks=Get-Content -LiteralPath $tweaksPath -Raw
    $polish=Get-Content -LiteralPath $polishPath -Raw
    $header=Get-Content -LiteralPath $headerPath -Raw
    $ini=Get-Content -LiteralPath $iniPath -Raw

    foreach($i in 1..8){
        foreach($suffix in @('Card','Flag','FlagMask','CardBorder','ItemImage','Name','DetailEachLabel','Gross','DetailEachNet','DetailEachTax','DetailTotalLabel','DetailTotal','DetailTotalNet','DetailTotalTax','Price','Take','Make','Leave','DetailToggle','Graph','InlineGraph')){
            $section='MeterOpportunity'+$i+$suffix
            if($rows -notmatch ('(?m)^\['+[regex]::Escape($section)+'\]\s*$')){
                Fail "OpportunityRows.inc missing [$section]."
            }
        }

        $card=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Card\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        $cardYMatch=[regex]::Match($card,'(?im)^Y=(\d+)\s*$')
        $cardY=if($cardYMatch.Success){[int]$cardYMatch.Groups[1].Value}else{-1}
        foreach($token in @('Shape2=Line 510,0,510,50 | StrokeWidth 1 | Stroke Color #Border#','Shape3=Line 510,25,536,25 | StrokeWidth 1 | Stroke Color #Border#')){
            if(-not$card.Contains($token)){Fail "Row $i card end-cap separator missing '$token'."}
        }
        if($card -notmatch ('ToggleCardExpanded\('+[string]$i+'\)')){Fail "Row $i card body must toggle both expansion sections."}

        $detail=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailToggle\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if($detail -notmatch '(?im)^Text=\$\s*$'){Fail "Row $i detail toggle must default to the money button."}
        foreach($token in @('X=531','W=24','H=23','StringAlign=CenterCenter','FontColor=#ToggleIdle#','SolidColor=0,0,0,1')){
            if(-not$detail.Contains($token)){Fail "Row $i money end-cap button missing '$token'."}
        }
        if($detail -notmatch ('ToggleCardDetails\('+[string]$i+'\)')){Fail "Row $i detail toggle must call ToggleCardDetails($i)."}

        $graph=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Graph\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if($graph -notmatch '(?im)^Meter=Shape\s*$' -or $graph -notmatch '(?im)^GraphExpanded=0\s*$'){Fail "Row $i graph button must be a collapsed Shape icon by default."}
        foreach($token in @('X=519','W=24','H=23','Shape=Rectangle 0,0,24,23 | Fill Color 0,0,0,1 | StrokeWidth 0','Stroke Color #ToggleIdle#','Shape2=Line 7,16,7,7','Shape3=Line 7,16,17,16','Shape4=Line 8,14,11,11','Shape5=Line 11,11,13,13','Shape6=Line 13,13,17,8')){
            if(-not$graph.Contains($token)){Fail "Row $i chart end-cap button missing '$token'."}
        }
        if($graph -notmatch ('ToggleInlineGraph\('+[string]$i+'\)')){Fail "Row $i graph toggle must call ToggleInlineGraph($i)."}

        $flagBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Flag\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        foreach($token in @('X=8','W=67','H=50','PreserveAspectRatio=1')){
            if(-not$flagBody.Contains($token)){Fail "Row $i flag must extend under the rounded card border without leaving a top/bottom gap; missing '$token'."}
        }
        $flagMask=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'FlagMask\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        foreach($token in @('X=8','W=67','H=50','ImageTint=#Panel#')){
            if(-not$flagMask.Contains($token)){Fail "Row $i flag mask missing '$token'."}
        }
        $itemImage=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'ItemImage\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        foreach($token in @('X=77','W=44','H=44','PreserveAspectRatio=1')){
            if(-not$itemImage.Contains($token)){Fail "Row $i item image missing '$token'."}
        }
        $cardBorder=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'CardBorder\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if(-not$cardBorder.Contains('Shape=Rectangle 0,0,536,50,5 | Fill Color 0,0,0,0 | StrokeWidth 1 | Stroke Color #Border#')){Fail "Row $i card border overlay is missing."}
        $nameBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Name\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if($nameBody -notmatch '(?im)^W=1\s*$' -or $nameBody -notmatch '(?im)^FontSize=12\s*$' -or $nameBody -notmatch '(?im)^FontColor=0,0,0,0\s*$'){
            Fail "Row $i Name meter must remain a hidden canonical lookup surface at the new 12pt typography."
        }

        $priceBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Price\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if($priceBody -notmatch '(?im)^X=123\s*$' -or $priceBody -notmatch '(?im)^W=265\s*$' -or $priceBody -notmatch '(?im)^FontSize=12\s*$'){
            Fail "Row $i combined item/unit/full-load-cost line must start after the 48px item-art cell at x=123 with a 265px width."
        }
        $takeBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Take\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        $leaveBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Leave\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if($takeBody -notmatch '(?im)^X=123\s*$' -or $takeBody -notmatch '(?im)^W=1\s*$' -or $takeBody -notmatch '(?im)^FontColor=0,0,0,0\s*$'){
            Fail "Row $i retired Take surface must remain inert; full-load cost belongs in the Price text run."
        }
        $makeBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Make\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if($makeBody -notmatch '(?im)^X=504\s*$' -or $makeBody -notmatch '(?im)^W=108\s*$' -or $makeBody -notmatch '(?im)^H=50\s*$' -or $makeBody -notmatch '(?im)^FontSize=16\s*$' -or $makeBody -notmatch '(?im)^StringAlign=RightCenter\s*$'){
            Fail "Row $i total net must be 16pt, vertically centered, and right-aligned at x=504."
        }
        if($leaveBody -notmatch '(?im)^FontSize=9\s*$'){Fail "Row $i window/guidance line must use 9pt typography."}
        foreach($fontBody in @($nameBody,$priceBody,$takeBody,$makeBody)){
            if($fontBody -notmatch '(?im)^FontFace=Nirmala UI Semilight\s*$'){Fail "Row $i first-line typography must use Nirmala UI Semilight."}
        }

        $stripEachLabel=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailEachLabel\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        $strip=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Gross\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        $stripEachNet=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailEachNet\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        $stripEachTax=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailEachTax\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        $stripTotalLabel=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailTotalLabel\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        $stripTotal=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailTotal\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        $stripTotalNet=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailTotalNet\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        $stripTotalTax=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailTotalTax\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        foreach($token in @('X=29','W=40','H=32','FontSize=8','StringAlign=CenterCenter','SolidColor=#Border#','Text=Each','Hidden=1')){
            if(-not$stripEachLabel.Contains($token)){Fail "Row $i Each label block missing '$token'."}
        }
        foreach($token in @('X=54','W=112','H=16','FontSize=9','StringAlign=LeftCenter','Hidden=1')){
            if(-not$strip.Contains($token)){Fail "Row $i per-item MV meter missing '$token'."}
        }
        foreach($token in @('X=270','W=98','H=16','StringAlign=RightCenter','Hidden=1')){
            if(-not$stripEachNet.Contains($token)){Fail "Row $i per-item Net meter missing '$token'."}
        }
        foreach($token in @('X=54','W=210','H=16','StringAlign=LeftCenter','Hidden=1')){
            if(-not$stripEachTax.Contains($token)){Fail "Row $i per-item Tax meter missing '$token'."}
        }
        foreach($token in @('X=297','W=40','H=32','FontSize=8','StringAlign=CenterCenter','SolidColor=#Border#','Text=Total','Hidden=1')){
            if(-not$stripTotalLabel.Contains($token)){Fail "Row $i Total label block missing '$token'."}
        }
        foreach($token in @('X=322','W=112','H=16','FontSize=9','StringAlign=LeftCenter','Hidden=1')){
            if(-not$stripTotal.Contains($token)){Fail "Row $i total MV meter missing '$token'."}
        }
        foreach($token in @('X=538','W=98','H=16','StringAlign=RightCenter','Hidden=1')){
            if(-not$stripTotalNet.Contains($token)){Fail "Row $i total Net meter missing '$token'."}
        }
        foreach($token in @('X=322','W=210','H=16','StringAlign=LeftCenter','Hidden=1')){
            if(-not$stripTotalTax.Contains($token)){Fail "Row $i total Tax meter missing '$token'."}
        }
        if($cardY -lt 0){Fail "Row $i card Y could not be parsed for economics baseline validation."}
        else {
            foreach($pair in @(
                @($strip,($cardY+8),'Each MV'),@($stripEachNet,($cardY+8),'Each Net'),@($stripEachTax,($cardY+25),'Each Tax'),
                @($stripTotal,($cardY+8),'Total MV'),@($stripTotalNet,($cardY+8),'Total Net'),@($stripTotalTax,($cardY+25),'Total Tax')
            )){
                $bodyText=[string]$pair[0]
                $expectedY=[int]$pair[1]
                if($bodyText -notmatch ('(?im)^Y='+[string]$expectedY+'\s*$')){Fail "Row $i $($pair[2]) baseline must be 1px above the prior position."}
            }
        }

        $inline=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'InlineGraph\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        foreach($token in @('W=528','H=125',('Group=OpportunityInlineGraph'+$i))){
            if(-not$inline.Contains($token)){Fail "Row $i inline graph missing '$token'."}
        }
    }

    foreach($token in @(
        'local detailExtraWithTax = 34',
        'local detailExtraNoTax = 18',
        'local function detailTaxRate(data, index)',
        'local function detailExtraForRow(data, index)',
        'local graphExtra = 133',
        'local footerExtra = 16',
        "local expandedDetailKey = ''",
        'local expandedDetailRow = 0',
        'local function setGraphButtonState(name, expanded)',
        'local function setDetailButtonState(name, expanded)',
        "'GraphExpanded', expanded and '1' or '0'",
        "'Rectangle 0,0,24,23 | Fill Color '..fill..' | StrokeWidth 0'",
        "SKIN:Bang('!SetOption', name, 'Text', '$')",
        "'126,190,73,255'","local active = '126,190,73,255'","'38,38,38,255'","'190,190,190,255'",
        'local function collapseCardDetails()',
        'local function syncExpandedRows(data, count)',
        'function ToggleCardExpanded(index)','function ToggleCardDetails(index)','local bothExpanded = (expandedDetailKey == key and expandedKey == key)',
        "local activeDetailExtra = detailExtraForRow(data, expandedDetailRow)",
        "local activeDetailHasTax = expandedDetailRow > 0 and detailTaxRate(data, expandedDetailRow) > 0",
        "if expandedDetailRow > 0 and i > expandedDetailRow then extraBefore = extraBefore + activeDetailExtra end",
        "if expandedRow > 0 and i > expandedRow then extraBefore = extraBefore + graphExtra end",
        'local bodyOffset = detailExpanded and activeDetailExtra or 0',
        'local cardHeight = collapsedCardHeight + bodyOffset + (graphExpanded and graphExtra or 0)',
        "'Shape2', 'Line 510,' .. bodyOffset .. ',510,' .. (bodyOffset+50)","'Shape4', 'Line 268,0,268,' .. bodyOffset","'Shape5', 'Line 0,' .. bodyOffset .. ',536,' .. bodyOffset",
        "'Shape3', 'Line 510,' .. (bodyOffset+25) .. ',536,' .. (bodyOffset+25)",
        'local detailLabelCenterY = y + (detailExpanded and math.floor(bodyOffset/2) or 9)',
        "'DetailEachLabel', 'Y', tostring(detailLabelCenterY)","'DetailEachLabel', 'H', tostring(detailLabelHeight)",
        "'Gross', 'Y', tostring(y+8)","'DetailEachNet', 'Y', tostring(y+8)","'DetailEachTax', 'Y', tostring(y+25)",
        "'DetailTotalLabel', 'Y', tostring(detailLabelCenterY)","'DetailTotalLabel', 'H', tostring(detailLabelHeight)",
        "'DetailTotal', 'Y', tostring(y+8)","'DetailTotalNet', 'Y', tostring(y+8)","'DetailTotalTax', 'Y', tostring(y+25)",
        "'DetailToggle', 'Y', tostring(y+13+bodyOffset)",
        "'Flag', 'Y', tostring(y+bodyOffset)","'Flag', 'W', '67'","'Flag', 'H', '50'",
        "'FlagMask', 'Y', tostring(y+bodyOffset)","'ItemImage', 'Y', tostring(y+3+bodyOffset)","'ItemImage', 'W', '44'","'ItemImage', 'H', '44'",
        "'CardBorder', 'Shape', 'Rectangle 0,0,536,' .. cardHeight",
        "'Window', 'Y', tostring(y+34+bodyOffset)","'Leave', 'Y', tostring(y+34+bodyOffset)",
        "'Make', 'Y', tostring(y+25+bodyOffset)","'Graph', 'Y', tostring(y+26+bodyOffset)",
        "panelHeight = 120 + (count * rowStride) + activeDetailExtra + ((expandedRow > 0) and graphExtra or 0) + 8 + footerExtra",
        "SKIN:Bang('!ShowMeter', p .. 'DetailEachLabel')","SKIN:Bang('!ShowMeter', p .. 'DetailEachNet')",
        "if activeDetailHasTax then SKIN:Bang('!ShowMeter', p .. 'DetailEachTax') else SKIN:Bang('!HideMeter', p .. 'DetailEachTax') end",
        "SKIN:Bang('!ShowMeter', p .. 'DetailTotalLabel')","SKIN:Bang('!ShowMeter', p .. 'DetailTotal')","SKIN:Bang('!ShowMeter', p .. 'DetailTotalNet')",
        "if activeDetailHasTax then SKIN:Bang('!ShowMeter', p .. 'DetailTotalTax') else SKIN:Bang('!HideMeter', p .. 'DetailTotalTax') end",
        "SKIN:Bang('!HideMeter', p .. 'DetailEachLabel')","SKIN:Bang('!HideMeter', p .. 'DetailEachNet')","SKIN:Bang('!HideMeter', p .. 'DetailEachTax')",
        "SKIN:Bang('!HideMeter', p .. 'DetailTotalLabel')","SKIN:Bang('!HideMeter', p .. 'DetailTotal')","SKIN:Bang('!HideMeter', p .. 'DetailTotalNet')","SKIN:Bang('!HideMeter', p .. 'DetailTotalTax')",
        "SKIN:Bang('!HideMeter', p .. 'Name')",
        "SKIN:Bang('!HideMeter', p .. 'Window')",
        "SKIN:Bang('!HideMeter', p .. 'Chance')",
        'local function flagMaskImagePath(detailExpanded, graphExpanded)',
        "flagMaskDir .. 'flag-mask-both.png'","flagMaskDir .. 'flag-mask-top.png'","flagMaskDir .. 'flag-mask-bottom.png'",
        'local function applyItemImageForRow(data, index, key)','local function requestItemImages(itemIds)',
        "setVariable('VisibleItemImageIds', signature)","'MeasureItemImages'"
    )){
        if(-not$reader.Contains($token)){Fail "StateReader.lua missing detail/graph geometry contract '$token'."}
    }

    foreach($token in @(
        "local face='Nirmala UI Semilight'",
        "setOption(prefix..'Name','Text',itemName)",
        "setOption(prefix..'Name','FontColor','0,0,0,0')",
        "unitCostText=unitCost>0 and formatMoney(unitCost) or '?'",
        "totalCost=number(state[projectedPrefix..'TotalCostValue'])",
        "totalCost=(fallbackPrice>0 and quantity>0) and (fallbackPrice*quantity) or 0",
        "setOption(prefix..'Price','X',123)","setOption(prefix..'Price','W',265)",
        "setOption(prefix..'Leave','X',123)","setOption(prefix..'Leave','W',263)",
        "setOption(prefix..'Price','Text',itemName..' | '..unitCostText..' | '..totalCostText)",
        "setOption(prefix..'Price','InlinePattern','\\|')",
        "setOption(prefix..'Price','InlineSetting','Color | #Muted#')",
        "setOption(prefix..'Price','InlinePattern2','(?<=\\| )-?\\$[0-9,]+')",
        "setOption(prefix..'Price','InlineSetting2','Color | '..priceColor)",
        "setOption(prefix..'Price','InlinePattern3','-?\\$[0-9,]+$')",
        "setOption(prefix..'Price','InlineSetting3','Color | #ToggleIdle#')",
        "setOption(prefix..'Take','Text','')",
        "setOption(prefix..'Take','FontColor','0,0,0,0')",
        "setOption(prefix..'Make','Text',formatSignedMoney(make))",
        "setOption(prefix..'Make','FontColor',profitColor(make))",
        "setOption(prefix..'DetailEachLabel','Text','Each')","setOption(prefix..'DetailEachLabel','SolidColor','#Border#')",
        "setOption(prefix..'Gross','Text','MV:'..formatMoney(mv))",
        "setOption(prefix..'DetailEachNet','Text','Net:'..formatSignedMoney(each))",
        "setOption(prefix..'DetailEachTax','Text',marketTaxRate>0 and (tostring(marketTaxRate)..'% Tax:'..formatMoney(taxEach)) or '')",
        "setOption(prefix..'DetailTotalLabel','Text','Total')","setOption(prefix..'DetailTotalLabel','SolidColor','#Border#')",
        "setOption(prefix..'DetailTotal','Text','MV:'..formatMoney(grossSale))",
        "setOption(prefix..'DetailTotalNet','Text','Net:'..formatSignedMoney(make))",
        "setOption(prefix..'DetailTotalTax','Text',marketTaxRate>0 and (tostring(marketTaxRate)..'% Tax:'..formatMoney(marketTax)) or '')",
        "setOption(prefix..'DetailEachNet','StringAlign','RightCenter')","setOption(prefix..'DetailTotalNet','StringAlign','RightCenter')",
        "setOption(prefix..'DetailEachTax','StringAlign','LeftCenter')","setOption(prefix..'DetailTotalTax','StringAlign','LeftCenter')",
        "local detailLabelHeight=(marketTaxRate>0) and 32 or 16",
        "setOption(prefix..'Window','Text','')",
        "setOption(prefix..'Chance','Text','')",
        "if certainty~='' then actionText=actionText..' '..certainty end",
        "setOption(prefix..'Leave','Text',actionText)"
    )){
        if(-not$presenter.Contains($token)){Fail "CardPresenter.lua missing compact-card presentation contract '$token'."}
    }

    if(-not$header.Contains("'Card','Flag','FlagMask','CardBorder','ItemImage','Name','DetailEachLabel','Gross','DetailEachNet','DetailEachTax','DetailTotalLabel','DetailTotal','DetailTotalNet','DetailTotalTax','Window','Leave','Chance','Price','Take','Make','DetailToggle','Graph','InlineGraph'")){
        Fail 'HeaderLayout.lua must shift DetailToggle with every compact card row.'
    }
    if(-not$header.Contains('math.max(160,math.floor(panel-compactOffset))')){
        Fail 'HeaderLayout.lua must preserve the footer-aware 160px minimum panel height.'
    }

    $updated=[regex]::Match($ini,'(?ms)^\[MeterUpdated\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    foreach($token in @('X=12','Y=(#PanelHeight#-20)','W=528','FontFace=Nirmala UI Semilight')){
        if(-not$updated.Contains($token)){Fail "MeterUpdated footer missing '$token'."}
    }
    if($ini -notmatch '(?m)^PanelHeight=160\s*$'){Fail 'Initial PanelHeight must reserve the footer.'}

    $title=[regex]::Match($ini,'(?ms)^\[MeterTitle\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    foreach($token in @('Y=25','StringAlign=LeftCenter','FontSize=16','FontFace=Nirmala UI Semilight')){
        if(-not$title.Contains($token)){Fail "MeterTitle centered typography missing '$token'."}
    }

    foreach($section in @('MeterSortUpcomingButton','MeterSortGrossButton','MeterSortProfitHourButton')){
        $body=[regex]::Match($ini,'(?ms)^\['+[regex]::Escape($section)+'\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        foreach($token in @('W=92','H=23','Shape=Rectangle 0,0,92,23,4 | Fill Color #Control# | StrokeWidth 1 | Stroke Color #Border#')){
            if(-not$body.Contains($token)){Fail "$section must use the standard 92x23 sort-button surface."}
        }
    }
    $sortCenters=@{MeterSortUpcoming='X=56';MeterSortGross='X=154';MeterSortProfitHour='X=252'}
    foreach($section in @($sortCenters.Keys)){
        $body=[regex]::Match($ini,'(?ms)^\['+[regex]::Escape($section)+'\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        foreach($token in @($sortCenters[$section],'Y=67','W=92','H=23','StringAlign=CenterCenter')){
            if(-not$body.Contains($token)){Fail "$section must center its text inside the standard sort button."}
        }
    }
    foreach($retiredSeparator in @('MeterHeaderBottomLine','MeterSortBottomLine')){
        if($ini -match ('(?m)^\['+[regex]::Escape($retiredSeparator)+'\]\s*$')){Fail "Separator [$retiredSeparator] must remain removed."}
    }
    foreach($retiredSection in @('MeterSortNameButton','MeterSortName','MeterViewer','MeasureItemViewer')){
        if($ini -match ('(?m)^\['+[regex]::Escape($retiredSection)+'\]\s*$')){Fail "Retired UI section [$retiredSection] returned."}
    }
    foreach($retiredToken in @('ViewerMarketKey=','OpenViewer(','LaunchItemViewer.ps1','OpenItemViewer.ps1')){
        if($ini.Contains($retiredToken) -or $reader.Contains($retiredToken)){Fail "Retired Viewer token '$retiredToken' returned."}
    }
    foreach($token in @('local function effectiveSortMode(rows, requestedMode)','if row.timeKnown or row.profitKnown then return requestedMode end',"return 'name'","out.OpportunitySortEffectiveMode = effectiveMode")){
        if(-not$reader.Contains($token)){Fail "StateReader missing Name-only fallback sort contract '$token'."}
    }
    if($rows -match '(?im)^FontFace=Segoe UI' -or $ini -match '(?im)^FontFace=Segoe UI'){
        Fail 'Main Rainmeter typography must not fall back to Segoe UI.'
    }
    $fontLines=@([regex]::Matches($rows,'(?im)^FontFace=(.+)$')) + @([regex]::Matches($ini,'(?im)^FontFace=(.+)$'))
    foreach($fontLine in $fontLines){
        if($fontLine.Groups[1].Value.Trim() -ne 'Nirmala UI Semilight'){Fail "Unexpected main-skin font face '$($fontLine.Groups[1].Value.Trim())'."}
    }

    foreach($forbiddenExpanded in @("Each | MV:","Total | MV:")){
        if($presenter.Contains($forbiddenExpanded)){Fail "Expanded economics must not contain pipe label '$forbiddenExpanded'."}
    }

    foreach($retired in @('applyExpandedGraphGeometry','applyHeader','applySecondLine','polishHeader','polishWindowStatus')){
        if($tweaks.Contains($retired) -or $polish.Contains($retired)){
            Fail "Legacy presentation pass retains retired card owner '$retired'."
        }
    }
    if($tweaks -match "!SetOption.*(?:Card|Flag|Name|Gross|Price|Leave|Graph|InlineGraph)"){
        Fail 'CardTweaks.lua must not mutate active compact-card geometry or content.'
    }
    if($polish.Contains('!SetOption') -or $polish.Contains('!ShowMeter') -or $polish.Contains('!HideMeter')){
        Fail 'FinalCardPolish.lua must remain non-destructive.'
    }

    $sortGross=[regex]::Match($ini,'(?ms)^\[MeterSortGross\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if($sortGross -notmatch '(?im)^Text=PROFIT\s*$'){Fail 'Profit sort surface must read PROFIT.'}
    if($sortGross -notmatch '(?im)^ToolTipText=\s*$'){Fail 'Gross sort button tooltip must remain disabled.'}

    $sortHour=[regex]::Match($ini,'(?ms)^\[MeterSortProfitHour\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if($sortHour -notmatch '(?im)^ToolTipText=\s*$'){
        Fail 'PROFIT/HR sort button tooltip must remain disabled.'
    }

    foreach($staticSurface in @($ini,$rows)){
        foreach($match in [regex]::Matches($staticSurface,'(?im)^ToolTipText=(.+)$')){
            if(-not[string]::IsNullOrWhiteSpace($match.Groups[1].Value)){Fail "Static non-window tooltip must remain disabled: $($match.Groups[1].Value)"}
        }
    }

    foreach($paletteToken in @('Panel=17,17,17,248','Card=0,0,0,255','Control=32,32,32,248','Border=64,64,64,255','Muted=150,150,150,255','TornLime=126,190,73,255','Accent=126,190,73,255','SortUpcomingColor=126,190,73,255','Greyscale=1','ImageTint=#TornLime#','ToggleDark=38,38,38,255','ToggleIdle=190,190,190,255')){
        if(-not$ini.Contains($paletteToken)){Fail "Neutral main-skin palette missing '$paletteToken'."}
    }
}

if($errors.Count -gt 0){
    foreach($error in $errors){Write-Host "FAIL: $error" -ForegroundColor Red}
    Write-Host "Compact card detail-layout validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Compact card detail-layout validation passed.' -ForegroundColor Green
Write-Host 'Base card, split per-item/total economics strip, exact full-load cost, large signed net, centered lime toggles, inline graph expansion, compact footer, and single-owner geometry are enforced.'
exit 0
