---
id: cortex-log
tipo: conceito
origem: [proveniência de escrita do Córtex]
ultima_confirmacao: 2026-07-08
zona: verde
confianca: auto
---

# 🧾 LOG — proveniência de escrita do Córtex (append-only)

> Cada linha: **data · lado (repo|vps) · autor · o quê**. **Nunca reescrever; só anexar.**
> É a fonte da coluna "de que lado veio cada nota" na Central do Córtex (admin).

| data | lado | autor | o quê |
|---|---|---|---|
| 2026-07-08 | repo | claude (sessão concorrente) | Fase 1A: `_importado-velho/` (33), `schema.md`, sync VPS→canónico · commits `0b44734`,`ffe08c5`,`f41429e` |
| 2026-07-08 | vps  | claude | Fix sync `obsidian-sync.sh`→`.obsidian-vault`; vault velho → `/opt/data/_vault_velho_arquivo/` |
| 2026-07-08 | repo | claude | Bloco 0: `sessions/`→`inbox/` (9), hash-fix no relatório 1A |
| 2026-07-08 | vps  | claude | Bloco 0.3: `sessoes` stale (5) → `_vault_velho_arquivo/…_stale_20260708` |
| 2026-07-08 | repo | claude | Bloco 2/3/4/5: `inbox/`, `_debt.md`, `wiki/decisoes/`(2), `wiki/licoes/`(5), `_tools/cortex_nightly.py`, `log.md` |
| 2026-07-08 | repo | bibliotecario-cerebro | Bloco 1: frontmatter de identidade em `permanente/**` |
| 2026-07-08 | repo | claude | Ponte MCP: servidor `cortex-mcp` + A1 obsidian.json + A2 aging fix + ADR fonte-verdade |
| 2026-07-08 | vps  | claude | B0 brain→`/opt/data/cortex-brain` (@7c96df8) + cron refresh 06:30 + deploy `cortex-mcp` LIVE (read/propose, HTTPS, token) |
