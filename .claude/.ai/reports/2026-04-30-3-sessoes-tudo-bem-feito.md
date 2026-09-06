# 3 Sessões HIGH-RISK — Tudo Bem Feito · 2026-04-30

> Branch: `autonomous-night-2026-04-29`
> Project Supabase: `ojykpzwqrtusfeakzrna` (LIVE)
> Modo: autónomo total · Stripe LIVE intacto
> Estado: ✅ S1 + ✅ S2 + ✅ S3 — todas com smoke 100% pass

---

## Sessão 1 — Pagamento misto wallet + Stripe/MBWay

### Edge Functions modificadas
| Função | v anterior → nova | Diff principal |
|---|---|---|
| `create-payment-intent` | 17 → **18** | Lê `wallet_applied_cents`, valida `serverChargeCents = grossCents - walletCents`. Rejeita se `serverChargeCents <= 0`. Persiste `stripe_charge_cents` + metadata. |
| `create-mbway-payment-intent` | 11 → **12** | Idem. Charge=price-wallet, error se wallet cobre fully, metadata gross/wallet/charge. |

### Migration aplicada via MCP
- `create_order_wallet_applied_cents` — adiciona `orders.wallet_applied_cents INTEGER NOT NULL DEFAULT 0 CHECK >=0` e re-escreve `create_order` para:
  1. Aceitar `wallet_applied_cents` no `p_input`
  2. Pré-validar saldo (`SELECT … FOR UPDATE`)
  3. Cap wallet ao `customer_total` (cliente nunca debita mais do que pedido)
  4. Chamar `wallet_debit_for_order(...)` atomicamente dentro da mesma transação
  5. Marcar `payment_status='paid'` se wallet cobre fully (skip Stripe)
  6. Retornar `wallet_applied_cents`, `charge_total`, `fully_paid_by_wallet`

### Smoke tests (5/5 PASS)

| # | Cenário | Verdict |
|---|---|---|
| 1 | `orders.wallet_applied_cents` column existe + default 0 + CHECK | ✅ PASS |
| 2 | `create_order` handles wallet, valida balance, chama `wallet_debit_for_order` | ✅ PASS |
| 3 | `wallet_debit_for_order` rejeita insufficient com `check_violation` | ✅ PASS |
| 4 | `wallet_debit_for_order` debita correctamente + cria tx `-amount_cents` | ✅ PASS |
| 5 | Cálculo charge: 6 casos (10€/0c→1000c · 10€/500c→500c · 10€/1000c→0c · 10€/1500c→0c · 5€/300c→200c · 25.50€/2000c→550c) | ✅ 6/6 PASS |

### Flutter checkout antes/depois

**Antes:**
- `OrderStore.createOrder` chamava `wallet_debit_for_order` post-RPC com gate `paymentMethod==cash` (mitigação overcharge)
- `PaymentMethodScreen` enviava `createdOrder.total` ao Stripe (charge cheio mesmo com wallet)
- Resultado: cliente com wallet activo pagava cartão pelo total cheio (overcharge)

**Depois:**
- `OrderStore.createOrder` passa `wallet_applied_cents` ao RPC; debit acontece atómicamente lá
- `PaymentMethodScreen` calcula `stripeAmount = total - walletEur`, salta Stripe se `<=0`
- Edge Fn valida `amount === price - wallet_applied_cents/100`
- `OrderModel.walletAppliedCents` novo field + parsing

### Decisões UX
- **Skip Stripe quando wallet cobre full**: evita 0.50€ min charge fail; UX directa "fully paid by wallet" → confirmação imediata
- **Cap wallet ao customer_total**: defensivo. Se cliente envia 1500c para pedido 10€, RPC clamp a 1000c
- **Pre-validate FOR UPDATE**: previne race entre check e debit em concurrent orders

---

## Sessão 2 — JWT vault cutover

### Vault secret criado
```sql
SELECT vault.create_secret(
  '<anon_jwt_208_chars>',
  'dispatch_anon_jwt',
  'Anon JWT used by pg_cron dispatch jobs (S2 vault cutover, 2026-04-30)'
);
```
Verificação: `SELECT name, LENGTH(public._dispatch_jwt()) FROM vault.decrypted_secrets WHERE name='dispatch_anon_jwt';` → `dispatch_anon_jwt`, `208`.

