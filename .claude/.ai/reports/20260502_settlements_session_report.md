# Sessão Settlements 2026-05-02 — 7 fases atómicas

**Branch:** `autonomous-night-2026-04-29`
**Estado:** ✅ Todas as 7 fases concluídas, smoke MCP validado, push em origin.

---

## Tabela executiva

| FASE | Status | SHA | Migration(s) | Smoke MCP | Tempo |
|---|---|---|---|---|---|
| 1 — Reverter foto câmara | ✅ DONE | `bd8bcee` | (DB column mantida) | flutter analyze 0 errors | ~15 min |
| 2 — Fix cash settlement + driver_transactions | ✅ DONE | `eb4b010` | `20260502060000_driver_cash_settlement_fix.sql` | ✅ 2 txns por order, balance correcto | ~40 min |
| 3 — Weekly settlements + RPCs + cron | ✅ DONE | `d423591` | `20260502070000_orders_delivered_at_column.sql` + `20260502080000_driver_weekly_settlements.sql` | ✅ compute persisted, net=-0.68 | ~50 min |
| 4 — Redesign tela Ganhos + MBWay | ✅ DONE | `00ed1c1` | `20260502090000_drivers_mbway_summary_rpc.sql` | flutter analyze 0 errors | ~35 min |
| 5 — Admin settlements screen | ✅ DONE | `2900b95` | `20260502100000_admin_settlements_rpcs.sql` | flutter analyze 0 errors | ~30 min |
| 6 — BUG 29 marker label | ✅ DONE | `0c2f10f` | (UI only) | DB confirmado correcto | ~20 min |

**Total:** 6/6 fases backend+frontend (FASE 7 = este relatório). ~3h15.

---

## Migrations aplicadas em prod (Supabase `ojykpzwqrtusfeakzrna`)

1. `driver_settlement_use_driver_earnings_fix` + `driver_transactions_unique_order_type` + `fn_credit_driver_on_delivery_use_composite_unique`
2. `orders_delivered_at_column`
3. `driver_weekly_settlements` (table + helper + RPCs + pg_cron)
4. `drivers_mbway_phone_and_summary_rpc`
5. `admin_settlements_rpcs` + `_is_admin` helper

---

## Smoke MCP results

### FASE 2 — driver_transactions
| Cenário | Resultado |
|---|---|
| Order cash €15.18 + earnings €5.25 | 2 txns: 5.25 earning + 9.93 cash_adjustment ✅ |
| Order card €10 + earnings €4 | 1 txn: 4.00 earning (sem cash_adj) ✅ |
| driver_balances acumulado | -0.68 (correcto: +5.25 -9.93 +4.00) ✅ |

### FASE 3 — settlements
| Cenário | Resultado |
|---|---|
| compute_driver_settlement (2 orders semana actual) | net_balance=-0.68, direction=driver_pays_bora ✅ |
| persist=true | settlement_id criado em driver_weekly_settlements ✅ |
| pg_cron close-weekly-settlements | active=true, schedule='5 0 * * 1' ✅ |

---

## Bugs colaterais detectados

- **driver_transactions UNIQUE(order_id) bloqueava 2 rows por order** (descoberta durante FASE 2). Substituído por composite UNIQUE(order_id, type). Sem este fix, fn_credit_driver_on_delivery NÃO conseguiria inserir delivery_earning quando apply_driver_cash_settlement já tinha inserido cash_adjustment para a mesma order.
- **orders.delivered_at não existia** (descoberta em FASE 3). Created_at podia ser dias antes do delivered. Adicionada coluna + trigger BEFORE UPDATE para set automaticamente.
- **fn_award_tokens_on_delivery ON CONFLICT (order_id)** desactualizado depois de mudar UNIQUE para composite. Patched para ON CONFLICT (order_id, type).
- **ledger_entries é append-only** — precisa restart parcial dos pedidos teste em vez de DELETE.
- **Pedido teste 1e041681 do Dan tinha driver_transaction com €2.50 (delivery_fee) em vez de €5.25 (driver_earnings)** — limpeza feita inline no smoke.

---

## Ficheiros tocados (lista completa)

### Migrations
- `20260502060000_driver_cash_settlement_fix.sql`
- `20260502070000_orders_delivered_at_column.sql`
- `20260502080000_driver_weekly_settlements.sql`
- `20260502090000_drivers_mbway_summary_rpc.sql`
- `20260502100000_admin_settlements_rpcs.sql`

