#!/usr/bin/env bash
# radar-videos-collect.sh — colector de VIDEOS (YouTube) do RADAR DE IA do batedor.
# Missao fecho-manha-2026-09-24 (bloco 4): o radar semanal passa a olhar tambem para
# novidades em video, nao so texto. Mesmo mecanismo do radar-dinheiro.sh (2026-09-02):
#   pesquisa por instancias Invidious (sem chave) -> yt-dlp tenta a LEGENDA automatica
#   -> se o YouTube bloquear a partir deste IP, usa a DESCRICAO do video, marcada como tal.
# Saida: texto simples em stdout, para ser colado ao material do radar-ia.sh.
# Zona verde: nao toca em dinheiro, dispatch, RLS nem no codigo do app.
set -u

# yt-dlp vive no venv do agent-reach (o /usr/local/bin/yt-dlp aponta la para dentro).
YTDLP=/opt/data/agent-reach-venv/bin/yt-dlp
[ -x "$YTDLP" ] || YTDLP=$(command -v yt-dlp 2>/dev/null || echo /usr/local/bin/yt-dlp)

DIAS="${RADAR_VIDEO_DIAS:-21}"
MAX_VIDEOS="${RADAR_VIDEO_MAX:-8}"
POR_PESQUISA="${RADAR_VIDEO_POR_PESQUISA:-2}"
WORK=/tmp/radar-videos-work-$$
UA="bora-batedor-radar-ia/1.0"
CORTE_TS=$(date -u -d "$DIAS days ago" +%s)
CORTE_YMD=$(date -u -d "$DIAS days ago" +%Y%m%d)
N_LEGENDAS=0
N_DESCRICOES=0
TOTAL=0
VISTOS=""

rm -rf "$WORK"; mkdir -p "$WORK"
trap 'rm -rf "$WORK"' EXIT

# Instancias Invidious: PESQUISAR o YouTube e ler titulo/canal/data/descricao.
# Escolhe-se a primeira que responder de facto (nao basta o 200 — tem de vir array com itens).
INVIDIOUS=""
for I in https://invidious.nikkosphere.com https://inv.nadeko.net https://invidious.privacyredirect.com https://iv.ggtyler.dev https://yewtu.be; do
  N=$(timeout 30 curl -s -m 25 -A "$UA" "$I/api/v1/search?q=teste&type=video" 2>/dev/null | jq -r 'if type=="array" then length else 0 end' 2>/dev/null)
  if [ "${N:-0}" -ge 1 ] 2>/dev/null; then INVIDIOUS="$I"; break; fi
done

echo
echo "== FONTE 3: VIDEOS NO YOUTUBE (novidades de IA, ultimos $DIAS dias, maximo $MAX_VIDEOS) =="
if [ -z "$INVIDIOUS" ]; then
  echo "(nenhuma instancia de pesquisa respondeu — sem videos nesta corrida)"
  echo "(videos recolhidos: 0)"
  exit 0
fi
echo "(pesquisa feita por: $INVIDIOUS)"
echo

while IFS= read -r Q; do
  [ -z "$Q" ] && continue
  [ "$TOTAL" -ge "$MAX_VIDEOS" ] && break
  LINHAS=$(timeout 45 curl -s -m 40 -A "$UA" --get "$INVIDIOUS/api/v1/search" \
             --data-urlencode "q=$Q" --data-urlencode "type=video" \
             --data-urlencode "sort_by=upload_date" 2>/dev/null \
           | jq -r --argjson corte "$CORTE_TS" \
               'if type=="array" then (.[] | select((.published // 0) >= $corte) | select((.lengthSeconds // 0) > 60 and (.lengthSeconds // 0) < 5400) | "\(.videoId)\t\(.published)\t\(.author)\t\(.title)") else empty end' \
               2>/dev/null | head -"$POR_PESQUISA")
  [ -z "$LINHAS" ] && continue
  echo "-- pesquisa: $Q"
  while IFS=$'\t' read -r VID PUB AUT TIT; do
    [ -z "${VID:-}" ] && continue
    [ "$TOTAL" -ge "$MAX_VIDEOS" ] && break
    case " $VISTOS " in *" $VID "*) continue ;; esac
    VISTOS="$VISTOS $VID"
    TOTAL=$((TOTAL+1))
    DATA=$(date -u -d "@$PUB" +%F 2>/dev/null || echo "?")
    echo "VIDEO $TOTAL | $DATA | $AUT | $TIT"
    echo "link: https://www.youtube.com/watch?v=$VID"

    # VIA 1 — legenda automatica pelo yt-dlp (pt ou en).
    CORPO=""
    ORIGEM=""
    rm -f "$WORK"/*.vtt 2>/dev/null
    COOK=""
    [ -n "${YT_COOKIES:-}" ] && [ -f "${YT_COOKIES:-}" ] && COOK="--cookies ${YT_COOKIES}"
    timeout 120 "$YTDLP" --no-warnings --ignore-errors --no-progress $COOK \
      --dateafter "$CORTE_YMD" \
      --write-auto-sub --write-sub --sub-langs "pt.*,en.*" --sub-format vtt --skip-download \
      -o "$WORK/%(id)s" "https://www.youtube.com/watch?v=$VID" \
      > "$WORK/ytdlp.out" 2>&1
    VTT=$(ls "$WORK"/*.vtt 2>/dev/null | head -1)
    if [ -n "$VTT" ] && [ -s "$VTT" ]; then
      CORPO=$(sed -e '/-->/d' -e '/^WEBVTT/d' -e '/^Kind:/d' -e '/^Language:/d' -e 's/<[^>]*>//g' "$VTT" \
              | tr -s ' \n' ' \n' | awk 'NF && $0!=prev {print; prev=$0}' | tr '\n' ' ' | head -c 4000)
    fi
    if [ -n "$CORPO" ]; then
      ORIGEM="LEGENDA (transcricao automatica do proprio video)"
      N_LEGENDAS=$((N_LEGENDAS+1))
    else
      # VIA 2 — descricao completa. Marcada como tal, nunca como legenda.
      CORPO=$(timeout 45 curl -s -m 40 -A "$UA" "$INVIDIOUS/api/v1/videos/$VID" 2>/dev/null \
              | jq -r '.description // ""' 2>/dev/null | tr -s ' \n' ' \n' | tr '\n' ' ' | head -c 2000)
      if [ -n "$CORPO" ]; then
        ORIGEM="DESCRICAO do video (SEM legenda: o YouTube bloqueou a transcricao a partir deste servidor)"
        N_DESCRICOES=$((N_DESCRICOES+1))
      else
        ORIGEM="SO O TITULO (nem legenda nem descricao)"
      fi
    fi
    echo "origem do texto: $ORIGEM"
    echo "texto: $CORPO"
    echo
  done <<< "$LINHAS"
  sleep 2
done <<'QUERIES'
Claude Code novidades
agentes de IA ferramentas novas
Supabase novidades
Flutter novidades
Gemini API novidades
IA para pequenos negócios
QUERIES
echo "(videos recolhidos: $TOTAL — com legenda: $N_LEGENDAS, so com descricao: $N_DESCRICOES)"
exit 0
