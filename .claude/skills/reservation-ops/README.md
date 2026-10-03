# README — reservation-ops

Lista e marca chegada de reservas via RPCs existentes. Não reimplementa pré-pagamento.

## Ambiente (.env)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` + JWT
(`BORA_ADMIN_JWT` ou `BORA_ADMIN_EMAIL`+`BORA_ADMIN_PASSWORD`) para a RPC.

## Uso
```bash
python scripts/list_reservations.py --restaurant <id> --status confirmed
python scripts/mark_status.py --reservation-id <uuid> --status arrived
python scripts/mark_status.py --reservation-id <uuid> --status arrived --commit
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) + `get_admin_jwt` + `rpc()` |
| `list_reservations.py` | SELECT reservations (restaurante/data/estado) read-only |
| `mark_status.py` | arrived → `partner_mark_arrival`; no_show → guidance (sem RPC single) |

## Notas
- €2 desconto na chegada e €3 pré-pagamento são geridos pela RPC (não recalculados aqui).
- no_show single não tem RPC → usar cron `auto_close_no_show_reservations` / painel admin.
