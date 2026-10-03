# Auditoria Painel Admin — 2026-05-18

> Inventário 100% estático de todos os ecrãs admin (`bora_app/lib/screens/admin/`).
> Análise: RPCs ↔ migrations, queries Supabase, TODOs, catch vazios, handlers nulos, PT-BR.
> **Sem alterações de código**. Base para fix-list e futuro chat IA admin.

---

## Resumo executivo

| Métrica | Valor |
|---|---|
| Total ficheiros em `lib/screens/admin/` | **49** |
| Ecrãs (full Screen) | **46** |
| Dialogs auxiliares | **2** (`_admin_cancel_order_dialog`, `_admin_partner_edit_dialog`) |
| Helper compartilhado | **1** (`_admin_rpc_errors.dart`) |
| Linhas totais | **23.493** |
| RPCs únicas chamadas | **62** |
| Tabelas/views únicas | **20** |
| Edge functions invocadas | **2** (`admin-cancel-order`, `analyze-conversations`) |
| Migrations SQL no projecto | **219** |
| Funções definidas nas migrations | **235** |
| RPCs chamadas no código **mas não existentes** | **1** 🔴 |
| Ficheiros com TODO/FIXME em comentário | **7** (notas, não bloqueantes) |
| `catch (_) {}` (engolem erros silenciosamente) | **3** |
| Strings PT-BR no admin | **2** |
| `onPressed: null` / `onPressed: () {}` | **0** |
| `UnimplementedError` | **0** |
| Ecrãs **órfãos** (não ligados de lado nenhum) | **3** |
| Ecrãs registados no dashboard | **37 / 46** (~80%) |

**Estado global do painel admin: 🟢 SAUDÁVEL.**
Estrutura sólida, 1 bug real (RPC inexistente), 3 ecrãs órfãos, alguns catch silenciosos, e duas strings PT-BR a corrigir. Sem ecrãs quebrados nem features hardcoded por implementar.

---

## Arquitectura geral

- **Entry point:** [main.dart](bora_app/lib/main.dart) regista rota `/admin` → `AdminDashboardScreen`
- **Dashboard:** [admin_dashboard_screen.dart](bora_app/lib/screens/admin/admin_dashboard_screen.dart) — 978 linhas, navega para 37 sub-ecrãs via tiles
- **Serviços de apoio:**
  - [services/admin_audit_service.dart](bora_app/lib/services/admin_audit_service.dart)
  - [services/admin/admin_driver_service.dart](bora_app/lib/services/admin/admin_driver_service.dart)
  - [services/admin/admin_order_service.dart](bora_app/lib/services/admin/admin_order_service.dart)
  - [services/auth_admin_service.dart](bora_app/lib/services/auth_admin_service.dart)
  - [services/admin_export_service.dart](bora_app/lib/services/admin_export_service.dart)
  - [services/admin_push_service.dart](bora_app/lib/services/admin_push_service.dart)
- **Widgets reutilizáveis:**
  - [widgets/admin_realtime_metrics_card.dart](bora_app/lib/widgets/admin_realtime_metrics_card.dart)
  - [widgets/admin_closed_partners_card.dart](bora_app/lib/widgets/admin_closed_partners_card.dart)
  - [widgets/admin_reservations_today_card.dart](bora_app/lib/widgets/admin_reservations_today_card.dart)
- **Helper:** `_admin_rpc_errors.dart` (39 linhas) — formatter genérico de erros RPC para SnackBars

---

## Inventário completo (46 ecrãs)

Legenda: **✅** OK · **⚠️** Parcial (TODO/strings/catch silencioso) · **❌** Quebrado · **👻** Órfão (não acessível pela UI)

