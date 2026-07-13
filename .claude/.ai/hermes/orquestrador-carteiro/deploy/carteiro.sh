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
#   • nota NUNCA vazia — todo ramo de falha grava causa (RATE-LIMIT/TIMEOUT-2400s/SAIDA-VAZIA/
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

ts(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
log(){ echo "[$(ts)] $*" >> "$LOG"; }
get(){ grep -E "^$1:" "$2" 2>/dev/null | head -1 | sed "s/^$1: *//" | tr -d '\r'; }
setf(){ if grep -qE "^$1:" "$3"; then sed -i "s|^$1:.*|$1: $2|" "$3"; else echo "$1: $2" >> "$3"; fi; }
notify(){ docker exec -u hermes "$C" hermes send -t telegram "$1" >/dev/null 2>&1 || log "notify(best-effort) falhou"; }
clean(){ grep -vE '^\[ponte\]|^\[loop\]|^\[juiz\]|Permission deny rule|matches no known tool' ; }
sync_espelho(){ docker exec -u hermes -e HOME=/opt/data -i "$C" sh -s fast < /root/cortex-mcp/sync-brain.sh >> "$LOG" 2>&1 && log "espelho sincronizado (fast)" || log "sync espelho (best-effort) falhou"; }

pc_exec(){ printf '%s' "$1" > "$HOSTDATA/orq_task.txt"
  # FASE 1.6 (2026-07-13, elo 6): a causa raiz do bloqueio era bora-live-parser.ps1 preso sem
  # EOF (ver inbox/investigacao-cadeia-ordens-2026-07-13.md) -- corrigido com StreamReader.
  # Testado reduzir este teto para 300s como rede de seguranca extra, mas cortou a meio uma
  # ordem legitima (233a, a editar/testar ficheiros reais) antes dela terminar -- 900s respeitava
  # o orcamento de "1 ordem <=15min" ja documentado acima.
  # 2026-07-13 (pedido Danilo): alargado 900->2400s (40min) para dar tempo a ordens grandes
  # legitimas terminarem sem serem cortadas. A cura real continua a ser o fix do parser (acima).
  docker exec -u hermes "$C" sh -lc 'export PATH=/opt/data/.local/bin:$PATH; timeout 2400 pc-loop "$(cat /opt/data/orq_task.txt)"' 2>&1 | clean; }
pc_judge(){ printf '%s' "$1" > "$HOSTDATA/orq_judge.txt"
  docker exec -u hermes "$C" sh -lc 'export PATH=/opt/data/.local/bin:$PATH; timeout 400 pc-judge "$(cat /opt/data/orq_judge.txt)"' 2>&1 | clean; }

# ---------------- LOCK-OCUPADO: executor.lock do PC recusou arrancar claude.exe ----------------
# FASE 1.7 (2026-07-13): 6 ordens seguidas (4c87/859a/858e/14bc/93e0/39c5) travaram rotuladas
# "JUIZ-SEM-VEREDITO" -- prova (saida.txt) mostrou que NENHUMA chegou a executar: o
# executor-lock.ps1 (FASE 1.5) recusou por "outro executor ja em curso" e o juiz foi chamado
# em cima dessa mensagem de erro (sem sentido para avaliar), devolvendo lixo sem "VEREDITO:".
# Deteta isto ANTES do juiz: não gasta tentativa, não chama o juiz, reabre para a próxima volta.
is_lock_busy(){ printf '%s' "$1" | grep -iqE "outro executor Bora ja em curso|ERRO: lock ocupado"; }

# ---------------- RATE-LIMIT: deteção + cálculo de retoma ----------------
is_rate_limit(){ printf '%s' "$1" | grep -iqE "hit your (session|usage) limit|session limit|usage limit|rate limit|reached your (usage|session)? *limit"; }
# "resets 5pm (Europe/London)" -> epoch UTC; se não parsear -> now+3600 (defensivo).
rl_resume_epoch(){
  local txt hh ap now h24 ep
  txt=$(printf '%s' "$1" | grep -oiE "resets[^0-9]*[0-9]{1,2} *(am|pm)" | head -1)
  hh=$(printf '%s' "$txt" | grep -oE '[0-9]{1,2}' | head -1)
  ap=$(printf '%s' "$txt" | grep -oiE 'am|pm' | head -1 | tr 'A-Z' 'a-z')
  now=$(date +%s)
  if [ -n "$hh" ] && [ -n "$ap" ]; then
    h24=$hh
    [ "$ap" = pm ] && [ "$hh" != 12 ] && h24=$((hh+12))
    [ "$ap" = am ] && [ "$hh" = 12 ] && h24=0
    ep=$(TZ='Europe/London' date -d "today ${h24}:00" +%s 2>/dev/null)
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
missao_travada_ou_silencio(){ # $1=of $2=mid $3=passo
  local mid="$2" p="$3" mf
  if [ -n "$mid" ]; then
    mf=$(missao_path "$mid"); [ -f "$mf" ] && missao_set_passo "$mf" "$p" "travada"
    notify "⛔ Bora/missão $mid: passo $p TRAVOU. Precisa de ti."
    log "missão $mid: passo $p travado -> Telegram"
  else
    log "ordem travada (sem missão) — sem Telegram (o watchdog escala se persistir >12h)"
  fi
}

# ---------------- MODOS AUXILIARES (não tocam a fila real de produção) ----------------
if [ "${1:-}" = "--selftest" ]; then
  fail=0; ok(){ echo "OK   $1"; }; bad(){ echo "FAIL $1"; fail=1; }
  is_rate_limit "You've hit your session limit · resets 5pm (Europe/London)" && ok "rate-limit detecta" || bad "rate-limit detecta"
  is_rate_limit "tudo bem, terminei a tarefa" && bad "rate-limit falso-positivo" || ok "rate-limit sem falso-positivo"
  now=$(date +%s)
  ep=$(rl_resume_epoch "resets 5pm (Europe/London)")
  [ "$ep" -gt "$now" ] && ok "reset 5pm -> epoch sempre futuro (nunca pausa no passado)" || bad "reset 5pm epoch futuro"
  ep2=$(rl_resume_epoch "sem hora nenhuma aqui")
  [ "$ep2" -gt "$now" ] && ok "reset sem hora -> futuro (now+1h defensivo)" || bad "reset defensivo"
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
fi

# T5 — kill switch
enabled=$(get orquestracao_enabled "$CTRL"); enabled=$(echo "${enabled:-false}" | tr 'A-Z' 'a-z')
if [ "$enabled" != "true" ]; then log "T5: kill switch OFF (enabled=$enabled) — nada a fazer"; exit 0; fi

for f in "$FILA"/*.md; do
  [ -f "$f" ] || continue
  case "$f" in */_controlo.md) continue;; esac
  [ "$(get estado "$f")" = "aberta" ] || continue
  id=$(get id "$f"); tarefa=$(get tarefa "$f"); tent=$(get tentativa "$f"); tent=${tent:-0}
  missao=$(get missao "$f"); passo=$(get passo "$f")
  log "ordem $id: aberta (tentativa=$tent)${missao:+ [missão $missao/$passo]}"

  # T3 — zona vermelha (dinheiro + intenção de escrita)
  if zona_vermelha "$tarefa"; then
    setf estado zona_vermelha "$f"; setf nota "🔴 ZONA VERMELHA — precisa de decisão humana (dinheiro)" "$f"
    log "ordem $id: 🔴 ZONA VERMELHA -> aprovacao humana"
    notify "🔴 Bora/orquestração: ordem $id toca zona vermelha (dinheiro) — precisa de ti."
    [ -n "$missao" ] && { mf=$(missao_path "$missao"); [ -f "$mf" ] && missao_set_passo "$mf" "$passo" "zona_vermelha"; }
    continue
  fi
  # T1 — teto 5
  if [ "$tent" -ge 5 ]; then setf estado travada "$f"
    [ -z "$(get nota "$f")" ] && setf nota "⛔ TRAVADA nas 5 tentativas" "$f"
    log "ordem $id: TRAVADA (5 tentativas)"; missao_travada_ou_silencio "$f" "$missao" "$passo"; continue; fi

  tent=$((tent+1)); setf tentativa "$tent" "$f"; setf estado executando "$f"
  saida=$(pc_exec "$tarefa"); printf '%s\n' "$saida" > "$FILA/$id.saida.txt"
  setf estado respondida "$f"; log "ordem $id: respondida (tentativa $tent)"
  vazio=0; [ -z "$(printf '%s' "$saida" | tr -d '[:space:]')" ] && vazio=1

  # ---- LOCK-OCUPADO: executor nem chegou a arrancar (outro claude.exe vivo no PC) — não
  # gasta tentativa nem chama o juiz (não há nada real para avaliar); reabre para a próxima
  # volta tentar de novo, sem queimar o teto T1 nem confundir com falha do juiz.
  if is_lock_busy "$saida"; then
    setf tentativa "$((tent-1))" "$f"
    setf estado aberta "$f"
    setf nota "🔒 LOCK-OCUPADO — outro executor Bora já em curso no PC; reagendado sem gastar tentativa." "$f"
    log "ordem $id: 🔒 LOCK-OCUPADO — reaberta sem gastar tentativa"
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
    break                                             # não processa mais nada até ao reset
  fi

  # juiz
  jinput=$(printf 'TAREFA:\n%s\n\nSAIDA DO EXECUTOR:\n%s\n' "$tarefa" "$(printf '%s' "$saida" | tail -50)")
  veredito=$(pc_judge "$jinput")
  vline=$(printf '%s' "$veredito" | grep -iE 'VEREDITO:' | head -1)
  log "ordem $id: ${vline:-<juiz sem veredito>}"

  if printf '%s' "$vline" | grep -iq 'APROVADA'; then
    setf estado aprovada "$f"; setf nota "" "$f"; log "ordem $id: APROVADA"
    if [ -n "$missao" ]; then missao_avanca "$missao" "$passo"
    else log "ordem $id: aprovada (sem missão) — silêncio (sem Telegram)"; fi
  else
    # ---- NOTA NUNCA VAZIA — causa explícita por construção ----
    motivo=$(printf '%s' "$vline" | sed 's/.*CORRIGIR: *//')
    if [ "$vazio" -eq 1 ]; then
      nota="⏱️ TIMEOUT-2400s / SAIDA-VAZIA — executor não devolveu texto (tarefa grande demais? dividir em passos menores — ver convencoes.md)"
    elif [ -z "$vline" ]; then
      nota="⚖️ JUIZ-SEM-VEREDITO — juiz não devolveu linha VEREDITO (ver $id.saida.txt; possível rate-limit/erro do juiz)"
    elif [ -n "$motivo" ] && [ "$motivo" != "$vline" ]; then
      nota="$motivo"
    else
      nota="❓ CORRIGIR sem motivo explícito (ver $id.saida.txt)"
    fi
    setf nota "$nota" "$f"

    if [ "$vazio" -eq 1 ] && [ "$tent" -ge 2 ]; then   # TIMEOUT não re-tenta 5x
      setf estado travada "$f"
      setf nota "⏱️ TIMEOUT-2400s x$tent — tarefa grande demais; DIVIDIR em passos menores (convencoes.md). Não re-tento a mesma coisa." "$f"
      log "ordem $id: TRAVADA-TIMEOUT (não re-tenta tarefa grande)"; missao_travada_ou_silencio "$f" "$missao" "$passo"
    elif [ "$tent" -ge 5 ]; then
      setf estado travada "$f"; log "ordem $id: TRAVADA (5 tentativas) — nota: $nota"; missao_travada_ou_silencio "$f" "$missao" "$passo"
    else
      setf estado aberta "$f"; log "ordem $id: CORRIGIR -> reaberta (nota: $nota)"
    fi
  fi
  sync_espelho
done
log "ciclo terminado"
