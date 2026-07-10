@echo off
rem espera-e-corre.cmd — vigia: espera o telemovel ficar AUTORIZADO no adb e arranca o loop noturno.
rem Criado na retoma 2026-07-10 (device ficou unauthorized a meio). Para cancelar: fecha a janela
rem ou cria o ficheiro PARAR nesta pasta.
cd /d "%~dp0"
set ADB=%LOCALAPPDATA%\Android\Sdk\platform-tools\adb.exe
echo [espera-e-corre] a a aguardar autorizacao USB do telemovel...
:espera
if exist PARAR (echo [espera-e-corre] PARAR encontrado — saio. & exit /b 0)
"%ADB%" devices | findstr /r /c:"device$" >nul 2>&1
if errorlevel 1 (
  timeout /t 30 /nobreak >nul
  goto espera
)
echo [espera-e-corre] telemovel autorizado — a arrancar o loop noturno.
call run-tudo.cmd
