@echo off
rem instalar-schtask-pc-knowledge-sync.cmd — regista o loop de sync do Cortex (PC->VPS,
rem pc-knowledge-sync-loop.sh, polling ~8s) como processo persistente da sessao do danil.
rem Mesmo padrao das outras pontes (ver ponte-pc/, push-bridge/): ONLOGON (sessao) + ONSTART
rem (SYSTEM, cobre boot sem login interativo). O proprio loop tem lock de instancia unica,
rem por isso disparar as 2 triggers nao cria 2 processos a competir.
rem Reversivel:
rem   schtasks /Delete /TN "Bora-cortex-pc-sync-logon" /F
rem   schtasks /Delete /TN "Bora-cortex-pc-sync-boot" /F

set BASH=C:\Program Files\Git\usr\bin\bash.exe
set LOOP=C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\cortex-mcp\pc-knowledge-sync-loop.sh

echo [cortex-pc-sync] a registar schtask ONLOGON (danil) ...
schtasks /Create /TN "Bora-cortex-pc-sync-logon" ^
  /TR "\"%BASH%\" \"%LOOP%\"" /SC ONLOGON /RU danil /F

echo [cortex-pc-sync] a registar schtask ONSTART (SYSTEM, cobre boot sem login) ...
schtasks /Create /TN "Bora-cortex-pc-sync-boot" ^
  /TR "\"%BASH%\" \"%LOOP%\"" /SC ONSTART /RU SYSTEM /RL HIGHEST /F

echo.
echo Feito. Verificar:     schtasks /Query /TN "Bora-cortex-pc-sync-logon"
echo Forcar arranque:      schtasks /Run /TN "Bora-cortex-pc-sync-logon"
echo Log do loop:          .claude\.ai\cortex-mcp\pc-knowledge-sync.log
echo Desligar:              schtasks /Delete /TN "Bora-cortex-pc-sync-logon" /F
echo                        schtasks /Delete /TN "Bora-cortex-pc-sync-boot" /F
