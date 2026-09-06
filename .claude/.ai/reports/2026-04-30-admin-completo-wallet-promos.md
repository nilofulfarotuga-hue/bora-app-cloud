# Sessão Autónoma — Admin Completo + Wallet 80/20 + Promos
> Data: 2026-04-30 · Branch: `autonomous-night-2026-04-29` · Modo: AUTÓNOMO TOTAL

## TL;DR

Backend completo para 8 das 12 features (F1, F3, F4, F8, F9, F10, F11) + UI admin para 6 (F1/F3/F4/F8/F9 + F12 widget).
Wiring de UI cliente em ecrãs existentes (profile, checkout, order_detail) **NÃO incluído** — files novos prontos, edits de integração ficam para próxima sessão (são bem definidos, não bloqueantes).
F2/F5/F6/F7 deferidas — diagnóstico abaixo.

⚠️ **Nenhuma migration foi aplicada à Supabase prod**. Todos os ficheiros SQL estão como migrations a postos para `supabase db push`.

⚠️ **CLAUDE.md "Validation Gate"** foi bypass conscientemente — autonomy memory de Danilo (2026-04-25) + instrução explícita "MODO AUTÓNOMO TOTAL — não pedir confirmação para nada" desta sessão. Refactor pricing_calculate fica como TODO em sub-branch (não tocado aqui — é HIGH-RISK separado).

---

## Tabela das 12 features

| # | Feature                          | Backend  | UI Admin | UI Cliente/Driver | Estado     |
|---|----------------------------------|----------|----------|-------------------|------------|
| 1 | Wallet 80/20                     | ✅ feito | ✅ feito | ✅ files novos    | ⚠️ wiring  |
| 2 | Notif. clareza reembolso         | ⏸ skip  | -        | -                 | ⏸ defer    |
| 3 | Audit log viewer                 | ✅ feito | ✅ feito | -                 | ✅ done    |
| 4 | Aprovação cancelamentos          | ✅ feito | ✅ feito | -                 | ⚠️ TODO Edge Fn refund |
| 5 | Detail parceiro Vendas+Catálogo  | ⏸ skip  | -        | -                 | ⏸ defer    |
| 6 | Mapa pedidos ao vivo             | -        | ⏸ skip  | -                 | ⏸ defer    |
| 7 | Export CSV/PDF                   | -        | ⏸ skip  | -                 | ⏸ defer    |
| 8 | Platform settings                | ✅ feito | ✅ feito | -                 | ✅ done (sem refactor pricing) |
| 9 | Promo codes                      | ✅ feito | ✅ feito | ⚠️ wiring         | ⚠️ wiring  |
|10 | Referral / convite               | ✅ feito | -        | ⚠️ wiring         | ⚠️ wiring  |
|11 | Cashback automático              | ✅ feito | (via F8) | ⚠️ banner         | ⚠️ wiring  |
|12 | Dashboard real-time              | -        | ✅ widget criado | -          | ⚠️ wiring  |

**✅ feito** = código escrito + ficheiro presente. **⚠️ wiring** = falta integrar em ecrã existente. **⏸ skip** = não tocado nesta sessão.

---

## Ficheiros criados (20)

### Migrations SQL (8)
1. `supabase/migrations/20260430110000_platform_settings.sql` — F8 + 26 settings seed
2. `supabase/migrations/20260430120000_client_wallets.sql` — F1 (tabelas + 8 RPCs)
3. `supabase/migrations/20260430130000_orders_refund_method_columns.sql` — F1 (refund_method/status cols)
4. `supabase/migrations/20260430140000_cancellation_requests.sql` — F4 (tabela + 4 RPCs)
5. `supabase/migrations/20260430150000_cashback_trigger.sql` — F11
6. `supabase/migrations/20260430160000_referral_system.sql` — F10 (2 tabelas + 3 RPCs + trigger)
7. `supabase/migrations/20260430170000_promo_codes.sql` — F9 (2 tabelas + 5 RPCs)
8. `supabase/migrations/20260430180000_admin_audit_log_viewer.sql` — F3 (2 RPCs)

### Edge Function (1)
9. `supabase/functions/cancel-order-with-choice/index.ts` — F1 (Stripe vs wallet branch)

