# README — manage-promo-codes

Cria/lista/desativa promos via RPCs admin (`promo_codes`). **Não toca pricing_service.**

## Ambiente (.env)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY` + JWT admin
(`BORA_ADMIN_JWT` ou `BORA_ADMIN_EMAIL`+`BORA_ADMIN_PASSWORD`).

## Uso
```bash
python scripts/list_promos.py --active-only
python scripts/create_promo.py --code BORA10 --type pct --value 10 --max-uses 100 --expires 2026-12-31
python scripts/create_promo.py --code BORA10 --type pct --value 10 --expires 2026-12-31 --commit
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) + `get_admin_jwt` + `rpc()` |
| `list_promos.py` | lê `promo_codes` (service_role, read-only) |
| `create_promo.py` | dry-run preview / `--commit` chama `admin_create_promo_code` (admin JWT) |

## Notas
- `pct`→p_value_pct, `fixed`→p_value_cents. RPC garante código único.
- Avisa impacto na margem. Desativar: chamar `admin_deactivate_promo_code` (suportado via create_promo --deactivate).
- Tabelas/RPCs já existiam (não criadas). Admin UI = pendência.
