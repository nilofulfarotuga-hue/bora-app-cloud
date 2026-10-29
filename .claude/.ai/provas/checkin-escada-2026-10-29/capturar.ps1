# Captura as paragens da prova visual da escada do check-in
# (integration_test/checkin_escada_prova_test.dart) no emulador Android (29/10/2026).
# O teste monta o cartão do check-in com um serviço falso (sem login, sem escrever no banco)
# e anuncia cada paragem no log: "[prova] PRONTO <nome>". Este guião espera pela linha e
# fotografa com screencap.
# Uso: powershell -File capturar.ps1 [-Apk <caminho do app-debug.apk>]
param(
  [string]$Apk = 'C:\BoraLocal\wt-missao-geral-28-10\build\app\outputs\flutter-apk\app-debug.apk'
)
$ErrorActionPreference = 'Continue'
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$saida = Join-Path $aqui 'capturas'
New-Item -ItemType Directory -Force $saida | Out-Null
$pkg = 'pt.boraapp.bora'

& $adb wait-for-device
for ($i = 0; $i -lt 120; $i++) {
  $b = (& $adb shell getprop sys.boot_completed 2>$null) -join ''
  if ($b.Trim() -eq '1') { break }
  Start-Sleep -Seconds 2
}
Write-Output "boot_completed=$b"

& $adb install -r -g $Apk | Select-Object -Last 1
& $adb shell am force-stop $pkg | Out-Null
& $adb logcat -c
& $adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS | Out-Null
& $adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null

$feitos = @{}
$limite = (Get-Date).AddMinutes(8)
while ((Get-Date) -lt $limite) {
  $log = & $adb logcat -d -s flutter:I 2>$null
  foreach ($l in $log) {
    if ($l -match '\[prova\] PRONTO (\S+)') {
      $nome = $Matches[1]
      if (-not $feitos.ContainsKey($nome)) {
        Start-Sleep -Milliseconds 1500
        $png = Join-Path $saida "$nome.png"
        & $adb shell screencap -p /sdcard/prova.png
        & $adb pull /sdcard/prova.png $png | Out-Null
        $feitos[$nome] = $true
        Write-Output "capturado $nome -> $png"
      }
    }
    if ($l -match '\[prova\] (FIM|FALHOU.*)') { Write-Output "log: $($Matches[0])" }
  }
  if ($log -match '\[prova\] (FIM|FALHOU)') { break }
  Start-Sleep -Milliseconds 700
}
Write-Output "total=$($feitos.Count)"
