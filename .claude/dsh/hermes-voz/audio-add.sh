#!/usr/bin/env bash
# audio-add.sh — deixa na fila de voz o AUDIO de uma mensagem que um script ja mandou por escrito ao Danilo.
# Regra do Danilo (30/10/2026): tudo o que o Hermes lhe manda chega em texto completo E em audio do texto inteiro.
# Funciona dentro do contentor e no host (so bash + python3 da biblioteca padrao). NUNCA faz o script que o chama falhar
# nem esperar: so escreve um ficheiro na fila; o trabalhador do host (voz.py --worker, cron de minuto a minuto) faz o resto.
#
# Uso:  audio-add.sh "texto"          ou          audio-add.sh -f ficheiro.txt
#       AUDIO_CHAT=123 audio-add.sh "texto"       (outro chat; por omissao TELEGRAM_HOME_CHANNEL)
set +e
FILA=/opt/data/voz/fila
if [ "$1" = "-f" ]; then TEXTO=$(cat "$2" 2>/dev/null); else TEXTO="$*"; fi
[ -z "$TEXTO" ] && exit 0
CH="${AUDIO_CHAT:-${TELEGRAM_HOME_CHANNEL:-}}"
if [ -z "$CH" ]; then
  CH=$(grep -m1 '^TELEGRAM_HOME_CHANNEL=' /opt/data/social/.aviso.conf 2>/dev/null | cut -d= -f2- | tr -d "\"'\r")
fi
[ -z "$CH" ] && CH=6731890157
mkdir -p "$FILA" 2>/dev/null; chmod 777 "$FILA" 2>/dev/null
[ "$(ls "$FILA"/*.job 2>/dev/null | wc -l)" -ge 15 ] && exit 0
N="$FILA/$(date +%s%3N)-$RANDOM.job"
python3 -c 'import json,sys; json.dump({"chat":sys.argv[2],"texto":sys.argv[3],"origem":"script"}, open(sys.argv[1],"w",encoding="utf-8"), ensure_ascii=False)' "$N" "$CH" "$TEXTO" 2>/dev/null
chmod 666 "$N" 2>/dev/null
exit 0
