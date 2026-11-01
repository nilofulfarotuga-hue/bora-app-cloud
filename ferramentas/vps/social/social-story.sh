#!/usr/bin/env bash
# social-story.sh — 1 story por dia as 19:30 de Lisboa, no Instagram E no Facebook.
# Alterna: dia par = foto real (a ultima cena guardada) com pergunta por cima;
# dia impar = so a pergunta em fundo da marca. A pergunta roda por uma lista.
# Guarda de "ja saiu hoje": .story-feita-<data>. Sem TVDE/boleia.
set -u
BASE=/opt/data/social; TMPD=$BASE/tmp; PY=$BASE/venv/bin/python; LOG=$BASE/log.md
ENVFILE=${SOCIAL_ENV:-/opt/data/.env}; FORCE=${SOCIAL_FORCE:-0}
HOJE=$(TZ=Europe/Lisbon date +%F); HORA=$(TZ=Europe/Lisbon date +%H); DIA=$(TZ=Europe/Lisbon date +%j)
STAMP=$(TZ=Europe/Lisbon date +%Y-%m-%dT%H:%M:%S%z)
log() { printf -- '- [%s] story: %s\n' "$STAMP" "$*" >> "$LOG"; }
# ensaio a seco da escolha (2026-10-27): nao escreve no log.md, so no ecra
[ "${SOCIAL_ENSAIO_ESCOLHA:-0}" = "1" ] && log() { printf -- '  (ensaio) %s\n' "$*" >&2; }
mkdir -p "$TMPD"
# ensaio completo (B8, 2026-11-01): SOCIAL_DRY_RUN=1 monta e confere a story
# toda (frase, foto, portoes, kit) mas NAO publica, nao marca o dia como feito,
# nao avisa no Telegram e nao escreve no log.md nem por cima da peca do dia.
DRY=${SOCIAL_DRY_RUN:-0}
if [ "$DRY" = "1" ]; then
  LOG=$TMPD/ensaio-story.log
  log() { printf -- '  (ensaio) %s\n' "$*" >&2; printf -- '- [%s] story(ensaio): %s\n' "$STAMP" "$*" >> "$LOG"; }
fi
# Se o .env nao se ler, a tarefa NAO morre calada: grita por um canal que
# nao depende dele (gritar.sh usa uma copia do token guardada a parte).
# Cicatriz de 2026-09-06, terceira vez: a loja do dia morreu ao meio-dia
# com "Permission denied" e ninguem soube ate a noite.
if [ ! -r "$ENVFILE" ]; then
  [ "${SOCIAL_DRY_RUN:-0}" = "1" ] || /opt/data/scripts/gritar.sh "$(basename "$0") nao arrancou: o ficheiro de segredos das redes ($ENVFILE) nao se le. A guarda das permissoes corre de 10 em 10 minutos e deve repor sozinha; se este aviso se repetir, e a mao." 2>/dev/null || true
  exit 1
fi
set -a; . "$ENVFILE"; set +a

# --- Portao de autenticacao da Meta (missao reels-veo-05-09, 2026-09-05) ------
# Ao 3 erro de autenticacao seguido para de tentar e so volta de hora a hora.
# Bater na API a falhar foi o que fez bloquearem a conta a 4 de Setembro.
PORTAO=/opt/data/social/portao_auth.py
if [ -f "$PORTAO" ] && [ "$DRY" != "1" ]; then
  if ! /opt/data/social/venv/bin/python "$PORTAO" --pode-tentar >/dev/null 2>&1; then
    echo "portao de autenticacao fechado; nao tento publicar" >&2
    exit 0
  fi
fi
# -----------------------------------------------------------------------------

# DOIS STORIES POR DIA (2026-09-07, cadencia nova do Danilo): um as 10:00 e outro
# as 19:30. Cada slot tem a SUA guarda -- se partilhassem a mesma, o da manha
# marcava o dia como feito e o da noite saltava-se a si proprio, que e a familia
# de falhas silenciosas que esta cadencia veio matar.
SLOT=${SOCIAL_SLOT:-noite}
GUARDA_STORY="$BASE/.story-feita-$HOJE"
[ "$SLOT" = manha ] && GUARDA_STORY="$BASE/.story-manha-feita-$HOJE"
if [ "$FORCE" != "1" ] && [ "$DRY" != "1" ]; then
  if [ "$SLOT" = manha ]; then
    case "$HORA" in 09|10|11) : ;; *) log "SALTA: sao $HORA em Lisboa; o story da manha e as 10:00"; exit 0 ;; esac
  else
    case "$HORA" in 18|19|20) : ;; *) log "SALTA: sao $HORA em Lisboa; o story e as 19:30"; exit 0 ;; esac
  fi
  [ -f "$GUARDA_STORY" ] && { log "SALTA: ja saiu o story do slot $SLOT"; exit 0; }
