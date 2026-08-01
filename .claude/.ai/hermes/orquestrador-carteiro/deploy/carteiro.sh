#!/bin/bash
# carteiro.sh — dispatcher determinístico do loop de orquestração (corre no HOST do VPS).
# Campainha -> este script -> pc-loop (executor) + pc-judge (juiz) -> escreve na fila.
#
# PAREDES DE SEGURANÇA (por ordem em que travam):
#   STOP-TOTAL     .pausa-total          -> Danilo trava TUDO (carteiro+campainha+crons)
#   PAUSA-RL       .pausa-rate-limit      -> automática; conta Claude no limite; retoma no reset
#   T5 kill switch _controlo.md           -> orquestracao_enabled: true|false
#   T3 zona verm.  zona_vermelha()        -> dinheiro + intenção de escrita -> humano
#   T1 teto 5      tentativa>=5           -> travada
#   T2/T4          budget/turns/tools nos .cmd do PC
#
# REENGENHARIA 2026-07-12 (ver inbox/reengenharia-esteira-2026-07-12.md):
#   • nota NUNCA vazia — todo ramo de falha grava causa (RATE-LIMIT/TIMEOUT-3600s/SAIDA-VAZIA/
#     JUIZ-SEM-VEREDITO). Antes: falha do juiz -> nota "" e a causa perdia-se.
#   • rate-limit inteligente — "hit your session limit" NÃO gasta tentativa; pausa a fila até ao
#     reset (.pausa-rate-limit), avisa 1x no Telegram, retoma sozinho.
#   • TIMEOUT não re-tenta 5x — após 2 timeouts a ordem trava com sugestão de DIVIDIR.
#   • encadeamento de missão — ordem com campo `missao:` que fecha aprovada marca o passo e
#     dispara o(s) seguinte(s). Telegram só em: missão concluída / dinheiro / missão travada.
#     Ordem normal (sem missão) aprovada = SILÊNCIO (nada de aviso por passo).
#
# ---- REGRA DE TAMANHO DE ORDEM (anti rate-limit) — ver orquestracao/convencoes.md ----
#   1 ordem = 1 objetivo pequeno (≤15 min de trabalho). Trabalho grande = PÁGINA DE MISSÃO
#   com passos pequenos encadeados. Tarefa que estoura 900s -> TIMEOUT + sugestão de dividir,
#   NUNCA a mesma coisa 5x.
#
# PARTE A (2026-07-16, pos-morte ordem 7838, pedido Danilo): o `timeout 3600` fixo do pc_exec
#   matou a 7838 2x nos testes finais enquanto ela ainda produzia output real — o relógio total
#   não distingue "morta" de "grande mas viva". A deteção real de INATIVIDADE agora corre do
#   lado do PC (stale-output-watchdog.ps1, em paralelo ao claude.exe): só mata se o LIVELOG
#   ficar 20min SEM crescer; teto duro de 4h fica como rede de segurança final. O `timeout`
#   aqui no VPS passou a ser só a rede de segurança EXTERNA (bridge/SSH pendurado), alargado
#   para acompanhar o teto duro de 4h + folga — nunca deve disparar primeiro. Quando o vigia do
#   PC mata, devolve "MOTIVO_KILL:INATIVIDADE:Xmin" ou "MOTIVO_KILL:TETO-DURO:Xmin" no stdout;
#   ver pc_exec() e a leitura de $motivo_kill mais abaixo — nunca mais "TIMEOUT-3600s" genérico.
set -u
C=hermes-agent-fvnc-hermes-agent-1
HOSTDATA=/docker/hermes-agent-fvnc/data
FILA="$HOSTDATA/cortex-brain/orquestracao"
CTRL="$FILA/_controlo.md"
LOG=/root/orquestracao/carteiro.log
LOCK=/root/orquestracao/.carteiro.lock
PAUSA_TOTAL="$FILA/.pausa-total"           # STOP global (Danilo)
PAUSA_RL="$FILA/.pausa-rate-limit"         # pausa automática por rate-limit (guarda epoch de retoma)
RL_AVISADO=/root/orquestracao/.rate-limit.avisado
# PARIDADE PARTE 2.2 (2026-08-01): ordens que CONCLUÍRAM mas cujo juiz não devolveu veredito.
# Vão para aqui (revisão humana no daily-pulse) em vez de `travada` + Telegram — não é travamento,
# é revisão em falta. Formato: <ts>\t<id ordem>\t<motivo>.
REVISAO_PENDENTE=/root/orquestracao/revisao-pendente.tsv
# I4: travadas NÃO-vermelhas arquivadas aqui em vez de Telegram (revistas no daily-pulse).
ARQUIVO_TRAVADAS=/root/orquestracao/travadas-arquivadas.tsv
FILA_ESTADO=/root/orquestracao/.fila-estado   # transição ocupado<->vazio (2026-07-16, substitui f523):
                                               # linha1=ocupada|vazia, linha2=epoch do último aviso (cooldown 30min)

# T3 money-filter. -iE (case-insensitive). 2026-07-11: menos sensível a PALAVRAS
# (ver wiki/licoes/classificador-zona-menos-sensivel-a-palavras.md). Vermelho exige INTENÇÃO
# DE ESCRITA: RED_ALWAYS = destrutivo por si só; RED_TERMS = domínio $; WRITE_INTENT = verbo de
# escrita; NEG = tira 'sem corrigir'/'nao alterar' antes do teste. Proteção real intacta.
RED_ALWAYS='disable row level|--force|force.?with.?lease|reset .*--hard|force.?push'
RED_TERMS='dispatch_engine|pricing_service|finalizePurchase|bora[ _]tokens?|tokens?_applied|tvde[a-z_ ]*tokens?|stripe|payment|webhook|wallet|ledger|refund|payout|commission|platform_settings'
WRITE_INTENT='mud(a|ar|e|ei|ou|anca|ança)|atualiz|altera|modific|mexer?|edita|reescrev|refator|aplica|grava|escrev|deploy|remov|apaga|dropa|insere|inserir|configura|corrig|ajusta|\b(UPDATE|INSERT|DELETE|ALTER|DROP|TRUNCATE)\b'
NEG='(sem|nao|não|nunca|jamais) +[a-zàáâãéêíóôõúç]+'
zona_vermelha(){ # $1=tarefa -> 0 (vermelho) / 1 (verde)
  local limpo; limpo=$(printf '%s' "$1" | sed -E "s/$NEG//gi")
  echo "$1" | grep -iqE "$RED_ALWAYS" && return 0
  echo "$1" | grep -iqE "$RED_TERMS" && echo "$limpo" | grep -iqE "$WRITE_INTENT" && return 0
  return 1
}

resultado_1linha(){ # $1=saida -> "Uma linha final: X" se existir, senão a última linha não vazia
  local r
  r=$(printf '%s' "$1" | grep -iE '^Uma linha final:' | tail -1 | sed -E 's/^Uma linha final: *//I' | tr -d '\r')
  [ -n "$r" ] && { echo "$r"; return; }
  printf '%s' "$1" | grep -vE '^[[:space:]]*$' | tail -1 | tr -d '\r'
}
resumo_tarefa(){ # $1=tarefa completa -> resumo curto p/ Telegram (sem prefixos [MODELO:.../[PROPOSE-ONLY:...])
  printf '%s' "$1" | sed -E 's/^(\[MODELO:[^]]*\] *)?(\[PROPOSE-ONLY:[^]]*\] *)?//' | cut -c1-160
}
ts(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }
get(){ grep -E "^$1:" "$2" 2>/dev/null | head -1 | sed "s/^$1: *//" | tr -d '\r'; }
setf(){ if grep -qE "^$1:" "$3"; then sed -i "s|^$1:.*|$1: $2|" "$3"; else echo "$1: $2" >> "$3"; fi; }
notify(){ docker exec -u hermes "$C" hermes send -t telegram "$1" >/dev/null 2>&1 || log "notify(best-effort) falhou"; }
# clean() — remove RUÍDO da saída das pontes, NUNCA erros.
#
# AUDITORIA 2026-08-01 (ordem do Danilo, depois de o clean() ter apagado a prova do juiz morto):
# a versão antiga era `grep -vE '^\[ponte\]|^\[loop\]|^\[juiz\]|…'` — descartava a linha INTEIRA
# por prefixo. Contagem real do que isso comia:
#   [ponte] 2 linhas vivas -> 2 são ERRO   (projeto não encontrado, falha base64)
#   [juiz]  4 linhas vivas -> 4 são ERRO   (incl. "claude.exe nao encontrado" — 4 dias escondido)
#   [loop]  5 linhas vivas -> 4 são ERRO
# Ou seja: um filtro de ruído que comia quase só diagnóstico. Foi assim que o juiz morto passou
# despercebido — o erro existia, era emitido, e era apagado antes de chegar ao diagnóstico.
# É a mesma classe de bug da nota "tarefa grande demais": esconde a causa e manda procurar no
# sítio errado.
#
# Regra nova: linha com prefixo de ponte só é descartada se NÃO contiver ERRO. Tudo o que cheire
# a erro passa. Os dois padrões de ruído genuíno (avisos de regra de permissão e "matches no
# known tool") continuam a ser removidos — esses não são diagnóstico de nada.
clean(){
  awk '
    /^\[(ponte|loop|juiz)\]/ { if ($0 ~ /ERRO/) print; next }
    /Permission deny rule|matches no known tool/ { next }
    { print }
  '
}
sync_espelho(){ docker exec -u hermes -e HOME=/opt/data -i "$C" sh -s fast < /root/cortex-mcp/sync-brain.sh >> "$LOG" 2>&1 && log "espelho sincronizado (fast)" || log "sync espelho (best-effort) falhou"; }