### Flutter
- `lib/screens/driver_map_screen.dart` (FASE 1 revert + FASE 6 mapStyle)
- `lib/stores/order_store.dart` (FASE 1 revert)
- `lib/screens/admin/admin_order_detail_screen.dart` (FASE 1 revert)
- `lib/widgets/weekly_settlement_card.dart` (NEW — FASE 4)
- `lib/screens/driver_earnings_screen.dart` (FASE 4 inserção)
- `lib/screens/admin/admin_settlements_screen.dart` (NEW — FASE 5)
- `lib/screens/admin/admin_dashboard_screen.dart` (FASE 5 NavCard)
- `.claude/.ai/decisions/2026-05-01-todos-pos-launch.md` (TODO foto reuso)

---

## flutter analyze diff

- **Antes da sessão:** 52 issues (info/warnings pré-existentes).
- **Depois da sessão:** 52 issues. **0 erros novos.**

---

## TODOs adicionados em todos-pos-launch.md

- **Coluna orders.items_unavailable_photos não-usada** (BAIXO): mantida em prod para reuso futuro (foto saco entregue, foto qualidade, etc.). Sem migration de eliminação necessária.

(Outros TODOs anteriores mantidos: BUG 24 admin photo reset, BUG 39 polyline, tech-debt GUC bypass, tech-debt shell driver↔cliente, Twilio masking.)

---

## Próximos passos sugeridos para Danilo

1. **Codemagic build:** push detectado em `autonomous-night-2026-04-29`. Última SHA: `0c2f10f`.

2. **Smoke E2E manual após APK:**

   - **FASE 1 (revert):** estafeta marca ❌ num item da lista de compras → marca directo, SEM câmera. ✅
   - **FASE 2 (cash settlement):** novo pedido cash storeShopping. Após delivered, verificar via Supabase Studio:
     - `driver_transactions`: 2 rows (delivery_earning + cash_adjustment), ambos com `amount` POSITIVO.
     - `driver_balances`: balance reflecte sinal correcto (driver deve OU recebe).
   - **FASE 3 (settlements):** abrir tela Ganhos do estafeta → vê secção "Esta semana" no topo (laranja se deve, verde se recebe). Detalhe por pedido. Tap MBWay → input + guardar. Verificar `drivers.mbway_phone`.
   - **FASE 4 (admin):** dashboard admin → "Settlements semanais" → vê lista drivers com saldo + status. Tap Marcar PAGO → input ref MBWay → confirma → row passa a 'paid' verde.
   - **FASE 6 (mapa):** durante entrega, marker laranja no Auchan + marker azul na entrega. Confirmar que NÃO aparece "Alexandre Herculano" perto do marker. (Se ainda aparecer, é Google POI nativo dependendo da API key — escalar como ocorrência específica.)

3. **pg_cron monitor:** segunda-feira 00:05 UTC Lisbon, `cron.job_run_details` deve mostrar `close_previous_week_settlements()` a executar com 0 falhas.

4. **MBWay dos drivers:** garantir que cada driver active tem `mbway_phone` configurado antes de fechar primeira semana real. Settlement com mbway_phone=NULL ainda cria row pending mas admin não conseguirá processar pagamento.

---

## Lista de commits desta sessão (cronológica)

```
0c2f10f fix(map): drop reverse geocoding in marker label (BUG 29 v2)
2900b95 feat(admin): weekly settlements management screen
00ed1c1 feat(driver): earnings screen redesign with weekly cycle + MBWay
d423591 feat(driver): weekly settlements table + compute RPC + cron close Sunday
eb4b010 fix(driver): cash settlement uses driver_earnings (was final_purchase_value=NULL)
bd8bcee revert(storeshopping): remove unavailable photo camera flow
```

6 commits atómicos. Cada um pode ser revertido individualmente.

---

## NÃO mexido (regras rigorosas honradas)

- ✅ dispatch engine intacto
- ✅ pricing_service intacto
- ✅ tokens Batch D regras intactas
- ✅ Stripe core intacto
- ✅ código 4 dígitos card/mbway intacto
- ✅ enforce_financial_immutability core intacto
- ✅ finalize_storeshopping_purchase RPC NÃO foi editada
