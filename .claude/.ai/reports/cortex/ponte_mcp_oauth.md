# CÓRTEX — Fechar a ponte: rotação PAT + OAuth 2.1

> Sessão Claude Code (Opus 4.8) · 2026-07-08 · Branch `autonomous-night-2026-04-29`.
> **Zona verde** (infra/Córtex; nunca DB/dinheiro/RLS → zero paragens 🔴). Aditivo e reversível.

## 🔴 PARTE 1 — PAT exposto: hardening feito, **revogação pende de ti** (é a tua conta)
**O que eu consegui fazer autónomo (sem a tua conta GitHub):**
- ✅ **PAT retirado dos 3 `.git/config`** das clones do VPS (`bora-app-cloud`, `bora-work`, `cortex-brain`). Confirmado: `grep github_pat → NENHUM (limpo)`.
- ✅ Movido para um **credential store 600** (`/opt/data/.secrets/git-credentials`) — `git remote -v` já não mostra token; `git fetch` continua a funcionar (`FETCH_OK`).
- ✅ **Deploy key** SSH dedicada gerada (`/opt/data/.secrets/cortex_deploy_ed25519`).

**Porque não revoguei sozinho:** revogar/rotacionar um PAT exige login na **tua conta GitHub**. O `gh` do PC **não está autenticado** e não tenho token de admin. É a tua autorização de conta.

**🖥️ OS TEUS 2 PASSOS (2 min) para fechar a rotação:**
1. **Adicionar a deploy key** em `https://github.com/nilofulfarotuga-hue/bora-app-cloud/settings/keys/new` (marca *Allow write access*), colando:
   `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIE7OUvdSJ6QoQ+UvwaI53wQI8KxAQebSXnZsTAU9K7DZ cortex-deploy-2026-07-08`
   *(depois disto eu troco as remotes para SSH e o PAT deixa de ser necessário.)*
2. **Revogar o PAT antigo** em `https://github.com/settings/tokens` (o token `github_pat_11B7BD…` — está exposto, revoga já).
- **Varredura de segredos:** só os 3 `.git/config` tinham o PAT (agora limpos). `.env`/logs — sem `ghp_`/`github_pat`/`AKIA`/`xoxb`. Nada mais encontrado.

## ✅ PARTE 2 — OAuth 2.1 no servidor MCP (self-tested end-to-end)
Servidor `cortex-mcp` v1.1 LIVE em `https://cortex.srv1786862.hstgr.cloud`. Fluxo OAuth 2.1 **testado ponta-a-ponta**:
| Passo | Resultado |
|---|---|
| `/.well-known/oauth-authorization-server` + `/.well-known/oauth-protected-resource` | ✅ metadata correta |
| `/register` (Dynamic Client Registration) | ✅ `client_id` emitido (claude.ai regista-se sozinho) |
| `/authorize` (code + PKCE S256, auto-consent single-user) | ✅ 302 com `code` + `state` preservado |
| `/token` (authorization_code + refresh_token) | ✅ `access_token` emitido |
| MCP `tools/list` com token OAuth | ✅ 6 ferramentas |
| PKCE errado | ✅ **`invalid_grant`** (rejeita) |
- **Token estático mantido em paralelo** (Claude Desktop/API). **Travas intactas e confirmadas:** `cortex_escrever` recusa (write off) + zona 🔴 recusada no servidor (`pricing`→vermelha), sem traversal/shell/segredos, rate-limit, log de cada escrita/proposta.
- **HTTPS** letsencrypt · corre **non-root** (uid 10000).
- ⚠️ Só não consigo confirmar a **aceitação pelo claude.ai** — isso precisa de tu adicionares o conector e clicares "autorizar" (Parte 3). É inerente, não é falha.

## 🖥️ PARTE 3 — o teu único clique (adicionar o conector)
claude.ai → **Definições → Conectores → Adicionar conector personalizado** → URL:
**`https://cortex.srv1786862.hstgr.cloud`**
- Com **DCR**, o claude.ai regista-se sozinho — **não precisas de colar Client ID/Secret**. Ao adicionar, abre o consentimento OAuth → clicas **Autorizar** uma vez. Fim.
- Se pedir um "MCP URL" com sufixo, é a mesma raiz (o servidor responde MCP no `/`).
- O token estático (para Claude Desktop/API) continua em `Desktop\cortex_mcp_TOKEN_SEGREDO.txt` — **nunca** no chat.

## ✅ PARTE 4 — Contradiction engine fora do "parcial"
`export_signals.py` (VPS) escreve `inbox/_signals.json` do último pulso: **`cancel_pct=50, crashes=5`** + commits recentes. O `cortex_nightly.py` já cruza (commit × negócio) — deixou de estar "parcial". **0 contradições** esta corrida (correto: nenhum commit recente toca a zona de cancelamento). Cron **07:05** (após refresh 06:30 + pulso 07:00): `export_signals → cortex_nightly`.

## 🚦 PARTE 5 — Escrita autónoma pública: **fica OFF** (de propósito)
Regra tua: só ligar `CORTEX_WRITE_ENABLED=true` com **PAT rotacionado ✅ + OAuth ✅ + travas ✅**.
- OAuth ✅ · travas ✅ · **PAT rotação = INCOMPLETA** (revogação pende de ti, Parte 1). → **Escrita fica DESLIGADA.**
- Assim que fizeres os 2 passos da Parte 1, digo "vai" e ligo a escrita verde (com push via a deploy key, não o PAT).

## ⚠️ Bugs / riscos
- 🔴 **PAT ainda válido até o revogares** (Parte 1, passo 2). Está fora dos configs, mas vivo. Revoga.
- 🟡 **claude.ai aceitar o OAuth** — não verificável sem a tua conta; se rejeitar, é ajuste de metadata (itero).
- 🟡 **OAuth em memória** — tokens/códigos perdem-se se o container reiniciar → re-autenticar (raro; `restart unless-stopped`).
- 🟢 **Repoint Obsidian** ainda por confirmares visualmente (config já criado).

## 📦 Commits / estado VPS
- `<este>` — server.mjs (OAuth 2.1 + DCR + PKCE), deploy.sh (issuer), export_signals.py, cortex_nightly (clareza).
- VPS: container `cortex-mcp` v1.1 (up, non-root, OAuth+token), cron `cortex-mcp-sync` 06:30 + `cortex-nightly` 07:05, deploy key em `.secrets`, PAT movido p/ store 600.
- *(push → origin.)*
