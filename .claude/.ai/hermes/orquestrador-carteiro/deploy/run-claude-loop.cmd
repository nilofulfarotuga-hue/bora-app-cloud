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
REM FASE 1.11 (2026-08-01) -- RESOLUCAO DINAMICA DO BINARIO + PREFLIGHT QUE GRITA.
REM Avaria de 27/07 a 31/07 (4 dias): ate 22/07 a CLI vinha do npm global e o caminho fixo
REM %APPDATA%\npm\node_modules\@anthropic-ai\claude-code\bin\claude.exe resolvia. A 27/07 a app
REM Claude passou a gerir a CLI em %APPDATA%\Claude\claude-code\<versao>\claude.exe e a pasta npm
REM desapareceu -> o caminho fixo deixou de existir -> "exit /b 4" -> 0 bytes -> o carteiro
REM inventava "SAIDA-VAZIA -- tarefa grande demais?". A avaria ficou escondida 4 dias atras de
REM uma nota que mentia. ISOLAMENTO DE PERFIL: o executor entra como `hermes` (ssh/tailscale) mas
REM a CLI esta sob o perfil do `danil`, logo %APPDATA% do hermes nunca a encontraria, e `where
REM claude` sob hermes tambem devolve vazio (nao ha shim no PATH dele).
REM Por isso: GLOB pela versao MAIS RECENTE (nunca versao fixa -- 2.1.219 muda na proxima
REM atualizacao e partia isto outra vez em silencio), com fallback ao PATH.
set "CLAUDE_ROOT=C:\Users\danil\AppData\Roaming\Claude\claude-code"
set "RESOLVEPS=%~dp0resolve-claude-exe.ps1"
set "CLAUDE_EXE="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%RESOLVEPS%" 2^>nul`) do if not defined CLAUDE_EXE set "CLAUDE_EXE=%%I"
REM Irmao da FASE 1.10: o parser nunca fica mudo -- e agora o ARRANQUE tambem nao. Linha
REM especifica e acionavel em vez de 0 bytes, para o carteiro nunca mais adivinhar a causa.
if not defined CLAUDE_EXE (
  echo CLI-NAO-ENCONTRADA: procurei em "%CLAUDE_ROOT%\*\claude.exe" e no PATH ^(where claude^) -- utilizador=%USERDOMAIN%\%USERNAME% APPDATA=%APPDATA%
  exit /b 4
)
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
if not exist "%CLAUDE_EXE%" (
  echo CLI-NAO-ENCONTRADA: resolvido para "%CLAUDE_EXE%" mas o ficheiro nao existe -- utilizador=%USERDOMAIN%\%USERNAME% APPDATA=%APPDATA%
  exit /b 4
)

REM ---- PREFLIGHT DE AUTH (FASE 1.11, item 4) -- irmao do CLI-NAO-ENCONTRADA ----
REM `claude auth status` devolve JSON com "loggedIn" e NAO gasta tokens de modelo. Sem isto, a
REM sessao OAuth morta so se manifestava DEPOIS de arrancar, e a saida ia parar ao ramo generico
REM "SAIDA-VAZIA -- tarefa grande demais?" -- a mesma mentira que escondeu a avaria do binario 4
REM dias. Retentar nao renova um token: quem trata disto e o Danilo, por isso trava-se a 1a.
REM CUIDADO (2026-08-01): `auth status` le o CREDENTIAL STORE. Quando a auth vem de
REM CLAUDE_CODE_OAUTH_TOKEN (env var), ha relato de que ele NAO reflete essa origem e pode dizer
REM loggedIn:false com o executor a funcionar perfeitamente. Se o preflight bloqueasse nesse caso,
REM eu proprio criava a avaria que vim consertar: loop saudavel travado por um gate que le a fonte
REM errada. Por isso: token presente => NAO bloquear. Uma auth genuinamente ma continua apanhada
REM a jusante, pela mensagem literal do executor em runtime (cli_sem_auth_linha no carteiro.sh),
REM que e' ground truth. O gate por auth status so vale quando NAO ha token no ambiente.
if defined CLAUDE_CODE_OAUTH_TOKEN (
  echo [loop] auth via CLAUDE_CODE_OAUTH_TOKEN ^(env^) -- preflight de auth ignorado de proposito
) else (
  set "AUTHJSON="
  for /f "usebackq delims=" %%A in (`"%CLAUDE_EXE%" auth status 2^>^&1`) do set "AUTHJSON=!AUTHJSON!%%A"
  echo !AUTHJSON! | find /i "\"loggedIn\": true" >nul 2>&1
  if errorlevel 1 (
    echo CLI-SEM-AUTH: sem CLAUDE_CODE_OAUTH_TOKEN e `claude auth status` nao confirma sessao -- resposta="!AUTHJSON!" binario="%CLAUDE_EXE%" utilizador=%USERDOMAIN%\%USERNAME% CLAUDE_CONFIG_DIR=%CLAUDE_CONFIG_DIR%
    exit /b 5
  )
)

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

