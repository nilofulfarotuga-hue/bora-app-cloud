# Bugfix Plan v3 — 2026-05-01

Branch: `autonomous-night-2026-04-29`
Modo: PROTECÇÃO TOTAL — análise apenas, aguarda aprovação Danilo por tarefa.

---

## BUG 16 — FINANCIAL_COLUMNS_IMMUTABLE em "Confirmar compra"

**Severidade:** CRÍTICO (bloqueia fluxo storeShopping não-parceiro fim-a-fim)
**Risk:** HIGH (toca DB + payments)
**Tempo:** ~140 min (2h20)
**Painel admin:** SIM (visualizar items adicionados/faltantes + refund/extra issued)

### Causa raiz CONFIRMADA
Trigger `enforce_financial_immutability` bloqueia UPDATE em colunas financeiras (`price`, `subtotal`, `delivery_fee`, `service_fee`, `platform_commission`, `driver_earnings`, `bag_fee`, `payment_buffer_total`, `final_total`, `final_purchase_value`, `refund_amount`, `extra_charge_amount`) por qualquer role ≠ `service_role`.

App estafeta faz UPDATE directo em `lib/stores/order_store.dart:1383` (`_finalizePurchaseUnchecked`) que toca `final_total`, `final_purchase_value`, `refund_amount`, `extra_charge_amount`, `payment_status` → bate no trigger.

### Ficheiros a tocar

**Flutter:**
- `lib/stores/order_store.dart`
  - `_finalizePurchaseUnchecked` @ L1383 — converter para chamar RPC
  - `processRefund` @ L1481 — converter para RPC
  - `processExtraCharge` @ L1457 — converter para RPC
  - `updateOrderItems` @ L2251 — converter para RPC (toca `bag_fee`)
- `lib/screens/driver_map_screen.dart`
  - `_FinalizePurchaseDialog` @ L1843-L1902 — REMOVER campo "Valor da compra" (input nota fiscal)
  - Substituir por `_ConfirmPurchaseStoreshoppingDialog` com 3 secções (verde / vermelho / adicionados) + total ajustado + botão "Confirmar e ir para entrega"
  - Adicionar fluxo de "adicionar produto" no ecrã da lista (estafeta mete nome + preço base; app aplica +15% auto antes de cobrar)
  - Adicionar botão "NÃO TEM" por item (marca como unavailable)
- `lib/models/order_model.dart`
  - Adicionar `itemsAdded` field (List de `{name, priceBaseCents, priceFinalCents, addedByDriver}`)
  - Adicionar serialização em `fromSupabase` / `toSupabase`

**Cliente (após confirmação estafeta):**
- Novo widget / reutilizar `lib/widgets/refund_choice_dialog.dart` (já existe) para diálogo "Faltaram €X.XX. Como queres receber? (a) Cartão 5-10 dias (b) Saldo App instantâneo"
- Trigger via realtime UPDATE quando `refund_amount > 0` e `payment_status = 'refundPending'`

**Backend (Supabase migrations):**
- Nova migration: `2026XXXX_finalize_storeshopping_purchase_rpc.sql`
  - `finalize_storeshopping_purchase(p_order_id, p_items_status JSONB, p_items_added JSONB)` — SECURITY DEFINER
  - Calcula: `bought_total`, `unavailable_total`, `added_total_with_markup`
  - Actualiza: `items` (com purchaseStatus), `items_added`, `final_total`, `refund_amount`, `extra_charge_amount`, `is_purchase_finalized`, `payment_status` (`paid` / `refundPending` / `extraRequired`)
  - Audit log em `admin_audit_log` ou tabela equivalente
- Nova migration: `2026XXXX_orders_items_added_column.sql`
  - `ALTER TABLE orders ADD COLUMN items_added JSONB DEFAULT '[]'::jsonb`
- Estender Edge Function `charge-extra` para ser invocada APÓS finalize (se `extra_charge_amount > 0` e método=card/wallet)
- Estender Edge Function `refund` idem (se `refund_amount > 0` e cliente escolheu cartão)
- Cash flow: marcar `cash_extra_pending` na order; `cash_balance` ajusta no settlement

**Painel admin:**
- `lib/screens/admin/admin_order_detail.dart` — adicionar secção "Items modificados pelo estafeta":
  - Tabela: bought (verde) | unavailable (vermelho) | added (azul, com markup mostrado)
  - Campos: `refund_amount` issued? `extra_charge_amount` charged? Estado payment_status
- Filtro novo: "Pedidos com refund/extra pendentes"

### Smoke test
1. Criar pedido Auchan cash com 5 items (€10 base × 5 = €50 base + 15% = €57.50 cobrado).
2. Estafeta marca 3 verde, 1 vermelho (item €10 base = €11.50 ajustado), adiciona 1 produto (€8 base → €9.20 com markup).
3. Confirmar compra → total ajustado = €57.50 - €11.50 + €9.20 = €55.20.
4. Cliente recebe diálogo refund de €11.50 (saldo OU cartão).
5. Cliente paga extra €9.20 ao estafeta na entrega (cash) ou auto (card).
6. Verificar `admin_audit_log` regista a transição.
7. Repetir em método=card: charge-extra deve cobrar €9.20 no cartão guardado, refund deve emitir €11.50 conforme escolha.

---