# PARTE B (2026-07-17) — verifica, CONTRA A BASE (nunca contra o ficheiro), que um
# audit_id do frontmatter existe MESMO como aprovação de proposta vermelha. Usa a
# RPC read-only cortex_verify_audit_id (anon) via o container (mesmas creds do sync).
# Devolve 0 (ok) só se a base disser "true". Qualquer falha/dúvida -> 1 (não autoriza).
audit_id_valido(){ # $1=audit_id
  local aid="$1" r
  case "$aid" in ''|*[!0-9a-fA-F-]*) return 1;; esac   # sanidade: só uuid-like
  r=$(docker exec -u hermes -e AID="$aid" "$C" sh -lc '
    U=$(sed -n "s/^SUPABASE_URL=//p" /opt/data/.env | head -1 | tr -d "\r\"")
    K=$(sed -n "s/^SUPABASE_ANON_KEY=//p" /opt/data/.env | head -1 | tr -d "\r\"")
    [ -n "$U" ] && [ -n "$K" ] || exit 3
    curl -s --max-time 12 -X POST "$U/rest/v1/rpc/cortex_verify_audit_id" \
      -H "apikey: $K" -H "Authorization: Bearer $K" -H "Content-Type: application/json" \
      -d "{\"p_audit_id\":\"$AID\"}"
  ' 2>/dev/null)
  [ "$r" = "true" ]
}

# FASE 4 (2026-07-17): ao marcar zona_vermelha, surfaca a ordem VERMELHA NOVA na Central (tab Cortex)
# escrevendo uma linha em proposals.jsonl -- o MESMO caminho do claude.ai/cortex_propor (nao inventa
# caminho novo). NAO toca zona_vermelha()/classificador/Lista Vermelha; so torna a ordem aprovavel.
# Salvaguardas: (1) salta ids -aprovado (ja vieram da Central -> decisao 7398), (2) idempotente por
# pid deterministico + grep (nao duplica a cada re-marcacao), (3) JSON via python (tarefa tem aspas/emoji).
PROPOSALS_JSONL="${PROPOSALS_JSONL:-$HOSTDATA/cortex-brain/.claude/.ai/knowledge/inbox/_reports/proposals.jsonl}"
surfacar_na_central(){  # $1=order_id  $2=tarefa
  local oid="$1" pid="prop-carteiro-$1"
  case "$oid" in *-aprovado) return 0;; esac
  [ -f "$PROPOSALS_JSONL" ] || { log "ordem $oid: proposals.jsonl ausente -- nao surfaco na Central"; return 0; }
  grep -q "\"pid\": *\"$pid\"" "$PROPOSALS_JSONL" 2>/dev/null && return 0
  if OID="$oid" PID="$pid" TAREFA="$2" python3 -c 'import json,os,datetime; print(json.dumps({"pid":os.environ["PID"],"id":os.environ["OID"],"tipo":"ordem_orquestracao","zona":"vermelha","tarefa":os.environ["TAREFA"],"who":"carteiro","ts":datetime.datetime.utcnow().strftime("%Y-%m-%dT%H:%M:%S.000Z")}, ensure_ascii=False))' >> "$PROPOSALS_JSONL" 2>>"$LOG"; then
    log "ordem $oid: surfada na Central (proposta $pid em proposals.jsonl)"
  else
    log "ordem $oid: FALHA ao surfar na Central (proposals.jsonl)"
  fi
}

pc_exec(){ printf '%s' "$1" > "$HOSTDATA/orq_task.txt"
  # FASE 1.6 (2026-07-13, elo 6): a causa raiz do bloqueio era bora-live-parser.ps1 preso sem
  # EOF (ver inbox/investigacao-cadeia-ordens-2026-07-13.md) -- corrigido com StreamReader.
  # Testado reduzir este teto para 300s como rede de seguranca extra, mas cortou a meio uma
  # ordem legitima (233a, a editar/testar ficheiros reais) antes dela terminar -- 900s respeitava
  # o orcamento de "1 ordem <=15min" ja documentado acima.
  # 2026-07-13 (pedido Danilo): alargado 900->2400s (40min) para dar tempo a ordens grandes
  # legitimas terminarem sem serem cortadas. A cura real continua a ser o fix do parser (acima).
  # 2026-07-14 (pedido Danilo): timeout 3600 = 1h, decisao do Danilo para deixar tarefas grandes
  # rodarem a vontade; so cortar de verdade acima disso.
  # 2026-07-16 (PARTE A, superado): o timeout fixo acima matava execucoes vivas (ordem 7838).
  # A deteccao real de inatividade agora e' do stale-output-watchdog.ps1 no PC (ve cabecalho do
  # ficheiro); este timeout so fica como rede de seguranca externa (bridge/SSH pendurado) —
  # 14700s = 4h10min, sempre por CIMA do teto duro do PC (4h) para nunca disparar primeiro.
  docker exec -u hermes "$C" sh -lc 'export PATH=/opt/data/.local/bin:$PATH; timeout 14700 pc-loop "$(cat /opt/data/orq_task.txt)"' 2>&1 | clean; }
pc_judge(){ printf '%s' "$1" > "$HOSTDATA/orq_judge.txt"
  docker exec -u hermes "$C" sh -lc 'export PATH=/opt/data/.local/bin:$PATH; timeout 400 pc-judge "$(cat /opt/data/orq_judge.txt)"' 2>&1 | clean; }

# ---- ACORDAR O CLAUDE.AI DESKTOP na fila vazia (2026-07-17, PEÇA 2) ----
# Mesma ponte SSH do pc_exec/pc-loop (container -> tailscale nc -> hermes@PC), mas para o
# schtask Bora-heartbeat-desktop (agora "Somente sob demanda", sem horário — só corre quando
# chamado). fila-vazia-wake.cmd semeia o pending.trigger do heartbeat-desktop com a frase
# curta e chama schtasks /run; se falhar (UAC, sessão do Danilo fechada, etc.) só regista o
# erro — NUNCA força, o Telegram (acima) já notificou de qualquer forma.
pc_wake_heartbeat(){
  docker exec -u hermes "$C" sh -lc 'ssh -o ProxyCommand="tailscale nc %h %p" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 hermes@100.71.105.7 "C:\\Users\\danil\\Desktop\\projetosflutter\\bora_app\\.claude\\.ai\\hermes\\heartbeat-desktop\\fila-vazia-wake.cmd"' 2>&1; }

# ---------------- EXECUÇÃO LOCAL NA VPS (2026-07-14, tira a dependência do PC de 4GB) ----------------
# claude -p corre diretamente no host da VPS (wrapper /root/claude-vps-exec.sh, tarefa por
# stdin) em vez de saltar por SSH/Tailscale até ao PC — o pc_exec acima fica como FALLBACK,
# não é apagado. rc=124 (timeout, mesmo teto de 3600s do pc_exec) segue o fluxo normal
# (vira TIMEOUT-3600s/SAIDA-VAZIA mais abaixo); só rc de erro real do wrapper (token
# inválido, claude ausente, etc.) é que cai para o PC.
VPS_EXEC=/root/claude-vps-exec.sh
VPS_RC_FILE=/root/orquestracao/.vps-exec.rc
VPS_FALLBACK_AVISADO=/root/orquestracao/.vps-exec-fallback.avisado
vps_exec(){ # $1=tarefa -> saida (stdout+stderr do wrapper); grava rc em $VPS_RC_FILE
  local out
  out=$(printf '%s' "$1" | timeout 3600 bash "$VPS_EXEC" 2>&1)
  echo $? > "$VPS_RC_FILE"
  printf '%s' "$out"
}
exec_ordem(){ # $1=tarefa -> PC-ONLY (2026-07-15 missao religar-loop): despacha SEMPRE pela ponte
  # SSH do PC. A rota VPS-local (vps_exec) fica definida mas DESATIVADA — a VPS foi abandonada
  # como executor (1 core/4GB, token ~2h). Reverter: apagar as 2 linhas seguintes.
  pc_exec "$1"; return
  local out rc
  out=$(vps_exec "$1" | clean)
  rc=$(cat "$VPS_RC_FILE" 2>/dev/null); rc=${rc:-1}
  if [ "$rc" -eq 0 ] || [ "$rc" -eq 124 ]; then
    rm -f "$VPS_FALLBACK_AVISADO"
    printf '%s' "$out"; return
  fi
  log "VPS-EXEC falhou (rc=$rc) — fallback para o PC nesta ordem"
  if [ ! -f "$VPS_FALLBACK_AVISADO" ]; then
    notify "⚠️ Bora/orquestração: execução local na VPS falhou (rc=$rc) — esta ordem caiu para o fallback PC."
    touch "$VPS_FALLBACK_AVISADO"
  fi
  pc_exec "$1"
}

# ---------------- LOCK-OCUPADO: executor.lock do PC recusou arrancar claude.exe ----------------
# FASE 1.7 (2026-07-13): 6 ordens seguidas (4c87/859a/858e/14bc/93e0/39c5) travaram rotuladas
# "JUIZ-SEM-VEREDITO" -- prova (saida.txt) mostrou que NENHUMA chegou a executar: o
# executor-lock.ps1 (FASE 1.5) recusou por "outro executor ja em curso" e o juiz foi chamado
# em cima dessa mensagem de erro (sem sentido para avaliar), devolvendo lixo sem "VEREDITO:".
# Deteta isto ANTES do juiz: não gasta tentativa, não chama o juiz, reabre para a próxima volta.
is_lock_busy(){ printf '%s' "$1" | grep -iqE "outro executor Bora ja em curso|ERRO: lock ocupado"; }

