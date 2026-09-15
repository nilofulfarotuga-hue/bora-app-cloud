@echo off
rem instalar-schtask.cmd — regista o gatilho heartbeat-browser como cron PC-side */10 min.
rem Corre o detetor anti-spam; so escreve pending.trigger quando ha mudanca real de estado.
rem O browser-operador (Claude in Chrome) le pending.trigger e abre o chat no claude.ai.
rem
rem Reversivel: schtasks /Delete /TN "Bora-heartbeat-browser" /F  (desliga tudo).

set REPO=C:\Users\danil\Desktop\projetosflutter\bora_app
rem python nao esta no PATH -> caminho completo do interpretador do perfil do Danilo.
set PY=C:\Users\danil\AppData\Local\Programs\Python\Python312\python.exe
set SCRIPT=%REPO%\.claude\scripts\heartbeat-browser.py

echo [heartbeat-browser] a registar schtask */10 ...
schtasks /Create /TN "Bora-heartbeat-browser" ^
  /TR "\"%PY%\" \"%SCRIPT%\"" ^
  /SC MINUTE /MO 10 /F

echo.
echo Feito. Verificar:  schtasks /Query /TN "Bora-heartbeat-browser"
echo Testar deteccao:   %PY% "%SCRIPT%" --dry
echo Forcar 1 trigger:  %PY% "%SCRIPT%" --force
echo Desligar:          schtasks /Delete /TN "Bora-heartbeat-browser" /F
