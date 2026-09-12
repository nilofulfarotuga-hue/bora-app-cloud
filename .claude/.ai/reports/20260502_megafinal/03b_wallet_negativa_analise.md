# Sessão 3B-NOVA — Wallet com Saldo Negativo (Fase A: Investigação)

**Data:** 2026-05-04
**Branch:** autonomous-night-2026-04-29
**Pré-requisito:** Sessões 1, 2 e 3 fechadas (commits 754b690..d4eaba3)
**Mudança de estratégia:** Abandona Stripe off_session (bloqueado por A4 MBWay + A8 STRIPE_MODE + A9 Termos legais). Substitui por wallet com saldo negativo, liquidação automática na próxima compra.
**Estado:** ⛔ FASE A CONCLUÍDA — A AGUARDAR LUZ VERDE DO DANILO

---

## ⚠️ HARD GATES DE BLOQUEIO

### Gate A0b — Fiscal/Contabilístico (BLOQUEIO #1)

Wallet negativa = empréstimo ao cliente sem documento fiscal imediato. Em PT pode ter implicações IVA / SAFT.

**Pergunta para Danilo:**
> Confirmaste com contabilista que aceitar saldo negativo até **−€20** sem doc fiscal imediato é OK em PT?
> [ ] Sim, confirmado
> [ ] Adiar — vou perguntar

**Recomendação técnica:** Cada `wallet_transactions` com `kind='debit'` deve gerar uma "nota interna" referenciada na fatura do **próximo pedido** (campo `settlement` no recibo). Esta abordagem mantém rasto contabilístico contínuo. Confirmar com contabilista.

**Sem confirmação → Fase B BLOQUEADA.**

### Gate A4b — Orders pendentes pré-deploy (RESOLVIDO ✅)

Query: `SELECT COUNT(*) FROM orders WHERE payment_status='extraRequired'`
Resultado: **0** (zero orders pendentes).

→ Sem necessidade de migração retroactiva. Sem decisão pendente.

---

## REGRESSÃO CHECK SESSÕES 1+2+3 (A0)

| Item | Esperado | Real | Status |
|---|---|---|---|
| Coords NULL pós 2026-05-03 (BUG 1) | 0 | 0 | ✅ |
| Backfill non-partner approved (BUG 6) | 10 | 10 | ✅ |
| Non-partner pending | 5 (memória) | 0 | ⚠️ Memória desactualizada (todos foram aprovados) |
| Reservation RPCs prod | 7 | **6** | ⚠️ Memória dizia 7, real são 6 (admin_reservations_metrics, admin_reservations_today, auto_close_no_show_reservations, client_cancel_reservation, client_confirm_reservation_payment, partner_decide_reservation). Provável o sétimo está noutra naming convention — não bloqueia esta sessão |
| `cash_total_due` column existe | sim | sim | ✅ |
| `pending_charges` table existe (inactiva) | sim | sim, 0 rows | ✅ |
| `finalize` cap p_bag_count 0-5 | sim | sim (`RAISE 'invalid_bag_count'`) | ✅ |
| `bag_fee_supermarket_per_bag_cents` = 10 | sim | sim | ✅ |
| `non_partner_markup_pct` = 0.15 | sim | sim | ✅ |
| `max_extra_charge_pct` = 0.30 (warning) | sim | sim | ✅ |

**Conclusão:** Nenhuma regressão crítica. Apenas duas notas de actualização da memória (5 pending non-partner → 0; 7 reservation → 6).

---

## SCHEMA `client_wallets` (A1)

```
user_id          uuid     NOT NULL  PRIMARY KEY  FK→auth.users(id) ON DELETE CASCADE
free_balance_cents  int   NOT NULL  DEFAULT 0
created_at       timestamptz NOT NULL DEFAULT now()
updated_at       timestamptz NOT NULL DEFAULT now()
```

**Constraints:**
- ⚠️ `client_wallets_free_balance_cents_check` CHECK ((`free_balance_cents` >= 0))
  → **TEM QUE SER DROPPED + RECRIADO** com `>= -10000` (hard floor −€100).
- PK: `user_id`
- FK: `auth.users(id)` ON DELETE CASCADE

**Indexes:** apenas `client_wallets_pkey` (UNIQUE em `user_id`).
**Triggers:** nenhum.
**RLS policies:**
- `wallet_select_self` — `user_id = auth.uid()`
- `wallet_select_admin` — JWT bora_role='admin'
- ❌ Sem INSERT/UPDATE/DELETE policies (todas as mutações via funções `SECURITY DEFINER` — correcto).

