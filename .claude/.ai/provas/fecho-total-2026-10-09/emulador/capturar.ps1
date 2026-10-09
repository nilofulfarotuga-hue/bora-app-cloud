# Prova no emulador Android 15 (AVD emdia35) — missão fecho-total-2026-10-09.
# Teste: integration_test/fecho_total_prova_test.dart (sem login, sem servidor).
# Encurta por adb o limite de 6 h do serviço dataSync do Android 15 para $TimeoutMs,
# para ver o que acontece ao serviço do estafeta quando o limite chega.
# Uso: powershell -File capturar.ps1 [-TimeoutMs 120000] [-Minutos 8]
param(
  [string]$Apk = 'C:\BoraLocal\projetosflutter\bora_app\build\app\outputs\flutter-apk\app-debug.apk',
  [int]$TimeoutMs = 120000,
  [int]$Minutos = 12
)
$ErrorActionPreference = 'Continue'
$adb = "$env:LOCALAPPDATA\Android\Sdk\platform-tools\adb.exe"
$aqui = Split-Path -Parent $MyInvocation.MyCommand.Path
$saida = Join-Path $aqui 'capturas'
New-Item -ItemType Directory -Force $saida | Out-Null
$pkg = 'pt.boraapp.bora'
$logFile = Join-Path $aqui 'logcat_completo.txt'

& $adb wait-for-device
for ($i = 0; $i -lt 120; $i++) {
  $b = (& $adb shell getprop sys.boot_completed 2>$null) -join ''
  if ($b.Trim() -eq '1') { break }
  Start-Sleep -Seconds 2
}
Write-Output "boot_completed=$b  android=$((& $adb shell getprop ro.build.version.release) -join '')  sdk=$((& $adb shell getprop ro.build.version.sdk) -join '')"

& $adb shell settings put secure user_setup_complete 1 | Out-Null
& $adb shell settings put global device_provisioned 1 | Out-Null
& $adb shell cmd overlay enable-exclusive --category com.android.internal.systemui.navbar.threebutton | Out-Null

& $adb install -r -g $Apk | Select-Object -Last 1
& $adb shell pm grant $pkg android.permission.POST_NOTIFICATIONS 2>$null
& $adb shell appops set $pkg USE_FULL_SCREEN_INTENT allow 2>$null
# Android 15: limite do serviço dataSync encurtado (o normal são 6 h por dia).
& $adb shell am compat enable FGS_INTRODUCE_TIME_LIMITS $pkg | Select-Object -Last 1
& $adb shell device_config put activity_manager data_sync_fgs_timeout_duration $TimeoutMs | Out-Null
Write-Output ("data_sync_fgs_timeout_duration=" + ((& $adb shell device_config get activity_manager data_sync_fgs_timeout_duration) -join ''))
Write-Output ("targetSdk=" + ((& $adb shell dumpsys package $pkg | Select-String 'targetSdk' | Select-Object -First 1) -join ''))

& $adb shell am force-stop $pkg | Out-Null
& $adb logcat -c
$logJob = Start-Process -FilePath $adb -ArgumentList @('logcat', '-v', 'time') -RedirectStandardOutput $logFile -NoNewWindow -PassThru
& $adb shell monkey -p $pkg -c android.intent.category.LAUNCHER 1 | Out-Null
$inicio = Get-Date

$feitos = @{}
$limite = (Get-Date).AddMinutes($Minutos)
$fim = $false
while ((Get-Date) -lt $limite -and -not $fim) {
  $log = & $adb logcat -d -s flutter:I 2>$null
  foreach ($l in $log) {
    if ($l -match '\[prova\] PRONTO (\S+)') {
      $nome = $Matches[1]
      if (-not $feitos.ContainsKey($nome)) {
        if ($nome -like '*aviso*' -or $nome -like '*servico*') {
          & $adb shell cmd statusbar expand-notifications | Out-Null
          Start-Sleep -Milliseconds 1500
        } else {
          Start-Sleep -Milliseconds 1500
        }
        $png = Join-Path $saida "$nome.png"
        & $adb shell screencap -p /sdcard/prova.png
        & $adb pull /sdcard/prova.png $png | Out-Null
        & $adb shell cmd statusbar collapse | Out-Null
        $feitos[$nome] = $true
        Write-Output ("{0:mm\:ss} capturado {1}" -f ((Get-Date) - $inicio), $nome)
      }
    }
    if ($l -match '\[prova\] (FIM|FGS .*)') { $script:ultimo = $Matches[0] }
    if ($l -match '\[prova\] FIM') { $fim = $true }
  }
  $vivo = ((& $adb shell pidof $pkg) -join '').Trim()
  if (-not $vivo -and $feitos.Count -gt 0) { Write-Output "PROCESSO DA APP MORREU aos $((Get-Date) - $inicio)"; break }
  Start-Sleep -Seconds 2
}
Start-Sleep -Seconds 3
Stop-Process -Id $logJob.Id -ErrorAction SilentlyContinue
Write-Output "total_capturas=$($feitos.Count) ultimo=$script:ultimo"
Write-Output '--- linhas do Android 15 sobre o serviço / falhas ---'
Select-String -Path $logFile -Pattern 'onTimeout|DidNotStopInTime|timed out|FATAL EXCEPTION|ForegroundService.*(time|limit)|\[prova\] FGS|AndroidRuntime' |
  Select-Object -First 40 | ForEach-Object { $_.Line }
& $adb shell device_config delete activity_manager data_sync_fgs_timeout_duration | Out-Null
