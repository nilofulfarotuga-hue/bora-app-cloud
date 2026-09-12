@echo off
rem instalar-schtask-ponte.cmd - regista ponte-pc-up.cmd para correr no logon do danil
rem e tambem no arranque do sistema (ONSTART, como SYSTEM) para cobrir o caso de
rem ninguem fazer logon interativo. Redundante aos servicos AUTO_START (ver ponte-pc-up.cmd).
rem Reversivel:
rem   schtasks /Delete /TN "Bora-ponte-pc-up-logon" /F
rem   schtasks /Delete /TN "Bora-ponte-pc-up-boot" /F

set WRAP=C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\hermes\ponte-pc\ponte-pc-up.cmd

echo [ponte-pc-up] a registar schtask ONLOGON (danil) ...
schtasks /Create /TN "Bora-ponte-pc-up-logon" /TR "\"%WRAP%\"" /SC ONLOGON /RU danil /F

echo [ponte-pc-up] a registar schtask ONSTART (SYSTEM, cobre boot sem login) ...
schtasks /Create /TN "Bora-ponte-pc-up-boot" /TR "\"%WRAP%\"" /SC ONSTART /RU SYSTEM /RL HIGHEST /F

echo.
echo Feito. Verificar com: schtasks /Query /TN "Bora-ponte-pc-up-logon"
echo                       schtasks /Query /TN "Bora-ponte-pc-up-boot"
echo Forcar 1 ciclo:       schtasks /Run /TN "Bora-ponte-pc-up-logon"
echo Desligar:             schtasks /Delete /TN "Bora-ponte-pc-up-logon" /F
echo                       schtasks /Delete /TN "Bora-ponte-pc-up-boot" /F
