#!/bin/bash
# Monta os vídeos pedidos (ou todos), envia-os para a VPS e corre o fiscal_video.py completo.
# Uso: bash render_e_fiscal.sh [nome ...]   (sem nomes = os 7)
cd "$(dirname "$0")"
NOMES=${@:-v1-fastfood-pago v1-fastfood-organico v2-mercado-pago v2-mercado-organico v3-goola v4-sabores v5-lavagem}
K=~/.ssh/id_ed25519_vps; H=root@srv1786862.hstgr.cloud; C=hermes-agent-fvnc-hermes-agent-1
for n in $NOMES; do
  for t in 1 2; do  # 2.a tentativa: a 1.a pode falhar por falta de memória no PC
    python montar_ipg.py planos/$n.json saidas/$n.mp4 2>&1 | grep -q "^ok" && break
  done
  ffmpeg -v error -y -i saidas/$n.mp4 -vf "fps=1.3,scale=216:-1,tile=11x2" -frames:v 1 saidas/$n-grelha.jpg
  scp -q -i $K saidas/$n.mp4 $H:/tmp/ipg/
done
ssh -o BatchMode=yes -i $K $H "for n in $NOMES; do docker cp /tmp/ipg/\$n.mp4 $C:/opt/data/social/tmp/ipg/; done; \
  docker exec -u hermes $C bash -lc 'set -a; . /opt/data/.env; set +a; cd /opt/data/social; \
  for n in $NOMES; do echo \"=== \$n\"; timeout 420 ./venv/bin/python fiscal_video.py --peca tmp/ipg/\$n.mp4 2>&1 | grep -E \"^(MAQUINA|OLHO|APROVADO|REPROVADO|chumbo|CHUMBO)\"; done'" 2>&1 | tee saidas/fiscal-$(date +%H%M).log
