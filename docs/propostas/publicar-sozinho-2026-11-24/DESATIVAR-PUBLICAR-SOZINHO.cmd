@echo off
chcp 65001 >nul
rem Volta ao modo de 05/11 (os agentes nao publicam).
set REPO=C:\BoraLocal\projetosflutter\bora_app
set T=%TEMP%\publicar-sozinho-volta-%RANDOM%
mkdir "%T%"
git -C "%REPO%" fetch -q origin autonomous-night-2026-04-29
git -C "%REPO%" archive --format=tar -o "%T%\pacote.tar" FETCH_HEAD docs/propostas/publicar-sozinho-2026-11-24
tar -xf "%T%\pacote.tar" -C "%T%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%T%\docs\propostas\publicar-sozinho-2026-11-24\DESINSTALAR.ps1"
pause
