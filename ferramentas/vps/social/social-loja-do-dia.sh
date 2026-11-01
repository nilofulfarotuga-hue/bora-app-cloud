#!/usr/bin/env bash
# social-loja-do-dia.sh — "uma loja por dia", todos os dias as 12:00 de Lisboa.
#
# Le /opt/data/social/rotacao.md: a primeira linha "por publicar" com data <= hoje
# e a loja do dia. Publica no Facebook E no Instagram (feed + story) com
# publicar_cartaz.sh, marca a linha como "feito" com os links, e manda o link ao
# Telegram do Danilo. Se a tabela acabar, continua sozinho (parceiro, grande,
# parceiro, grande...) lendo a base.
#
# Regras de marca (ordem do Danilo, 03/09):
#  - parceiro (is_partner=true, coming_soon=false): logo real + cena feita a partir
#    das fotos reais + marcacao (social_instagram da base ou parceiros.md)
#  - loja grande (is_partner=false): nome SO em texto, sem logo nem fotos deles,
#    cena generica da categoria, aviso legal no fim da legenda
#  - nunca TVDE/boleia
#
# Cena "de cinema": 1) tenta o Gemini pela API (gerar_cena.py); 2) se a API
# estiver no tecto (429/403), usa a ultima cena guardada em cenas/<slug>-*.jpg
# (parceiros) ou cenas/generico-<categoria>.jpg (grandes); 3) se nao houver
# nenhuma, avisa no Telegram "cena por gerar" e usa o cartaz plano de reserva.
#
# Guarda de "ja publicou hoje": /opt/data/social/.loja-feita-<data>.
# Vigia: publicar_cartaz.sh ja tenta 1x mais e avisa com o erro.
set -u
BASE=/opt/data/social
LOG=$BASE/log.md
TMPD=$BASE/tmp
PY=$BASE/venv/bin/python
ENVFILE=${SOCIAL_ENV:-/opt/data/.env}
ROT=${SOCIAL_ROTACAO:-$BASE/rotacao.md}   # B8: SOCIAL_ROTACAO so para ensaios com copia
FORCE=${SOCIAL_FORCE:-0}
DRY=${SOCIAL_DRY_RUN:-0}
HOJE=$(TZ=Europe/Lisbon date +%F)
HORA=$(TZ=Europe/Lisbon date +%H)
STAMP=$(TZ=Europe/Lisbon date +%Y-%m-%dT%H:%M:%S%z)
log() { printf -- '- [%s] loja-do-dia: %s\n' "$STAMP" "$*" >> "$LOG"; }
# ensaio a seco da escolha (2026-10-27): nao escreve no log.md, so no ecra
[ "${SOCIAL_ENSAIO_ESCOLHA:-0}" = "1" ] && log() { printf -- '  (ensaio) %s\n' "$*" >&2; }
avisar() { printf '%s\n' "$*" > "$TMPD/aviso-loja.txt"; (cd /opt/data && python3 /opt/data/voz/porteiro_cli.py send -t telegram -f "$TMPD/aviso-loja.txt" --json >/dev/null 2>&1) || log "AVISO NAO SAIU (hermes send falhou); o texto era: $*"; }
# B8 (2026-11-01): em ensaio (SOCIAL_DRY_RUN=1) nada vai ao Telegram nem ao
# log.md, e uma loja bloqueada salta-se so em memoria (SALTAR), sem marcar o
# rotacao.md verdadeiro.
if [ "$DRY" = "1" ]; then
  LOG=$TMPD/ensaio-loja.log
  avisar() { log "(ensaio, Telegram nao enviado) $*"; }
fi
saltar_linha() {  # $1 = estado a escrever na linha
  if [ "$DRY" = "1" ] || [ "${SOCIAL_ENSAIO_ESCOLHA:-0}" = "1" ]; then
    SALTAR="${SALTAR:-} $SLUG"; export SALTAR; exec "$0"
  fi
  "$PY" "$BASE/marcar_rotacao.py" --rotacao "$ROT" --data "$DATA" --slug "$SLUG" --estado "$1"
  exec "$0"
}
mkdir -p "$TMPD" "$BASE/cenas" "$BASE/saidas"

# Se o .env nao se ler, a tarefa NAO morre calada: grita por um canal que
# nao depende dele (gritar.sh usa uma copia do token guardada a parte).
# Cicatriz de 2026-09-06, terceira vez: a loja do dia morreu ao meio-dia
# com "Permission denied" e ninguem soube ate a noite.
if [ ! -r "$ENVFILE" ]; then
  [ "${SOCIAL_DRY_RUN:-0}" = "1" ] || /opt/data/scripts/gritar.sh "$(basename "$0") nao arrancou: o ficheiro de segredos das redes ($ENVFILE) nao se le. A guarda das permissoes corre de 10 em 10 minutos e deve repor sozinha; se este aviso se repetir, e a mao." 2>/dev/null || true
  exit 1
