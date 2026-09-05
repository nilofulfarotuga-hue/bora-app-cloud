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
# COSTURAS DE TESTE (2026-08-11, FASE 1 SISTEMA-100) — todas DEFAULT-OFF: sem estas variáveis
# no ambiente, o comportamento é byte-a-byte o de antes (a fila viva, o log vivo, o Telegram
# real). Existem porque a prova exigida ("mostra a ordem a chegar ao fim por vários arranques")
# não se pode fazer a sério contra a fila de produção nem a mandar avisos verdadeiros ao Danilo.
# Com elas, os testes correm o CARTEIRO REAL — a mesma máquina de estados, os mesmos ramos — só
# que sobre uma fila descartável e com um executor de mentira que morre quando queremos.
# Testar uma cópia do código não provava nada; isto prova o código que corre a sério.
C=hermes-agent-fvnc-hermes-agent-1
HOSTDATA="${CARTEIRO_HOSTDATA:-/docker/hermes-agent-fvnc/data}"
FILA="${CARTEIRO_FILA:-$HOSTDATA/cortex-brain/orquestracao}"
CTRL="$FILA/_controlo.md"
LOG="${CARTEIRO_LOG:-/root/orquestracao/carteiro.log}"
LOCK="${CARTEIRO_LOCK:-/root/orquestracao/.carteiro.lock}"
PAUSA_TOTAL="$FILA/.pausa-total"           # STOP global (Danilo)
PAUSA_RL="$FILA/.pausa-rate-limit"         # pausa automática por rate-limit (guarda epoch de retoma)
# 2026-08-11: memória de que o PLANO Claude está esgotado (guarda o epoch do reset lido da
# própria mensagem). Diferente do PAUSA_RL: este NÃO pára a fila — só evita que cada ordem
# nova gaste um arranque de claude.exe a redescobrir o limite. Verde segue no Go, vermelha espera.
PLANO_ESGOTADO="$FILA/.plano-esgotado"
RL_AVISADO=/root/orquestracao/.rate-limit.avisado
# PARIDADE PARTE 2.2 (2026-08-01): ordens que CONCLUÍRAM mas cujo juiz não devolveu veredito.
# Vão para aqui (revisão humana no daily-pulse) em vez de `travada` + Telegram — não é travamento,
# é revisão em falta. Formato: <ts>\t<id ordem>\t<motivo>.
REVISAO_PENDENTE=/root/orquestracao/revisao-pendente.tsv
# I4: travadas NÃO-vermelhas arquivadas aqui em vez de Telegram (revistas no daily-pulse).
ARQUIVO_TRAVADAS=/root/orquestracao/travadas-arquivadas.tsv
LATCH_TRAVADA=/root/orquestracao/.travadas-avisadas   # 2026-08-11: latch por ordem (1 aviso/12h)
FILA_ESTADO=/root/orquestracao/.fila-estado   # transição ocupado<->vazio (2026-07-16, substitui f523):
                                               # linha1=ocupada|vazia, linha2=epoch do último aviso (cooldown 30min)
# FASE 2 SISTEMA-100 (2026-08-11): loop total com conselho — ver revisao_conselho() abaixo.
# CONSELHO_ENV é o MESMO .env do conselho-mcp (não duplica o segredo); se não existir, a
# revisão salta em silêncio (best-effort, nunca trava o fecho da ordem).
CONSELHO_ENV="${CONSELHO_ENV:-/root/conselho-mcp/.env}"
CONSELHO_URL="${CONSELHO_URL:-https://conselho.srv1786862.hstgr.cloud/}"
CONSELHO_RONDAS_MAX="${CONSELHO_RONDAS_MAX:-3}"
# Livro de bordo do conselho: uma linha por ronda, com consenso E divergência (ver revisao_conselho).
CONSELHO_REGISTO="${CONSELHO_REGISTO:-/root/orquestracao/conselho-registo.tsv}"
# FASE 3 (2026-08-11): acordar a Claude.ai quando uma ordem fecha, trava, ou fica à espera de
# autorização de dinheiro. Best-effort ABSOLUTO: nunca falha para fora, nunca trava uma ordem.
ACORDAR_CLAUDE="${ACORDAR_CLAUDE:-/root/orquestracao/acordar-claude.sh}"
acordar_claude(){ # $1=evento $2=id $3=estado $4=resumo
  [ -x "$ACORDAR_CLAUDE" ] || return 0
  [ -n "${CARTEIRO_NOTIFY_STUB:-}" ] && return 0   # em modo de prova não acorda ninguém a sério
  "$ACORDAR_CLAUDE" "$1" "$2" "$3" "$4" >/dev/null 2>&1 || true
}
# FASE 1 SISTEMA-100-AUTONOMO (2026-08-11): AUTO-FATIAMENTO + FAILOVER DE PLANO.
# CONT_MAX = teto ABSOLUTO de arranques encadeados por ordem. Bater no --max-turns deixou de
# gastar tentativa (é pausa, não falha), portanto sem este número uma ordem impossível ficava a
# arrancar para sempre. 12 arranques × 150 turnos é folga real para qualquer ordem legítima; lá
# chegar significa "grande demais mesmo fatiada" e trava com essa nota exata, nunca em silêncio.
CONT_MAX="${CONT_MAX:-12}"
# Motor de recurso quando o PLANO Claude (Pro) bate no limite: custo fixo, não esgota como o Pro.
# 2026-08-11: era `qwen3.8-max` — ERRADO. O 3.8 responde a TEXTO mas está em baixo do lado do
# fornecedor como MOTOR de agente ("Endpoint is unavailable"), por isso o salto antigo só podia
# produzir texto. O que corre COM FERRAMENTAS é o qwen3.7-max (ferramentas\motores\README.md,
# testado 2026-08-10; reconfirmado ao vivo 2026-08-11 a criar ficheiro na conta `hermes`).
GO_FAILOVER_MODELO="${GO_FAILOVER_MODELO:-qwen3.7-max}"
# ============================================================================================
# FASE 1 MISSÃO DE FECHO (2026-08-11 23:xx) — A CADEIA NÃO PODE FICAR PRESA NUM DEGRAU
# ============================================================================================
# MEDIDO no bora-live.log do Danilo:
#   [21:24:38] API Error: Request rejected (429) · 5-hour usage limit reached. Resets in 2hr 16min
#   [22:01:13] API Error: Request rejected (429) · 5-hour usage limit reached. Resets in 1hr 39min
# e, entre as duas, "MOTOR-GO ativo :: modelo=qwen3.7-max" às 21:25, 21:40 e 22:00 — o loop
# ficou 40 minutos a bater de 15/20 em 20 minutos contra um motor JÁ ESGOTADO.
# O plano OpenCode Go também tem janela de 5h: um único degrau de recurso não chega.
#
# CADEIA (ordem pedida pelo Danilo): Claude Pro -> qwen3.8-max -> qwen3.7-max -> minimax-m3
#                                    -> último recurso: Hermes na VPS (ferramentas próprias).
# NOTA HONESTA sobre o 1º degrau: a 2026-08-10 o qwen3.8-max respondia a TEXTO mas estava em
# baixo como MOTOR de agente ("Endpoint is unavailable"). Fica na cadeia porque foi o pedido e
# porque cada degrau se AUTO-VERIFICA: se não devolver trabalho, é marcado indisponível por
# COOLDOWN_FALHA e a cadeia desce sozinha. Não custa nada tentar; custava ficar preso.
GO_CADEIA="${GO_CADEIA:-qwen3.8-max qwen3.7-max minimax-m3}"
# Livro de esgotamentos POR MODELO: uma linha "modelo<TAB>epoch_do_reset". A hora vem lida da
# própria mensagem ("Resets in 2hr 16min"), como já se fazia para o plano Claude.
MOTORES_ESGOTADOS="${MOTORES_ESGOTADOS:-$FILA/.motores-esgotados}"
# Quando um degrau falha sem dizer porquê (endpoint em baixo, saída vazia), não se marca "5h" —
# marca-se um castigo curto, para ele voltar a ser tentado quando o fornecedor recuperar.
COOLDOWN_FALHA="${COOLDOWN_FALHA:-1800}"     # 30 min
# Janela assumida quando a mensagem de limite não traz os minutos (o plano Go é de 5 horas).
JANELA_GO_DEFAULT="${JANELA_GO_DEFAULT:-300}"  # minutos
# go_failover corre em subshell `$(...)`; variáveis não sobem. Estes ficheiros são o canal de volta.
GO_MOTOR_USADO_F="$FILA/.go-motor-usado"
# Latch do aviso "todos os degraus esgotados" — UMA vez, não a cada 20 minutos (pedido 3 da FASE 1).
CADEIA_AVISADO="$FILA/.cadeia-esgotada.avisado"
HERMES_CONTAINER="${HERMES_CONTAINER:-hermes-agent-fvnc-hermes-agent-1}"

