#!/usr/bin/env bash
# hermes-hook-conclusao.sh — HOOK DE CONCLUSÃO POR EVENTO (mecanismo PRIMÁRIO do loop).
#
# Desenho do Danilo (2026-07-12): o encadeamento de tarefas passa a ser POR EVENTO, não por
# ronda de 10 min. Quando o carteiro fecha uma ordem (o juiz deu veredito terminal: APROVADA,
# TRAVADA ou ZONA_VERMELHA), ele CHAMA este hook, que revê o resultado e encadeia o próximo
# passo sozinho — só escalando ao Danilo no fim (missão inteira concluída) ou quando precisa
# mesmo de decisão dele (dinheiro / ambíguo). Nunca mais "alarme vermelho" de ordem travada que
# o sistema consegue auto-resolver: o sistema RESOLVE, não avisa.
#
# É a "cabeça" barata (bash no HOST, zero-Opus, não gasta o limite Claude.ai): o juízo de
# qualidade JÁ foi feito pelo pc-judge (APROVADA vs CORRIGIR×5→TRAVADA). Este hook só AGE sobre
# o veredito terminal. A camada cara (Claude Code) só volta a acordar via campainha quando o
# hook cria/reabre uma ordem — exatamente o que Danilo quer.
#
# DECISÃO (por veredito terminal):
#   APROVADA:
#     · faz parte de missão e há próxima parte PENDENTE  -> promove-a (pendente->aberta). SILENCIOSO.
#     · faz parte de missão e era a ÚLTIMA parte          -> MISSÃO CONCLUÍDA -> Telegram resumo.
#     · ordem solta (sem missão)                          -> concluída. SILENCIOSO (fim do spam por-ordem).
#   TRAVADA (zona verde, 5 tentativas esgotadas):
#     · continuacao < MAX_CONT  -> cria ORDEM DE CONTINUAÇÃO (continua de onde parou, nota do juiz
#                                  como contexto, 5 tentativas frescas). SILENCIOSO (auto-resolve).
#     · continuacao >= MAX_CONT -> genuinamente preso -> aviso (decisão: reformular/arquivar).
#   ZONA_VERMELHA:
#     · dinheiro / destrutivo / ambíguo -> Telegram + espera o Danilo. NUNCA auto.
#
# TELEGRAM ao Danilo em 3 casos: (a) missão inteira terminou; (b) travada esgotou continuações
# (genuinamente presa); (c) zona vermelha. Nos casos (a) e (b), desde 2026-08-01, o aviso passa
# primeiro pela Rotina Claude.ai (resumo em PT-BR escrito por LLM, via
# hermes-notificar-rotina.sh) — que cai sozinha no Telegram cru (o "caminho normal") quando o
# teto diário de corridas da rotina (5/dia no plano Pro) já foi gasto, ou quando a rotina ainda
# não foi configurada pelo Danilo. Nunca dispara por tentativa/ordem individual, só nestes
# vereditos terminais. Ver .claude/scripts/hermes-notificar-rotina.sh.
#
# Uso:  hermes-hook-conclusao.sh <ficheiro-ordem.md> <estado_final>
#       hermes-hook-conclusao.sh --selftest      (não toca docker/Telegram/fila real)
#
# Canónico: bora_app/.claude/scripts/. Deploy espelhado: /usr/local/bin/ no VPS + chamado por carteiro.sh.
set -u

MAX_CONT="${HOOK_MAX_CONT:-2}"   # nº de ordens de continuação antes de arquivar uma travada genuína
# PARIDADE PARTE 2.1: teto GENEROSO para pausas por --max-turns/--max-budget. Uma tarefa grande
# pode legitimamente precisar de várias continuações — na sessão interactiva do Danilo não há teto
# nenhum. Continua a ser um teto ABSOLUTO (backstop contra loop infinito), só que largo.
MAX_CONT_PAUSA="${HOOK_MAX_CONT_PAUSA:-8}"
# I4: travadas não-vermelhas que esgotam continuações vão para aqui (revisto no daily-pulse),
# em vez de Telegram. Telegram = só zona vermelha e missão concluída.
ARQUIVO_ESGOTADAS="${HOOK_ARQUIVO_ESGOTADAS:-/root/orquestracao/ordens-arquivadas.tsv}"
C=hermes-agent-fvnc-hermes-agent-1
HOSTDATA=/docker/hermes-agent-fvnc/data
FILA="${HOOK_FILA:-$HOSTDATA/cortex-brain/orquestracao}"
LOG="${HOOK_LOG:-/root/orquestracao/hook-conclusao.log}"
NOTIFICAR_ROTINA_BIN="${HOOK_NOTIFICAR_ROTINA:-/usr/local/bin/hermes-notificar-rotina.sh}"
SELFTEST=0
[ "${1:-}" = "--selftest" ] && SELFTEST=1

