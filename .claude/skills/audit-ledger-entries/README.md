# README — audit-ledger-entries (read-only)

Forensics do `ledger_entries`. Só deteta e reporta; nunca corrige.

## Ambiente (.env)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.

## Uso
```bash
python scripts/audit.py
python scripts/audit.py --days 30
python scripts/audit.py --json
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) + `rest_paginate` |
| `audit.py` | órfãs / duplicados / sinais inesperados / pedidos incompletos → relatório |

## Notas
- Read-only absoluto (só SELECT). Correção = decisão humana (manual/outra skill).
- Heurístico: lista ids/order_ids para investigação. Exit 1 se achados críticos.
