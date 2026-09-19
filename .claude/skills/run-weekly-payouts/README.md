# README — run-weekly-payouts (read-only)

Relatório de payouts semanais somando `ledger_entries`. **Nunca executa transferências.**

## Ambiente (.env)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`.

## Uso
```bash
python scripts/payouts.py                 # últimos 7 dias
python scripts/payouts.py --days 14
python scripts/payouts.py --since 2026-05-01T00:00:00Z --until 2026-05-08T00:00:00Z
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) + `rest_paginate` |
| `payouts.py` | agrega ledger_entries por (user_type,user_id); net a pagar; CSV + relatório |

## Notas
- Soma os valores **já lançados** no ledger (fonte de verdade) — não recalcula comissões.
- Dry-run sempre (sem `--commit`). Transferência real = humano/Stripe Connect.
- CSV em `_preview/payouts_{periodo}.csv`.
