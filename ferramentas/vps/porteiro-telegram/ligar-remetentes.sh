#!/usr/bin/env bash
# Bloco 6 (retoma-geral-2026-10-31): todos os remetentes da VPS passam pelo porteiro.
#  (a) quem falava com a API do bot: o endereco base passa a ser o espelho do porteiro (http://172.16.1.1:8796/o/<origem>/bot)
#  (b) quem usava `hermes send -t telegram`: passa a usar porteiro_cli.py send (mesmo formato)
#  (c) audio-add.sh deixa de pedir voz (a voz e do porteiro)
# Copia de cada ficheiro antes de mexer: <ficheiro>.bak-31-10. So mexe se o padrao existir. Prova a sintaxe no fim.
set -u
D=/docker/hermes-agent-fvnc/data
API_FILES="
$D/scripts/enviar-video-telegram.sh
$D/scripts/gritar.sh
$D/scripts/prova_do_dia.sh
$D/scripts/social-carrossel.sh
$D/scripts/social-grupos-plano.sh
$D/scripts/social-grupos-resumo.sh
$D/scripts/social-reavaliacao.sh
$D/social/ig_auto_dm.py
$D/social/resumo_do_dia.py
/opt/assistente-negocio/rotinas.py
/root/aviso2.py
/root/claude-token-watchdog.sh
/root/em-dia-telegram.sh
/root/ipg-envio/enviar-video-telegram.sh
/root/radar-jai/radar/comum.py
/root/whatsapp-bora/vigia_porta.py
/root/whatsapp-bora/ligar.js
/usr/local/bin/hermes-gateway-watchdog.sh
/usr/local/bin/hermes-heartbeat.sh
/usr/local/bin/hermes-meta-token-vigia.sh
/usr/local/bin/hermes-notificar-rotina.sh
/usr/local/bin/hermes-sonda-auth.sh
/usr/local/bin/hermes-voz-guarda.sh
"
SEND_FILES="
$D/scripts/social-medir.sh
$D/scripts/publicar_cartaz.sh
$D/scripts/radar-ia.sh
$D/scripts/social-loja-do-dia.sh
$D/scripts/social-story.sh
$D/scripts/radar-dinheiro.sh
$D/scripts/social-bora.sh
$D/scripts/social-reel.sh
/usr/local/bin/hermes-carteiro-vigia.sh
/usr/local/bin/hermes-watchdog.sh
/usr/local/bin/hermes-hook-conclusao.sh
/usr/local/bin/hermes-relatorio-semanal.sh
/root/orquestracao/carteiro.sh
/root/orquestracao/bom-dia.sh
"
bak() { [ -f "$1.bak-31-10" ] || cp -p "$1" "$1.bak-31-10"; }
sintaxe() {
  case "$1" in
    *.sh) bash -n "$1" 2>&1 && echo ok ;;
    *.py) python3 -m py_compile "$1" 2>&1 && echo ok ;;
    *.js) node --check "$1" 2>&1 && echo ok ;;
    *) echo "?" ;;
  esac
}
echo "== (a) espelho da API"
for f in $API_FILES; do
  [ -f "$f" ] || { echo "FALTA $f"; continue; }
  o=$(basename "$f"); o=${o%.*}
  [ "$f" = "/root/ipg-envio/enviar-video-telegram.sh" ] && o=ipg-enviar-video
  [ "$f" = "/root/radar-jai/radar/comum.py" ] && o=radar-jai
  [ "$f" = "/opt/assistente-negocio/rotinas.py" ] && o=assistente-rotinas
  n=$(grep -c "https://api.telegram.org/bot" "$f")
  if [ "$n" -gt 0 ]; then
    bak "$f"
    sed -i "s#https://api.telegram.org/bot#http://172.16.1.1:8796/o/$o/bot#g" "$f"
  fi
  echo "$n troca(s) | $(grep -c "172.16.1.1:8796/o/" "$f") no espelho | sintaxe $(sintaxe "$f") | $f"
done
echo "== (b) hermes send"
for f in $SEND_FILES; do
  [ -f "$f" ] || { echo "FALTA $f"; continue; }
  n=$(grep -c -E "hermes send -t telegram" "$f")
  if [ "$n" -gt 0 ]; then
    bak "$f"
    sed -i -E 's#docker exec -u hermes (-e [A-Z_]+=[^ ]+ )?"?\$\{?C\}?"? hermes send -t telegram#python3 /opt/data/voz/porteiro_cli.py send -t telegram#g; s#(^|[^/_a-z])hermes send -t telegram#\1python3 /opt/data/voz/porteiro_cli.py send -t telegram#g' "$f"
  fi
  echo "$n troca(s) | resta hermes-send=$(grep -c -E '(^|[^_a-z/])hermes send -t telegram' "$f") | porteiro_cli=$(grep -c porteiro_cli.py "$f") | sintaxe $(sintaxe "$f") | $f"
done
echo "== (c) audio-add.sh"
cp -p /tmp/porteiro-inst/audio-add.sh /tmp/aa.sh && sed -i 's/\r$//' /tmp/aa.sh && install -o root -g root -m 755 /tmp/aa.sh $D/voz/audio-add.sh && bash -n $D/voz/audio-add.sh && echo "audio-add.sh: agora nao faz nada (copia em audio-add.sh.bak-31-10)"
