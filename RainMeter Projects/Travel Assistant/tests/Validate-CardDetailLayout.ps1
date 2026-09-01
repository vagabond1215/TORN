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
        foreach($suffix in @('Card','Flag','Name','Gross','Price','Leave','DetailToggle','Graph','InlineGraph')){
            $section='MeterOpportunity'+$i+$suffix
            if($rows -notmatch ('(?m)^\['+[regex]::Escape($section)+'\]\s*$')){
                Fail "OpportunityRows.inc missing [$section]."
            }
        }

        $detail=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailToggle\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if($detail -notmatch '(?im)^Text=\+\s*$'){Fail "Row $i detail toggle must default to +."}
        if($detail -notmatch ('ToggleCardDetails\('+[string]$i+'\)')){Fail "Row $i detail toggle must call ToggleCardDetails($i)."}

        $graph=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Graph\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if($graph -notmatch ('ToggleInlineGraph\('+[string]$i+'\)')){Fail "Row $i graph toggle must call ToggleInlineGraph($i)."}

        $nameBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Name\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if($nameBody -notmatch '(?im)^W=1\s*$' -or $nameBody -notmatch '(?im)^FontSize=11\s*$' -or $nameBody -notmatch '(?im)^FontColor=0,0,0,0\s*$'){
            Fail "Row $i Name meter must remain a hidden canonical lookup surface at the new 11pt typography."
        }

        $priceBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Price\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        if($priceBody -notmatch '(?im)^X=78\s*$' -or $priceBody -notmatch '(?im)^W=440\s*$' -or $priceBody -notmatch '(?im)^FontSize=11\s*$'){
            Fail "Row $i visible first-line meter must span Name | Cost | Take | Make at 11pt."
        }
        if($nameBody -notmatch '(?im)^FontFace=Nirmala UI Semilight\s*$' -or $priceBody -notmatch '(?im)^FontFace=Nirmala UI Semilight\s*$'){
            Fail "Row $i first-line typography must use Nirmala UI Semilight."
        }

        $strip=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Gross\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        foreach($token in @('W=500','H=14','FontSize=7','Hidden=1')){
            if(-not$strip.Contains($token)){Fail "Row $i detail strip missing '$token'."}
        }

        $inline=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'InlineGraph\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
        foreach($token in @('W=528','H=125',('Group=OpportunityInlineGraph'+$i))){
            if(-not$inline.Contains($token)){Fail "Row $i inline graph missing '$token'."}
        }
    }

    foreach($token in @(
        'local detailExtra = 18',
        'local graphExtra = 133',
        'local footerExtra = 28',
        "local expandedDetailKey = ''",
        'local expandedDetailRow = 0',
        'local function collapseCardDetails()',
        'local function syncExpandedRows(data, count)',
        'function ToggleCardDetails(index)',
        "if expandedDetailRow > 0 and i > expandedDetailRow then extraBefore = extraBefore + detailExtra end",
        "if expandedRow > 0 and i > expandedRow then extraBefore = extraBefore + graphExtra end",
        'local bodyOffset = detailExpanded and detailExtra or 0',
        'local cardHeight = collapsedCardHeight + bodyOffset + (graphExpanded and graphExtra or 0)',
        "panelHeight = 120 + (count * rowStride) + ((expandedDetailRow > 0) and detailExtra or 0) + ((expandedRow > 0) and graphExtra or 0) + 8 + footerExtra",
        "if i == expandedDetailRow then SKIN:Bang('!ShowMeter', p .. 'Gross') else SKIN:Bang('!HideMeter', p .. 'Gross') end",
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
        "setOption(prefix..'Price','Text',itemName..' | '..unitCostText..'  Take: '..takeText..'  Make: '..formatMoney(make))",
        "setOption(prefix..'Price','InlinePattern','\\|')",
        "setOption(prefix..'Price','InlineSetting','Color | #Muted#')",
        "'MV:'..formatMoney(mv)",
        "'  Each:'..formatMoney(each)",
        "'  Gross:'..formatMoney(grossSale)",
        "'  Per Hour:'..formatMoney(grossProfitHour)",
        "'  Tax:'..formatMoney(marketTax)",
        "setOption(prefix..'Gross','InlinePattern','MV:')",
        "setOption(prefix..'Gross','InlineSetting','Color | 218,178,69,255')",
        "setOption(prefix..'Gross','InlinePattern2','Each:')",
        "setOption(prefix..'Gross','InlineSetting2','Color | 255,255,255,255')",
        "setOption(prefix..'Gross','InlinePattern3','Gross:')",
        "setOption(prefix..'Gross','InlineSetting3','Color | 255,255,255,255')",
        "setOption(prefix..'Gross','InlinePattern4','Per Hour:')",
        "setOption(prefix..'Gross','InlineSetting4','Color | 255,255,255,255')",
        "setOption(prefix..'Gross','InlinePattern5','Tax:')",
        "setOption(prefix..'Gross','InlineSetting5','Color | 232,104,70,255')",
        "setOption(prefix..'Window','Text','')",
        "setOption(prefix..'Chance','Text','')",
        "if certainty~='' then actionText=actionText..' '..certainty end",
        "setOption(prefix..'Leave','Text',actionText)"
    )){
        if(-not$presenter.Contains($token)){Fail "CardPresenter.lua missing compact-card presentation contract '$token'."}
    }

    if(-not$header.Contains("'Card','Flag','Name','Gross','Window','Leave','Chance','Price','DetailToggle','Graph','InlineGraph'")){
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
    if($rows -match '(?im)^FontFace=Segoe UI' -or $ini -match '(?im)^FontFace=Segoe UI'){
        Fail 'Main Rainmeter typography must not fall back to Segoe UI.'
    }
    foreach($fontLine in @([regex]::Matches($rows,'(?im)^FontFace=(.+)$') + [regex]::Matches($ini,'(?im)^FontFace=(.+)$'))){
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
    if($sortHour -notmatch '(?im)^ToolTipText=Gross profit divided by total elapsed hours; likelihood stays separate\s*$'){
        Fail 'PROFIT/HR sort tooltip must describe gross profit per hour.'
    }
}

if($errors.Count -gt 0){
    foreach($error in $errors){Write-Host "FAIL: $error" -ForegroundColor Red}
    Write-Host "Compact card detail-layout validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}

Write-Host 'Compact card detail-layout validation passed.' -ForegroundColor Green
Write-Host 'Base card, slide-up economics strip, independent graph expansion, Take/Make line, unified window line, gross-profit sorts, and single-owner geometry are enforced.'
exit 0
