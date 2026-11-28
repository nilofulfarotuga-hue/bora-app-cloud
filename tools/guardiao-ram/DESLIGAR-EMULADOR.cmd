@echo off
rem DESLIGAR-EMULADOR.cmd - missao pc-sem-travar 2026-11-28.
rem Desliga o emulador (guarda o snapshot para o proximo arranque ser rapido)
rem e para os daemons do Gradle e do Kotlin que ficam a ocupar RAM depois de um build.
set "SDK=%LOCALAPPDATA%\Android\Sdk"
"%SDK%\platform-tools\adb.exe" devices | findstr /R "emulator-[0-9]*" >nul
if %errorlevel%==0 (
  echo A desligar o emulador ...
  for /f "tokens=1" %%d in ('"%SDK%\platform-tools\adb.exe" devices ^| findstr /R "^emulator-"') do "%SDK%\platform-tools\adb.exe" -s %%d emu kill
) else (
  echo O emulador ja estava desligado.
)
if exist "C:\BoraLocal\projetosflutter\bora_app\android\gradlew.bat" (
  pushd "C:\BoraLocal\projetosflutter\bora_app\android"
  call gradlew.bat --stop >nul 2>&1
  popd
)
powershell -NoProfile -Command "Get-CimInstance Win32_Process -Filter \"Name='java.exe'\" | Where-Object { $_.CommandLine -match 'KotlinCompileDaemon|GradleDaemon' } | ForEach-Object { Stop-Process -Id $_.ProcessId -Force }"
echo Feito.
