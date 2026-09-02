$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$iniPath = Join-Path $ProjectRoot 'TravelAssistant.ini'
$rowIncludePath = Join-Path $ProjectRoot '@Resources\Includes\OpportunityRows.inc'
$stateReaderPath = Join-Path $ProjectRoot '@Resources\Scripts\StateReader.lua'
$rendererPath = Join-Path $ProjectRoot '@Resources\Scripts\RenderInlineGraph.ps1'
$flagDir = Join-Path $ProjectRoot '@Resources\Images\Flags'
$errors = New-Object System.Collections.Generic.List[string]
function Fail([string]$Message) { $script:errors.Add($Message) }

foreach ($path in @($iniPath,$rowIncludePath,$stateReaderPath,$rendererPath)) {
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

foreach ($section in @('MeasureUpdate','MeasureSettings','MeasureFilterPopup','MeasureInlineGraph','MeasurePreferenceAction','MeasureState','MeterSortUpcoming','MeterSortGross','MeterSortProfitHour')) {
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
    foreach ($suffix in @('Card','Flag','Name','Gross','DetailTotal','Window','Leave','Chance','Price','Take','Make','DetailToggle','Graph','InlineGraph')) {
        $section='MeterOpportunity'+$i+$suffix
        if ($rows -notmatch ('(?m)^\['+[regex]::Escape($section)+'\]\s*$')) { Fail "OpportunityRows.inc missing [$section]." }
    }
    $flagBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Flag\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $detailBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailToggle\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $nameBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Name\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $priceBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Price\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $takeBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Take\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $makeBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Make\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $grossBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Gross\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $detailTotalBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'DetailTotal\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $graphButtonBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Graph\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $graphBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'InlineGraph\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if ($flagBody -notmatch '(?im)^Meter=Image\s*$' -or $flagBody -notmatch '(?im)^W=62\s*$' -or $flagBody -notmatch '(?im)^H=44\s*$') { Fail "Opportunity $i flag must be a near-full-height native Image meter." }
    if ($detailBody -notmatch '(?im)^Text=\$\s*$' -or $detailBody -notmatch ('ToggleCardDetails\('+[string]$i+'\)')) { Fail "Opportunity $i money button must control the top economics strip." }
    if ($graphButtonBody -notmatch '(?im)^Meter=Shape\s*$' -or $graphButtonBody -notmatch '(?im)^GraphExpanded=0\s*$') { Fail "Opportunity $i graph control must be a chart Shape button." }
    foreach($token in @('X=518','W=26','H=25','Shape=Rectangle 0,0,26,25 | Fill Color 0,0,0,1 | StrokeWidth 0','Stroke Color #ToggleIdle#','Shape2=Line 8,17,8,8','Shape3=Line 8,17,18,17','Shape4=Line 9,15,12,12','Shape5=Line 12,12,14,14','Shape6=Line 14,14,18,9')){if(-not$graphButtonBody.Contains($token)){Fail "Opportunity $i chart end-cap control missing '$token'."}}
    if ($nameBody -notmatch '(?im)^W=1\s*$' -or $nameBody -notmatch '(?im)^FontSize=11\s*$' -or $nameBody -notmatch '(?im)^FontColor=0,0,0,0\s*$') { Fail "Opportunity $i canonical Name meter must stay hidden behind the combined first line." }
    if ($priceBody -notmatch '(?im)^X=78\s*$' -or $priceBody -notmatch '(?im)^W=198\s*$' -or $priceBody -notmatch '(?im)^FontSize=11\s*$') { Fail "Opportunity $i item/unit-cost column must be fixed at x=78, width 198." }
    if ($takeBody -notmatch '(?im)^X=280\s*$' -or $takeBody -notmatch '(?im)^W=108\s*$' -or $takeBody -notmatch '(?im)^FontSize=11\s*$' -or $takeBody -notmatch '(?im)^FontColor=#ToggleIdle#\s*$') { Fail "Opportunity $i full-load total cost must be light gray at x=280." }
    if ($makeBody -notmatch '(?im)^X=504\s*$' -or $makeBody -notmatch '(?im)^W=108\s*$' -or $makeBody -notmatch '(?im)^H=50\s*$' -or $makeBody -notmatch '(?im)^FontSize=15\s*$' -or $makeBody -notmatch '(?im)^StringAlign=RightCenter\s*$') { Fail "Opportunity $i signed total net must span both text lines and align right-center at x=504." }
    if ($grossBody -notmatch '(?im)^X=14\s*$' -or $grossBody -notmatch '(?im)^W=256\s*$' -or $grossBody -notmatch '(?im)^H=18\s*$' -or $grossBody -notmatch '(?im)^FontSize=10\s*$' -or $grossBody -notmatch '(?im)^StringAlign=LeftCenter\s*$') { Fail "Opportunity $i per-item economics half must be 10pt and vertically centered." }
    if ($detailTotalBody -notmatch '(?im)^X=282\s*$' -or $detailTotalBody -notmatch '(?im)^W=256\s*$' -or $detailTotalBody -notmatch '(?im)^H=18\s*$' -or $detailTotalBody -notmatch '(?im)^FontSize=10\s*$' -or $detailTotalBody -notmatch '(?im)^StringAlign=LeftCenter\s*$') { Fail "Opportunity $i total economics half must mirror the per-item half." }
    foreach($fontBody in @($nameBody,$priceBody,$takeBody,$makeBody,$grossBody,$detailTotalBody,$detailBody)){if($fontBody -match '(?im)^FontFace=' -and $fontBody -notmatch '(?im)^FontFace=Nirmala UI Semilight\s*$'){Fail "Opportunity $i card string meters must use Nirmala UI Semilight."}}
    if ($graphBody -notmatch '(?im)^Meter=Image\s*$' -or $graphBody -notmatch '(?im)^W=528\s*$' -or $graphBody -notmatch '(?im)^H=125\s*$') { Fail "Opportunity $i inline graph must be the 528x125 native Image surface." }
    if ($graphBody -notmatch ('(?im)^Group=OpportunityInlineGraph'+$i+'\s*$')) { Fail "Opportunity $i inline graph must use its isolated visibility group." }
    if ($graphBody -match ('(?im)^Group=OpportunityRow'+$i+'\s*$')) { Fail "Opportunity $i inline graph must not be re-shown by the row visibility group." }
    if ($rows -match ('(?ms)^\[MeterOpportunity'+$i+'Rank\]')) { Fail "Opportunity $i must not restore visible place/rank meters." }
    if ($rows -match ('(?ms)^\[MeterOpportunity'+$i+'Country\]')) { Fail "Opportunity $i must not add a separate country meter; country belongs in the title." }
    if ($rows -match ('(?ms)^\[MeterOpportunity'+$i+'Time\]')) { Fail "Opportunity $i must not restore travel/elapsed text in the card body." }
}

foreach ($code in @('MX','KY','CA','US','GB','AR','CH','JP','CN','AE','ZA')) {
    if (-not (Test-Path -LiteralPath (Join-Path $flagDir ($code+'@3x.png')))) { Fail "Missing FlagKit asset ${code}@3x.png." }
}
if (-not (Test-Path -LiteralPath (Join-Path $flagDir 'LICENSE-FlagKit.txt'))) { Fail 'FlagKit MIT attribution file is missing.' }

foreach ($token in @(
    "mexico='MX'","cayman_islands='KY'","hawaii='US'","united_kingdom='GB'","united_arab_emirates='AE'",
    "return flagDir .. code .. '@3x.png'",'ToolTipText',"' | travel '",
    'local function setGraphButtonState(name, expanded)','local function setDetailButtonState(name, expanded)',
    "'GraphExpanded', expanded and '1' or '0'","SKIN:Bang('!SetOption', name, 'Text', '$')","'126,190,73,255'","'38,38,38,255'","'190,190,190,255'",
    'local function collapseInlineGraph()','local function collapseCardDetails()','function ToggleCardDetails(index)',
    'local detailExtra = 18','local graphExtra = 133','local footerExtra = 16','expandedDetailKey','expandedDetailRow',
    "if expandedDetailRow > 0 and i > expandedDetailRow then extraBefore = extraBefore + detailExtra end",
    "local cardHeight = collapsedCardHeight + bodyOffset + (graphExpanded and graphExtra or 0)",
    "SKIN:Bang('!ShowMeter', p .. 'Gross')","SKIN:Bang('!ShowMeter', p .. 'DetailTotal')",
    "SKIN:Bang('!HideMeter', p .. 'Gross')","SKIN:Bang('!HideMeter', p .. 'DetailTotal')",
    "SKIN:Bang('!HideMeter', p .. 'Name')","SKIN:Bang('!HideMeter', p .. 'Window')","SKIN:Bang('!HideMeter', p .. 'Chance')",
    'if lastSortMode ~= mode then collapseInlineGraph() end',
    "setVariable('InlineGraphMarketKey', key)","SKIN:Bang('!CommandMeasure', 'MeasureInlineGraph', 'Run')",
    'local function effectiveSortMode(rows, requestedMode)',"out.OpportunitySortEffectiveMode = effectiveMode",
    'local function safeLeaveText(data, prefix)',"return 'WAIT DATA'","return 'NO HIT'",
    "SKIN:Bang('!SetOption', p .. 'InlineGraph', 'Y'",'graphImagePath(expandedKey)'
)) {
    if (-not $reader.Contains($token)) { Fail "StateReader.lua missing '$token'." }
}

$tokens=$null; $parseErrors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($rendererPath,[ref]$tokens,[ref]$parseErrors)
foreach($parseError in @($parseErrors)){ Fail "RenderInlineGraph.ps1 parse error: $($parseError.Message)" }
foreach ($token in @(
    'RuntimeObservationFile','SeedObservationFile','$historySource = ''runtime_observations''','if ($allRows.Count -eq 0)',
    'Compress-StockHistory','history_bootstrap','history_repair_baseline','current_snapshot',
    'Add-Type -AssemblyName System.Drawing','New-Object System.Drawing.Bitmap','for ($i=0; $i -le 8; $i++)',
    'Copy-Item -LiteralPath $imagePath -Destination $stableImagePath -Force','StableImageFile','PointCount','ChangeCount',
    'UnknownBeforeTimestamp','WindowStartTimestamp'
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
) { Fail "Opportunity $i full-load total cost must be light gray at x=280." }
    if ($makeBody -notmatch '(?im)^X=504\s*$' -or $makeBody -notmatch '(?im)^W=108\s*$' -or $makeBody -notmatch '(?im)^H=50\s*$' -or $makeBody -notmatch '(?im)^FontSize=15\s*$' -or $makeBody -notmatch '(?im)^StringAlign=RightCenter\s*$') { Fail "Opportunity $i signed total net must span both text lines and align right-center at x=504." }
    if ($grossBody -notmatch '(?im)^X=14\s*$' -or $grossBody -notmatch '(?im)^W=256\s*$' -or $grossBody -notmatch '(?im)^H=18\s*$' -or $grossBody -notmatch '(?im)^FontSize=10\s*$' -or $grossBody -notmatch '(?im)^StringAlign=LeftCenter\s*$') { Fail "Opportunity $i per-item economics half must be 10pt and vertically centered." }
    if ($detailTotalBody -notmatch '(?im)^X=282\s*$' -or $detailTotalBody -notmatch '(?im)^W=256\s*$' -or $detailTotalBody -notmatch '(?im)^H=18\s*$' -or $detailTotalBody -notmatch '(?im)^FontSize=10\s*$' -or $detailTotalBody -notmatch '(?im)^StringAlign=LeftCenter\s*$') { Fail "Opportunity $i total economics half must mirror the per-item half." }
    foreach($fontBody in @($nameBody,$priceBody,$takeBody,$makeBody,$grossBody,$detailTotalBody,$detailBody)){if($fontBody -match '(?im)^FontFace=' -and $fontBody -notmatch '(?im)^FontFace=Nirmala UI Semilight\s*$'){Fail "Opportunity $i card string meters must use Nirmala UI Semilight."}}
    if ($graphBody -notmatch '(?im)^Meter=Image\s*$' -or $graphBody -notmatch '(?im)^W=528\s*$' -or $graphBody -notmatch '(?im)^H=125\s*$') { Fail "Opportunity $i inline graph must be the 528x125 native Image surface." }
    if ($graphBody -notmatch ('(?im)^Group=OpportunityInlineGraph'+$i+'\s*$')) { Fail "Opportunity $i inline graph must use its isolated visibility group." }
    if ($graphBody -match ('(?im)^Group=OpportunityRow'+$i+'\s*$')) { Fail "Opportunity $i inline graph must not be re-shown by the row visibility group." }
    if ($rows -match ('(?ms)^\[MeterOpportunity'+$i+'Rank\]')) { Fail "Opportunity $i must not restore visible place/rank meters." }
    if ($rows -match ('(?ms)^\[MeterOpportunity'+$i+'Country\]')) { Fail "Opportunity $i must not add a separate country meter; country belongs in the title." }
    if ($rows -match ('(?ms)^\[MeterOpportunity'+$i+'Time\]')) { Fail "Opportunity $i must not restore travel/elapsed text in the card body." }
}

foreach ($code in @('MX','KY','CA','US','GB','AR','CH','JP','CN','AE','ZA')) {
    if (-not (Test-Path -LiteralPath (Join-Path $flagDir ($code+'@3x.png')))) { Fail "Missing FlagKit asset ${code}@3x.png." }
}
if (-not (Test-Path -LiteralPath (Join-Path $flagDir 'LICENSE-FlagKit.txt'))) { Fail 'FlagKit MIT attribution file is missing.' }

foreach ($token in @(
    "mexico='MX'","cayman_islands='KY'","hawaii='US'","united_kingdom='GB'","united_arab_emirates='AE'",
    "return flagDir .. code .. '@3x.png'",'ToolTipText',"' | travel '",
    'local function setGraphButtonState(name, expanded)','local function setDetailButtonState(name, expanded)',
    "'GraphExpanded', expanded and '1' or '0'","SKIN:Bang('!SetOption', name, 'Text', '$')","'126,190,73,255'","'38,38,38,255'","'190,190,190,255'",
    'local function collapseInlineGraph()','local function collapseCardDetails()','function ToggleCardDetails(index)',
    'local detailExtra = 18','local graphExtra = 133','local footerExtra = 16','expandedDetailKey','expandedDetailRow',
    "if expandedDetailRow > 0 and i > expandedDetailRow then extraBefore = extraBefore + detailExtra end",
    "local cardHeight = collapsedCardHeight + bodyOffset + (graphExpanded and graphExtra or 0)",
    "SKIN:Bang('!ShowMeter', p .. 'Gross')","SKIN:Bang('!ShowMeter', p .. 'DetailTotal')",
    "SKIN:Bang('!HideMeter', p .. 'Gross')","SKIN:Bang('!HideMeter', p .. 'DetailTotal')",
    "SKIN:Bang('!HideMeter', p .. 'Name')","SKIN:Bang('!HideMeter', p .. 'Window')","SKIN:Bang('!HideMeter', p .. 'Chance')",
    'if lastSortMode ~= mode then collapseInlineGraph() end',
    "setVariable('InlineGraphMarketKey', key)","SKIN:Bang('!CommandMeasure', 'MeasureInlineGraph', 'Run')",
    'local function effectiveSortMode(rows, requestedMode)',"out.OpportunitySortEffectiveMode = effectiveMode",
    'local function safeLeaveText(data, prefix)',"return 'WAIT DATA'","return 'NO HIT'",
    "SKIN:Bang('!SetOption', p .. 'InlineGraph', 'Y'",'graphImagePath(expandedKey)'
)) {
    if (-not $reader.Contains($token)) { Fail "StateReader.lua missing '$token'." }
}

$tokens=$null; $parseErrors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($rendererPath,[ref]$tokens,[ref]$parseErrors)
foreach($parseError in @($parseErrors)){ Fail "RenderInlineGraph.ps1 parse error: $($parseError.Message)" }
foreach ($token in @(
    'RuntimeObservationFile','SeedObservationFile','$historySource = ''runtime_observations''','if ($allRows.Count -eq 0)',
    'Compress-StockHistory','history_bootstrap','history_repair_baseline','current_snapshot',
    'Add-Type -AssemblyName System.Drawing','New-Object System.Drawing.Bitmap','for ($i=0; $i -le 8; $i++)',
    'Copy-Item -LiteralPath $imagePath -Destination $stableImagePath -Force','StableImageFile','PointCount','ChangeCount',
    'UnknownBeforeTimestamp','WindowStartTimestamp'
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
