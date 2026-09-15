@echo off
rem fila-vazia-wake.cmd -- chamado pelo carteiro.sh (VPS) via ponte SSH hermes@PC, na
rem transicao ocupado->vazio da fila de orquestracao (2026-07-17, PECA 2). Semeia o
rem pending.trigger do heartbeat-desktop com uma frase curta de revisao e dispara o
rem schtask Bora-heartbeat-desktop (agora "Somente sob demanda", sem horario).
setlocal
set REPO=C:\Users\danil\Desktop\projetosflutter\bora_app
set PY=C:\Users\danil\AppData\Local\Programs\Python\Python312\python.exe
set LOG=%REPO%\.claude\.ai\hermes\heartbeat-desktop\heartbeat-desktop.log

echo [%DATE% %TIME%] fila-vazia-wake: a semear pending.trigger >> "%LOG%"
"%PY%" "%REPO%\.claude\.ai\hermes\heartbeat-desktop\_write_fila_vazia_trigger.py" >> "%LOG%" 2>&1
schtasks /run /tn "Bora-heartbeat-desktop" >> "%LOG%" 2>&1
echo [%DATE% %TIME%] fila-vazia-wake: schtasks /run exit=%ERRORLEVEL% >> "%LOG%"
endlocal
