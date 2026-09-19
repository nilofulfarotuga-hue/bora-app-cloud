# README — seed-demo-data

Dados de demonstração isolados e reversíveis. **Só cash. Nunca Stripe.**

## Ambiente (.env)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`.

## Fluxo
```bash
python scripts/seed.py --clients 3 --orders 5            # dry-run
python scripts/seed.py --clients 3 --orders 5 --commit   # cria DEMO_
python scripts/cleanup.py --commit                        # remove tudo DEMO_
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) + `audit_log` + prefixo `DEMO_` |
| `seed.py` | cria N clientes (users DEMO_) + N pedidos (orders is_test_order=true, cash) |
| `cleanup.py` | remove linhas DEMO_ (users por email demo_*@bora.test; orders is_test_order+DEMO_) |

## Isolamento
- `orders.is_test_order=true` + `customer_name` `DEMO_*` + `payment_method='cash'`.
- `users.email` `demo_<n>@bora.test`, `name` `DEMO_<n>` (não há coluna is_demo).
- cleanup só apaga o que tem o marcador → zero risco para dados reais.