# ---------------- EXECUTOR-PAROU: claude.exe parou por --max-turns/--max-budget-usd ----------------
# FASE 1.10 (2026-07-17): causa raiz da "SAIDA-VAZIA -- tarefa grande demais?" era o claude.exe a
# parar por atingir --max-turns/--max-budget-usd; o stream-json emitia type:result sem .result nem
# .error e o bora-live-parser.ps1 ficava mudo (0 bytes). Fixado o parser (emite sempre esta linha) e
# subidos os tetos em run-claude-loop.cmd (40->150 turnos, $10->$25). Aqui: grava a linha EXATA como
# nota (nunca a nota generica) e trava JA a ordem -- reter igual contra o mesmo teto so repetiria o
# mesmo estouro e queimaria as 5 tentativas as cegas (prova: ordem 94b1 vazia 3x / eba8 passou só
# porque era menor). Ver inbox/fix-executor-max-turns-parser-mudo-2026-07-17.md.
executor_parou_linha(){ printf '%s' "$1" | grep -E '^EXECUTOR-PAROU:' | head -1 | tr -d '\r'; }

# FASE 1.11 (2026-08-01): IRMÃO da FASE 1.10, do outro lado do arranque. A 1.10 cobre "o executor
# parou a MEIO"; esta cobre "o executor NUNCA ARRANCOU". Avaria real de 27/07 a 31/07 (4 dias):
# a app Claude passou a gerir a CLI em %APPDATA%\Claude\claude-code\<versao>\ e a pasta npm global
# desapareceu; o caminho fixo do run-claude-loop.cmd deixou de existir -> "exit /b 4" -> 0 bytes ->
# esta função não existia -> caía no ramo genérico e a nota dizia "SAIDA-VAZIA -- tarefa grande
# demais?". A avaria ficou 4 dias escondida atrás de uma nota que mentia, e ninguém procurou o
# binário porque a nota culpava o tamanho da tarefa. Agora o .cmd grita uma linha específica e ela
# vira a nota EXATA (com utilizador e caminhos procurados), travando já — retentar não instala a CLI.
cli_nao_encontrada_linha(){ printf '%s' "$1" | grep -E '^CLI-NAO-ENCONTRADA:' | head -1 | tr -d '\r'; }

# FASE 1.11 item 4 (2026-08-01): AUTH morta. Terceiro irmão (1.10 = parou a meio, CLI-NAO-ENCONTRADA
# = nunca arrancou, este = arrancou mas não autentica). Apanha as DUAS formas: a linha do preflight
# do run-claude-loop.cmd (`claude auth status` sem loggedIn:true) e a mensagem literal que o próprio
# executor cospe em runtime se o token morrer a meio ("Failed to authenticate: OAuth session
# expired and could not be refreshed"). Trava à 1.ª: RETENTAR NÃO RENOVA UM TOKEN — só queima
# tentativas e volta a produzir a nota errada. Renovar é ato do Danilo (`claude setup-token`).
cli_sem_auth_linha(){
  printf '%s' "$1" \
    | grep -iE '^CLI-SEM-AUTH:|Failed to authenticate|OAuth session expired|Invalid API key|not logged in' \
    | head -1 | tr -d '\r'
}

# ---------------- RATE-LIMIT: deteção + cálculo de retoma ----------------
# 2026-07-13 (ordem a73d, falso rate-limit): a regex batia em QUALQUER saída que
# contivesse a frase, mesmo um relatório de sucesso que a CITA (ex.: tarefa cujo
# objetivo é diagnosticar rate-limit e reportar "TEXTO EXATO DETECTADO: ..." —
# a própria tarefa manda citar a frase). Prova: bloqueio genuíno (f523/f960) =
# saída de 61 bytes, SÓ a mensagem, nada mais — o claude -p pára ali. O
# falso-positivo (a73d) = relatório completo de 1986 bytes que MENCIONA a frase
# a meio de texto substantivo. Um bloqueio real nunca produz relatório — corta
# o falso-positivo exigindo que a saída inteira seja curta (bloqueio genuíno
# nunca passa disto; 600 é ~10x a maior saída real observada e ~3x menor que a
# menor saída falsa observada — larga margem dos dois lados).
is_rate_limit(){
  printf '%s' "$1" | grep -iqE "hit your (session|usage) limit|session limit|usage limit|rate limit|reached your (usage|session)? *limit" || return 1
  [ "$(printf '%s' "$1" | wc -c)" -le 600 ]
}
# "resets 5pm (Europe/London)" ou "resets 11:50pm (Europe/London)" -> epoch UTC;
# se não parsear -> now+3600 (defensivo). TZ=Europe/London via `date` já resolve BST/GMT
# sozinho (tzdata do sistema) — não precisa de lógica extra de DST aqui.
rl_resume_epoch(){
  local txt hh mm ap now h24 ep
  txt=$(printf '%s' "$1" | grep -oiE "resets[^0-9]*[0-9]{1,2}(:[0-9]{2})? *(am|pm)" | head -1)
  hh=$(printf '%s' "$txt" | grep -oE '[0-9]{1,2}' | head -1 | sed 's/^0*//')
  mm=$(printf '%s' "$txt" | grep -oE ':[0-9]{2}' | head -1 | tr -d ':')
  mm=${mm:-00}
  ap=$(printf '%s' "$txt" | grep -oiE 'am|pm' | head -1 | tr 'A-Z' 'a-z')
  now=$(date +%s)
  if [ -n "$hh" ] && [ -n "$ap" ]; then
    h24=$hh
    [ "$ap" = pm ] && [ "$hh" != 12 ] && h24=$((hh+12))
    [ "$ap" = am ] && [ "$hh" = 12 ] && h24=0
    ep=$(TZ='Europe/London' date -d "today ${h24}:${mm}" +%s 2>/dev/null)
    [ -n "$ep" ] && [ "$ep" -gt "$now" ] && { echo "$ep"; return; }
  fi
  echo $((now+3600))
}
hhmm(){ date -u -d "@$1" +%H:%M 2>/dev/null || echo "?"; }

# ---------------- ENCADEAMENTO DE MISSÃO (FASE 2) ----------------
# Formato de cada passo (1 linha) em orquestracao/<mid>.md:
#   passo: A | modelo: SONNET | paralelo: sim | depende: - | propose_only: nao | estado: pendente | tarefa: <texto>
missao_path(){ echo "$FILA/missoes/$1.md"; }   # missões num subdir -> o glob de ordens nunca as vê
missao_set_passo(){ # $1=mf $2=passoid $3=estado — [|] = pipe literal (evita alternância ERE)
  sed -i -E "/^passo: *$2 *[|]/ s|(estado: *)[A-Za-z_-]+|\1$3|I" "$1"; }
