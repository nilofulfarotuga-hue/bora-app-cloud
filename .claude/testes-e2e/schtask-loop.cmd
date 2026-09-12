@echo off
rem Loop Noturno E2E via Tarefa Agendada SYSTEM — sobrevive ao fim da sessao do Claude.
rem Env fixado em caminhos absolutos do perfil danil (a task corre como SYSTEM).
rem Parar: criar ficheiro chamado PARAR nesta pasta.
cd /d "%~dp0"
set "LOCALAPPDATA=C:\Users\danil\AppData\Local"
set "JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set "ANDROID_HOME=C:\Users\danil\AppData\Local\Android\Sdk"
set "PATH=%ANDROID_HOME%\platform-tools;%JAVA_HOME%\bin;%PATH%"
set "PY=C:\Users\danil\AppData\Local\Programs\Python\Python312\python.exe"
if not exist "%PY%" set PY=python
echo [schtask-loop] arranque %DATE% %TIME% > _schtask_loop.log
whoami >> _schtask_loop.log 2>&1
"%PY%" loop-noturno.py >> _schtask_loop.log 2>&1
echo [schtask-loop] fim %DATE% %TIME% rc=%ERRORLEVEL% >> _schtask_loop.log
