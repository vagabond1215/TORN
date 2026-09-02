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
        foreach($suffix in @('Card','Flag','Name','Gross','DetailTotal','Price','Take','Make','Leave','DetailToggle','Graph','InlineGraph')){
            $section='MeterOpportunity'+$i+$suffix
            if($rows -notmatch ('(?m)^\['+[regex]::Escape($section)+'\]\s*$')){
                Fail "OpportunityRows.inc missing [$section]."
            }
        }

        $card=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Card\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        foreach($token in @('Shape2=Line 510,0,510,50 | StrokeWidth 1 | Stroke Color #Border#','Shape3=Line 510,25,536,25 | StrokeWidth 1 | Stroke Color #Border#')){
            if(-not$card.Contains($token)){Fail "Row $i card end-cap separator missing '$token'."}
        }

        $detail=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailToggle\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if($detail -notmatch '(?im)^Text=\$\s*$'){Fail "Row $i detail toggle must default to the money button."}
        foreach($token in @('X=531','W=26','H=25','StringAlign=CenterCenter','FontColor=#ToggleIdle#','SolidColor=0,0,0,1')){
            if(-not$detail.Contains($token)){Fail "Row $i money end-cap button missing '$token'."}
        }
        if($detail -notmatch ('ToggleCardDetails\('+[string]$i+'\)')){Fail "Row $i detail toggle must call ToggleCardDetails($i)."}

        $graph=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Graph\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if($graph -notmatch '(?im)^Meter=Shape\s*$' -or $graph -notmatch '(?im)^GraphExpanded=0\s*$'){Fail "Row $i graph button must be a collapsed Shape icon by default."}
        foreach($token in @('X=518','W=26','H=25','Shape=Rectangle 0,0,26,25 | Fill Color 0,0,0,1 | StrokeWidth 0','Stroke Color #ToggleIdle#','Shape2=Line 8,17,8,8','Shape3=Line 8,17,18,17','Shape4=Line 9,15,12,12','Shape5=Line 12,12,14,14','Shape6=Line 14,14,18,9')){
            if(-not$graph.Contains($token)){Fail "Row $i chart end-cap button missing '$token'."}
        }
        if($graph -notmatch ('ToggleInlineGraph\('+[string]$i+'\)')){Fail "Row $i graph toggle must call ToggleInlineGraph($i)."}

        $nameBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Name\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if($nameBody -notmatch '(?im)^W=1\s*$' -or $nameBody -notmatch '(?im)^FontSize=11\s*$' -or $nameBody -notmatch '(?im)^FontColor=0,0,0,0\s*$'){
            Fail "Row $i Name meter must remain a hidden canonical lookup surface at the new 11pt typography."
        }

        $priceBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Price\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if($priceBody -notmatch '(?im)^X=78\s*$' -or $priceBody -notmatch '(?im)^W=198\s*$' -or $priceBody -notmatch '(?im)^FontSize=11\s*$'){
            Fail "Row $i item/unit-cost column must start at x=78 with a fixed 198px width."
        }
        $takeBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Take\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if($takeBody -notmatch '(?im)^X=280\s*$' -or $takeBody -notmatch '(?im)^W=108\s*$' -or $takeBody -notmatch '(?im)^FontSize=11\s*$' -or $takeBody -notmatch '(?im)^FontColor=#Muted#\s*$'){
            Fail "Row $i full-load cost column must be independently anchored at x=280 and remain muted."
        }
        $makeBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Make\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if($makeBody -notmatch '(?im)^X=504\s*$' -or $makeBody -notmatch '(?im)^W=108\s*$' -or $makeBody -notmatch '(?im)^H=50\s*$' -or $makeBody -notmatch '(?im)^FontSize=15\s*$' -or $makeBody -notmatch '(?im)^StringAlign=RightCenter\s*$'){
            Fail "Row $i total net must be 15pt, vertically centered, and right-aligned at x=504."
        }
        foreach($fontBody in @($nameBody,$priceBody,$takeBody,$makeBody)){
            if($fontBody -notmatch '(?im)^FontFace=Nirmala UI Semilight\s*$'){Fail "Row $i first-line typography must use Nirmala UI Semilight."}
        }

        $strip=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Gross\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        $stripTotal=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailTotal\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        foreach($token in @('X=14','W=256','H=18','FontSize=10','StringAlign=LeftCenter','Hidden=1')){
            if(-not$strip.Contains($token)){Fail "Row $i per-item detail half missing '$token'."}
        }
        foreach($token in @('X=282','W=256','H=18','FontSize=10','StringAlign=LeftCenter','Hidden=1')){
            if(-not$stripTotal.Contains($token)){Fail "Row $i total detail half missing '$token'."}
        }

        $inline=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'InlineGraph\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        foreach($token in @('W=528','H=125',('Group=OpportunityInlineGraph'+$i))){
            if(-not$inline.Contains($token)){Fail "Row $i inline graph missing '$token'."}
        }
    }

    foreach($token in @(
        'local detailExtra = 18',
        'local graphExtra = 133',
        'local footerExtra = 16',
        "local expandedDetailKey = ''",
        'local expandedDetailRow = 0',
        'local function setGraphButtonState(name, expanded)',
        'local function setDetailButtonState(name, expanded)',
        "'GraphExpanded', expanded and '1' or '0'",
        "'Rectangle 0,0,26,25 | Fill Color '..fill..' | StrokeWidth 0'",
        "SKIN:Bang('!SetOption', name, 'Text', '$')",
        "'126,190,73,255'","'38,38,38,255'","'190,190,190,255'",
        'local function collapseCardDetails()',
        'local function syncExpandedRows(data, count)',
        'function ToggleCardDetails(index)',
        "if expandedDetailRow > 0 and i > expandedDetailRow then extraBefore = extraBefore + detailExtra end",
        "if expandedRow > 0 and i > expandedRow then extraBefore = extraBefore + graphExtra end",
        'local bodyOffset = detailExpanded and detailExtra or 0',
        'local cardHeight = collapsedCardHeight + bodyOffset + (graphExpanded and graphExtra or 0)',
        "'Shape2', 'Line 510,' .. bodyOffset .. ',510,' .. (bodyOffset+50)","'Shape4', 'Line 268,0,268,' .. detailExtra","'Shape5', 'Line 0,' .. detailExtra .. ',536,' .. detailExtra",
        "'Shape3', 'Line 510,' .. (bodyOffset+25) .. ',536,' .. (bodyOffset+25)",
        "'Gross', 'Y', tostring(y+9)","'DetailTotal', 'Y', tostring(y+9)",
        "'DetailToggle', 'Y', tostring(y+13+bodyOffset)",
        "'Make', 'Y', tostring(y+25+bodyOffset)","'Graph', 'Y', tostring(y+25+bodyOffset)",
        "panelHeight = 120 + (count * rowStride) + ((expandedDetailRow > 0) and detailExtra or 0) + ((expandedRow > 0) and graphExtra or 0) + 8 + footerExtra",
        "SKIN:Bang('!ShowMeter', p .. 'DetailTotal')",
        "SKIN:Bang('!HideMeter', p .. 'DetailTotal')",
        "SKIN:Bang('!HideMeter', p .. 'Name')",
        "SKIN:Bang('!HideMeter', p .. 'Window')",
        "SKIN:Bang('!HideMeter', p .. 'Chance')"
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
        "setOption(prefix..'Price','Text',itemName..' | '..unitCostText)",
        "setOption(prefix..'Price','InlinePattern','\\|')",
        "setOption(prefix..'Price','InlineSetting','Color | #Muted#')",
        "setOption(prefix..'Price','InlinePattern2','(?<=\\| )-?\\$[0-9,]+')",
        "setOption(prefix..'Price','InlineSetting2','Color | '..priceColor)",
        "setOption(prefix..'Take','Text','| '..totalCostText)",
        "setOption(prefix..'Take','FontColor','#Muted#')",
        "setOption(prefix..'Make','Text',formatSignedMoney(make))",
        "setOption(prefix..'Make','FontColor',profitColor(make))",
        "local eachDetail='Each | Gross:'..formatMoney(grossEach)",
        "local totalDetail='Total | Gross:'..formatMoney(grossSale)",
        "'% Tax:'..formatMoney(taxEach)",
        "'% Tax:'..formatMoney(marketTax)",
        "' Net:'..formatSignedMoney(each)",
        "' Net:'..formatSignedMoney(make)",
        "setOption(prefix..'Gross','InlinePattern3','(?<=Net:)[+-]?\\$[0-9,]+')",
        "setOption(prefix..'DetailTotal','InlinePattern3','(?<=Net:)[+-]?\\$[0-9,]+')",
        "setOption(prefix..'Window','Text','')",
        "setOption(prefix..'Chance','Text','')",
        "if certainty~='' then actionText=actionText..' '..certainty end",
        "setOption(prefix..'Leave','Text',actionText)"
    )){
        if(-not$presenter.Contains($token)){Fail "CardPresenter.lua missing compact-card presentation contract '$token'."}
    }

    if(-not$header.Contains("'Card','Flag','Name','Gross','DetailTotal','Window','Leave','Chance','Price','Take','Make','DetailToggle','Graph','InlineGraph'")){
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
        foreach($token in @('W=92','H=23','Shape=Rectangle 0,0,92,23,4 | Fill Color #Card# | StrokeWidth 1 | Stroke Color #Border#')){
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
    if($sortGross -notmatch '(?im)^Text=GROSS PROFIT\s*$'){Fail 'Gross sort surface must remain GROSS PROFIT.'}
    if($sortGross -notmatch '(?im)^ToolTipText=Highest total trip gross profit first\s*$'){Fail 'Gross sort tooltip must describe pre-tax gross profit.'}

    $sortHour=[regex]::Match($ini,'(?ms)^\[MeterSortProfitHour\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if($sortHour -notmatch '(?im)^ToolTipText=Net profit after tax divided by total elapsed hours; likelihood stays separate\s*$'){
        Fail 'PROFIT/HR sort tooltip must describe after-tax net profit per hour.'
    }

    foreach($paletteToken in @('Panel=17,17,17,248','Card=32,32,32,248','Border=64,64,64,255','Muted=150,150,150,255','TornLime=126,190,73,255','ToggleDark=38,38,38,255','ToggleIdle=190,190,190,255')){
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
