@echo off
rem instalar-schtask-desktop.cmd — regista o heartbeat-DESKTOP como schtask PC de hora em hora.
rem CRITICO: corre /RU danil /IT (sessao interativa) — so assim o operador alcanca o desktop
rem visivel e conduz o app Claude (PWA). O executor headless (Hermes, Session 0) NAO consegue.
rem
rem Substitui o heartbeat-browser (que bateu no Cloudflare Turnstile via Playwright).
rem 2026-07-13: intervalo passou de */10min para 60min (pedido do Danilo) — o detetor
rem (Peca 1, anti-spam por watermark) ja so dispara em mudanca real; 1x/hora chega.
rem Reversivel: schtasks /Delete /TN "Bora-heartbeat-desktop" /F
rem            (e opcional) schtasks /Delete /TN "Bora-heartbeat-browser" /F

set WRAP=C:\Users\danil\Desktop\projetosflutter\bora_app\.claude\.ai\hermes\heartbeat-desktop\run-heartbeat-desktop.cmd

echo [heartbeat-desktop] a registar schtask de hora em hora (RU danil, interativo) ...
schtasks /Create /TN "Bora-heartbeat-desktop" ^
  /TR "\"%WRAP%\"" ^
  /SC MINUTE /MO 60 /RU danil /IT /F

echo.
echo [heartbeat-desktop] a desligar o antigo heartbeat-browser (Turnstile) ...
schtasks /Delete /TN "Bora-heartbeat-browser" /F 2>nul

echo.
echo Feito. Verificar:  schtasks /Query /TN "Bora-heartbeat-desktop"
echo Forcar 1 ciclo:    schtasks /Run /TN "Bora-heartbeat-desktop"
echo Desligar:          schtasks /Delete /TN "Bora-heartbeat-desktop" /F
