# README — refund-assistant (SHADOW)

Prepara PROPOSTA de refund para aprovação humana. **Nunca executa.**

## Ambiente (.env)
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`.

## Uso
```bash
python scripts/prepare_refund.py --order-id <id>
```

## Scripts
| script | função |
|--------|--------|
| `_shared.py` | motor S1 (Ctx/log) + `audit_log` + `REPO_ROOT` |
| `prepare_refund.py` | lê pedido + settings → calcula refund + split 80/20 → proposta + audit |

## Regra 5B (crítica)
Refund/cancelamento pós-compra/disputa = escala sempre a humano. Esta skill **só propõe**:
nunca chama a Edge Fn `refund`, nunca toca Stripe nem `bora_tokens`. Execução = Danilo/admin.
Proposta em `_preview/refund_<order_id>.md`. Auditada como `refund_proposed`.