deps_ok(){ # $1=mf $2="A,B" ou "-" -> 0 se todas concluídas
  local mf="$1" dep d
  dep=$(printf '%s' "$2" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//')   # trim: o extrator [^|]* deixa espaço à direita
  { [ -z "$dep" ] || [ "$dep" = "-" ]; } && return 0
  for d in $(echo "$dep" | tr ',' ' '); do
    d=$(echo "$d" | tr -d ' '); [ -z "$d" ] && continue
    grep -E "^passo: *$d *[|]" "$mf" | grep -qi 'estado: *concluida' || return 1
  done
  return 0
}
missao_dispara_passo(){ # $1=mid $2=mf $3=linha $4=pid — cria a ordem na fila (via container, dono hermes)
  local mid="$1" mf="$2" linha="$3" pid="$4" modelo propose tarefa prefixo oid stamp
  modelo=$(echo "$linha" | grep -oiE 'modelo: *[A-Za-z]+' | sed -E 's/modelo: *//I' | tr 'a-z' 'A-Z')
  propose=$(echo "$linha" | grep -oiE 'propose_only: *[a-z]+' | sed -E 's/propose_only: *//I' | tr 'A-Z' 'a-z')
  tarefa=$(echo "$linha" | sed -E 's/.*[|] *tarefa: *//')
  prefixo="[MODELO: ${modelo:-SONNET}]"
  [ "$propose" = sim ] && prefixo="$prefixo [PROPOSE-ONLY: prepara o fix completo mas NÃO apliques nem faças commit; devolve a proposta e espera 'vai' do Danilo]"
  stamp=$(date -u +%Y%m%d%H%M%S)
  oid="ordem-${stamp}-${mid}-${pid}"
  missao_set_passo "$mf" "$pid" "executando"
  docker exec -i -u hermes "$C" sh -lc "cat > /opt/data/cortex-brain/orquestracao/$oid.md" <<EOF
--- ordem ---
id: $oid
estado: aberta
autor: carteiro-chaining
criada: $(ts)
zona: verde
tentativa: 0
teto_tentativas: 5
missao: $mid
passo: $pid
tarefa: $prefixo $tarefa
--- fim ---
nota:
EOF
  log "missão $mid: disparado passo $pid -> $oid (modelo ${modelo:-SONNET}${propose:+, propose-only})"
}
missao_fire_next(){ # $1=mid -> dispara até 2 passos pendentes elegíveis; 2º só se ambos paralelo:sim
  local mid="$1" mf disparados=0 linha pid est dep par
  mf=$(missao_path "$mid"); [ -f "$mf" ] || { echo 0; return; }
  while IFS= read -r linha; do
    [ "$disparados" -ge 2 ] && break
    pid=$(echo "$linha" | sed -E 's/^passo: *([^ |]+).*/\1/')
    est=$(echo "$linha" | grep -oiE 'estado: *[a-z_-]+' | sed -E 's/estado: *//I' | tr 'A-Z' 'a-z')
    [ "$est" = pendente ] || continue
    dep=$(echo "$linha" | grep -oE 'depende: *[^|]*' | sed -E 's/depende: *//')
    deps_ok "$mf" "$dep" || continue
    par=$(echo "$linha" | grep -oiE 'paralelo: *[a-z]+' | sed -E 's/paralelo: *//I' | tr 'A-Z' 'a-z')
    if [ "$disparados" -eq 0 ]; then
      missao_dispara_passo "$mid" "$mf" "$linha" "$pid"; disparados=1
      [ "$par" = sim ] || break            # 1º solo -> não dispara 2º
    else
      [ "$par" = sim ] || continue         # 2º só se paralelo:sim
      missao_dispara_passo "$mid" "$mf" "$linha" "$pid"; disparados=2
    fi
  done < <(grep -E '^passo:' "$mf")
  echo "$disparados"
}
missao_avanca(){ # $1=mid $2=passo (que acabou aprovado)
  local mid="$1" p="$2" mf n
  mf=$(missao_path "$mid"); [ -f "$mf" ] || { log "missão $mid: ficheiro não existe"; return; }
  missao_set_passo "$mf" "$p" "concluida"; log "missão $mid: passo $p CONCLUÍDO"
  if ! grep -E '^passo:' "$mf" | grep -qiE 'estado: *(pendente|aberta|executando|em_correcao|corrigir)'; then
    setf estado concluida "$mf"; log "missão $mid: MISSÃO CONCLUÍDA"
    notify "✅ Bora/missão $mid CONCLUÍDA — todos os passos fechados."; return
  fi
  n=$(missao_fire_next "$mid")
  [ "${n:-0}" -eq 0 ] && log "missão $mid: sem próximos passos elegíveis agora (deps pendentes)"
}
# ---------------- C4: falha -> LIÇÃO (fecha o ciclo do aprendizado) ----------------
# Até 2026-07-20 o loop travava ordens e não aprendia NADA: o `.claude/juiz/reflexao.py`
# existia mas nenhum script o invocava (código morto — confirmado por grep em todos os
# .sh/.cmd/.ps1). As 28 lições do Cérebro vieram de commits manuais em lote. Com isto o
# ciclo fecha-se: erro -> lição -> consolidador (2x/dia) -> injeção no executor -> menos erro.
#
# Regras, todas com motivo:
#  - SÓ em TRAVADA (ordem morta de vez). Em CORRIGIR geraria um rascunho por tentativa
#    -> exatamente a `licao-spam-ordens-autoreferencial` que já está registada.
#  - DEDUPE por hash de tarefa+nota: o mesmo erro não gera dois rascunhos.
#  - BEST-EFFORT: nenhum caminho aqui pode travar o loop — tudo devolve 0.
#  - Rascunho vai para o INBOX. Quem promove a lição permanente continua a ser o
#    `bibliotecario-cerebro` (regra do escritor único do Cérebro, não a quebro aqui).
# Sobrescrevíveis por ambiente SÓ para o auto-teste poder correr contra um inbox
# temporário — em produção ficam sempre nestes valores.
REFLEXAO="${REFLEXAO:-$HOSTDATA/cortex-brain/.claude/juiz/reflexao.py}"
LICOES_INBOX="${LICOES_INBOX:-$HOSTDATA/cortex-brain/.claude/.ai/knowledge/inbox}"

licao_de_falha(){ # $1=ficheiro da ordem — best-effort, nunca falha para fora
  local of="$1" oid tarefa nota chave alvo certo
  [ -f "$REFLEXAO" ] && [ -d "$LICOES_INBOX" ] || return 0
  oid=$(get id "$of"); tarefa=$(get tarefa "$of"); nota=$(get nota "$of")
  [ -n "$tarefa" ] || return 0

  chave=$(printf '%s|%s' "$tarefa" "$nota" | sha256sum | cut -c1-10)
  if grep -rlq "licao-chave: $chave" "$LICOES_INBOX" 2>/dev/null; then
    log "licao: chave $chave já registada — não duplico"; return 0
  fi

  # O "o certo é Z" exige juízo — um shell não o inventa. Reusa o pc-judge que o loop
  # JÁ tem (haiku, barato, só leitura). Se não responder, fica PENDENTE: melhor um
  # campo por preencher do que uma regra fabricada a entrar no Cérebro.
  # 2026-07-20, apanhado pela 1ª prova real ponta-a-ponta: quando a ponte do juiz falha, ela
  # devolve texto NÃO-VAZIO — um erro do cmd do Windows ("'PONTE' não é reconhecido como um
  # comando interno"). A 1ª versão só caía para PENDENTE se a saída fosse VAZIA, por isso
  # plantou uma mensagem de erro como se fosse regra dentro do Cérebro. Agora: filtrar erros
  # conhecidos E exigir uma frase com corpo. Lixo -> PENDENTE, nunca ao Cérebro.
  local bruto
  bruto=$(pc_judge "Uma ordem do loop autónomo do Bora morreu de vez (travada).
TAREFA: $(resumo_tarefa "$tarefa")
MOTIVO DA MORTE: $nota
Responde SÓ com UMA frase: a regra generalizável que evitaria repetir isto. Sem preâmbulo." \
    2>/dev/null | tr -d '\r')
  # 2ª correção (2026-07-20): a 1ª filtrava LINHA A LINHA — e o erro do cmd tem 2 linhas
  # ("'PONTE' não é reconhecido..." / "ou externo, um programa operável..."), por isso ao
  # cortar a 1ª o head apanhava a 2ª: o mesmo erro, outro pedaço. Um blob de erro não se
  # salva por pedaços — ou a saída INTEIRA é limpa, ou não se aproveita nada dela.
  if printf '%s' "$bruto" | grep -qiE "não é reconhecido|nao e reconhecido|is not recognized|command not found|comando interno|programa operável|arquivo em lotes|permission denied|^ *fatal:|cmd\.exe|the system cannot find|não foi possível|nao foi possivel"; then
    certo=""
  else
    certo=$(printf '%s' "$bruto" | grep -v '^[[:space:]]*$' | head -1)
  fi
  # uma regra útil tem corpo; um fragmento de 5 palavras é quase sempre resto de erro
  [ "${#certo}" -ge 30 ] || certo=""
  [ -n "$certo" ] || certo="PENDENTE — a completar pelo bibliotecario-cerebro (o juiz não devolveu uma regra utilizável)."

  alvo="$LICOES_INBOX/licao-pendente-$oid.md"
  {
    printf -- '---\n'
    printf 'tema: licao-falha-%s · escopo: projeto · estado: rascunho · atualizado: %s\n' "$oid" "$(date -u +%F)"
    printf 'tipo: licao\norigem: [loop de orquestracao · ordem %s]\nzona: verde\nconfianca: auto\n' "$oid"
    printf 'licao-chave: %s\n' "$chave"
    printf -- '---\n\n'
    # PROVENIÊNCIA HONESTA: o reflexao.py traz hardcoded "(evidência: veredito determinístico
    # do Juiz — git diff mecânico, não opinião de IA.)". Nesta via isso é FALSO: o "certo"
    # saiu de um haiku. Num projeto com anti_trapaca e a regra de nunca inventar prova, deixar
    # essa frase entrar no Cérebro era plantar uma alegação errada. Trocamo-la pela verdade.
    python3 "$REFLEXAO" --tentei "$(resumo_tarefa "$tarefa")" --falhou "${nota:-motivo desconhecido}" \
            --certo "$certo" --codigo ORDEM_TRAVADA 2>/dev/null \
      | sed 's|(evidência: veredito determinístico do Juiz.*|(proveniência: "Tentei" e "Falhou" são factos mecânicos do loop — id da ordem + nota do veredito. "O certo é" é SUGESTÃO de IA (juiz haiku), POR VALIDAR pelo bibliotecario-cerebro.)|'
  } > "$alvo" 2>/dev/null || { log "licao: falhei a escrever o rascunho (ignorado)"; return 0; }

  log "licao: rascunho gerado -> $(basename "$alvo") (chave $chave)"
  notify "🧠 Bora: a ordem $oid travou e virou lição — rascunho em inbox/$(basename "$alvo"). O Bibliotecário promove."
  return 0
}

missao_travada_ou_silencio(){ # $1=of $2=mid $3=passo
  local of="$1" mid="$2" p="$3" mf oid nota
  # C4: este é o funil ÚNICO por onde passam os 4 caminhos de TRAVADA (teto de 5,
  # EXECUTOR-PAROU, saída vazia, e 5 tentativas pós-juiz). Enganchar aqui cobre todos
  # sem tocar em nenhum deles.
  licao_de_falha "$of"
  # I4 (2026-08-01, ordem do Danilo): `travada` NÃO-VERMELHA deixa de chamar o Danilo.
  # HISTÓRIA (não apagar): a 2026-07-13 (ordem f523) estes avisos foram RESTAURADOS de propósito,
  # porque antes o loop ficava mudo à espera do watchdog (>12h) e uma travada exigia decisão
  # humana. O que mudou desde então: o hook passou a criar CONTINUAÇÕES automáticas (a travada
  # auto-resolve-se na maioria dos casos) e a fila enchia-se de travadas espúrias — o Danilo
  # apanhou notificação "travou" a cada ~40 min. O aviso deixou de ser sinal e passou a ser ruído.
  # Agora: arquiva-se em ficheiro, revisto no daily-pulse. Telegram fica RESERVADO à zona vermelha
  # (ramo `zona_vermelha`, intocado — é a única coisa no sistema que pára e chama o Danilo) e à
  # missão concluída. Se o daily-pulse deixar de ser lido, isto vira silêncio — é o risco assumido.
  oid=$(get id "$of"); nota=$(get nota "$of")
  if [ -n "$mid" ]; then
    mf=$(missao_path "$mid"); [ -f "$mf" ] && missao_set_passo "$mf" "$p" "travada"
    mkdir -p "$(dirname "$ARQUIVO_TRAVADAS")" 2>/dev/null
    printf '%s\t%s\tmissao=%s passo=%s\t%s\n' "$(date -u +%FT%TZ)" "$oid" "$mid" "$p" "${nota:-—}" >> "$ARQUIVO_TRAVADAS" \
      || log "ordem $oid: AVISO — não consegui escrever em $ARQUIVO_TRAVADAS"
    log "missão $mid: passo $p travado -> ARQUIVO (daily-pulse). SEM Telegram (I4)."
  else
    mkdir -p "$(dirname "$ARQUIVO_TRAVADAS")" 2>/dev/null
    printf '%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$oid" "sem-missao" "${nota:-motivo desconhecido}" >> "$ARQUIVO_TRAVADAS" \
      || log "ordem $oid: AVISO — não consegui escrever em $ARQUIVO_TRAVADAS"
    log "ordem $oid: travada (sem missão) -> ARQUIVO (daily-pulse). SEM Telegram (I4)."
  fi
}

# ---------------- MODOS AUXILIARES (não tocam a fila real de produção) ----------------
if [ "${1:-}" = "--selftest" ]; then
  fail=0; ok(){ echo "OK   $1"; }; bad(){ echo "FAIL $1"; fail=1; }
  is_rate_limit "You've hit your session limit · resets 5pm (Europe/London)" && ok "rate-limit detecta (bloqueio curto genuino)" || bad "rate-limit detecta"
  is_rate_limit "tudo bem, terminei a tarefa" && bad "rate-limit falso-positivo" || ok "rate-limit sem falso-positivo"
  # REGRESSAO 2026-07-13 (ordem a73d): relatorio longo que CITA a frase (tarefa
  # era diagnosticar rate-limit) nao pode disparar pausa -- so bloqueio curto conta.
  relatorio_longo="Confirmado: o relatorio ja existe e responde a pergunta pedida. $(printf 'x%.0s' $(seq 1 500)) TEXTO EXATO DETECTADO: \"You've hit your session limit · resets 1pm (Europe/London)\" · E RATE-LIMIT REAL: sim (mas essa janela ja passou ha muito)."
  is_rate_limit "$relatorio_longo" && bad "relatorio longo que cita a frase NAO devia disparar rate-limit" || ok "relatorio longo citando a frase nao dispara (falso-positivo a73d corrigido)"
  now=$(date +%s)
  ep=$(rl_resume_epoch "resets 5pm (Europe/London)")
  [ "$ep" -gt "$now" ] && ok "reset 5pm -> epoch sempre futuro (nunca pausa no passado)" || bad "reset 5pm epoch futuro"
  ep2=$(rl_resume_epoch "sem hora nenhuma aqui")
  [ "$ep2" -gt "$now" ] && ok "reset sem hora -> futuro (now+1h defensivo)" || bad "reset defensivo"
  # REGRESSAO 2026-07-13 (ordem 883f): "resets 11:50pm" (com minutos) caía no
  # fallback now+3600 porque a regex só reconhecia hora redonda ("6pm"). Os
  # testes abaixo confirmam que os minutos são extraídos e preservados (o
  # offset Europe/London->UTC é sempre em horas inteiras, nunca fraciona minuto).
  ep3=$(rl_resume_epoch "resets 11:50pm (Europe/London)")
  { [ "$ep3" -gt "$now" ] && [ "$(date -u -d "@$ep3" +%M)" = "50" ]; } \
    && ok "reset 11:50pm -> minutos preservados (23:50 Europe/London)" || bad "reset 11:50pm minutos"
  ep4=$(rl_resume_epoch "resets 9:05am (Europe/London)")
  { [ "$ep4" -gt "$now" ] && [ "$(date -u -d "@$ep4" +%M)" = "05" ]; } \
    && ok "reset 9:05am -> minutos preservados" || bad "reset 9:05am minutos"
  ep5=$(rl_resume_epoch "resets 12am (Europe/London)")
  [ "$ep5" -gt "$now" ] && ok "reset 12am -> epoch futuro (meia-noite)" || bad "reset 12am epoch futuro"
  ep6=$(rl_resume_epoch "resets 12pm (Europe/London)")
  [ "$ep6" -gt "$now" ] && ok "reset 12pm -> epoch futuro (meio-dia)" || bad "reset 12pm epoch futuro"
  ep7=$(rl_resume_epoch "resets 6pm (Europe/London)")
  [ "$ep7" -gt "$now" ] && ok "reset 6pm -> formato hora redonda continua a funcionar" || bad "reset 6pm hora redonda"
  tmf=$(mktemp)
  printf 'passo: A | modelo: SONNET | paralelo: sim | depende: - | propose_only: nao | estado: concluida | tarefa: x\npasso: B | modelo: SONNET | paralelo: sim | depende: A | propose_only: nao | estado: pendente | tarefa: y\n' > "$tmf"
  deps_ok "$tmf" "A" && ok "deps_ok A concluida" || bad "deps_ok A"
  deps_ok "$tmf" "B" && bad "deps_ok B pendente devia falhar" || ok "deps_ok B pendente falha"
  deps_ok "$tmf" "-" && ok "deps_ok sem deps" || bad "deps_ok -"
  deps_ok "$tmf" "- " && ok "deps_ok tolera trailing space (bug do extrator)" || bad "deps_ok trailing space"
  dep_real=$(echo "passo: X | depende: A | estado: pendente | tarefa: y" | grep -oE 'depende: *[^|]*' | sed -E 's/depende: *//')
  deps_ok "$tmf" "$dep_real" && ok "deps_ok com dep extraido de linha real (A concluida)" || bad "deps_ok dep extraido"
  missao_set_passo "$tmf" "B" "concluida"
  grep -E '^passo: *B' "$tmf" | grep -qi 'estado: *concluida' && ok "set_passo B->concluida" || bad "set_passo B"
  grep -E '^passo: *A' "$tmf" | grep -qi 'estado: *concluida' && ok "set_passo não tocou A" || bad "set_passo tocou A errado"
  rm -f "$tmf"
  # aviso-espera-telegram (2026-07-14): resumo_tarefa() tira os prefixos de máquina e corta
  # a mensagem — é o texto que vai para o Telegram no aviso de zona vermelha.
  r1=$(resumo_tarefa "[MODELO: SONNET] Atualizar o platform_settings stripe_enabled para true")
  [ "$r1" = "Atualizar o platform_settings stripe_enabled para true" ] && ok "resumo_tarefa tira [MODELO: ...]" || bad "resumo_tarefa tira [MODELO: ...] (got: $r1)"
  r2=$(resumo_tarefa "[MODELO: OPUS] [PROPOSE-ONLY: prepara o fix completo mas NÃO apliques] Corrigir o refund cap")
  [ "$r2" = "Corrigir o refund cap" ] && ok "resumo_tarefa tira [MODELO:...] + [PROPOSE-ONLY:...]" || bad "resumo_tarefa tira os dois prefixos (got: $r2)"
  longa=$(printf 'x%.0s' $(seq 1 300))
  r3=$(resumo_tarefa "$longa")
  [ "${#r3}" -eq 160 ] && ok "resumo_tarefa corta em 160 chars" || bad "resumo_tarefa corta em 160 chars (len=${#r3})"
  # PARTE A (2026-07-16): extração do marcador MOTIVO_KILL devolvido pelo vigia de inatividade do PC
  mk1=$(printf 'MOTIVO_KILL:INATIVIDADE:23\n' | grep -oE '^MOTIVO_KILL:(INATIVIDADE|TETO-DURO):[0-9]+' | head -1)
  [ "$mk1" = "MOTIVO_KILL:INATIVIDADE:23" ] && ok "motivo_kill extrai INATIVIDADE:23" || bad "motivo_kill extrai INATIVIDADE (got: $mk1)"
  mk2=$(printf 'MOTIVO_KILL:TETO-DURO:240\n' | grep -oE '^MOTIVO_KILL:(INATIVIDADE|TETO-DURO):[0-9]+' | head -1)
  [ "$mk2" = "MOTIVO_KILL:TETO-DURO:240" ] && ok "motivo_kill extrai TETO-DURO:240" || bad "motivo_kill extrai TETO-DURO (got: $mk2)"
  mk3=$(printf 'texto normal sem marcador\n' | grep -oE '^MOTIVO_KILL:(INATIVIDADE|TETO-DURO):[0-9]+' | head -1)
  [ -z "$mk3" ] && ok "motivo_kill vazio quando não há marcador" || bad "motivo_kill deveria ser vazio (got: $mk3)"
  # FASE 1.10 (2026-07-17): extração da linha EXECUTOR-PAROU devolvida pelo parser quando o
  # claude.exe para por max-turns/max-budget sem .result/.error (fix da SAIDA-VAZIA fantasma).
  ep1=$(executor_parou_linha "$(printf 'EXECUTOR-PAROU: subtype=error_max_turns turns=150 custo=25.0\n')")
  [ "$ep1" = "EXECUTOR-PAROU: subtype=error_max_turns turns=150 custo=25.0" ] && ok "executor_parou_linha extrai a linha exata" || bad "executor_parou_linha extrai (got: $ep1)"
  ep2=$(executor_parou_linha "$(printf 'texto normal sem marcador\n')")
  [ -z "$ep2" ] && ok "executor_parou_linha vazio quando não há marcador" || bad "executor_parou_linha deveria ser vazio (got: $ep2)"
  # C4 (2026-07-20): falha -> lição. Corre contra um inbox TEMPORÁRIO com o pc_judge e o
  # notify substituídos — zero Telegram, zero toque no Cérebro real.
  if [ -f "$REFLEXAO" ] && command -v python3 >/dev/null 2>&1; then
    _td=$(mktemp -d); LICOES_INBOX="$_td"
    notify(){ :; }                                   # sem Telegram no teste
    pc_judge(){ echo "REGRA DE TESTE: nunca repetir X sem verificar Y."; }
    printf 'id: ordem-teste-c4\ntarefa: [MODELO: SONNET] tarefa de teste do C4\nnota: SAIDA-VAZIA -- teste\nestado: travada\n' > "$_td/ordem.md"
    licao_de_falha "$_td/ordem.md"
    _lf="$_td/licao-pendente-ordem-teste-c4.md"
    [ -f "$_lf" ] && ok "licao_de_falha gera o rascunho" || bad "licao_de_falha NÃO gerou rascunho"
    grep -q "HANDOFF → bibliotecario-cerebro" "$_lf" 2>/dev/null \
      && ok "rascunho traz o bloco de handoff do reflexao.py" || bad "rascunho sem bloco de handoff"
    grep -q "REGRA DE TESTE" "$_lf" 2>/dev/null \
      && ok "o 'certo' vem do juiz, não é inventado" || bad "o 'certo' não chegou ao rascunho"
    grep -q "tarefa de teste do C4" "$_lf" 2>/dev/null \
      && ok "rascunho traz a tarefa real" || bad "rascunho sem a tarefa"
    grep -q "SUGESTÃO de IA" "$_lf" 2>/dev/null \
      && ok "proveniência honesta: marca o 'certo' como sugestão de IA" || bad "rascunho sem a nota de proveniência"
    grep -q "não opinião de IA" "$_lf" 2>/dev/null \
      && bad "rascunho ainda alega 'não opinião de IA' (falso nesta via)" || ok "alegação falsa de proveniência removida"
    # dedupe: segunda passagem com a MESMA tarefa+nota não pode criar outro ficheiro
    _antes=$(ls -1 "$_td"/licao-pendente-*.md 2>/dev/null | wc -l)
    licao_de_falha "$_td/ordem.md"
    _depois=$(ls -1 "$_td"/licao-pendente-*.md 2>/dev/null | wc -l)
    [ "$_antes" = "$_depois" ] && ok "dedupe: mesmo erro não gera 2º rascunho" || bad "dedupe falhou ($_antes -> $_depois)"
    # fail-safe: sem reflexao.py, devolve 0 e não escreve nada
    REFLEXAO=/caminho/que/nao/existe licao_de_falha "$_td/ordem.md" >/dev/null 2>&1
    [ "$?" = 0 ] && ok "licao_de_falha é best-effort (sem reflexao.py devolve 0)" || bad "licao_de_falha devolveu erro"
    # REGRESSÃO (defeito real de 2026-07-20): a ponte do juiz avariada devolve um erro do cmd,
    # não uma regra — e isso NÃO pode entrar no Cérebro disfarçado de lição.
    rm -f "$_td"/licao-pendente-*.md
    # o erro REAL do cmd tem 2 linhas — a 2ª passava o filtro linha-a-linha da 1ª correção
    pc_judge(){ printf \"'PONTE' não é reconhecido como um comando interno\\nou externo, um programa operável ou um arquivo em lotes.\\n\"; }
    printf 'id: ordem-teste-erro\ntarefa: tarefa com ponte avariada\nnota: SAIDA-VAZIA\nestado: travada\n' > "$_td/o2.md"
    licao_de_falha "$_td/o2.md"
    grep -q "PENDENTE" "$_td/licao-pendente-ordem-teste-erro.md" 2>/dev/null \
      && ok "erro da ponte vira PENDENTE, não vira regra" || bad "erro da ponte passou como se fosse regra"
    grep -q "não é reconhecido" "$_td/licao-pendente-ordem-teste-erro.md" 2>/dev/null \
      && bad "mensagem de erro do cmd entrou no rascunho" || ok "mensagem de erro do cmd filtrada"
    # fragmento curto (resto de erro) também não serve como regra
    pc_judge(){ echo "usa o flag -x"; }
    printf 'id: ordem-teste-curto\ntarefa: tarefa curta\nnota: SAIDA-VAZIA\nestado: travada\n' > "$_td/o3.md"
    licao_de_falha "$_td/o3.md"
    grep -q "PENDENTE" "$_td/licao-pendente-ordem-teste-curto.md" 2>/dev/null \
      && ok "fragmento curto vira PENDENTE" || bad "fragmento curto passou como regra"
    rm -rf "$_td"
  else
    ok "licao_de_falha: teste saltado (reflexao.py/python3 ausentes nesta máquina)"
  fi
  [ "$fail" = 0 ] && echo "SELFTEST: TODOS OK" || echo "SELFTEST: HÁ FALHAS"
  exit "$fail"
fi
if [ "${1:-}" = "--iniciar-missao" ]; then   # arranca a missão: dispara os primeiros passos elegíveis
  mid="${2:-}"; mf=$(missao_path "$mid")
  [ -f "$mf" ] || { echo "missão '$mid' não existe em $mf"; exit 1; }
  n=$(missao_fire_next "$mid")
  echo "missão $mid: $n passo(s) disparado(s). A campainha acorda o carteiro."
  exit 0
fi

# ================= CICLO NORMAL =================
exec 9>"$LOCK"; flock -n 9 || { log "outro carteiro a correr — saio"; exit 0; }
mkdir -p "$FILA"

# STOP global — .pausa-total (Danilo): trava TUDO
if [ -f "$PAUSA_TOTAL" ]; then log "STOP-TOTAL: .pausa-total presente — nada a fazer"; exit 0; fi

# PAUSA automática por rate-limit: espera o reset e retoma sozinho
if [ -f "$PAUSA_RL" ]; then
  resume=$(tr -dc '0-9' < "$PAUSA_RL" 2>/dev/null); now=$(date +%s)
  if [ -n "$resume" ] && [ "$now" -lt "$resume" ]; then
    log "PAUSA-RATE-LIMIT: fila pausada até $(hhmm "$resume") UTC — saio"; exit 0
  fi
  rm -f "$PAUSA_RL" "$RL_AVISADO"; log "PAUSA-RATE-LIMIT: reset atingido — retomo o ciclo"
  # 2026-07-13: ao expirar, isto só limpava o ficheiro de controlo — a ordem que estava
  # EM EXECUÇÃO no instante exato do rate-limit ficava gravada em `estado: pausada-rate-limit`
  # (linha ~280) e o loop abaixo só processa `estado: aberta`, logo nada a devolvia. Ficava
  # presa nesse rótulo para sempre mesmo com a fila já a funcionar (ver
  # inbox/diagnostico-rate-limit-2026-07-13.md, caso f523/f960). A tentativa já foi devolvida
  # na altura da pausa (linha ~279) — reabrir aqui não gasta tentativa extra.
  for pf in "$FILA"/*.md; do
    [ -f "$pf" ] || continue
    case "$pf" in */_controlo.md) continue;; esac
    if [ "$(get estado "$pf")" = "pausada-rate-limit" ]; then
      pid=$(get id "$pf")
      setf estado aberta "$pf"; setf nota "" "$pf"
      log "ordem $pid: reaberta automaticamente (era pausada-rate-limit, reset já passou)"
    fi
  done
fi

# T5 — kill switch
enabled=$(get orquestracao_enabled "$CTRL"); enabled=$(echo "${enabled:-false}" | tr 'A-Z' 'a-z')
if [ "$enabled" != "true" ]; then log "T5: kill switch OFF (enabled=$enabled) — nada a fazer"; exit 0; fi

# resumo do ciclo (aviso de fila vazia por evento, 2026-07-16) — conta aprovadas/corrigir
# e guarda a última ordem processada, para a mensagem de transição ocupado->vazio no fim.
n_aprovadas=0; n_corrigir=0; ultima_id=""; ultima_veredito=""

for f in "$FILA"/*.md; do
  [ -f "$f" ] || continue
  case "$f" in */_controlo.md) continue;; esac
  [ "$(get estado "$f")" = "aberta" ] || continue
  id=$(get id "$f"); tarefa=$(get tarefa "$f"); tent=$(get tentativa "$f"); tent=${tent:-0}
  missao=$(get missao "$f"); passo=$(get passo "$f")
  ultima_id="$id"
  log "ordem $id: aberta (tentativa=$tent)${missao:+ [missão $missao/$passo]}"

  # PARTE B (2026-07-17) — RESPEITAR uma autorização humana já verificável na base.
  # BARREIRA: os campos autorizado_por_admin/audit_id SÓ podem ser escritos pelo passo 2
  # do sync (hermes-cortex-proposals-sync.sh), a partir de uma linha aprovada_danilo na
  # Central. Nenhum executor/agente/processo-da-ordem os escreve. E mesmo escritos, o
  # carteiro NUNCA confia no ficheiro: re-verifica o audit_id contra admin_audit_log
  # (audit_id_valido). NÃO altera zona_vermelha()/classificador/Lista Vermelha/Juiz/
  # zonas_diff.py — só evita re-gatilhar T3 numa ordem que o Danilo JÁ autorizou (fim do loop).
  autz_admin=$(get autorizado_por_admin "$f"); autz_audit=$(get audit_id "$f"); autz_ok=0
  if [ -n "$autz_admin" ] && [ -n "$autz_audit" ]; then
    if audit_id_valido "$autz_audit"; then
      autz_ok=1
      log "ordem $id: autorizada por admin $autz_admin (audit $autz_audit valido na base) -> salta T3"
    else
      log "ordem $id: campo autorizado presente mas audit $autz_audit NAO existe na base -> ignora, trata normal"
    fi
  fi

  # T3 — zona vermelha (dinheiro + intenção de escrita)
  if [ "$autz_ok" != 1 ] && zona_vermelha "$tarefa" && [ "$(get vai "$f")" != "sim" ]; then
    setf estado zona_vermelha "$f"; setf nota "🔴 ZONA VERMELHA — precisa de decisão humana (dinheiro)" "$f"
    log "ordem $id: 🔴 ZONA VERMELHA -> aprovacao humana"
    # 2026-07-14 (aviso-espera-telegram): antes o aviso só dizia "toca zona vermelha — precisa
    # de ti", sem dizer O QUE a ordem faz nem como desbloquear — o Danilo ficava a saber que
    # algo esperava, mas preso sem contexto nem ação direta. Agora leva o resumo da tarefa +
    # o comando exato de desbloqueio (a skill desbloqueio-zona-vermelha do Hermes trata o "vai $id").
    # 2026-07-17 (surface na Central, ver surfacar_na_central abaixo): a ordem passa a ficar
    # também rastreável na Central de Autonomia. NÃO diz "aprova lá" — sem a PARTE B (parada em
    # 7398, Lista Vermelha, aguarda "vai" humano com diff revisto) uma aprovação só na Central
    # NÃO liberta a ordem (o carteiro reavalia zona_vermelha() outra vez ao reabrir); prometer
    # isso recriaria o mesmo deadlock que esta mudança devia resolver. O "vai $id" aqui continua
    # a ser o único desbloqueio real.
    resumo=$(resumo_tarefa "$tarefa")
    notify "🔴 Bora/orquestração: ordem $id EM ESPERA (zona vermelha — toca dinheiro/pagamento).
Resumo: ${resumo:-(sem resumo)}
Para libertar para a fila normal, responde aqui: vai $id
(rastreável também em Perfil > Painel Admin > Central de Autonomia > tab Cortex)"
    surfacar_na_central "$id" "$tarefa"
    [ -n "$missao" ] && { mf=$(missao_path "$missao"); [ -f "$mf" ] && missao_set_passo "$mf" "$passo" "zona_vermelha"; }
    ultima_veredito="ZONA_VERMELHA"
    continue
  fi
  # T1 — teto 5
  if [ "$tent" -ge 5 ]; then setf estado travada "$f"
    [ -z "$(get nota "$f")" ] && setf nota "⛔ TRAVADA nas 5 tentativas" "$f"
    log "ordem $id: TRAVADA (5 tentativas)"; ultima_veredito="TRAVADA"; missao_travada_ou_silencio "$f" "$missao" "$passo"; continue; fi

  tent=$((tent+1)); setf tentativa "$tent" "$f"; setf estado executando "$f"
  # inicio da ORDEM = campo criada: (nao o relogio da tentativa) — commit feito numa tentativa
  # anterior CONTA como trabalho novo (fix 2026-07-15: a 1a corrida real travou a ordem reborn
  # porque o t0 por-tentativa excluia o commit da tentativa 1). Fallback: agora.
  criada_ts=$(grep -m1 '^criada:' "$f" | sed 's/criada: *//' | tr -d '\r')
  t0=""; [ -n "$criada_ts" ] && t0=$(date -d "$criada_ts" +%s 2>/dev/null)
  t0=${t0:-$(date +%s)}
  saida=$(exec_ordem "$tarefa"); printf '%s\n' "$saida" > "$FILA/$id.saida.txt"
  setf estado respondida "$f"; log "ordem $id: respondida (tentativa $tent)"
  # PARTE A (2026-07-16): se o vigia de inatividade do PC matou o executor, o run-claude-loop.cmd
  # devolve esta linha no stdout — conta como saida vazia (nao houve resultado real), mas o
  # MOTIVO fica preservado para a nota nunca dizer "timeout" generico.
  motivo_kill=$(printf '%s' "$saida" | grep -oE '^MOTIVO_KILL:(INATIVIDADE|TETO-DURO):[0-9]+' | head -1)
  vazio=0; [ -z "$(printf '%s' "$saida" | grep -vE '^MOTIVO_KILL:' | tr -d '[:space:]')" ] && vazio=1
  [ -n "$motivo_kill" ] && vazio=1

  # ---- LOCK-OCUPADO: executor nem chegou a arrancar (outro claude.exe vivo no PC) — não
  # gasta tentativa nem chama o juiz (não há nada real para avaliar); reabre para a próxima
  # volta tentar de novo, sem queimar o teto T1 nem confundir com falha do juiz.
  if is_lock_busy "$saida"; then
    setf tentativa "$((tent-1))" "$f"
    setf estado aberta "$f"
    setf nota "🔒 LOCK-OCUPADO — outro executor Bora já em curso no PC; reagendado sem gastar tentativa." "$f"
    log "ordem $id: 🔒 LOCK-OCUPADO — reaberta sem gastar tentativa"
    ultima_veredito="LOCK-OCUPADO"
    continue
  fi

  # ---- EXECUTOR-PAROU: claude.exe parou por max-turns/max-budget (Fix FASE 1.10) — nota EXATA,
  # trava já sem chamar o juiz nem gastar as 5 tentativas às cegas (repetir dá sempre o mesmo estouro).
  linha_parou=$(executor_parou_linha "$saida")
  if [ -n "$linha_parou" ]; then
    # PARIDADE PARTE 2.1 (2026-08-01): TETO NÃO É FALHA, É PAUSA.
    # Quando o Danilo cola o prompt numa sessão interactiva não há teto nenhum — a tarefa vai até
    # ao fim. Pelo loop havia `--max-turns/--max-budget`, e bater no teto marcava a ordem como
    # falhada e chamava o Danilo. Isso é a diferença que esta missão veio matar: o mesmo trabalho
    # tem de acabar pelos dois caminhos. Agora bater no teto gera CONTINUAÇÃO automática (o
    # mecanismo já existe no hermes-hook-conclusao.sh, ramo TRAVADA + continuacao < teto) e é
    # SILENCIOSO — `missao_travada_ou_silencio` NÃO é chamado de propósito, zero Telegram.
    # `pausa_teto: 1` diz ao hook para usar o teto GENEROSO (uma tarefa grande pode precisar de
    # várias continuações) em vez do teto 2 das travadas genuínas. Continua a haver teto absoluto,
    # para um loop infinito não correr para sempre — e o hook regista quando lá chega.
    setf estado travada "$f"
    setf pausa_teto 1 "$f"
    setf nota "⏸️ PAUSA-POR-TETO (não é falha): $linha_parou — continuação automática, o trabalho segue de onde parou." "$f"
    log "ordem $id: PAUSA-POR-TETO -> continuação silenciosa (sem Telegram) — $linha_parou"
    ultima_veredito="PAUSA-TETO"
    continue
  fi

  # ---- RATE-LIMIT: não gasta tentativa, pausa a fila, avisa 1x, retoma sozinho ----
  if is_rate_limit "$saida"; then
    setf tentativa "$((tent-1))" "$f"                 # devolve a tentativa (foi limite, não trabalho)
    setf estado pausada-rate-limit "$f"
    resume=$(rl_resume_epoch "$saida"); echo "$resume" > "$PAUSA_RL"
    setf nota "🚫 RATE-LIMIT (conta Claude no limite; retoma $(hhmm "$resume") UTC)" "$f"
    log "ordem $id: 🚫 RATE-LIMIT — fila pausada até $(hhmm "$resume") UTC"
    if [ ! -f "$RL_AVISADO" ]; then
      notify "🚫 Bora/orquestração: conta Claude Code no limite de sessão. Fila PAUSADA até $(hhmm "$resume") UTC — retomo sozinho, sem gastar tentativas."; touch "$RL_AVISADO"
    fi
    ultima_veredito="RATE-LIMIT"
    break                                             # não processa mais nada até ao reset
  fi

  # juiz — META_JUIZ leva o inicio_epoch p/ o chao mecanico do PC (juiz-mecanico.ps1) verificar
  # commit novo/ficheiro em disco. O veredito completo (com as linhas PROVA-JUIZ) fica auditavel
  # em $id.veredito.txt — prova no proprio veredito, nunca no e2e_log.
  jinput=$(printf 'TAREFA:\n%s\nMETA_JUIZ: inicio_epoch=%s\n\nSAIDA DO EXECUTOR:\n%s\n' "$tarefa" "${t0:-}" "$(printf '%s' "$saida" | tail -50)")
  veredito=$(pc_judge "$jinput")

  # PARIDADE PARTE 2.2 (2026-08-01): O JUIZ DEIXA DE MATAR TRABALHO BOM.
  # Antes: juiz sem veredito -> CORRIGIR -> a ordem REABRIA e a TAREFA corria outra vez do zero,
  # queimando as 5 tentativas. Provado nesta sessão: a ordem 054224-aplic fez o trabalho todo à 1.ª
  # (ficheiro escrito, sugestão em `aplicada`) e mesmo assim voltou a correr 3x porque o juiz não
  # devolvia veredito — cada volta ~4 min de executor a repetir trabalho já feito. Também matou as
  # ordens a1d2 e 6244 a 22/07. O trabalho JÁ ESTÁ FEITO quando o juiz falha: re-tentar a tarefa é
  # desperdício e arrisca efeitos repetidos. Portanto: re-tenta SÓ O JUIZ, nunca a tarefa.
  jtent=1
  while [ -z "$(printf '%s' "$veredito" | grep -iE 'VEREDITO:')" ] && [ "$jtent" -lt 3 ]; do
    jtent=$((jtent+1))
    log "ordem $id: juiz sem veredito — re-tento SÓ o juiz ($jtent/3; a tarefa NÃO volta a correr)"
    sleep 5
    veredito=$(pc_judge "$jinput")
  done
  printf '%s\n' "$veredito" > "$FILA/$id.veredito.txt"
  vline=$(printf '%s' "$veredito" | grep -iE 'VEREDITO:' | head -1)
  log "ordem $id: ${vline:-<juiz sem veredito>}"

  # 2026-07-16: guarda anti-conserto-fantasma antiga (mentions_failure) removida — grep de
  # palavras na saida do executor reabria ordens que reportavam falha honestamente (mesmo
  # tendo feito o trabalho certo), o MESMO defeito ja corrigido no juiz-mecanico esta manha
  # (recusa honesta != falha real). O juiz JA distingue os dois casos no seu VEREDITO; reabrir
  # e' decisao EXCLUSIVA dele (CORRIGIR), nunca de um grep paralelo sobre o texto do executor.
  if printf '%s' "$vline" | grep -iq 'APROVADA'; then
    setf estado aprovada "$f"; setf nota "" "$f"; log "ordem $id: APROVADA"
    ultima_veredito="APROVADA"; n_aprovadas=$((n_aprovadas+1))
    if [ -n "$missao" ]; then
      missao_avanca "$missao" "$passo"
    else
      # 2026-07-13 (ordem f523): restaurado o aviso de conclusão — antes era
      # silêncio total (reengenharia 2026-07-12, pensada só para não repetir
      # aviso a cada passo de uma MISSÃO). Ordem avulsa aprovada volta a avisar.
      resumo=$(resultado_1linha "$saida")
      notify "✅ Bora: tarefa $id concluída com sucesso. ${resumo:-(sem resumo)}"
      log "ordem $id: aprovada -> Telegram (conclusão)"
    fi
  else
    # ---- NOTA NUNCA VAZIA — causa explícita por construção ----
    motivo=$(printf '%s' "$vline" | sed 's/.*CORRIGIR: *//')
    # FASE 1.11: arranque falhado tem prioridade sobre TUDO o resto — se a CLI não foi encontrada,
    # nada correu, logo qualquer outro diagnóstico (vazio/juiz/timeout) seria inventado.
    cli_line=$(cli_nao_encontrada_linha "$saida")
    auth_line=$(cli_sem_auth_linha "$saida")
    if [ -n "$cli_line" ]; then
      nota="🚫 $cli_line"
    elif [ -n "$auth_line" ]; then
      nota="🔑 CLI-SEM-AUTH: $auth_line — sessão do executor caducada; renovar com \`claude setup-token\` (ato do Danilo). Retentar não renova."
    elif [ "$vazio" -eq 1 ]; then
      # PARTE A (2026-07-16): distingue morte por INATIVIDADE real (vigia do PC) / TETO-DURO-4h
      # de uma saida vazia comum — nunca mais "TIMEOUT-3600s" generico (ver cabecalho do ficheiro).
      case "$motivo_kill" in
        MOTIVO_KILL:INATIVIDADE:*)
          nota="💤 MORTA-POR-INATIVIDADE (${motivo_kill#MOTIVO_KILL:INATIVIDADE:}min sem output) — não é timeout de relógio; o executor parou de produzir texto (ver $id.saida.txt)."
          ;;
        MOTIVO_KILL:TETO-DURO:*)
          nota="⏱️ TETO-DURO-4h (${motivo_kill#MOTIVO_KILL:TETO-DURO:}min corridos) — output ainda saía mas ultrapassou o teto máximo de segurança; DIVIDIR em passos menores (convencoes.md)."
          ;;
        *)
          nota="⏱️ SAIDA-VAZIA — executor não devolveu texto (tarefa grande demais? dividir em passos menores — ver convencoes.md)"
          ;;
      esac
    elif [ -z "$vline" ] && [ "$vazio" -eq 0 ]; then
      # PARIDADE 2.2: o executor PRODUZIU trabalho e só o juiz falhou. Isto NÃO é falha da tarefa.
      # Fecha como concluída com revisão pendente (nunca `travada`, nunca Telegram) e entra na
      # lista revista no daily-pulse. Zona vermelha continua a ser a ÚNICA coisa que chama o Danilo.
      nota="⚖️ CONCLUÍDA COM REVISÃO PENDENTE — trabalho feito, mas o juiz não devolveu VEREDITO em 3 tentativas (só o juiz foi re-tentado; a tarefa correu 1x). Revisão humana na lista do daily-pulse."
    elif [ -z "$vline" ]; then
      nota="⚖️ JUIZ-SEM-VEREDITO — juiz não devolveu linha VEREDITO e o executor também não produziu saída (ver $id.saida.txt)"
    elif [ -n "$motivo" ] && [ "$motivo" != "$vline" ]; then
      nota="$motivo"
    else
      nota="❓ CORRIGIR sem motivo explícito (ver $id.saida.txt)"
    fi
    setf nota "$nota" "$f"

    if [ -n "$cli_line" ]; then   # FASE 1.11: CLI ausente — trava À 1.ª, retentar não a instala
      setf estado travada "$f"
      log "ordem $id: TRAVADA (CLI do executor nao encontrada — ato humano) — $nota"
      ultima_veredito="TRAVADA-CLI"; missao_travada_ou_silencio "$f" "$missao" "$passo"
    elif [ -n "$auth_line" ]; then   # FASE 1.11 item 4: auth morta — trava À 1.ª, retentar não renova
      setf estado travada "$f"
      log "ordem $id: TRAVADA (executor sem auth — ato humano: claude setup-token) — $nota"
      ultima_veredito="TRAVADA-AUTH"; missao_travada_ou_silencio "$f" "$missao" "$passo"
    elif [ -z "$vline" ] && [ "$vazio" -eq 0 ]; then
      # PARIDADE 2.2: fecha CONCLUÍDA (o trabalho existe), com revisão pendente. ZERO Telegram —
      # `missao_travada_ou_silencio` NÃO é chamado de propósito: não é travamento, é revisão em falta.
      setf estado concluida "$f"
      setf revisao pendente "$f"
      printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$id" "juiz sem veredito em 3 tentativas" >> "$REVISAO_PENDENTE"
      log "ordem $id: CONCLUÍDA COM REVISÃO PENDENTE (juiz mudo 3x; tarefa correu 1x, não repetida) — sem Telegram"
      ultima_veredito="REVISAO-PENDENTE"
    elif [ "$vazio" -eq 1 ] && [ "$tent" -ge 2 ]; then   # saida vazia não re-tenta 5x
      setf estado travada "$f"
      setf nota "$nota (x$tent — não re-tento a mesma coisa)" "$f"
      log "ordem $id: TRAVADA (não re-tenta tarefa vazia/inativa) — $nota"; ultima_veredito="TRAVADA-VAZIA"; missao_travada_ou_silencio "$f" "$missao" "$passo"
    elif [ "$tent" -ge 5 ]; then
      setf estado travada "$f"; log "ordem $id: TRAVADA (5 tentativas) — nota: $nota"; ultima_veredito="TRAVADA"; missao_travada_ou_silencio "$f" "$missao" "$passo"
    else
      setf estado aberta "$f"; log "ordem $id: CORRIGIR -> reaberta (nota: $nota)"; ultima_veredito="CORRIGIR"; n_corrigir=$((n_corrigir+1))
    fi
  fi
  sync_espelho