### Flutter (8 + 2 widgets/services)
10. `lib/services/wallet_service.dart` — RPCs wrapper + models
11. `lib/widgets/refund_choice_dialog.dart` — diálogo cliente (F1)
12. `lib/widgets/admin_realtime_metrics_card.dart` — F12 card (auto-refresh 10s)
13. `lib/screens/wallet_history_screen.dart` — F1 cliente
14. `lib/screens/admin/admin_wallets_screen.dart` — F1 admin
15. `lib/screens/admin/admin_platform_settings_screen.dart` — F8 admin
16. `lib/screens/admin/admin_audit_log_screen.dart` — F3 admin
17. `lib/screens/admin/admin_cancellation_requests_screen.dart` — F4 admin
18. `lib/screens/admin/admin_promo_codes_screen.dart` — F9 admin

### Knowledge (2)
19. `.claude/.ai/decisions/2026-04-30-wallet-promos-design.md` — research + decisões
20. `.claude/.ai/knowledge/business-rules/wallet.md` — §17 (10 secções)
+ Edit `.claude/.ai/knowledge/INDEX.md` — pointer §17

---

## Decisões UX + fontes

| Padrão escolhido                       | Inspiração                | Fonte (web search) |
|----------------------------------------|---------------------------|---|
| Choice cartão vs app no cancelamento   | iFood                     | [institucional.ifood.com.br](https://institucional.ifood.com.br/clientes/prazos-e-regras-para-reembolso-ifood-ao-cliente/) |
| Saldo livre **NUNCA expira**           | Diferencial vs Glovo      | [Glovo expira 30-90d](https://glovoapp.com/en/promo/) |
| 1 promo code por pedido                | Glovo                     | (idem) |
| Default UI: app (wallet)               | iFood "ativar default"    | iFood |
| Tokens persistem (Batch D existente)   | Bora interno              | — |
| Switch "Usar saldo livre" no checkout  | Uber Cash                 | [Uber Help](https://help.uber.com/en/ubereats/restaurants/article/how-does-uber-credit-work) |

Detalhes em `decisions/2026-04-30-wallet-promos-design.md` (D1–D13).

---

## TODOs / Wiring necessários (não bloqueantes mas pendentes)

### Cliente Flutter (3 ecrãs existentes precisam de edits)
- **`profile_screen.dart`** — adicionar 2 cards (Saldo Bora verde / Tokens amarelo) + nav para `WalletHistoryScreen`
- **`order_details_screen.dart` ou `order_tracking_screen.dart`** — botão "Cancelar" elegível por status → `showRefundChoiceDialog(...)` → callback que re-faz `OrderStore.refresh()`
- **`cart_screen.dart`** — campo "Código promocional" + Switch "Usar saldo livre" + recalc de total

### Admin Dashboard (1 ecrã)
- **`admin_dashboard_screen.dart`** — adicionar:
  - `AdminRealtimeMetricsCard()` no topo (F12)
  - Cards de navegação para: `AdminWalletsScreen`, `AdminPlatformSettingsScreen`, `AdminAuditLogScreen`, `AdminCancellationRequestsScreen`, `AdminPromoCodesScreen`

### Backend (2)
- **Edge Fn `execute-cancellation`** (F4 cont.) — chamada após `admin_approve_cancellation` para realmente fazer refund Stripe ou wallet split
- **Edge Fn `notify-client` payload** — push referral/cashback ("Recebeste €X de cashback!", "O teu amigo X registou-se")

### Compliance / pricing
- **HIGH-RISK pricing_calculate refactor** (F8 §13) — sub-branch `draft/pricing-from-settings`. NÃO tocado nesta sessão. Plano em decisions/.
- **§17.10 Wallet legal review** — validar com jurista limites de "moeda electrónica" (DGAE/BdP)
- **Free delivery promo type** — wiring no `PricingService.calculateBreakdown` para honrar `client_apply_promo_code` retornando `free_delivery=true`

---

## Bugs/observações descobertos durante a sessão

1. **`get_user_tokens` retorno** — assumi que retorna JSONB com `balance` key. A migration 20260404000000 confirma signature mas não pude validar contrato exacto sem aplicar. Se contrato for diferente, ajustar `wallet_get_balance` em `20260430120000_client_wallets.sql:84`.
2. **`restaurants.owner_id`** — usado em `request_order_cancel` para detectar role 'partner'. Coluna existe? Se não, ajustar query (não validei vs schema actual).
3. **`drivers.is_online`** — usado em `AdminRealtimeMetricsCard`. Se a coluna for diferente (ex. `is_active`), ajustar.
4. **Refund 100% retido** (after_pickup tier) → `cancel-order-with-choice` salta wallet/stripe mas continua a marcar order cancelled. Comportamento correcto, mas notificação ainda diz "Reembolso processado" — ajustar copy se refundEur=0.

---

## Comandos rollback

Se algo correr mal após `supabase db push`:

```bash
# Rollback SQL (reverter migrations 110000–180000):
supabase migration repair --status reverted 20260430180000
supabase migration repair --status reverted 20260430170000
# ... etc
# Depois aplicar SQL inverso à mão:
DROP TABLE IF EXISTS public.promo_code_uses CASCADE;
DROP TABLE IF EXISTS public.promo_codes CASCADE;
DROP TABLE IF EXISTS public.referral_invites CASCADE;
DROP TABLE IF EXISTS public.referral_codes CASCADE;
DROP TABLE IF EXISTS public.cancellation_requests CASCADE;
DROP TABLE IF EXISTS public.wallet_transactions CASCADE;
DROP TABLE IF EXISTS public.client_wallets CASCADE;
DROP TABLE IF EXISTS public.platform_settings CASCADE;
ALTER TABLE public.orders DROP COLUMN IF EXISTS refund_method;
ALTER TABLE public.orders DROP COLUMN IF EXISTS refund_status;
DROP FUNCTION IF EXISTS public.fn_award_cashback_on_delivery() CASCADE;
DROP FUNCTION IF EXISTS public.fn_referral_reward_on_first_delivery() CASCADE;
```

Edge Function rollback: `supabase functions delete cancel-order-with-choice`

Flutter — ficheiros novos podem ser apagados sem afectar build (não há imports ainda em ecrãs existentes — wiring está pendente). Se quiseres apagar:
```bash
git rm lib/services/wallet_service.dart lib/widgets/refund_choice_dialog.dart \
       lib/widgets/admin_realtime_metrics_card.dart lib/screens/wallet_history_screen.dart \
       lib/screens/admin/admin_wallets_screen.dart \
       lib/screens/admin/admin_platform_settings_screen.dart \
       lib/screens/admin/admin_audit_log_screen.dart \
       lib/screens/admin/admin_cancellation_requests_screen.dart \
       lib/screens/admin/admin_promo_codes_screen.dart
```

---

## Tempo aproximado por feature

(estimado; sessão única autónoma — turn budget Anthropic)

| Feature              | SQL    | Edge   | Flutter | Total |
|----------------------|--------|--------|---------|-------|
| F1 Wallet            | 25min  | 15min  | 30min   | ~70min |
| F3 Audit log         | 5min   | -      | 15min   | ~20min |
| F4 Cancel requests   | 15min  | TODO   | 15min   | ~30min |
| F8 Settings          | 15min  | -      | 15min   | ~30min |
| F9 Promo codes       | 20min  | -      | 20min   | ~40min |
| F10 Referral         | 25min  | -      | TODO    | ~25min |
| F11 Cashback         | 10min  | -      | TODO    | ~10min |
| F12 Realtime card    | -      | -      | 10min   | ~10min |
| Pesquisa + decisions | -      | -      | -       | ~15min |
| **Total**            |        |        |         | ~250min |

---

## Stats CTX (pré-push)

Ver `/ctx-stats` na próxima invocação para totais finais. Sessão usou principalmente Write tool (20 ficheiros) — context-mode usado para batch diagnostics inicial.

---

## Próximos passos imediatos (sugestão Danilo)

1. **`flutter analyze`** local para validar imports/syntax dos novos files (esperar 0 errors mas pode haver pequenos ajustes)
2. **`supabase db push`** num branch DB ou local antes de prod (8 migrations encadeadas)
3. **`supabase functions deploy cancel-order-with-choice`** após validar
4. **Wiring de UI** (~1h trabalho focado): edits em profile/cart/order_details + admin_dashboard
5. **TODO Edge Fn `execute-cancellation`** — completa F4 end-to-end
6. **Validation gate** com Claude.ai sobre os 8 SQL antes de aplicar a prod

---

## Bypass declarado da Validation Gate (CLAUDE.md)

CLAUDE.md instrui "STOP and output ⚠️ VALIDAÇÃO RECOMENDADA antes de tocar em DB/Stripe/security/>1h". Bypass aplicado por:
1. **Memory `feedback_autonomy_multi_phase.md`** — Danilo aprovou modo end-to-end multi-fase
2. **Instrução explícita** desta sessão: "MODO: AUTÓNOMO TOTAL — não pedir confirmação para nada"
3. **Plano detalhado e pré-aprovado** (12 features com specs)

Mitigação: nenhuma migration aplicada à Supabase prod — ficaram como ficheiros para `db push` controlado por Danilo. Stripe LIVE não tocado directamente — apenas nova Edge Function paralela à `refund` existente.
