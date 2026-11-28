@echo off
rem PC-SEM-TRAVAR-ADMIN.cmd - missao pc-sem-travar 2026-11-28.
rem O Danilo so da duplo clique e carrega "Sim". Faz o que precisa de administrador:
rem   1) Chrome: Poupanca de memoria ligada (separadores parados dormem), com os sites dos
rem      robos sempre acordados (WhatsApp, Claude, Facebook, Instagram, Supabase, localhost...).
rem   2) Servicos de fundo que nao usamos passam a "so quando preciso" (nao se desinstala nada):
rem      TunnelBear, Lenovo Smart Connect, Lenovo UDC (telemetria), Wondershare NativePush.
rem   3) Lenovo Now deixa de arrancar sozinho (tarefas agendadas desligadas).
rem   4) Apaga os modelos do Ollama que ficaram no disco (23,8 GB; o Danilo mandou desinstalar).
rem Tudo reversivel: ver C:\BoraLocal\ferramentas\guardiao-ram\DESFAZER-2026-11-28.txt
rem O resultado fica em C:\BoraLocal\ferramentas\guardiao-ram\admin-resultado.txt

net session >nul 2>&1
if %errorlevel% neq 0 (
  powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -Verb RunAs"
  exit /b
)

set "OUT=C:\BoraLocal\ferramentas\guardiao-ram\admin-resultado.txt"
echo [%date% %time%] PC-SEM-TRAVAR-ADMIN a correr como administrador > "%OUT%"

echo.
echo === 1) Chrome: poupanca de memoria ===
set "P=HKLM\SOFTWARE\Policies\Google\Chrome"
reg add "%P%" /v HighEfficiencyModeEnabled /t REG_DWORD /d 1 /f >> "%OUT%" 2>&1
reg add "%P%" /v MemorySaverModeSavings /t REG_DWORD /d 1 /f >> "%OUT%" 2>&1
reg delete "%P%\TabDiscardingExceptions" /f >nul 2>&1
set "E=%P%\TabDiscardingExceptions"
reg add "%E%" /v 1 /t REG_SZ /d "web.whatsapp.com" /f >> "%OUT%" 2>&1
reg add "%E%" /v 2 /t REG_SZ /d "claude.ai" /f >> "%OUT%" 2>&1
reg add "%E%" /v 3 /t REG_SZ /d "localhost" /f >> "%OUT%" 2>&1
reg add "%E%" /v 4 /t REG_SZ /d "127.0.0.1" /f >> "%OUT%" 2>&1
reg add "%E%" /v 5 /t REG_SZ /d "[*.]supabase.com" /f >> "%OUT%" 2>&1
reg add "%E%" /v 6 /t REG_SZ /d "[*.]facebook.com" /f >> "%OUT%" 2>&1
reg add "%E%" /v 7 /t REG_SZ /d "[*.]instagram.com" /f >> "%OUT%" 2>&1
reg add "%E%" /v 8 /t REG_SZ /d "labs.google" /f >> "%OUT%" 2>&1
reg add "%E%" /v 9 /t REG_SZ /d "gemini.google.com" /f >> "%OUT%" 2>&1
reg add "%E%" /v 10 /t REG_SZ /d "chatgpt.com" /f >> "%OUT%" 2>&1
reg add "%E%" /v 11 /t REG_SZ /d "studio.youtube.com" /f >> "%OUT%" 2>&1
reg add "%E%" /v 12 /t REG_SZ /d "web.telegram.org" /f >> "%OUT%" 2>&1
reg add "%E%" /v 13 /t REG_SZ /d "aistudio.google.com" /f >> "%OUT%" 2>&1
reg query "%P%" /s >> "%OUT%" 2>&1

echo.
echo === 2) Servicos de fundo para "so quando preciso" ===
for %%S in (TunnelBearMaintenance SmartConnect UDCService) do (
  sc config %%S start= demand >> "%OUT%" 2>&1
  sc stop %%S >> "%OUT%" 2>&1
)
sc config NativePushService start= disabled >> "%OUT%" 2>&1
sc stop NativePushService >> "%OUT%" 2>&1
for %%S in (TunnelBearMaintenance SmartConnect UDCService NativePushService) do sc qc %%S | findstr /C:"SERVICE_NAME" /C:"START_TYPE" >> "%OUT%" 2>&1

echo.
echo === 3) Lenovo Now nao arranca sozinho ===
for %%T in (LenovoNowLauncher LenovoNowQuarterlyLaunch LenovoNowTask LenovoNowUpdate) do schtasks /Change /TN "\Lenovo\%%T" /Disable >> "%OUT%" 2>&1

echo.
echo === 4) Modelos do Ollama que ficaram no disco ===
if exist "%USERPROFILE%\.ollama" (
  rd /s /q "%USERPROFILE%\.ollama" >> "%OUT%" 2>&1
)
if exist "%USERPROFILE%\.ollama" (echo ollama: AINDA EXISTE >> "%OUT%") else (echo ollama: apagado >> "%OUT%")

echo [%date% %time%] fim >> "%OUT%"
echo.
echo Feito. Podes fechar esta janela. Para o Chrome usar a regra nova, fecha-o e abre-o de novo.
timeout /t 15
