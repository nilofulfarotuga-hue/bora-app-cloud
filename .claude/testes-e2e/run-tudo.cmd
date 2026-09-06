@echo off
rem Loop Noturno E2E (Fase 7, single-device) — liga o telemóvel por USB e corre isto.
rem Para parar a meio: cria um ficheiro chamado PARAR nesta pasta.
cd /d "%~dp0"
rem deteccao robusta de python (autonomous corre como outro utilizador sem python no PATH)
set PY=C:\Users\danil\Desktop\produtividade-ia\agent-reach-venv\Scripts\python.exe
if not exist "%PY%" set PY=C:\Users\danil\AppData\Local\Programs\Python\Python312\python.exe
if not exist "%PY%" set PY=python
echo [run-tudo] python = %PY%
"%PY%" loop-noturno.py %*
