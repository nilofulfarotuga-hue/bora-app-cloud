@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >NUL
REM ===========================================================================
REM  PONTE BORA :: EXECUTOR do loop de orquestracao (carteiro -> pc-loop -> aqui)
REM  Isolado do run-claude.cmd partilhado. Tetos T2/T4 do loop vivem AQUI.
REM  - T2 custo: --max-turns 150 + --max-budget-usd 25 (teto por tentativa; subido de 40/10 em
REM    2026-07-17, FASE 1.10 -- tarefas reais do Bora nao cabiam em 40 turnos/$10, o claude.exe
REM    parava a meio e o stream-json emitia type:result sem campo .result, deixando o parser
REM    mudo (0 bytes) -- ver bora-live-parser.ps1 e inbox/fix-executor-max-turns-parser-mudo-2026-07-17.md)
REM  - FASE 1.3 (2026-07-12): MODELO por tarefa. [MODELO: OPUS] no texto -> opus;
REM    senao SONNET (default economico). Antes era opus fixo -> queimava a conta.
REM  - FASE 1.4 (2026-07-12): stream-json --verbose -> bora-live-parser.ps1 escreve
REM    linhas legiveis no LIVELOG (Danilo acompanha com assistir.cmd) e emite so o
REM    resultado final no stdout (o carteiro/juiz recebem texto igual ao de antes).
REM  - FASE 1.5 (2026-07-13, ordem 4833): LOCK DE CONCORRENCIA -- causa raiz de dias de
REM    travamento era RAM esgotada por varios claude.exe empilhados (nao a ponte). Agora:
REM    so 1 claude.exe executor de cada vez (lock em .claude\executor.lock, PID+timestamp;
REM    lock orfao = PID morto OU idade >10min -> assumido na hora) + limpeza de processos
REM    orfaos da esteira antes de cada ciclo. Ver executor-lock.ps1 +
REM    inbox/lock-concorrencia-2026-07-13.md.
REM  - FASE 1.6 (2026-07-13, ordem auto-limpeza-ram): rede de seguranca extra de RAM/zumbis
REM    -- auto-limpeza-ram.cmd corre no FIM de cada ciclo (zumbis claude/cmd/python/conhost +
REM    limpeza de temp se RAM < 300MB). Complementa o cleanorphans acima (que so corre ANTES);
REM    esta corre DEPOIS, apanhando o que sobrou do proprio ciclo. Ver auto-limpeza-ram.ps1 +
REM    inbox/auto-limpeza-ram-2026-07-13.md.
REM  - FASE 1.8 (2026-07-14, lock orfao definitivo): "PID vivo?" sozinho nao chega -- o Windows
REM    recicla PIDs, e um lock cujo dono morreu podia ficar "vivo para sempre" se o numero
REM    calhasse noutro processo (travou a fila 2x no mesmo dia). executor-lock.ps1 agora grava
REM    pid+timestamp+start-time do dono e so considera o lock vivo se AMBOS baterem; cleanorphans
REM    tambem apaga o executor.lock orfao logo no arranque do ciclo (nao so no 'acquire' a
REM    seguir). Ver inbox/lock-orfao-definitivo-2026-07-14.md.
REM  - FASE 1.9 (2026-07-16, pos-morte ordem 7838, pedido Danilo): o teto fixo `timeout 3600`
REM    do lado VPS (carteiro.sh) matou a 7838 2x enquanto ela ainda produzia output real nos
REM    testes finais -- relogio total nao distingue "morta" de "grande mas viva". Agora corre
REM    stale-output-watchdog.ps1 EM PARALELO ao claude.exe: so mata por INATIVIDADE real (o
REM    LIVELOG sem crescer ha 20min); teto duro de 4h fica como rede de seguranca final. Se o
REM    watchdog matar, grava o motivo em STALESTAMP e este .cmd devolve "MOTIVO_KILL:..." no
REM    stdout (carteiro.sh le isto e avisa "morta por inatividade", nunca "timeout" generico).
REM ===========================================================================
set "CLAUDE_CONFIG_DIR=C:\Users\danil\.claude"
set "CLAUDE_EXE=C:\Users\danil\AppData\Roaming\npm\node_modules\@anthropic-ai\claude-code\bin\claude.exe"
set "PROJ=C:\Users\danil\Desktop\projetosflutter\bora_app"
set "LIVELOG=%PROJ%\.claude\bora-live.log"
set "PARSER=%~dp0bora-live-parser.ps1"
set "TASKFILE=%TEMP%\bora_loop_task.txt"
set "LOCKFILE=%PROJ%\.claude\executor.lock"
set "LOCKPS=%~dp0executor-lock.ps1"
set "LOCK_MAXWAIT=480"
set "AUTOLIMPEZA=%~dp0auto-limpeza-ram.cmd"
set "WATCHDOGPS=%~dp0stale-output-watchdog.ps1"
set "STALESTAMP=%TEMP%\bora_stale_stamp.txt"
if not exist "%CLAUDE_EXE%" ( echo [loop] ERRO: claude.exe nao encontrado & exit /b 4 )

set "PERM=--dangerously-skip-permissions"
set "BUDGET=--max-budget-usd 25"
set "TURNS=--max-turns 150"

set "GUARD=Estas a correr como EXECUTOR de um loop autonomo do Bora (headless, sem canal com o Danilo). Faz a tarefa toda sozinho, decisoes REVERSIVEIS por conta propria. NUNCA facas git commit nem git push (a menos que a tarefa peca explicitamente). Se a tarefa comecar com [PROPOSE-ONLY], prepara tudo mas NAO apliques nem facas commit - devolve a proposta e para. PARA e responde SO com uma linha 'CONFIRMACAO NECESSARIA: <o que>' se a tarefa tocar Lista Vermelha (Stripe/pagamentos/payouts/pricing/dispatch_engine/finalizePurchase/bora_tokens/RLS de orders-wallets-ledger/migrations destrutivas/force-push/disparos em massa/builds de producao). Nunca imprimas segredos. No fim devolve RESULTADO conciso PT-BR: o que fizeste + ficheiros tocados."

