# PLANO — Categoria "Serviços" / Vertical Barbearias

> Data: 2026-06-08 · Branch: autonomous-night-2026-04-29 · Repo: `bora_app/`
> Estado: **AGUARDA APROVAÇÃO** (MODO PROTECÇÃO TOTAL + Validation Gate)
> Autor: Claude Code (Opus 4.8) sob orquestração CEO-AI

---

## 0. SUMÁRIO EXECUTIVO

Criar a vertical **Barbearias** dentro de uma nova categoria **"Serviços"** na home,
copiando 100% os padrões do sistema de **Reservas de Mesa** (`reservas_pro`) já em produção.
Arquitetura preparada para futuras verticais (manicure, fisio, PT, etc.) via `service_providers.category`.

Esforço: **grande** (6 tabelas, ~13 RPCs, 1 Edge Function, ~16 ecrãs Flutter, admin, 4 crons, demo).
Execução proposta em **5 fases sequenciais** (A→E) após aprovação única.

---

## 1. DESCOBERTAS DA FASE 0 (o que já existe)

### 1.1 DB — confirmado por query
- ✅ As 6 tabelas novas (`service_providers`, `staff_members`, `provider_services`, `staff_availability`, `appointments`, `appointment_payouts`) **NÃO existem** — caminho livre.
- `platform_settings.value` é **JSONB** (não int). `INSERT ... VALUES ('k', 50)` funciona (50 = número JSON).
- `restaurants.id` é **TEXT** (legado). Padrão: IDs de entidades de negócio = TEXT. → `service_providers.id` será TEXT (como no prompt).
- `ledger_entries`: `user_id TEXT`, `user_type TEXT`, `order_id UUID nullable`, `amount NUMERIC`, `type TEXT`, `reference TEXT`. → para receita Bora de marcações: `order_id=NULL`, `reference=appointment_id`.
- Settings de reserva existentes (referência): `reservation_prepayment_cents=300`, `reservation_bora_service_cents=100`, `reservation_partner_payout_cents=200`, `reservation_cancel_window_hours=2`.

### 1.2 Padrão de pagamento Stripe (CRÍTICO)
- O PaymentIntent é criado por **Edge Function** `create-reservation-payment-intent` (a chave secreta Stripe não está acessível a PL/pgSQL).
- A confirmação é feita por RPC `client_confirm_reservation_payment` (fallback client-side após `presentPaymentSheet`) **e/ou** webhook `confirm_reservation_payment_webhook`.
- `payment_service.dart` usa `flutter_stripe` → `initPaymentSheet` + `presentPaymentSheet`.

### 1.3 RPCs/infra reutilizáveis (modelos a clonar)
- Cliente: `client_confirm_reservation_payment`, `client_cancel_reservation`
- Parceiro: `partner_decide_reservation`, `partner_mark_arrival`, `partner_seat_walk_in`
- Admin: `admin_reservations_metrics`, `admin_get_reservations_stats`, `admin_force_create_reservation`, `admin_cancel_reservation_on_behalf_of`, `approve_partner`, `reject_partner`, `admin_list_partners_detailed`
- Payouts: `admin_list_partner_payouts`, `admin_mark_partner_payouts_paid`, `admin_partner_payout_summary`, `compute_driver_settlement`, `close_previous_week_settlements`
- Push/cron: `_reservas_pro_notify_client_push`, `_reservas_pro_notify_partner_push`, `_reservas_pro_cron_send_reminders_24h/2h`, `auto_close_no_show_reservations`
- Crons existentes usam `net.http_post` + `vault.decrypted_secrets` (project_url, service_role_key).

### 1.4 Design system
- Tokens: `primary #16A34A`, `accent #F97316`, `background #F0F2EF`, `surface #FFFFFF`, `textPrimary/Secondary/Subtle`, `divider`, `success/warning/error`, `shadowCard/shadowNav`, `Spacing.*`, `Radii.*`.
- Widgets: `BoraScreenAppBar`, `BoraTileCard.image()`, `BoraPrimaryButton`, `BoraAccentButton`, `BoraBottomNavV2`, `BoraMascot`. **NÃO existe** widget de calendário/slots — será construído (showDatePicker pt_PT + grid de slots, como reservas).
- Home: 7 categorias em `client_home_screen.dart` via `_TileData` + `BoraTileCard.image()`. Adiciona-se a **8ª: "Serviços"**.
- Regra **1 elemento laranja por ecrã** (auditável por `audit-orange-rule`).
- Moeda: `'€${(cents/100).toStringAsFixed(2)}'`. Datas: `showDatePicker(locale pt_PT)`.

