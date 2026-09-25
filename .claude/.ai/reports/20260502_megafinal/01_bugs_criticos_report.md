# Sessão 1/7 — Bugs Críticos Launch — RELATÓRIO FINAL

**Data:** 2026-05-03
**Branch:** autonomous-night-2026-04-29
**Modo:** Protecção Total (aprovação per-task confirmada)
**Estado:** ✅ 7/7 bugs fechados — 8 commits, 0 erros novos

---

## 📊 Métricas

| Métrica | Valor |
|---------|-------|
| `flutter analyze` baseline | 52 issues, **0 errors** |
| `flutter analyze` final | 52 issues, **0 errors** ✅ |
| Commits novos | **8** (1 análise Fase A + 7 bugs) |
| Migrations novas | **6** |
| Linhas adicionadas | ~1925 |
| Linhas removidas | ~287 (BUG 3 cleanup) |
| Componentes proibidos tocados | **0** (dispatch, Stripe core, enforce_immut, tokens Batch D) |
| Smoke MCP testes | **15** corridos, **15** PASS |
| Bugs colaterais detectados | **0** |
| Checkpoints respeitados | **2/2** (não decidido sozinho) |

---

## ✅ Bugs fechados

### BUG 1 — Coords NULL no checkout (CRÍTICO RECEITA)
**Commit:** `fc6505e`
**Causa raiz:** RPC `create_order` v4 omitia `pickup_lat/lng` + `dropoff_lat/lng` do INSERT. 90% (45/50) dos últimos pedidos tinham coords NULL.
**Fix:** Migration v5 ([20260503000000_create_order_v5_persist_coords.sql](supabase/migrations/20260503000000_create_order_v5_persist_coords.sql)) — adiciona 4 colunas no INSERT + RAISE EXCEPTION `MISSING_DROPOFF_COORDS` se omitido (sendPackage permite pickup NULL).
**Smoke:** S1 coords persistem ✅ / S2 RAISE EXCEPTION sem coords ✅
**Flutter check:** `order_store.dart:669-672` já enviava — não foi necessário fix Flutter.