ts(){ date -u +%Y-%m-%dT%H:%M:%SZ; }
log(){ echo "[$(ts)] $*" >> "$LOG" 2>/dev/null || echo "[$(ts)] $*"; }
get(){ grep -E "^$1:" "$2" 2>/dev/null | head -1 | sed "s/^$1: *//" | tr -d '\r'; }
setf(){ if grep -qE "^$1:" "$3"; then sed -i "s|^$1:.*|$1: $2|" "$3"; else echo "$1: $2" >> "$3"; fi; }
# notify e escrita na fila real ficam atrás de guardas — o selftest não os dispara.
notify(){ [ "$SELFTEST" = 1 ] && { echo "[NOTIFY] $1"; return 0; }
  docker exec -u hermes "$C" hermes send -t telegram "$1" >/dev/null 2>&1 || log "notify(best-effort) falhou"; }
# notificar_rotina: avisos que valem o resumo LLM da Rotina (missão concluída / travada esgotada).
# Nunca chamar por tentativa/ordem individual — só nestes 2 vereditos terminais raros.
notificar_rotina(){ # $1=tipo  $2=texto
  [ "$SELFTEST" = 1 ] && { echo "[ROTINA tipo=$1] $2"; return 0; }
  if [ -x "$NOTIFICAR_ROTINA_BIN" ]; then
    "$NOTIFICAR_ROTINA_BIN" "$1" "$2" || log "notificar_rotina($1): dispatcher devolveu erro"
  else
    log "notificar_rotina($1): $NOTIFICAR_ROTINA_BIN ausente — a usar notify() cru"
    notify "$2"
  fi
}

# cria uma ordem NOVA na fila (equivalente-host de cortex_nova_ordem: escreve ordem-*.md -> campainha).
# $1=tarefa  $2..=pares "campo: valor" extra (missao/parte/continuacao/…)
cria_ordem(){
  local tarefa="$1"; shift
  local id criada dest
  id="ordem-$(date -u +%Y%m%d%H%M%S)-$(head -c2 /dev/urandom 2>/dev/null | od -An -tx1 | tr -d ' \n' || echo xx)"
  criada="$(ts)"
  dest="$FILA/$id.md"
  { printf -- '--- ordem ---\nid: %s\nestado: aberta\nautor: hook-conclusao\ncriada: %s\nzona: verde\ntentativa: 0\nteto_tentativas: 5\n' "$id" "$criada"
    for kv in "$@"; do printf '%s\n' "$kv"; done
    printf 'tarefa: %s\n--- fim ---\n' "$tarefa"
  } > "$dest"
  log "criou ordem $id (aberta) -> campainha"
  echo "$id"
}

