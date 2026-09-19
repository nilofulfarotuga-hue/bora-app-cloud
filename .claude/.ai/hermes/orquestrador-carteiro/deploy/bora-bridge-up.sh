#!/usr/bin/env bash
# Reativa a ligacao Tailscale do container do Hermes ao PC do Danilo.
# Estado em /opt/data/tailscale (volume) -> sobrevive a recreate da imagem.
# Idempotente: so age se o tailscale estiver em baixo.
# Cópia VERSIONADA do master do host /root/bora-bridge-up.sh (deploy manifesto: ver DEPLOY.md).
set -e
C=hermes-agent-fvnc-hermes-agent-1
STATE=/opt/data/tailscale/tailscaled.state

echo "[bridge-up] container: $C"
# Migracao unica: se o estado novo (volume) nao existe mas o antigo existe, copia.
docker exec "$C" sh -lc "mkdir -p /opt/data/tailscale; if [ ! -f $STATE ] && [ -f /var/lib/tailscale/tailscaled.state ]; then cp -a /var/lib/tailscale/tailscaled.state $STATE && echo '[bridge-up] estado tailscale migrado para o volume'; fi" || true

# Instalar comandos da ponte (pc + shim do claude) a partir do volume -> persistente a recreate
docker exec "$C" sh -lc 'if [ -f /opt/data/pc ]; then cp -f /opt/data/pc /usr/local/bin/pc; chmod +x /usr/local/bin/pc; fi; if [ -f /opt/data/readpage ]; then cp -f /opt/data/readpage /usr/local/bin/readpage; chmod +x /usr/local/bin/readpage; fi; if [ -f /opt/data/websearch ]; then cp -f /opt/data/websearch /usr/local/bin/websearch; chmod +x /usr/local/bin/websearch; fi; if [ -f /opt/data/vault ]; then cp -f /opt/data/vault /usr/local/bin/vault; chmod +x /usr/local/bin/vault; fi; if [ -f /opt/data/browse ]; then cp -f /opt/data/browse /usr/local/bin/browse; chmod +x /usr/local/bin/browse; fi; if [ -f /opt/data/vps_render ]; then cp -f /opt/data/vps_render /usr/local/bin/vps_render; chmod +x /usr/local/bin/vps_render; fi; if [ -f /opt/data/claude-shim ]; then rm -f /usr/local/bin/claude; cp /opt/data/claude-shim /usr/local/bin/claude; chmod +x /usr/local/bin/claude; fi' || true
echo "[bridge-up] comandos pc + claude-shim instalados"

# Garantir chromium (para o vps_render / browse via VPS) — reinstala apos recreate
docker exec "$C" sh -lc 'command -v chromium >/dev/null 2>&1 || { apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq chromium >/dev/null 2>&1; }' || true

# Garantir tailscale (binario) -- a identidade (chaves do node) fica no volume
# /opt/data/tailscale e sobrevive a recreate, mas o BINARIO tailscale/tailscaled so
# vive na camada gravavel do container -- um recreate (docker compose up -d) apaga-o.
# Reinstala se faltar, mesmo padrao idempotente do chromium acima.
docker exec "$C" sh -lc 'command -v tailscaled >/dev/null 2>&1 || curl -fsSL https://tailscale.com/install.sh | sh >/dev/null 2>&1' || true

# Garantir STT local (faster-whisper) -- o .venv e root-owned (parte da imagem),
# so root consegue instalar aqui (mesma razao do voice-guard usar -u root pro edge-tts).
# Ja partiu 2x por recreate (28/06, 05/07). Reinstala se faltar.
docker exec "$C" sh -lc '/opt/hermes/.venv/bin/python3 -c "import faster_whisper" >/dev/null 2>&1 || { VIRTUAL_ENV=/opt/hermes/.venv /usr/local/bin/uv pip install --python /opt/hermes/.venv/bin/python3 "faster-whisper==1.2.1" "sounddevice==0.5.5" "numpy==2.4.3" >/dev/null 2>&1; apt-get update -qq && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq libportaudio2 >/dev/null 2>&1; }' || true
# O modelo faster-whisper fica em cache no volume /opt/data/.cache/huggingface (sobrevive
# a recreate); corrige ownership caso algum passo root tenha escrito la.
docker exec "$C" sh -lc 'chown -R hermes:hermes /opt/data/.cache 2>/dev/null' || true

