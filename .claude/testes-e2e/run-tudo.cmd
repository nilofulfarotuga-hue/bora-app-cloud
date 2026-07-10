@echo off
rem Loop Noturno E2E (Fase 7, single-device) — liga o telemóvel por USB e corre isto.
rem Para parar a meio: cria um ficheiro chamado PARAR nesta pasta.
cd /d "%~dp0"
python loop-noturno.py %*
