param(
    [ValidateSet('Read','Toggle')]
    [string]$Action = 'Read',
    [ValidateSet('Hindsight','Chance','Window','Stock')]
    [string]$Value = 'Hindsight'
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$ConfigDir = Join-Path $ProjectRoot 'config'
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$BaseSettingsPath = Join-Path $ConfigDir 'settings.example.json'
$LocalSettingsPath = Join-Path $ConfigDir 'settings.local.json'
$LocalExamplePath = Join-Path $ConfigDir 'settings.local.example.json'
$StatePath = Join-Path $GeneratedDir 'graph-visuals.kv'
$AtomicFileScript = Join-Path $PSScriptRoot 'AtomicFile.ps1'
if (-not (Test-Path -LiteralPath $AtomicFileScript)) { throw 'AtomicFile.ps1 is required for graph visual preferences.' }
. $AtomicFileScript

function Read-GraphVisualJson {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $raw = Read-TravelAssistantSharedText -Path $Path
    if ([string]::IsNullOrWhiteSpace($raw)) { return $null }
    return ($raw | ConvertFrom-Json)
}

function Set-GraphVisualProperty {
    param([object]$Object,[string]$Name,[object]$Value)
    $property=$Object.PSObject.Properties[$Name]
    if($null -eq $property){$Object|Add-Member NoteProperty $Name $Value}
    else{$property.Value=$Value}
}

function Get-GraphVisualEffectiveValue {
    param([object]$Base,[object]$Local,[string]$Name,[bool]$Default=$true)
    $value=$Default
    if($null -ne $Base -and $Base.PSObject.Properties['graphVisuals']){
        $visuals=$Base.graphVisuals
        if($null -ne $visuals -and $null -ne $visuals.PSObject.Properties[$Name]){$value=[bool]$visuals.PSObject.Properties[$Name].Value}
    }
    if($null -ne $Local -and $Local.PSObject.Properties['graphVisuals']){
        $visuals=$Local.graphVisuals
        if($null -ne $visuals -and $null -ne $visuals.PSObject.Properties[$Name]){$value=[bool]$visuals.PSObject.Properties[$Name].Value}
    }
    return [bool]$value
}

function Ensure-GraphVisualObject {
    param([object]$Local)
    if($null -eq $Local.PSObject.Properties['graphVisuals']){
        $Local|Add-Member NoteProperty graphVisuals ([pscustomobject]@{})
    }elseif($null -eq $Local.graphVisuals){
        $Local.graphVisuals=[pscustomobject]@{}
    }
    return $Local.graphVisuals
}

function Write-GraphVisualJsonAtomic {
    param([string]$Path,[object]$Value)
    $json=$Value|ConvertTo-Json -Depth 20
    Write-TravelAssistantAtomicText -Path $Path -Text $json
}

function Write-GraphVisualState {
    param([object]$Base,[object]$Local)
    New-Item -ItemType Directory -Force -Path $GeneratedDir | Out-Null
    $values=[ordered]@{
        GraphHindsightOn=$(if(Get-GraphVisualEffectiveValue -Base $Base -Local $Local -Name 'showHindsightWindows'){'1'}else{'0'})
        GraphChanceOn=$(if(Get-GraphVisualEffectiveValue -Base $Base -Local $Local -Name 'showChance'){'1'}else{'0'})
        GraphWindowOn=$(if(Get-GraphVisualEffectiveValue -Base $Base -Local $Local -Name 'showRestockWindowBounds'){'1'}else{'0'})
        GraphStockOn=$(if(Get-GraphVisualEffectiveValue -Base $Base -Local $Local -Name 'showTransitions'){'1'}else{'0'})
        UpdatedAt=[DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    }
    $lines=@()
    foreach($key in $values.Keys){$lines+=($key+'='+[string]$values[$key])}
    Write-TravelAssistantAtomicText -Path $StatePath -Text (($lines -join [Environment]::NewLine)+[Environment]::NewLine)
}

$base=Read-GraphVisualJson $BaseSettingsPath
if($null -eq $base){throw 'settings.example.json is required for graph visual preferences.'}
$local=Read-GraphVisualJson $LocalSettingsPath
if($null -eq $local){$local=Read-GraphVisualJson $LocalExamplePath}
if($null -eq $local){$local=[pscustomobject]@{schemaVersion=1}}

if($Action -eq 'Toggle'){
    $settingName=switch($Value){
        'Hindsight' {'showHindsightWindows'}
        'Chance' {'showChance'}
        'Window' {'showRestockWindowBounds'}
        'Stock' {'showTransitions'}
    }
    $current=Get-GraphVisualEffectiveValue -Base $base -Local $local -Name $settingName
    $visuals=Ensure-GraphVisualObject -Local $local
    Set-GraphVisualProperty -Object $visuals -Name $settingName -Value (-not $current)
    Write-GraphVisualJsonAtomic -Path $LocalSettingsPath -Value $local
}

Write-GraphVisualState -Base $base -Local $local