# T3 money-filter. -iE (case-insensitive). 2026-07-11: menos sensível a PALAVRAS
# (ver wiki/licoes/classificador-zona-menos-sensivel-a-palavras.md). Vermelho exige INTENÇÃO
# DE ESCRITA: RED_ALWAYS = destrutivo por si só; RED_TERMS = domínio $; WRITE_INTENT = verbo de
# escrita; NEG = negação. Proteção real intacta.
#
# FIX 2026-08-01 (missao sistema-redondo, ordem-20260801071337-3cb4): o NEG antigo
# `(sem|nao|...) +UMA palavra` só apagava a negação + o próximo token — frases reais em PT quase
# nunca colam o verbo logo a seguir ("não DEVE mexer", "nunca, em circunstância nenhuma, vai
# ALTERAR") e o verbo de escrita sobrevivia à limpeza, continuando a bater com WRITE_INTENT mesmo
# sob negação explícita. Agora a negação é por CLÁUSULA: a tarefa é dividida em fronteiras de
# frase (`. ! ? ; \n`) e em conjunções contrastivas (`mas/porém/contudo/entretanto`, que reiniciam
# a polaridade dentro do mesmo período) — RED_TERMS + WRITE_INTENT só contam vermelho se não
# houver NEG em QUALQUER ponto da MESMA cláusula (antes ou depois do termo, sem limite de
# distância). Uma negação noutra cláusula (separada por "mas" ou por ponto) não apaga um termo
# genuíno mais à frente — evita o extremo oposto de suprimir tudo por haver "não" em qualquer
# lugar do texto. RED_ALWAYS continua INCONDICIONAL (design deliberado: comandos destrutivos como
# --force/reset --hard são vermelho mesmo mencionados sob proibição — ver lição 2026-07-11).
RED_ALWAYS='disable row level|--force|force.?with.?lease|reset .*--hard|force.?push'
RED_TERMS='dispatch_engine|pricing_service|finalizePurchase|bora[ _]tokens?|tokens?_applied|tvde[a-z_ ]*tokens?|stripe|payment|webhook|wallet|ledger|refund|payout|commission|platform_settings'
WRITE_INTENT='mud(a|ar|e|ei|ou|anca|ança)|atualiz|altera|modific|mexer?|edita|reescrev|refator|aplica|grava|escrev|deploy|remov|apaga|dropa|insere|inserir|configura|corrig|ajusta|\b(UPDATE|INSERT|DELETE|ALTER|DROP|TRUNCATE)\b'
# FIX 2026-08-05 (ordem 7bcc): NEG cobria "não/sem/nunca/jamais/nem" mas não "proibido" — a Parte 1
# de 01/08 já tinha achado isto em flagrante (prop-5345589b, "PROIBIDO tocar EFs de dinheiro") e
# ficou por corrigir. Confirmado ao vivo: "É proibido mexer no pricing_service" continuava VERMELHA
# (RED_TERMS+WRITE_INTENT na cláusula, NEG não via "proibido" como negação). Aditivo: só acrescenta
# o radical "proibid" (cobre proibido/proibida/proibição/proibitivo) — nada removido de RED_TERMS/
# RED_ALWAYS/WRITE_INTENT, proteção real intacta (ver prova em classificador-zona-prova-2026-08-05.md).
NEG='\b(sem|nao|não|nunca|jamais|nem)\b|proibid'
zona_vermelha(){ # $1=tarefa -> 0 (vermelho) / 1 (verde)
  echo "$1" | grep -iqE "$RED_ALWAYS" && return 0
  local clausulas clausula
  clausulas=$(printf '%s' "$1" | sed -E 's/[.!?;]+/\n/g' | sed -E 's/\b(mas|porem|porém|contudo|entretanto)\b/\n/gi')
  while IFS= read -r clausula; do
    [ -z "$clausula" ] && continue
    echo "$clausula" | grep -iqE "$RED_TERMS" || continue
    echo "$clausula" | grep -iqE "$WRITE_INTENT" || continue
    echo "$clausula" | grep -iqE "$NEG" && continue   # mesma clausula nega a escrita -> nao conta
    return 0
  done <<< "$clausulas"
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
notify(){
  # COSTURA DE TESTE (default-off): nas provas os avisos vão para um ficheiro em vez do Telegram
  # real — provar o mecanismo não pode custar spam ao Danilo. Sem a variável, vai para o Telegram.
  if [ -n "${CARTEIRO_NOTIFY_STUB:-}" ]; then printf '%s\n---\n' "$1" >> "$CARTEIRO_NOTIFY_STUB"; return; fi
  # 2026-08-11 (ENTREGAS FANTASMA): a versão antiga mandava a resposta do servidor para
  # /dev/null. Resultado: NUNCA ficava prova de que a mensagem tinha sido aceite — e uma ordem
  # podia jurar "avisei o Danilo no Telegram" sem que nada tivesse chegado, exatamente o que
  # aconteceu na ordem-20260811143542-1fa4. Agora a ACEITAÇÃO fica registada no log, literal.
  local _resp _rc
  _resp=$(docker exec -u hermes "$C" hermes send -t telegram "$1" 2>&1); _rc=$?
  if [ "$_rc" -eq 0 ]; then
    log "notify: ACEITE pelo servidor -> $(printf '%s' "$_resp" | tr '\n' ' ' | cut -c1-160)"
  else
    log "notify(best-effort) FALHOU rc=$_rc -> $(printf '%s' "$_resp" | tr '\n' ' ' | cut -c1-160)"
  fi; }
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

# ---------------- FASE 2 SISTEMA-100 (2026-08-11): LOOP TOTAL COM CONSELHO ----------------
# Ao fechar uma ordem avulsa (sem missão) que o Juiz mecânico já aprovou, uma segunda opinião
# (3 modelos do go_conselho, cada um por si) revê o resumo+resultado. NUNCA decide o gate — o
# Juiz mecânico continua o portão duro, isto só corre DEPOIS de "APROVADA" já estar decidido.
# Se ≥2 vozes pedirem ajuste concreto (marcador CONSELHO: AJUSTAR, nunca palavra solta — grep de
# palavras soltas tipo "falta/errado" apanha "não falta nada" como falso positivo, o mesmo erro
# de classe já documentado no NEG de zona_vermelha() acima), a ordem reabre com a crítica anexa
# SÓ na chamada ao executor (nunca no campo tarefa: — esse é lido linha-a-linha por get() em todo
# o resto do ficheiro; escrever texto multi-linha lá corromperia essa leitura). Teto de 3 rondas
# (CONSELHO_RONDAS_MAX): a quota semanal do plano Go é partilhada, nunca ciclo infinito. Qualquer
# falha (VPS do conselho em baixo, rede, JSON ilegível) é best-effort — fecha a ordem exatamente
# como já fechava antes desta função existir.
conselho_divergiu(){ # $1=texto do conselho -> "sim" se >=2 vozes pedem ajuste E mais que as que dizem OK
  local t="$1" n_aj n_ok
  n_aj=$(printf '%s' "$t" | grep -c 'CONSELHO: *AJUSTAR')
  n_ok=$(printf '%s' "$t" | grep -c 'CONSELHO: *OK')
  if [ "$n_aj" -ge 2 ] && [ "$n_aj" -gt "$n_ok" ]; then echo sim; else echo nao; fi
}
revisao_conselho(){ # $1=of $2=id $3=tarefa $4=saida -> stdout: "DIVERGENCIA" ou "CONSENSO" (vazio se saltou)
  local of="$1" id="$2" tarefa="$3" saida="$4" token ronda resumo_saida corpo_json resposta_txt texto_conselho
  [ -f "$CONSELHO_ENV" ] || { log "ordem $id: conselho — sem $CONSELHO_ENV, salto (best-effort)"; return 0; }
  token=$(grep -m1 '^CONSELHO_TOKEN=' "$CONSELHO_ENV" 2>/dev/null | cut -d= -f2-)
  [ -n "$token" ] || { log "ordem $id: conselho — sem CONSELHO_TOKEN, salto"; return 0; }

  ronda=$(get conselho_ronda "$of"); ronda=${ronda:-0}; ronda=$((ronda+1))
  if [ "$ronda" -gt "$CONSELHO_RONDAS_MAX" ]; then
    log "ordem $id: conselho — teto de $CONSELHO_RONDAS_MAX rondas já atingido, fecho sem nova consulta"
    return 0
  fi

  resumo_saida=$(printf '%s' "$saida" | tail -c 6000)
  corpo_json=$(TAREFA="$tarefa" RESUMO="$resumo_saida" python3 -c '
import json, os
print(json.dumps({
  "jsonrpc": "2.0", "id": 1, "method": "tools/call",
  "params": {"name": "go_conselho", "arguments": {
    "tarefa": ("Reve este fecho de uma ordem do loop autonomo do Bora. Diz em 2-4 pontos curtos "
               "o que reparaste. NA ULTIMA LINHA da tua resposta escreve exatamente uma destas "
               "duas: \"CONSELHO: OK\" (tudo bem, mesmo com sugestoes menores) ou "
               "\"CONSELHO: AJUSTAR\" (so se houver algo CONCRETO e IMPORTANTE por corrigir). "
               "Na duvida escreve OK - nao travas o fecho por preferencia de estilo."),
    "contexto": [{"nome": "tarefa pedida", "texto": os.environ["TAREFA"]},
                 {"nome": "resultado do executor (fim)", "texto": os.environ["RESUMO"]}],
    # FASE 5 (2026-08-11): HERMES COMO 4.ª VOZ. O servidor do conselho já o sabia invocar
    # (chamar_hermes -> HERMES_SHIM_URL, um shim HTTP — NENHUMA senha de administrador é
    # guardada em lado nenhum, era essa a condição). O que faltava era o carteiro pedi-lo.
    # Ele acrescenta o que os outros três não têm: memória do projeto e pesquisa web —
    # provado a 2026-08-11 com uma pergunta que só se responde assim.
    # Custo: é o mais lento dos quatro (~17s medido, contra ~3s dos outros). O `--max-time 200`
    # do curl abaixo é o travão: se ele se atrasar, a resposta chega sem ele e o fecho segue —
    # o conselho nunca fica refém da voz mais lenta.
    "modelos": ["glm-5.2", "qwen3.7-max", "minimax-m3", "hermes"]
  }}
}, ensure_ascii=False))
' 2>/dev/null)
  [ -n "$corpo_json" ] || { log "ordem $id: conselho — falha a montar o pedido JSON, salto"; return 0; }

  resposta_txt=$(curl -s --max-time 200 -X POST "$CONSELHO_URL" \
    -H "Authorization: Bearer $token" -H "Content-Type: application/json" \
    -d "$corpo_json" 2>/dev/null)
  [ -n "$resposta_txt" ] || { log "ordem $id: conselho — sem resposta (rede/timeout), fecho sem revisão"; return 0; }

  texto_conselho=$(RESP="$resposta_txt" python3 -c '
import json, os, sys
try:
    d = json.loads(os.environ["RESP"])
    print(d["result"]["content"][0]["text"])
except Exception as e:
    sys.stderr.write(str(e))
' 2>/dev/null)
  [ -n "$texto_conselho" ] || { log "ordem $id: conselho — resposta ilegivel, fecho sem revisão"; return 0; }

  setf conselho_ronda "$ronda" "$of"
  printf '%s\n' "$texto_conselho" > "$FILA/$id.conselho-r$ronda.txt"
  log "ordem $id: conselho revisto (ronda $ronda/$CONSELHO_RONDAS_MAX) -> $id.conselho-r$ronda.txt"

  local vd n_aj n_ok
  if [ "$(conselho_divergiu "$texto_conselho")" = sim ]; then vd=DIVERGENCIA; else vd=CONSENSO; fi
  # FASE 2 (2026-08-11): REGISTAR CONSENSO **E** DIVERGÊNCIAS. Antes só ia para o log corrido,
  # onde se perde, e a contagem de vozes (quantas pediram ajuste vs quantas disseram OK) não
  # ficava em lado nenhum. Sem isso não se responde à pergunta que interessa — "o conselho
  # costuma concordar com o que o loop produz?" — nem se apanha um modelo que discorda sempre.
  # Uma linha por ronda, TSV, para o daily-pulse ler.
  n_aj=$(printf '%s' "$texto_conselho" | grep -c 'CONSELHO: *AJUSTAR')
  n_ok=$(printf '%s' "$texto_conselho" | grep -c 'CONSELHO: *OK')
  printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$id" "$ronda" "$vd" "ajustar=$n_aj" "ok=$n_ok" \
    >> "$CONSELHO_REGISTO" 2>/dev/null || true
  echo "$vd"
}

# ---------------- FASE 1 SISTEMA-100 (2026-08-11): FAILOVER DE PLANO ----------------
# Quando o PLANO Claude Pro bate no limite, o trabalho parava até ao reset (podia ser meio dia).
# Pedido explícito do Danilo: a tarefa NÃO pode parar — continua no motor mais forte do OpenCode
# Go (custo fixo, não esgota como o Pro), retomando pelos marcos já feitos.
#
# CORRIGIDO 2026-08-11 (ENTREGAS FANTASMA — causa raiz descoberta pelo Danilo):
# ------------------------------------------------------------------------------------------
# COMO ERA (defeito): este caminho fazia um curl de TEXTO ao conselho-mcp (tool `go_perguntar`).
# Um modelo chamado por texto NAO TEM FERRAMENTAS — nao escreve ficheiros, nao corre comandos,
# nao abre browser, nao envia Telegram. Ele apenas DESCREVIA o trabalho; o carteiro colhia as
# linhas `MARCO:` desse texto e a ordem fechava como concluida SEM NADA TER SIDO FEITO.
# Prova: ordem-20260811143542-1fa4 fechou `estado: concluida`, `motor_final: qwen3.8-max`, com
# 5 marcos todos do genero "pronto para executar / pronto para gravar / pronto para colar" — e a
# rotina nunca foi criada nem chegou mensagem ao Telegram. O Danilo estava a ver a janela do loop
# e NAO viu sessao nenhuma arrancar, porque de facto nenhuma arrancou (`_saltou_claude=1`).
#
# COMO E' AGORA: o salto arranca uma SESSAO REAL DE AGENTE — o MESMO executor de sempre
# (claude.exe com ferramentas no PC, via pc-loop-go -> run-claude-loop.cmd --motor-go), so
# trocando o MOTOR por tras para o plano OpenCode Go (custo fixo, nao esgota como o Pro).
# Caminho ja provado: ferramentas\motores\_motor.cmd (2026-08-10) e reconfirmado ao vivo a
# 2026-08-11 na propria conta `hermes` (criou ficheiro com a ferramenta Write).
#
# MODELO: qwen3.7-max, NAO qwen3.8-max. O 3.8 responde a texto mas esta em baixo do lado do
# fornecedor como MOTOR ("Endpoint is unavailable") — era mais uma razao para o salto antigo so
# poder produzir texto. Ver ferramentas\motores\README.md.
#
# EXCEÇÃO DE SEGURANÇA (regra do Danilo): ordem em zona vermelha NUNCA passa para o Go. Aí é
# melhor esperar pelo Pro do que arriscar dinheiro/dispatch no modelo mais fraco.
# ---------------- FASE 1 MISSÃO DE FECHO: LIVRO DE ESGOTAMENTOS **POR MODELO** ----------------
# O plano Claude já tinha memória (.plano-esgotado). Os motores do Go não tinham nenhuma, por
# isso o loop voltava a bater no mesmo motor morto de 20 em 20 minutos. Uma linha por modelo:
#   <modelo>\t<epoch do reset>
motor_esgotado_ate(){ # $1=modelo -> epoch futuro, ou 0 se está disponível
  local m="$1" now ep
  [ -f "$MOTORES_ESGOTADOS" ] || { echo 0; return; }
  now=$(date +%s)
  ep=$(awk -F'\t' -v m="$m" '$1==m{v=$2} END{print v+0}' "$MOTORES_ESGOTADOS" 2>/dev/null)
  ep=$(printf '%s' "${ep:-0}" | tr -dc '0-9'); ep=${ep:-0}
  [ "$ep" -gt "$now" ] && { echo "$ep"; return; }
  echo 0
}
motor_marcar_esgotado(){ # $1=modelo $2=epoch $3=motivo
  local m="$1" ep="$2" motivo="${3:-}" tmp
  tmp="${MOTORES_ESGOTADOS}.tmp.$$"
  if [ -f "$MOTORES_ESGOTADOS" ]; then awk -F'\t' -v m="$m" '$1!=m' "$MOTORES_ESGOTADOS" > "$tmp" 2>/dev/null || : ; fi
  printf '%s\t%s\n' "$m" "$ep" >> "$tmp"
  mv -f "$tmp" "$MOTORES_ESGOTADOS" 2>/dev/null || true
  log "motor $m marcado ESGOTADO ate $(hhmm "$ep") UTC${motivo:+ ($motivo)}"
}
eh_motor_go(){ case " $GO_CADEIA " in *" $1 "*) return 0;; esac; return 1; }
motor_do_sinal(){ # lê ##BORA-MOTOR##: <modelo> que o parser do PC passou a emitir
  printf '%s' "$1" | sed -n 's/.*##BORA-MOTOR##: *\([^ ]*\).*/\1/p' | head -1; }
# Minutos até o reset lidos da PRÓPRIA mensagem ("Resets in 2hr 16min" -> 136), como já se fazia
# para o "resets 4:10pm" do Claude. Sem minutos na mensagem, assume a janela de 5h do plano Go.
go_reset_epoch(){ # $1=saida -> epoch em que ESTE motor volta
  local txt mins h m now
  now=$(date +%s)
  txt=$(printf '%s' "$1" | tr -d '\r')
  mins=$(printf '%s' "$txt" | sed -n 's/.*##BORA-RESET-MIN##: *\([0-9][0-9]*\).*/\1/p' | head -1)
  mins=${mins:-0}
  if [ "$mins" -le 0 ] 2>/dev/null; then
    h=$(printf '%s' "$txt" | grep -oiE 'resets in *[0-9]+ *hr' | grep -oE '[0-9]+' | head -1)
    m=$(printf '%s' "$txt" | grep -oiE '(hr|resets in) *[0-9]+ *min' | grep -oE '[0-9]+' | tail -1)
    h=${h:-0}; m=${m:-0}
    mins=$((h*60+m))
  fi
  [ "$mins" -gt 0 ] 2>/dev/null || mins="$JANELA_GO_DEFAULT"
  echo $((now + mins*60))
}
cadeia_proximo_reset(){ # -> epoch do PRIMEIRO degrau a repor; 0 se algum degrau está vivo
  local m ep best=0
  for m in $GO_CADEIA; do
    ep=$(motor_esgotado_ate "$m")
    [ "$ep" -eq 0 ] && { echo 0; return; }
    { [ "$best" -eq 0 ] || [ "$ep" -lt "$best" ]; } && best="$ep"
  done
  echo "$best"
}
# ÚLTIMO DEGRAU: o Hermes, na própria VPS, com as ferramentas dele. Não depende do plano Go nem
# do plano Claude — é o que sobra quando os dois fecham a porta.
hermes_ultimo_recurso(){ # $1=tarefa -> stdout (vazio = falhou)
  local out
  if [ -n "${CARTEIRO_HERMES_STUB:-}" ] && [ -x "${CARTEIRO_HERMES_STUB:-}" ]; then
    printf '%s' "$1" | "$CARTEIRO_HERMES_STUB"; return
  fi
  printf '%s' "$1" > "$HOSTDATA/orq_task_hermes.txt"
  out=$(docker exec -u hermes "$HERMES_CONTAINER" sh -lc 'timeout 3600 hermes chat -q "$(cat /opt/data/orq_task_hermes.txt)"' 2>&1 | clean)
  printf '%s' "$out" | grep -qiE 'not logged|authentication failed|command not found' && return 1
  [ -n "$out" ] || return 1
  printf '%s' "$out"
}

go_failover(){ # $1=tarefa $2=ficheiro de marcos -> stdout: saida real (vazio = cadeia toda em baixo)
  local tarefa="$1" marcosf="$2" feitos="" retoma="" saida_go="" modelo="" ep=0
  : > "$GO_MOTOR_USADO_F" 2>/dev/null || true
  # COSTURA DE TESTE (2026-08-11, mesma família de CARTEIRO_EXEC_STUB/JUDGE_STUB): default-OFF.
  if [ -n "${CARTEIRO_GO_STUB:-}" ] && [ -x "${CARTEIRO_GO_STUB:-}" ]; then
    printf '%s' "$tarefa" | "$CARTEIRO_GO_STUB"; return
  fi
  [ -s "$marcosf" ] && feitos=$(cat "$marcosf")
  [ -n "$feitos" ] && retoma="

--- JA ESTA FEITO (nao repitas, continua a partir daqui) ---
$feitos"
  # O executor do Go recebe a MESMA tarefa e as MESMAS ferramentas. A unica coisa que muda em
  # relacao a uma corrida normal e' o motor — por isso NAO se lhe diz "nao tens acesso ao disco"
  # (era essa frase que, no caminho antigo, o convidava a descrever em vez de fazer).
  # Nome do ficheiro da tarefa: parametrizável para que a prova (--prova-cadeia) NUNCA escreva
  # por cima da tarefa de uma ordem de produção que esteja a correr ao mesmo tempo.
  _taskf="${ORQ_TASK_BASENAME:-orq_task.txt}"
  printf '%s' "$tarefa$retoma" > "$HOSTDATA/$_taskf"
  # ---- A CADEIA: cada degrau só é usado se o anterior estiver marcado como esgotado ----
  for modelo in $GO_CADEIA; do
    ep=$(motor_esgotado_ate "$modelo")
    if [ "$ep" -gt 0 ]; then
      log "cadeia: degrau $modelo ESGOTADO ate $(hhmm "$ep") UTC — salto (nao gasto arranque)"
      continue
    fi
    log "cadeia: a tentar o degrau $modelo"
    saida_go=$(docker exec -u hermes -e ORQ_MODELO="$modelo" -e ORQ_TASKF="$_taskf" -e ORQ_TIMEOUT="${GO_TIMEOUT:-14700}" "$C" sh -lc 'export PATH=/opt/data/.local/bin:$PATH; timeout "$ORQ_TIMEOUT" pc-loop-go --modelo "$ORQ_MODELO" "$(cat "/opt/data/$ORQ_TASKF")"' 2>&1 | clean)
    if [ -z "$saida_go" ]; then
      log "cadeia: $modelo nao devolveu saida — castigo curto de $((COOLDOWN_FALHA/60))min e desco"
      motor_marcar_esgotado "$modelo" "$(( $(date +%s) + COOLDOWN_FALHA ))" "sem saida"
      continue
    fi
    if is_rate_limit "$saida_go"; then
      ep=$(go_reset_epoch "$saida_go")
      motor_marcar_esgotado "$modelo" "$ep" "429 do plano Go"
      log "cadeia: $modelo bateu no limite — volta $(hhmm "$ep") UTC; desco ao degrau seguinte"
      continue
    fi
    printf '%s' "$modelo" > "$GO_MOTOR_USADO_F"
    log "cadeia: degrau $modelo assumiu e devolveu trabalho"
    printf '%s' "$saida_go"
    return 0
  done
  # ---- ÚLTIMO RECURSO ----
  log "cadeia: todos os motores Go indisponiveis — entrego a ordem ao HERMES na VPS"
  saida_go=$(hermes_ultimo_recurso "$tarefa$retoma")
  if [ -n "$saida_go" ]; then
    printf '%s' "hermes" > "$GO_MOTOR_USADO_F"
    log "cadeia: o HERMES (VPS) assumiu a ordem"
    printf '%s' "$saida_go"
    return 0
  fi
  log "failover: cadeia inteira em baixo (Go + Hermes) — nao ha motor vivo"
  return 1
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
  docker exec -u hermes "$C" sh -lc 'export PATH=/opt/data/.local/bin:$PATH; timeout 3600 pc-loop-novo "$(cat /opt/data/orq_task.txt)"' 2>&1 | clean; }
# ---------------- BLINDAGEM CONTRA ENTREGA FANTASMA (2026-08-11) ----------------
# REGRA (ordem do Danilo): uma ordem só pode fechar como CONCLUÍDA se existir prova MATERIAL do
# trabalho — ficheiro criado/alterado em disco ou commit. Marcos extraídos de TEXTO não chegam.
# Sem prova material a ordem fecha como INCOMPLETA e diz o que falta.
#
# Porque não basta o Juiz: no caso que originou isto (ordem-20260811143542-1fa4) o Juiz morreu
# ("[juiz] ERRO: base64 vazio") e o carteiro fechou a ordem como concluída à mesma. Esta sonda é
# de propósito burra e independente — sem LLM, sem rede, só relógio do sistema de ficheiros e git.
PROVA_MATERIAL_TXT=""            # última saída da sonda (para a nota da ordem)
prova_material(){ # $1=epoch de arranque da tentativa -> 0 = há prova, 1 = não há
  local inicio="$1" out rc
  PROVA_MATERIAL_TXT=""
  # COSTURA DE TESTE (default-OFF, mesma família de CARTEIRO_EXEC_STUB/JUDGE_STUB/GO_STUB).
  if [ -n "${CARTEIRO_PROVA_STUB:-}" ] && [ -x "${CARTEIRO_PROVA_STUB:-}" ]; then
    out=$("$CARTEIRO_PROVA_STUB" "$inicio" 2>&1); rc=$?
    PROVA_MATERIAL_TXT="$out"; return $rc
  fi
  [ -n "$inicio" ] || { PROVA_MATERIAL_TXT="PROVA-MATERIAL: sem epoch de arranque"; return 1; }
  out=$(docker exec -u hermes "$C" sh -lc "export PATH=/opt/data/.local/bin:\$PATH; timeout 300 pc-prova-novo $inicio" 2>&1); rc=$?
  PROVA_MATERIAL_TXT=$(printf '%s' "$out" | grep -E '^PROVA-(MATERIAL|FICHEIRO|COMMIT):' | head -20)
  # Falha da PONTE (ssh/docker em baixo) não é o mesmo que ausência de prova: se a sonda nem
  # chegou a responder, não invento um veredito — deixo passar e registo, para não travar o loop
  # inteiro por causa de uma ponte constipada. Ausência de prova só conta quando a sonda RESPONDEU.
  if [ -z "$PROVA_MATERIAL_TXT" ]; then
    PROVA_MATERIAL_TXT="PROVA-MATERIAL: sonda nao respondeu (ponte) — nao conta como ausencia de prova"
    log "prova material: sonda nao respondeu (rc=$rc) — nao bloqueio o fecho por isto"
    return 0
  fi
  return $rc
}

pc_judge(){
  # COSTURA DE TESTE (default-off) — ver bloco no topo.
  if [ -n "${CARTEIRO_JUDGE_STUB:-}" ] && [ -x "${CARTEIRO_JUDGE_STUB:-}" ]; then
    printf '%s' "$1" | "$CARTEIRO_JUDGE_STUB"; return
  fi
  printf '%s' "$1" > "$HOSTDATA/orq_judge.txt"
  docker exec -u hermes "$C" sh -lc 'export PATH=/opt/data/.local/bin:$PATH; timeout 1200 pc-judge-novo "$(cat /opt/data/orq_judge.txt)"' 2>&1 | clean; }

# ---- ACORDAR O CLAUDE.AI DESKTOP na fila vazia (2026-07-17, PEÇA 2) ----
# Mesma ponte SSH do pc_exec/pc-loop (container -> tailscale nc -> hermes@PC), mas para o
# schtask Bora-heartbeat-desktop (agora "Somente sob demanda", sem horário — só corre quando
# chamado). fila-vazia-wake.cmd semeia o pending.trigger do heartbeat-desktop com a frase
# curta e chama schtasks /run; se falhar (UAC, sessão do Danilo fechada, etc.) só regista o
# erro — NUNCA força, o Telegram (acima) já notificou de qualquer forma.
pc_wake_heartbeat(){
  # COSTURA DE TESTE (default-off) — apanhado ao vivo a 2026-08-11: a primeira corrida da prova
  # do auto-fatiamento esvaziou a fila DE TESTE, o ramo fila-vazia disparou, e este wake foi
  # acordar o desktop REAL do Danilo a meio da missão. O notify() já estava desviado; este
  # caminho não estava. Uma prova não pode ter efeitos no mundo verdadeiro.
  if [ -n "${CARTEIRO_NOTIFY_STUB:-}" ]; then printf '[WAKE-DESKTOP suprimido em modo de prova]\n' >> "$CARTEIRO_NOTIFY_STUB"; return 0; fi
  docker exec -u hermes "$C" sh -lc 'ssh -o ProxyCommand="tailscale nc %h %p" -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 danil@100.75.79.116 "C:\\Users\\danil\\Desktop\\projetosflutter\\bora_app\\.claude\\.ai\\hermes\\heartbeat-desktop\\fila-vazia-wake.cmd"' 2>&1; }

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
  # COSTURA DE TESTE (default-off): executor de mentira, para as provas poderem escolher quando
  # o executor morre por teto de turnos. Sem CARTEIRO_EXEC_STUB no ambiente isto nem é lido.
  if [ -n "${CARTEIRO_EXEC_STUB:-}" ] && [ -x "${CARTEIRO_EXEC_STUB:-}" ]; then
    printf '%s' "$1" | "$CARTEIRO_EXEC_STUB"; return
  fi
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
# PRE-VOO DE RAM (2026-08-01, missao sistema-redondo parte 4): o executor recusou-se a arrancar
# por falta de memoria no PC. Mesmo tratamento do lock ocupado — a ordem volta a fila intacta,
# sem gastar tentativa e sem chamar o juiz — mas com nota propria, para o log nao mentir sobre
# a causa (uma coisa e' "outro executor a correr", outra e' "o PC nao tem RAM").
is_ram_baixa(){ printf '%s' "$1" | grep -iqE "ERRO: RAM insuficiente no PC"; }

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
# 2026-08-11 (PROVA DO ECRÃ DO DANILO, bora-live.log 101058-101073): a guarda dos 600 bytes
# acima tornava o detector CEGO ao caso normal — bater no limite DEPOIS de já ter trabalhado.
# Medido: 16:04:25 "You've hit your session limit · resets 4:10pm" com turns=17 → a saída era
# longa → is_rate_limit=falso → sem pausa, sem failover, relançou em opus às 16:07:32. O
# esgotamento de plano quase nunca acontece ao turno 0; a guarda só apanhava esse caso raro.
# Correção: o bora-live-parser.ps1 (PC) passou a converter a assinatura real num sinal CURTO e
# canónico — e este ramo (a) aceita-o a qualquer tamanho. A guarda antiga fica no ramo (c),
# intacta, para quem chegar aqui sem passar pelo parser.
is_rate_limit(){
  # (a) SINAL CANÓNICO do parser do PC — o parser já distinguiu bloqueio genuíno de citação
  #     (decide por BLOCO de texto, não pela saída inteira). Vale a QUALQUER tamanho.
  printf '%s' "$1" | grep -qE '^##BORA-LIMITE-PLANO##' && return 0
  # (b) rede / ferramenta / modelo NÃO é esgotamento de plano — nunca aciona o failover.
  printf '%s' "$1" | grep -iqE "ECONNRESET|ETIMEDOUT|ENOTFOUND|socket hang up|fetch failed|connection (refused|reset)|overloaded|529|502 bad gateway|503 service|504 gateway|tool_use_error" && return 1
  # (c) legado: assinatura crua numa saída curta (bloqueio que corta ali, sem relatório).
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
    # BUG DIÁRIO CORRIGIDO 2026-08-11 (apanhado pelo --selftest desta missão, falhava desde
    # sempre a partir das 09:05): quando a hora do reset JÁ PASSOU hoje, "today HH:MM" dá um
    # epoch no passado, a condição `-gt now` reprovava e caíamos no now+3600 defensivo. Efeito
    # real: um "resets 9:05am" lido às 12:30 pausava 1h em vez de até ao reset verdadeiro — a
    # fila retomava cedo, batia OUTRA VEZ no limite e voltava a pausar, em ciclo. Hora que já
    # passou significa a PRÓXIMA ocorrência, portanto rola para amanhã. O now+3600 fica só para
    # o que é genuinamente impossível de parsear (sem hora no texto).
    [ -n "$ep" ] && [ "$ep" -le "$now" ] && ep=$(TZ='Europe/London' date -d "tomorrow ${h24}:${mm}" +%s 2>/dev/null)
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

# 2026-08-11 (ordem "repor os avisos automaticos no Telegram"): o Danilo voltou a pedir o aviso
# de TRAVADA. I4 (2026-08-01) tinha-o silenciado por RUIDO (aviso a cada ~40 min na mesma ordem),
# nao por o canal estar mau -- o canal sempre esteve vivo (provado: hermes send devolve
# success/message_id). Reposto aqui COM o travao que faltava em 2026-07-13: latch por ordem,
# no maximo 1 aviso por ordem a cada 12h. O arquivo TSV do daily-pulse continua a ser escrito
# na mesma (rede de seguranca inalterada).
aviso_travada(){ # $1=oid  $2=texto
  local latch="$LATCH_TRAVADA/$1" agora mt=0
  mkdir -p "$LATCH_TRAVADA" 2>/dev/null
  agora=$(date -u +%s)
  [ -f "$latch" ] && mt=$(stat -c %Y "$latch" 2>/dev/null || echo 0)
  if [ $((agora - mt)) -ge 43200 ]; then
    notify "$2"
    : > "$latch" 2>/dev/null || true
    log "ordem $1: travada -> Telegram (latch 12h renovado)"
  else
    log "ordem $1: travada -> aviso suprimido (ja avisado ha <12h)"
  fi
}

# --------- FASE 2 SISTEMA-100 (2026-08-11): A TRAVADA ABRE O SEU PRÓPRIO DIAGNÓSTICO ---------
# Até aqui, uma ordem que travava de vez gerava um rascunho de lição (passivo: fica à espera que o
# Bibliotecário o promova) e um aviso. Ninguém ia PERCEBER a falha sem o Danilo mandar. Agora a
# travagem nasce já com a sua ordem de diagnóstico na fila — o sistema investiga-se a si próprio.
#
# Três travões, porque um gerador automático de ordens é precisamente onde se faz um ciclo infinito
# sem dar por isso:
#   1. NUNCA diagnostica um diagnóstico (ids `-diag`): senão um diagnóstico que trave gera outro,
#      que trava, que gera outro, para sempre.
#   2. Idempotente: se o ficheiro do diagnóstico já existe, não cria segundo.
#   3. O texto é de INVESTIGAÇÃO (ler, medir, explicar), nunca de correção. Diagnosticar uma falha
#      em zona de dinheiro é seguro; consertá-la sozinho não seria — e continua a precisar do "vai".
ordem_diagnostico(){ # $1=ficheiro da ordem travada
  local of="$1" oid did dfile nota_o resumo_o ult
  oid=$(get id "$of")
  case "$oid" in *-diag|*-diag-*) log "diagnostico: $oid ja e um diagnostico — nao gero outro (anti-recursao)"; return 0;; esac
  did="${oid}-diag"; dfile="$FILA/$did.md"
  [ -f "$dfile" ] && { log "diagnostico: $did ja existe — nao duplico"; return 0; }
  nota_o=$(get nota "$of")
  resumo_o=$(resumo_tarefa "$(get tarefa "$of")")
  ult=$(grep -vE '^[[:space:]]*$' "$FILA/$oid.saida.txt" 2>/dev/null | tail -1 | cut -c1-200 | tr -d '\r|')
  {
    printf 'id: %s\n' "$did"
    # `tarefa:` TEM de caber numa linha — o get() lê linha-a-linha e texto multi-linha aqui
    # corromperia a leitura de todos os outros campos do ficheiro.
    printf 'tarefa: [MODELO: SONNET] INVESTIGACAO (so ler e medir, NAO corrigir): a ordem %s travou de vez. Nota registada: "%s". Ultima linha da saida: "%s". Tarefa original: "%s". Le na VPS (ssh root@srv1786862.hstgr.cloud) os ficheiros %s/%s.saida.txt e %s/%s.veredito.txt e o /root/orquestracao/carteiro.log, descobre a CAUSA MEDIDA (nao adivinhada) e devolve: causa provada + correcao minima recomendada + se e seguro aplica-la sozinho. NAO apliques nada.\n' \
      "$oid" "${nota_o:-sem nota}" "${ult:-<saida vazia>}" "$resumo_o" "$FILA" "$oid" "$FILA" "$oid"
    printf 'estado: aberta\ntentativa: 0\nteto_tentativas: 2\n'
    printf 'criada: %s\n' "$(date -u +%FT%TZ)"
    printf 'origem: diagnostico-automatico de %s\n' "$oid"
  } > "$dfile" 2>/dev/null || { log "diagnostico: falhei a escrever $did (ignorado)"; return 0; }
  setf diagnostico_gerado "$did" "$of"
  log "ordem $oid: TRAVADA -> ordem de diagnostico $did criada automaticamente (sem humano)"
  acordar_claude TRAVOU "$oid" travada "travou: ${nota_o:-sem nota} · diagnostico $did aberto sozinho"   # FASE 3
  return 0
}

missao_travada_ou_silencio(){ # $1=of $2=mid $3=passo
  local of="$1" mid="$2" p="$3" mf oid nota
  # C4: este é o funil ÚNICO por onde passam os 4 caminhos de TRAVADA (teto de 5,
  # EXECUTOR-PAROU, saída vazia, e 5 tentativas pós-juiz). Enganchar aqui cobre todos
  # sem tocar em nenhum deles.
  licao_de_falha "$of"
  ordem_diagnostico "$of"
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
    log "missão $mid: passo $p travado -> ARQUIVO (daily-pulse)."
    # FASE 4 (2026-08-11): 3 linhas — o quê · veredito · o que falta. E o "falta" já não é
    # uma tarefa para o Danilo: é a ordem de diagnóstico que o sistema abriu sozinho.
    aviso_travada "$oid" "⛔ Bora: ordem \`$oid\` travou (passo $p da missão $mid).
· O quê: ${nota:-motivo desconhecido}
· Conselho: não chegou a haver — a ordem nem passou o Juiz.
· Falta: nada da tua parte — abri sozinho o diagnóstico \`$oid-diag\`; conto-te o que descobrir."
  else
    mkdir -p "$(dirname "$ARQUIVO_TRAVADAS")" 2>/dev/null
    printf '%s\t%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$oid" "sem-missao" "${nota:-motivo desconhecido}" >> "$ARQUIVO_TRAVADAS" \
      || log "ordem $oid: AVISO — não consegui escrever em $ARQUIVO_TRAVADAS"
    log "ordem $oid: travada (sem missão) -> ARQUIVO (daily-pulse)."
    aviso_travada "$oid" "⛔ Bora: ordem \`$oid\` travou de vez.
· O quê: ${nota:-motivo desconhecido}
· Conselho: não chegou a haver — a ordem nem passou o Juiz.
· Falta: nada da tua parte — abri sozinho o diagnóstico \`$oid-diag\`; conto-te o que descobrir."
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
  # REGRESSAO 2026-08-11 (o bug que o Danilo viu no ecra as 16:04): o limite REAL bate DEPOIS
  # de ja se ter trabalhado (turns=17) -> a saida e longa -> a guarda dos 600 bytes cegava o
  # detector. O parser do PC passou a emitir este sinal canonico curto; aqui prova-se que o
  # carteiro o aceita a QUALQUER tamanho, colando o TEXTO LITERAL do log real.
  sinal_real="##BORA-LIMITE-PLANO##
You've hit your session limit · resets 4:10pm (Europe/London)
LIMITE-DE-PLANO-REAL: sim turns=17 custo=0.9385517999999999"
  is_rate_limit "$sinal_real" && ok "sinal canonico do parser detecta (texto LITERAL do log real 16:04:25)" || bad "sinal canonico do parser NAO detectou (bug 16:04 por corrigir)"
  is_rate_limit "$sinal_real
$(printf 'z%.0s' $(seq 1 2000))" && ok "sinal canonico detecta mesmo com saida LONGA (fim da cegueira dos 600 bytes)" || bad "sinal canonico morreu na guarda dos 600 bytes"
  ep_real=$(rl_resume_epoch "$sinal_real"); agora_real=$(date +%s)
  { [ "$ep_real" -gt "$agora_real" ] && [ "$(date -u -d "@$ep_real" +%M)" = "10" ]; } \
    && ok "hora do reset lida da propria mensagem real (4:10pm -> minutos 10)" || bad "reset 4:10pm do log real"
  # Erro de rede/ferramenta/modelo NUNCA e esgotamento de plano -> nunca aciona o failover.
  for e in "API Error: fetch failed (ECONNRESET) ao contactar o modelo" \
           "Error: overloaded_error 529 upstream" \
           "tool_use_error: Bash timed out after 120s"; do
    is_rate_limit "$e" && bad "erro nao-plano disparou rate-limit: $e" || ok "erro nao-plano nao dispara: ${e%% *}"
  done
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
  # FASE 2 SISTEMA-100 (2026-08-11): conselho_divergiu — puro texto, sem rede. Regressao alvo:
  # grep de palavra solta ("falta"/"errado") apanharia "nao falta nada" como falso positivo —
  # por isso o parser exige o marcador exato CONSELHO: AJUSTAR/OK, nunca palavra livre.
  [ "$(conselho_divergiu "CONSELHO: OK")" = nao ] && ok "conselho_divergiu: 1 OK -> nao diverge" || bad "conselho_divergiu 1 OK"
  [ "$(conselho_divergiu "$(printf 'CONSELHO: AJUSTAR\nCONSELHO: AJUSTAR\nCONSELHO: OK')")" = sim ] && ok "conselho_divergiu: 2 AJUSTAR vs 1 OK -> diverge" || bad "conselho_divergiu 2v1"
  [ "$(conselho_divergiu "$(printf 'CONSELHO: AJUSTAR\nCONSELHO: OK\nCONSELHO: OK')")" = nao ] && ok "conselho_divergiu: 1 AJUSTAR vs 2 OK -> nao diverge (nao e maioria)" || bad "conselho_divergiu 1v2"
  [ "$(conselho_divergiu "sem marcador nenhum, so texto livre com a palavra errado e falta")" = nao ] && ok "conselho_divergiu: sem marcador exato -> nao diverge (fail-safe, nao apanha palavra solta)" || bad "conselho_divergiu sem marcadores"
  [ "$(conselho_divergiu "")" = nao ] && ok "conselho_divergiu: texto vazio -> nao diverge" || bad "conselho_divergiu vazio"

  # ---- FASE 1 MISSÃO DE FECHO (2026-08-11): CADEIA DE MOTORES -------------------------------
  # Provas contra o TEXTO LITERAL do ecrã do Danilo (bora-live.log 21:24:38 e 22:01:13).
  _t429='API Error: Request rejected (429) · 5-hour usage limit reached. Resets in 2hr 16min. To continue using this model now, edit your Claude Code settings and select a different model.'
  _t429b='##BORA-LIMITE-PLANO##
API Error: Request rejected (429) · 5-hour usage limit reached. Resets in 1hr 39min.
##BORA-MOTOR##: qwen3.7-max
##BORA-RESET-MIN##: 99
LIMITE-DE-PLANO-REAL: sim turns=1 custo=0'
  is_rate_limit "$_t429" && ok "429 do plano Go LITERAL reconhecido como limite" || bad "429 literal nao reconhecido"
  _now=$(date +%s); _ep=$(go_reset_epoch "$_t429")
  [ "$((_ep-_now))" -ge 8100 ] && [ "$((_ep-_now))" -le 8220 ] \
    && ok "hora lida da propria mensagem: 'Resets in 2hr 16min' -> 136 min" || bad "reset 2hr16min ($(( (_ep-_now)/60 )) min)"
  _ep=$(go_reset_epoch "$_t429b")
  [ "$((_ep-_now))" -ge 5880 ] && [ "$((_ep-_now))" -le 6000 ] \
    && ok "##BORA-RESET-MIN##: 99 -> 99 min" || bad "reset via marcador do parser"
  [ "$(motor_do_sinal "$_t429b")" = "qwen3.7-max" ] \
    && ok "atribuicao: o sinal diz QUAL motor se esgotou (qwen3.7-max)" || bad "motor_do_sinal"
  eh_motor_go "qwen3.7-max" && ok "qwen3.7-max reconhecido como degrau da cadeia" || bad "eh_motor_go"
  eh_motor_go "claude-opus" && bad "claude-opus nao pode contar como degrau Go" || ok "claude-opus NAO e degrau Go (plano Claude fica intacto)"
  # Livro de esgotamentos por modelo, em disco descartavel.
  _tdm=$(mktemp -d); MOTORES_ESGOTADOS="$_tdm/.motores-esgotados"
  [ "$(motor_esgotado_ate qwen3.7-max)" = 0 ] && ok "motor sem registo -> disponivel" || bad "motor sem registo"
  motor_marcar_esgotado "qwen3.7-max" "$((_now+3600))" "teste" >/dev/null 2>&1
  [ "$(motor_esgotado_ate qwen3.7-max)" -gt "$_now" ] && ok "motor marcado -> fica esgotado ate a hora do reset" || bad "marcar esgotado"
  [ "$(motor_esgotado_ate qwen3.8-max)" = 0 ] && ok "esgotar um degrau NAO esgota os outros" || bad "esgotamento contagiou"
  motor_marcar_esgotado "qwen3.7-max" "$((_now-10))" "ja passou" >/dev/null 2>&1
  [ "$(motor_esgotado_ate qwen3.7-max)" = 0 ] && ok "hora do reset passou -> motor volta sozinho" || bad "motor nao volta apos reset"
  [ "$(cadeia_proximo_reset)" = 0 ] && ok "ha degrau vivo -> nao ha espera" || bad "cadeia_proximo_reset com degrau vivo"
  for _m in $GO_CADEIA; do motor_marcar_esgotado "$_m" "$((_now+7200))" "teste" >/dev/null 2>&1; done
  motor_marcar_esgotado "minimax-m3" "$((_now+900))" "teste" >/dev/null 2>&1
  [ "$(cadeia_proximo_reset)" = "$((_now+900))" ] \
    && ok "cadeia toda esgotada -> espera pelo PRIMEIRO a repor (minimax-m3, +15min)" || bad "cadeia_proximo_reset primeiro"
  rm -rf "$_tdm"

  [ "$fail" = 0 ] && echo "SELFTEST: TODOS OK" || echo "SELFTEST: HÁ FALHAS"
  exit "$fail"
fi
# ---- PROVA RE-EXECUTÁVEL DA CADEIA (FASE 1 MISSÃO DE FECHO, 2026-08-11) ---------------------
# `carteiro.sh --prova-cadeia [tarefa]` corre o go_failover VERDADEIRO (o mesmo que a fila usa)
# contra os motores REAIS, num livro de esgotamentos descartável, e mostra o rasto: que degraus
# saltou, qual bateu no limite, e qual assumiu. Não toca na fila de produção.
if [ "${1:-}" = "--prova-cadeia" ]; then
  _pd=$(mktemp -d)
  MOTORES_ESGOTADOS="$_pd/.motores-esgotados"
  GO_MOTOR_USADO_F="$_pd/.go-motor-usado"
  LOG="$_pd/prova.log"
  ORQ_TASK_BASENAME="orq_task_prova.txt"   # nunca pisa a tarefa de uma ordem em curso
  GO_TIMEOUT="${GO_TIMEOUT:-600}"          # a prova é curta; não fica 4h presa
  _tarefa="${2:-Corre este comando exato e mostra a saida: echo VIVO-\$env:MOTOR_GO_MODEL > C:\\Users\\danil\\Desktop\\ferramentas\\provas-cadeia-motores\\PROVA-DEGRAU.txt ; type C:\\Users\\danil\\Desktop\\ferramentas\\provas-cadeia-motores\\PROVA-DEGRAU.txt . Depois responde numa linha: MARCO: escrevi PROVA-DEGRAU.txt}"
  echo "=== PROVA DA CADEIA — degraus: $GO_CADEIA -> hermes ==="
  echo "=== livro de esgotamentos descartavel: $MOTORES_ESGOTADOS ==="
  _saida=$(go_failover "$_tarefa" /dev/null)
  echo
  echo "--- RASTO (o que o carteiro registou) ---"
  cat "$LOG" 2>/dev/null
  echo
  echo "--- LIVRO DE ESGOTAMENTOS no fim ---"
  if [ -s "$MOTORES_ESGOTADOS" ]; then
    while IFS="$(printf '\t')" read -r _m _e; do echo "  $_m esgotado ate $(hhmm "$_e") UTC"; done < "$MOTORES_ESGOTADOS"
  else echo "  (vazio — nenhum degrau precisou de ser marcado)"; fi
  echo
  echo "--- MOTOR QUE ASSUMIU: $(cat "$GO_MOTOR_USADO_F" 2>/dev/null || echo NENHUM) ---"
  echo "--- SAIDA (200 primeiros chars) ---"
  printf '%s' "$_saida" | head -c 200; echo
  rm -rf "$_pd"
  exit 0
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
  rm -f "$PAUSA_RL" "$RL_AVISADO" "$CADEIA_AVISADO"; log "PAUSA-RATE-LIMIT: reset atingido — retomo o ciclo"
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
    acordar_claude ESPERA-AUTORIZACAO "$id" zona_vermelha "$(resumo_tarefa "$tarefa")"   # FASE 3
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
  # (2026-08-11) FONTE DA VERDADE = campo `teto_tentativas:` do ficheiro da ordem. Antes estava
  # 5 CRAVADO aqui e o campo era decorativo -- mudar o campo nao mudava nada. Default 3: com a
  # RETOMA por marcos (abaixo), 3 tentativas que CONTINUAM valem mais que 5 que recomecam.
  teto=$(get teto_tentativas "$f"); case "$teto" in ''|*[!0-9]*) teto=3;; esac
  [ "$teto" -lt 1 ] && teto=3
  if [ "$tent" -ge "$teto" ]; then setf estado travada "$f"
    [ -z "$(get nota "$f")" ] && setf nota "⛔ TRAVADA nas $teto tentativas" "$f"
    log "ordem $id: TRAVADA ($teto tentativas)"; ultima_veredito="TRAVADA"; missao_travada_ou_silencio "$f" "$missao" "$passo"; continue; fi

  tent=$((tent+1)); setf tentativa "$tent" "$f"; setf estado executando "$f"
  # inicio da ORDEM = campo criada: (nao o relogio da tentativa) — commit feito numa tentativa
  # anterior CONTA como trabalho novo (fix 2026-07-15: a 1a corrida real travou a ordem reborn
  # porque o t0 por-tentativa excluia o commit da tentativa 1). Fallback: agora.
  criada_ts=$(grep -m1 '^criada:' "$f" | sed 's/criada: *//' | tr -d '\r')
  t0=""; [ -n "$criada_ts" ] && t0=$(date -d "$criada_ts" +%s 2>/dev/null)
  t0=${t0:-$(date +%s)}
  # FASE 2 SISTEMA-100: se uma ronda anterior do conselho deixou critica pendente, anexa-a
  # SO nesta chamada (em memoria — tarefa_exec, nunca escrita no campo tarefa: do ficheiro).
  tarefa_exec="$tarefa"
  if [ "$(get conselho_pendente "$f")" = "sim" ]; then
    ronda_c=$(get conselho_ronda "$f"); ronda_c=${ronda_c:-1}
    critica_arq="$FILA/$id.conselho-r$ronda_c.txt"
    if [ -f "$critica_arq" ]; then
      tarefa_exec="$tarefa

[Revisao do conselho, ronda $ronda_c/$CONSELHO_RONDAS_MAX -- ajusta o que fizer sentido, ignora o resto se ja estiver certo:]
$(cat "$critica_arq")"
      log "ordem $id: a incluir critica do conselho (ronda $ronda_c) nesta tentativa"
    fi
    setf conselho_pendente nao "$f"
  fi
  # ---- RETOMA POR MARCOS (2026-08-11) ----
  # Antes cada tentativa mandava a tarefa CRUA -> a tentativa 2 recomecava tudo do zero e batia
  # no mesmo sitio. Agora a ordem tem MEMORIA: o executor devolve `MARCO: <o que ficou feito>` no
  # RESULTADO (tem de ser no RESULTADO: o bora-live-parser.ps1 so deixa passar o resultado final),
  # guardamos em $id.marcos.txt e a tentativa seguinte recebe a lista com ordem de CONTINUAR.
  MARCOF="$FILA/$id.marcos.txt"
  tarefa_exec="$tarefa_exec

--- CONTABILIDADE DE PROGRESSO (obrigatorio) ---
No RESULTADO final inclui UMA LINHA por cada fase/passo que ficou MESMO concluido, no formato:
MARCO: <descricao curta do que ficou feito>
Escreve-as mesmo que nao tenhas acabado tudo - servem para a proxima tentativa continuar daqui."
  # (2026-08-11, FASE 1 SISTEMA-100) A condição era `tent -gt 1 && -s MARCOF`. Com o
  # auto-fatiamento isso passou a estar ERRADO: bater no teto de turnos já NÃO gasta tentativa,
  # logo um 2.º arranque da mesma ordem pode acontecer com `tent` ainda em 1 — e a RETOMA nunca
  # seria injetada, fazendo o arranque seguinte recomeçar tudo (exatamente a avaria que a Fase 1
  # veio matar). Agora a regra é a única que importa: SE HÁ MARCOS, RETOMA-SE.
  _cont_feitas=$(get continuacoes "$f"); case "$_cont_feitas" in ''|*[!0-9]*) _cont_feitas=0;; esac
  if [ -s "$MARCOF" ]; then
    tarefa_exec="$tarefa_exec

--- RETOMA: tentativa $tent de $teto · arranque $((_cont_feitas+1)) (NAO RECOMECES DO ZERO) ---
Esta ordem JA FOI TENTADA. Isto JA ESTA FEITO (confirma que existe, nao repitas):
$(cat "$MARCOF")
Continua a partir do primeiro passo que NAO esta nessa lista."
    log "ordem $id: RETOMA com $(wc -l < "$MARCOF" | tr -d ' ') marco(s) (tentativa $tent, arranque $((_cont_feitas+1)))"
  fi
  # ---- MOTOR / MODELO (2026-08-11) ----
  # O executor (run-claude-loop.cmd, FASE 1.3) so sobe para Opus se encontrar a string LITERAL
  # "[MODELO: OPUS]" (findstr /C:). O Danilo escreve "MOTOR: OPUS" -> nunca batia. Medido no
  # bora-live.log: 667 de 669 arranques em sonnet, 2 em opus. Normaliza-se aqui.
  _motor_low=$(printf '%s' "$tarefa_exec" | tr 'A-Z' 'a-z')
  case "$_motor_low" in
    *"[modelo: opus]"*) : ;;
    *"motor: opus"*|*"motor:opus"*|*"modelo: opus"*|*"modelo:opus"*)
      tarefa_exec="[MODELO: OPUS]
$tarefa_exec"
      log "ordem $id: motor OPUS pedido no cabecalho -> etiqueta [MODELO: OPUS] injetada" ;;
  esac
  t_att=$(date +%s)   # relogio DESTA tentativa (o t0 e' da ordem toda) — usado na nota medida
  # ---- MEMÓRIA DO PLANO ESGOTADO (2026-08-11) ----------------------------------------------
  # Medido no carteiro.log de hoje (36424 e 36437): o failover FUNCIONOU nas duas vezes, mas o
  # carteiro não guardava que o plano estava esgotado. Resultado: a ordem SEGUINTE era à mesma
  # despachada para o Claude, subia um claude.exe inteiro no PC de 4GB, batia no limite ao turno
  # 1 (~14s, custo $0) e só então caía no failover. Era isto que o Danilo via no ecrã como
  # "relançou no mesmo motor e queimou tempo" — não era retentativa da mesma ordem, era cada
  # ordem nova a redescobrir sozinha que o plano tinha acabado.
  # Agora, enquanto a janela do limite não passar: verde vai DIRETO ao Go (zero arranques
  # desperdiçados) e vermelha fica segura à espera do Pro. Ficheiro apaga-se sozinho no reset.
  _saltou_claude=0
  if [ -f "$PLANO_ESGOTADO" ]; then
    _pe=$(tr -dc '0-9' < "$PLANO_ESGOTADO" 2>/dev/null); _pe=${_pe:-0}
    if [ "$_pe" -le "$(date +%s)" ]; then
      rm -f "$PLANO_ESGOTADO"; log "plano Claude voltou (janela do limite passou) — arranques normais retomados"
    elif zona_vermelha "$tarefa"; then
      setf tentativa "$((tent-1))" "$f"; setf estado pausada-rate-limit "$f"
      echo "$_pe" > "$PAUSA_RL"
      setf nota "🔴 SEGURA — zona protegida e plano Claude no limite (retoma $(hhmm "$_pe") UTC); não deixo o motor mais fraco assumir." "$f"
      log "limite do plano detectado -> ordem segura (zona protegida) ate $(hhmm "$_pe") UTC"
      log "ordem $id: plano no limite + ZONA VERMELHA — nem sequer arranco o executor; espero o Pro"
      # FIX 2026-08-11 (apanhado pela prova com a frase literal): este ramo segurava a ordem
      # em SILENCIO. O ramo do RATE-LIMIT avisava; este — que trata de TODAS as ordens
      # protegidas seguintes enquanto a janela dura — nao. Marcador por-ordem para avisar
      # uma vez por ordem (nao a cada volta do carteiro), com a hora lida da propria mensagem.
      if [ ! -f "$FILA/$id.rl-vermelha.avisado" ]; then
        touch "$FILA/$id.rl-vermelha.avisado"
        notify "🔴 Bora: a ordem \`$id\` toca zona protegida (dinheiro/dispatch) e o plano Claude Pro está no limite.
· Veredito: SEGURA — não deixo o motor mais fraco assumir nestas; nem sequer arranco o executor.
· Falta: esperar o reset ($(hhmm "$_pe") UTC); retomo sozinho, sem gastar tentativa."
      fi
      ultima_veredito="RATE-LIMIT"; break
    else
      log "limite do plano detectado -> a continuar pela cadeia Go ($GO_CADEIA -> hermes)"
      log "ordem $id: plano ainda no limite ate $(hhmm "$_pe") UTC — vou DIRETO a cadeia, sem gastar um arranque do Claude"
      saida=$(go_failover "$tarefa_exec" "$MARCOF" 2>/dev/null)
      _mgo_direto=$(cat "$GO_MOTOR_USADO_F" 2>/dev/null)
      if [ -n "$saida" ]; then _saltou_claude=1; setf motor_final "${_mgo_direto:-$GO_FAILOVER_MODELO}" "$f"; fi
    fi
  fi
  [ "$_saltou_claude" -eq 1 ] || saida=$(exec_ordem "$tarefa_exec")
  printf '%s\n' "$saida" > "$FILA/$id.saida.txt"
  printf '%s\n' "$saida" | grep -E '^[[:space:]]*MARCO:' | sed 's/^[[:space:]]*//' >> "$MARCOF" 2>/dev/null || true
  if [ -s "$MARCOF" ]; then sort -u "$MARCOF" -o "$MARCOF"; setf marcos "$(wc -l < "$MARCOF" | tr -d ' ')" "$f"; fi
  setf estado respondida "$f"
  # (2026-08-11, FASE 1) Regista QUAL plano/motor terminou este arranque. Com o failover de plano
  # uma mesma ordem pode acabar parte em Claude e parte no Go — sem esta linha o log deixava de
  # dizer quem fez o quê, e a promessa "distingue no log qual modelo terminou cada arranque"
  # ficava por cumprir. O ramo do failover reescreve este campo quando assume.
  if [ "$_saltou_claude" -eq 1 ]; then _motor_usado="${_mgo_direto:-$GO_FAILOVER_MODELO}"   # nem chegou a subir claude.exe
  else case "$tarefa_exec" in *"[MODELO: OPUS]"*) _motor_usado="claude-opus";; *) _motor_usado="claude-sonnet";; esac
  fi
  setf motor_final "$_motor_usado" "$f"
  log "ordem $id: respondida (tentativa $tent, motor $_motor_usado)"
  # PARTE A (2026-07-16): se o vigia de inatividade do PC matou o executor, o run-claude-loop.cmd
  # devolve esta linha no stdout — conta como saida vazia (nao houve resultado real), mas o
  # MOTIVO fica preservado para a nota nunca dizer "timeout" generico.
  motivo_kill=$(printf '%s' "$saida" | grep -oE '^MOTIVO_KILL:(INATIVIDADE|TETO-DURO):[0-9]+' | head -1)
  vazio=0; [ -z "$(printf '%s' "$saida" | grep -vE '^MOTIVO_KILL:' | tr -d '[:space:]')" ] && vazio=1
  [ -n "$motivo_kill" ] && vazio=1

  # ---- LOCK-OCUPADO: executor nem chegou a arrancar (outro claude.exe vivo no PC) — não
  # gasta tentativa nem chama o juiz (não há nada real para avaliar); reabre para a próxima
  # volta tentar de novo, sem queimar o teto T1 nem confundir com falha do juiz.
  if is_ram_baixa "$saida"; then
    # FIX 2026-09-05 (tudo-05-09-mao): esta linha nunca apanhava o numero, por isso as notas
    # das ordens ficavam todas com "(? livres)" -- 6 ordens travadas assim, sem se saber
    # quanta RAM havia. Esperava "RAM insuficiente no PC (123MB livres)", mas o executor
    # escreve "RAM insuficiente no PC (PREFLIGHT-RAM: BLOCK motivo=... avail=222MB ...)".
    # Passa a aceitar as duas formas.
    livres=$(printf %s "$saida" | grep -oiE "avail=[0-9]+MB|\(([0-9]+)MB livres\)" | grep -oE "[0-9]+MB" | head -1)
    setf tentativa "$((tent-1))" "$f"
    setf estado aberta "$f"
    setf nota "🧠 RAM-BAIXA — o PC não tinha memória (${livres:-?} livres) para subir o executor; reagendada sem gastar tentativa." "$f"
    log "ordem $id: 🧠 RAM-BAIXA (${livres:-?}) — reaberta sem gastar tentativa"
    ultima_veredito="RAM-BAIXA"
    continue
  fi

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
    #
    # AUTO-FATIAMENTO (2026-08-11, FASE 1 SISTEMA-100) — o teto deixa de matar, passa a ser só
    # o tamanho da fatia. Antes este ramo marcava `travada` e DELEGAVA a continuação num hook
    # externo (hermes-hook-conclusao.sh). Duas fragilidades: (a) a ordem ficava `travada` no
    # disco entre o teto e o hook — quem olhasse via uma falha que não existia; (b) dependia de
    # uma segunda peça correr. Agora é tratado AQUI, na mesma classe de RAM-BAIXA/LOCK-OCUPADO:
    # devolve a tentativa (não foi o trabalho que falhou, foi a fatia que acabou), reabre a
    # ordem, e o arranque seguinte apanha os marcos pela RETOMA acima. Uma ordem grande passa a
    # ser vários arranques encadeados até acabar.
    cont=$(get continuacoes "$f"); case "$cont" in ''|*[!0-9]*) cont=0;; esac
    cont=$((cont+1)); setf continuacoes "$cont" "$f"
    nmarcos=0; [ -s "$MARCOF" ] && nmarcos=$(wc -l < "$MARCOF" | tr -d ' ')
    #
    # TRAVÃO DO PROGRESSO (2026-08-11) — acrescentado DEPOIS de o conselho de 4 vozes criticar
    # a primeira versão desta função. As três vozes independentes bateram no mesmo ponto: um
    # arranque que não gasta tentativa não tem custo visível, portanto o único travão passava a
    # ser o contador — e um trabalho que não avança ganhava 12 arranques de borla à mesma.
    # Tinham razão na substância. A resposta certa não é voltar a queimar tentativa (o Danilo
    # pediu explicitamente o contrário, e um arranque produtivo NÃO é uma falha); é distinguir
    # PAUSA de EMPERRAMENTO: um arranque só é gratuito se tiver produzido pelo menos um marco
    # novo. Dois arranques seguidos sem marco novo não é uma tarefa grande, é uma tarefa presa —
    # e essa trava já, em vez de rodar 12 vezes contra a mesma parede.
    marcos_antes=$(get marcos_no_arranque_anterior "$f"); case "$marcos_antes" in ''|*[!0-9]*) marcos_antes=-1;; esac
    setf marcos_no_arranque_anterior "$nmarcos" "$f"
    if [ "$nmarcos" -le "$marcos_antes" ]; then
      sem_progresso=$(get arranques_sem_progresso "$f"); case "$sem_progresso" in ''|*[!0-9]*) sem_progresso=0;; esac
      sem_progresso=$((sem_progresso+1)); setf arranques_sem_progresso "$sem_progresso" "$f"
      if [ "$sem_progresso" -ge 2 ]; then
        setf estado travada "$f"
        setf nota "⛔ EMPERRADA — $sem_progresso arranques seguidos sem UM marco novo (fica em $nmarcos). Não é tarefa grande, é tarefa presa: relançar outra vez daria o mesmo. $linha_parou" "$f"
        log "ordem $id: EMPERRADA — $sem_progresso arranques sem progresso (marcos parados em $nmarcos) -> travada em vez de gastar os $CONT_MAX"
        ultima_veredito="TRAVADA"; missao_travada_ou_silencio "$f" "$missao" "$passo"
        continue
      fi
      log "ordem $id: arranque $cont sem marco novo ($sem_progresso/2) — dou-lhe mais uma, depois trava"
    else
      setf arranques_sem_progresso 0 "$f"    # avançou: o contador de emperramento reinicia
    fi
    if [ "$cont" -ge "$CONT_MAX" ]; then
      setf estado travada "$f"
      setf nota "⛔ TETO ABSOLUTO DE ARRANQUES ($CONT_MAX) — $linha_parou; $nmarcos marco(s) feitos. Grande demais mesmo fatiada: precisa de ser dividida em ordens separadas." "$f"
      log "ordem $id: TETO-ABSOLUTO de arranques ($cont/$CONT_MAX) — travada com $nmarcos marco(s)"
      ultima_veredito="TRAVADA"; missao_travada_ou_silencio "$f" "$missao" "$passo"
      continue
    fi
    setf tentativa "$((tent-1))" "$f"          # teto de turnos NÃO é falha -> não queima tentativa
    setf estado aberta "$f"
    setf pausa_teto 1 "$f"
    setf nota "⏸️ PAUSA-POR-TETO (não é falha, não gasta tentativa): $linha_parou — arranque $cont/$CONT_MAX, $nmarcos marco(s) em memória; continua da fase seguinte." "$f"
    log "ordem $id: PAUSA-POR-TETO -> reaberta SEM gastar tentativa (arranque $cont/$CONT_MAX, $nmarcos marco(s)) — $linha_parou"
    ultima_veredito="PAUSA-TETO"
    continue
  fi

  # ---- RATE-LIMIT: não gasta tentativa, pausa a fila, avisa 1x, retoma sozinho ----
  if is_rate_limit "$saida"; then
    setf tentativa "$((tent-1))" "$f"                 # devolve a tentativa (foi limite, não trabalho)
    # ---- FAILOVER DE PLANO (2026-08-11, FASE 1 SISTEMA-100, pedido explícito do Danilo) ----
    # O plano Pro esgotou, mas a tarefa não pode parar: passa para o motor mais forte do
    # OpenCode Go (custo fixo). EXCEÇÃO DURA: zona vermelha (dinheiro/dispatch/zonas que exigem
    # Opus) NÃO passa — nessas é melhor esperar pelo Pro do que arriscar no modelo mais fraco.
    _fo_ok=0
    _resume_calc=$(rl_resume_epoch "$saida")          # calcula AGORA: a $saida pode ser substituída
    # ---- DE QUEM É ESTE LIMITE? (FASE 1 MISSÃO DE FECHO, 2026-08-11) --------------------
    # Defeito medido às 21:01:15: o 429 do plano **Go** era lido aqui e escrito em
    # .plano-esgotado como se fosse o plano **Claude**. A seguir, o ramo do "plano no limite"
    # mandava a ordem DIRETA ao qwen3.7-max — precisamente o motor que estava morto. O parser
    # do PC passou a dizer quem foi (##BORA-MOTOR##); aqui usa-se essa etiqueta.
    _motor_lim=$(motor_do_sinal "$saida")
    if [ -n "$_motor_lim" ] && eh_motor_go "$_motor_lim"; then
      _ep_go=$(go_reset_epoch "$saida")
      motor_marcar_esgotado "$_motor_lim" "$_ep_go" "429 lido do arranque"
      log "ordem $id: o limite era do motor $_motor_lim (plano Go), NAO do Claude Pro — plano Claude fica intacto"
    else
      # Grava a janela do limite para as ordens SEGUINTES não gastarem cada uma um arranque a
      # redescobrir o mesmo (ver "MEMÓRIA DO PLANO ESGOTADO" acima). Apaga-se sozinho no reset.
      echo "$_resume_calc" > "$PLANO_ESGOTADO"
      log "limite do plano registado ate $(hhmm "$_resume_calc") UTC — as proximas ordens verdes vao direto a cadeia Go"
    fi
    if zona_vermelha "$tarefa"; then
      # Linha LEGÍVEL pedida pelo Danilo (2026-08-11): quem lê o log tem de perceber o que
      # aconteceu sem decifrar siglas — e a hora vem lida da PRÓPRIA mensagem do limite.
      log "limite do plano detectado -> ordem segura (zona protegida) ate $(hhmm "$_resume_calc") UTC"
      log "ordem $id: RATE-LIMIT em ZONA VERMELHA — failover BLOQUEADO de propósito, seguro a ordem até o Pro voltar"
      notify "🔴 Bora: a ordem \`$id\` toca zona protegida (dinheiro/dispatch) e o plano Claude Pro está no limite.
· Veredito: SEGURA — não deixo o motor mais fraco assumir nestas.
· Falta: esperar o reset ($(hhmm "$_resume_calc") UTC); retomo sozinho, sem gastar tentativa."
    else
      log "limite do plano detectado -> a continuar pela cadeia Go ($GO_CADEIA -> hermes)"
      log "ordem $id: RATE-LIMIT — desco a cadeia de motores ate encontrar um vivo"
      _saida_go=$(go_failover "$tarefa_exec" "$MARCOF" 2>/dev/null)
      _mgo=$(cat "$GO_MOTOR_USADO_F" 2>/dev/null); _mgo=${_mgo:-$GO_FAILOVER_MODELO}
      if [ -n "$_saida_go" ]; then
        saida="$_saida_go"
        printf '%s\n' "$saida" > "$FILA/$id.saida.txt"
        printf '%s\n' "$saida" | grep -E '^[[:space:]]*MARCO:' | sed 's/^[[:space:]]*//' >> "$MARCOF" 2>/dev/null || true
        if [ -s "$MARCOF" ]; then sort -u "$MARCOF" -o "$MARCOF"; setf marcos "$(wc -l < "$MARCOF" | tr -d ' ')" "$f"; fi
        setf tentativa "$tent" "$f"                   # houve trabalho real: a tentativa volta a contar
        setf motor_final "$_mgo" "$f"
        log "ordem $id: FAILOVER-PLANO OK — arranque terminado em $_mgo (degrau vivo da cadeia)"
        _fo_ok=1                                      # segue para o Juiz pelo caminho normal
      else
        log "ordem $id: cadeia inteira sem motor vivo — caio na pausa normal até ao primeiro reset"
      fi
    fi
    if [ "$_fo_ok" -eq 0 ]; then
      setf estado pausada-rate-limit "$f"
      # ---- FASE 1, pedido 3: NÃO QUEIMAR CICLOS ------------------------------------------
      # Se TODOS os degraus estão esgotados, a ordem espera pela hora do PRIMEIRO que repõe
      # (Claude ou Go, o que vier antes) e o Danilo é avisado UMA vez — não de 20 em 20 min.
      _ep_cad=$(cadeia_proximo_reset)
      resume="$_resume_calc"
      [ "$_ep_cad" -gt 0 ] && [ "$_ep_cad" -lt "$resume" ] && resume="$_ep_cad"
      echo "$resume" > "$PAUSA_RL"
      setf nota "🚫 RATE-LIMIT (todos os motores no limite; retoma $(hhmm "$resume") UTC)" "$f"
      log "ordem $id: 🚫 RATE-LIMIT — fila pausada até $(hhmm "$resume") UTC"
      if [ "$_ep_cad" -gt 0 ]; then
        if [ ! -f "$CADEIA_AVISADO" ]; then
          notify "🚫 Bora/orquestração: TODOS os motores no limite (Claude Pro + $GO_CADEIA). Fila PAUSADA até $(hhmm "$resume") UTC — o primeiro a repor assume, retomo sozinho e sem gastar tentativas."; touch "$CADEIA_AVISADO"
        else
          log "ordem $id: cadeia toda esgotada — aviso ja dado (latch), nao repito no Telegram"
        fi
      elif [ ! -f "$RL_AVISADO" ]; then
        notify "🚫 Bora/orquestração: conta Claude Code no limite de sessão. Fila PAUSADA até $(hhmm "$resume") UTC — retomo sozinho, sem gastar tentativas."; touch "$RL_AVISADO"
      fi
      ultima_veredito="RATE-LIMIT"
      break                                           # não processa mais nada até ao reset
    fi
  fi

  # juiz — META_JUIZ leva o inicio_epoch p/ o chao mecanico do PC (juiz-mecanico.ps1) verificar
  # commit novo/ficheiro em disco. O veredito completo (com as linhas PROVA-JUIZ) fica auditavel
  # em $id.veredito.txt — prova no proprio veredito, nunca no e2e_log.
  jinput=$(printf 'TAREFA:\n%s\nMETA_JUIZ: inicio_epoch=%s\n\nSAIDA DO EXECUTOR:\n%s\n' "$tarefa" "${t0:-}" "$(printf '%s' "$saida" | tail -300)")
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
  # BLINDAGEM CONTRA ENTREGA FANTASMA (2026-08-11) — corre ANTES de qualquer fecho POSITIVO.
  # Nem o "APROVADA" do Juiz dispensa prova material: o Juiz julga TEXTO, e texto foi exatamente
  # o que a ordem-20260811143542-1fa4 produziu (5 marcos, zero entregas). Ficheiro em disco ou
  # commit — senão a ordem fecha INCOMPLETA a dizer o que falta, nunca concluída.
  #
  # SÓ intercepta os fechos POSITIVOS (APROVADA, ou juiz mudo com saída não-vazia = o antigo
  # "CONCLUÍDA COM REVISÃO PENDENTE", que foi por onde a ordem fantasma passou). Um CORRIGIR ou
  # uma travagem seguem o caminho normal: aí a ordem ainda vai voltar a correr, e exigir-lhe prova
  # agora só matava a re-tentativa legítima — o defeito que a PARIDADE 2.2 já tinha pago caro.
  _fecho_positivo=0
  printf '%s' "$vline" | grep -iq 'APROVADA' && _fecho_positivo=1
  [ -z "$vline" ] && [ "$vazio" -eq 0 ] && _fecho_positivo=1

  _tem_prova=1
  if [ "$_fecho_positivo" -eq 1 ]; then
    if prova_material "${t0:-}"; then _tem_prova=1; else _tem_prova=0; fi
    _prova_linha=$(printf '%s' "$PROVA_MATERIAL_TXT" | grep -m1 '^PROVA-MATERIAL:')
    log "ordem $id: ${_prova_linha:-PROVA-MATERIAL: <sonda sem resposta>}"
    printf '%s\n' "$PROVA_MATERIAL_TXT" > "$FILA/$id.prova-material.txt" 2>/dev/null || true
  fi

  if [ "$_tem_prova" -eq 0 ]; then
    # Sem prova material NÃO se fecha como concluída, diga o Juiz o que disser. Estado próprio
    # (`incompleta`) para o Danilo distinguir de `travada` (avaria) e de `concluida` (entregue).
    setf estado incompleta "$f"
    setf nota "👻 INCOMPLETA — SEM PROVA MATERIAL: nenhum ficheiro criado/alterado em disco nem commit desde o arranque da ordem. O executor produziu TEXTO (marcos: $(get marcos "$f")), mas texto não é entrega. Falta: fazer mesmo o trabalho descrito na saída ($id.saida.txt). Sonda: ${_prova_linha:-<sem resposta>}" "$f"
    setf revisao pendente "$f"
    printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$id" "sem prova material (entrega fantasma) — motor_final=$(get motor_final "$f")" >> "$REVISAO_PENDENTE"
    log "ordem $id: 👻 INCOMPLETA (sem prova material) — motor_final=$(get motor_final "$f"), veredito=${vline:-<nenhum>}"
    ultima_veredito="INCOMPLETA-SEM-PROVA"
    sync_espelho
    continue
  fi

  if printf '%s' "$vline" | grep -iq 'APROVADA'; then
    setf estado aprovada "$f"; setf nota "" "$f"; log "ordem $id: APROVADA"
    ultima_veredito="APROVADA"; n_aprovadas=$((n_aprovadas+1))

    # FASE 2 SISTEMA-100 (2026-08-11): segunda opiniao do conselho DEPOIS do Juiz mecanico ja
    # ter aprovado — ver revisao_conselho() acima. So ordens avulsas (sem missao, para nao
    # interferir no encadeamento existente). Falha de qualquer tipo aqui = fecha na mesma.
    if [ -z "$missao" ]; then
      cv=$(revisao_conselho "$f" "$id" "$tarefa" "$saida")
      ronda_c=$(get conselho_ronda "$f"); ronda_c=${ronda_c:-0}
      if [ "$cv" = "DIVERGENCIA" ] && [ "$ronda_c" -lt "$CONSELHO_RONDAS_MAX" ]; then
        setf estado aberta "$f"
        setf tentativa "$((tent-1))" "$f"     # revisao de qualidade nao gasta o teto T1
        setf conselho_pendente sim "$f"
        setf nota "🔎 conselho pediu ajuste (ronda $ronda_c/$CONSELHO_RONDAS_MAX) — ver $id.conselho-r$ronda_c.txt" "$f"
        log "ordem $id: conselho pediu ajuste (ronda $ronda_c/$CONSELHO_RONDAS_MAX) -> reaberta"
        sync_espelho
        continue
      fi
      [ "$cv" = "DIVERGENCIA" ] && log "ordem $id: conselho ainda com objecoes na ronda $ronda_c, teto atingido -> fecha registando divergencia"
      [ "$cv" = "CONSENSO" ] && log "ordem $id: conselho sem objecoes (ronda $ronda_c) -> consenso"
    fi

    if [ -n "$missao" ]; then
      missao_avanca "$missao" "$passo"
    else
      # 2026-07-13 (ordem f523): restaurado o aviso de conclusão — antes era
      # silêncio total (reengenharia 2026-07-12, pensada só para não repetir
      # aviso a cada passo de uma MISSÃO). Ordem avulsa aprovada volta a avisar.
      resumo=$(resultado_1linha "$saida")
      # FASE 4 (2026-08-11): formato de 3 LINHAS, igual em todos os avisos —
      # o quê · veredito do conselho · o que falta. Antes era uma linha só e não dizia se o
      # conselho tinha concordado, o que obrigava o Danilo a ir ver o ficheiro para saber se
      # podia confiar no "concluída". A informação que decide já vem no aviso.
      case "${cv:-}" in
        CONSENSO)    _vc="conselho concordou (ronda ${ronda_c:-1})";;
        DIVERGENCIA) _vc="conselho MANTEVE objeções ao fim de ${ronda_c:-?} rondas — vale uma vista de olhos";;
        *)           _vc="conselho não opinou (fora de serviço ou missão encadeada)";;
      esac
      _falta="nada — fechada pelo Juiz e pelo conselho"
      [ "${cv:-}" = "DIVERGENCIA" ] && _falta="ver $id.conselho-r${ronda_c:-1}.txt (o que o conselho ainda queria)"
      notify "✅ Bora: ordem \`$id\` concluída.
· O quê: ${resumo:-(sem resumo)}
· Conselho: $_vc
· Falta: $_falta"
      log "ordem $id: aprovada -> Telegram (conclusão)"
      acordar_claude FECHOU "$id" aprovada "${resumo:-sem resumo}"   # FASE 3
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
          # (2026-08-11) A nota antiga ADIVINHAVA ("tarefa grande demais?"). Essa frase ja escondeu
          # 4 dias de avaria real (o binario da CLI mudou de sitio a 27/07). Agora diz o MEDIDO.
          _dur=$(( $(date +%s) - ${t_att:-$(date +%s)} ))
          _bytes=$(printf '%s' "$saida" | wc -c | tr -d ' ')
          _ultima=$(printf '%s' "$saida" | grep -v '^[[:space:]]*$' | tail -1 | cut -c1-120)
          nota="⏱️ SAIDA-VAZIA (medido) — executor devolveu ${_bytes} bytes uteis em ${_dur}s na tentativa ${tent}; ultima linha: ${_ultima:-<nenhuma>}. Nao morreu por inatividade nem por teto (esses tem nota propria)."
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
    elif [ "$tent" -ge "$teto" ]; then
      setf estado travada "$f"; log "ordem $id: TRAVADA ($teto tentativas) — nota: $nota"; ultima_veredito="TRAVADA"; missao_travada_ou_silencio "$f" "$missao" "$passo"
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
