@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >NUL
REM ===========================================================================
REM  EXECUTOR LIMPO do loop -- PC NOVO (Lenovo), 2026-08-31.
REM  O executor legado (run-claude-loop-novopc.cmd) acumulou armadilhas de parsing
REM  do cmd que so disparam neste PC (pipes e parenteses dentro de blocos, bytes
REM  nulos no findstr, .ps1 vs .cmd, subprocessos a comer o stdin). Em vez de mais
REM  whack-a-mole, este executor faz SO o essencial e ja provado:
REM    1. captura a tarefa (base64 no stdin) PRIMEIRO, antes de qualquer subprocesso;
REM    2. corre o claude.cmd (npm) com o guard, a tarefa por ficheiro;
REM    3. passa pelo parser que da a saida legivel + o resultado final.
REM  Sem RAM-gate (16 GB), sem lock/watchdog/orfaos, sem MOTOR-GO, sem preflight de
REM  auth (redundante: uma auth ma aparece na saida real do executor).
REM ===========================================================================

REM 1. TAREFA primeiro (antes de tudo). base64 por stdin -> ficheiro.
if /I "%~1"=="--b64stdin" powershell -NoProfile -Command "$b=[Console]::In.ReadToEnd().Trim(); $b=$b.PadRight([math]::Ceiling($b.Length/4)*4,'='); [IO.File]::WriteAllText($env:TEMP + '\bora_loop_task.txt', [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)))"

set "PROJ=C:\BoraLocal\projetosflutter\bora_app"
set "CLAUDE_CONFIG_DIR=C:\Users\danil\.claude"
set "HOME=C:\Users\danil"
set "USERPROFILE=C:\Users\danil"
set "GIT_CONFIG_COUNT=1"
set "GIT_CONFIG_KEY_0=safe.directory"
set "GIT_CONFIG_VALUE_0=*"
REM BUG 6 (2026-09-05, sessao fila-ganho-05-09): CARIMBO DE SESSAO DO LOOP.
REM O juiz atribuia a ordem em curso TODOS os commits feitos desde que ela
REM arrancou, fossem dela ou nao. Media-se assim: uma ordem foi reprovada por
REM zona vermelha por causa de um commit de uma sessao manual, e outra foi dada
REM por provada com 46 ficheiros que tambem nao eram dela. Agora o executor
REM assina o que commita, e o juiz so olha para o que tem esta assinatura.
REM So o COMMITTER muda; o autor fica como esta, para o historico continuar a
REM ler-se como sempre.
set "GIT_COMMITTER_NAME=bora-loop"
set "GIT_COMMITTER_EMAIL=loop@bora.local"
set "CLAUDE_EXE=%APPDATA%\npm\claude.cmd"
if not exist "%CLAUDE_EXE%" set "CLAUDE_EXE=claude"
set "TASKFILE=%TEMP%\bora_loop_task.txt"
set "PARSER=%~dp0bora-live-parser.ps1"
set "LIVELOG=%PROJ%\.claude\bora-live.log"

if not exist "%TASKFILE%" ( echo [loop-limpo] ERRO: tarefa vazia ^(taskfile ausente^) & exit /b 5 )

set "GUARD=Estas a correr como EXECUTOR de um loop autonomo do Bora (headless, sem canal com o Danilo). Faz a tarefa toda sozinho, decisoes REVERSIVEIS por conta propria. NUNCA facas git commit nem git push (a menos que a tarefa peca explicitamente). Se a tarefa comecar com [PROPOSE-ONLY], prepara tudo mas NAO apliques nem facas commit - devolve a proposta e para. PARA e responde SO com uma linha 'CONFIRMACAO NECESSARIA: <o que>' se a tarefa tocar Lista Vermelha (Stripe/pagamentos/payouts/pricing/dispatch_engine/finalizePurchase/bora_tokens/RLS de orders-wallets-ledger/migrations destrutivas/force-push/disparos em massa/builds de producao). Nunca imprimas segredos. No fim devolve RESULTADO conciso PT-BR: o que fizeste + ficheiros tocados."

cd /d "%PROJ%" || ( echo [loop-limpo] ERRO: projeto nao encontrado & exit /b 3 )

echo [%date% %time%] ==== executor-limpo :: arranque ==== >> "%LIVELOG%"
"%CLAUDE_EXE%" -p --append-system-prompt "%GUARD%" --output-format stream-json --verbose --model sonnet --dangerously-skip-permissions --max-turns 150 --max-budget-usd 25 < "%TASKFILE%" 2>&1 | powershell -NoProfile -ExecutionPolicy Bypass -File "%PARSER%" "%LIVELOG%"
set "RC=%ERRORLEVEL%"
echo [%date% %time%] ==== executor-limpo :: fim rc=%RC% ==== >> "%LIVELOG%"
exit /b %RC%