| # | Ecrã | Linhas | Função | Estado | Notas |
|---|---|---:|---|:---:|---|
| 1 | `admin_advanced_kpis_screen` | 176 | Hot zones + ticket médio + conversão | ✅ | T13 |
| 2 | `admin_audit_log_screen` | 238 | Histórico de Acções (log audit) | ⚠️ | `catch (_) {}` em L36 |
| 3 | `admin_broadcasts_history_screen` | 234 | Histórico de broadcasts | ✅ | Acessível só via `admin_send_notification_screen` |
| 4 | `admin_cancellation_requests_screen` | 197 | Aprovar/rejeitar cancelamentos | ✅ | — |
| 5 | `admin_cashbacks_screen` | 173 | Lista pagamentos cashback + totais | ✅ | T5.2 |
| 6 | `admin_catalog_screen` | 331 | Edição em massa preços + disponibilidade | ✅ | — |
| 7 | `admin_category_mapping_screen` | 293 | Editor de mapeamento de categorias raw→canónicas | ✅ | — |
| 8 | `admin_clients_screen` | 661 | Lista/ban/block clientes + histórico | ✅ | — |
| 9 | `admin_complaints_screen` | 169 | Reclamações + mudar status | ✅ | — |
| 10 | `admin_crosstalk_screen` | 835 | Comunicação Robô A ↔ Robô B + reply | ✅ | 5F B5 / 5F-α / 5F-β |
| 11 | `admin_dashboard_screen` | 978 | Painel principal (tiles + métricas) | ✅ | Liga a 37 sub-ecrãs |
| 12 | `admin_dispatch_settings_screen` | 428 | Editar parâmetros do dispatch engine | ✅ | — |
| 13 | `admin_driver_approval_screen` | 834 | Aprovar drivers em onboarding | ⚠️ | `catch (_) {}` em L406; usa tabela `drivers` directamente (sem RPC) |
| 14 | `admin_driver_detail_screen` | 1260 | Detalhe driver: balance, transacções, banimentos | ✅ | Sub-ecrã (drivers / approval / global search) |
| 15 | `admin_driver_payments_screen` | 291 | Pagamentos de entregadores semanais | ✅ | View: `v_driver_weekly_earnings` |
| 16 | `admin_drivers_screen` | 283 | Gestão de Entregadores | ✅ | Usa tabela `drivers` directamente |
| 17 | `admin_edge_functions_screen` | 164 | Monitor health das Edge Functions | ✅ | T5.5 |
| 18 | `admin_global_search_screen` | 511 | Busca global cross-entidade | ⚠️ | PT-BR "busca" em L294 |
| 19 | `admin_knowledge_screen` | 589 | Stats da knowledge base RAG | ✅ | — |
| 20 | `admin_live_orders_map_screen` | 525 | Mapa pedidos+drivers em tempo real | ✅ | — |
| 21 | `admin_notifications_inbox_screen` | 438 | Inbox de notificações admin | ✅ | **Sem AppBar.title literal** (provavelmente dinâmico) |
| 22 | `admin_order_detail_screen` | 732 | Detalhe pedido + audit + refund info | ⚠️ | 1 TODO (docstring scope) |
| 23 | `admin_orders_screen` | 705 | Gestão de Pedidos (lista + filtros) | ⚠️ | 1 TODO (chips PT-BR) |
| 24 | `admin_orphan_payments_screen` | 186 | Pagamentos órfãos (Stripe sem ordem) | ✅ 👻 | **Não ligado a partir do dashboard** |
| 25 | `admin_partner_detail_screen` | 1644 | Detalhe parceiro: produtos, fotos, abrir/fechar | ✅ | Maior ficheiro do painel |
| 26 | `admin_partner_payouts_screen` | 911 | Repasses semanais aos parceiros | ✅ | — |
| 27 | `admin_partner_settlements_screen` | 386 | Acerto Semanal Parceiros (€2 menu credits) | ✅ | — |
| 28 | `admin_partners_pending_screen` | 340 | Aprovar parceiros pendentes | ✅ | BUG 6d completo |
| 29 | `admin_partners_screen` | 189 | Lista parceiros/restaurantes | ✅ | — |
| 30 | `admin_pending_actions_screen` | 728 | Aprovar/finalizar/rejeitar actions críticas | ✅ | Invoca `admin-cancel-order` |
| 31 | `admin_platform_settings_screen` | 150 | Editar `platform_settings` (high-risk) | ✅ | — |
| 32 | `admin_promo_codes_screen` | 200 | CRUD promo codes | ✅ | — |
| 33 | `admin_ratings_screen` | 555 | Sujeitos com média < 2.0 (≥3 ratings) | ✅ | — |
| 34 | `admin_receipts_screen` | 760 | Reembolsos / talões / OCR flagged | ⚠️ 👻 | 2 TODOs (placeholders + decisão flag); **não ligado** |
| 35 | `admin_referrals_screen` | 313 | Invites + stats + código manual | ✅ | T5.1 |
| 36 | `admin_reservations_metrics_screen` | 517 | Métricas Reservas Pro | ✅ | — |
| 37 | `admin_reservations_screen` | 780 | Lista de reservas + atribuir mesa | ⚠️ | `catch (_) {}` em L711 |
| 38 | `admin_search_kpi_screen` | 155 | Top searches + parceiros favoritados | ✅ | T2.2 |
| 39 | `admin_send_notification_screen` | 266 | Envio de broadcasts / push individual | ✅ | — |
| 40 | `admin_settlements_screen` | 404 | Settlements semanais drivers | ⚠️ | 1 TODO (docstring); **chama RPC inexistente?** ver §RPCs |
| 41 | `admin_skill_suggestions_metrics_screen` | 451 | 4 gráficos métricas IA | ✅ | 5G B6 |
| 42 | `admin_skill_suggestions_screen` | 1727 | Propostas IA (aprovar/rejeitar/rollback) | ❌ | **Chama RPC `admin_reject_skill_suggestion` que não existe** (L754). RPC real: `admin_bulk_reject_skill_suggestions` |
| 43 | `admin_support_stats_screen` | 366 | Stats robô suporte IA | ✅ | Refere RPC `admin_get_support_stats` no doc (a confirmar) |
| 44 | `admin_support_tickets_screen` | 253 | Lista tickets suporte (mínimo) | ✅ 👻 | **Não ligado** ao dashboard |
| 45 | `admin_tokens_screen` | 267 | Grant/revoke tokens Bora | ⚠️ | PT-BR "usuário" em L183 |
| 46 | `admin_wallets_screen` | 561 | Histórico transacções de carteira | ✅ | — |