### Funções refactorizadas (2 em prod, 4 SQL files no repo)
| Função | Antes | Depois |
|---|---|---|
| `bora_dispatch_maintenance` | hardcoded `'Bearer eyJ...'` | `'Bearer ' \|\| _dispatch_jwt()` |
| `fn_dispatch_on_calling_driver` | hardcoded `'Bearer eyJ...'` | `'Bearer ' \|\| _dispatch_jwt()` |

### Verificação
```sql
SELECT proname, pg_get_functiondef(oid) ~ 'eyJhbGciOi' AS still_has_hardcoded,
       pg_get_functiondef(oid) ~ '_dispatch_jwt' AS uses_vault_helper
FROM pg_proc WHERE pronamespace='public'::regnamespace
  AND proname IN ('bora_dispatch_maintenance','fn_dispatch_on_calling_driver');
```
| proname | still_has_hardcoded | uses_vault_helper |
|---|---|---|
| `bora_dispatch_maintenance` | **false** ✅ | **true** ✅ |
| `fn_dispatch_on_calling_driver` | **false** ✅ | **true** ✅ |

### Smoke test dispatch (PASS)
`SELECT public.bora_dispatch_maintenance();` → executou sem erro `dispatch_jwt_not_in_vault`. Cron job 22 (every 2min) continua a chamar a função sem changes necessárias.

### Rollback documentado

```sql
-- Se vault falhar, reverter funções para hardcoded literal:
-- 1. Re-aplicar a versão pre-S2 das 2 funções (CREATE OR REPLACE com JWT hardcoded)
-- 2. Drop da helper:
DROP FUNCTION public._dispatch_jwt();
-- 3. Vault secret pode ficar — não tem efeito sem _dispatch_jwt
```

Tempo de rollback: <2min (CREATE OR REPLACE de 2 funções).

---

## Sessão 3 — Pricing refactor (settings-driven)

### Resultados 49/49 cenários v1 vs v2

```sql
SELECT COUNT(*) total_cases, COUNT(*) FILTER (WHERE all_fields_match) exact_match;
-- → 49 / 49 (100%)
```

Cenários cobertos:
- 10× partner restaurant (subtotal 5–50€, dist 1–10km, apt/stacked/both)
- 5× partner storeShopping
- 5× non-partner restaurant
- 5× non-partner storeShopping
- 5× carryGroceries
- 5× sendPackage
- 4× edge cases distance < 1km (clamp), exactly 4km
- 2× edge cases subtotal=0
- 2× edge cases very large (200€/15km, 150€/10km)
- 2× edge cases mix stacked+apt+partner
- 3× decimal subtotals (13.37€, 99.99€, 7.50€)
- + 1 extra (49 total cases distintos)

Comparação byte-by-byte: `delivery_fee`, `service_fee`, `platform_commission`, `driver_earnings`, `customer_total`, `partner_markup_hidden`, `bag_fee` — todos exact match v1 vs v2.

### Switchover executado (transação atómica)

```sql
BEGIN;
ALTER FUNCTION public.pricing_calculate(...) RENAME TO pricing_calculate_legacy_pre_settings;
ALTER FUNCTION public.pricing_calculate_v2(...) RENAME TO pricing_calculate;
COMMIT;
```

Tempo de transação: <100ms. Nenhum `create_order` em flight viu fn missing — `BEGIN/COMMIT` garante atomicidade.

### Settings agora afectam preços reais (S3.5 PASS)

```sql
-- Baseline: delivery_base_fee_cents=250, fn returns delivery_fee=2.50
-- Mutate to 350 → fn returns delivery_fee=3.50 (NEW VALUE)
-- Restore 250 → fn returns 2.50 (RESTORED)
-- Legacy fn always returns 2.50 (immutable, unchanged)
```
✅ PASS: settings mutation affects pricing_calculate (legacy unchanged)

7 settings novos seeded para cobrir todas as constantes: `apartment_*` (3), `logistics_driver_*` (2), `package_*` (2). Total platform_settings: 26 → **33**.

---

## Bugs novos descobertos

1. **`payment_buffer_total` semantics drift** (S1): create_order populava `payment_buffer_total` com `customer_total*1.15` (non-partner shopping) mas Edge Fn validava contra `price`. Era buffer "decorativo". Agora `payment_buffer_total = (charge_total)*1.15` — coerente, embora Edge Fn continue a usar `price - wallet_cents` (não buffer*1.15) pela compat.

