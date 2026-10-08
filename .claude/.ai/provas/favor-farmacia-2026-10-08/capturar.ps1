# Captura as paragens da prova visual (integration_test/favor_ecras_prova_test.dart)
# no emulador, com a barra do sistema por cima da app (08/10/2026).
# Uso: powershell -File capturar.ps1 -Modo tres_botoes|gestos
param(
  [Parameter(Mandatory = $true)][ValidateSet('tres_botoes', 'gestos')] [string]$Modo,
  [string]$Apk = 'C:\BoraLocal\projetosflutter\bora_app\build\app\outputs\flutter-apk\app-debug.apk'
)
$ErrorActionPreference = 'Continue'
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$saida = Join-Path $aqui "capturas_$Modo"
New-Item -ItemType Directory -Force $saida | Out-Null
$pkg = 'pt.boraapp.bora'

& $adb wait-for-device
for ($i = 0; $i -lt 90; $i++) {
  $b = (& $adb shell getprop sys.boot_completed 2>$null) -join ''
  if ($b.Trim() -eq '1') { break }
  Start-Sleep -Seconds 2
}
Write-Output "boot_completed=$b"

if ($Modo -eq 'tres_botoes') {
  & $adb shell cmd overlay enable-exclusive --category com.android.internal.systemui.navbar.threebutton | Out-Null
} else {
  & $adb shell cmd overlay enable-exclusive --category com.android.internal.systemui.navbar.gestural | Out-Null
}
Start-Sleep -Seconds 3
Write-Output ("overlays: " + ((& $adb shell cmd overlay list | Select-String 'navbar' | Select-String '\[x\]') -join ' | '))

& $adb install -r -g $Apk | Select-Object -Last 1
& $adb shell mkdir -p "/sdcard/Android/data/$pkg/files" | Out-Null
& $adb push (Join-Path $aqui 'receita_teste.png') "/sdcard/Android/data/$pkg/files/receita_teste.png" | Select-Object -Last 1
& $adb shell am force-stop $pkg | Out-Null
& $adb logcat -c
& $adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null

$feitos = @{}
$limite = (Get-Date).AddMinutes(6)
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
    if ($l -match '\[prova\] (FIM|SEM .*)') { Write-Output "log: $($Matches[0])" }
  }
  if ($log -match '\[prova\] FIM') { break }
  Start-Sleep -Milliseconds 700
}
Write-Output "total=$($feitos.Count)"