fi
set -a; . "$ENVFILE"; set +a

if [ "$FORCE" != "1" ] && [ "$DRY" != "1" ]; then
  case "$HORA" in 11|12|13) : ;; *) log "SALTA: sao $HORA em Lisboa; a loja do dia e ao meio-dia"; exit 0 ;; esac
  if [ -f "$BASE/.loja-feita-$HOJE" ]; then log "SALTA: ja saiu a loja de hoje ($HOJE)"; exit 0; fi
fi

# ── 1. Que loja e hoje? ───────────────────────────────────────────────────────
if [ "${SOCIAL_ENSAIO_ESCOLHA:-0}" = "1" ] && [ -n "${SOCIAL_ENSAIO_DATA:-}" ]; then HOJE=$SOCIAL_ENSAIO_DATA; fi
LINHA=$(SALTAR="${SALTAR:-}" "$PY" - "$ROT" "$HOJE" <<'PYFIM'
import os, re, sys
rot, hoje = sys.argv[1], sys.argv[2]
saltar = os.environ.get("SALTAR", "").split()  # so usado no ensaio a seco
for l in open(rot, encoding="utf-8"):
    c = [x.strip() for x in l.strip().strip("|").split("|")]
    if len(c) >= 6 and re.match(r"\d{4}-\d{2}-\d{2}$", c[0]) and c[5] == "por publicar" and c[0] <= hoje and c[1] not in saltar:
        print("|".join(c[:5])); break
PYFIM
)
if [ -z "$LINHA" ] && { [ "${SOCIAL_ENSAIO_ESCOLHA:-0}" = "1" ] || [ "$DRY" = "1" ]; }; then
  # B8: no ensaio mostra a escolha do proxima_loja.py sem escrever no rotacao.md
  LINHA=$(SALTAR="${SALTAR:-}" "$PY" "$BASE/proxima_loja.py" --rotacao "$ROT" --hoje "$HOJE" --so-mostrar 2>&1) || { echo "ENSAIO loja-do-dia $HOJE: proxima_loja.py falhou: $LINHA"; exit 1; }
  echo "ENSAIO loja-do-dia $HOJE: sem linha por publicar; o proxima_loja.py escolheria $LINHA"
fi
if [ -z "$LINHA" ]; then
  log "rotacao.md sem linhas por publicar; a continuar pela regra parceiro/grande"
  LINHA=$("$PY" "$BASE/proxima_loja.py" --rotacao "$ROT" --hoje "$HOJE" 2>>"$TMPD/proxima.err") || { log "FALHOU: proxima_loja.py: $(tail -2 "$TMPD/proxima.err")"; avisar "Loja do dia $HOJE: nao consegui escolher a loja (proxima_loja.py falhou)."; exit 1; }
fi
IFS='|' read -r DATA SLUG TABELA TIPO CAT <<< "$LINHA"
log "hoje e $TIPO $SLUG ($TABELA, $CAT)"

# ── 1b. Regra das lojas permitidas (2026-10-27, missao redes-coming-soon) ─────
# Supabase na hora + lista fixa de exclusao (lojas_permitidas.py). Bloqueada:
# marca-se saltada e passa a linha seguinte. Base sem resposta: NAO sai peca de
# loja hoje (nunca publicar na mesma) e a linha fica por publicar para amanha.
VLP=$("$PY" "$BASE/lojas_permitidas.py" --verifica "$SLUG" --tabela "$TABELA" 2>&1); RLP=$?
if [ "${SOCIAL_ENSAIO_ESCOLHA:-0}" = "1" ]; then
  echo "ENSAIO loja-do-dia $HOJE: linha $DATA $SLUG ($TABELA) -> $VLP (codigo $RLP)"
  [ $RLP -eq 3 ] && { SALTAR="${SALTAR:-} $SLUG"; export SALTAR; exec "$0"; }
  exit 0
fi
if [ $RLP -eq 3 ]; then
  log "SALTA $SLUG: $VLP; marco a linha como saltada"
  saltar_linha "SALTADA (em breve/inativa/exclusao)"
elif [ $RLP -ne 0 ]; then
  log "NAO PUBLICO hoje: $VLP"
  avisar "Loja do dia $HOJE nao saiu, de proposito: $VLP"
  exit 1
fi

# ── 2. Dados da loja na base ──────────────────────────────────────────────────
DADOS=$TMPD/loja-$SLUG.json
curl -sS --max-time 40 -o "$DADOS" -H "apikey: $SUPABASE_ANON_KEY" -H "Authorization: Bearer $SUPABASE_ANON_KEY" \
  "$SUPABASE_URL/rest/v1/$TABELA?id=eq.$SLUG&select=id,name,category,photo_url,hero_image_url,social_instagram,social_facebook,is_active_admin,coming_soon"
