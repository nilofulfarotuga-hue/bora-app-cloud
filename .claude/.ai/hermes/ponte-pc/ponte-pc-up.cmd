@echo off
rem ponte-pc-up.cmd - rede de seguranca redundante da ponte Hermes<->PC.
rem Os servicos Windows "sshd" e "Tailscale" ja sao AUTO_START (arrancam no boot,
rem antes do login) - esta tarefa e so um cinto-e-suspensorios: corre no logon,
rem confirma que os 2 servicos estao Running e forca "tailscale up" (idempotente,
rem nao faz nada se ja estiver ligado). Nunca para nada, so verifica/reforca.
rem Reversivel: schtasks /Delete /TN "Bora-ponte-pc-up" /F

set LOG=%~dp0ponte-pc-up.log
echo [%date% %time%] ponte-pc-up: a verificar... >> "%LOG%"

sc query sshd | find "RUNNING" >nul
if errorlevel 1 (
  echo [%date% %time%] sshd nao estava Running - a arrancar... >> "%LOG%"
  net start sshd >> "%LOG%" 2>&1
) else (
  echo [%date% %time%] sshd OK (Running). >> "%LOG%"
)

sc query Tailscale | find "RUNNING" >nul
if errorlevel 1 (
  echo [%date% %time%] Tailscale service nao estava Running - a arrancar... >> "%LOG%"
  net start Tailscale >> "%LOG%" 2>&1
) else (
  echo [%date% %time%] Tailscale service OK (Running). >> "%LOG%"
)

"C:\Program Files\Tailscale\tailscale.exe" up --hostname=laptop-2q09vqa1 >> "%LOG%" 2>&1

echo [%date% %time%] ponte-pc-up: verificacao concluida. >> "%LOG%"
