#!/usr/bin/env bash
# vigia_processos.sh — mata processos ORFAOS dos agentes com mais de 2 horas (missao hermes-diretor-2026-11-20, B1.3).
# Porque: a 15/11 ficou um vitest a correr 11 horas dentro do perfil fiscal e a VPS (1 processador) ficou de joelhos.
# Sem IA. Corre no HOST, de 15 em 15 minutos. So toca em processos DENTRO do contentor do Hermes que sejam
# testes, instaladores ou navegadores sem cabeca; nunca no gateway, na ponte, nem nos servicos do host.
#   vigia_processos.sh            mata e avisa
#   vigia_processos.sh --ensaio   so mostra o que mataria
C=hermes-agent-fvnc-hermes-agent-1
LIMITE=7200
LOG=/var/log/vigia-processos.log
PADRAO='vitest|jest|playwright|chrome-headless-shell|(chrom(e|ium)).*--headless|pnpm (test|install|exec|dlx)|npm (test|ci|install|exec)|npx |esbuild --service|tsx |pytest|flutter (test|analyze|build)'
NUNCA='gateway run|tailscaled|hermes dashboard|s6-|/opt/data/voz|porta\.py'
ENSAIO=0; [ "${1:-}" = "--ensaio" ] && ENSAIO=1
ts(){ date -u +%FT%TZ; }
docker ps --format '{{.Names}}' | grep -q "^$C$" || exit 0

achados=$(docker top "$C" -eo pid,etimes,args 2>/dev/null | awk -v l="$LIMITE" 'NR>1 && $2+0 > l' | grep -E "$PADRAO" | grep -vE "$NUNCA")
[ -z "$achados" ] && { [ "$ENSAIO" = 1 ] && echo "nenhum processo orfao com mais de 2 horas"; exit 0; }

n=0; resumo=""
while read -r pid seg resto; do
  [ -z "$pid" ] && continue
  n=$((n+1)); horas=$((seg/3600))
  resumo="$resumo ${horas}h: $(echo "$resto" | cut -c1-70);"
  if [ "$ENSAIO" = 1 ]; then echo "(ensaio) mataria $pid (${horas} h): $(echo "$resto" | cut -c1-120)"; continue; fi
  echo "$(ts) a parar $pid (${seg}s): $(echo "$resto" | cut -c1-160)" >> "$LOG"
  kill -TERM "$pid" 2>/dev/null
done <<< "$achados"
[ "$ENSAIO" = 1 ] && exit 0
sleep 8
while read -r pid seg resto; do [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null && { kill -KILL "$pid" 2>/dev/null; echo "$(ts) $pid nao saiu a bem: morto a forca" >> "$LOG"; }; done <<< "$achados"
# aviso pelo porteiro (vai para os bastidores e para o resumo; nao acorda o Danilo)
python3 - "$n" "$resumo" <<'PY' >/dev/null 2>&1
import json, sys, urllib.request
texto = "Vigia do servidor: parei %s processo(s) presos ha mais de 2 horas nos agentes.%s" % (sys.argv[1], sys.argv[2][:400])
req = urllib.request.Request("http://127.0.0.1:8796/telegram_danilo", data=json.dumps({"texto": texto, "nivel": "INFO", "origem": "vigia-processos"}).encode(), headers={"Content-Type": "application/json"})
urllib.request.urlopen(req, timeout=20).read()
PY
exit 0
