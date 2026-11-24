@echo off
chcp 65001 >nul
rem Liga "quem faz a missao publica" (ordem do Danilo, 24/11/2026). Duplo clique do Danilo.
rem Vai buscar os ficheiros ao GitHub (ramo principal) sem mexer na pasta de trabalho e corre o instalador.
set REPO=C:\BoraLocal\projetosflutter\bora_app
set T=%TEMP%\publicar-sozinho-%RANDOM%
mkdir "%T%"
git -C "%REPO%" fetch -q origin autonomous-night-2026-04-29 || goto erro
git -C "%REPO%" archive --format=tar -o "%T%\pacote.tar" FETCH_HEAD docs/propostas/publicar-sozinho-2026-11-24 .claude/dsh/plugin-dsh-bora || goto erro
tar -xf "%T%\pacote.tar" -C "%T%" || goto erro
powershell -NoProfile -ExecutionPolicy Bypass -File "%T%\docs\propostas\publicar-sozinho-2026-11-24\INSTALAR.ps1" -Fonte "%T%"
echo.
pause
exit /b
:erro
echo FALHOU a ir buscar os ficheiros ao GitHub. Nada foi mudado.
pause
