@echo off
REM ===========================================================================
REM  LOGIN DA PONTE  ::  corre ISTO UMA VEZ (como danil) para autenticar.
REM  Abre o Claude Code interactivo no MESMO config-dir que a ponte usa,
REM  para o token e o "trust" ficarem no sitio certo (C:\Users\danil\.claude).
REM
REM  Passos quando abrir:
REM    1) Se pedir para confiar na pasta -> aceita.
REM    2) Escreve:  /login   e segue o OAuth no browser (conta Max).
REM    3) Quando estiver autenticado, escreve:  /exit
REM  Depois disto a ponte (run-claude.cmd) funciona para o hermes/VPS.
REM ===========================================================================
REM ---------------------------------------------------------------------------
REM  2026-08-01: a linha era `claude` NU, a contar com o PATH. O PATH nao tem
REM  `claude` -- nem sequer para o danil: desde 27/07 a app gere a CLI em
REM  %APPDATA%\Claude\claude-code\<versao>\ e nao instala shim nenhum
REM  (`where claude` nao devolve nada). Ou seja, o CAMINHO DE RECUPERACAO da
REM  autenticacao estava partido, calado, precisamente para o dia em que a auth
REM  falha e e' por aqui que se entra. Resolvido pelo MESMO helper das pontes
REM  (glob pela versao mais recente, nunca versao fixa).
REM  Backup da versao anterior: _backup\login.cmd.20260801-pre-resolver.bak
REM ---------------------------------------------------------------------------
set "CLAUDE_CONFIG_DIR=C:\Users\danil\.claude"
set "RESOLVEPS=%~dp0resolve-claude-exe.ps1"
set "CLAUDE_EXE="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%RESOLVEPS%" 2^>nul`) do if not defined CLAUDE_EXE set "CLAUDE_EXE=%%I"
if not defined CLAUDE_EXE (
  echo CLI-NAO-ENCONTRADA: o login nao resolveu o binario do Claude Code.
  echo   Procurei em: %%APPDATA%%\Claude\claude-code\*\claude.exe e no PATH.
  echo   utilizador=%USERDOMAIN%\%USERNAME%  APPDATA=%APPDATA%
  echo   Se a app foi reinstalada noutro sitio, ajusta resolve-claude-exe.ps1.
  exit /b 4
)
cd /d "C:\Users\danil\Desktop\projetosflutter\bora_app"
"%CLAUDE_EXE%"
