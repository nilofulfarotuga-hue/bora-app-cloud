@echo off
rem LIGAR-EMULADOR.cmd - missao pc-sem-travar 2026-11-28.
rem Liga o emulador Android so quando e preciso (arranque rapido pelo snapshot).
rem Uso: LIGAR-EMULADOR.cmd            -> liga o emdia35 (Android 35, o mais recente)
rem      LIGAR-EMULADOR.cmd emdia      -> liga o emdia (Android 34)
rem No fim da missao: DESLIGAR-EMULADOR.cmd (devolve ~2,5 GB de RAM).
set "SDK=%LOCALAPPDATA%\Android\Sdk"
set "AVD=%~1"
if "%AVD%"=="" set "AVD=emdia35"
"%SDK%\platform-tools\adb.exe" devices | findstr /R "emulator-[0-9]*" >nul
if %errorlevel%==0 (
  echo O emulador ja esta ligado.
  goto :eof
)
echo A ligar o emulador %AVD% ...
start "" /B "%SDK%\emulator\emulator.exe" -avd %AVD% -no-boot-anim -memory 2048
"%SDK%\platform-tools\adb.exe" wait-for-device
echo Ligado. Quando acabares: DESLIGAR-EMULADOR.cmd