# --- decisão principal -------------------------------------------------------
decide(){
  local f="$1" estado="$2"
  local id missao parte cont nota tarefa
  id=$(get id "$f"); missao=$(get missao "$f"); parte=$(get parte "$f")
  cont=$(get continuacao "$f"); cont=${cont:-0}
  nota=$(get nota "$f"); tarefa=$(get tarefa "$f")
  log "ordem $id: veredito=$estado missao=${missao:-—} parte=${parte:-—} continuacao=$cont"

  case "$estado" in
    aprovada)
      if [ -n "$missao" ]; then
        # próxima parte PENDENTE da mesma missão (menor 'parte')
        local prox="" pmin=999999
        for g in "$FILA"/*.md; do
          [ -f "$g" ] || continue
          [ "$(get missao "$g")" = "$missao" ] || continue
          [ "$(get estado "$g")" = "pendente" ] || continue
          local p; p=$(get parte "$g"); p=${p:-0}
          if [ "$p" -lt "$pmin" ] 2>/dev/null; then pmin=$p; prox="$g"; fi
        done
        if [ -n "$prox" ]; then
          setf estado aberta "$prox"                    # promove -> campainha encadeia
          log "MISSÃO $missao: parte $parte ok -> promovi parte $pmin ($(basename "$prox")). SILENCIOSO."
        else
          # não há mais partes pendentes -> missão concluída
          notificar_rotina missao_concluida "$(resumo_missao "$missao")"
          log "MISSÃO $missao: CONCLUÍDA (última parte $parte) -> aviso (rotina/fallback)."
        fi
      else
        log "ordem $id: solta, aprovada -> concluída (silenciosa)."
      fi
      ;;
    travada)
      # PARIDADE PARTE 2.1 + I4 (2026-08-01). Duas naturezas distintas de "travada":
      #  · pausa_teto=1 -> o executor bateu em --max-turns/--max-budget. NÃO é falha: é uma tarefa
      #    grande a meio. Numa sessão interactiva o Danilo não tem teto nenhum e ela acabava. Aqui
      #    dá-se um teto GENEROSO de continuações para o trabalho poder terminar. Continua a haver
      #    teto absoluto (um loop infinito não pode correr para sempre) e regista-se quando lá chega.
      #  · travada normal -> teto curto, como antes.
      # I4: esgotar continuações numa travada NÃO-vermelha deixa de chamar o Danilo por Telegram —
      # vai para a lista de arquivo revista no daily-pulse. Telegram fica reservado à zona vermelha
      # (o ramo abaixo) e à missão concluída.
      local teto="$MAX_CONT" tipo="TRAVADA"
      if [ "$(get pausa_teto "$f")" = "1" ]; then teto="$MAX_CONT_PAUSA"; tipo="PAUSA-POR-TETO"; fi
      if [ "$cont" -lt "$teto" ] 2>/dev/null; then
        local next=$((cont+1))
        local ctx
        if [ "$tipo" = "PAUSA-POR-TETO" ]; then
          ctx="[CONTINUAÇÃO ${next}/${teto} — a ordem $id NÃO falhou: o executor atingiu o teto de turnos/custo a meio do trabalho. Retoma exactamente de onde parou; NÃO recomeces do zero e NÃO repitas o que já ficou feito.]"
        else
          ctx="[CONTINUAÇÃO ${next}/${teto} — a ordem $id travou nas 5 tentativas. Nota do juiz: ${nota:-(sem nota)}. Continua de onde parou; não recomeces do zero.]"
        fi
        local extra=(); [ -n "$missao" ] && extra+=("missao: $missao"); [ -n "$parte" ] && extra+=("parte: $parte")
        extra+=("continuacao: $next")
        [ "$tipo" = "PAUSA-POR-TETO" ] && extra+=("pausa_teto: 1")
        cria_ordem "$tarefa $ctx" "${extra[@]}" >/dev/null
        log "ordem $id: $tipo -> criei continuação $next/$teto. SILENCIOSO (auto-resolve)."
      else
        # mkdir -p: sem isto, uma pasta em falta faz o append falhar e a ordem desaparece SEM
        # rasto — trocávamos "Telegram a mais" por "esquecimento em silêncio", que é pior.
        mkdir -p "$(dirname "$ARQUIVO_ESGOTADAS")" 2>/dev/null
        printf '%s\t%s\t%s\n' "$(date -u +%FT%TZ)" "$id" "$tipo esgotou $teto continuações; nota: ${nota:-—}" >> "$ARQUIVO_ESGOTADAS" \
          || log "ordem $id: AVISO — não consegui escrever em $ARQUIVO_ESGOTADAS"
        notificar_rotina travada_esgotada "🔒 Ordem $id ($tipo) esgotou $teto continuações e ficou genuinamente presa. Tarefa: ${tarefa:-—}. Nota do juiz: ${nota:-(sem nota)}. Precisa de decisão: reformular ou arquivar."
        log "ordem $id: $tipo + continuações esgotadas ($teto) -> ARQUIVO (daily-pulse) + aviso (rotina/fallback)."
      fi
      ;;
    zona_vermelha)
      notify "🔴 Bora/loop: ordem $id toca zona vermelha (dinheiro/produção/destrutivo) — precisa de ti."
      log "ordem $id: ZONA_VERMELHA -> ESCALEI (decisão)."
      ;;
    *)
      log "ordem $id: estado '$estado' não é terminal — hook não age."
      ;;
  esac
}

# resumo de missão para o Telegram (só quando a missão FECHA)
resumo_missao(){
  local missao="$1" linhas="" ultima_saida=""
  for g in "$FILA"/*.md; do
    [ -f "$g" ] || continue
    [ "$(get missao "$g")" = "$missao" ] || continue
    local p e; p=$(get parte "$g"); e=$(get estado "$g")
    linhas="${linhas}  • parte ${p:-?}: ${e}\n"
  done
  ultima_saida=$(cat "$FILA/$missao.saida.txt" 2>/dev/null | tail -6)
  printf '✅ Bora/loop: MISSÃO %s concluída.\n%b%s' "$missao" "$linhas" \
    "${ultima_saida:+\nÚltimo passo:\n$ultima_saida}"
}

# --- selftest (headless, sem docker/Telegram/fila real) ----------------------
selftest(){
  local tmp; tmp=$(mktemp -d); FILA="$tmp"; LOG="$tmp/hook.log"; ARQUIVO_ESGOTADAS="$tmp/arquivadas.tsv"; local ok=0 fail=0
  chk(){ if eval "$2"; then echo "  [OK] $1"; ok=$((ok+1)); else echo "  [X ] $1"; fail=$((fail+1)); fi; }

  echo "== T1: missão parte 1 aprovada -> promove parte 2 pendente =="
  printf 'id: o1\nestado: aprovada\nmissao: mtest\nparte: 1\ntarefa: a\n' > "$tmp/o1.md"
  printf 'id: o2\nestado: pendente\nmissao: mtest\nparte: 2\ntarefa: b\n' > "$tmp/o2.md"
  decide "$tmp/o1.md" aprovada
  chk "parte 2 passou pendente->aberta" '[ "$(get estado "$tmp/o2.md")" = "aberta" ]'

  echo "== T2: última parte aprovada -> sem promoção (missão fecha, notificar_rotina) =="
  printf 'id: o3\nestado: aprovada\nmissao: mfim\nparte: 2\ntarefa: c\n' > "$tmp/o3.md"
  out=$(SELFTEST=1 decide "$tmp/o3.md" aprovada 2>&1); # notificar_rotina imprime [ROTINA ...]
  chk "missão fechada gerou aviso" 'grep -q "CONCLUÍDA" "$tmp/hook.log"'
  chk "aviso passou pela rotina (tipo=missao_concluida)" 'printf "%s" "$out" | grep -q "\[ROTINA tipo=missao_concluida\]"'

  echo "== T3: travada continuacao<MAX -> cria ordem de continuação =="
  printf 'id: o4\nestado: travada\ntarefa: xyz\nnota: faltou X\ncontinuacao: 0\n' > "$tmp/o4.md"
  before=$(ls "$tmp"/ordem-*.md 2>/dev/null | wc -l)
  decide "$tmp/o4.md" travada
  after=$(ls "$tmp"/ordem-*.md 2>/dev/null | wc -l)
  chk "criou 1 ordem de continuação" '[ "$after" -gt "$before" ]'
  chk "continuação leva continuacao: 1" 'grep -rq "^continuacao: 1" "$tmp"/ordem-*.md'

  echo "== T4: travada continuacao>=MAX -> escala (nada de nova ordem, aviso via rotina) =="
  printf 'id: o5\nestado: travada\ntarefa: xyz\ncontinuacao: 2\n' > "$tmp/o5.md"
  before=$(ls "$tmp"/ordem-*.md 2>/dev/null | wc -l)
  out4=$(decide "$tmp/o5.md" travada 2>&1)
  after=$(ls "$tmp"/ordem-*.md 2>/dev/null | wc -l)
  chk "NÃO criou nova ordem (escalou)" '[ "$after" = "$before" ]'
  chk "log registou escalada" 'grep -q "continuações esgotadas" "$tmp/hook.log"'
  chk "aviso passou pela rotina (tipo=travada_esgotada)" 'printf "%s" "$out4" | grep -q "\[ROTINA tipo=travada_esgotada\]"'

  echo "== T5: ordem solta aprovada -> silenciosa (sem promoção/notify) =="
  printf 'id: o6\nestado: aprovada\ntarefa: solo\n' > "$tmp/o6.md"
  decide "$tmp/o6.md" aprovada
  chk "registou conclusão silenciosa" 'grep -q "solta, aprovada" "$tmp/hook.log"'

  rm -rf "$tmp"
  echo "-- selftest: $ok OK, $fail FALHAS --"
  [ "$fail" = 0 ]
}

# --- main --------------------------------------------------------------------
if [ "$SELFTEST" = 1 ]; then selftest; exit $?; fi
[ $# -ge 2 ] || { echo "uso: $0 <ficheiro-ordem.md> <estado_final>  |  --selftest" >&2; exit 2; }
[ -f "$1" ] || { log "ficheiro '$1' não existe — nada a fazer"; exit 0; }
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
decide "$1" "$2"
exit 0
