@echo off
setlocal EnableExtensions
chcp 65001 >NUL
REM ===========================================================================
REM  PONTE BORA :: EXECUTOR do loop de orquestração (carteiro -> pc-loop -> aqui)
REM  Isolado do run-claude.cmd partilhado. Tetos T2/T4 do loop vivem AQUI.
REM  - T2 custo: --max-turns 40 + --max-budget-usd 10 (teto por tentativa)
REM    (subido 2026-07-10: com 20/5 as tarefas pesadas nao terminavam dentro do
REM     timeout 320s da carteiro -> --output-format text so emite no fim -> saida VAZIA)
REM  - T3 zona vermelha: os hooks protege-*.sh disparam mesmo com skip-permissions
REM    (verificado). O guard abaixo reforça (soft). Sem commit/push automático.
REM ===========================================================================
set "CLAUDE_CONFIG_DIR=C:\Users\danil\.claude"
set "CLAUDE_EXE=C:\Users\danil\AppData\Roaming\npm\node_modules\@anthropic-ai\claude-code\bin\claude.exe"
set "PROJ=C:\Users\danil\Desktop\projetosflutter\bora_app"
if not exist "%CLAUDE_EXE%" ( echo [loop] ERRO: claude.exe nao encontrado & exit /b 4 )

set "PERM=--dangerously-skip-permissions"
set "MODEL=--model opus"
set "BUDGET=--max-budget-usd 10"
set "TURNS=--max-turns 40"

set "GUARD=Estas a correr como EXECUTOR de um loop autonomo do Bora (headless, sem canal com o Danilo). Faz a tarefa toda sozinho, decisoes REVERSIVEIS por conta propria. NUNCA faças git commit nem git push (a menos que a tarefa peça explicitamente). PARA e responde SO com uma linha 'CONFIRMACAO NECESSARIA: <o que>' se a tarefa tocar Lista Vermelha (Stripe/pagamentos/payouts/pricing/dispatch_engine/finalizePurchase/bora_tokens/RLS de orders-wallets-ledger/migrations destrutivas/force-push/disparos em massa/builds de producao). Nunca imprimas segredos. No fim devolve RESULTADO conciso PT-BR: o que fizeste + ficheiros tocados."

cd /d "%PROJ%" || ( echo [loop] ERRO: projeto nao encontrado & exit /b 3 )

if /I "%~1"=="--b64" (
  set "BORA_B64=%~2"
  powershell -NoProfile -Command "$b=$env:BORA_B64; $b=$b.PadRight([math]::Ceiling($b.Length/4)*4,'='); [IO.File]::WriteAllText($env:TEMP + '\bora_loop_task.txt', [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)))" || ( echo [loop] ERRO base64 & exit /b 5 )
  "%CLAUDE_EXE%" -p --append-system-prompt "%GUARD%" --output-format text %MODEL% %PERM% %TURNS% %BUDGET% < "%TEMP%\bora_loop_task.txt"
  exit /b %ERRORLEVEL%
)
echo [loop] ERRO: uso: run-claude-loop.cmd --b64 ^<BASE64^>
exit /b 2
