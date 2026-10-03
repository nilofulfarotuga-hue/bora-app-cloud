# CÓRTEX — Ponte MCP (Claude.ai ↔ Hermes) + pendentes fechados

> Sessão Claude Code (Opus 4.8) · 2026-07-08 · Branch `autonomous-night-2026-04-29`.
> **Zona verde** (Córtex/infra; nunca DB/dinheiro/RLS → zero paragens 🔴). Aditivo e reversível.
> **A ponte está LIVE em modo seguro (read/propose; escrita desligada).**

## ✅ A1 — Obsidian repontado (determinístico, sem clique)
Não há automação de **desktop** disponível (só browser) e o Obsidian não tinha `obsidian.json`. Em vez do
clique manual, **criei o config** `%APPDATA%\obsidian\obsidian.json` a apontar para o vault canónico
`…\bora_app\.obsidian-vault` (`open:true`). **Efeito:** na próxima abertura, o Obsidian abre o canónico.
- Obsidian está instalado em `…\Local\Programs\obsidian\Obsidian.exe`. Se estiver **aberto agora**, basta reabrir.
- Mantive o breadcrumb `Desktop\_LEIA_vault_Bora_mudou.txt` (não o apaguei porque não consigo **ver** o ecrã para confirmar; assim que confirmares que abre com as 150 notas, apago).

## ✅ A2 — Aging do inbox corrigido
`cortex_nightly.py` passa a contar a idade **desde a entrada no inbox** (`entrou_inbox` → data do commit
que o trouxe → mtime), não pelo mtime original. Dry-run confirma: **Inbox aging (>14d): 0** (era 9 falsos-velhos).

## ✅ B0 — Cérebro sincronizado no VPS (+ ADR)
Espelho **dedicado** `/opt/data/cortex-brain` (clone raso da branch, @ `7c96df8`) — **não** mexe nas clones
de trabalho do Hermes. Já tem o Córtex real (`inbox/`, `wiki/`, `schema.md`, `_tools/`, `_debt.md`, `log.md`).
Refresca-se sozinho: **cron 06:30** (antes do pulso das 07:00). ADR: `wiki/decisoes/2026-07-08-cortex-fonte-de-verdade-e-ponte-mcp`.

## ✅ B1 — Servidor MCP (LIVE) — `https://cortex.srv1786862.hstgr.cloud`
6 ferramentas, testadas ponta-a-ponta sobre HTTPS público:
| Ferramenta | Teste | Resultado |
|---|---|---|
| `cortex_buscar("pricing")` | leitura do brain | ✅ 19 resultados |
| `cortex_ler/listar/debt` | leitura | ✅ |
| `cortex_escrever` | escrita de página | ✅ **RECUSADA** (write off) |
| `cortex_propor("pricing",…)` | fila do admin | ✅ `pid` gerado + gravado; detetou `zona:"vermelha"` |
- **Trava de zona NO SERVIDOR** (não no prompt): página `zona: vermelha` ou conteúdo com padrões de dinheiro → recusa `cortex_escrever` e manda `cortex_propor`.

## ✅ B2 — Segurança (cada item confirmado)
| Controlo | Estado |
|---|---|
| **Token** (Bearer / x-api-key) | ✅ sem token → **401**, com token → **200** |
| **HTTPS** letsencrypt (traefik) | ✅ cert emitido, servido em `websecure` |
| **Não-root** | ✅ container corre como uid `10000` (dono do brain), não root |
| **Sem segredos/shell** | ✅ só lê `.md` dentro do brain (sem traversal); nunca `.env`/`.secrets`; sem shell arbitrário |
| **Rate limit** | ✅ 60/min/IP (em código) |
| **Dial cauteloso** | ✅ `CORTEX_WRITE_ENABLED=false` por defeito; read/propose live |

## ✅/🟡 B3 — Hermes no mesmo cérebro
Brain partilhado (`/opt/data/cortex-brain`) + cron de refresh → o `cortex_nightly.py` e o Hermes podem operar
sobre o **mesmo** Córtex. 🟡 **Contradiction engine ainda parcial:** falta o daily-pulse exportar
`inbox/_signals.json` (cancel_pct/GMV/crashes) para o cruzamento commits×negócio. Próximo passo pequeno.

## 🖥️ B4 — o passo do Danilo (com uma ressalva honesta)
- **URL:** `https://cortex.srv1786862.hstgr.cloud` · **Token:** no ficheiro local `Desktop\cortex_mcp_TOKEN_SEGREDO.txt` (e em `/root/cortex_mcp_token`, 600) — **nunca** no chat.
- **⚠️ RESSALVA IMPORTANTE:** o conector **web** do claude.ai (Definições → Conectores → Adicionar personalizado)
  normalmente exige **OAuth**, não um bearer estático num header. Este servidor autentica por **token** —
  **funciona já** com clientes MCP que aceitam header (Claude Desktop via config, chamadas API). Para o
  conector **web** do claude.ai falta a camada **OAuth 2.1** (é o próximo bloco de trabalho). Não te mando
  "colar e funciona" quando pode não aceitar — prefiro dizer-te a verdade.

## 🔴 RISCO DE SEGURANÇA ENCONTRADO (fora do scope, mas crítico)
As clones do repo no VPS (`bora-work`, `bora-app-cloud`, e agora `cortex-brain`) têm um **GitHub PAT em
texto puro embutido no URL do `origin`** (visível em `git remote -v`). É uma credencial com escrita ao repo.
**Recomendação forte:** **rotacionar o PAT** no GitHub e passar a usar um *credential helper* / deploy key
em vez de o embutir no URL. Não o reproduzi em lado nenhum; a rotação invalida a exposição.

## ⚠️ Outros bugs/riscos
- 🟡 **Repoint Obsidian** só se confirma quando reabrires a app (não tenho olhos no desktop).
- 🟡 **Escrita autónoma pública** ao repo fica **desligada** de propósito. Para ligar: redeploy com
  `CORTEX_WRITE_ENABLED=true CORTEX_GIT_PUSH=true` — recomendo só **depois** de rotacionares o PAT e de decidires o OAuth.
- 🟡 **OAuth p/ claude.ai web** = trabalho real que falta para o conector web (ver B4).
- 🟢 Proposta de **teste** (`prop-…`) foi limpa da fila; a fila fica vazia.

## 📦 Commits / deploy
- `9fcae33` — servidor MCP + fix aging + ADR + B0 sync (código no repo).
- `<este>` — `deploy.sh` (--user, mount rw) + `ponte_mcp.md`.
- VPS: `/root/cortex-mcp/` (código), container `cortex-mcp` (up, non-root), cron `cortex-mcp-sync` 06:30, token em `/root/cortex_mcp_token`.
- *(push → origin.)*