cd /d "%PROJ%" || ( echo [loop] ERRO: projeto nao encontrado & exit /b 3 )

REM MYPID = PID deste cmd.exe (dono do lock durante toda a execucao, via PID pai do
REM powershell que se auto-consulta). Vive tanto quanto durar este .cmd (inclui o claude.exe).
for /f %%P in ('powershell -NoProfile -Command "(Get-CimInstance Win32_Process -Filter ('ProcessId=' + $PID)).ParentProcessId"') do set "MYPID=%%P"

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
echo [%date% %time%] ==== ciclo :: MYPID=%MYPID% ==== >> "%LIVELOG%"

REM FASE 1.5 -- limpeza de orfaos da esteira (so claude/cmd/python com a marca do Bora
REM na linha de comando, parados ha >10min a ~0% CPU) ANTES de tentar subir outro claude.exe.
REM FASE 1.7 (2026-07-13, deteccao de terminal preso): tambem mata se o LIVELOG nao cresce ha
REM >15min -- PID vivo nao chega, um terminal pode estar preso para sempre numa pergunta/
REM sugestao do proprio Claude Code sem produzir output novo. Ver executor-lock.ps1.
powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCKPS%" -Action cleanorphans -LockFile "%LOCKFILE%" -LiveLog "%LIVELOG%" -StaleOutputMin 15 > "%TEMP%\bora_lock_clean.txt" 2>&1
for /f "usebackq delims=" %%L in ("%TEMP%\bora_lock_clean.txt") do echo [%date% %time%] %%L >> "%LIVELOG%"

REM FASE 1.5 -- lock de concorrencia: so 1 claude.exe executor de cada vez. Se outro
REM executor vivo (<10min) estiver a correr, ESPERA (nunca sobe um segundo); lock orfao e
REM assumido na hora.
powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCKPS%" -Action acquire -LockFile "%LOCKFILE%" -OwnerPid %MYPID% -MaxWaitSec %LOCK_MAXWAIT% > "%TEMP%\bora_lock_acquire.txt" 2>&1
set "LOCKRESULT="
for /f "usebackq delims=" %%L in ("%TEMP%\bora_lock_acquire.txt") do (
  echo [%date% %time%] %%L >> "%LIVELOG%"
  set "LOCKRESULT=%%L"
)
if /I not "!LOCKRESULT!"=="ACQUIRED" (
  echo [%date% %time%] [loop] ERRO: lock ocupado por outro executor vivo - abortar sem subir claude.exe, evita empilhar RAM >> "%LIVELOG%"
  echo ERRO: outro executor Bora ja em curso ha muito tempo - tarefa nao executada, o carteiro tenta de novo.
  exit /b 7
)

REM FASE 1.3 -- modelo por tarefa (default sonnet; [MODELO: OPUS] sobe para opus)
set "MODEL=--model sonnet"
findstr /I /C:"[MODELO: OPUS]" "%TASKFILE%" >NUL 2>&1 && set "MODEL=--model opus"
echo [%date% %time%] ==== nova ordem :: %MODEL% ==== >> "%LIVELOG%"
REM FASE 1.9 -- vigia de inatividade em paralelo (so mata se o LIVELOG parar de crescer 20min;
REM teto duro 4h). Auto-termina sozinho (~30s) se o claude.exe ja tiver acabado antes disso.
del /f /q "%STALESTAMP%" >nul 2>&1
if exist "%WATCHDOGPS%" (
  start "" /B powershell -NoProfile -ExecutionPolicy Bypass -File "%WATCHDOGPS%" -LiveLog "%LIVELOG%" -StampFile "%STALESTAMP%" -StaleMinutes 20 -HardCeilingMinutes 240 -PollSeconds 30
)
REM FASE 1.4 -- stream legivel no LIVELOG + resultado final no stdout (via parser)
"%CLAUDE_EXE%" -p --append-system-prompt "%GUARD%" --output-format stream-json --verbose %MODEL% %PERM% %TURNS% %BUDGET% < "%TASKFILE%" 2>&1 | powershell -NoProfile -ExecutionPolicy Bypass -File "%PARSER%" "%LIVELOG%"
set "CLAUDE_RC=%ERRORLEVEL%"
REM FASE 1.9 -- se o vigia matou o executor, o motivo (INATIVIDADE:Xmin | TETO-DURO:Xmin) vai
REM no stdout para o carteiro.sh distinguir de uma saida vazia normal e nunca dizer "timeout".
if exist "%STALESTAMP%" (
  set "MOTIVO_KILL="
  set /p MOTIVO_KILL=<"%STALESTAMP%"
  echo [%date% %time%] [loop] vigia-inatividade matou o executor: !MOTIVO_KILL! >> "%LIVELOG%"
  echo MOTIVO_KILL:!MOTIVO_KILL!
  del /f /q "%STALESTAMP%" >nul 2>&1
)
powershell -NoProfile -ExecutionPolicy Bypass -File "%LOCKPS%" -Action release -LockFile "%LOCKFILE%" -OwnerPid %MYPID% >> "%LIVELOG%" 2>&1
if exist "%AUTOLIMPEZA%" ( call "%AUTOLIMPEZA%" hook >> "%LIVELOG%" 2>&1 )
exit /b %CLAUDE_RC%
