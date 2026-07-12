@echo off
setlocal EnableExtensions
chcp 65001 >NUL
REM ===========================================================================
REM  PONTE BORA :: EXECUTOR do loop de orquestracao (carteiro -> pc-loop -> aqui)
REM  Isolado do run-claude.cmd partilhado. Tetos T2/T4 do loop vivem AQUI.
REM  - T2 custo: --max-turns 40 + --max-budget-usd 10 (teto por tentativa)
REM  - FASE 1.3 (2026-07-12): MODELO por tarefa. [MODELO: OPUS] no texto -> opus;
REM    senao SONNET (default economico). Antes era opus fixo -> queimava a conta.
REM  - FASE 1.4 (2026-07-12): stream-json --verbose -> bora-live-parser.ps1 escreve
REM    linhas legiveis no LIVELOG (Danilo acompanha com assistir.cmd) e emite so o
REM    resultado final no stdout (o carteiro/juiz recebem texto igual ao de antes).
REM ===========================================================================
set "CLAUDE_CONFIG_DIR=C:\Users\danil\.claude"
set "CLAUDE_EXE=C:\Users\danil\AppData\Roaming\npm\node_modules\@anthropic-ai\claude-code\bin\claude.exe"
set "PROJ=C:\Users\danil\Desktop\projetosflutter\bora_app"
set "LIVELOG=%PROJ%\.claude\bora-live.log"
set "PARSER=%~dp0bora-live-parser.ps1"
set "TASKFILE=%TEMP%\bora_loop_task.txt"
if not exist "%CLAUDE_EXE%" ( echo [loop] ERRO: claude.exe nao encontrado & exit /b 4 )

set "PERM=--dangerously-skip-permissions"
set "BUDGET=--max-budget-usd 10"
set "TURNS=--max-turns 40"

set "GUARD=Estas a correr como EXECUTOR de um loop autonomo do Bora (headless, sem canal com o Danilo). Faz a tarefa toda sozinho, decisoes REVERSIVEIS por conta propria. NUNCA facas git commit nem git push (a menos que a tarefa peca explicitamente). Se a tarefa comecar com [PROPOSE-ONLY], prepara tudo mas NAO apliques nem facas commit - devolve a proposta e para. PARA e responde SO com uma linha 'CONFIRMACAO NECESSARIA: <o que>' se a tarefa tocar Lista Vermelha (Stripe/pagamentos/payouts/pricing/dispatch_engine/finalizePurchase/bora_tokens/RLS de orders-wallets-ledger/migrations destrutivas/force-push/disparos em massa/builds de producao). Nunca imprimas segredos. No fim devolve RESULTADO conciso PT-BR: o que fizeste + ficheiros tocados."

cd /d "%PROJ%" || ( echo [loop] ERRO: projeto nao encontrado & exit /b 3 )

REM --b64stdin: base64 da tarefa vem por STDIN (nao como argumento CLI). Args grandes
REM rebentavam o comando remoto do ssh no Windows -> o .cmd nunca corria (fix 2026-07-10).
if /I "%~1"=="--b64stdin" (
  powershell -NoProfile -Command "$b=[Console]::In.ReadToEnd().Trim(); $b=$b.PadRight([math]::Ceiling($b.Length/4)*4,'='); [IO.File]::WriteAllText($env:TEMP + '\bora_loop_task.txt', [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)))" || ( echo [loop] ERRO base64stdin & exit /b 5 )
  call :run_claude
  exit /b %ERRORLEVEL%
)
if /I "%~1"=="--b64" (
  set "BORA_B64=%~2"
  powershell -NoProfile -Command "$b=$env:BORA_B64; $b=$b.PadRight([math]::Ceiling($b.Length/4)*4,'='); [IO.File]::WriteAllText($env:TEMP + '\bora_loop_task.txt', [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)))" || ( echo [loop] ERRO base64 & exit /b 5 )
  call :run_claude
  exit /b %ERRORLEVEL%
)
echo [loop] ERRO: uso: run-claude-loop.cmd --b64stdin ^(tarefa por STDIN^) ^| --b64 ^<BASE64^>
exit /b 2

:run_claude
REM FASE 1.3 -- modelo por tarefa (default sonnet; [MODELO: OPUS] sobe para opus)
set "MODEL=--model sonnet"
findstr /I /C:"[MODELO: OPUS]" "%TASKFILE%" >NUL 2>&1 && set "MODEL=--model opus"
echo [%date% %time%] ==== nova ordem :: %MODEL% ==== >> "%LIVELOG%"
REM FASE 1.4 -- stream legivel no LIVELOG + resultado final no stdout (via parser)
"%CLAUDE_EXE%" -p --append-system-prompt "%GUARD%" --output-format stream-json --verbose %MODEL% %PERM% %TURNS% %BUDGET% < "%TASKFILE%" 2>&1 | powershell -NoProfile -ExecutionPolicy Bypass -File "%PARSER%" "%LIVELOG%"
exit /b %ERRORLEVEL%
