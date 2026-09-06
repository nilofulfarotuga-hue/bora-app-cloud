# README — pre-launch-checklist (read-only)

Auditoria de prontidão para lançamento. **Não escreve nada.**

## Ambiente (.env)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` (leitura).

## Uso
```bash
python scripts/checklist.py            # relatório PT-BR + _preview/checklist.md
python scripts/checklist.py --json     # JSON para pipelines
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) |
| `checklist.py` | agrega contagens read-only e classifica ✅/⚠️/❌ |

## Notas
- Contagens via PostgREST `Prefer: count=exact` + `Range: 0-0` (lê só o total, não as linhas).
- Edge Functions não são listáveis via REST → o relatório lembra de validar via MCP
  `list_edge_functions` (baseline 44 em S2).
- Exit code: 0 se sem ❌; 1 se houver ❌ (útil em CI/checklists).
