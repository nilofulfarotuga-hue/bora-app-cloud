@echo off
rem run-heartbeat-desktop.cmd — 1 ciclo do heartbeat-DESKTOP. Corre NA SESSAO do Danilo
rem (via schtask /RU danil /IT). Peca 1 (detetor, headless-safe) escreve pending.trigger so
rem em mudanca real; Peca 2 (operador desktop) age no trigger conduzindo o app Claude (PWA).
setlocal
set REPO=C:\Users\danil\Desktop\projetosflutter\bora_app
set PY=C:\Users\danil\AppData\Local\Programs\Python\Python312\python.exe
set DET=%REPO%\.claude\scripts\heartbeat-browser.py
set OP=%REPO%\.claude\.ai\hermes\heartbeat-desktop\desktop-send.py
set LOG=%REPO%\.claude\.ai\hermes\heartbeat-desktop\heartbeat-desktop.log

echo [%DATE% %TIME%] --- ciclo heartbeat-desktop --- >> "%LOG%"
if exist "%DET%" ("%PY%" "%DET%" >> "%LOG%" 2>&1) else (echo detetor ausente, salto Peca 1 >> "%LOG%")
"%PY%" "%OP%" >> "%LOG%" 2>&1
echo [%DATE% %TIME%] exit=%ERRORLEVEL% >> "%LOG%"
endlocal
