@echo off
setlocal EnableExtensions EnableDelayedExpansion
chcp 65001 >NUL
REM ---------------------------------------------------------------------------
REM FIX 2026-09-05 (sessao tudo-05-09-mao) -- O JUIZ REPROVAVA TRABALHO BEM FEITO.
REM Causa MEDIDA: o prompt vinha por stdin em base64 e era acumulado numa variavel do
REM cmd. As variaveis do cmd tem tecto de 8191 caracteres. Teste com 22.593 bytes:
REM     COMPRIMENTO_ACUMULADO=8160  ->  chegaram 6120 bytes de 22593 (27%)
REM     linhas com "C:": 202 -> 55 ; o FIM do prompt NUNCA chegou.
REM O juiz julgava so o principio da ordem, nunca via a saida do executor nem a prova,
REM e dava CORRIGIR a ordens boas ate esgotar as tentativas.
REM O pc-loop resolveu isto em 2026-07-10 (le com PowerShell e escreve DIRECTO no
REM ficheiro, sem variavel nenhuma). O juiz ficou para tras. Agora faz o mesmo.
REM ---------------------------------------------------------------------------
if /I "%~1"=="--b64stdin" powershell -NoProfile -Command "$b=[Console]::In.ReadToEnd() -replace '[^A-Za-z0-9+/=]',''; $b=$b.TrimEnd('='); $b=$b.PadRight([math]::Ceiling($b.Length/4)*4,'='); [IO.File]::WriteAllText($env:TEMP + '\bora_judge_task.txt', [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)))"
REM ===========================================================================
REM  PONTE BORA :: JUIZ do loop (carteiro -> pc-judge -> aqui)
REM  So AVALIA: le tarefa + saida do executor e devolve UMA linha de veredito.
REM  Read-only (nunca edita/executa).
REM
REM  2026-08-11 -- JUIZ FORTE (decisao do Danilo). Ordem de avaliacao:
REM    1) juiz-mecanico.ps1   (chao determinista: git/disco. Reprova mecanica manda.)
REM    2) juiz-go.ps1         (qwen3.8-max no plano OpenCode Go -- custo fixo JA PAGO,
REM                            nao gasta o plano Claude, teto de tokens PROPORCIONAL
REM                            ao tamanho do que tem de ler, 3 tentativas internas)
REM    3) Claude opus         (SO se o Go estiver em baixo -- recurso, nao rotina)
REM    4) diagnostica-juiz.ps1 (escolhe a linha VEREDITO; se nao houver, NOMEIA a causa
REM                            medida em vez de deixar o carteiro adivinhar)
REM
REM  PORQUE ISTO MUDOU: o juiz corria `--model haiku --max-turns 5 --max-budget-usd 1`.
REM  NOTA DE HONESTIDADE: as 321 ordens historicas com JUIZ-SEM-VEREDITO NAO foram culpa do
REM  haiku -- foram a avaria de 25-31/07 em que este .cmd tinha o caminho da CLI hardcoded e
REM  MORTO (ver bloco FASE 1.11 abaixo); zero ocorrencias desde 01/08. A troca para um modelo
REM  forte e' na mesma a decisao certa (haiku a arbitrar saidas grandes e' fraco, e 4 das 6
REM  ordens travadas desde 01/08 sao rejeicoes de CONTEUDO do juiz), mas nao se venda como
REM  o conserto daquela avaria -- essa ja estava consertada.
REM ===========================================================================
set "CLAUDE_CONFIG_DIR=C:\Users\danil\.claude"
REM FASE 1.11 (2026-08-01) -- MESMA resolucao dinamica do run-claude-loop.cmd.
REM Esta linha esteve com o caminho npm HARDCODED e MORTO: a FASE 1.11 corrigiu o executor e
REM ESQUECEU o juiz. Consequencia: de 27/07 a 01/08 o juiz abortava sempre em "claude.exe nao
REM encontrado" -> nunca devolvia VEREDITO -> JUIZ-SEM-VEREDITO e o carteiro reabria as ordens,
REM repetindo trabalho JA FEITO (provado: ordem 054224-aplic correu 3x).
REM Pior: a mensagem antiga comecava por "[juiz]", e o clean() do carteiro.sh filtra as linhas
REM ^\[juiz\] -- ou seja, o erro era APAGADO antes de chegar ao diagnostico. Por isso agora
REM emite-se CLI-NAO-ENCONTRADA (nao filtrado, e o carteiro trava com essa nota exata).
set "RESOLVEPS=%~dp0resolve-claude-exe.ps1"
set "CLAUDE_EXE="
for /f "usebackq delims=" %%I in (`powershell -NoProfile -ExecutionPolicy Bypass -File "%RESOLVEPS%" 2^>nul`) do if not defined CLAUDE_EXE set "CLAUDE_EXE=%%I"
REM MELHORIA PC-NOVO 2026-08-31: usar o claude.cmd do npm (o cmd.exe nao corre o .ps1 direto).
if /I "%CLAUDE_EXE:~-4%"==".ps1" if exist "%APPDATA%\npm\claude.cmd" set "CLAUDE_EXE=%APPDATA%\npm\claude.cmd"
if not defined CLAUDE_EXE if exist "%APPDATA%\npm\claude.cmd" set "CLAUDE_EXE=%APPDATA%\npm\claude.cmd"
set "PROJ=C:\BoraLocal\projetosflutter\bora_app"
set "JUIZGO=%~dp0juiz-go.ps1"

