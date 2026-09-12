#!/bin/sh
# atualizar-bin-hermes.sh -- substitui um executavel em /opt/data/.local/bin GUARDANDO a versao
# anterior, e verifica o resultado por hash.
#
# Porque existe (limitacao L1, Parte 3 da missao sistema-redondo-2026-08-01):
#   /opt/data/.local/bin e' root:root drwxr-xr-x, mas os ficheiros la dentro sao hermes:hermes.
#   Consequencia provada a 2026-08-01 de dentro do container:
#     - criar ficheiro NOVO em bin/      -> Permission denied  (precisa de escrita NA PASTA)
#     - sobrescrever ficheiro EXISTENTE  -> OK                 (o hermes e' dono do ficheiro)
#   Ou seja: nao da' para escrever o backup ao lado do original. A versao anterior tem de ir
#   para outro sitio. /opt/data/.local E' hermes:hermes, logo o hermes pode criar pastas la ->
#   /opt/data/.local/bin-versoes/ e' o sitio.
#
# Uso (dentro do container, como hermes):
#   sh atualizar-bin-hermes.sh pc-loop /tmp/pc-loop.novo
#   sh atualizar-bin-hermes.sh pc-judge /tmp/pc-judge.novo
#
# Do host:
#   docker exec -i -u hermes hermes-agent-fvnc-hermes-agent-1 sh -s pc-loop /tmp/novo < este.sh
set -eu

BIN=/opt/data/.local/bin
VERSOES=/opt/data/.local/bin-versoes

nome="${1:?uso: $0 <nome-do-executavel> <ficheiro-novo>}"
novo="${2:?uso: $0 <nome-do-executavel> <ficheiro-novo>}"
alvo="$BIN/$nome"

[ -f "$novo" ] || { echo "!! ficheiro novo nao existe: $novo"; exit 1; }
[ -f "$alvo" ] || { echo "!! $alvo nao existe -- e NAO da' para o criar (L1: a pasta e' root:root)."; \
                    echo "   Um executavel NOVO tem de ser criado pelo root no host:"; \
                    echo "   docker exec -u root <container> sh -c 'install -o hermes -g hermes -m 755 /dev/null $alvo'"; exit 1; }

mkdir -p "$VERSOES"
ts=$(date -u +%Y%m%dT%H%M%SZ)
cp -p "$alvo" "$VERSOES/$nome.$ts"
echo "versao anterior guardada em $VERSOES/$nome.$ts ($(sha256sum "$VERSOES/$nome.$ts" | cut -c1-12))"

# sobrescrever o conteudo SEM apagar/recriar o ficheiro (apagar exigiria escrita na pasta).
cat "$novo" > "$alvo"
chmod 755 "$alvo" 2>/dev/null || true

h_novo=$(sha256sum "$novo" | cut -d' ' -f1)
h_alvo=$(sha256sum "$alvo" | cut -d' ' -f1)
if [ "$h_novo" = "$h_alvo" ]; then
  echo "OK: $alvo actualizado ($(echo "$h_alvo" | cut -c1-12))"
else
  echo "!! FALHOU: o conteudo no destino nao bate certo com a origem"
  echo "   origem=$h_novo destino=$h_alvo"
  echo "   repor com: cat $VERSOES/$nome.$ts > $alvo"
  exit 1
fi
