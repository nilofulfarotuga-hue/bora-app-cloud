# Sessão 3/7 — Saco Mercado · Relatório Fase B

**Branch**: `autonomous-night-2026-04-29`
**Data**: 2026-05-04
**Decisão checkpoint B3→B4**: **[b] ADIAR** (cash 100% funcional; card/mbway mantém `extraRequired`)
**Estado**: ✅ FECHADA com Sessão 3B + 3C planeadas

---

## Itens executados

| # | Item | Estado | Resumo |
|---|---|---|---|
| B0 | Pedidos in-flight `bag_count > 5` | ✅ | Validado Fase A (0 pedidos, max=2). Sem trabalho preventivo. |
| B1 | Migration `pending_charges` + `cash_total_due` | ✅ aplicado | DDL aditivo; RLS admin only; ZERO backfill |
| B2 | UI estafeta cap 5 | ✅ aplicado | `driver_map_screen.dart` botão `+` cap `< 5` |
| B3 | RPC `finalize_storeshopping_purchase` (estender) | ✅ aplicado | Cap 0..5; branch CASH escreve `cash_total_due`; card/mbway mantém `extraRequired` |
| B5 | Banner cash com fallback `cashTotalDue` | ✅ aplicado | `OrderModel.cashTotalDue` + banner mostra "+€Y de sacos" |
| B7 | Admin vista mínima | ✅ aplicado | `admin_order_detail_screen.dart` lê `cash_total_due` com prioridade |
| B4 | Edge Fn `charge-extra` off_session + webhook market_bags | ⏸️ ADIADO | Sessão 3B (consent flow + off_session infra ausente) |
| B6 | Push pós-charge | ⏸️ ADIADO | Depende B4 |
| B7b | Admin charges screen completo | ⏸️ ADIADO | Sessão 3B com B4 |

---

## Smoke MCP executados

| # | Cenário | Resultado |
|---|---|---|
| S10 | RPC source contém `must be 0-5` | ✅ `CAP_5_OK` |
| S10 | RPC source contém branch `v_cash_extra_cents > 0` | ✅ `CASH_EXTRA_OK` |
| S10 | RPC source contém UPDATE `cash_total_due` | ✅ `CASH_TOTAL_DUE_OK` |
| S13 | Sessão 1 BUG 1 coords NULL não regrediu | ✅ `0` pedidos |
| S14 | `pricing_calculate` exists + `cash_total_due` + `pending_charges` | ✅ `true,true,true` |
| S15 | Pedidos legado bag_count > 5 | ✅ `0` (max=2; cap 5 não quebra UI) |

**Smokes não executáveis sem cliente real** (S1-S9, S11-S12): documentados em `sessao_3_pending.md` para teste manual antes de produção.

**flutter analyze**: ✅ exit 0 — **52 issues, 0 erros novos** (baseline mantido).

---

## Ficheiros modificados

### Migrations
- `supabase/migrations/20260504000000_market_bags_cash_and_pending_charges.sql` (novo)
- `supabase/migrations/20260504010000_finalize_storeshopping_cap5_cash_total_due.sql` (novo)

### Dart
- `lib/models/order_model.dart` — campo `cashTotalDue` + serialização
- `lib/screens/driver_map_screen.dart` — slider cap `< 5` + banner cash com fallback `cashTotalDue` + linha "inclui +€Y de sacos"
- `lib/screens/admin/admin_order_detail_screen.dart` — `cash_total_due` no SELECT + prioridade no `cashCollected`

### Documentação
- `.claude/.ai/business_rules.md` — secção 2.5 reescrita (tabela parceiro/não-parceiro + diagrama fluxo + checkpoint B3→B4)
- `.claude/.ai/todos/sessao_3_pending.md` (novo) — TODOs Sessão 3B/3C + colaterais
- `.claude/.ai/reports/20260502_megafinal/03_saco_mercado_analise.md` (Fase A)
- `.claude/.ai/reports/20260502_megafinal/03_saco_mercado_report.md` (este)

---

## RPCs / Tabelas / Edge Fns tocadas

| Recurso | Mudança |
|---|---|
| `public.orders.cash_total_due` (NOVA coluna) | `NUMERIC NULL`, sem default, sem backfill |
| `public.pending_charges` (NOVA tabela) | + 3 indexes + trigger `updated_at` + 2 policies admin |
| `public.finalize_storeshopping_purchase` (RPC) | Cap 0..5; branch cash escreve `cash_total_due`; audit log inclui `cash_extra_cents` |
| `public.pending_charges_set_updated_at` (NOVA fn trigger) | helper |

**NÃO tocados** (preservados):
- `dispatch-engine`, Stripe core (`create-payment-intent`, `stripe-webhook`, `create-mbway-payment-intent`, `charge-extra`)
- `enforce_financial_immutability` trigger
- `create_order` RPC (Sessão 1)
- Reservation RPCs (Sessão 2)
- `pricing_calculate` (Sessão 2)
- BUG 35 banner cash, BUG 38 linha verde

---

## Bugs colaterais reportados (anotados em sessao_3_pending.md)

1. **`confirm-mbway-payment` Edge Fn obsoleta** mas ACTIVE — apagar Sessão 6/7
2. **`create-mbway-payment-intent-debug`** em prod — apagar
3. **Schema divergência** `orders.final_total` (double precision) vs `orders.customer_total` (numeric)
4. **`extra_charge_amount` não nullify** após charge succeeded
5. **`mbway_debug_errors` RLS check** pendente

---

## Decisão B3→B4 (registada)

**[b] ADIAR**. Razões:
- Edge Function `charge-extra` actual é interactive (devolve `clientSecret`), não off_session — REWRITE total
- `setup_future_usage` propositadamente OMISSO em `create-payment-intent` por decisão de produto documentada
- Schema `orders` SEM `stripe_customer_id`/`stripe_payment_method_id` — nenhum payment_method guardado para off_session
- `stripe-webhook` SEM handler `metadata.reason='market_bags'` — risco crítico de sobrescrever `payment_status='paid'`
- Stripe LIVE em PT — cobrança sem consent recusa SCA
- Cash já cobre 100% do fluxo principal sem risco financeiro

**Sessão 3B** vai implementar charge automático off_session + webhook + retry queue.
**Sessão 3C** vai implementar consent flow (UI + `setup_future_usage` + storage).

---

## Próximos passos

1. ✅ Commit atómico desta sessão
2. ⏭️ Aprovação Danilo para Sessão 3B (consent flow primeiro? ou chargre-extra primeiro?)
3. ⏭️ Continuar Sessão 4/7 do plano mega-final (próximo escopo TBD)