### 1.5 Zonas protegidas (doc 10) — respeitadas
Não se edita: `dispatch-engine`, `pricing_service`/`pricing_calculate`, triggers financeiros, `bora_tokens`, `stripe-webhook`, Edge Fns Stripe existentes, RLS de `orders/wallets/ledger`, `payment_method_screen.dart`, sistema `reservations`/`_reservas_pro_*`.
**Criamos ficheiros NOVOS**; edições em ficheiros existentes são **cirúrgicas** (home +1 categoria, app_colors +1 gradiente, main.dart +1 provider, rotas).

---

## 2. DIVERGÊNCIAS NECESSÁRIAS DO PROMPT ORIGINAL

| # | Prompt pedia | Realidade do projeto | Decisão |
|---|---|---|---|
| **D1** | `client_book_appointment` cria o PaymentIntent Stripe dentro da RPC SQL | Impossível — Stripe secret só em Edge Fn | RPC cria o appointment `pending_payment`; **Edge Function `create-appointment-payment-intent`** (clone de `create-reservation-payment-intent`) cria o PI e devolve `clientSecret`. RPC `client_confirm_appointment_payment` confirma. |
| **D2** | MBWay implícito | Reservas têm card + MBWay; MBWay exige tocar `stripe-webhook` (protegido) | **MVP = só cartão** (Stripe PaymentSheet + confirm RPC, padrão das reservas, **não toca webhook**). MBWay = extensão futura. |
| **D3** | Refund "via Stripe refund" na RPC | RPC não chama Stripe | `client_cancel_appointment` replica **exatamente** o mecanismo de refund de `client_cancel_reservation` (a confirmar na execução: `net.http_post`→Edge Fn `refund` vs registo). Não recria a Edge Fn `refund`. |
| **D4** | `status='blocked'` para bloqueio de horário | OK, mas precisa não colidir com slots | Mantido: appointment "fantasma" `status='blocked'` filtrado em `get_available_slots`. |

Nada disto altera o resultado funcional pedido — apenas o **como**, para respeitar o padrão e as zonas protegidas.

---

## 3. MODELO FINANCEIRO — ⚠️ DECISÃO A CONFIRMAR

O prompt tem uma ambiguidade: "Bora cobra €0,50 **independente do que acontece**" vs "Cancelamento >24h: sinal devolvido, **Bora recebe €0**".

**Modelo recomendado (M3)** — concilia ambos e usa os settings tal como definidos:

| Evento | Cliente | Bora | Parceiro (payout semanal) |
|---|---|---|---|
| Marcação (booking) | paga **€3 sinal** (cartão) | segura €3 | — |
| **Concluída** | sinal abate ao serviço; paga o resto na app/loja | **+€0,50** (booking fee) | **+€2,50** (+ resto se pago na app) |
| **Cancel >24h** | refund **€3** | €0 | €0 |
| **Cancel <24h / no-show** | perde **€3** | **+€0,50** | **+€2,50** |

Ou seja: Bora fica sempre com €0,50 **exceto** em cancelamento antecipado (>24h), que é grátis. `appointment_booking_fee_cents` (conclusão) e `appointment_deposit_bora_cut_cents` (no-show) coincidem em €0,50. **Confirmar se é este o modelo pretendido.**

---

## 4. FASE A — BASE DE DADOS

### A.1 Migrations de tabelas (1 migration por bloco lógico, snake_case)
Tabelas conforme o prompt (validadas contra padrões reais):
- `service_providers` (id TEXT PK, user_id, name, category default 'barbershop', morada/lat/lng, photo/hero, is_online, is_active_admin, approval_status, business_hours JSONB, avg_rating, fcm_token, nif, iban, timestamps)
- `staff_members` (id TEXT PK, provider_id FK CASCADE, name, bio, photo, specialties TEXT[], is_active, sort_order)
- `provider_services` (id TEXT PK, provider_id FK, name, duration_minutes, price_cents, is_active, sort_order)
- `staff_availability` (id UUID, staff_id FK, day_of_week SMALLINT, start_time, end_time, is_working, UNIQUE(staff_id,day_of_week))
- `appointments` (UUID PK; provider/staff/service FKs; client_user_id; scheduled_at; duration; service_price_cents; deposit_cents/pi/status; full_payment_method/pi/status; status; timestamps de estado; reminders; notes; is_walk_in)
- `appointment_payouts` (UUID PK; provider_id FK; week_start/end; totais; net_payout_cents; direction; status; paid_*) — modelo `driver_weekly_settlements` (agregado semanal).

