---
session: 5G
phase: A (audit)
date: 2026-05-07
branch: autonomous-night-2026-04-29
status: complete · awaiting green light
---

# Sessão 5G — Fase A Audit (Obsidian sync)

> Sync canónico de `.claude/.ai/reports/20260502_megafinal/05g_audit.md`.

## TL;DR

- **21 skills** active (3 escalate + 11 read_only + 7 write_shadow)
- **0 propostas** em prod (cron 5D só corre segundas)
- `support-chatbot` v8 SHA: `e351ab629847ff0edcea3b7719acc41418cf728426373917f67f0a9f68f9a108`
- Status enum: 5 valores (5E preservado) → +`auto_archived` em B1
- `proposal_type`, `zone_type`: ambos **lowercase** ✅
- `admin_notes` ausente → criar em B1
- `fl_chart 0.69.0` já presente; `diff_match_patch` ausente (diff naive 5G; LCS 5G-β)
- `admin_list_skill_suggestions` actual: 2 params (DROP+CREATE em B3 com defaults backward-compat)
- 6 indexes existentes; 4 novos em B1 (sem conflito)
- Próxima secção `business_rules.md`: **§43**

## Pontos críticos

1. **R1** mitigado: `_load()` actual usa só `p_status`+`p_limit` — defaults novos (`p_type='all'`, `p_zone='all'`, `p_category='all'`, `p_search=NULL`) mantêm chamada antiga válida.
2. **R2** mitigado: 0 rows em prod elimina risco do `ALTER CHECK status`.
3. **R7** flag: `_RootNavigator` é `home:` directo. `RouteObserver` precisa subscribe em `didChangeDependencies` na `AdminDashboardScreen`. Testar `didPopNext` em B7.
4. `_pendingBadgeCount` já existe na `AdminSkillSuggestionsScreen` (linha 33) — **reusar mesma stat RPC** no `AdminDashboardScreen` (B7).

## Migrations Fase B (5)

| Commit | Migration | Reversível? |
|---|---|---|
| 1 | B1 schema_extend (admin_notes + CHECK +4 idx) | ✅ |
| 1 | B2 rpcs_new (4 RPCs novas) | ✅ |
| 1 | B3 list_extended (DROP+CREATE 6 params) | ⚠️ guardar versão antiga |
| 1 | B4 auto_archive_cron | ✅ |
| 2 | B5 EDIT AdminSkillSuggestionsScreen | git revert |
| 3 | B6 NEW AdminSkillSuggestionsMetricsScreen | git revert |
| 4 | B7+B8 EDIT Dashboard + main.dart | git revert |
| 5 | docs §43 | git revert |

## Próximo passo

⛔ **STOP** — Danilo aprova "go B1" para arrancar Fase B.

## Cross-refs

- 5E: `idx_skill_suggestions_status_pending`, `proposal_type`, `zone_type` introduzidos
- 5F-β-α (§42): vault pattern (não relevante 5G)
- 5G-β (futuro): `diff_match_patch` proper LCS · filtro categoria dinâmica · CSV export · audit trail