### BUG 2 — Widget Ganhos mostra 0.00€
**Commit:** `64aed6e` — 1 char
**Causa raiz:** [weekly_settlement_card.dart:291](lib/widgets/weekly_settlement_card.dart#L291) lia `o['finalTotal']` (camelCase) mas RPC retorna `final_total` (snake_case).
**Fix:** `'finalTotal'` → `'final_total'`. L322 (Cash recebido) usa a variável local — fix downstream.

### BUG 3 — Tela Ganhos antiga duplica card novo
**Commit:** `b02d668` — −267 linhas
**Causa raiz:** `WeeklySettlementCard` mostrava saldo + ganhos + entregas + histórico; depois o legado `_BalanceCard` + `_StatChip` + `_TransactionTile` repetiam tudo a partir de `driver_balances` / `driver_transactions`. Risco de divergência entre as duas fontes.
**Fix:** Remoção de classes `_BalanceCard`, `_StatChip`, `_TransactionTile`, vars `_balance/_weeklyEarnings/_weeklyDeliveries/_transactions` e respectivas queries. `_TokenSection` e `_PrioritySection` mantidos (não tocam settlement).

### BUG 4 — Restaurante não-parceiro rejeitado em finalize (CRÍTICO RECEITA)
**Commit:** `b8bdcdf`
**Causa raiz:** `finalize_storeshopping_purchase` rejeitava `service_type='restaurant'` com `wrong_service_type`. Drivers não podiam fechar entregas de McDonald's, Burger King, KFC, Pizza Hut.
**Fix:** Migration ([20260503010000_finalize_extends_restaurant.sql](supabase/migrations/20260503010000_finalize_extends_restaurant.sql)) **estende** (não reescreve):
- Aceita `service_type IN ('storeShopping','restaurant')`.
- Bag fee: parceiro restaurant = 0; não-parceiro = 30c (BR €0.30); storeShopping inalterado.
- Default canonical-status `'bought'` para restaurant (driver não substitui itens).

Flutter:
- `order_store.finalizePurchaseV2` aceita restaurant + storeShopping.
- `driver_map_screen._ShoppingListSheetContent._bagFee` respeita `is_partner_store`.
- UI: parceiro restaurant esconde secção sacos; não-parceiro mostra "Sacos / €0.30 (fixo)"; storeShopping mantém slider.

**Smoke (SQL impersonating driver):** S1 rest non-partner bag=30c ✅ / S2 rest partner bag=0 ✅ / S3 storeShopping bag=20c (regressão zero) ✅

### BUG 5 — Sync migrations Git
**Commit:** `754b690`
**Causa raiz:** Prod e Git tinham 2 divergências:
1. `compute_driver_settlement` — prod permite `v_caller IS NULL` (cron); git levantava `unauthenticated`.
2. `list_driver_orders_in_week` — prod retorna `cash_received`; git declarava `cash_adjust_due`.

**Fix:** Migration ([20260503020000_settlement_rpcs_sync_prod.sql](supabase/migrations/20260503020000_settlement_rpcs_sync_prod.sql)) — snapshot prod aplicado idempotente. Zero mudança funcional.

### BUG 6 — Aprovação admin parceiros (CRÍTICO SEGURANÇA — ÉPICO)
**Commit:** `31465af` — 633 linhas
**Causa raiz:** Tabela `restaurants` não tinha approval_status. Qualquer parceiro registado ficava imediatamente visível ao cliente.

**Fix integrado:**

| Subtarefa | Artefacto |
|-----------|-----------|
| 6a colunas | [20260503030000_partner_approval_workflow.sql](supabase/migrations/20260503030000_partner_approval_workflow.sql) — `approval_status / approved_at / approved_by / rejection_reason` + index |
| 6b backfill | 10 non-partner → `approved` (zero regressão); 5 partner → `pending` (decisão (a)) |
| 6c RPCs | `approve_partner` / `reject_partner` (motivo obrigatório) / `list_partners_by_status` — todas com admin gate (role + email allowlist) + audit log |
| 6d UI admin | `lib/screens/admin/admin_partners_pending_screen.dart` — chips filter pending/approved/rejected/todos + cards com info + botões Aprovar (confirm) / Rejeitar (reason modal). Nav adicionada ao dashboard |
| 6e RLS | [20260503040000_partners_rls_approved_only.sql](supabase/migrations/20260503040000_partners_rls_approved_only.sql) — `public.is_admin()` SECURITY DEFINER (anon não pode SELECT auth.users) + `ALTER POLICY restaurants_public_read USING (approved OR is_admin())` |
| 6f email | TODO em [.claude/.ai/todos/sessao_1_pending.md](.claude/.ai/todos/sessao_1_pending.md) (Resend infra ausente) |

**Smoke (SQL impersonating anon e admin):** S1 pending invisível anon ✅ / S2 approved visível anon ✅ / S3 rejected invisível + audit log ✅ / S4 backfill regressão zero (10 visíveis) ✅

### BUG 7 — Foto parceiro obrigatória no cadastro
**Commit:** `ba1df37`
**Causa raiz:** [register_partner_screen.dart:244-247](lib/screens/register_partner_screen.dart#L244-L247) tinha validator que bloqueava save sem URL de foto.
**Fix:** Validator removido; helperText/labelText "(opcional)"; constante `_kPartnerPlaceholderPhoto` aplicada quando o input é vazio (URL Bora-branded em storage bucket).

### BUG 24 — Admin não consegue resetar foto produto
**Commit:** `c9a73b7`
**Causa raiz:** UI completamente ausente. `admin_catalog_screen` só tinha toggle availability + edit price. Nenhum botão para limpar `photo_url` quando uma imagem está errada/desactualizada.
**Fix:** Migration ([20260503050000_admin_reset_product_photo.sql](supabase/migrations/20260503050000_admin_reset_product_photo.sql)) com RPC `admin_reset_product_photo` SECURITY DEFINER + audit. UI: novo IconButton "🚫📷 Resetar foto" no trailing Row do produto, com confirm dialog e reload.

**Smoke:** before photo_url ✅ / after photo_url=NULL ✅ / needs_photo=true ✅ / audit log gravado ✅ / dados restaurados após teste ✅

---

## 🐛 Colaterais detectados

**Nenhum.** Os bugs estavam isolados; nenhum revelou outro problema durante a investigação ou execução.

---

## 📂 Ficheiros tocados (resumo)

### Backend (6 migrations novas)
- `supabase/migrations/20260503000000_create_order_v5_persist_coords.sql`
- `supabase/migrations/20260503010000_finalize_extends_restaurant.sql`
- `supabase/migrations/20260503020000_settlement_rpcs_sync_prod.sql`
- `supabase/migrations/20260503030000_partner_approval_workflow.sql`
- `supabase/migrations/20260503040000_partners_rls_approved_only.sql`
- `supabase/migrations/20260503050000_admin_reset_product_photo.sql`

### Flutter (6 ficheiros editados/criados)
- `lib/widgets/weekly_settlement_card.dart` (BUG 2 — 1 char)
- `lib/screens/driver_earnings_screen.dart` (BUG 3 — −267 linhas)
- `lib/stores/order_store.dart` (BUG 4 — guard finalize)
- `lib/screens/driver_map_screen.dart` (BUG 4 — bag UI)
- `lib/screens/register_partner_screen.dart` (BUG 7 — placeholder)
- `lib/screens/admin/admin_partners_pending_screen.dart` (BUG 6 — novo)
- `lib/screens/admin/admin_dashboard_screen.dart` (BUG 6 — nav)
- `lib/screens/admin/admin_catalog_screen.dart` (BUG 24 — botão)

### Documentação
- `.claude/.ai/reports/20260502_megafinal/01_bugs_criticos_analise.md` (Fase A)
- `.claude/.ai/reports/20260502_megafinal/01_bugs_criticos_report.md` (este)
- `.claude/.ai/todos/sessao_1_pending.md` (Sessão 1B push + email parceiro)

---

## 🔐 RPCs novas (todas SECURITY DEFINER + audit log)

| RPC | Onde | Acesso |
|-----|------|--------|
| `create_order` (v5) | migration BUG 1 | authenticated |
| `finalize_storeshopping_purchase` (extended) | migration BUG 4 | authenticated (driver gate) |
| `compute_driver_settlement` (sync) | migration BUG 5 | authenticated |
| `list_driver_orders_in_week` (sync) | migration BUG 5 | authenticated |
| `approve_partner` | migration BUG 6c | authenticated (admin gate) |
| `reject_partner` | migration BUG 6c | authenticated (admin gate) |
| `list_partners_by_status` | migration BUG 6c | authenticated (admin gate) |
| `is_admin` | migration BUG 6e | anon + authenticated |
| `admin_reset_product_photo` | migration BUG 24 | authenticated (admin gate) |

---

## 🚦 Validação pendente do Danilo

Antes de merge para `main`:
- [ ] BUG 2 — settlement card mostra valor real no driver real (não €0.00)
- [ ] BUG 3 — tela Ganhos sem secção duplicada (só card + tokens + priority)
- [ ] BUG 4 — driver fecha entrega de McDonald's/BK/KFC sem erro
- [ ] BUG 6 — admin abre nova tela "Aprovação de parceiros" e aprova/rejeita
- [ ] BUG 7 — partner registo com foto vazia salva com placeholder
- [ ] BUG 24 — admin reseta foto e botão produto recarrega lista

Smokes SQL já passaram em prod; falta validação UI no telemóvel real.

---

## 🎯 Atualizações sugeridas em `business_rules.md`

Após validação real, adicionar:

1. **Approval status** — todo parceiro novo entra `pending`. Cliente NÃO vê. Admin aprova via `admin_partners_pending_screen` ou RPC `approve_partner`. Rejeição requer motivo (`rejection_reason`).
2. **Foto parceiro opcional** — placeholder Bora-branded usado quando URL vazia.
3. **Coords obrigatórias em create_order** — `dropoff_lat/lng` SEMPRE obrigatórios; `pickup_lat/lng` obrigatórios para `restaurant/storeShopping/carryGroceries`; `sendPackage` tolera pickup NULL.
4. **Bag fee restaurant** — parceiro = 0€; não-parceiro = €0.30 fixo (não slider).

---

## ⏭️ Próximas sessões

- **Sessão 1B (push notifications)** — escopo removido desta sessão.
- **Sessão 1C (BUG 6f email parceiro)** — Resend integração + template aprovado/rejeitado.
- **Sessão 3 (saco mercado storeShopping)** — não tocada aqui (preservada para sessão dedicada).

---

✅ **Sessão 1/7 fechada com sucesso.** Push pronto para `autonomous-night-2026-04-29`.
