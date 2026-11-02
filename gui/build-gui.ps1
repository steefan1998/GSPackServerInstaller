# Builds GSPackInstaller.exe (the Windows GUI) next to the scripts.
# Uses the C# compiler that ships with Windows (.NET Framework 4), nothing to install.
#   powershell -ExecutionPolicy Bypass -File gui\build-gui.ps1
$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.Drawing
$root = Split-Path $PSScriptRoot -Parent

$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw 'C# compiler (.NET Framework 4) not found' }

# Program icon from the pack logo: a PNG stored in an .ico (Windows Vista+)
$logo = Join-Path $PSScriptRoot 'logo.png'
$ico = Join-Path $PSScriptRoot 'GSPack.ico'
$src = [Drawing.Image]::FromFile($logo)
$bmp = New-Object Drawing.Bitmap 256, 256
$g = [Drawing.Graphics]::FromImage($bmp)
$g.InterpolationMode = 'NearestNeighbor'; $g.PixelOffsetMode = 'Half'
$g.DrawImage($src, 0, 0, 256, 256); $g.Dispose(); $src.Dispose()
$ms = New-Object IO.MemoryStream
$bmp.Save($ms, [Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
$png = $ms.ToArray()
$fs = [IO.File]::Create($ico)
$w = New-Object IO.BinaryWriter $fs
$w.Write([uint16]0); $w.Write([uint16]1); $w.Write([uint16]1)          # header: icon, 1 image
$w.Write([byte]0); $w.Write([byte]0); $w.Write([byte]0); $w.Write([byte]0)  # 256x256, no palette
$w.Write([uint16]1); $w.Write([uint16]32); $w.Write([uint32]$png.Length); $w.Write([uint32]22)
$w.Write($png); $w.Close()

$out = Join-Path $root 'GSPackInstaller.exe'
& $csc /nologo /target:winexe /optimize+ "/out:$out" "/win32icon:$ico" `
    /r:System.Windows.Forms.dll /r:System.Drawing.dll /r:System.Web.Extensions.dll `
    (Join-Path $PSScriptRoot 'GSPackInstaller.cs')
if ($LASTEXITCODE -ne 0) { throw "Compile failed (exit $LASTEXITCODE)" }
Write-Host "Built $out" -ForegroundColor Green
