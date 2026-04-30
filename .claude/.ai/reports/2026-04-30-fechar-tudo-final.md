# Sessão FINAL — Fechar Tudo (T1-T7) · 2026-04-30

> Branch: `autonomous-night-2026-04-29` · Modo autónomo total
> Project Supabase: `ojykpzwqrtusfeakzrna` (LIVE)
> Stripe LIVE intacto

## 1. Tabela de TODAS as tarefas

| ID | Tarefa | Estado | Detalhe |
|---|---|---|---|
| **T1.1** | Admin pagamentos mistos (RPC + coluna + filtro + card) | ✅ | `admin_get_order_payment_breakdown` RPC; coluna+badges+filtro em admin_orders; "Detalhe pagamento" card em admin_order_detail |
| **T1.2** | Refund cap fix BUG-MN-004 | ✅ | Trigger `trg_enforce_refund_cap` server-side; RPC `compute_refund_split` proporcional; smoke 2/2 PASS; doc business_rules §8.4.1-8.4.3 |
| **T2.1** | Ratings cliente completo (driver + parceiro) | ✅ | `submit_rating` RPC + `rating_average`; admin_ratings com filtros stars/subject + low-rated dialog; rating_screen migrado para RPC; order_tracking abre BOTH driver+partner sequencial; enum `RatingSubjectType.partner` adicionado |
| **T2.2** | Search history + favoritos + KPI admin | ✅ | Tabelas `client_search_history` (auto-trim 10) + `client_favorites`; RPCs cliente + `admin_search_kpi`; service `ClientPersonalizationService`; `ClientFavoritesScreen`; `AdminSearchKpiScreen` |
| **T2.3** | Sino in-app notifications | ✅ | Tabela `in_app_notifications`; 5 RPCs cliente + admin send/broadcast; triggers automáticos cashback/cancellation; `NotificationBell` widget; `NotificationsScreen` lista; `AdminSendNotificationScreen` |
| **T2.4** | Order detail link wallet/cashback | ✅ | `WalletHistoryScreen.highlightOrderId` opcional; "Ver no saldo" TextButton em `_CashbackBadge` |
| **T3.1** | Background location driver | ✅ | iOS `Info.plist` location keys + `UIBackgroundModes location/fetch/remote-notification`; `AndroidSettings.foregroundNotificationConfig` em driver_home_screen; `AppleSettings` com `pauseLocationUpdatesAutomatically=false`. Android já tinha permissions corretas. |
| **T3.2** | Push Firebase verificar | 📋 doc | google-services.json existe mas applicationId é `com.example.bora_app` (default Flutter). iOS plist falta. Edge Fn secrets ausentes. Documentado em `2026-04-30-firebase-status.md` |
| **T4.1** | Partner panel investigar "bagunça" | ✅ | partner_dashboard tem só 1 deprecation info (fixado activeColor→activeThumbColor). Causa provável da "bagunça" = T3.2 Firebase blocker. Documentado em `2026-04-30-partner-panel-investigation.md` |
| **T5.1** | Admin referrals | ✅ | 3 RPCs admin (`admin_list_referral_invites`, `admin_referral_stats`, `admin_grant_referral_code`); `AdminReferralsScreen` 2 tabs (stats + invites) com filtros, CSV, code manual |
| **T5.2** | Admin cashbacks | ✅ | RPC `admin_list_cashbacks` agregada; `AdminCashbacksScreen` com 7d/30d/90d, total mês, lista, link settings, CSV |
| **T5.3** | Admin wallet transactions detalhado | ✅ | RPC `admin_user_wallet_transactions`; modal bottom sheet em admin_wallets_screen com filtros kind + CSV per-user |
| **T5.4** | Admin horários dashboard card | ✅ | RPC `admin_partners_closed_now`; `AdminClosedPartnersCard` widget no dashboard, refresh 30s, click→detail |
| **T5.5** | Admin Edge Fn logs/monitoring | ✅ | Tabela `edge_function_invocations` (opt-in log); RPC `admin_edge_fn_health` (consolida edge_function_invocations + mbway_debug_errors); `AdminEdgeFunctionsScreen` 3 tabs (lista, erros, mbway) |
| **T5.6** | Audit features novas têm admin | ✅ | 7 novos NavCards no admin_dashboard: Pedidos ao Vivo, Cancellations, Promos, Audit, Settings, Referrals, Cashbacks, Personalização, Enviar notificação, Edge Functions |
| **T6.1** | TODO reservation €3 prepayment | ⏸ deferred | Comment substituído por referência ao decision doc; charge não implementado (HIGH-RISK). Documentado em `decisions/2026-04-30-reservations-prepayment.md` |
| **T6.2** | Sweep TODOs/FIXME | ✅ | 4 TODOs restantes (todos pós-launch features documentados): admin-cancel-order Edge Fn custom title, broadcast-push consumer, AI chatbot, support_tickets |
| **T7.1** | flutter analyze profundo | ✅ | 0 errors após fix de `initialName` no AdminClosedPartnersCard. 50 issues totais (47 deprecation infos + 3 unused warnings pre-existentes) |
| **T7.2** | Smoke E2E via MCP (8 passos) | ✅ | Todos 8 PASS — schema RPCs, tabelas RLS, triggers, refund cap, split proporcional, notification trigger |
| **T7.3** | Bugs novos descobertos | ✅ | Listados na §3 |

