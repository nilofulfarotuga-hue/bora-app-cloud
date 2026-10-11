# Captura as paragens da prova visual do cartão da corrida do motorista por
# fases (integration_test/tvde_corrida_fases_prova_test.dart) no emulador
# Android (11/10/2026). Molde: .claude/.ai/provas/reservas-num-so-sitio-2026-10-10/capturar.ps1
# Uso: powershell -File capturar.ps1 [-Apk <caminho>] [-Modo tres_botoes|gestos]
param(
  [string]$Apk = 'C:\BoraLocal\projetosflutter\bora_app\build\app\outputs\flutter-apk\app-debug.apk',
  [string]$Modo = 'tres_botoes'
)
$ErrorActionPreference = 'Continue'
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$saida = Join-Path $aqui "capturas_android_$Modo"
New-Item -ItemType Directory -Force $saida | Out-Null
$pkg = 'pt.boraapp.bora'

& $adb wait-for-device
for ($i = 0; $i -lt 150; $i++) {
  $b = (& $adb shell getprop sys.boot_completed 2>$null) -join ''
  if ($b.Trim() -eq '1') { break }
  Start-Sleep -Seconds 2
}
Write-Output "boot_completed=$b"
# AVD limpo fica no assistente de configuração e fecha a app.
& $adb shell settings put secure user_setup_complete 1 | Out-Null
& $adb shell settings put global device_provisioned 1 | Out-Null
if ($Modo -eq 'gestos') {
  & $adb shell cmd overlay enable-exclusive --category com.android.internal.systemui.navbar.gestural | Out-Null
} else {
  & $adb shell cmd overlay enable-exclusive --category com.android.internal.systemui.navbar.threebutton | Out-Null
}
# GPS do emulador na Guarda, perto da recolha de exemplo.
& $adb emu geo fix -7.2702 40.5349 | Out-Null

& $adb install -r -g $Apk | Select-Object -Last 1
& $adb shell am force-stop $pkg | Out-Null
& $adb logcat -c
& $adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null

$feitos = @{}
$limite = (Get-Date).AddMinutes(10)
while ((Get-Date) -lt $limite) {
  $log = & $adb logcat -d -s flutter:I 2>$null
  foreach ($l in $log) {
    if ($l -match '\[prova\] PRONTO (\S+)') {
      $nome = $Matches[1]
      if (-not $feitos.ContainsKey($nome)) {
        Start-Sleep -Milliseconds 1500
        # Fecha um "não responde" do sistema (emulador lento a traduzir ARM).
        & $adb shell am broadcast -a android.intent.action.CLOSE_SYSTEM_DIALOGS | Out-Null
        Start-Sleep -Milliseconds 800
        $png = Join-Path $saida "$nome.png"
        & $adb shell rm -f /sdcard/prova.png | Out-Null
        & $adb shell screencap -p /sdcard/prova.png
        & $adb pull /sdcard/prova.png $png | Out-Null
        $feitos[$nome] = $true
        Write-Output "capturado $nome -> $png"
      }
    }
  }
  if ($log -match '\[prova\] FIM') { Write-Output 'log: [prova] FIM'; break }
  Start-Sleep -Milliseconds 700
}
& $adb logcat -d -s flutter:I | Select-String -Pattern '\[prova\] TAMANHO' | ForEach-Object { $_.Line }
& $adb logcat -d -s flutter:I | Select-String -Pattern 'EXCEPTION|overflow|Another exception' | Select-Object -First 10
Write-Output "total=$($feitos.Count)"
