@echo off
rem _setup-deps.cmd — instala as dependencias de automacao de desktop no Python do Danilo.
rem Correr uma vez (via schtask /RU danil ou duplo-clique). Reversivel: pip uninstall.
set PY=C:\Users\danil\AppData\Local\Programs\Python\Python312\python.exe
set HBD=C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\hermes\heartbeat-desktop
set LOG=%HBD%\_setup-deps.log
rem TMP estavel (o TEMP da schtask e' volatil e rebentou o build-tracker do pip)
set TMP=%HBD%\_tmp
set TEMP=%HBD%\_tmp
if not exist "%TMP%" mkdir "%TMP%"
echo [setup] a instalar pyautogui pygetwindow pyperclip pillow ... > "%LOG%"
"%PY%" -m pip install --disable-pip-version-check --no-cache-dir pyautogui pygetwindow pyperclip pillow >> "%LOG%" 2>&1
echo [setup] exit=%ERRORLEVEL% >> "%LOG%"
