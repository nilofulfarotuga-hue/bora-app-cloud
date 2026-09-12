@echo off
rem PASSO 4 — prova de que uma Tarefa Agendada corre o Maestro SEM sessao interativa.
rem Env fixado em caminhos absolutos para nao depender do perfil do utilizador (SYSTEM).
cd /d "%~dp0"
set "LOCALAPPDATA=C:\Users\danil\AppData\Local"
set "JAVA_HOME=C:\Program Files\Android\Android Studio\jbr"
set "ANDROID_HOME=C:\Users\danil\AppData\Local\Android\Sdk"
set "PATH=%ANDROID_HOME%\platform-tools;%JAVA_HOME%\bin;%PATH%"
set "PY=C:\Users\danil\AppData\Local\Programs\Python\Python312\python.exe"
if not exist "%PY%" set PY=python
echo [schtask-prova] inicio %DATE% %TIME% > _schtask_prova.log
echo [schtask-prova] whoami: >> _schtask_prova.log
whoami >> _schtask_prova.log 2>&1
"%PY%" _passo3_login_manual.py N75LTG5X5DSKDMV4 >> _schtask_prova.log 2>&1
echo [schtask-prova] fim %DATE% %TIME% rc=%ERRORLEVEL% >> _schtask_prova.log
