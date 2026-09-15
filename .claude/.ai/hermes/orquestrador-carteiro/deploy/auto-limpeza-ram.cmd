@echo off
rem auto-limpeza-ram.cmd -- wrapper do auto-limpeza-ram.ps1. Corre NA SESSAO do Danilo
rem (via schtask /RU danil /IT, igual ao heartbeat-desktop). Modo passado como 1o argumento
rem (hook | schtask); default schtask.
setlocal
set REPO=C:\Users\danil\Desktop\projetosflutter\bora_app
set PS1=%REPO%\.claude\.ai\hermes\orquestrador-carteiro\deploy\auto-limpeza-ram.ps1
set MODE=%~1
if "%MODE%"=="" set MODE=schtask
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%" -Mode %MODE%
endlocal
