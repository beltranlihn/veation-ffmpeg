# tools/sde.ps1 - puerta I (FFMPEG-PROPIO.md, 5.6): el binario arranca y trabaja en una CPU SIN AVX2.
# Ejecuta, bajo Intel SDE emulando una CPU antigua (por defecto Sandy Bridge, -snb), las ordenes que
# cubren D1-D3: x264/x265/SVT-AV1 por CPU, HAP con snappy, decodificacion dav1d y VP9 con alfa.
# Una biblioteca estatica compilada con AVX2 fijo mataria ffmpeg.exe con "instruccion ilegal".
# Archivo en ASCII a proposito (PowerShell 5.1 lee los .ps1 como ANSI).
#
#   pwsh tools/sde.ps1 -Sde <carpeta del kit de SDE> -Ffmpeg <ffmpeg.exe> [-Cpu snb]
param(
    [Parameter(Mandatory = $true)][string]$Sde,
    [Parameter(Mandatory = $true)][string]$Ffmpeg,
    [string]$Cpu = 'snb'
)
$ErrorActionPreference = 'Stop'
$sdeExe = Join-Path $Sde 'sde.exe'
if (-not (Test-Path $sdeExe)) { throw "no esta $sdeExe" }
$tmp = Join-Path ([System.IO.Path]::GetTempPath()) ("vf-sde-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $tmp | Out-Null

$pruebas = @(
    @{ id = 'I1'; txt = 'libx264 por CPU'; args = @('-f','lavfi','-i','testsrc2=s=640x360:r=30:d=0.3','-c:v','libx264','-preset','veryfast',(Join-Path $tmp 'a.mp4')) },
    @{ id = 'I2'; txt = 'libx265 10 bits por CPU'; args = @('-f','lavfi','-i','testsrc2=s=640x360:r=30:d=0.3','-c:v','libx265','-preset','ultrafast','-pix_fmt','yuv420p10le',(Join-Path $tmp 'b.mp4')) },
    @{ id = 'I3'; txt = 'SVT-AV1 10 bits'; args = @('-f','lavfi','-i','testsrc2=s=640x360:r=30:d=0.3','-c:v','libsvtav1','-preset','12','-pix_fmt','yuv420p10le',(Join-Path $tmp 'c.mkv')) },
    @{ id = 'I4'; txt = 'decodificar AV1 con dav1d'; args = @('-c:v','libdav1d','-i',(Join-Path $tmp 'c.mkv'),'-f','null','-') },
    @{ id = 'I5'; txt = 'HAP Q con snappy (proxy live)'; args = @('-f','lavfi','-i','testsrc2=s=640x360:r=30:d=0.3','-c:v','hap','-format','hap_q','-compressor','snappy','-chunks','4',(Join-Path $tmp 'd.mov')) },
    @{ id = 'I6'; txt = 'VP9 con alfa (libvpx)'; args = @('-f','lavfi','-i','testsrc2=s=320x240:r=30:d=0.3','-vf','format=yuva420p','-c:v','libvpx-vp9','-pix_fmt','yuva420p',(Join-Path $tmp 'e.webm')) },
    @{ id = 'I7'; txt = 'decodificar VP9 con alfa (libvpx-vp9)'; args = @('-c:v','libvpx-vp9','-i',(Join-Path $tmp 'e.webm'),'-f','null','-') },
    @{ id = 'I8'; txt = 'zscale + tonemap (zimg)'; args = @('-f','lavfi','-i','testsrc2=s=320x240:r=30:d=0.2','-vf','format=yuv420p10le,setparams=colorspace=bt2020nc:color_primaries=bt2020:color_trc=smpte2084:range=tv,zscale=t=linear:npl=100,format=gbrpf32le,zscale=p=bt709,tonemap=hable:desat=0,zscale=t=bt709:m=bt709:r=tv,format=yuv420p','-f','null','-') }
)

$fallos = 0
foreach ($p in $pruebas) {
    $todo = @("-$Cpu", '--', $Ffmpeg, '-hide_banner', '-nostdin', '-y', '-loglevel', 'error') + $p.args
    & $sdeExe @todo 2>&1 | Out-String | Set-Variable salida
    if ($LASTEXITCODE -eq 0) { "OK      $($p.id)  $($p.txt) (SDE -$Cpu)" }
    else { "FALLO   $($p.id)  $($p.txt) (SDE -$Cpu) codigo $LASTEXITCODE`n$salida"; $fallos++ }
}
Remove-Item -Recurse -Force $tmp
if ($fallos -gt 0) { Write-Error "puerta I: $fallos prueba(s) fallan sin AVX2"; exit 1 }
"puerta I: todo en verde sin AVX2 (-$Cpu)"
