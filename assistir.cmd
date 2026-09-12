@echo off
chcp 65001 >NUL
REM assistir.cmd -- acompanha AO VIVO o executor do loop de orquestracao.
REM FASE 1.4 da reengenharia da esteira (2026-07-12). Uma linha por acao do executor.
set "LIVELOG=%~dp0.claude\bora-live.log"
if not exist "%LIVELOG%" type nul > "%LIVELOG%"
echo A acompanhar o executor do loop AO VIVO. Ctrl+C para sair.
echo Ficheiro: %LIVELOG%
echo.
powershell -NoProfile -Command "Get-Content -Wait -Tail 40 -LiteralPath '%LIVELOG%'"