done

# ---- FILA VAZIA / TERMINAL LIMPO (2026-07-16, substitui o aviso f523 por relógio) ----
# Gatilho por EVENTO: dispara 1x na TRANSIÇÃO ocupado->vazio (o heartbeat-desktop por relógio
# já foi desativado pelo Danilo). Estado em $FILA_ESTADO (linha1=ocupada|vazia, linha2=epoch
# do último aviso ENVIADO) para (a) só notificar na transição real, nunca a cada ciclo ocioso
# com a fila já vazia, e (b) cooldown de 30min — se a fila esvaziar/encher várias vezes numa
# janela curta (ex.: encadeamento de missão rápido), só a primeira notifica; o timestamp só
# avança quando uma notificação é REALMENTE enviada (fica parado enquanto suprimida).
pendentes=0
for f in "$FILA"/*.md; do
  [ -f "$f" ] || continue
  case "$f" in */_controlo.md) continue;; esac
  case "$(get estado "$f")" in aberta|executando|respondida) pendentes=$((pendentes+1));; esac
done
estado_ant=$(sed -n '1p' "$FILA_ESTADO" 2>/dev/null)
ultimo_aviso=$(sed -n '2p' "$FILA_ESTADO" 2>/dev/null); ultimo_aviso=${ultimo_aviso:-0}
agora=$(date +%s)
if [ "$pendentes" -eq 0 ]; then
  if [ "$estado_ant" != "vazia" ]; then
    if [ $((agora - ultimo_aviso)) -ge 1800 ]; then
      notify "🧹 Fila vazia — todas as tarefas terminadas. Última: ${ultima_id:-(nenhuma)} (${ultima_veredito:-sem veredito}). Resumo do ciclo: ${n_aprovadas} aprovadas, ${n_corrigir} corrigir."
      log "FILA-VAZIA: transição ocupado->vazio -> Telegram (última=${ultima_id:-?}/${ultima_veredito:-?}, ciclo=${n_aprovadas}a/${n_corrigir}c)"
      wake_out=$(pc_wake_heartbeat); wake_rc=$?
      if [ "$wake_rc" -eq 0 ]; then
        log "FILA-VAZIA: schtask Bora-heartbeat-desktop disparado via ponte PC (rc=0)"
      else
        log "FILA-VAZIA: schtask Bora-heartbeat-desktop falhou (rc=$wake_rc), Telegram já notificou — saída: $(printf '%s' "$wake_out" | tr '\n' ' ' | cut -c1-300)"
      fi
      ultimo_aviso="$agora"
    else
      log "FILA-VAZIA: transição ocupado->vazio dentro do cooldown de 30min — silêncio"
    fi
  fi
  printf 'vazia\n%s\n' "$ultimo_aviso" > "$FILA_ESTADO"
else
  printf 'ocupada\n%s\n' "$ultimo_aviso" > "$FILA_ESTADO"
fi
log "ciclo terminado"