NOME=$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d[0]["name"] if d else "")' "$DADOS")
ACTIVA=$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print("sim" if d and d[0].get("is_active_admin") and not d[0].get("coming_soon") else "nao")' "$DADOS")
IG_ALVO=$("$PY" -c 'import json,sys,re; d=json.load(open(sys.argv[1])); u=(d[0].get("social_instagram") or "") if d else ""; m=re.search(r"instagram\.com/([A-Za-z0-9_.]+)", u); print(m.group(1) if m else "")' "$DADOS")
[ -z "$NOME" ] && { log "FALHOU: loja $SLUG nao encontrada em $TABELA"; avisar "Loja do dia $HOJE: $SLUG nao existe na base."; exit 1; }
if [ "$ACTIVA" != "sim" ]; then
  log "SALTA $SLUG: nao esta activa ou esta coming_soon; marco a linha como saltada"
  saltar_linha "saltada (inactiva/coming_soon)"   # passa a proxima linha
fi
# marcacao: base primeiro, depois parceiros.md
if [ -z "$IG_ALVO" ] && [ -f "$BASE/parceiros.md" ]; then
  IG_ALVO=$(grep -F "$SLUG" "$BASE/parceiros.md" | grep -oE 'instagram\.com/[A-Za-z0-9_.]+' | head -1 | cut -d/ -f2)
fi

# ── 3. Cena de cinema ─────────────────────────────────────────────────────────
CENA=
if [ "$DRY" = "1" ]; then
  echo "ensaio: sem gerar cena pela API (usa a guardada)" > "$TMPD/cena.out"   # B8: ensaio nao gasta API
else
"$PY" "$BASE/gerar_cena.py" --slug "$SLUG" --tabela "$TABELA" --tipo "$TIPO" --categoria "$CAT" --saida "$BASE/cenas/$SLUG-$HOJE-api.jpg" >"$TMPD/cena.out" 2>&1 && CENA="$BASE/cenas/$SLUG-$HOJE-api.jpg"
fi
[ -n "$CENA" ] && log "cena gerada pela API: $(tail -1 "$TMPD/cena.out")"
if [ -z "$CENA" ]; then
  log "API de imagem indisponivel ($(tail -1 "$TMPD/cena.out" | cut -c1-120)); uso cena guardada"
  if [ "$TIPO" = "parceiro" ]; then CENA=$(ls -t "$BASE/cenas/$SLUG"-*.jpg 2>/dev/null | head -1)
  else CENA=$(ls -t "$BASE/cenas/$SLUG"-*.jpg 2>/dev/null | head -1); [ -n "$CENA" ] || CENA=$(ls -t "$BASE/cenas/generico-$CAT"*.jpg 2>/dev/null | head -1); fi  # 31/10 banco-pecas: cena propria da loja grande primeiro (30/10 o KFC caiu no generico com mao deformada e foi reprovado)
fi
if [ -z "$CENA" ]; then
  log "sem cena para $SLUG; aviso e uso o cartaz plano de reserva"
  avisar "Loja do dia $HOJE ($NOME): nao ha cena de cinema guardada e a API do Gemini esta no tecto. Sai o cartaz plano de reserva. Gerar cena em gemini.google.com e guardar em $BASE/cenas/."
  CENA=$BASE/imagens/fundo-reserva.jpg
fi

# --- PORTAO DA FOTO DO PARCEIRO (2026-09-08) ----------------------------------
# A peca de um parceiro CONCRETO so pode usar foto DESSE parceiro, e a categoria
# tem de bater. Cicatriz de 2026-09-07: barbearia publicada com fotografia de um
# saco de compras de supermercado. Se o parceiro nao tiver foto sua, a peca nao
# sai: grita-se, em vez de publicar imagem generica de outra categoria.
if [ "$TIPO" = "parceiro" ]; then
  FOTO_P=$("$PY" "$BASE/portao_parceiro.py" --escolher-foto --slug "$SLUG" --texto "$NOME" --dia "$(date +%j)" 2>"$TMPD/portao-parceiro.err")
  if [ $? -ne 0 ]; then
    MOT=$(cat "$TMPD/portao-parceiro.err" 2>/dev/null)
    log "PORTAO DA FOTO DO PARCEIRO travou a loja do dia: $MOT"
    avisar "Loja do dia $HOJE ($NOME): $MOT"
    exit 1
  fi
  VP=$("$PY" "$BASE/portao_parceiro.py" --verificar --slug "$SLUG" --texto "$NOME" --foto "$CENA" 2>&1)
  if [ $? -ne 0 ]; then
    log "PORTAO DA FOTO DO PARCEIRO reprovou a cena escolhida: $VP; troco por $FOTO_P"
    CENA=$FOTO_P
    VP=$("$PY" "$BASE/portao_parceiro.py" --verificar --slug "$SLUG" --texto "$NOME" --foto "$CENA" 2>&1)
    if [ $? -ne 0 ]; then
      log "PORTAO DA FOTO DO PARCEIRO reprovou tambem a foto de reserva: $VP. NAO publiquei."
      avisar "Loja do dia $HOJE ($NOME): $VP. Nao publiquei."
      exit 1
    fi
  fi
  log "portao do parceiro: $VP (cena $(basename "$CENA"))"
