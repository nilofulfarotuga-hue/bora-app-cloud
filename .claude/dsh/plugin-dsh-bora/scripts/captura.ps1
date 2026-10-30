# Captura o ecrã inteiro (todos os monitores) para um PNG e escreve só o caminho no stdout.
# Código nosso (missão C-liga, 30/10/2026). Não envia nada a lado nenhum: quem envia é a ferramenta ver_imagem.
# Uso: powershell -NoProfile -File captura.ps1 -Saida C:\caminho\captura.png [-LarguraMax 1600]
param([Parameter(Mandatory)][string]$Saida, [int]$LarguraMax = 1600)

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
Add-Type @"
using System; using System.Runtime.InteropServices;
public class DpiCaptura { [DllImport("user32.dll")] public static extern bool SetProcessDPIAware(); }
"@
[void][DpiCaptura]::SetProcessDPIAware()

$v = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap $v.Width, $v.Height
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($v.X, $v.Y, 0, 0, $bmp.Size)
$g.Dispose()

$final = $bmp
if ($bmp.Width -gt $LarguraMax) {
  $h = [int]($bmp.Height * $LarguraMax / $bmp.Width)
  $final = New-Object System.Drawing.Bitmap $LarguraMax, $h
  $g2 = [System.Drawing.Graphics]::FromImage($final)
  $g2.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
  $g2.DrawImage($bmp, 0, 0, $LarguraMax, $h)
  $g2.Dispose()
}
$pasta = Split-Path $Saida -Parent
if ($pasta -and -not (Test-Path $pasta)) { New-Item -ItemType Directory -Force $pasta | Out-Null }
$final.Save($Saida, [System.Drawing.Imaging.ImageFormat]::Png)
if ($final -ne $bmp) { $final.Dispose() }
$bmp.Dispose()
Write-Output $Saida
