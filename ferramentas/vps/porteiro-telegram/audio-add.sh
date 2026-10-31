#!/usr/bin/env bash
# audio-add.sh — DESDE 31/10/2026 (missao retoma-geral-2026-10-31, bloco 6) NAO FAZ NADA.
# A voz de tudo o que chega ao Danilo passou a ser do PORTEIRO (/opt/data/voz/porteiro.py): ele poe a voz no que vai
# para o chat e NAO a poe no que fica nos bastidores. Se este script continuasse a pedir audio, o ruido que o porteiro
# segura (INFO) voltava a chegar ao Danilo em forma de voz, e o que ele recebe ia em voz duas vezes.
# Copia do comportamento antigo: /opt/data/voz/audio-add.sh.bak-31-10
# Nunca faz o script que o chama falhar nem esperar.
echo "$(date -u +%FT%TZ) ignorado (a voz e do porteiro): $(printf '%s' "${2:-$1}" | head -c 80 | tr '\n' ' ')" >> /opt/data/voz/porteiro/audio-add-ignorado.log 2>/dev/null
exit 0