### A.2 RLS (padrão do projeto)
- `service_providers`: SELECT público se `is_online AND approval_status='approved'`; escrita só `auth.uid()=user_id`.
- `staff_members`/`provider_services`/`staff_availability`: SELECT público; escrita só pelo dono do provider.
- `appointments`: cliente vê os seus (`client_user_id=auth.uid()`); parceiro vê os do seu provider; admin tudo (helper `is_admin()` existente).
- `appointment_payouts`: parceiro vê os seus; admin tudo.

### A.3 Índices
Conforme prompt (provider, staff, client, scheduled_at, status; staff/services/availability por FK).

### A.4 platform_settings (8 chaves, JSONB)
`appointment_booking_fee_cents=50`, `appointment_deposit_cents=300`, `appointment_cancel_window_hours=24`, `appointment_deposit_bora_cut_cents=50`, `appointment_deposit_partner_cut_cents=250`, `appointment_reminder_24h_enabled=true`, `appointment_reminder_2h_enabled=true`, `appointment_max_advance_days=30` (+ `category='appointments'` + description).

### A.5 RPCs (SECURITY DEFINER, asserts de papel como `_reservas_pro_assert_*`)
1. `get_available_slots(p_staff_id, p_service_id, p_date)` → slots livres (server-side).
2. `client_book_appointment(p_service_id, p_staff_id, p_scheduled_at, p_client_notes)` → cria `pending_payment`, devolve `appointment_id` (PI vem da Edge Fn — ver D1).
3. `client_confirm_appointment_payment(p_appointment_id)` → `confirmed` + ledger booking_fee + push parceiro/cliente.
4. `client_cancel_appointment(p_appointment_id)` → janela 24h: refund vs reter (ledger) — ver D3.
5. `partner_complete_appointment(p_appointment_id, p_payment_method)` → `completed` + ledger.
6. `partner_mark_no_show(p_appointment_id)` → reter sinal split €0,50/€2,50 + ledger.
7. `partner_add_walk_in(...)` → `is_walk_in=true`, `deposit_status='waived'`, `confirmed`.
8. `partner_block_slot(p_staff_id, p_start_at, p_end_at, p_reason)` → appointment `blocked`.
9. `_appointment_cron_send_reminders_24h()` / `_2h()` — clones dos `_reservas_pro_*`.
10. `_appointment_cron_auto_no_show()` — `confirmed` vencidas >grace → `no_show`.
11. `compute_provider_weekly_payout(p_provider_id, p_week_start)` — clone de `compute_driver_settlement`.
12. `compute_all_provider_weekly_payouts()` — itera providers.
13. `admin_appointments_metrics(p_provider_id, p_from, p_to)`, `admin_list_appointment_payouts`, `admin_mark_appointment_payouts_paid`, `admin_appointment_provider_approve/reject` (clones admin).

### A.6 Edge Function
- `supabase/functions/create-appointment-payment-intent/` — **clone** de `create-reservation-payment-intent` (amount=deposit_cents, currency EUR, mín €0,50, metadata appointment_id; `verify_jwt` igual ao original). Deploy via skill `deploy-edge-function` (dry-run primeiro).

### A.7 Demo "Barbearia Nobre"
User auth `barbearia.nobre@bora.app` (role partner) + provider (Guarda, `is_online=false`, `approved`) + 2 barbeiros + 6 serviços + availability Seg–Sáb. Via SQL (idempotente, prefixos identificáveis para rollback).

**Validação A:** queries do prompt (tabelas, demo, settings, crons).

---

## 5. FASE B — FLUTTER CLIENTE