## BUG 17 — Perfil estafeta vazio

**Severidade:** MÉDIO
**Risk:** LOW
**Tempo:** ~10 min
**Painel admin:** Não

### Causa raiz CONFIRMADA (90% confiança)
`syncDriverWithAuth(uid)` em `lib/stores/driver_store.dart:130` é assíncrono mas chamado fire-and-forget no construtor do `DriverStore` via `_listenAuthChanges()`. `getDriverById(_primaryDriverId)` em L249-255 só lê lista em-memória `_drivers` — retorna `null` durante o primeiro render porque a query DB ainda não terminou.

`lib/screens/profile_screen.dart` mostra:
- L418-433: telemóvel, veículo, matrícula
- Todos `?? '-'` quando driver é null → ecrã aparece "vazio".

### Fix proposto
Em `lib/screens/profile_screen.dart:43-74` (`_validateSession`), adicionar await explícito:

```dart
final driverStore = context.read<DriverStore>();
if (driverStore.currentDriver == null) {
  final userId = Supabase.instance.client.auth.currentUser?.id;
  if (userId != null) {
    await driverStore.syncDriverWithAuth(userId);
  }
}
```

Mais loading indicator enquanto driver é null.

### Smoke test
1. Login estafeta (910000000 / 123456 ou conta real).
2. Navegar para perfil.
3. Verificar: telemóvel + veículo + matrícula populados (não "-").

### Risco colateral identificado
RLS policy `drivers_all_authenticated` em `supabase/schema.sql` permite qualquer authenticated SELECT em TODAS rows da tabela `drivers`. NÃO é causa do BUG 17 mas é leak de privacidade. Sugiro migration separada (`drivers_select_own`: `USING (id = auth.uid())`) — listar como BUG 18.

---

## BUGS COLATERAIS DESCOBERTOS

### BUG 18 — RLS demasiado permissiva em `drivers`
`drivers_all_authenticated` permite qualquer authenticated ler tudo. Fix: trocar por `drivers_select_own`. **Risk:** LOW. **Tempo:** ~5 min + migration.

### BUG 19 — `processExtraCharge` / `processRefund` sem validação de `paymentIntentId`
`order_store.dart:1457, 1481` assumem charge/refund Stripe já confirmado mas não validam que `order.paymentIntentId` foi criado. Se Edge Function falha, `payment_status` fica inconsistente. **Risk:** MED. **Tempo:** ~15 min (incluído no fix BUG 16 RPC consolidada).

### BUG 20 — `updateOrderItems` race com `bag_fee`
`order_store.dart:2251` actualiza `bag_fee` directo sem validar se já foi aplicado em `final_total`. Risk: double-charging bag_fee se ocorre post-finalization. **Risk:** MED. **Tempo:** ~10 min (incluído no fix BUG 16 — RPC `update_order_items_rpc` valida invariantes).

### BUG 21 — `finalizePurchase` race com webhook Stripe
Se webhook Stripe seta `paid` e cliente clica "finalizar" simultâneo, client-side update pode reverter para `extraRequired`. **Risk:** MED (resolvido pela RPC SECURITY DEFINER que coordena toda transição numa transacção).

### BUG 11 (pré-existente) — Double markup Stripe
NÃO investigar agora — continua na fila pós BUG 16 conforme instrução Danilo.

---

## ORDEM PROPOSTA DE EXECUÇÃO

| Ordem | Bug | Tempo | Aprovação Danilo |
|---|---|---|---|
| 1 | BUG 17 (quick win, low risk) | 10 min | aprovar antes |
| 2 | BUG 16 — Migration: `items_added` column | 5 min | aprovar antes |
| 3 | BUG 16 — RPC `finalize_storeshopping_purchase` + 3 RPCs irmãs (SECURITY DEFINER) | 45 min | aprovar antes |
| 4 | BUG 16 — Atualizar `OrderModel` + serialização | 10 min | aprovar antes |
| 5 | BUG 16 — Refactor UI `driver_map_screen.dart` + remover input nota fiscal | 30 min | aprovar antes |
| 6 | BUG 16 — Diálogo refund cliente (reutilizar refund_choice_dialog) | 10 min | aprovar antes |
| 7 | BUG 16 — Painel admin (items modificados secção) | 20 min | aprovar antes |
| 8 | BUG 16 — Smoke test E2E Auchan cash + card | 30 min | aprovar antes |
| 9 | BUG 18 — RLS drivers_select_own (migration) | 5 min | aprovar antes |

**Tempo total estimado:** ~165 min (2h45) + smoke tests.

---

## QUESTÕES ABERTAS PARA DANILO

1. Para items adicionados pelo estafeta: app aplica +15% auto. Confirmar markup é sempre 15% (não varia por loja)?
2. Refund cliente "saldo App instantâneo": é a wallet existente ou novo balance? Verificar tabela `user_balances` / `wallet_transactions`.
3. Cash + extra charge: cliente paga ao estafeta na entrega. App regista no settlement do estafeta automaticamente?
4. Limite diário de extra_charge_amount? (evitar abuso por estafeta a inflar adicionados)
5. Painel admin: quero auditoria por estafeta de items_added agregado mensal? (KPI de fraude)

---

## SAÍDA

Aguardar aprovação Danilo por TAREFA antes de executar qualquer item da tabela acima.
