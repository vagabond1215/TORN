$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$rowIncludePath = Join-Path $ProjectRoot '@Resources\Includes\OpportunityRows.inc'
$stateReaderPath = Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
$rendererPath = Join-Path $ProjectRoot '@Resources\Scripts\RenderInlineGraph.ps1'
$itemImageScriptPath = Join-Path $ProjectRoot '@Resources\Scripts\EnsureItemImages.ps1'
$flagDir = Join-Path $ProjectRoot '@Resources\Images\Flags'
$uiImageDir = Join-Path $ProjectRoot '@Resources\Images\UI'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($iniPath,$rowIncludePath,$stateReaderPath,$rendererPath,$itemImageScriptPath)) {
    if (-not (Test-Path -LiteralPath $path)) { Fail "Missing required UI file: $path" }
}
if ($errors.Count -gt 0) { foreach($e in $errors){Write-Host "FAIL: $e" -ForegroundColor Red}; exit 1 }

$ini = Get-Content -LiteralPath $iniPath -Raw
$rows = Get-Content -LiteralPath $rowIncludePath -Raw
$reader = Get-Content -LiteralPath $stateReaderPath -Raw
$renderer = Get-Content -LiteralPath $rendererPath -Raw

if ($ini -notmatch '(?m)^Version=0\.6\.0\s*$') { Fail 'Skin must report version 0.6.0.' }
$includeToken='@IncludeRows=#@#Includes\OpportunityRows.inc'
$includeAt=$ini.IndexOf($includeToken,[System.StringComparison]::Ordinal)
$backgroundAt=$ini.IndexOf('[MeterBackground]',[System.StringComparison]::Ordinal)
$messageAt=$ini.IndexOf('[MeterOpportunityMessage]',[System.StringComparison]::Ordinal)
if ($includeAt -lt 0) { Fail 'TravelAssistant.ini must include OpportunityRows.inc as the final row layer.' }
elseif ($includeAt -lt $backgroundAt -or $includeAt -lt $messageAt) { Fail 'OpportunityRows.inc must be included after the panel/background meters so cards render above the background.' }
if ($ini.Contains('@Include=#@#Includes\OpportunityRows.inc')) { Fail 'Retired early OpportunityRows include would darken the cards beneath MeterBackground.' }

foreach ($section in @('MeasureUpdate','MeasureSettings','MeasureFilterPopup','MeasureInlineGraph','MeasureItemImages','MeasurePreferenceAction','MeasureState','MeterSortUpcoming','MeterSortGross','MeterSortProfitHour')) {
    if ($ini -notmatch ('(?m)^\['+[regex]::Escape($section)+'\]\s*$')) { Fail "Missing [$section]." }
}