- **Models** (`lib/models/`): `service_provider_model.dart`, `staff_member_model.dart`, `provider_service_model.dart`, `appointment_model.dart` (com classe `AppointmentStatus` de `static const String`, padrão das reservas; `fromSupabase`/`toSupabase`).
- **Store** (`lib/stores/services_store.dart`): ChangeNotifier; métodos `fetchProviders`, `fetchServices/Staff`, `getAvailableSlots`, `bookAppointment`(+Edge Fn PI + PaymentSheet + confirm), `cancelAppointment`, `fetchMyAppointments` (+ realtime `subscribeMyAppointments`). Error-map PT-PT.
- **Categoria home** (cirúrgico): `app_colors.dart` +`tileServices` gradiente; `client_home_screen.dart` +`_TileData('Serviços', …, ServicesCategoryScreen())`; asset `assets/categories/cat_servicos.png`; registo do provider em `main.dart`. (Pode usar a skill `add-home-category` em modo patch.)
- **Ecrãs** (`lib/screens/client/services/`): `services_category_screen` (lista barbearias) → `provider_detail_screen` → fluxo 6 passos (`booking_service` → `booking_staff` → `booking_day` → `booking_slot` → `booking_confirm` + PaymentSheet → sucesso) → `my_appointments_screen` (futuras/passadas/canceladas + cancelar com aviso <24h).
- Widget novo `appointment_slot_grid.dart` (grid de slots). Reutiliza `BoraScreenAppBar`, cards, `BoraAccentButton` (1 laranja: o CTA "Confirmar e Pagar").

**Validação B:** `flutter analyze` = 0 erros.

---

## 6. FASE C — FLUTTER PARCEIRO

- **Store** `partner_appointments_store.dart`.
- **Ecrãs** (`lib/screens/partner/services/`): `partner_agenda_screen` (Hoje/Semana, cards com ações Concluído-loja/Concluído-app/Faltou), `partner_add_walk_in`, `partner_block_slot`, `partner_manage_services`, `partner_manage_staff` (+ availability semanal), `partner_appointments_finance_screen` (resumo semana + BarChart `fl_chart` 4 semanas + histórico de liquidações).
- Estados/cores: Confirmada=verde, Concluída=cinza, Cancelada=riscado, Bloqueado=laranja.

**Validação C:** `flutter analyze` = 0 erros.

---

## 7. FASE D — ADMIN

- `admin_service_providers_screen` (pendentes/aprovados/rejeitados, aprovar/rejeitar c/ motivo, editar, ativar/desativar) — padrão `admin_partners_pending_screen`.
- `admin_appointments_screen` (agenda global, filtros data/loja/estado, cancelar em nome com/sem refund).
- `admin_appointments_payouts_screen` (resumo taxas Bora/semana, liquidações pendentes por provider, marcar pago c/ dupla confirmação, gráfico) — padrão `admin_partner_payouts_screen`.
- `admin_appointments_metrics_screen` (total hoje/semana/mês, no-show %, providers ativos, horas de pico).
- PT-BR (admin é PT-BR), `BoraScreenAppBar`/`.branded`, tokens, registo na navegação admin.

**Validação D:** `flutter analyze` = 0 erros.

---

## 8. FASE E — CRONS + VALIDAÇÃO FINAL + GIT

- 4 crons `pg_cron` (clonando o padrão; nomes `appt-*`):
  - `appt-reminders-24h` `0 10 * * *`
  - `appt-reminders-2h` `*/30 * * * *`
  - `appt-auto-noshow` `*/15 * * * *`
  - `appt-weekly-payout` `0 8 * * 1`
- Correr todas as queries de **VALIDAÇÃO FINAL** do prompt + `flutter analyze`.
- Correr `audit-protected-zones` + `audit-orange-rule`.
- `versionCode` bump (+1) no `build.gradle`.
- `git -C bora_app add -A && commit && push origin autonomous-night-2026-04-29`.
- `/ctx doctor` + `/ctx stats`.

---

## 9. ORDEM DE EXECUÇÃO & CHECKPOINTS

A → B → C → D → E, sequencial. Cada fase termina com a sua validação.
Conforme a regra de autonomia aprovada (memória `feedback_autonomy_multi_phase`), **após aprovação deste plano corro A→E end-to-end** sem pedir aprovação por fase — exceto se surgir uma decisão estrutural nova não coberta aqui.

Pontos onde poderei parar e perguntar: confirmação do mecanismo exato de refund (D3) se divergir do esperado; qualquer settings blindado; conflito inesperado em zona protegida.

---

## 10. O QUE PRECISO DE TI AGORA

1. **Aprovar o plano** (ou ajustar).
2. **Confirmar o modelo financeiro M3** (secção 3).
3. Confirmar **MVP só cartão** (MBWay depois) — divergência D2.
