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
  # 2026-07-14 (pedido Danilo): timeout 3600 = 1h, decisao do Danilo para deixar tarefas grandes
  # rodarem a vontade; so cortar de verdade acima disso.
  # 2026-07-16 (PARTE A, superado): o timeout fixo acima matava execucoes vivas (ordem 7838).
  # A deteccao real de inatividade agora e' do stale-output-watchdog.ps1 no PC (ve cabecalho do
  # ficheiro); este timeout so fica como rede de seguranca externa (bridge/SSH pendurado) —
  # 14700s = 4h10min, sempre por CIMA do teto duro do PC (4h) para nunca disparar primeiro.
  docker exec -u hermes "$C" sh -lc 'export PATH=/opt/data/.local/bin:$PATH; timeout 14700 pc-loop "$(cat /opt/data/orq_task.txt)"' 2>&1 | clean; }
pc_judge(){ printf '%s' "$1" > "$HOSTDATA/orq_judge.txt"
  docker exec -u hermes "$C" sh -lc 'export PATH=/opt/data/.local/bin:$PATH; timeout 400 pc-judge "$(cat /opt/data/orq_judge.txt)"' 2>&1 | clean; }

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
missao_travada_ou_silencio(){ # $1=of $2=mid $3=passo
  local of="$1" mid="$2" p="$3" mf oid nota
  if [ -n "$mid" ]; then
    mf=$(missao_path "$mid"); [ -f "$mf" ] && missao_set_passo "$mf" "$p" "travada"
    nota=$(get nota "$of")
    notify "⛔ Bora/missão $mid: passo $p TRAVOU — ${nota:-precisa de ti}."
    log "missão $mid: passo $p travado -> Telegram"
  else
    # 2026-07-13 (ordem f523): avisos de travamento restaurados — antes ficava
    # mudo à espera do watchdog (>12h). Uma tarefa travada é sinal de que
    # precisa de decisão humana, não de silêncio.
    oid=$(get id "$of"); nota=$(get nota "$of")
    notify "⛔ Bora: tarefa $oid TRAVOU — ${nota:-motivo desconhecido}"
    log "ordem $oid: travada (sem missão) -> Telegram"
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

  # T3 — zona vermelha (dinheiro + intenção de escrita)
  if zona_vermelha "$tarefa"; then
    setf estado zona_vermelha "$f"; setf nota "🔴 ZONA VERMELHA — precisa de decisão humana (dinheiro)" "$f"
    log "ordem $id: 🔴 ZONA VERMELHA -> aprovacao humana"
    # 2026-07-14 (aviso-espera-telegram): antes o aviso só dizia "toca zona vermelha — precisa
    # de ti", sem dizer O QUE a ordem faz nem como desbloquear — o Danilo ficava a saber que
    # algo esperava, mas preso sem contexto nem ação direta. Agora leva o resumo da tarefa +
    # o comando exato de desbloqueio (a skill desbloqueio-zona-vermelha do Hermes trata o "vai $id").
    resumo=$(resumo_tarefa "$tarefa")
    notify "🔴 Bora/orquestração: ordem $id EM ESPERA (zona vermelha — toca dinheiro/pagamento).
Resumo: ${resumo:-(sem resumo)}
Para libertar para a fila normal, responde aqui: vai $id"
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
    if [ "$vazio" -eq 1 ]; then
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
    elif [ -z "$vline" ]; then
      nota="⚖️ JUIZ-SEM-VEREDITO — juiz não devolveu linha VEREDITO (ver $id.saida.txt; possível rate-limit/erro do juiz)"
    elif [ -n "$motivo" ] && [ "$motivo" != "$vline" ]; then
      nota="$motivo"
    else
      nota="❓ CORRIGIR sem motivo explícito (ver $id.saida.txt)"
    fi
    setf nota "$nota" "$f"

    if [ "$vazio" -eq 1 ] && [ "$tent" -ge 2 ]; then   # saida vazia não re-tenta 5x
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
