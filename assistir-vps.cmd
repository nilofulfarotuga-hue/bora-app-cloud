@echo off
chcp 65001 >NUL
REM assistir-vps.cmd -- acompanha AO VIVO o orquestrador (carteiro.sh) NA VPS.
REM Janela de visibilidade VPS (2026-07-14). Complementa o assistir.cmd (esse mostra
REM o Claude a trabalhar passo a passo NESTA maquina); este mostra o carteiro.sh na
REM VPS: ordens a entrar/sair da fila, tentativas, veredito do Juiz, rc, notificacoes.
REM Religa sozinho se a ligacao SSH cair (rede instavel, VPS a reiniciar, etc.).
setlocal
set "SSHEXE=C:\Program Files\Git\usr\bin\ssh.exe"
if not exist "%SSHEXE%" set "SSHEXE=ssh"
set "KEY=C:\Users\danil\.ssh\id_ed25519_vps"
set "VPS=root@srv1786862.hstgr.cloud"
set "REMLOG=/root/orquestracao/carteiro.log"

echo A acompanhar o orquestrador (carteiro.sh) AO VIVO na VPS. Ctrl+C para sair.
echo Ligacao: %VPS%   Log: %REMLOG%
echo.

:loop
"%SSHEXE%" -i "%KEY%" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=15 -o ServerAliveInterval=25 -o ServerAliveCountMax=3 %VPS% "tail -n 60 -f %REMLOG%"
echo.
echo [ligacao caiu - a tentar de novo em 3s... Ctrl+C para sair]
timeout /t 3 /nobreak >NUL
goto loop
