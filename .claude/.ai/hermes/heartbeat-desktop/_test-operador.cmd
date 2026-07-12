@echo off
rem _test-operador.cmd — corre SO o operador desktop (Peca 2) e regista stdout. Para o teste
rem unico ao vivo na sessao do Danilo (via schtask /RU danil /IT). Nao corre o detetor.
set PY=C:\Users\danil\AppData\Local\Programs\Python\Python312\python.exe
set OP=C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\hermes\heartbeat-desktop\desktop-send.py
set LOG=C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\hermes\heartbeat-desktop\_test-operador.log
echo [test %DATE% %TIME%] a correr operador desktop... > "%LOG%"
"%PY%" "%OP%" >> "%LOG%" 2>&1
echo [test] exit=%ERRORLEVEL% >> "%LOG%"