fi
# ------------------------------------------------------------------------------

# ── 4. Cartaz + legenda ───────────────────────────────────────────────────────
TIT=$("$PY" "$BASE/texto_loja.py" --nome "$NOME" --tipo "$TIPO" --categoria "$CAT" --campo titulo)
"$PY" "$BASE/texto_loja.py" --nome "$NOME" --tipo "$TIPO" --categoria "$CAT" --ig "$IG_ALVO" --campo legenda > "$TMPD/legenda-$SLUG.txt"
LOGO_ARG=(); NOME_CARTAZ="$NOME"; AVISO_ARG=()
if [ "$TIPO" = "parceiro" ]; then
  LOGO_URL=$("$PY" -c 'import json,sys; d=json.load(open(sys.argv[1])); print(d[0].get("photo_url") or "")' "$DADOS")
  if [ -n "$LOGO_URL" ] && curl -sSL --max-time 40 -o "$TMPD/logo-$SLUG.img" "$LOGO_URL"; then LOGO_ARG=(--logo-parceiro "$TMPD/logo-$SLUG.img"); fi
else
  AVISO_ARG=(--aviso "Serviço de entrega independente, sem ligação oficial à marca.")
fi
OUTD=$BASE/saidas; [ "$DRY" = "1" ] && { OUTD=$TMPD/ensaio-saidas; mkdir -p "$OUTD"; }  # B8: ensaio nao pisa a peca do dia
FEED=$OUTD/$HOJE-$SLUG-feed.jpg; STORY=$OUTD/$HOJE-$SLUG-story.jpg
for F in feed story; do
  "$PY" "$BASE/cartaz_cinema.py" --cena "$CENA" --formato "$F" --titulo "$TIT" --logo-bora "$BASE/imagens/bora_logo.png" \
    --origem "qr-$F" \
    "${LOGO_ARG[@]}" --nome "$NOME_CARTAZ" "${AVISO_ARG[@]}" --saida "$OUTD/$HOJE-$SLUG-$F.jpg" >>"$TMPD/cartaz.out" 2>&1 \
    || { log "FALHOU a montagem ($F): $(tail -2 "$TMPD/cartaz.out")"; avisar "Loja do dia $HOJE ($NOME): a montagem do cartaz falhou."; exit 1; }
done
log "cartazes prontos: $FEED e $STORY (cena $(basename "$CENA"))"

# ── 5. Juiz de visao (se a API responder) ─────────────────────────────────────
if [ "$DRY" != "1" ] && "$PY" "$BASE/juiz_visao.py" --imagem "$FEED" >"$TMPD/juiz.out" 2>&1; then
  log "juiz de visao: $(tail -1 "$TMPD/juiz.out")"
  if grep -q '^REPROVADO' "$TMPD/juiz.out"; then
    avisar "Loja do dia $HOJE ($NOME): o juiz de visao reprovou o cartaz: $(tail -1 "$TMPD/juiz.out"). Nao publiquei."
    exit 1
  fi
else
  log "juiz de visao indisponivel ($(tail -1 "$TMPD/juiz.out" | cut -c1-100)); sigo sem juiz"
fi

if [ "$DRY" = "1" ]; then log "ENSAIO: nao publiquei. $FEED"; printf '%s\n' "$FEED"; exit 0; fi

# ── 6. Publicar nas duas redes ────────────────────────────────────────────────
SAIDA=$(bash /opt/data/scripts/publicar_cartaz.sh "$FEED" "$STORY" "$TMPD/legenda-$SLUG.txt" "$IG_ALVO" "")
RC=$?
LFB=$(printf '%s\n' "$SAIDA" | sed -n 's/^facebook=//p'); LIG=$(printf '%s\n' "$SAIDA" | sed -n 's/^instagram=//p')
if [ $RC -eq 0 ]; then
  "$PY" "$BASE/marcar_rotacao.py" --rotacao "$ROT" --data "$DATA" --slug "$SLUG" --estado feito --links "FB $LFB · IG $LIG"
  : > "$BASE/.loja-feita-$HOJE"
  log "FIM: $SLUG publicado. facebook=$LFB instagram=$LIG"
  exit 0
fi
log "FIM: $SLUG NAO saiu nas duas redes (rc=$RC). facebook=${LFB:-nao} instagram=${LIG:-nao}"
exit 1