---

## SCHEMA `wallet_transactions` (A3) — JÁ EXISTE

```
id                uuid        NOT NULL  DEFAULT gen_random_uuid()  PK
user_id           uuid        NOT NULL
amount_cents      int         NOT NULL  -- signed (+credit, -debit)
kind              text        NOT NULL
reason            text        NOT NULL
related_order_id  text        NULL
related_admin_id  uuid        NULL
created_at        timestamptz NOT NULL DEFAULT now()
```

**FALTAM (B1):**
- ❌ `balance_after_cents` INT NOT NULL — para audit trail completo
- ❌ `idempotency_key` TEXT NULL UNIQUE — para evitar débitos duplicados em retries

**Note:** Coluna chama-se `related_order_id` (não `order_id`). Plano original tinha `order_id` — usar nome existente.

**RLS:** select self + select admin (correcto).

---

## FUNÇÕES WALLET ACTUAIS (A2)

| Função | Status | Mudança necessária Sessão 3B |
|---|---|---|
| `wallet_credit_generic(user, amount, kind, reason, order_id)` | ✅ | Aceitar mais kinds: `cashback`, `referral`, `admin_grant` (já), `+ adjustment` (NOVO) |
| `wallet_debit_for_order(user, order, amount)` | ⚠️ RAISE `insufficient_balance` se `balance < amount` | **MODIFICAR** — permitir negativo até hard floor −€100, RAISE só se ultrapassa floor |
| `wallet_get_balance(user?)` | ✅ Retorna `free_cents`, `tokens_balance`, `last_transactions` | Adicionar flag `is_negative`, `max_negative_cents` (futuro) |
| `wallet_credit_refund_split(order, user, total, reason)` | ⚠️ Splita 80/20 livre/tokens | **MODIFICAR** — se `balance < 0`, abater dívida primeiro; resto vai para split normal |
| `admin_grant_wallet_free(user, amount, reason)` | ✅ | Sem mudança |
| `admin_revoke_wallet_free(user, amount, reason)` | ✅ | Validar comportamento se faz balance < 0 (reportar) |
| `admin_list_wallets(search, min_balance, limit, offset)` | ✅ | Adicionar param `p_only_negative` (B9) |
| `admin_user_wallet_transactions(user, kind, limit)` | ✅ | Sem mudança |

---

## RPC `create_order` (A10) — DIAGNÓSTICO

**Já tem (parcial):**
- ✅ `SELECT free_balance_cents FOR UPDATE` (mas SÓ se `v_wallet_cents > 0`)
- ✅ RAISE `INSUFFICIENT_WALLET_BALANCE` se balance < cents pedidos
- ✅ Fluxo `consume_menu_credit_for_order` (este é o sistema "tokens/menu credits", não confundir com tokens loyalty separado)
- ✅ Cálculo `v_charge_total = customer_total - wallet_eur - credit/100`
- ✅ `wallet_debit_for_order` chamado no fim se `v_wallet_cents > 0`

**FALTA (B5):**
- ❌ Bloco SELECT FOR UPDATE incondicional (mesmo se `v_wallet_cents = 0`, para ler estado actual)
- ❌ Gate `IF balance < wallet_max_negative_balance_cents → RAISE 'WALLET_BLOCKED'`
- ❌ Bloco `IF balance < 0 → settlement` (charge_total += |balance|, wallet → 0, INSERT wallet_transactions kind='settlement')

**Posição correcta dos novos blocos (ordem CRÍTICA):**

```
1. v_user_id = auth.uid()                           [existe]
2. SELECT FOR UPDATE balance INCONDICIONAL          [NOVO]
3. Gate balance < wallet_max_negative → RAISE       [NOVO]
4. validações service_type / payment_method         [existe]
5. validação wallet_cents <= balance                [existe — ajustar: balance pode ser negativo]
6. cálculo subtotal_server (markup non-partner)     [existe]
7. pricing_calculate                                [existe]
8. consume_menu_credit_for_order (tokens)           [existe]
9. v_charge_total = customer_total - wallet - credit [existe]
10. SETTLEMENT: IF balance < 0 →                    [NOVO]
      v_settlement = -balance
      v_charge_total += v_settlement
      UPDATE wallet → 0
      INSERT wallet_transactions kind='settlement'
11. v_buffer_total + INSERT order                   [existe — mas charge_total novo]
12. wallet_debit_for_order (se v_wallet_cents > 0)  [existe]
```

