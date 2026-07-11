@echo off
rem Monitor visual do Bora e2e: 1 janela scrcpy always-on-top por telemovel autorizado
rem + 1 janela cmd com tail (5s) das ultimas 15 linhas de e2e_log.
cd /d "%~dp0"

set PY=C:\Users\danil\Desktop\produtividade-ia\agent-reach-venv\Scripts\python.exe
if not exist "%PY%" set PY=C:\Users\danil\AppData\Local\Programs\Python\Python312\python.exe
if not exist "%PY%" set PY=python

for /f "tokens=1" %%d in ('adb devices ^| findstr /R /C:"device$"') do (
  echo [monitor-bora] a abrir scrcpy para %%d
  start "Bora-%%d" scrcpy -s %%d --window-title "Bora-%%d" --always-on-top
)

echo [monitor-bora] a abrir monitor de e2e_log
start "Bora-e2e-log" cmd /k ""%PY%" tail_e2e_log.py"