set "GUARD=Es o CLAUDE-JUIZ de qualidade do Bora. NAO edites nem executes nada - so avalias. Le a TAREFA e a SAIDA do executor. Decide se a saida cumpre a tarefa com qualidade (funcional, correto, sem efeitos colaterais, sem tocar zona vermelha). Se o executor fez o trabalho mas foi honesto sobre uma limitacao, isso NAO e falha. Responde EXATAMENTE UMA linha, comecando por 'VEREDITO: APROVADA' (se cumpre) ou 'VEREDITO: CORRIGIR: <o que corrigir numa frase>' (se falha). Nada mais, sem explicacoes extra."

cd /d "%PROJ%" || ( echo [juiz] ERRO: projeto nao encontrado & exit /b 3 )

REM --b64stdin (2026-08-01): o prompt do juiz chega por STDIN, nao como argumento CLI.
REM O pc-loop ja fazia isto desde 2026-07-10 (args >~1KB rebentavam o comando remoto do ssh no
REM Windows); o pc-judge ficou para tras a passar --b64 <BASE64> na linha de comando. O prompt do
REM juiz leva a TAREFA + saida do executor -- cresce facilmente para la do limite.
if /I "%~1"=="--b64stdin" (
  REM ja foi lido e descodificado no topo deste ficheiro (fix 2026-09-05).
  if not exist "%TEMP%\bora_judge_task.txt" ( echo [juiz] ERRO: base64stdin ^(prompt vazio^) & exit /b 5 )
  goto :apos_decodifica
)
REM --jaentregue (2026-09-05, sessao fila-ganho-05-09): O PROMPT JA ESTA EM DISCO.
REM Causa que isto conserta: mandar o prompt pelo STDIN emperra acima de ~2 KB de
REM base64 -- o pipe entre o ssh e o cmd.exe enche, ninguem drena, e a ligacao
REM morre 180s depois com "Timeout, server ... not responding", sem o .cmd chegar
REM a escrever o ficheiro da tarefa. Medido por bisseccao a 2026-09-05: prompt de
REM 977 B da veredito em 6s; de 2249 B em diante, emperra sempre. Era esta a causa
REM real dos JUIZ-SEM-VEREDITO em ordens grandes -- nao o tecto de tempo, que nem
REM chega a disparar. Agora a ponte entrega o ficheiro por scp (aguenta 57 KB em
REM 1s, medido) e chama isto sem stdin.
if /I "%~1"=="--jaentregue" (
  if not exist "%TEMP%\bora_judge_task.txt" ( echo [juiz] ERRO: jaentregue mas o ficheiro da tarefa nao existe & exit /b 5 )
  goto :apos_decodifica
)
if /I "%~1"=="--b64" (
  set "BORA_B64=%~2"
  goto :decodifica
)
echo [juiz] ERRO: uso: run-claude-judge.cmd --b64stdin ^(prompt por STDIN^) ^| --b64 ^<BASE64^>
exit /b 2

