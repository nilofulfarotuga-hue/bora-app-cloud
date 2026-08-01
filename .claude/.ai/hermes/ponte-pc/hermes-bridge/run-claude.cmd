@echo off
setlocal EnableExtensions
chcp 65001 >NUL
REM ===========================================================================
REM  PONTE BORA :: Hermes (VPS) -> SSH no PC -> Claude Code headless (worker)
REM
REM  FORMA ROBUSTA (recomendada, tarefas longas / aspas / quebras de linha):
REM    -> a tarefa vem por STDIN (o cmd.exe NAO a interpreta). Ex. via SSH:
REM         ssh ... hermes@PC "C:\...\run-claude.cmd" <<'BORA_TASK'
REM         <a tarefa do Danilo, varias linhas, "aspas", :, %, ! ...>
REM         BORA_TASK
REM
REM  FORMA SIMPLES (fallback, tarefas curtas sem caracteres especiais):
REM         run-claude.cmd lista os ficheiros do projeto bora
REM
REM  AUTONOMIA TOTAL por defeito (--dangerously-skip-permissions, sem prompts).
REM  Modo seguro pontual: set BORA_BRIDGE_SAFE=1 (acceptEdits). --max-turns 20 = trava custo.
REM ===========================================================================

REM --- Auth partilhada: aponta para a config/credenciais do user danil ---
set "CLAUDE_CONFIG_DIR=C:\Users\danil\.claude"
REM FASE 1.11 (2026-08-01) — TERCEIRO ficheiro com o caminho npm morto, encontrado na auditoria
REM que o Danilo mandou fazer depois de o mesmo bug ter existido em DOIS sitios e so um ter sido
REM corrigido (4 dias de avaria silenciosa). Este nao tem chamador vivo na cadeia de orquestracao,
REM mas continua invocavel a mao — e morreria exatamente da mesma maneira. Resolucao dinamica pelo
REM helper partilhado; nunca caminho fixo, nunca versao fixa.
REM O prefixo antigo "[ponte]" era FILTRADO pelo clean() do carteiro.sh (^\[ponte\]) — o mesmo
REM mecanismo que apagou o erro do juiz. Agora emite CLI-NAO-ENCONTRADA, que nao e' filtrado.
set "RESOLVEPS=%~dp0resolve-claude-exe.ps1"
set "CLAUDE_EXE="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%RESOLVEPS%" 2^>nul`) do if not defined CLAUDE_EXE set "CLAUDE_EXE=%%I"
set "PROJ=C:\Users\danil\Desktop\projetosflutter\bora_app"

if not exist "%CLAUDE_EXE%" (
  echo CLI-NAO-ENCONTRADA: ponte partilhada nao resolveu o binario -- utilizador=%USERDOMAIN%\%USERNAME% APPDATA=%APPDATA%
  exit /b 4
)

REM --- Permissoes: AUTONOMIA TOTAL por defeito (faz tudo sem prompts).
REM     BORA_BRIDGE_SAFE=1 volta ao modo seguro (leitura + edits, sem bash) ---
set "PERM=--dangerously-skip-permissions"
if "%BORA_BRIDGE_SAFE%"=="1" set "PERM=--permission-mode acceptEdits"

REM --- Modelo: Opus 4.8 por defeito; override com BORA_MODEL=<id> ---
set "MODEL=--model opus"
if defined BORA_MODEL set "MODEL=--model %BORA_MODEL%"

REM --- Guarda de seguranca injectada em TODO o pedido (texto fixo, sem stdin) ---
set "GUARD=Estas a correr em modo headless via ponte SSH remota (Hermes), sem canal interactivo com o Danilo. MODO PADRAO = AGIR: executa a tarefa toda sozinho, do principio ao fim, e toma todas as decisoes REVERSIVEIS por conta propria, sem perguntar e sem devolver perguntas tecnicas. Nunca pecas confirmacao para algo que se possa reverter; investiga e resolve tu. So PARAS quando a acao for IRREVERSIVEL ou da Lista Vermelha do Bora: operacoes destrutivas (apagar dados, branches, force-push), financeiras (Stripe, dinheiro, pagamentos, payouts), migrations destrutivas, RLS/auth/roles, disparos em massa, builds de producao, ou ficheiros sensiveis (dispatch_engine, pricing, triggers financeiros). Nesses casos NAO executes: responde apenas com UMA linha a comecar por CONFIRMACAO NECESSARIA: descrevendo o que precisa de aprovacao do Danilo. Nao facas commit nem push sem pedido explicito. Nunca imprimas senhas, tokens ou credenciais. No fim devolve um RESULTADO claro e conciso em PT-BR: o que fizeste e o desfecho."

cd /d "%PROJ%" || (echo [ponte] ERRO: projeto nao encontrado em %PROJ% & exit /b 3)

REM --- TRANSPORTE BASE64 (robusto): pc envia  run-claude.cmd --b64 <BASE64>
REM     A tarefa viaja em base64 (so A-Z a-z 0-9 + / =), imune a aspas, crase,
REM     aspas curvas, dois-pontos, %, !, espacos. Descodifica-se SO aqui no PC. ---
if /I "%~1"=="--b64" (
  set "BORA_B64=%~2"
  REM cmd.exe corta '=' (delimitador) -> o pc envia base64 SEM padding; re-pomos aqui.
  powershell -NoProfile -Command "$b=$env:BORA_B64; $b=$b.PadRight([math]::Ceiling($b.Length/4)*4,'='); [IO.File]::WriteAllText($env:TEMP + '\bora_task.txt', [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)))" || (echo [ponte] ERRO: falha a descodificar base64 & exit /b 5)
  "%CLAUDE_EXE%" -p --append-system-prompt "%GUARD%" --output-format text %MODEL% %PERM% --max-turns 20 < "%TEMP%\bora_task.txt"
  exit /b %ERRORLEVEL%
)

set "PROMPT=%*"
if defined PROMPT (
  REM --- Tarefa por argumento. %* JA inclui as aspas do chamador, por isso NAO
  REM     se voltam a por aspas (evita aspas duplicadas que truncavam a tarefa). ---
  "%CLAUDE_EXE%" -p %PROMPT% --append-system-prompt "%GUARD%" --output-format text %MODEL% %PERM% --max-turns 20 <NUL
) else (
  REM --- Robusto: tarefa lida do STDIN (claude -p usa o stdin como prompt) ---
  "%CLAUDE_EXE%" -p --append-system-prompt "%GUARD%" --output-format text %MODEL% %PERM% --max-turns 20
)
exit /b %ERRORLEVEL%
