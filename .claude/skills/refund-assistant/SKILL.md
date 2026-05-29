---
name: refund-assistant
description: SHADOW MODE — prepara uma PROPOSTA de refund para aprovação humana. Lê o pedido, calcula refund elegível (cancel_fee_* por escalão) e split wallet 80% / tokens 20%. Gera proposta em _preview/ + admin_audit_log 'refund_proposed'. NUNCA executa refund nem toca Stripe.
metadata:
  type: financeiro
  category: refund
  depends_on: bora-knowledge
  uses_edge_fns: []
  version: 1.0.0
---

# Refund Assistant (SHADOW — só propõe)

Prepara o cálculo de um refund **para o humano aprovar**. **NUNCA executa.** Regra 5B:
refund/cancelamento pós-compra/disputa → **escala sempre a humano**.

## Pré-requisitos (LER bora-knowledge ANTES de agir)
1. `bora-knowledge/knowledge/05-business-rules.md` (cancel fees, split wallet)
2. `bora-knowledge/knowledge/09-platform-settings.md` (`cancel_fee_*`, `wallet_split_free_pct`)
3. `bora-knowledge/knowledge/10-protected-zones.md` (Stripe/refund intocáveis)

## Ambiente
`SUPABASE_URL`, `SUPABASE_ANON_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `BORA_ADMIN_USER_ID`.

## Uso
```bash
python scripts/prepare_refund.py --order-id <id>
```

## Cálculo (proposta)
1. Lê o pedido (total pago, status, payment_method).
2. **Fee por escalão** (lido de `platform_settings`):
   - antes de dispatch (created/preparing/callingDriver) → `cancel_fee_before_dispatch_cents`
   - após aceite/pickup (driverAccepted/pickedUp) → `cancel_fee_after_accept_cents`
   - em rota/entregue (onTheWay/delivered) → `cancel_fee_after_pickup_ratio` (1 = sem refund)
3. `refund_elegivel = max(0, total_pago − fee)`.
4. **Split**: `wallet_split_free_pct` (0.80) em saldo livre + restante (~20%) em **tokens** (expira 60d).
5. Escreve `_preview/refund_<order_id>.md` (proposta) + `admin_audit_log` action `refund_proposed`.

## Salvaguardas CRÍTICAS
- **NUNCA** chama a Edge Fn `refund` nem toca Stripe/`bora_tokens`. Só **lê** e **propõe**.
- A execução real é decisão humana (Danilo / painel admin).
- Cálculo é estimativa para revisão — confirma sempre antes de processar.