fi
# B8 (2026-11-01, stories-em-breve-2026-11-01): ordem do Danilo 01/11 19:56
# "Robo da Story esta publicando lojas em breve". A lista fixa NAO leva nome de
# loja nenhum, nem convite a pedir lojas que ainda nao estao no Bora: sairam
# "Qual e a loja da Guarda que querias ver no Bora?" (foi a das stories de
# 01/11, le-se como anuncio de lojas em breve), a da Barbearia Ouro e Prata e a
# do Sabores do Brasil. Ficam 7 frases genericas (a rotacao % 7 nao muda).
PERGUNTAS=(
  "O que pedes hoje na Guarda?"
  "Já usaste o código BEMVINDO?"
  "Jantar de casa ou do restaurante? Pede no Bora."
  "Compras do supermercado sem fila. Já experimentaste?"
  "Mercado, farmácia ou jantar: o que te levamos hoje?"
  "Um recado na Guarda? Um estafeta trata disso por ti."
  "Festa em casa? Encomenda pelo Bora e recebe a horas."
)
N=${#PERGUNTAS[@]}
# --- REGRA DAS LOJAS PERMITIDAS (2026-10-27, missao redes-coming-soon) --------
# CICATRIZ: a 26/10 saiu outra vez a frase da Ouro e Prata (coming_soon=true
# desde 25/09, proibida nas redes desde 05/10), porque esta lista e fixa e
# ninguem perguntava a base. Agora cada frase que fala de uma loja passa por
# lojas_permitidas.py (Supabase na hora + lista fixa de exclusao). Frase
# bloqueada ou base sem resposta: salta para a frase seguinte; as genericas
# passam sempre, por isso ha sempre story, mas nunca de loja fechada.
if { [ "${SOCIAL_ENSAIO_ESCOLHA:-0}" = "1" ] || [ "$DRY" = "1" ]; } && [ -n "${SOCIAL_ENSAIO_DATA:-}" ]; then
  HOJE=$SOCIAL_ENSAIO_DATA; DIA=$(date -d "$HOJE" +%j)
fi
# B8: %j vem com zeros a esquerda (008, 089...) e o bash le-o como octal e
# rebenta nesses dias; forca base 10.
DIA=$((10#$DIA))
P=
for k in $(seq 0 $(( N - 1 ))); do
  CAND=${PERGUNTAS[$(( (DIA + k) % N ))]}
  VLP=$("$PY" "$BASE/lojas_permitidas.py" --texto "$CAND" 2>&1)
  if [ $? -eq 0 ]; then P=$CAND; break; fi
  log "lojas permitidas: salto a frase \"$CAND\": $VLP"
done
[ -n "$P" ] || { log "FALHOU: nenhuma frase passou na regra das lojas permitidas"; exit 1; }
# --- CONTADOR "A Guarda tem tudo" (2026-10-29, missao final-app-2026-10-29, passo 5.b) ----
# Nos dias listados em social/contador-datas.txt, o story da MANHA (10:00) leva a frase do
# contador, calculada na hora com o que a base tem (contador_guarda.py usa a mesma regra de
# lojas_permitidas.py). Se a base nao responder, ou a frase falhar a regra das lojas
# permitidas, fica a pergunta normal: nunca sai numero inventado.
if [ "$SLOT" = manha ] && "$PY" "$BASE/contador_guarda.py" --hoje "$HOJE" >/dev/null 2>&1; then
  CF=$("$PY" "$BASE/contador_guarda.py" --frase 2>"$TMPD/contador.err")
  if [ $? -eq 0 ] && [ -n "$CF" ]; then
    VLP=$("$PY" "$BASE/lojas_permitidas.py" --texto "$CF" 2>&1)
    if [ $? -eq 0 ]; then P=$CF; log "contador: $CF"; else log "contador BLOQUEADO pela regra das lojas: $VLP"; fi
  else
    log "contador: sem numeros da base ($(tail -1 "$TMPD/contador.err" 2>/dev/null)); sai a pergunta normal"
  fi
fi
# ------------------------------------------------------------------------------------
if [ "${SOCIAL_ENSAIO_ESCOLHA:-0}" = "1" ]; then echo "ENSAIO story $SLOT $HOJE (dia $DIA): sairia \"$P\""; exit 0; fi
# ------------------------------------------------------------------------------

# --- PORTAO DA FOTO DO PARCEIRO (2026-09-08) ----------------------------------
# CICATRIZ: a 2026-09-07 saiu no Instagram e no Facebook um story com o texto da
# barbearia por cima de uma fotografia de um saco de compras de supermercado. O
# texto vinha de `DIA % 7` e a foto de `ls -t cenas/*.jpg | head -1` -- duas
# contas sem relacao nenhuma, e nada media se batiam certo.
#
# Agora quem escolhe a foto e' o portao: se o texto fala de um parceiro concreto,
# a foto TEM de ser desse parceiro; se ele nao tiver foto, o story NAO sai e
# grita-se, em vez de publicar uma imagem generica de outra categoria.
FOTO=
if [ $(( DIA % 2 )) -eq 0 ]; then
  FOTO=$("$PY" "$BASE/portao_parceiro.py" --escolher-foto --texto "$P" --dia "$DIA" --permitir-generica 2>"$TMPD/portao-parceiro.err")
else
  FOTO=$("$PY" "$BASE/portao_parceiro.py" --escolher-foto --texto "$P" --dia "$DIA" 2>"$TMPD/portao-parceiro.err")
fi
if [ $? -ne 0 ]; then
  MOT=$(cat "$TMPD/portao-parceiro.err" 2>/dev/null)
  log "PORTAO DA FOTO DO PARCEIRO travou o story: $MOT"
  [ "$DRY" = "1" ] || /opt/data/scripts/gritar.sh "Story de $HOJE nao saiu, e de proposito: $MOT" 2>/dev/null || true
  exit 1
fi
# ------------------------------------------------------------------------------
SAIDA=$BASE/saidas/$HOJE-story-1930.jpg
[ "$DRY" = "1" ] && SAIDA=$TMPD/ensaio-story-$HOJE-$SLOT.jpg
if [ -n "$FOTO" ]; then
  "$PY" "$BASE/story_pergunta.py" --pergunta "$P" --foto "$FOTO" --logo "$BASE/imagens/bora_logo.png" --origem qr-story --saida "$SAIDA" >/dev/null 2>"$TMPD/story.err" || { log "FALHOU a montagem: $(tail -1 "$TMPD/story.err")"; exit 1; }
else
  "$PY" "$BASE/story_pergunta.py" --pergunta "$P" --logo "$BASE/imagens/bora_logo.png" --origem qr-story --saida "$SAIDA" >/dev/null 2>"$TMPD/story.err" || { log "FALHOU a montagem: $(tail -1 "$TMPD/story.err")"; exit 1; }
fi
log "story montado: $SAIDA (pergunta: $P; foto: ${FOTO:-nenhuma})"

# Segunda passagem do portao do parceiro, agora sobre o par (texto, foto) que
# foi mesmo montado. A primeira escolheu; esta confere. Sao duas porque o valor
# de FOTO pode ser mexido entre uma coisa e outra, e o que interessa e' o que
# saiu, nao o que se pediu.
VP=$("$PY" "$BASE/portao_parceiro.py" --verificar --texto "$P" --foto "$FOTO" 2>&1)
if [ $? -ne 0 ]; then
  log "PORTAO DA FOTO DO PARCEIRO reprovou: $VP. NAO publiquei."
  [ "$DRY" = "1" ] || /opt/data/scripts/gritar.sh "Story de $HOJE nao saiu: $VP" 2>/dev/null || true
  exit 1
fi
log "portao do parceiro: $VP"
# B8 (2026-11-01): ultima porta pela regra unica antes de publicar. A loja da
# foto (se for de uma loja) tem de dar 0 em lojas_permitidas.py --verifica.
DONO=$("$PY" -c 'import sys; sys.path.insert(0, "/opt/data/social"); import lojas_permitidas as lp; d = lp.dono_da_foto(sys.argv[1]) if sys.argv[1] else None; print(d or "")' "$FOTO" 2>/dev/null)
if [ -n "$DONO" ] && [ "$DONO" != generica ]; then
  VLP=$("$PY" "$BASE/lojas_permitidas.py" --verifica "$DONO" 2>&1); RLP=$?
  if [ $RLP -ne 0 ]; then
    log "LOJAS PERMITIDAS reprovou a foto ($DONO, codigo $RLP): $VLP. NAO publiquei."
    [ "$DRY" = "1" ] || /opt/data/scripts/gritar.sh "Story de $HOJE nao saiu: a foto e de $DONO, que nao pode sair nas redes ($VLP)" 2>/dev/null || true
    exit 1
  fi
  log "lojas permitidas: foto de $DONO -> $VLP"
fi

# --- PORTAO DO DESIGN KIT (2026-09-04, crescer-bora-04-09) --------------------
# Nada sai sem passar pelo kit. Ver /opt/data/social/design-kit.md (§9).
. /opt/data/social/portao_kit.sh
if ! portao_kit "$SAIDA"; then
  log "DESIGN KIT REPROVOU a peca: NAO publiquei. Motivos na linha kit: acima."
  exit 1
fi
# ------------------------------------------------------------------------------
if [ "$DRY" = "1" ]; then
  echo "ENSAIO story $SLOT $HOJE (dia $DIA): sairia \"$P\" foto=${FOTO:-nenhuma} dono=${DONO:-nenhum} peca=$SAIDA -- NAO publiquei"
  exit 0
fi

# publicar_cartaz.sh so com stories: passa o story como feed vazio? Nao — usa a funcao propria:
G=https://graph.facebook.com/${META_GRAPH_VERSION:-v21.0}; AUTH=(-H "Authorization: Bearer $META_PAGE_TOKEN")
J=$TMPD/st-$HOJE.json; PID=$(curl -sS --max-time 180 -o "$J" -w '' -X POST "$G/$META_PAGE_ID/photos" "${AUTH[@]}" -F "source=@$SAIDA" -F "published=false"; jq -r '.id // empty' "$J")
[ -n "$PID" ] || { log "FALHOU upload FB: $(cut -c1-200 "$J")"; exit 1; }
curl -sS --max-time 120 -o "$J" -X POST "$G/$META_PAGE_ID/photo_stories" "${AUTH[@]}" -F "photo_id=$PID" >/dev/null
FBS=$(jq -r 'if .success==true then "ok" else (.error.message // "falhou") end' "$J"); log "FB STORY: $FBS"
IMG=$(curl -sS --max-time 60 "${AUTH[@]}" "$G/$PID?fields=images" | jq -r '.images[0].source // empty')
curl -sS --max-time 120 -o "$J" -X POST "$G/$IG_USER_ID/media" "${AUTH[@]}" -F "image_url=$IMG" -F "media_type=STORIES" >/dev/null
CID=$(jq -r '.id // empty' "$J"); IGS=falhou
if [ -n "$CID" ]; then
  for i in 1 2 3 4 5 6 7 8 9 10 11 12; do S=$(curl -sS --max-time 30 "${AUTH[@]}" "$G/$CID?fields=status_code" | jq -r '.status_code // empty'); [ "$S" = FINISHED ] && break; [ "$S" = ERROR ] && break; sleep 5; done
  curl -sS --max-time 120 -o "$J" -X POST "$G/$IG_USER_ID/media_publish" "${AUTH[@]}" -F "creation_id=$CID" >/dev/null
  IGS=$(jq -r '.id // (.error.message // "falhou")' "$J")
fi
log "IG STORY: $IGS"
printf 'Story do Bora %s\nPergunta: %s\nFacebook: %s\nInstagram: %s\n' "$HOJE" "$P" "$FBS" "$IGS" > "$TMPD/tg-story.txt"
(cd /opt/data && python3 /opt/data/voz/porteiro_cli.py send -t telegram -f "$TMPD/tg-story.txt" --json >/dev/null 2>&1)
if [ "$FBS" = ok ] || [ "$IGS" != falhou ]; then : > "$GUARDA_STORY"; printf 'fb=%s\nig=%s\n' "$FBS" "$IGS"; exit 0; fi
exit 1