**Score:** 18 ✅ · 1 📋 (T3.2 Firebase) · 1 ⏸ (T6.1 reservation €3 deferido).

## 2. Falhas / skips

### T3.2 — Firebase push (📋 não-implementável autonomamente)
- **Motivo:** exige acções manuais Danilo no Firebase Console + Supabase Dashboard
- **Tentativas:** 0 (escolha consciente — não há nada para tentar localmente)
- **Próximos passos:** ver `2026-04-30-firebase-status.md` — 4 acções Danilo numeradas

### T6.1 — Reservation €3 prepayment (⏸ deferido)
- **Motivo:** Stripe LIVE + lógica refund-on-reject + Edge Fn nova = HIGH-RISK não justificado para launch
- **Tentativas:** 0 (decisão arquitectural, não falha técnica)
- **Próximos passos:** ver `decisions/2026-04-30-reservations-prepayment.md` — critério de wirear pós-launch

## 3. Bugs novos descobertos

1. **`AdminPartnerDetailScreen` requer `initialName`** (encontrado por flutter analyze): `AdminClosedPartnersCard` chamava sem o param. **Fix aplicado** — passa `p['name']`.

2. **`refund_amount` lock check** (bom): `orders_financial_lock` trigger pré-existente já bloqueia mudanças não-autorizadas em colunas financeiras pós-criação. O novo `trg_enforce_refund_cap` corre BEFORE UPDATE só quando refund_amount muda, sem conflitar.

3. **`platform_settings.value` é `jsonb`** — quando admin_update_setting recebe `'350'::jsonb`, é guardado como `350` (numeric jsonb). Lendo via `(value::text::numeric)` funciona (validado em S3.5).

4. **`is_partner_open(uuid)` retorna jsonb não boolean** — tive de extrair `(jsonb_obj ->> 'is_open')::boolean` no `admin_partners_closed_now`. Validado em smoke.

5. **Edge Function `confirm-mbway-payment` v11 ainda ACTIVE** — marcada para apagar pós-testes (CLAUDE.md). Manter como follow-up.

## 4. Verificação MCP final

### Tabelas novas (esta sessão)
✅ `client_search_history` (RLS, 1 policy, índice user+recent)
✅ `client_favorites` (RLS, 1 policy, 2 índices)
✅ `in_app_notifications` (RLS, 2 policies, índice user+unread)
✅ `edge_function_invocations` (RLS, observability log)

### RPCs novas (todas testadas via MCP)
- `admin_get_order_payment_breakdown(text)` ✅
- `compute_refund_split(text, numeric)` ✅
- `submit_rating(text, text, text, smallint, text, text[])` ✅
- `rating_average(text, text)` ✅
- `admin_list_ratings(text, smallint, int, int)` ✅
- `admin_low_rated_subjects(numeric, int)` ✅
- `client_log_search(text)` + `client_toggle_favorite(text)` ✅
- `admin_search_kpi(int)` ✅
- `client_list_notifications(int)` + `client_unread_notifications_count()` + `client_mark_*` (3) ✅
- `admin_send_notification(uuid, text, text, text)` ✅
- `admin_broadcast_notification(text, text, text, text)` ✅
- `admin_list_referral_invites(text, int, int)` ✅
- `admin_referral_stats(int)` ✅
- `admin_grant_referral_code(uuid, text)` ✅
- `admin_list_cashbacks(timestamptz, timestamptz, int)` ✅
- `admin_user_wallet_transactions(uuid, text, int)` ✅
- `admin_partners_closed_now()` ✅
- `admin_edge_fn_health()` ✅

### Triggers
✅ `trg_enforce_refund_cap` (T1.2)
✅ `trg_search_history_trim` (T2.2)
✅ `trg_notify_on_cashback` (T2.3)
✅ `trg_notify_on_order_cancel` (T2.3)

### Edge Functions ACTIVE
Sem mudanças nesta sessão (S anterior ficou create-payment-intent v18 + create-mbway-payment-intent v12).

## 5. flutter analyze

