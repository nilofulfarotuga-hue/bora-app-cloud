---
id: adr-cortex-fonte-verdade-ponte-mcp
tipo: decisao
origem: [prompt Danilo "Ponte MCP", gather VPS 2026-07-08]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# ADR — Fonte de verdade do Córtex + a ponte MCP (Claude.ai ↔ Hermes)

**Contexto.** Claude.ai e o Hermes não partilham o cérebro ao vivo. A ponte certa não é as duas IAs
telefonarem uma à outra — é **ambas lerem/escreverem o MESMO Córtex** via um servidor MCP.

**Decisão.**
1. **Fonte de verdade = o repo git** (`.claude/.ai/knowledge/` na branch `autonomous-night-2026-04-29`).
2. **Espelho no VPS** num diretório **dedicado** `/opt/data/cortex-brain` (checkout raso da branch) —
   **NÃO** se reusa `/opt/data/bora-app-cloud` nem `/opt/data/bora-work` (estão noutras branches,
   usados pelo Hermes; mudar-lhes a branch parte o Hermes).
3. O **servidor MCP** lê/escreve nesse espelho. Escrita **verde** → `git commit + push` de volta ao
   repo (não diverge). Escrita **vermelha** → NUNCA escreve; cria proposta na fila do admin.
4. O `cortex_nightly.py` e o Hermes passam a operar sobre o mesmo espelho.

**PORQUÊ.**
- Um cérebro só, coerente, com git como árbitro (histórico + reversível).
- Isolar o espelho do Córtex das clones de trabalho do Hermes evita partir o que já funciona.

**Consequências / riscos.**
- 🔴 **Segurança:** o servidor fica exposto na internet pública (Claude.ai liga da cloud da Anthropic,
  não pela Tailscale) → token obrigatório + HTTPS + trava de zona **no servidor** (não no prompt).
- 🟡 **Escrita autónoma pública** ao repo é sensível → **`cortex_escrever` começa DESLIGADO**
  (`CORTEX_WRITE_ENABLED=false`); read/propose live desde o início (dial começa cauteloso, como a Fase 5).
- 🟡 **claude.ai custom connector** normalmente exige **OAuth**, não um bearer estático — ver relatório `ponte_mcp.md`.

## Actualização 2026-07-10 — sync do espelho POR-TAREFA (fim da cegueira diária)

**Problema.** O espelho `/opt/data/cortex-brain` só sincronizava no cron das 06h30 → o Claude.ai
ficava **cego ao conteúdo novo até ao dia seguinte**.

**Decisão.** Sincronizar a **cada ordem** do loop, não só de madrugada:
1. **`sync-brain.sh` ganhou 2 modos:** `hard` (default, cron 06h30, `reset --hard` autoritário) e
   `fast` (por-tarefa, `merge --ff-only`). O `fast` **preserva a fila `orquestracao/`** que o
   carteiro edita localmente (o `reset --hard` rebobinava-a → re-execução). Auth **sempre** deploy
   key SSH (`/opt/data/.secrets/cortex_deploy_ed25519`), **nunca PAT**.
2. **`carteiro.sh`** chama `sync_espelho` (modo fast) **no fim de cada ordem** (após o push do executor).
3. **`pre-push` hook** no repo do PC: qualquer push à branch (loop OU manual) agenda o sync fast no
   VPS em background (~6s depois, best-effort; nunca bloqueia o push).
4. **`bora-bridge-up.sh`** re-garante (idempotente) o remote SSH deploy key do espelho após um recreate.
5. **Cron 06h30 mantido** como rede de segurança (reconcilia se algum `fast` falhar por árvore suja).

**Consequência.** Espelho fresco em **segundos** após cada push; o `≤24h` continua garantido pelo
fallback. Ver `permanente/semantica/loops.md` (linha cortex-mcp-sync, v2).