---

## RPC `finalize_storeshopping_purchase` (A4) — DIAGNÓSTICO

**Já tem (Sessão 3):**
- ✅ Cap `p_bag_count` 0-5 (RAISE `invalid_bag_count`)
- ✅ `v_per_bag_cents` lido de `bag_fee_supermarket_per_bag_cents` (default 10)
- ✅ Markup 15% em items_added (`v_markup_pct`)
- ✅ Cap warning `max_extra_charge_pct=0.30` (não bloqueia, só log)
- ✅ Cash extra → `cash_total_due += extra` (Sessão 3)
- ✅ Refund flow (refundPending) para cards quando `final < orig`

**Comportamento actual quando `card/mbway` E `final > orig`:**
```
v_extra_charge_cents := v_final_total_cents - v_orig_total_cents;
v_new_payment_status := 'extraRequired';   ← este path morre nesta sessão
```

**MUDANÇA Sessão 3B (B4):**
Substituir esse bloco por:
```
PERFORM wallet_apply_post_delivery_adjustment(
  p_order_id   := p_order_id,
  p_user_id    := v_order.user_id,
  p_amount_cents := v_extra_charge_cents,
  p_reason     := CASE WHEN p_bag_count IS NOT NULL THEN 'market_bags' ELSE 'substitutions' END,
  p_kind       := 'debit'
);
v_new_payment_status := v_order.payment_status;  -- mantém 'paid' (já paid no checkout)
v_extra_charge_cents := 0;                        -- limpa flag
```

**Cap absoluto €10/pedido (B2 + B3):** validar dentro de `wallet_apply_post_delivery_adjustment` antes de aplicar débito.

---

## PLATFORM SETTINGS (A9)

**Existem:**
- `bag_fee_restaurant_cents` = 30 ✅
- `bag_fee_supermarket_per_bag_cents` = 10 ✅
- `non_partner_markup_pct` = 0.15 ✅
- `max_extra_charge_pct` = 0.30 ✅
- `token_value_cents_x100` = 5 ✅
- `wallet_split_free_pct` = 0.80 ✅

**FALTAM (B2 — todos a criar):**
- `wallet_max_negative_balance_cents` = -2000 (soft cap −€20, gate em RPC)
- `wallet_hard_floor_cents` = -10000 (espelho do CHECK constraint, defesa em depth)
- `max_extra_charge_cents` = 1000 (€10/pedido absoluto)
- `wallet_negative_alert_days` = 90
- `wallet_negative_action_days` = 180
- `wallet_negative_enabled` = true (kill switch para rollback rápido)

---

## UI ACTUAL (A5-A8)

### Cliente — `lib/screens/profile_screen.dart`
- ✅ `_WalletCardsBlock` mostra 2 cards (saldo verde + tokens amarelo) via `WalletService.getBalance()` → `freeCents`
- ✅ Tappable → `wallet_history_screen.dart`
- ❌ NÃO mostra estado negativo (saldo sempre ≥ 0 hoje)
- → **B6:** vermelho se < 0, banner avisar próxima compra liquidará, bloqueio se < −€20

### Cliente — `lib/screens/cart_screen.dart`
- `_CheckoutPanel`: state `_wallet: WalletBalance?`, switch `_useWalletBalance` aplica `freeCents`
- `_walletAppliedCents()`: `_wallet!.freeCents < totalCents ? freeCents : totalCents`
- `cartStore.setWalletApplied(cents)` → propaga ao create_order
- ❌ NÃO trata saldo negativo, NÃO mostra "Saldo devedor anterior" como linha
- → **B7:** se `freeCents < 0`, linha "Saldo devedor anterior: +€X.XX" (=|freeCents|/100), recalcular total. Bloquear botão "Confirmar" se < −€20.

### Cliente — `lib/screens/wallet_history_screen.dart`
- ✅ Existe e usa filtros `kind` incluindo `admin_grant`, `admin_revoke`, `refund_credit_free`
- → **B8:** adicionar filtro `settlement`, `adjustment`, `forgive`. Ícone para distinguir débito post-delivery.

### Cliente — `lib/screens/orders_screen.dart`
- → **B8:** ícone "carteira" se pedido gerou ajuste (lookup wallet_transactions WHERE related_order_id = order.id)

