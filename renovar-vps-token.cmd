@echo off
chcp 65001 >NUL
setlocal

REM renovar-vps-token.cmd -- renova o token OAuth do Claude Code na VPS com o MINIMO de cliques.
REM Correr quando o watchdog avisar "token expirou" (ou sempre que o executor parar por auth).
REM
REM Fluxo (2026-07-15):
REM   1) SSH automatico a VPS -- (re)arranca 'claude setup-token' numa sessao tmux persistente
REM      "authnow2" (sobrevive a quedas de ligacao, como fizemos manualmente em 2026-07-14).
REM   2) Captura a URL de autorizacao do pane da sessao e ABRE-A no teu browser padrao.
REM      Tu NAO precisas copiar/colar a URL -- so ves o browser abrir.
REM   3) Autorizas na pagina, copias o codigo que aparece, e colas aqui nesta janela.
REM   4) O script injeta o codigo na sessao tmux da VPS via SSH e mostra as ultimas linhas
REM      para confirmares que ficou "Login successful" / o token foi guardado.
REM
REM Requisitos (ja configurados no teu PC, ver .claude/.ai/knowledge/inbox/e2e-via-vps-web-2026-07-11.md):
REM   - OpenSSH client do Windows (ssh.exe) -- vem de origem no Windows 10/11.
REM   - Chave privada em C:\Users\%USERNAME%\.ssh\id_ed25519_vps ja autorizada na VPS.

set "HOST=root@srv1786862.hstgr.cloud"
set "SESSION=authnow2"
set "SSHKEY=%USERPROFILE%\.ssh\id_ed25519_vps"
set "SSH=ssh -o ConnectTimeout=15 -o StrictHostKeyChecking=accept-new"
if exist "%SSHKEY%" set "SSH=%SSH% -i "%SSHKEY%""

echo ============================================================
echo   RENOVACAO DO TOKEN DA VPS (Claude Code) -- minimo de cliques
echo ============================================================
echo.
echo [1/4] A ligar a VPS (%HOST%) e a arrancar a sessao de autorizacao...

set "AUTH_URL="
for /f "usebackq delims=" %%U in (`%SSH% %HOST% "tmux kill-session -t %SESSION% 2>/dev/null; tmux new-session -d -s %SESSION% -x 220 -y 50 'claude setup-token'; sleep 3; tmux capture-pane -t %SESSION% -p | grep -oE 'https://[^ ]+' | head -1"`) do set "AUTH_URL=%%U"

if "%AUTH_URL%"=="" (
  echo.
  echo [ERRO] Nao consegui obter a URL de autorizacao pela VPS.
  echo   - Confirma que consegues fazer: ssh -i "%SSHKEY%" %HOST%
  echo   - Ou entra manualmente e ve a sessao: ssh %HOST% "tmux attach -t %SESSION%"
  echo.
  pause
  exit /b 1
)

echo [2/4] URL de autorizacao obtida. A abrir no teu browser...
echo   %AUTH_URL%
start "" "%AUTH_URL%"

echo.
echo [3/4] No browser: clica AUTORIZAR e copia o codigo que aparece na pagina.
set /p CODE="      Cola aqui o codigo e prime Enter: "

if "%CODE%"=="" (
  echo.
  echo [AVISO] Nenhum codigo introduzido. A sessao "%SESSION%" continua aberta na VPS --
  echo         corre este script outra vez, ou entra manualmente: ssh %HOST% "tmux attach -t %SESSION%"
  echo.
  pause
  exit /b 1
)

echo.
echo [4/4] A enviar o codigo para a VPS e a confirmar...
%SSH% %HOST% "tmux send-keys -t %SESSION% '%CODE%' Enter"
timeout /t 3 /nobreak >NUL
echo.
echo ------------------------------------------------------------
%SSH% %HOST% "tmux capture-pane -t %SESSION% -p | tail -6"
echo ------------------------------------------------------------
echo.
echo Confere as ultimas linhas acima. Se disser algo como
echo "Login successful" ou "credentials saved", esta feito.
echo Se nao, corre o script outra vez (ele reinicia a sessao do zero).
echo ============================================================
pause
endlocal
