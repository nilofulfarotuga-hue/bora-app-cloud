@echo off
rem Monitor visual do Bora e2e: 1 janela scrcpy always-on-top por telemovel autorizado
rem + 1 janela cmd com tail (5s) das ultimas 15 linhas de e2e_log.
cd /d "%~dp0"

set PY=C:\Users\danil\Desktop\produtividade-ia\agent-reach-venv\Scripts\python.exe
if not exist "%PY%" set PY=C:\Users\danil\AppData\Local\Programs\Python\Python312\python.exe
if not exist "%PY%" set PY=python

rem scrcpy nao esta no PATH neste PC (instalado via WinGet). Resolver o .exe primeiro
rem senao 'scrcpy' falha em silencio e NENHUMA janela abre.
set "SCRCPY=scrcpy"
set "SC_WINGET=C:\Users\danil\AppData\Local\Microsoft\WinGet\Packages\Genymobile.scrcpy_Microsoft.Winget.Source_8wekyb3d8bbwe\scrcpy-win64-v4.0\scrcpy.exe"
where scrcpy >nul 2>&1 || if exist "%SC_WINGET%" set "SCRCPY=%SC_WINGET%"
rem usar o adb do SDK para evitar mismatch de versao com o adb embutido do scrcpy
set "ADB=C:\Users\danil\AppData\Local\Android\Sdk\platform-tools\adb.exe"

for /f "tokens=1" %%d in ('adb devices ^| findstr /R /C:"device$"') do (
  echo [monitor-bora] a abrir scrcpy para %%d
  start "Bora-%%d" "%SCRCPY%" -s %%d --window-title "Bora-%%d" --always-on-top
)

echo [monitor-bora] a abrir monitor de e2e_log
start "Bora-e2e-log" cmd /k ""%PY%" tail_e2e_log.py"
