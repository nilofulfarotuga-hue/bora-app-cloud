# CÓRTEX — Escrita autónoma LIGADA (deploy key + write ON)

> Sessão Claude Code (Opus 4.8) · 2026-07-08 · Branch `autonomous-night-2026-04-29`.
> Danilo confirmou no GitHub: deploy key `cortex-deploy-2026-07-08` com *Allow write* ✅ · PAT `hermes-bora` **DELETADO** ✅.
> Zona verde. Aditivo e reversível (voltar a `CORTEX_WRITE_ENABLED=false` reverte).

## ✅ 1 — Remotes trocados para a deploy key (SSH)
- **VPS (3 clones):** `bora-app-cloud`, `bora-work`, `cortex-brain` → `git@github.com:nilofulfarotuga-hue/bora-app-cloud.git`, cada um com `core.sshCommand` a apontar `/opt/data/.secrets/cortex_deploy_ed25519` (`IdentitiesOnly=yes`, host key do GitHub **pinada** em `.secrets/known_hosts`, `StrictHostKeyChecking=yes`). `credential.helper` removido.
- **Auth confirmada:** `Hi nilofulfarotuga-hue/bora-app-cloud! You've successfully authenticated`. `git fetch` OK nos 3.
- **PC:** **não usa** o PAT (usa Windows Credential Manager, `https://…` limpo) → nada a mudar.

## ✅ 2 — Varredura do PAT antigo: limpo
- `git-credentials` (o store 600 com o PAT já revogado) **apagado**.
- Varredura em `.env`, `*/.git/config`, `.bash_history`, `.secrets` → **`RESIDUO_PAT=0`**. Nenhum resíduo.

## ✅ 3 + 4 — Escrita ligada + teste ponta-a-ponta (via HTTPS público)
`CORTEX_WRITE_ENABLED=true` + `CORTEX_GIT_PUSH=true` no `cortex-mcp` (redeploy). Health: `{"write_enabled":true,"oauth":true}`.

| Teste | Resultado |
|---|---|
| **GREEN** `cortex_escrever` (`cortex-selftest`, zona verde) | `{"written":true,"pushed":true}` → commit **`285f0e9`** confirmado no GitHub (`local=origin`), push **via deploy key** |
| **RED conteúdo** (`stripe refund pricing…`) | `{"refused":"ZONA VERMELHA — recusado no servidor","redirect":"cortex_propor"}` |
| **RED página real** (`decisoes`, `zona:vermelha`) | `refused` + `redirect: cortex_propor` (dupla trava: zona + conteúdo) |

**2 bugs encontrados e corrigidos durante o teste (aditivo):**
1. `cortex-mcp` (alpine) **não tinha `ssh`** → `git push` SSH falhava. Fix: `openssh-client` no Dockerfile + mount `.secrets:ro` no container.
2. Container corre `--user 10000` sem entrada em `/etc/passwd` → `ssh` abortava com *"No user exists for uid 10000"*. Fix: entrada `passwd` para uid 10000 + `HOME=/tmp` no Dockerfile.

## ✅ 5 — Hermes usa a MESMA deploy key
O push de teste do lado do Hermes (host, container `hermes`) passou pela deploy key: commit **`f7e10c8`** (`07a0355..f7e10c8`). Os 3 clones do Hermes partilham o mesmo `core.sshCommand` → todos os pushes do Hermes usam a deploy key, **nunca** um PAT à parte.

## ⚠️ Riscos / notas
- **`passwd` uid 10000 fixado no image** — casa com o dono do brain (`OWN=10000:10000`). Se algum dia o uid do volume mudar, ajustar o Dockerfile.
- **claude.ai (OAuth)** — a ponte web só fica confirmada quando adicionares o conector (`https://cortex.srv1786862.hstgr.cloud`) e clicares *Autorizar*. Independente disto; a escrita local/API já funciona.
- **Página `inbox/cortex-selftest.md`** fica no brain como evidência — é transitória (o `cortex_nightly` trata inbox >14d). Podes ignorar.
- **Dois escritores na mesma branch** (o teu PC + o brain do VPS) — o `cortex_nightly`/refresh faz `reset --hard origin` às 06:30, por isso o brain segue sempre o origin; ok. Se editares à mão a branch, faz `git pull` antes.
- 🔴 **Zona do banco continua PARAR-e-PROPOR** — não mudou nada disso.

## Estado final
- `cortex-mcp` v1.1 **write ON**, non-root uid 10000, ssh+deploy key, OAuth+token, HTTPS.
- Origin @ `285f0e9` (inclui os 2 commits de selftest). PAT morto e sem rasto.
