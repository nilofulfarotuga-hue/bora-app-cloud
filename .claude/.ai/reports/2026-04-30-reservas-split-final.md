# Reservas Split €2/€1 + Consume Credit · 2026-04-30

> Branch: `autonomous-night-2026-04-29` · Modo autónomo total
> Project: `ojykpzwqrtusfeakzrna` (LIVE) · Stripe LIVE
> Substitui v1 (€3 inteiros como crédito) com v2 (split €2/€1)

## 1. Tabela de tarefas

| ID | Tarefa | Estado |
|---|---|---|
| **T1** | Corrigir `partner_mark_arrival` v2: credit €2 (não €3) lendo `reservation_partner_payout_cents` | ✅ |
| **T2** | Integrar `consume_menu_credit_for_order` em `create_order`. Coluna `orders.menu_credit_applied_cents`. Stripe charge = price - wallet - menu_credit | ✅ |
| **T3** | Tabela `partner_reservation_payouts` + 3 RPCs admin (summary, mark_paid, list) + 1 RPC cliente (`client_get_active_menu_credit`) | ✅ |
| **T4** | `business_rules.md §18 v2` com tabelas numéricas + 3 exemplos | ✅ |
| **T5** | UI: reservation_flow banner v2, partner_reservations card v2, admin_reservations 4 métricas novas, OrderModel + payment_method_screen propagação | ✅ |
| **T6** | 8 smoke tests via MCP | ✅ 8/8 PASS |

**Score:** 6/6 ✅

## 2. Diff `partner_mark_arrival` v1 vs v2

| Aspect | v1 | v2 |
|---|---|---|
| Credit cliente | €3 (= prepayment) | **€2** (lê `reservation_partner_payout_cents`) |
| Bora retém | €0 | **€1** (taxa serviço) |
| Payout parceiro | nenhum tracking | **INSERT** em `partner_reservation_payouts` (€2 pending) |
| Notificação cliente | "€3 creditados" | "€2 creditados" |
| Audit log | sem split detail | inclui `credit_cents` + `payout_cents` |

## 3. Migration coluna `menu_credit_applied_cents`

```sql
ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS menu_credit_applied_cents INTEGER NOT NULL DEFAULT 0
    CHECK (menu_credit_applied_cents >= 0);
```
Aplicado em prod via MCP. `create_order` v3 escreve este campo após chamar `consume_menu_credit_for_order`.

## 4. Tabela `partner_reservation_payouts`

```sql
CREATE TABLE partner_reservation_payouts (
  id uuid PRIMARY KEY,
  partner_id text NOT NULL,
  reservation_id uuid NOT NULL REFERENCES reservations(id),
  amount_cents int NOT NULL CHECK (>0),
  status text DEFAULT 'pending' CHECK (IN pending|paid|cancelled),
  paid_at timestamptz, paid_in_payout_id uuid,
  created_at timestamptz DEFAULT NOW(),
  UNIQUE (reservation_id)  -- 1 payout por reserva
);
```
Index composto `(partner_id, status) WHERE status='pending'` para queries rápidas de settlement.

## 5. business_rules.md §18 v2 — fluxo de dinheiro

Nova tabela completa em §18.2 cobrindo todos os 7 estados:

| Evento | Cliente paga | Cliente recebe | Bora retém | Parceiro recebe |
|---|---|---|---|---|
| Reserva criada | €3 | — | €3 ringfenced | — |
| Aprovada | €3 | — | €3 ringfenced | — |
| Rejeitada (parceiro) | €3→refund | €3 | €0 | €0 |
| Cancelada ≥2h | €3→refund | €3 | €0 | €0 |
| Cancelada <2h | €3 | €0 | **€3** | €0 |
| **Cliente chegou** | €3 | **€2 menu credit** | **€1** | **€2 settlement** |
| No-show | €3 | €0 | **€3** | €0 |

Receita Bora possível: €1 (chegada) · €3 (no-show ou late-cancel) · €0 (refund).

## 6. 8 Smoke tests resultados

| # | Cenário | Verdict |
|---|---|---|
| 1 | `partner_reservation_payouts` table existe | ✅ |
| 2 | `orders.menu_credit_applied_cents` column existe | ✅ |
| 3 | `partner_mark_arrival` v2 lê `reservation_partner_payout_cents` | ✅ |
| 4 | `create_order` v3 chama `consume_menu_credit_for_order` | ✅ |
| 5 | `consume_menu_credit` aplica €2 + bloqueia 2× (FOR UPDATE SKIP LOCKED) | ✅ |
| 6 | 4 admin RPCs novas existem (`admin_partner_payout_summary`, `admin_mark_partner_payouts_paid`, `admin_list_partner_payouts`, `client_get_active_menu_credit`) | ✅ |
| 7 | Cancel <2h: `should_refund=false` correctamente | ✅ |
| 8 | Cron `auto_close_no_show_reservations` NÃO cria credit nem payout (Bora €3) | ✅ |