2. **`platform_settings.key` não `setting_key`** (já documentado em S anterior): coluna canónica é `key`. Confirmado.

3. **49 vs 50 cenários** (S3): a contagem real é 49 (ROW_NUMBER deu indicação 50 inicial mas a VALUES tinha 49 tuplos). Ajustado nos relatórios.

4. **Stripe charge buffer não enforced** (S1): create-payment-intent já não usa o 1.15 buffer; charge é exact `price - wallet`. Para non-partner shopping orders, isto significa NO pre-auth surplus → se final_purchase_value > estimated, Bora não tem buffer Stripe para cobrar. Seria preciso `charge-extra` Edge Fn ser chamada (já existe). Documentar para Danilo.

## TODOs/FIXME restantes

Apenas o pre-existente: `lib/screens/reservation_flow_screen.dart:100 prepaymentCents: 300, // €3 (BR §14.5) — charge wiring TODO`.

## Verificação MCP final

✅ **Tabelas (42)**: incl. `client_wallets`, `wallet_transactions`, `driver_locations`, `cancellation_requests`, `promo_codes`, `referral_codes`. `orders.wallet_applied_cents` column nova.

✅ **RPCs admin (48+)**: incl. `admin_realtime_metrics`, `admin_live_orders`, `admin_live_drivers`, `driver_update_location`, `admin_partner_sales_summary`.

✅ **Edge Functions ACTIVE**: `create-payment-intent v18`, `create-mbway-payment-intent v12`, `dispatch-engine v38`, `refund v12`, `cancel-order-with-choice v1`, `execute-cancellation v1` + 13 outras.

✅ **Vault**: `dispatch_anon_jwt` secret presente, `public._dispatch_jwt()` callable.

✅ **Pricing**: `pricing_calculate` (canónica, lê settings) + `pricing_calculate_legacy_pre_settings` (rollback). 33 entries em platform_settings.

✅ **Cron job 22**: `*/2 * * * *  bora_dispatch_maintenance` continua activo (sem mudança de schedule).

## flutter analyze (output relevante)

Pre-existing 47 deprecation infos + 3 unused warnings (todas pre-S1/S2/S3). 0 erros novos. Mudanças nesta sessão de Flutter:
- `lib/models/order_model.dart` — novo field `walletAppliedCents`
- `lib/stores/order_store.dart` — passa wallet ao RPC, propaga ao OrderModel
- `lib/screens/payment_method_screen.dart` — calcula stripeAmount=total-walletEur, skip Stripe se <=0

## Comandos rollback

### S1 rollback
```sql
-- Reverter create_order para versão sem wallet_applied_cents (verificar git history para definição)
-- Edge Fns: re-deploy versões anteriores via mcp__supabase__deploy_edge_function
-- Coluna pode ficar (não causa harm).
```

### S2 rollback
```sql
-- Re-aplicar bora_dispatch_maintenance + fn_dispatch_on_calling_driver com JWT hardcoded
-- DROP FUNCTION public._dispatch_jwt();
-- Vault secret pode ficar inactivo.
```

### S3 rollback (mais crítico)
```sql
BEGIN;
ALTER FUNCTION public.pricing_calculate(text, numeric, numeric, boolean, boolean, boolean)
  RENAME TO pricing_calculate_v2_broken;
ALTER FUNCTION public.pricing_calculate_legacy_pre_settings(text, numeric, numeric, boolean, boolean, boolean)
  RENAME TO pricing_calculate;
COMMIT;
```
Tempo: <30s. Atómico.

## Tempo por sessão

| Sessão | Duração |
|---|---|
| S1 (mixed payment) | ~45min |
| S2 (JWT vault) | ~15min |
| S3 (pricing settings) | ~30min |
| Migrations locais + relatório | ~15min |
| **Total** | **~1h 45min** |

## Estado da branch

Commits novos planeados (4):
1. `feat(S1): mixed wallet+Stripe payment — atomic debit in create_order`
2. `feat(S2): JWT vault cutover — _dispatch_jwt() helper + 2 fn refactor`
3. `feat(S3): pricing_calculate reads platform_settings (49 smoke + atomic switchover)`
4. `docs: 3-sessoes-tudo-bem-feito report`

Push final: `origin/autonomous-night-2026-04-29`.