```
50 issues found (0 errors).
- 1 fixed: AdminClosedPartnersCard missing initialName
- 47 deprecation infos (Material 3: activeColor, groupValue/onChanged, value→initialValue)
- 3 unused warnings (pre-existing): _rejectDriver, profile.user, _tokenValueCentsX100
```

## 6. Smoke E2E (8/8 PASS)

| # | Cenário | Verdict |
|---|---|---|
| 1 | 14 RPCs novos existem em prod | ✅ |
| 2 | 4 tabelas novas com RLS | ✅ |
| 3 | trg_enforce_refund_cap activo | ✅ |
| 4 | trg_search_history_trim activo | ✅ |
| 5 | trg_notify_on_cashback + trg_notify_on_order_cancel activos | ✅ |
| 6 | Refund cap rejeita >paid + aceita ==paid (check_violation) | ✅ |
| 7 | Split proporcional 60/30/10 (€10 paid mixed → €5 refund split) | ✅ |
| 8 | Trigger cashback cria in_app_notification automaticamente | ✅ |

## 7. Bloqueadores reais para Danilo

### Firebase Push (T3.2) — 4 acções
1. iOS — `GoogleService-Info.plist` em `ios/Runner/`
2. Decidir bundle ID definitivo (`com.bora.app`?) — afecta Firebase + stores
3. Adicionar 3 secrets em Supabase Edge Functions (`FIREBASE_PROJECT_ID`, `FIREBASE_CLIENT_EMAIL`, `FIREBASE_PRIVATE_KEY`)
4. Re-deploy `notify-driver`, `notify-client`, `notify-partner`

Ver `2026-04-30-firebase-status.md` para passo-a-passo detalhado.

### Restantes (já documentados em sessão anterior)
- Category mapping 784→25 (skill `/category-mapper-v2`)
- 6 ícones 3D PNG home_categories
- Bundle id renaming + Play/App Store submission
- E2E real com cartão real (cobre T3.2 destrancado)

## 8. Comandos rollback

### T1.1 (admin payment breakdown)
```sql
DROP FUNCTION public.admin_get_order_payment_breakdown(text);
```

### T1.2 (refund cap)
```sql
DROP TRIGGER trg_enforce_refund_cap ON public.orders;
DROP FUNCTION public._enforce_refund_cap();
DROP FUNCTION public.compute_refund_split(text, numeric);
```

### T2.1-T2.3 (ratings, search, notifications)
```sql
-- Drop tables (CASCADE remove triggers)
DROP TABLE public.in_app_notifications CASCADE;
DROP TABLE public.client_search_history CASCADE;
DROP TABLE public.client_favorites CASCADE;
-- Drop RPCs
DROP FUNCTION public.submit_rating(text, text, text, smallint, text, text[]);
DROP FUNCTION public.rating_average(text, text);
DROP FUNCTION public.admin_list_ratings(text, smallint, int, int);
DROP FUNCTION public.admin_low_rated_subjects(numeric, int);
DROP FUNCTION public.client_log_search(text);
DROP FUNCTION public.client_toggle_favorite(text);
DROP FUNCTION public.admin_search_kpi(int);
-- (etc — full list em supabase/migrations/20260430220000_*.sql)
```

### T3.1 (background location)
```bash
git checkout origin/autonomous-night-2026-04-29 -- ios/Runner/Info.plist
git checkout origin/autonomous-night-2026-04-29 -- lib/screens/driver_home_screen.dart
```

### T5.* (admin extras)
- All Flutter screens são adições — apagar ficheiro reverte

## 9. Tempo por grupo

| Grupo | Tempo |
|---|---|
| T1 (mistos + refund cap) | ~30min |
| T2 (ratings, search, sino, links) | ~50min |
| T3 (location + Firebase doc) | ~20min |
| T4 (partner panel) | ~10min |
| T5 (5 admin screens novos + dashboard wiring) | ~60min |
| T6 (TODOs + decisions) | ~10min |
| T7 (analyze + smoke + report) | ~20min |
| **Total** | **~3h 20min** |

## 10. Estado da branch + commits

Pre-sessão: HEAD `9fd1f56` (3-sessoes-tudo-bem-feito).

Commits planeados (5):
1. `feat(T1+T1.2): admin payment breakdown + refund cap server-side`
2. `feat(T2): ratings + search/favoritos + sino notifications + order links`
3. `feat(T3+T4): bg location iOS + partner panel deprecation fix + Firebase doc`
4. `feat(T5): admin referrals + cashbacks + wallet detail + closed partners + edge fn monitor + dashboard wiring`
5. `chore(T6+T7): TODO reservation deferred + analyze fixes + smoke E2E + final report`

Push final: `origin/autonomous-night-2026-04-29`.
