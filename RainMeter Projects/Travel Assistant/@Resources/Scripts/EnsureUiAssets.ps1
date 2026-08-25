param([switch]$SkipMain)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version 2.0

$ProjectRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
$GeneratedDir = Join-Path $ProjectRoot '@Resources\Generated'
$InfoIconFile = Join-Path $GeneratedDir 'info-icon.png'

function Write-InfoIconPng {
    param([string]$Path)
    Add-Type -AssemblyName System.Drawing
    New-Item -ItemType Directory -Force -Path (Split-Path $Path -Parent) | Out-Null
    $bitmap = New-Object System.Drawing.Bitmap 64,64,[System.Drawing.Imaging.PixelFormat]::Format32bppArgb
    $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
    $blue = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,82,174,255))
    $white = New-Object System.Drawing.SolidBrush ([System.Drawing.Color]::FromArgb(255,255,255,255))
    $border = New-Object System.Drawing.Pen ([System.Drawing.Color]::FromArgb(255,45,105,190)),3
    try {
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.Clear([System.Drawing.Color]::Transparent)
        $graphics.FillEllipse($blue,3,3,58,58)
        $graphics.DrawEllipse($border,4,4,56,56)
        # Draw the information mark geometrically so this asset has no font or
        # encoding dependency on the target Windows installation.
        $graphics.FillEllipse($white,29,14,7,7)
        $graphics.FillRectangle($white,29,26,7,24)
        $tmp = $Path + '.tmp.png'
        $bitmap.Save($tmp,[System.Drawing.Imaging.ImageFormat]::Png)
        Move-Item -LiteralPath $tmp -Destination $Path -Force
    } finally {
        $border.Dispose()
        $white.Dispose()
        $blue.Dispose()
        $graphics.Dispose()
        $bitmap.Dispose()
    }
}

if ($SkipMain) { return }
if (-not (Test-Path -LiteralPath $InfoIconFile)) { Write-InfoIconPng -Path $InfoIconFile }
exit 0
