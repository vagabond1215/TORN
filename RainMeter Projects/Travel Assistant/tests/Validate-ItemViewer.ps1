$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$viewerPath=Join-Path $ProjectRoot '@Resources\Scripts\OpenItemViewer.ps1'
$launcherPath=Join-Path $ProjectRoot '@Resources\Scripts\LaunchItemViewer.ps1'
$inlineRendererPath=Join-Path $ProjectRoot '@Resources\Scripts\RenderInlineGraph.ps1'
$hostPath=Join-Path $ProjectRoot '@Resources\Scripts\PopupHost.ps1'
$historyPath=Join-Path $ProjectRoot '@Resources\Scripts\MaintainObservationHistory.ps1'
$settingsPath=Join-Path $ProjectRoot 'config\settings.example.json'
$errors=New-Object System.Collections.Generic.List[string]
function Fail([string]$Message){$script:errors.Add($Message)}

foreach($path in @($viewerPath,$launcherPath,$inlineRendererPath,$hostPath,$historyPath)){
 if(-not(Test-Path -LiteralPath $path)){Fail "Missing $path.";continue}
 $tokens=$null;$parseErrors=$null
 [void][System.Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$parseErrors)
 foreach($parseError in @($parseErrors)){Fail "PowerShell parse error in $(Split-Path $path -Leaf): $($parseError.Message)"}
}

if(Test-Path -LiteralPath $launcherPath){
 $launcher=Get-Content -LiteralPath $launcherPath -Raw
 foreach($token in @('PopupHost.ps1','Start-Process','-WindowStyle Hidden','-STA','-Popup ItemViewer','-MarketKey','$MarketKey')){if(-not$launcher.Contains($token)){Fail "Viewer launcher missing '$token'."}}
 if($launcher.Contains('-WindowStyle Normal')){Fail 'Viewer launcher must not expose a PowerShell console.'}
}

if(Test-Path -LiteralPath $hostPath){
 $hostText=Get-Content -LiteralPath $hostPath -Raw
 foreach($token in @('OpenItemViewer.ps1','RuntimeLog.ps1','Write-TravelAssistantLog','ItemViewer')){if(-not$hostText.Contains($token)){Fail "PopupHost viewer contract missing '$token'."}}
}

if(Test-Path -LiteralPath $viewerPath){
 $viewer=Get-Content -LiteralPath $viewerPath -Raw
 foreach($token in @('[string]$MarketKey','RuntimeObservationFile','SeedObservationFile','MaintainObservationHistory.ps1','graphWindowHours','observedMarkets','resaleCache','sourceTimestamp','carry_forward',"ToString('HH:mm')",'Green: observed restock','Red: observed sellout','Dropdown is sorted by known profit/item.')){if(-not$viewer.Contains($token)){Fail "Standalone Viewer missing '$token'."}}
 if($viewer -match '(?i)Invoke-RestMethod|Invoke-WebRequest|api\.torn\.com|prombot\.co\.uk|yata\.yt'){Fail 'Standalone Viewer must remain local-only.'}
}

if(Test-Path -LiteralPath $inlineRendererPath){
 $inline=Get-Content -LiteralPath $inlineRendererPath -Raw
 foreach($token in @(
  'RuntimeObservationFile','SeedObservationFile','$historySource = ''runtime_observations''','if ($allRows.Count -eq 0)',
  'Compress-StockHistory','history_bootstrap','history_repair_baseline','current_snapshot',
  'Add-Type -AssemblyName System.Drawing','New-Object System.Drawing.Bitmap','for ($i=0; $i -le 8; $i++)',
  'PointCount','ChangeCount','StableImageFile','stableImagePath','UnknownBeforeTimestamp','WindowStartTimestamp'
 )){if(-not$inline.Contains($token)){Fail "Inline card renderer missing '$token'."}}
 if($inline -match '(?i)Invoke-RestMethod|Invoke-WebRequest|api\.torn\.com|prombot\.co\.uk|yata\.yt'){Fail 'Inline card renderer must remain local-only.'}
 foreach($retired in @('Path GraphPath','display_carry')){if($inline.Contains($retired)){Fail "Inline card renderer retains retired fabricated/Shape behavior '$retired'."}}
}

if(Test-Path -LiteralPath $historyPath){
 $history=Get-Content -LiteralPath $historyPath -Raw
 foreach($token in @(
  'Write-BaselineAwareObservationPrune','retention_baseline','latestBefore','Test-IsSyntheticHistorySource',
  'Remove-SyntheticObservationArtifacts',"@('history_bootstrap','history_repair_baseline')",'[void](Remove-SyntheticObservationArtifacts)',
  "if (`$Phase -eq 'PostUpdate') { return }"
 )){if(-not$history.Contains($token)){Fail "History maintenance missing '$token'."}}
 if($history.Contains('Add-MissingMarketBaselines')){Fail 'History maintenance must not recreate migration-era synthetic baselines.'}
}

if(-not(Test-Path -LiteralPath $settingsPath)){Fail 'Missing settings.example.json.'}
else{
 $settings=Get-Content -LiteralPath $settingsPath -Raw|ConvertFrom-Json
 if([int]$settings.graphWindowHours -ne 8){Fail 'Graph display must remain eight hours.'}
 if([int]$settings.highResolutionRetentionHours -ne 48){Fail 'High-resolution retention must remain 48 hours.'}
 if([int]$settings.cycleRetentionDays -ne 90){Fail 'Completed-cycle retention must remain 90 days.'}
}

if($errors.Count -gt 0){foreach($message in $errors){Write-Host "FAIL: $message" -ForegroundColor Red};Write-Host "Item viewer validation failed with $($errors.Count) error(s)." -ForegroundColor Red;exit 1}
Write-Host 'Standalone Viewer and separate observed-only runtime PNG inline-history validation passed.' -ForegroundColor Green
Write-Host 'Legacy synthetic rows are purged; retention carry-forward is allowed only from an actual predecessor observation.' -ForegroundColor DarkGreen
exit 0