**Dialogs e helpers (3):**
- `_admin_cancel_order_dialog.dart` (175L) — diálogo para cancelar pedido com motivo
- `_admin_partner_edit_dialog.dart` (125L) — diálogo para editar dados básicos do parceiro
- `_admin_rpc_errors.dart` (39L) — helper de formatação de erros RPC

---

## Bugs encontrados (detalhe)

### 🔴 P1 — RPC inexistente
**Ficheiro:** [admin_skill_suggestions_screen.dart:754](bora_app/lib/screens/admin/admin_skill_suggestions_screen.dart#L754)
```dart
await _supabase.rpc('admin_reject_skill_suggestion', params: { ... });
```
- A função `admin_reject_skill_suggestion` **não existe** em nenhuma migration do projecto.
- Existe `admin_bulk_reject_skill_suggestions` (`20260507071100_5g_b2_rpcs_new.sql`) e é chamada correctamente em L309 do mesmo ficheiro.
- **Impacto:** botão de rejeição individual falha com erro `function does not exist`.
- **Fix sugerido:** ou (a) refactor para usar a versão bulk com 1 item, ou (b) criar migration `admin_reject_skill_suggestion(p_id uuid, p_reason text)`.

### 🟡 P2 — Catch silenciosos (3 ocorrências)
Engolem erros sem log nem feedback ao admin:
- [admin_audit_log_screen.dart:36](bora_app/lib/screens/admin/admin_audit_log_screen.dart#L36) — `} catch (_) {}`
- [admin_driver_approval_screen.dart:406](bora_app/lib/screens/admin/admin_driver_approval_screen.dart#L406) — `} catch (_) {}`
- [admin_reservations_screen.dart:711](bora_app/lib/screens/admin/admin_reservations_screen.dart#L711) — `} catch (_) {}`

Em todos os casos a operação pode falhar silenciosamente e o admin não percebe.

### 🟡 P2 — Strings PT-BR no painel (oficial = PT-PT)
- [admin_global_search_screen.dart:294](bora_app/lib/screens/admin/admin_global_search_screen.dart#L294) — `'A **busca** cobre clientes...'` → PT-PT: *pesquisa*
- [admin_tokens_screen.dart:183](bora_app/lib/screens/admin/admin_tokens_screen.dart#L183) — `hintText: 'Buscar **usuário**'` → PT-PT: *Procurar utilizador*

> Nota: já existem variantes PT-PT consistentes no resto do painel (`Entregadors`, `Configurações`). Estes 2 ficheiros estão dessincronizados.

### 🟠 P3 — TODOs em código (7 ocorrências — todos não-bloqueantes)
- [admin_orders_screen.dart:477](bora_app/lib/screens/admin/admin_orders_screen.dart#L477) — chips de tipo de serviço (PT-BR mencionado, mas só comentário)
- [admin_order_detail_screen.dart:11](bora_app/lib/screens/admin/admin_order_detail_screen.dart#L11) — docstring scope ("Pagamento — método, status, refund info")
- [admin_receipts_screen.dart:5](bora_app/lib/screens/admin/admin_receipts_screen.dart#L5) — *"abas são placeholder nesta versão mínima — serão expandidas em sessão"*
- [admin_receipts_screen.dart:115](bora_app/lib/screens/admin/admin_receipts_screen.dart#L115) — *"Decisão TODO 5: ocr_flagged=true OU abs(diff_cents) > 100"*
- [admin_settlements_screen.dart:7](bora_app/lib/screens/admin/admin_settlements_screen.dart#L7) — docstring
- [admin_skill_suggestions_screen.dart:1140](bora_app/lib/screens/admin/admin_skill_suggestions_screen.dart#L1140) — *"categoria dinâmica = TODO 5G-β"*
- [admin_skill_suggestions_screen.dart:1460](bora_app/lib/screens/admin/admin_skill_suggestions_screen.dart#L1460) — *"LCS proper / package diff_match_patch: TODO 5G-β"*

### 🟠 P3 — Ecrãs órfãos (3) — implementados mas inacessíveis
Estes ecrãs existem como ficheiros mas não são abertos por nenhum tile/botão/rota:
- [admin_support_tickets_screen.dart](bora_app/lib/screens/admin/admin_support_tickets_screen.dart) — 253L · "Suporte — Tickets"
- [admin_orphan_payments_screen.dart](bora_app/lib/screens/admin/admin_orphan_payments_screen.dart) — 186L · "Órfãos de pagamento"
- [admin_receipts_screen.dart](bora_app/lib/screens/admin/admin_receipts_screen.dart) — 760L · "Reembolsos / Talões"

**Sugestão:** adicionar tiles no dashboard ou consolidar com ecrãs irmãos (ex.: receipts dentro de order_detail).

### ℹ️ P4 — Observações menores
- [admin_notifications_inbox_screen.dart](bora_app/lib/screens/admin/admin_notifications_inbox_screen.dart) não tem `AppBar(title: Text('...'))` literal — confirmar que título é gerado dinamicamente, senão UI fica sem header.
- [admin_drivers_screen.dart](bora_app/lib/screens/admin/admin_drivers_screen.dart) e [admin_driver_approval_screen.dart](bora_app/lib/screens/admin/admin_driver_approval_screen.dart) consultam tabela `drivers` directamente em vez de RPC — não é bug, mas inconsistente com a convenção do resto do painel (sempre via RPC SECURITY DEFINER).
- [admin_settlements_screen.dart](bora_app/lib/screens/admin/admin_settlements_screen.dart) e [admin_partners_pending_screen.dart](bora_app/lib/screens/admin/admin_partners_pending_screen.dart) e [admin_ratings_screen.dart](bora_app/lib/screens/admin/admin_ratings_screen.dart) — sem RPC nem `.from()` no scan: provavelmente delegam a um service/store que não foi inspeccionado neste ficheiro. **Não é bug por si só** mas vale a pena confirmar.

---

## RPCs em uso (62 únicas)

### ✅ 61 RPCs definidas correctamente nas migrations
Todas as 62 RPCs chamadas no código (excepto 1) estão presentes em `bora_app/supabase/migrations/`. As 12 inicialmente classificadas como "em falta" foram localizadas em:
- `20260430220000_session_final_consolidated.sql` (consolidado de 8 RPCs admin)
- `20260430230000_categories_reservations_session.sql` (3 RPCs de categorias)

Lista completa de RPCs admin chamadas: ver §Anexo A.

### 🔴 1 RPC chamada mas não definida
- **`admin_reject_skill_suggestion`** — chamada em `admin_skill_suggestions_screen.dart:754` mas inexistente nas migrations (existe só a versão `_bulk_`).

---

## Tabelas/views em uso (20)

| Tabela | Onde é usada (ecrãs admin) |
|---|---|
| `admin_audit_log` | driver_detail, order_detail |
| `admin_notifications` | dashboard, notifications_inbox |
| `client_restaurant_profiles` | clients |
| `driver_balances` | driver_detail |
| `driver_transactions` | driver_detail, driver_payments |
| `drivers` | driver_approval, driver_detail, drivers, tokens, receipts |
| `order_receipts_v2` | receipts |
| `orders` | driver_detail, global_search, order_detail, orders, receipts |
| `payment_drafts` | orphan_payments |
| `products` | partner_detail |
| `ratings` | ratings |
| `receipts` | receipts |
| `reservations` | reservations |
| `restaurant_menu_credits` | partner_settlements |
| `restaurant_tables` | reservations |
| `restaurants` | partner_detail, partner_settlements, partners |
| `skill_suggestions` | skill_suggestions |
| `support_settings` | skill_suggestions |
| `support_tickets` | support_tickets |
| `v_driver_weekly_earnings` (view) | driver_payments |

Todas existem nas migrations. **Nenhuma tabela em falta.**

---

## Edge functions invocadas pelo painel admin (2)

- `admin-cancel-order` — invocada de `admin_pending_actions_screen` (existe em `bora_app/supabase/functions/admin-cancel-order/`)
- `analyze-conversations` — invocada de `admin_skill_suggestions_screen` (existe em `bora_app/supabase/functions/analyze-conversations/`)

Ambas confirmadas presentes. Existem outras edge functions deployadas (35 no total) mas só estas 2 são invocadas a partir do painel admin.

---

## Cobertura no dashboard

Dos 46 ecrãs full-screen:
- **37** ligados directamente do dashboard via tiles
- **6** acessíveis por navegação interna a partir de outros ecrãs admin:
  - AdminBroadcastsHistoryScreen ← AdminSendNotificationScreen
  - AdminSkillSuggestionsMetricsScreen ← main.dart (rota registada)
  - AdminDriverDetailScreen ← AdminDriversScreen / AdminDriverApprovalScreen / AdminGlobalSearchScreen
  - AdminOrderDetailScreen ← AdminOrdersScreen / AdminGlobalSearchScreen
  - AdminPartnerDetailScreen ← AdminPartnersScreen / AdminGlobalSearchScreen / AdminClosedPartnersCard
- **3 órfãos** sem acesso (acima listados)

---

## Prioridade de fix sugerida

| # | Prioridade | Ecrã | Problema | Impacto | Esforço |
|---|---|---|---|---|---|
| 1 | **P1** | admin_skill_suggestions_screen | RPC `admin_reject_skill_suggestion` inexistente | Botão rejeição individual quebra | Baixo (migration nova OU refactor para bulk) |
| 2 | **P2** | admin_audit_log_screen / admin_driver_approval_screen / admin_reservations_screen | 3 × `catch (_) {}` silenciosos | Erros invisíveis ao admin | Baixo (log + SnackBar) |
| 3 | **P2** | admin_global_search_screen / admin_tokens_screen | Strings PT-BR ("busca", "usuário") | Inconsistência idioma | Trivial |
| 4 | **P3** | admin_support_tickets / admin_orphan_payments / admin_receipts | Órfãos no dashboard | Features escondidas ao admin | Baixo (adicionar tiles) |
| 5 | **P3** | admin_skill_suggestions_screen (L1140, L1460) | TODOs 5G-β: categoria dinâmica + LCS proper | Funcionalidade IA reduzida (mas funciona) | Médio |
| 6 | **P4** | admin_receipts_screen (L5, L115) | Abas placeholder + regra OCR flag | Versão mínima — expandir | Médio |
| 7 | **P4** | admin_notifications_inbox_screen | Sem `AppBar.title` literal | Confirmar título no runtime | Trivial |
| 8 | **P4** | admin_drivers_screen / admin_driver_approval_screen | Consultam `drivers` directamente sem RPC SECURITY DEFINER | Inconsistência de padrão (não funcional) | Médio |

---

## Recomendações estratégicas

1. **Bug P1 deve ser resolvido antes do lançamento** — a UI tem o botão visível, partner experience compromete-se se admin rejeita propostas individuais e nada acontece.
2. **Os 3 catch silenciosos devem ser substituídos por log + SnackBar visível** — princípio "atacar raiz" do CEO-AI. Erros silenciosos em painel admin são piores que noutros painéis porque o admin é a última linha de defesa.
3. **Os 3 órfãos** (receipts, orphan_payments, support_tickets) representam ~1.200 linhas de código já escritas. Não merecem ficar inacessíveis — adicionar tiles ao dashboard ou consolidar.
4. **Consistência idioma** — a 99% PT-PT, mas estes 2 ficheiros ficaram em PT-BR. Fácil de fixar.
5. **Padrão de acesso à DB** — convenção é "sempre via RPC SECURITY DEFINER". Os 4 ecrãs que consultam `drivers` directamente (driver_approval, drivers, tokens, receipts) deviam idealmente migrar para RPCs admin-only, garantindo audit log automático e RLS bypass controlado.

---

## Anexo A — RPCs admin chamadas (62 totais, ordenadas)

```
admin_approve_action                    admin_list_clients
admin_approve_cancellation              admin_list_complaints
admin_approve_skill_suggestion          admin_list_crosstalk
admin_ban_client                        admin_list_orphans
admin_block_client                      admin_list_pending_actions
admin_broadcast_notification            admin_list_products_by_partner
admin_bulk_reject_skill_suggestions     admin_list_promo_codes
admin_category_mapping_stats            admin_list_settings
admin_create_broadcast                  admin_list_skill_suggestions
admin_create_promo_code                 admin_live_drivers
admin_dashboard_metrics                 admin_live_orders
admin_deactivate_promo_code             admin_partners_with_counts
admin_edge_fn_health                    admin_referral_stats
admin_finalize_action                   admin_reject_action
admin_get_client_history                admin_reject_cancellation
admin_get_knowledge_stats               admin_reject_skill_suggestion   🔴 NÃO EXISTE
admin_get_user_tokens                   admin_reservations_metrics
admin_grant_referral_code               admin_resolve_ticket
admin_grant_tokens                      admin_respond_to_crosstalk
admin_kpi_avg_ticket                    admin_revoke_token_grant
admin_kpi_conversion                    admin_rollback_suggestion
admin_kpi_hot_zones                     admin_search_kpi
admin_list_audit_action_types           admin_send_notification
admin_list_audit_log                    admin_set_product_availability
admin_list_cashbacks                    admin_skill_suggestions_metrics
admin_list_category_mappings            admin_skill_suggestions_stats
                                        admin_unban_client
                                        admin_unblock_client
                                        admin_update_category_mapping
                                        admin_update_complaint_status
                                        admin_update_product_price
                                        admin_update_setting
                                        admin_update_skill_suggestion_note
                                        admin_user_wallet_transactions
                                        driver_effective_status
                                        is_partner_open
```

---

## Metodologia

1. Inventário via `Glob` em `bora_app/lib/screens/admin/**/*.dart` → 49 ficheiros
2. Análise estática Node.js (sandbox `ctx_execute`) com regexes para:
   - `\.rpc('NAME')` → RPCs chamadas
   - `\.from('TABLE')` → tabelas usadas
   - `\.functions\.invoke('FN')` → edge functions
   - `TODO|FIXME|XXX|HACK` em comentários
   - `throw UnimplementedError`
   - `onPressed:\s*(null|\(\)\s*\{\s*\})`
   - `catch\s*\([^)]*\)\s*\{\s*\}`
   - Lista PT-BR: você, busca, carrinho, utilizar, arquivo, usuário, aplicativo, celular, gerencia, cadastra, sobrenome, gratuit*, grátis
3. Cross-reference com 219 migrations SQL em `bora_app/supabase/migrations/` para detectar funções/tabelas em falta
4. Análise do dashboard para mapear ecrãs ligados vs órfãos
5. Cross-reference de orfãos contra os 248 ficheiros `.dart` em `bora_app/lib/` para detectar acessos por outros caminhos

**Limitações:** análise puramente estática. Não foi feito runtime testing nem inspecção de stores/services Provider — alguns ecrãs delegam queries a stores não inspeccionados (notado nas observações P4).

---

*Relatório gerado em 2026-05-18 pelo CEO-AI orchestrator. Sem alterações de código.*