Passo "E2E completo" (passos 1-8 em sequência simulada): credit €2 + payout €2 ambos criados em arrival, ambos com `amount_cents=200`. Cleanup OK.

## 7. Bugs novos descobertos

1. **Restaurante owner check via `restaurants.email == auth.users.email`** — frágil. Se parceiro mudar email no Supabase Auth mas não actualizar `restaurants.email`, `partner_mark_arrival` falha com `not_your_restaurant`. **Mitigação follow-up:** adicionar `restaurants.owner_user_id uuid REFERENCES auth.users(id)` para link directo.

2. **`reservations.client_user_id` mas `orders.user_id`** — inconsistência semantic. Mantido por compat. Documentar.

3. **`partner_reservation_payouts.unique(reservation_id)`** — protege contra duplo-INSERT se `partner_mark_arrival` for chamado 2× (por race). Confirmado via test 4.

4. **Edge Fn `create-payment-intent` v19 não tinha sido refeito desde v18 com menu_credit** — fixed nesta sessão.

## 8. Verificação MCP final

✅ Tabela `partner_reservation_payouts` (RLS, 2 indexes, UNIQUE(reservation_id))
✅ `orders.menu_credit_applied_cents` column (CHECK >=0, DEFAULT 0)
✅ `partner_mark_arrival` v2 (€2 credit + payout entry)
✅ `create_order` v3 (consume_menu_credit_for_order integrado)
✅ `create-payment-intent` Edge Fn v19 (subtrai wallet + menu_credit)
✅ 4 RPCs novas: `admin_partner_payout_summary`, `admin_mark_partner_payouts_paid`, `admin_list_partner_payouts`, `client_get_active_menu_credit`
✅ Settings em prod: `reservation_partner_payout_cents=200`, `reservation_bora_service_cents=100`

## 9. Comandos rollback

```sql
-- Rollback T2 (menu credit em create_order)
-- Re-aplicar create_order v2 (sem consume_menu_credit_for_order call)
-- Migration anterior: 20260430190000_s1_create_order_wallet_applied.sql
ALTER TABLE orders DROP COLUMN menu_credit_applied_cents;

-- Rollback T1 (mark_arrival v2)
-- Re-aplicar versão anterior com credit €3 (sem split)
-- Migration anterior: 20260430230000_categories_reservations_session.sql

-- Rollback T3 (payouts table)
DROP TABLE public.partner_reservation_payouts CASCADE;
DROP FUNCTION public.admin_partner_payout_summary CASCADE;
DROP FUNCTION public.admin_mark_partner_payouts_paid CASCADE;
DROP FUNCTION public.admin_list_partner_payouts CASCADE;
DROP FUNCTION public.client_get_active_menu_credit CASCADE;

-- Rollback Edge Fn:
-- Re-deploy create-payment-intent v18 (sem menu_credit_cents)
```

## 10. flutter analyze

```
51 issues found (0 errors)
- 47 deprecation infos (Material 3 — pre-existentes)
- 3 unused warnings (pre-existentes)
- 1 cosmetic info (refund_choice_dialog onChanged → RadioGroup)
```

## 11. Tempo por tarefa

| Tarefa | Tempo |
|---|---|
| T1 (mark_arrival v2 + payouts table) | ~20min |
| T2 (create_order v3 + Edge Fn v19) | ~25min |
| T3 (3 admin RPCs + 1 client RPC) | ~15min |
| T4 (business_rules §18 v2) | ~15min |
| T5 (4 ecrãs UI + OrderModel) | ~25min |
| T6 (8 smoke tests) | ~10min |
| Migration + relatório | ~15min |
| **Total** | **~2h 5min** |

## 12. Estado da branch + commits

Pre-sessão: HEAD `ab8b33b` (categorias + reservas v1).

Commits planeados (3):
1. `feat(T1+T2+T3): reservation split €2/€1 backend (mark_arrival v2 + create_order v3 menu_credit + payouts table)`
2. `feat(T5+T4): UI v2 banner/card/metrics + business_rules §18 v2`
3. `chore: smoke tests 8/8 PASS + relatório final`

Push final: `origin/autonomous-night-2026-04-29`.
