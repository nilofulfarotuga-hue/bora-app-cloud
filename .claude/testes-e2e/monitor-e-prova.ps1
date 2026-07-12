# monitor-e-prova.ps1
# Corre DENTRO da sessao interativa do Danilo (session 1) via Tarefa Agendada /ru danil /it.
# 1) lanca 1 janela scrcpy always-on-top por telemovel autorizado + 1 janela tail do e2e_log
# 2) espera as janelas desenharem, traz para a frente
# 3) tira screenshot do ECRA DO PC (nao do telemovel) -> screenshots-pc/monitor-confirmado.png
# Idempotente: nao abre scrcpy duplicado se ja houver processo vivo.
$ErrorActionPreference = 'SilentlyContinue'
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $base

# --- resolver binarios (nao dependem do PATH) ---
$adb = "C:\Users\danil\AppData\Local\Android\Sdk\platform-tools\adb.exe"
$scrcpy = "C:\Users\danil\AppData\Local\Microsoft\WinGet\Packages\Genymobile.scrcpy_Microsoft.Winget.Source_8wekyb3d8bbwe\scrcpy-win64-v4.0\scrcpy.exe"
if (-not (Test-Path $scrcpy)) {
  $cand = Get-ChildItem "C:\Users\danil\AppData\Local\Microsoft\WinGet\Packages" -Filter scrcpy.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cand) { $scrcpy = $cand.FullName }
}
$env:ADB = $adb
$py = "C:\Users\danil\AppData\Local\Programs\Python\Python312\python.exe"
if (-not (Test-Path $py)) { $py = "python" }

$log = Join-Path $base "_monitor_prova.log"
"[monitor-e-prova] arranque $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" | Out-File $log -Encoding utf8
"whoami: $(whoami)" | Out-File $log -Append -Encoding utf8
"scrcpy: $scrcpy (existe=$(Test-Path $scrcpy))" | Out-File $log -Append -Encoding utf8

# --- devices autorizados ---
$devs = & $adb devices | Select-String "device$" | ForEach-Object { ($_ -split "\s+")[0] } | Where-Object { $_ -and $_ -ne "List" }
"devices autorizados: $($devs -join ', ')" | Out-File $log -Append -Encoding utf8

# --- lancar scrcpy por device (idempotente: nao empilha se ja houver janela viva) ---
if (Test-Path $scrcpy) {
  $jaVivos = (Get-Process scrcpy -ErrorAction SilentlyContinue).Count
  if ($jaVivos -gt 0) {
    "scrcpy ja tinha $jaVivos janela(s) viva(s) — nao relanco" | Out-File $log -Append -Encoding utf8
  } else {
    foreach ($d in $devs) {
      $title = "Bora-$d"
      Start-Process -FilePath $scrcpy -ArgumentList @('-s', $d, '--window-title', $title, '--always-on-top') -WorkingDirectory (Split-Path $scrcpy)
      "scrcpy lancado para $d" | Out-File $log -Append -Encoding utf8
    }
  }
} else {
  "ERRO: scrcpy.exe nao encontrado" | Out-File $log -Append -Encoding utf8
}

# --- janela de tail do e2e_log ---
Start-Process -FilePath "cmd.exe" -ArgumentList @('/k', "`"$py`" tail_e2e_log.py") -WorkingDirectory $base
"tail e2e_log lancado" | Out-File $log -Append -Encoding utf8

# --- esperar as janelas desenharem e trazer para a frente ---
Start-Sleep -Seconds 8
Add-Type @"
using System;
using System.Runtime.InteropServices;
public class Win {
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int c);
}
"@
Get-Process scrcpy -ErrorAction SilentlyContinue | ForEach-Object {
  if ($_.MainWindowHandle -ne 0) { [Win]::ShowWindow($_.MainWindowHandle, 5) | Out-Null; [Win]::SetForegroundWindow($_.MainWindowHandle) | Out-Null }
}
Start-Sleep -Seconds 2

# --- screenshot do ECRA DO PC ---
Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
$screens = [System.Windows.Forms.SystemInformation]::VirtualScreen
$bmp = New-Object System.Drawing.Bitmap($screens.Width, $screens.Height)
$g = [System.Drawing.Graphics]::FromImage($bmp)
$g.CopyFromScreen($screens.Left, $screens.Top, 0, 0, $bmp.Size)
$outDir = Join-Path $base "screenshots-pc"
if (-not (Test-Path $outDir)) { New-Item -ItemType Directory -Force $outDir | Out-Null }
$out = Join-Path $outDir "monitor-confirmado.png"
$bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
$g.Dispose(); $bmp.Dispose()

$alive = (Get-Process scrcpy -ErrorAction SilentlyContinue).Count
"scrcpy vivos apos lancar: $alive" | Out-File $log -Append -Encoding utf8
"screenshot guardado: $out (existe=$(Test-Path $out))" | Out-File $log -Append -Encoding utf8
"[monitor-e-prova] fim $(Get-Date -Format 'HH:mm:ss')" | Out-File $log -Append -Encoding utf8
