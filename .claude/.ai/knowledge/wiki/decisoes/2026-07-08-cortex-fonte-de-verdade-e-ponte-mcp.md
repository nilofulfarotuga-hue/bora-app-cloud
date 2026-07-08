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