:decodifica
if not defined BORA_B64 ( echo [juiz] ERRO: base64 vazio & exit /b 2 )
powershell -NoProfile -Command "$b=$env:BORA_B64; $b=$b.PadRight([math]::Ceiling($b.Length/4)*4,'='); [IO.File]::WriteAllText($env:TEMP + '\bora_judge_task.txt', [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($b)))" || ( echo [juiz] ERRO base64 & exit /b 5 )

:apos_decodifica

REM ---- 1) CHAO MECANICO (2026-07-15): verifica git/disco ANTES de qualquer juiz textual. ----
REM ---- Reprova mecanica ja imprime VEREDITO: CORRIGIR (rc=2). Crash = fail-closed. ----
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0juiz-mecanico.ps1" "%TEMP%\bora_judge_task.txt"
set "MRC=!ERRORLEVEL!"
if "!MRC!"=="2" exit /b 0
if not "!MRC!"=="0" ( echo VEREDITO: CORRIGIR: juiz-mecanico falhou rc=!MRC! - fail-closed, nada aprovado sem chao mecanico & exit /b 0 )

REM apagar SEMPRE as saidas antes de correr: um ficheiro velho de uma corrida anterior seria
REM lido como veredito desta -- aprovacao fantasma. Fail-closed comeca por aqui.
del /q "%TEMP%\bora_judge_v0.txt" "%TEMP%\bora_judge_v1.txt" "%TEMP%\bora_judge_v2.txt" 2>NUL

REM ---- 2) JUIZ FORTE no plano Go (rotina) ----
if exist "%JUIZGO%" (
  powershell -NoProfile -ExecutionPolicy Bypass -File "%JUIZGO%" -TaskFile "%TEMP%\bora_judge_task.txt" > "%TEMP%\bora_judge_v0.txt" 2>"%TEMP%\bora_judge_go.err"
  findstr /I "VEREDITO:" "%TEMP%\bora_judge_v0.txt" >NUL && (
    type "%TEMP%\bora_judge_v0.txt"
    exit /b 0
  )
  echo [juiz] Go sem veredito - caio no Claude. Diagnostico do Go: 1>&2
  type "%TEMP%\bora_judge_go.err" 1>&2
) else (
  echo [juiz] AVISO: juiz-go.ps1 ausente em "%JUIZGO%" - vou direto ao Claude 1>&2
)

REM ---- 3) RECURSO: Claude opus, so quando o Go nao se pronunciou ----
REM Se a CLI tambem nao existe, nao ha 3o nem 4o passo: diz-se a causa exata (nao filtrada
REM pelo clean() do carteiro) em vez de devolver silencio.
if not defined CLAUDE_EXE (
  echo CLI-NAO-ENCONTRADA: juiz nao resolveu o binario e o Go nao respondeu -- utilizador=%USERDOMAIN%\%USERNAME% APPDATA=%APPDATA%
  exit /b 4
)
if not exist "%CLAUDE_EXE%" (
  echo CLI-NAO-ENCONTRADA: juiz resolveu "%CLAUDE_EXE%" mas o ficheiro nao existe e o Go nao respondeu -- utilizador=%USERDOMAIN%\%USERNAME%
  exit /b 4
)
REM Tetos mais largos que os antigos (haiku/5/1): isto agora e' excecao, nao rotina, e um juiz
REM que rebenta o teto a meio e nao se pronuncia custa MUITO mais caro do que a diferenca.
"%CLAUDE_EXE%" -p --append-system-prompt "%GUARD%" --output-format text --model opus --disallowedTools "Bash Edit Write MultiEdit WebFetch WebSearch Task" --max-turns 8 --max-budget-usd 3 < "%TEMP%\bora_judge_task.txt" > "%TEMP%\bora_judge_v1.txt" 2>&1
findstr /I "VEREDITO:" "%TEMP%\bora_judge_v1.txt" >NUL || "%CLAUDE_EXE%" -p --append-system-prompt "%GUARD%" --output-format text --model opus --disallowedTools "Bash Edit Write MultiEdit WebFetch WebSearch Task" --max-turns 8 --max-budget-usd 3 < "%TEMP%\bora_judge_task.txt" > "%TEMP%\bora_judge_v2.txt" 2>&1

REM ---- 4) diagnostico: escolhe a linha VEREDITO; senao NOMEIA a causa (nunca inventa veredito)
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0diagnostica-juiz.ps1" -A "%TEMP%\bora_judge_v1.txt" -B "%TEMP%\bora_judge_v2.txt"
exit /b 0
