@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >NUL
REM ===========================================================================
REM  PONTE BORA :: CLAUDE-JUIZ do loop (carteiro -> pc-judge -> aqui)
REM  Só AVALIA: lê tarefa + saída do executor e devolve UMA linha de veredito.
REM  Read-only (nunca edita/executa). Teto baixo (haiku, budget 1, 3 turns).
REM ===========================================================================
set "CLAUDE_CONFIG_DIR=C:\Users\danil\.claude"
set "CLAUDE_EXE=C:\Users\danil\AppData\Roaming\npm\node_modules\@anthropic-ai\claude-code\bin\claude.exe"
set "PROJ=C:\Users\danil\Desktop\projetosflutter\bora_app"
if not exist "%CLAUDE_EXE%" ( echo [juiz] ERRO: claude.exe nao encontrado & exit /b 4 )

set "MODEL=--model haiku"
set "GUARD=Es o CLAUDE-JUIZ de qualidade do Bora. NAO edites nem executes nada - so avalias. Le a TAREFA e a SAIDA do executor. Decide se a saida cumpre a tarefa com qualidade (funcional, correto, sem efeitos colaterais, sem tocar zona vermelha). Responde EXATAMENTE UMA linha, comecando por 'VEREDITO: APROVADA' (se cumpre) ou 'VEREDITO: CORRIGIR: <o que corrigir numa frase>' (se falha). Nada mais, sem explicacoes extra."

cd /d "%PROJ%" || ( echo [juiz] ERRO: projeto nao encontrado & exit /b 3 )

if /I "%~1"=="--b64" (
  set "BORA_B64=%~2"
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
echo [juiz] ERRO: uso: run-claude-judge.cmd --b64 ^<BASE64^>
exit /b 2