if docker exec "$C" sh -lc 'tailscale status >/dev/null 2>&1'; then
  echo "[bridge-up] tailscaled JA esta a correr."
else
  echo "[bridge-up] a arrancar tailscaled (userspace, estado no volume)..."
  docker exec "$C" sh -lc 'rm -f /var/run/tailscale/tailscaled.sock' || true
  docker exec -d "$C" tailscaled \
    --tun=userspace-networking \
    --socket=/var/run/tailscale/tailscaled.sock \
    --state=/opt/data/tailscale/tailscaled.state
  sleep 5
  docker exec "$C" sh -lc 'tailscale up --hostname=bora-vps --ssh --timeout=30s' || true
  sleep 2
fi

echo "[bridge-up] status:"
docker exec "$C" sh -lc 'tailscale status | head -5'
echo "[bridge-up] teste ao PC:"
docker exec "$C" sh -lc 'ssh -o BatchMode=yes -o StrictHostKeyChecking=accept-new -o ConnectTimeout=20 bora-pc "whoami" 2>&1' \
  && echo "[bridge-up] PONTE OK" || echo "[bridge-up] FALHOU a chegar ao PC"

# Agent-Reach (canais keyless youtube/web/rss) — venv persistente em /opt/data/agent-reach-venv
docker exec "$C" sh -lc 'if [ -x /opt/data/agent-reach-venv/bin/agent-reach ]; then cp -f /opt/data/agent-reach /usr/local/bin/agent-reach; chmod +x /usr/local/bin/agent-reach; ln -sf /opt/data/agent-reach-venv/bin/yt-dlp /usr/local/bin/yt-dlp; echo "[bridge-up] agent-reach + yt-dlp instalados"; fi' || true
echo "[bridge-up] agent-reach pronto (youtube/web/rss keyless)"

# ── [cortex] re-garantir espelho do Córtex + comando cortex (padrão do fix tailscale) ──
docker exec -u root "$C" sh -lc 'command -v git >/dev/null 2>&1 || (apt-get update -qq && apt-get install -y -qq git) >/dev/null 2>&1' || true
docker exec -u hermes -e HOME=/opt/data "$C" sh -lc '[ -d /opt/data/cortex-brain/.git ] || GIT_SSH_COMMAND="ssh -i /opt/data/.secrets/cortex_deploy_ed25519 -o IdentitiesOnly=yes -o UserKnownHostsFile=/opt/data/.secrets/known_hosts -o StrictHostKeyChecking=yes" git clone --depth 1 -b autonomous-night-2026-04-29 git@github.com:nilofulfarotuga-hue/bora-app-cloud.git /opt/data/cortex-brain && echo "[bridge-up] espelho cortex-brain recriado"' || true
docker exec -u root "$C" sh -lc '[ -x /usr/local/bin/cortex ] || { cp /opt/data/bin/cortex /usr/local/bin/cortex && chmod 755 /usr/local/bin/cortex && echo "[bridge-up] comando cortex reinstalado"; }' || true

# ── [concierge] re-garantir comandos estado+ordem (Fase 6 2026-07-10) ──
docker exec -u root "$C" sh -lc "for b in estado ordem; do [ -x /usr/local/bin/\$b ] || { cp /opt/data/bin/\$b /usr/local/bin/\$b && chmod 755 /usr/local/bin/\$b && echo \"[bridge-up] comando \$b reinstalado\"; }; done" || true

# ── [cortex-sync] re-garantir o SYNC POR-TAREFA do espelho após recreate (2026-07-10) ──
# O espelho é editado localmente pelo carteiro (fila orquestracao/) e refrescado a CADA ordem
# em modo fast (merge --ff-only). Um recreate pode deixar o remote em https/PAT; força SSH deploy
# key (NUNCA PAT) para que o pull por-tarefa continue a autenticar. Idempotente.
docker exec -u hermes -e HOME=/opt/data "$C" sh -lc '
  [ -d /opt/data/cortex-brain/.git ] || exit 0
  git -C /opt/data/cortex-brain remote set-url origin git@github.com:nilofulfarotuga-hue/bora-app-cloud.git
  git config --global --get-all safe.directory | grep -qx /opt/data/cortex-brain \
    || git config --global --add safe.directory /opt/data/cortex-brain
  echo "[bridge-up] sync por-tarefa do espelho re-garantido (remote SSH deploy key)"
' || true
