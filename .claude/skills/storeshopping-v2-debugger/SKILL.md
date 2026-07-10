---
name: storeshopping-v2-debugger
description: Diagnostica um pedido storeShopping V2 não-parceiro completo. Cruza orders + order_purchase_items_v2 + order_receipts_v2 + wallet_transactions + admin_audit_log num único relatório. Útil para validar fluxo end-to-end após fixes ou debug de pedidos com comportamento estranho.
triggers:
  - "diagnosticar pedido storeShopping v2"
  - "validar fluxo v2"
  - "auditar order_receipts_v2"
  - "/storeshopping-v2-debugger"
  - "debug v2 order"
metadata:
  versao: 1.0
  execucoes: 0
  sucessos: 0
  falhas: 0
  ultima_execucao: null
  criada_por: pre-telemetria (rollout 2026-07-10)
---

# StoreShopping V2 Debugger

Skill para o Robô B (Claude Code) diagnosticar pedidos storeShopping V2
não-parceiros. Lê estado completo do pedido cruzando 5 tabelas + produz
relatório formatado.

## Quando invocar

- Após aplicar fixes da sessão exec (validar pedido teste)
- Quando Danilo reporta pedido v2 com comportamento estranho
- Auditoria periódica de pedidos v2 com `reimbursement_status='pending_admin'`
- Suspeita de discrepância matemática driver_earnings vs talão

## Parâmetros

- `order_id` (UUID, obrigatório) — id do pedido a investigar
- `verbose` (bool, default false) — incluir raw OCR response + idempotency_keys

## Algoritmo

1. Query `orders` por id → confirma:
   - service_type='storeShopping', is_partner_store=false
   - purchase_flow_version=2 (caso contrário → erro: pedido v1, usar outro fluxo)
   - capture: status, payment_method, subtotal, total, delivery_fee, service_fee,
     final_purchase_value, cash_total_due, driver_earnings, platform_commission

2. Query `order_purchase_items_v2` WHERE order_id → confirmar items:
   - Total esperado purchased: COUNT(*) - count(unavailable) = count(decided)
   - Sum actual_price_cents × actual_qty (replaced+added) vs original (purchased)
   - Flag se algum status='pending' (driver não decidiu)

3. Query `order_receipts_v2` WHERE order_id → confirmar receipt:
   - photo_url existe → tentar SIGNED URL (se admin)
   - driver_typed_total_cents reasonable (não null, > 0)
   - ocr_*: se ocr_ran_at IS NULL → pendente (shadow Gemini)
   - ocr_flagged=true → diff > €0.50 (alertar admin)
   - reimbursement_status:
     * `cash_settled` (CASH OK)
     * `pending_admin` (Stripe/MBWay aguarda admin)
     * `admin_paid` (admin marcou pago + wallet creditada)
     * `rejected` (admin rejeitou — mostrar motivo)

4. Query `wallet_transactions` WHERE related_order_id:
   - Se houver items unavailable → confirmar 'refund_credit_free' com
     idempotency_key 'v2_unavail_<order_id>'
   - Se reimbursement_status='admin_paid' → confirmar 'reimbursement_storeshopping'
     com idempotency_key 'reimb_paid_<receipt_id>'

5. Query `admin_audit_log` WHERE entity_id_text=order_id OR entity_id_text=receipt_id:
   - Lista actions (receipt_paid, receipt_rejected) com admin_id + timestamp

6. Validation cross-check matemática:
   - boraMarkup = subtotal × 0.15
   - driverFixed = 3.80 + 0.80 + (0.20 × distance_km)
   - boraGross = boraMarkup + delivery_fee + service_fee
   - boraNet = max(0, boraGross - driverFixed)
   - expected_driver_earnings = driverFixed + (boraNet × 0.30)
   - Flag se ≠ orders.driver_earnings (com tolerância €0.02)

## Output Format

```
=== StoreShopping V2 Debug — Order <short_id> ===

📋 Status: <status> | Flow v<version> | Payment: <method>
🚚 Driver: <name> (<assigned_driver_id>)
👤 Client: <name> (<user_id>)
🏪 Vendor: <vendor_name>

💰 Pricing:
  Subtotal:     €<subtotal>
  Service fee:  €<service_fee>
  Delivery fee: €<delivery_fee>  (distance=<distance_km>km)
  Bag fee:      €<bag_fee>
  Total:        €<total>
  Final purch:  €<final_purchase_value>
  Cash due:     €<cash_total_due>  (se CASH)

🛒 Items V2 (<count>):
  ✅ Purchased: <n>
  ❌ Unavailable: <n>  → credit: €<credit>
  🔄 Replaced: <n>
  ➕ Added: <n>
  ⏳ Pending: <n>  (⚠️ se >0)

📷 Receipt V2:
  Photo: <photo_url> (signed: <yes/no>)
  Driver typed: €<driver_typed>
  OCR: €<ocr> (diff: €<diff>) <FLAGGED if true>
  Reimbursement: <status>  → admin: <admin_id> at <date>

💳 Wallet transactions (<count>):
  - <kind>: €<amount> (<reason>)
  ...

📜 Audit log (<count>):
  - <action> by <admin_id> at <date>

🧮 Driver earnings validation:
  Expected: €<calc>
  Actual:   €<db>
  Status: ✅ MATCH | ⚠️ DRIFT €<diff>

⚠️ Flags:
  - <flag1>
  - <flag2>
```

## Notas

- Read-only — NÃO modifica DB
- Requer admin role para signed URL de photo
- Driver earnings cross-check usa fórmula pricing_service.dart como single
  source of truth (replica em SQL/Python aqui)
- Para parceiro storeShopping (v1) ou restaurant → erro, redirecionar para
  outra skill (sessão futura: storeshopping-v1-debugger)

## 📊 Telemetria (obrigatório no fim de cada execução)

No fim de cada execução desta skill:
1. Atualiza o frontmatter deste ficheiro: incrementa `execucoes` e `sucessos` OU `falhas`; atualiza `ultima_execucao` (YYYY-MM-DD).
2. Acrescenta UMA linha à tabela de `.claude/.ai/knowledge/wiki/skills-metrics.md` (Skill | Data | Contexto | Volume | Resultado).
O evolution-engine lê essa tabela: falhas/execucoes > 30% → candidata a reescrita; 90 dias sem uso → candidata a arquivo.
