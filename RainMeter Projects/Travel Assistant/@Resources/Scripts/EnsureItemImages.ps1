param(
    [Parameter(Mandatory=$true)]
    [string]$ItemIds
)

$ErrorActionPreference='Stop'
Set-StrictMode -Version 2.0

$ProjectRoot=(Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$GeneratedDir=Join-Path $ProjectRoot '@Resources\Generated'
$ItemDir=Join-Path $GeneratedDir 'Items'
New-Item -ItemType Directory -Force -Path $ItemDir | Out-Null

$ids=@()
foreach($token in @($ItemIds -split ',')){
    $id=0
    if([int]::TryParse(([string]$token).Trim(),[ref]$id) -and $id -gt 0){
        $ids+=$id
    }
}
$ids=@($ids | Select-Object -Unique | Select-Object -First 16)
if($ids.Count -eq 0){ exit 0 }

Add-Type -AssemblyName System.Net.Http
$client=New-Object System.Net.Http.HttpClient
$client.Timeout=[TimeSpan]::FromSeconds(8)
$client.DefaultRequestHeaders.UserAgent.ParseAdd('TORN-Travel-Assistant/0.6')

try {
    foreach($id in $ids){
        $destination=Join-Path $ItemDir (([string]$id)+'.png')
        if(Test-Path -LiteralPath $destination){
            try {
                if((Get-Item -LiteralPath $destination).Length -gt 8){ continue }
            } catch { }
        }

        $url=('https://www.torn.com/images/items/{0}/large.png' -f $id)
        try {
            $response=$client.GetAsync($url).GetAwaiter().GetResult()
            if(-not $response.IsSuccessStatusCode){ continue }
            $bytes=$response.Content.ReadAsByteArrayAsync().GetAwaiter().GetResult()
            if($null -eq $bytes -or $bytes.Length -lt 8){ continue }
            if($bytes[0] -ne 137 -or $bytes[1] -ne 80 -or $bytes[2] -ne 78 -or $bytes[3] -ne 71){ continue }

            $tmp=$destination+'.tmp'
            [System.IO.File]::WriteAllBytes($tmp,$bytes)
            Move-Item -LiteralPath $tmp -Destination $destination -Force
        } catch {
            # Item art is decorative; a failed image fetch must never fail Travel Assistant.
            continue
        }
    }
} finally {
    $client.Dispose()
}