### Driver — `lib/screens/driver_map_screen.dart`
- ✅ Tem `finalizePurchaseV2` com `items_added` (substituições) — `extra_*` parser → `price_base_cents` + markup 15% server-side
- → Sem mudança directa; o débito wallet acontece server-side em finalize

### Admin — `lib/screens/admin/admin_wallets_screen.dart`
- ✅ Tem filtros kind `cashback / order_payment / admin_grant / admin_revoke / refund_credit_free / referral`
- → **B9:** filtro novo "Apenas negativo", coluna "Dias inactividade", coluna "Status (ok/90d/180d)", botão "Perdoar dívida"

### Edge Function `notify-client/index.ts`
- ✅ Existe, aceita `{clientId, orderId, status, title, body, vendorName, driverName, etaMinutes}`
- ✅ Lê `users.fcm_token` + envia FCM v1 via `FIREBASE_PROJECT_ID` + `FIREBASE_SERVICE_ACCOUNT`
- → **B12:** invocar 3 templates (push cruza zero / liquida / 90d alerta). Não precisa modificar Edge Fn — só adicionar invocações server-side dentro das RPCs (B3, B5, B10).

---

## A11 — `users.last_activity_at`

`public.users` tem apenas: `id, created_at, name, email, phone, role, fcm_token, photo_url`.
❌ Sem coluna `last_activity_at` ou similar.

**Solução B11:** derivar via `MAX(orders.created_at) WHERE user_id=...`. Não criar nova coluna (evita writes em todo lado). pg_cron diário 09:00 UTC:

```sql
INSERT INTO admin_audit_log (action, entity_type, entity_id, details)
SELECT 'wallet_overdue_alert', 'user', cw.user_id::text,
       jsonb_build_object('balance_cents', cw.free_balance_cents,
                          'last_order_at', last_o.max_at,
                          'days_inactive', extract(day from now()-last_o.max_at)::int)
FROM client_wallets cw
LEFT JOIN LATERAL (SELECT MAX(created_at) AS max_at FROM orders WHERE user_id=cw.user_id) last_o ON true
WHERE cw.free_balance_cents < 0
  AND last_o.max_at < now() - interval '90 days'
  AND NOT EXISTS (... evita duplicar alerta nas últimas 24h ...);
```

90d → log; 180d → action=`wallet_action_required` (admin tem que cobrar/perdoar/suspender).

---

## A12 — TOKENS + SETTLEMENT (ORDEM CRÍTICA)

**Nota:** O sistema "tokens" aqui são `menu_credit_applied_cents` (créditos de cashback/promo aplicados via `consume_menu_credit_for_order`). Diferente do sistema "tokens loyalty" via `add_tokens` em `wallet_credit_refund_split`.

**Ordem actual em `create_order`:**
1. subtotal calculation (markup non-partner aplicado)
2. pricing_calculate (delivery_fee, service_fee, customer_total)
3. v_max_wallet_cents = customer_total*100
4. consume_menu_credit_for_order → v_credit_cents
5. v_charge_total = customer_total - wallet_eur - credit/100
6. INSERT order
7. wallet_debit_for_order

**Ordem proposta Sessão 3B (CRÍTICA):**
1. SELECT FOR UPDATE balance (incondicional)
2. **Gate negativo (NOVO)**
3. validações + subtotal + pricing (sem mudança)
4. tokens/menu_credit (sem mudança)
5. v_charge_total = customer_total - wallet - credit
6. **Settlement (NOVO):** se balance < 0 → charge_total += |balance|, wallet→0, log
7. INSERT order com charge_total final
8. wallet_debit_for_order (se cents>0)

✅ Esta ordem garante que:
- Tokens descontam ANTES do settlement (cliente recebe desconto, depois paga dívida)
- Settlement aplicado UMA vez por pedido (FOR UPDATE evita race)
- INSERT order tem charge_total final correcto

---

## DECISÃO TÉCNICA — RPC vs TRIGGER (A4)

**Recomendação: ESTENDER `finalize_storeshopping_purchase` directamente (não trigger AFTER UPDATE).**

| Aspecto | Estender RPC | Trigger AFTER |
|---|---|---|
| Determinismo | ✅ Tudo em uma transacção | ⚠️ Trigger fora do controlo do caller |
| Idempotency | ✅ Idempotency key explícito | ❌ Difícil garantir |
| Push notification | ✅ Pode invocar Edge Fn no mesmo flow | ⚠️ Complica timing |
| Debug | ✅ Stack-trace claro | ❌ Trigger esconde lógica |
| Performance | ✅ Sem overhead de trigger | ✅ Igual |

