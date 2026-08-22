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
if (-not $ini.Contains('@Include=#@#Includes\OpportunityRows.inc')) { Fail 'TravelAssistant.ini must include OpportunityRows.inc.' }
foreach ($section in @('MeasureUpdate','MeasureSettings','MeasureFilterPopup','MeasureItemViewer','MeasureInlineGraph','MeasurePreferenceAction','MeasureState','MeterSortName','MeterSortUpcoming','MeterSortGross','MeterSortProfitHour','MeterViewer')) {
    if ($ini -notmatch ('(?m)^\['+[regex]::Escape($section)+'\]\s*$')) { Fail "Missing [$section]." }
}

$viewerBody=[regex]::Match($ini,'(?ms)^\[MeasureItemViewer\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
$inlineBody=[regex]::Match($ini,'(?ms)^\[MeasureInlineGraph\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
if ($viewerBody -notmatch 'LaunchItemViewer\.ps1' -or $viewerBody -notmatch '#ViewerMarketKey#') { Fail 'Standalone Viewer must use LaunchItemViewer.ps1 and ViewerMarketKey.' }
if ($inlineBody -notmatch 'RenderInlineGraph\.ps1' -or $inlineBody -notmatch '#InlineGraphMarketKey#') { Fail 'Inline chevron must use its own local RenderInlineGraph.ps1 measure.' }
if ($inlineBody -match 'LaunchItemViewer|PopupHost|ViewerMarketKey') { Fail 'Inline history measure must not route through the popup Viewer.' }

foreach ($i in 1..8) {
    foreach ($suffix in @('Card','Flag','Name','Gross','Window','Leave','Chance','Price','Graph','InlineGraph')) {
        $section='MeterOpportunity'+$i+$suffix
        if ($rows -notmatch ('(?m)^\['+[regex]::Escape($section)+'\]\s*$')) { Fail "OpportunityRows.inc missing [$section]." }
    }
    $flagBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'Flag\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    $graphBody=[regex]::Match($rows,'(?ms)^\[MeterOpportunity'+$i+'InlineGraph\]\s*(.*?)(?=^\[|\z)').Groups[1].Value
    if ($flagBody -notmatch '(?im)^Meter=Image\s*$' -or $flagBody -notmatch '(?im)^W=62\s*$' -or $flagBody -notmatch '(?im)^H=44\s*$') { Fail "Opportunity $i flag must be a near-full-height native Image meter." }
    if ($graphBody -notmatch '(?im)^Meter=Image\s*$') { Fail "Opportunity $i inline graph must be a native Image meter." }
    if ($rows -match ('(?ms)^\[MeterOpportunity'+$i+'Rank\]')) { Fail "Opportunity $i must not restore visible place/rank meters." }
    if ($rows -match ('(?ms)^\[MeterOpportunity'+$i+'Country\]')) { Fail "Opportunity $i must not restore country text in the card body." }
    if ($rows -match ('(?ms)^\[MeterOpportunity'+$i+'Time\]')) { Fail "Opportunity $i must not restore travel/elapsed text in the card body." }
}

foreach ($code in @('MX','KY','CA','US','GB','AR','CH','JP','CN','AE','ZA')) {
    if (-not (Test-Path -LiteralPath (Join-Path $flagDir ($code+'@3x.png')))) { Fail "Missing FlagKit asset ${code}@3x.png." }
}
if (-not (Test-Path -LiteralPath (Join-Path $flagDir 'LICENSE-FlagKit.txt'))) { Fail 'FlagKit MIT attribution file is missing.' }

foreach ($token in @(
    "mexico='MX'","cayman_islands='KY'","hawaii='US'","united_kingdom='GB'","united_arab_emirates='AE'",
    "return flagDir .. code .. '@3x.png'",'ToolTipText',"' | travel '",
    'local function collapseInlineGraph()','if lastSortMode ~= mode then collapseInlineGraph() end',
    "setVariable('InlineGraphMarketKey', key)","SKIN:Bang('!CommandMeasure', 'MeasureInlineGraph', 'Run')",
    "setVariable('ViewerMarketKey', marketKey or '')","SKIN:Bang('!CommandMeasure', 'MeasureItemViewer', 'Run')",
    'local function safeLeaveText(data, prefix)',"return 'WAIT DATA'","return 'NO HIT'",
    "SKIN:Bang('!SetOption', p .. 'InlineGraph', 'Y'",'graphImagePath(expandedKey)'
)) {
    if (-not $reader.Contains($token)) { Fail "StateReader.lua missing '$token'." }
}
if ($reader.Contains("runViewerMeasure('inline_'")) { Fail 'Inline graph must never execute through the standalone Viewer transport.' }

$tokens=$null; $parseErrors=$null
[void][System.Management.Automation.Language.Parser]::ParseFile($rendererPath,[ref]$tokens,[ref]$parseErrors)
foreach($parseError in @($parseErrors)){ Fail "RenderInlineGraph.ps1 parse error: $($parseError.Message)" }
foreach ($token in @(
    'RuntimeObservationFile','SeedObservationFile',"$historySource = 'runtime_observations'",'if ($allRows.Count -eq 0)',
    "source='current_snapshot'",'Add-Type -AssemblyName System.Drawing','New-Object System.Drawing.Bitmap',
    'for ($i=0; $i -le 8; $i++)','Copy-Item -LiteralPath $imagePath -Destination $stableImagePath -Force',
    'StableImageFile','PointCount','ChangeCount'
)) {
    if (-not $renderer.Contains($token)) { Fail "Inline renderer missing '$token'." }
}
if ($renderer -match '(?i)Invoke-RestMethod|Invoke-WebRequest|curl\.exe|api\.torn\.com|prombot\.co\.uk|yata\.yt') { Fail 'Inline renderer must remain local-only.' }
foreach ($retired in @('H STOCK  |','retained point(s)','change(s)','Path GraphPath')) {
    if ($renderer.Contains($retired)) { Fail "Inline renderer retains retired visible/Shape chart token '$retired'." }
}

if ($errors.Count -gt 0) {
    foreach ($message in $errors) { Write-Host "FAIL: $message" -ForegroundColor Red }
    Write-Host "Rainmeter native-image opportunity validation failed with $($errors.Count) error(s)." -ForegroundColor Red
    exit 1
}
Write-Host 'Rainmeter native FlagKit cards, sort-collapse behavior, separate inline/popup transports, and runtime-observation PNG history validation passed.' -ForegroundColor Green
exit 0
