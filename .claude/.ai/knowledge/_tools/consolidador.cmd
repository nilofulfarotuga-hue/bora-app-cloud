@echo off
REM ===========================================================================
REM  MOTOR DE CONHECIMENTO (C1) — wrapper da schtask BoraMotorConhecimento.
REM  Uma so task com DOIS gatilhos (04:00 e 16:00). Como os gatilhos nao podem
REM  levar argumentos diferentes, e' aqui que se decide o slot pelo relogio:
REM  antes do meio-dia = corrida da manha; depois = corrida das 16h (que se
REM  auto-salta se a cadencia em platform_settings estiver em "1x").
REM  Leve por construcao: so leitura + sumarizacao. Zero build, zero teste.
REM ===========================================================================
setlocal
set "AQUI=%~dp0"
set "LOG=%AQUI%..\inbox\_reports\consolidador.log"

set "SLOT="
for /f %%H in ('powershell -NoProfile -Command "(Get-Date).Hour"') do set "HORA=%%H"
if %HORA% GEQ 12 set "SLOT=--slot 16h"

echo [%date% %time%] --- corrida (hora=%HORA%) %SLOT% >> "%LOG%"
python "%AQUI%consolidador.py" %SLOT% >> "%LOG%" 2>&1
echo [%date% %time%] --- fim rc=%ERRORLEVEL% >> "%LOG%"
endlocal