**Decisão final:** Estender RPC.

---

## A13 — IMPACTO + RISCOS + ROLLBACK

### Telas afectadas
- `profile_screen.dart` — wallet card (vermelho/banner)
- `cart_screen.dart` — _CheckoutPanel (linha settlement, bloqueio)
- `wallet_history_screen.dart` — novos kinds (filtros)
- `orders_screen.dart` — ícone carteira
- `admin_wallets_screen.dart` — filtro negativo, perdoar
- `driver_map_screen.dart` — sem mudança (server-side)

### RPCs afectadas
- `create_order` — ESTENDER (gate + settlement)
- `finalize_storeshopping_purchase` — ESTENDER (substituir extraRequired por wallet debit)
- `wallet_debit_for_order` — MODIFICAR (permitir negativo até hard floor)
- `wallet_credit_refund_split` — MODIFICAR (abate dívida primeiro se balance<0)
- `wallet_apply_post_delivery_adjustment` — NOVA
- `admin_forgive_wallet_debt` — NOVA
- `admin_list_wallets` — adicionar param `p_only_negative` (opcional)

### Triggers / Jobs
- pg_cron diário 09:00 UTC: alertas 90d / 180d

### Migrations
- DROP CHECK constraint `>= 0` + ADD `>= -10000`
- ALTER TABLE wallet_transactions ADD `balance_after_cents INT`, `idempotency_key TEXT UNIQUE`
- INSERT em platform_settings (6 chaves novas)

### Riscos regressão
| Risco | Probabilidade | Mitigação |
|---|---|---|
| Race condition débito wallet | Baixa | `SELECT FOR UPDATE` em todas as RPCs |
| Settlement aplicado 2x | Baixa | Idempotency_key em wallet_transactions |
| Cliente não vê dívida | Média | Banner persistente + push |
| BUG 35 banner cash regredir | Baixa | Testar smoke S5 |
| BUG 38 linha verde regredir | Baixa | Não tocamos pricing UI |
| Reservation RPCs (Sessão 2) | Nula | Sem overlap |
| Sessão 3 cap 5 sacos | Nula | Mantemos cap |
| `finalize` refund flow | Baixa | Branch refund permanece intacto |
| MBWay flow (Sessão 1) | Nula | Sem overlap |

### Plano rollback (kill-switch)
1. `UPDATE platform_settings SET value=false WHERE key='wallet_negative_enabled'`
2. RPCs lêem este flag no início → fallback para comportamento antigo (`extraRequired`)
3. Migration constraint: `ALTER TABLE client_wallets DROP CONSTRAINT ..._check; ADD CHECK >= 0` (re-aplicar) — apenas se zero rows com balance<0

### Estimativa Fase B
- B1 migration + B2 settings: 30 min
- B3 wallet_apply_post_delivery_adjustment: 45 min
- B4 finalize estender: 30 min
- B5 create_order estender: 1h
- B6-B9 UI cliente + admin: 2h
- B10 admin_forgive: 30 min
- B11 pg_cron: 45 min
- B12 push templates: 30 min
- Smokes S1-S18: 2h
- **Total: ~8h** (1 sessão grande)

---

## DECISÕES PENDENTES PARA DANILO

1. **Gate A0b fiscal:** confirmas com contabilista que aceitar saldo negativo até −€20 é OK em PT? **[BLOQUEIA Fase B]**
2. **A4b orders pendentes:** RESOLVIDO (0 orders) — sem decisão necessária ✅
3. **Limite soft −€20:** confirmas valor ou queres outro (ex: −€10, −€30)?
4. **Hard floor DB −€100:** confirmas valor ou outro?
5. **Cap €10/pedido absoluto:** confirmas?
6. **Reservation RPCs:** memória dizia 7 mas só achámos 6 — investigamos a sétima ou aceita-se como "6 RPCs prod"?
7. **Backfill non-partner:** memória dizia 5 pending — todos foram aprovados; actualizamos memória.

---

## PRÓXIMO PASSO

⛔ **PARAGEM. Aguardar luz verde do Danilo para Fase B.**

Hard gates:
- Gate A0b fiscal não confirmado → **BLOQUEAR Fase B**
- Gate A4b → resolvido ✅

Quando Danilo aprovar, invocar nova mensagem para começar Fase B (B1 → B12 → smokes S1-S18 → relatório final + commit atómico por bloco).
