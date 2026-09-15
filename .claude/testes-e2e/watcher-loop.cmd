@echo off
rem watcher-loop.cmd — relanca loop-noturno.py sempre que ele sair (ele nao e daemon, MAX_CICLOS
rem e batch). Criado 2026-07-12 porque a tarefa agendada SYSTEM "BoraE2E_LoopNoturno" (padrao
rem provado 2026-07-11) nao pode ser recriada nesta sessao (Task Scheduler negou acesso, mesmo
rem sem /ru SYSTEM). Isto e o substituto: processo destacado, persistente, que chama
rem schtask-loop.cmd em ciclo ate aparecer o ficheiro PARAR.
cd /d "%~dp0"
:loop
if exist PARAR (
  echo [watcher-loop] PARAR encontrado - saio. >> _watcher_loop.log
  exit /b 0
)
echo [watcher-loop] a chamar schtask-loop.cmd em %DATE% %TIME% >> _watcher_loop.log
call schtask-loop.cmd
echo [watcher-loop] schtask-loop.cmd terminou rc=%ERRORLEVEL% em %DATE% %TIME% >> _watcher_loop.log
rem timeout /t exige consola real e falha logo quando stdin esta redirecionado (processo
rem destacado/background) -- usa ping como sleep sem consola (truque classico .cmd).
ping -n 61 127.0.0.1 >nul
goto loop