REM PRE-VOO DE RAM v2 (2026-08-01, tarde) -- METRICA CERTA + LIMIAR MEDIDO.
REM A v1 (manha do mesmo dia) lia Win32_OperatingSystem.FreePhysicalMemory e travava abaixo de
REM 800 MB. Errado duas vezes:
REM  (1) "Free" no Windows e' mantido baixo DE PROPOSITO (o SO prefere paginas na standby list a
REM      servir de cache); pouca free e' o estado normal e nao diz nada sobre capacidade. A metrica
REM      que responde a "cabe mais um processo?" e' AVAILABLE (\Memory\Available MBytes = free +
REM      zero + standby) -- o mesmo numero que o Gestor de Tarefas mostra como "Disponivel".
REM  (2) 800 MB nunca saiu de medicao nenhuma. Custo real: a ordem-...-ffc9-aprovado foi recusada
REM      com "769MB livres" enquanto o Danilo corria 5 sessoes a mao no mesmo PC -- e um executor
REM      completou um ciclo inteiro (23 turnos, $1.16) nessas condicoes as 12:13 do mesmo dia.
REM Agora: ram-preflight.ps1 le AvailableMBytes + o headroom de COMMIT (commit esgotado e' que faz
REM a alocacao FALHAR; pouca available so faz PAGINAR -- avarias diferentes, testes separados) e
REM calibra-se pelo pico REAL gravado por executor-rss-sampler.ps1 em .claude\executor-rss.csv.
REM Continua a Lei do Pre-Voo: nao havendo memoria, NAO se sobe o claude.exe -- a ordem volta a
REM fila intacta e sem gastar tentativa (o carteiro le "ERRO: RAM insuficiente no PC").
set "PREFLIGHTPS=%~dp0ram-preflight.ps1"
set "RSSCSV=%PROJ%\.claude\executor-rss.csv"
set "RSSSAMPLERPS=%~dp0executor-rss-sampler.ps1"
set "RAMLINE="
if exist "%PREFLIGHTPS%" (
  for /f "usebackq delims=" %%R in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%PREFLIGHTPS%" -CsvPath "%RSSCSV%" 2^>^&1`) do set "RAMLINE=%%R"
  echo !RAMLINE! | find "BLOCK" >nul 2>&1
  if not errorlevel 1 (
    echo [%date% %time%] [loop] !RAMLINE! - abortar sem subir claude.exe >> "%LIVELOG%"
    echo ERRO: RAM insuficiente no PC ^(!RAMLINE!^) - tarefa nao executada, o carteiro tenta de novo.
    exit /b 7
  )
  echo [%date% %time%] [loop] !RAMLINE! >> "%LIVELOG%"
) else (
  echo [%date% %time%] [loop] AVISO: ram-preflight.ps1 ausente em "%PREFLIGHTPS%" - pre-voo de RAM SALTADO >> "%LIVELOG%"
)

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
REM CALIBRACAO DO PRE-VOO (2026-08-01) -- o sampler corre em paralelo e grava o pico REAL deste
REM executor em .claude\executor-rss.csv. E' o que tira o limiar do dominio da opiniao: a partir da
REM 1a linha, o ram-preflight.ps1 dimensiona-se pelo pior caso MEDIDO em vez de um numero redondo.
REM Auto-termina quando o claude.exe desaparece; nao escreve nada se nunca vir um executor.
set "RSSSTATE=%TEMP%\bora_rss_current.txt"
del /f /q "%RSSSTATE%" >nul 2>&1
if exist "%RSSSAMPLERPS%" (
  start "" /B powershell -NoProfile -ExecutionPolicy Bypass -File "%RSSSAMPLERPS%" -CsvPath "%RSSCSV%" -StateFile "%RSSSTATE%" -PollSeconds 3 -HardCeilingMinutes 260 -Tag loop >> "%TEMP%\bora_rss_sampler.log" 2>&1
)
REM FASE 1.4 -- stream legivel no LIVELOG + resultado final no stdout (via parser)
"%CLAUDE_EXE%" -p --append-system-prompt "%GUARD%" --output-format stream-json --verbose %MODEL% %PERM% %TURNS% %BUDGET% < "%TASKFILE%" 2>&1 | powershell -NoProfile -ExecutionPolicy Bypass -File "%PARSER%" "%LIVELOG%"
set "CLAUDE_RC=%ERRORLEVEL%"
REM CALIBRACAO -- grava a linha do CSV AQUI, nao no sampler. Quando este .cmd corre por SSH, o
REM OpenSSH mata a arvore de processos ao terminar o comando remoto e o `start /B` do sampler
REM nunca chegava ao seu proprio fim (provado: 2 corridas reais, log do sampler vazio, 0 linhas).
REM O sampler deixa o pico corrente em %RSSSTATE% a cada amostra; quem persiste e' este passo,
REM que e' sincrono e corre sempre.
if exist "%RSSSTATE%" (
  powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=(Get-Content -LiteralPath $env:RSSSTATE -ErrorAction SilentlyContinue | Select-Object -First 1); if($s){$p=$s.Split(','); if(-not (Test-Path -LiteralPath $env:RSSCSV)){Set-Content -LiteralPath $env:RSSCSV -Value 'ts,peak_ws_mb,peak_private_mb,dur_s,tag' -Encoding UTF8}; Add-Content -LiteralPath $env:RSSCSV -Value ((Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')+','+$p[0]+','+$p[1]+','+$p[2]+',loop') -Encoding UTF8; Write-Output ('[loop] RSS medido: ws='+$p[0]+'MB private='+$p[1]+'MB dur='+$p[2]+'s')}" >> "%LIVELOG%" 2>&1
  del /f /q "%RSSSTATE%" >nul 2>&1
)
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
