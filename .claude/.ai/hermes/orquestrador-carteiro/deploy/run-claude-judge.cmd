@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >NUL
REM ===========================================================================
REM  PONTE BORA :: CLAUDE-JUIZ do loop (carteiro -> pc-judge -> aqui)
REM  Só AVALIA: lê tarefa + saída do executor e devolve UMA linha de veredito.
REM  Read-only (nunca edita/executa). Teto baixo (haiku, budget 1, 3 turns).
REM ===========================================================================
set "CLAUDE_CONFIG_DIR=C:\Users\danil\.claude"
REM FASE 1.11 (2026-08-01) -- MESMA resolucao dinamica do run-claude-loop.cmd.
REM Esta linha esteve com o caminho npm HARDCODED e MORTO ate hoje: a FASE 1.11 corrigiu o
REM executor e ESQUECEU o juiz. Consequencia: desde 27/07 o juiz abortava sempre em "claude.exe
REM nao encontrado" -> nunca devolvia VEREDITO -> as ordens levavam JUIZ-SEM-VEREDITO e o
REM carteiro reabria-as, repetindo trabalho JA FEITO (provado: ordem 054224-aplic correu 3x).
REM Pior: a mensagem antiga comecava por "[juiz]", e o clean() do carteiro.sh filtra as linhas
REM ^\[juiz\] -- ou seja, o erro era APAGADO antes de chegar ao diagnostico. Por isso agora
REM emite-se CLI-NAO-ENCONTRADA (nao filtrado, e o carteiro trava com essa nota exata).
set "RESOLVEPS=%~dp0resolve-claude-exe.ps1"
set "CLAUDE_EXE="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%RESOLVEPS%" 2^>nul`) do if not defined CLAUDE_EXE set "CLAUDE_EXE=%%I"
set "PROJ=C:\Users\danil\Desktop\projetosflutter\bora_app"
if not defined CLAUDE_EXE (
  echo CLI-NAO-ENCONTRADA: juiz nao resolveu o binario -- utilizador=%USERDOMAIN%\%USERNAME% APPDATA=%APPDATA%
  exit /b 4
)
if not exist "%CLAUDE_EXE%" (
  echo CLI-NAO-ENCONTRADA: juiz resolveu "%CLAUDE_EXE%" mas o ficheiro nao existe -- utilizador=%USERDOMAIN%\%USERNAME%
  exit /b 4
)

set "MODEL=--model haiku"
set "GUARD=Es o CLAUDE-JUIZ de qualidade do Bora. NAO edites nem executes nada - so avalias. Le a TAREFA e a SAIDA do executor. Decide se a saida cumpre a tarefa com qualidade (funcional, correto, sem efeitos colaterais, sem tocar zona vermelha). Responde EXATAMENTE UMA linha, comecando por 'VEREDITO: APROVADA' (se cumpre) ou 'VEREDITO: CORRIGIR: <o que corrigir numa frase>' (se falha). Nada mais, sem explicacoes extra."

cd /d "%PROJ%" || ( echo [juiz] ERRO: projeto nao encontrado & exit /b 3 )

REM --b64stdin (2026-08-01): o prompt do juiz chega por STDIN, nao como argumento CLI.
REM O pc-loop ja fazia isto desde 2026-07-10 (args >~1KB rebentavam o comando remoto do ssh no
REM Windows); o pc-judge ficou para tras a passar --b64 <BASE64> na linha de comando. O prompt do
REM juiz leva a TAREFA + 50 linhas da saida do executor -- cresce facilmente para la do limite.
if /I "%~1"=="--b64stdin" (
  set "BORA_B64="
  for /f "usebackq delims=" %%L in (`more`) do set "BORA_B64=!BORA_B64!%%L"
  goto :decodifica
)
if /I "%~1"=="--b64" (
  set "BORA_B64=%~2"
  goto :decodifica
)
echo [juiz] ERRO: uso: run-claude-judge.cmd --b64stdin ^(prompt por STDIN^) ^| --b64 ^<BASE64^>
exit /b 2

:decodifica
if defined BORA_B64 (
  powershell -NoProfile -Command "$b=$env:BORA_B64; $b=$b.PadRight([math]::Ceiling($b.Length/4)*4,'='); [IO.File]::WriteAllText($env:TEMP + '\bora_judge_task.txt', [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)))" || ( echo [juiz] ERRO base64 & exit /b 5 )
  REM ---- CHAO MECANICO (2026-07-15): verifica git/disco ANTES do juiz textual. ----
  REM ---- Reprova mecanica ja imprime VEREDITO: CORRIGIR (rc=2). Crash = fail-closed. ----
  powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0juiz-mecanico.ps1" "%TEMP%\bora_judge_task.txt"
  set "MRC=!ERRORLEVEL!"
  if "!MRC!"=="2" exit /b 0
  if not "!MRC!"=="0" ( echo VEREDITO: CORRIGIR: juiz-mecanico falhou rc=!MRC! - fail-closed, nada aprovado sem chao mecanico & exit /b 0 )
  REM ---- juiz textual (Haiku) com 1 retry se nao devolver linha VEREDITO ----
  "%CLAUDE_EXE%" -p --append-system-prompt "%GUARD%" --output-format text %MODEL% --disallowedTools "Bash Edit Write MultiEdit WebFetch WebSearch Task" --max-turns 5 --max-budget-usd 1 < "%TEMP%\bora_judge_task.txt" > "%TEMP%\bora_judge_verdict.txt" 2>&1
  findstr /I "VEREDITO:" "%TEMP%\bora_judge_verdict.txt" >NUL || "%CLAUDE_EXE%" -p --append-system-prompt "%GUARD%" --output-format text %MODEL% --disallowedTools "Bash Edit Write MultiEdit WebFetch WebSearch Task" --max-turns 5 --max-budget-usd 1 < "%TEMP%\bora_judge_task.txt" > "%TEMP%\bora_judge_verdict.txt" 2>&1
  type "%TEMP%\bora_judge_verdict.txt"
  exit /b 0
)
echo [juiz] ERRO: base64 vazio
exit /b 2