$updateBody=[regex]::Match($ini,'(?ms)^\[MeasureUpdate\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
$updateTimeoutMatch=[regex]::Match($updateBody,'(?im)^Timeout=(\d+)\s*$')
if (-not $updateTimeoutMatch.Success) { Fail 'MeasureUpdate must declare a bounded timeout.' }
else {
    $updateTimeout=[int]$updateTimeoutMatch.Groups[1].Value
    if ($updateTimeout -lt 60000) { Fail "MeasureUpdate timeout $updateTimeout ms is too short for provider fallback + travel context + evidence projection." }
    if ($updateTimeout -gt 120000) { Fail "MeasureUpdate timeout $updateTimeout ms exceeds the bounded 120s runtime ceiling." }
}

$inlineBody=[regex]::Match($ini,'(?ms)^\[MeasureInlineGraph\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if ($inlineBody -notmatch 'RenderInlineGraph\.ps1' -or $inlineBody -notmatch '#InlineGraphMarketKey#') { Fail 'Inline chart button must use its dedicated local RenderInlineGraph.ps1 measure.' }
foreach($retired in @('MeasureItemViewer','MeterViewer','ViewerMarketKey','LaunchItemViewer','OpenItemViewer')){
    if($ini.Contains($retired) -or $reader.Contains($retired)){Fail "Standalone Viewer token '$retired' must remain removed."}
}

foreach ($i in 1..8) {
    foreach ($suffix in @('Card','Flag','FlagMask','CardBorder','ItemImage','Name','DetailEachLabel','Gross','DetailEachNet','DetailEachTax','DetailTotalLabel','DetailTotal','DetailTotalNet','DetailTotalTax','Window','Leave','Chance','Price','Take','Make','DetailToggle','Graph','InlineGraph')) {
        $section='MeterOpportunity'+$i+$suffix
        if ($rows -notmatch ('(?m)^\['+[regex]::Escape($section)+'\]\s*$')) { Fail "OpportunityRows.inc missing [$section]." }
    }
    $flagBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Flag\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $flagMaskBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'FlagMask\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $cardBorderBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'CardBorder\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $itemImageBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'ItemImage\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $detailBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailToggle\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $nameBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Name\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $priceBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Price\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $takeBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Take\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $leaveBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Leave\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $makeBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Make\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $detailEachLabelBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailEachLabel\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $grossBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Gross\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $detailEachNetBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailEachNet\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $detailEachTaxBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailEachTax\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $detailTotalLabelBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailTotalLabel\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $detailTotalBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailTotal\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $detailTotalNetBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailTotalNet\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $detailTotalTaxBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailTotalTax\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $graphButtonBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Graph\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $graphBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'InlineGraph\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if ($flagBody -notmatch '(?im)^Meter=Image\s*$' -or $flagBody -notmatch '(?im)^X=8\s*$' -or $flagBody -notmatch '(?im)^W=67\s*$' -or $flagBody -notmatch '(?im)^H=50\s*$' -or $flagBody -notmatch '(?im)^PreserveAspectRatio=1\s*$') { Fail "Opportunity $i flag must extend under the rounded border with no top/bottom gap." }
    if ($flagMaskBody -notmatch '(?im)^X=8\s*$' -or $flagMaskBody -notmatch '(?im)^W=67\s*$' -or $flagMaskBody -notmatch '(?im)^H=50\s*$' -or $flagMaskBody -notmatch '(?im)^ImageTint=#Panel#\s*$') { Fail "Opportunity $i flag mask must match the full-height flag and tint to the panel." }
    if ($cardBorderBody -notmatch '(?im)^Shape=Rectangle 0,0,536,50,5 \| Fill Color 0,0,0,0 \| StrokeWidth 1 \| Stroke Color #Border#\s*$') { Fail "Opportunity $i must redraw the rounded card border over the flag edge." }
    if ($itemImageBody -notmatch '(?im)^X=77\s*$' -or $itemImageBody -notmatch '(?im)^W=44\s*$' -or $itemImageBody -notmatch '(?im)^H=44\s*$' -or $itemImageBody -notmatch '(?im)^PreserveAspectRatio=1\s*$') { Fail "Opportunity $i item art must fill the 48px square cell immediately right of the flag with a 2px inset." }
    if ($detailBody -notmatch '(?im)^Text=\$\s*$' -or $detailBody -notmatch ('ToggleCardDetails\('+[string]$i+'\)')) { Fail "Opportunity $i money button must control the top economics strip." }
    if ($graphButtonBody -notmatch '(?im)^Meter=Shape\s*$' -or $graphButtonBody -notmatch '(?im)^GraphExpanded=0\s*$') { Fail "Opportunity $i graph control must be a chart Shape button." }
    foreach($token in @('X=519','W=24','H=23','Shape=Rectangle 0,0,24,23 | Fill Color 0,0,0,1 | StrokeWidth 0','Stroke Color #ToggleIdle#','Shape2=Line 7,16,7,7','Shape3=Line 7,16,17,16','Shape4=Line 8,14,11,11','Shape5=Line 11,11,13,13','Shape6=Line 13,13,17,8')){if(-not$graphButtonBody.Contains($token)){Fail "Opportunity $i chart end-cap control missing '$token'."}}
    if ($nameBody -notmatch '(?im)^W=1\s*$' -or $nameBody -notmatch '(?im)^FontSize=12\s*$' -or $nameBody -notmatch '(?im)^FontColor=0,0,0,0\s*$') { Fail "Opportunity $i canonical Name meter must stay hidden behind the combined first line." }
    if ($priceBody -notmatch '(?im)^X=123\s*$' -or $priceBody -notmatch '(?im)^W=265\s*$' -or $priceBody -notmatch '(?im)^FontSize=12\s*$') { Fail "Opportunity $i combined item/unit/full-load-cost line must start after the 48px item-art cell at x=123, width 265." }
    if ($takeBody -notmatch '(?im)^X=123\s*$' -or $takeBody -notmatch '(?im)^W=1\s*$' -or $takeBody -notmatch '(?im)^FontColor=0,0,0,0\s*$') { Fail "Opportunity $i retired Take surface must remain inert." }
    if ($makeBody -notmatch '(?im)^X=504\s*$' -or $makeBody -notmatch '(?im)^W=108\s*$' -or $makeBody -notmatch '(?im)^H=50\s*$' -or $makeBody -notmatch '(?im)^FontSize=16\s*$' -or $makeBody -notmatch '(?im)^StringAlign=RightCenter\s*$') { Fail "Opportunity $i signed total net must span both text lines and align right-center at x=504." }
    if ($leaveBody -notmatch '(?im)^FontSize=9\s*$') { Fail "Opportunity $i visible window/guidance line must use 9pt typography." }
    if ($detailEachLabelBody -notmatch '(?im)^X=29\s*$' -or $detailEachLabelBody -notmatch '(?im)^W=40\s*$' -or $detailEachLabelBody -notmatch '(?im)^H=32\s*$' -or $detailEachLabelBody -notmatch '(?im)^StringAlign=CenterCenter\s*$' -or $detailEachLabelBody -notmatch '(?im)^SolidColor=#Border#\s*$' -or $detailEachLabelBody -notmatch '(?im)^Text=Each\s*$') { Fail "Opportunity $i Each label must be a vertically centered border-colored block." }
    if ($grossBody -notmatch '(?im)^X=54\s*$' -or $grossBody -notmatch '(?im)^W=112\s*$' -or $grossBody -notmatch '(?im)^H=16\s*$' -or $grossBody -notmatch '(?im)^StringAlign=LeftCenter\s*$') { Fail "Opportunity $i Each MV must be left-aligned on the top row." }
    if ($detailEachNetBody -notmatch '(?im)^X=270\s*$' -or $detailEachNetBody -notmatch '(?im)^W=98\s*$' -or $detailEachNetBody -notmatch '(?im)^H=16\s*$' -or $detailEachNetBody -notmatch '(?im)^StringAlign=RightCenter\s*$') { Fail "Opportunity $i Each Net must be right-aligned on the top row." }
    if ($detailEachTaxBody -notmatch '(?im)^X=54\s*$' -or $detailEachTaxBody -notmatch '(?im)^W=210\s*$' -or $detailEachTaxBody -notmatch '(?im)^H=16\s*$' -or $detailEachTaxBody -notmatch '(?im)^StringAlign=LeftCenter\s*$') { Fail "Opportunity $i Each Tax must be left-aligned on the second row." }
    if ($detailTotalLabelBody -notmatch '(?im)^X=297\s*$' -or $detailTotalLabelBody -notmatch '(?im)^W=40\s*$' -or $detailTotalLabelBody -notmatch '(?im)^H=32\s*$' -or $detailTotalLabelBody -notmatch '(?im)^StringAlign=CenterCenter\s*$' -or $detailTotalLabelBody -notmatch '(?im)^SolidColor=#Border#\s*$' -or $detailTotalLabelBody -notmatch '(?im)^Text=Total\s*$') { Fail "Opportunity $i Total label must be a vertically centered border-colored block." }
    if ($detailTotalBody -notmatch '(?im)^X=322\s*$' -or $detailTotalBody -notmatch '(?im)^W=112\s*$' -or $detailTotalBody -notmatch '(?im)^H=16\s*$' -or $detailTotalBody -notmatch '(?im)^StringAlign=LeftCenter\s*$') { Fail "Opportunity $i Total MV must be left-aligned on the top row." }
    if ($detailTotalNetBody -notmatch '(?im)^X=538\s*$' -or $detailTotalNetBody -notmatch '(?im)^W=98\s*$' -or $detailTotalNetBody -notmatch '(?im)^H=16\s*$' -or $detailTotalNetBody -notmatch '(?im)^StringAlign=RightCenter\s*$') { Fail "Opportunity $i Total Net must be right-aligned on the top row." }
    if ($detailTotalTaxBody -notmatch '(?im)^X=322\s*$' -or $detailTotalTaxBody -notmatch '(?im)^W=210\s*$' -or $detailTotalTaxBody -notmatch '(?im)^H=16\s*$' -or $detailTotalTaxBody -notmatch '(?im)^StringAlign=LeftCenter\s*$') { Fail "Opportunity $i Total Tax must be left-aligned on the second row." }
    foreach($fontBody in @($nameBody,$priceBody,$takeBody,$makeBody,$detailEachLabelBody,$grossBody,$detailEachNetBody,$detailEachTaxBody,$detailTotalLabelBody,$detailTotalBody,$detailTotalNetBody,$detailTotalTaxBody,$detailBody)){if($fontBody -match '(?im)^FontFace=' -and $fontBody -notmatch '(?im)^FontFace=Nirmala UI Semilight\s*$'){Fail "Opportunity $i card string meters must use Nirmala UI Semilight."}}
    if ($graphBody -notmatch '(?im)^Meter=Image\s*$' -or $graphBody -notmatch '(?im)^W=528\s*$' -or $graphBody -notmatch '(?im)^H=125\s*$') { Fail "Opportunity $i inline graph must be the 528x125 native Image surface." }
    if ($graphBody -notmatch ('(?im)^Group=OpportunityInlineGraph'+$i+'\s*$')) { Fail "Opportunity $i inline graph must use its isolated visibility group." }
    if ($graphBody -match ('(?im)^Group=OpportunityRow'+$i+'\s*$')) { Fail "Opportunity $i inline graph must not be re-shown by the row visibility group." }
    if ($rows -match ('(?ms)^\[MeterOpportunity'+$i+'Rank\]')) { Fail "Opportunity $i must not restore visible place/rank meters." }
    if ($rows -match ('(?ms)^\[MeterOpportunity'+$i+'Country\]')) { Fail "Opportunity $i must not add a separate country meter; country belongs in the title." }
    if ($rows -match ('(?ms)^\[MeterOpportunity'+$i+'Time\]')) { Fail "Opportunity $i must not restore travel/elapsed text in the card body." }
}

foreach ($maskName in @('flag-mask-both.png','flag-mask-top.png','flag-mask-bottom.png')) {
    if (-not (Test-Path -LiteralPath (Join-Path $uiImageDir $maskName))) { Fail "Missing flag corner mask $maskName." }
}

foreach ($code in @('MX','KY','CA','US','GB','AR','CH','JP','CN','AE','ZA')) {
    if (-not (Test-Path -LiteralPath (Join-Path $flagDir ($code+'@3x.png')))) { Fail "Missing FlagKit asset ${code}@3x.png." }
}
if (-not (Test-Path -LiteralPath (Join-Path $flagDir 'LICENSE-FlagKit.txt'))) { Fail 'FlagKit MIT attribution file is missing.' }

$itemImageScript=Get-Content -LiteralPath $itemImageScriptPath -Raw
foreach($token in @('https://www.torn.com/images/items/{0}/large.png','@Resources\Generated','Items','System.Net.Http.HttpClient','$bytes[0] -ne 137')){
    if(-not$itemImageScript.Contains($token)){Fail "EnsureItemImages.ps1 missing '$token'."}
}

foreach ($token in @(
    "mexico='MX'","cayman_islands='KY'","hawaii='US'","united_kingdom='GB'","united_arab_emirates='AE'",
    "return flagDir .. code .. '@3x.png'",'ToolTipText',"' | travel '",
    'local function setGraphButtonState(name, expanded)','local function setDetailButtonState(name, expanded)',
    "'GraphExpanded', expanded and '1' or '0'","SKIN:Bang('!SetOption', name, 'Text', '$')","'126,190,73,255'","'38,38,38,255'","'190,190,190,255'",
    "'Rectangle 0,0,24,23 | Fill Color '..fill..' | StrokeWidth 0'",
    'local function collapseInlineGraph()','local function collapseCardDetails()','function ToggleCardDetails(index)',
    'local detailExtraWithTax = 34','local detailExtraNoTax = 18','local function detailTaxRate(data, index)','local function detailExtraForRow(data, index)','local graphExtra = 133','local footerExtra = 16','expandedDetailKey','expandedDetailRow',
    "local activeDetailExtra = detailExtraForRow(data, expandedDetailRow)","local activeDetailHasTax = expandedDetailRow > 0 and detailTaxRate(data, expandedDetailRow) > 0",
    "if expandedDetailRow > 0 and i > expandedDetailRow then extraBefore = extraBefore + activeDetailExtra end",
    "local cardHeight = collapsedCardHeight + bodyOffset + (graphExpanded and graphExtra or 0)",
    'local detailLabelCenterY = y + (detailExpanded and math.floor(bodyOffset/2) or 9)',
    "'DetailEachLabel', 'Y', tostring(detailLabelCenterY)","'DetailEachLabel', 'H', tostring(detailLabelHeight)",
    "'Gross', 'Y', tostring(y+9)","'DetailEachNet', 'Y', tostring(y+9)","'DetailEachTax', 'Y', tostring(y+26)",
    "'DetailTotalLabel', 'Y', tostring(detailLabelCenterY)","'DetailTotalLabel', 'H', tostring(detailLabelHeight)",
    "'DetailTotal', 'Y', tostring(y+9)","'DetailTotalNet', 'Y', tostring(y+9)","'DetailTotalTax', 'Y', tostring(y+26)",
    "'Flag', 'Y', tostring(y+bodyOffset)","'FlagMask', 'Y', tostring(y+bodyOffset)","'Flag', 'W', '67'","'Flag', 'H', '50'","'ItemImage', 'Y', tostring(y+3+bodyOffset)","'ItemImage', 'W', '44'","'ItemImage', 'H', '44'","'Window', 'Y', tostring(y+34+bodyOffset)","'Graph', 'Y', tostring(y+26+bodyOffset)",
    "SKIN:Bang('!ShowMeter', p .. 'DetailEachLabel')","SKIN:Bang('!ShowMeter', p .. 'Gross')","SKIN:Bang('!ShowMeter', p .. 'DetailEachNet')",
    "if activeDetailHasTax then SKIN:Bang('!ShowMeter', p .. 'DetailEachTax') else SKIN:Bang('!HideMeter', p .. 'DetailEachTax') end",
    "SKIN:Bang('!ShowMeter', p .. 'DetailTotalLabel')","SKIN:Bang('!ShowMeter', p .. 'DetailTotal')","SKIN:Bang('!ShowMeter', p .. 'DetailTotalNet')",
    "if activeDetailHasTax then SKIN:Bang('!ShowMeter', p .. 'DetailTotalTax') else SKIN:Bang('!HideMeter', p .. 'DetailTotalTax') end",
    "SKIN:Bang('!HideMeter', p .. 'DetailEachLabel')","SKIN:Bang('!HideMeter', p .. 'Gross')","SKIN:Bang('!HideMeter', p .. 'DetailEachNet')","SKIN:Bang('!HideMeter', p .. 'DetailEachTax')",
    "SKIN:Bang('!HideMeter', p .. 'DetailTotalLabel')","SKIN:Bang('!HideMeter', p .. 'DetailTotal')","SKIN:Bang('!HideMeter', p .. 'DetailTotalNet')","SKIN:Bang('!HideMeter', p .. 'DetailTotalTax')",
    "SKIN:Bang('!HideMeter', p .. 'Name')","SKIN:Bang('!HideMeter', p .. 'Window')","SKIN:Bang('!HideMeter', p .. 'Chance')",
    'if lastSortMode ~= mode then collapseInlineGraph() end',
    "setVariable('InlineGraphMarketKey', key)","SKIN:Bang('!CommandMeasure', 'MeasureInlineGraph', 'Run')",
    'local function effectiveSortMode(rows, requestedMode)',"out.OpportunitySortEffectiveMode = effectiveMode",
    'local function safeLeaveText(data, prefix)',"return 'WAIT DATA'","return 'NO HIT'",
    "SKIN:Bang('!SetOption', p .. 'InlineGraph', 'Y'",'graphImagePath(expandedKey)',
    'flagMaskImagePath','flag-mask-both.png','flag-mask-top.png','flag-mask-bottom.png','applyItemImageForRow','requestItemImages','MeasureItemImages','VisibleItemImageIds'
)) {
    if (-not $reader.Contains($token)) { Fail "StateReader.lua missing '$token'." }
}

foreach($surface in @($ini,$rows)){
    foreach($match in [regex]::Matches($surface,'(?im)^ToolTipText=(.+)$')){
        if(-not[string]::IsNullOrWhiteSpace($match.Groups[1].Value)){Fail "Only dynamically populated flag/window tooltips are allowed; static tooltip found: $($match.Groups[1].Value)"}
    }
}
foreach($forbiddenDynamicTooltip in @(
    "MeterTitle', 'ToolTipText', 'Open Torn travel'",
    "meter, 'ToolTipText', itemName",
    "DetailToggle', 'ToolTipText', detailExpanded",
    "Name', 'ToolTipText', tooltip",
    "Gross', 'ToolTipText', tooltip"
)){
    if($reader.Contains($forbiddenDynamicTooltip)){Fail "StateReader retains non-window tooltip owner '$forbiddenDynamicTooltip'."}
}

if($ini -notmatch '(?m)^Card=0,0,0,255\s*$'){Fail 'Opportunity card background must be pure black.'}
if($ini -notmatch '(?m)^Accent=126,190,73,255\s*$'){Fail 'Main UI accent must use Torn lime.'}
foreach($iconName in @('MeterFilterIcon','MeterSettingsIcon')){
    $iconBody=[regex]::Match($ini,'(?ms)^\['+$iconName+'\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if($iconBody -notmatch '(?im)^Greyscale=1\s*$' -or $iconBody -notmatch '(?im)^ImageTint=#TornLime#\s*$'){Fail "$iconName must render with the Torn-lime icon tint."}
}
if($ini -notmatch '(?m)^Control=32,32,32,248\s*$'){Fail 'Sort-control background must remain neutral gray.'}
$sortProfit=[regex]::Match($ini,'(?ms)^\[MeterSortGross\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if($sortProfit -notmatch '(?im)^Text=PROFIT\s*$'){Fail 'Displayed-profit sort must be labeled PROFIT.'}

$tokens=$null; $parseErrors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($rendererPath,[ref]$tokens,[ref]$parseErrors)
foreach($parseError in @($parseErrors)){ Fail "RenderInlineGraph.ps1 parse error: $($parseError.Message)" }
foreach ($token in @(
    'RuntimeObservationFile','SeedObservationFile','$historySource = ''runtime_observations''','if ($allRows.Count -eq 0)',
    'Compress-StockHistory','history_bootstrap','history_repair_baseline','current_snapshot',
    'Add-Type -AssemblyName System.Drawing','New-Object System.Drawing.Bitmap','for ($i=0; $i -le 8; $i++)',
    'Copy-Item -LiteralPath $imagePath -Destination $stableImagePath -Force','StableImageFile','PointCount','ChangeCount',
    'UnknownBeforeTimestamp','WindowStartTimestamp',
    '$graphics.Clear([System.Drawing.Color]::FromArgb(0,0,0))',
    'FromArgb(126,190,73),2','FromArgb(0,71,171),1','FromArgb(255,117,24),1'
)) {
    if (-not $renderer.Contains($token)) { Fail "Inline renderer missing '$token'." }
}
if ($renderer -match '(?i)Invoke-RestMethod|Invoke-WebRequest|curl\.exe|api\.torn\.com|prombot\.co\.uk|yata\.yt') { Fail 'Inline renderer must remain local-only.' }
foreach ($retired in @('H STOCK  |','retained point(s)','change(s)','Path GraphPath','display_carry')) {
    if ($renderer.Contains($retired)) { Fail "Inline renderer retains retired visible/fabricated-history token '$retired'." }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Rainmeter native-image opportunity validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Rainmeter card layering, bounded update timeout, isolated inline-graph visibility, native FlagKit cards, sort-collapse behavior, separate inline/popup transports, and observed-only PNG history validation passed.' -ForegroundColor Green
exit 0
