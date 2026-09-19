# Sessão 5G — TODOs adiados (5G-β e seguintes)

**Data:** 2026-05-07
**Origem:** Sessão 5G — Painel Admin Inbox Avançado

## 5G-β (futuro)

### Diff visual proper
- Substituir diff naive linha-a-linha por package `diff_match_patch` ou similar
- LCS algorithm para `playbook_update`
- Highlighting word-level vs line-level

### Filtros
- Filtro **categoria dinâmica** — dropdown alimentado por `top_categories` da RPC `admin_skill_suggestions_metrics()` em vez de TextField livre
- Search com **highlighted matches** em `pattern_summary`

### Export
- Export CSV de propostas (admin power-user)

### Audit trail
- Tabela `skill_suggestions_history` (UPDATE/DELETE log)
- Tracking quem alterou notas e quando

### Métricas avançadas
- Tempo médio **reject** vs **implement**
- Diff highlighting para `settings_update` (key: oldVal → newVal — visual mais rico)

## Próximas sessões

- **Sessão 6 original** — Avaliações por estrelas (~3-4h)
- **Sessão 7** — Validações finais + UUID refactor (BUG 39, ~6-8h)
- **5F-β-β** — Refactor 7 cron jobs scrapers BROKEN (`update-products` etc.)
