# BORA MOTORISTA — PLANO DE EXECUÇÃO (FASE 0)

> Vertical TVDE (transporte de passageiros estilo Uber, preço fixo Guarda).
> **Categoria escondida** — só visível ao cliente após aprovação manual do admin.
> 100% ISOLADA do delivery. Gerado pelo CEO-AI · 2026-06-26 · revisão: Claude.ai.

---

## 0. RESUMO EXECUTIVO

- **Green field confirmado:** zero código TVDE existente no repo (grep `tvde|motorista|passageiro|carro_passageiros` → 0 hits em `lib/` e `supabase/`).
- **Blueprint:** a vertical **"Serviços/Beleza" (barbearia)** é o molde arquitectural ideal — vertical isolada já em produção com tabelas próprias (`service_providers`, `appointments`, `appointment_payouts`), stores próprias (`services_store`, `partner_appointments_store`), screens `client/services/*` + `partner/services/*` + `admin/admin_appointments_*`, edge function própria `notify-service-provider`, e ecrã admin dedicado. Copiamos esse padrão para `tvde_*`.
- **Isolamento garantido:** tabela própria `tvde_rides`, função própria `tvde_calculate_fare`, dispatch próprio de passageiros, liquidação CASH própria (mirror de `driver_balances`). **Nenhuma** zona protegida é tocada.

---

## 1. MAPA DE REAPROVEITAMENTO (confirmado no código real)

### ✅ Reutilizar tal-e-qual
| Recurso | Ficheiro/objecto confirmado | Uso TVDE |
|---|---|---|
| `platform_settings` (key TEXT PK / value JSONB) | `migrations/20260430110000_platform_settings.sql` | Todas as chaves `tvde_*`. Helpers `get_setting(key)`, RPCs `admin_update_setting`/`admin_list_settings` já existem |
| Padrão admin RPC | `_admin_op_guard()` + `log_admin_action()` + `REVOKE…public,anon`+`GRANT…authenticated` | Todas as RPCs admin TVDE seguem este padrão |
| `drivers` (is_online, lat, lng, last_heartbeat_at, fcm_token, approval_status, avg_rating, ratings_count) | `lib/stores/driver_store.dart` | Online/posição/aprovação/rating do motorista |
| `driver_locations` + RPC update | `migrations/20260430170000_driver_locations_realtime.sql`, `20260501000000_driver_location_sync.sql` | Mapa tempo real da corrida (admin + cliente) |
| `notify-driver` (edge fn) | `supabase/functions/notify-driver/index.ts` | **Molde** para `notify-tvde-driver` (push de oferta) |
| `notify-client` (edge fn) | `supabase/functions/notify-client/index.ts` | **Molde** para push ao passageiro (a caminho/chegou) |
| `notify-admin-urgent` + `admin_notifications` | `supabase/functions/notify-admin-urgent/index.ts` | Avisar admin de novo pedido de acesso |
| `messages` | `lib/models/message_model.dart`, `notify-chat-message` | Chat passageiro↔motorista (reuso direto) |
| Google Places autocomplete | `lib/services/place_autocomplete_service.dart` (+io/web/stub) | Campo destino |
| Directions/ETA | `lib/services/directions_service.dart`, `order_eta_service.dart` | ETA no mapa |
| `ratings` + `rating_model.dart` | `lib/models/rating_model.dart` | Base para avaliação bidirecional |
| Login cliente/estafeta | `AuthStore` (dual-layer) + `SessionStore` (`bora_app.user_role`) + `_RootNavigator` em `main.dart` | Reuso total — sem novo login |
| Home cliente (grid de categorias) | `client_home_screen.dart::_buildCategoryGrid` → `List<_TileData>` | Injeção condicional do tile escondido |
| Ecrã admin settings | `admin_platform_settings_screen.dart` | Já lê/escreve `platform_settings` por categoria — as chaves `tvde_*` aparecem automaticamente |
| Perfil cliente p/ admin | `users` (photo_url, name, phone, email, created_at) + `admin_clients_screen.dart` | Ecrã de aprovação mostra perfil completo |

### 🟡 Estender (alteração cirúrgica, retro-compatível)
- **`VehicleType` enum** (`driver_model.dart`) tem só `motorcycle, car, bicycle`. Serialização DB usa `enum.name` (`driver_store.dart:474`), e leitura faz `VehicleType.values.firstWhere(... , orElse: motorcycle)`.
  → **CRÍTICO:** adicionar `carPassengers`. Decisão de valor DB no §6 (Risco R1).

### 🆕 Criar do zero (isolado)
Tabelas, RPCs, função de tarifa, dispatch, screens, edge functions — §2–§4.

---

## 2. BACKEND — TABELAS, FUNÇÃO E RPCs (DDL resumido)

Migrations versionadas `YYYYMMDDHHMMSS_descr.sql` (convenção confirmada). Cada tabela com RLS. Todas as RPCs `SECURITY DEFINER`, `REVOKE…public,anon` + `GRANT…authenticated`, admin via `_admin_op_guard()`.

### 2.1 Tabelas novas
```
users.tvde_access            BOOLEAN NOT NULL DEFAULT false   -- coluna nova (gate)

tvde_access_requests(
  id UUID PK, client_id UUID→users, status TEXT
    CHECK(status IN ('pendente','aprovado','recusado')) DEFAULT 'pendente',
  requested_at, decided_at, decided_by UUID, decision_note TEXT)
  RLS: cliente vê o seu; admin vê tudo (via _admin_op_guard)

tvde_rides(
  id UUID PK, client_id UUID, driver_id UUID NULL,
  origin_lat/lng, origin_label, dest_lat/lng, dest_label,
  est_distance_km NUMERIC, est_fare_cents INT,
  final_distance_km NUMERIC NULL, final_fare_cents INT NULL,
  driver_earn_cents INT NULL, bora_cut_cents INT NULL,
  payment_method TEXT DEFAULT 'cash',
  subscription_id UUID NULL, used_subscription_ride BOOL DEFAULT false,
  cancel_fee_cents INT DEFAULT 0, cancel_reason TEXT NULL,
  status TEXT CHECK(status IN ('solicitada','motorista_atribuido',
    'motorista_a_caminho','motorista_chegou','em_andamento','finalizada',
    'cancelada_cliente','cancelada_motorista','no_show','sem_motorista')),
  current_offer_driver_id UUID NULL, offer_expires_at TIMESTAMPTZ NULL,
  created_at, updated_at)
  RLS: cliente vê as suas; motorista vê as atribuídas/ofertadas; admin tudo
  ⚠️ ISOLADA — não referencia orders

tvde_ride_events(
  id UUID PK, ride_id UUID→tvde_rides, status TEXT, actor TEXT, meta JSONB, at)
  RLS: partes da corrida + admin

tvde_subscriptions(
  id UUID PK, client_id UUID, plan TEXT CHECK(plan IN
    ('semanal','quinzenal','mensal')), rides_total INT, rides_used INT DEFAULT 0,
  daily_included INT DEFAULT 2, price_cents INT, granted_by UUID,
  starts_at, ends_at, active BOOL DEFAULT true)
  RLS: cliente vê a sua; admin tudo

tvde_ride_counters(            -- contador diário (2/dia incluídas)
  client_id UUID, day DATE, rides_count INT DEFAULT 0,
  PRIMARY KEY(client_id, day))
  RLS: cliente vê o seu; admin tudo
```

### 2.2 `drivers.vehicle_type` — novo valor
- Não existe CHECK constraint visível em `drivers.vehicle_type` (texto livre) → adicionar valor é seguro. Adicionar (se houver constraint) `'carro_passageiros'` sem quebrar `motorcycle/car/bicycle`.

### 2.3 `tvde_calculate_fare(distance_km NUMERIC) → INT (cents)`
```
base   = get_setting('tvde_base_fare_cents')::int          -- 500
free   = get_setting('tvde_base_distance_km')::int         -- 6
perkm  = get_setting('tvde_extra_per_km_cents')::int       -- 50
fare   = base + GREATEST(0, ceil(distance_km - free)) * perkm
```
Testes do gate: 3km→500, 6km→500, 10km→700. (SQL puro `STABLE`, sem tocar `pricing_calculate`.)

### 2.4 Ganho do motorista (no finish)
```
d_base = get_setting('tvde_driver_base_cents')::int        -- 400
d_perkm= get_setting('tvde_driver_per_km_cents')::int      -- 40
extra_km = GREATEST(0, ceil(final_km - 6))
driver_earn = d_base + extra_km*d_perkm
bora_cut    = final_fare - driver_earn        -- sempre o resto (auto-consistente)
```
Validação 10km: cliente 700 → motorista 560 → Bora 140. ✓

### 2.5 RPCs (todas isoladas)
`tvde_request_access`, `admin_set_tvde_access(client, action aprovar/recusar/revogar)`,
`tvde_request_ride`, `tvde_accept_ride`, `tvde_reject_ride`, `tvde_driver_arrived`,
`tvde_start_ride`, `tvde_finish_ride(final_distance_km)`,
`tvde_cancel_ride(actor, reason)` (cliente/motorista/no_show),
`tvde_rate(ride, target, stars, comment)` (bidirecional),
`tvde_consume_subscription_ride`, `admin_grant_subscription`.

### 2.6 Liquidação CASH isolada
- Tabela `tvde_driver_balances` (mirror de `driver_balances`): por corrida cash, motorista deve `bora_cut_cents` ao Bora; settle semanal. **NUNCA** `ledger_entries`/`order_financials`/triggers de orders.

---

## 3. DISPATCH DE PASSAGEIROS (isolado — Fase 2)

- Trigger/edge fn `tvde-dispatch`: ao criar `tvde_rides(status='solicitada')`, escolhe motorista `is_online=true AND vehicle_type='carro_passageiros'`, mais próximo por haversine (lat/lng), grava `current_offer_driver_id`+`offer_expires_at`, e chama `notify-tvde-driver` (molde `notify-driver`).
- Recusa/timeout → próximo motorista. Sem motorista → `status='sem_motorista'`, push ao cliente.
- **Não encosta** em `dispatch-engine` nem `DispatchEngine` (Flutter). Motor próprio, timer/cron próprio.

---

## 4. FLUTTER — FICHEIROS A CRIAR/TOCAR

### Cliente (PT-PT) — Fase 3
- **CRIAR:** `lib/models/tvde_ride.dart`, `tvde_subscription.dart`; `lib/stores/tvde_store.dart` (Model→Store→Screen); `lib/screens/client/tvde/tvde_unlock_screen.dart` (pedir acesso + estado pendente/aprovado/recusado), `tvde_request_ride_screen.dart` (pickup GPS + destino Places + preço estimado), `tvde_ride_tracking_screen.dart` (mapa tempo real/ETA/estados), `tvde_rate_screen.dart`, `tvde_rides_history_screen.dart`, `tvde_plans_screen.dart` (planos + contador diário).
- **TOCAR (cirúrgico):** `client_home_screen.dart::_buildCategoryGrid` → injetar tile "Bora Motorista" **só se** `tvde_access==true`, e entrada discreta "Quero desbloquear uma categoria exclusiva" (abre `tvde_unlock_screen`). Registar `TvdeStore` no provider chain em `main.dart`. Asset `assets/categories/cat_motorista.png` (+ fallback ícone, padrão já suportado).

### Estafeta (PT-PT) — Fase 4
- **CRIAR:** `lib/screens/driver/tvde/tvde_driver_home_screen.dart` (toggle online passageiros), `tvde_offer_screen.dart` (oferta c/ timeout, nome/pickup/destino/valor), `tvde_ride_active_screen.dart` (a caminho→cheguei→iniciar→finalizar), `tvde_driver_rate_screen.dart`.
- **TOCAR:** `driver_model.dart` (+`carPassengers`); cadastro estafeta (opção 🚗 "Carro — Passageiros"); routing pós-login: motorista `carro_passageiros` → modo passageiros (no `_RootNavigator`/driver home). Reuso de heartbeat/location/FCM existentes.

### Admin (PT-BR) — Fase 5
- **CRIAR:** `lib/screens/admin/admin_tvde_access_requests_screen.dart` (perfil completo do cliente + aprovar/recusar/revogar), `admin_tvde_rides_screen.dart` (ao vivo + histórico + financeiro motorista/Bora + cancelamentos), `admin_tvde_drivers_screen.dart` (gerir/banir motoristas passageiros), `admin_tvde_subscriptions_screen.dart` (conceder assinatura). Tarifas/planos/taxas → já no `admin_platform_settings_screen.dart` existente.

### Edge functions novas
- `notify-tvde-driver`, `notify-tvde-client`, `tvde-dispatch` (todas cópias de molde, isoladas).

---

## 5. CHAVES `platform_settings` (seed Fase 1)
```
tvde_base_fare_cents=500  tvde_base_distance_km=6  tvde_extra_per_km_cents=50
tvde_driver_base_cents=400  tvde_driver_per_km_cents=40
tvde_plan_weekly_cents=5600  tvde_plan_biweekly_cents=10500  tvde_plan_monthly_cents=18000
tvde_extra_ride_cents=450  tvde_plan_daily_included=2
tvde_cancel_fee_cents=0   (placeholder — Danilo decide)
```
(categoria `tvde` → aparece agrupada no ecrã admin de settings.)

---

## 6. RISCOS E DECISÕES

- **R1 (CRÍTICO) — serialização vehicle_type:** Flutter grava `enum.name` e lê com fallback→`motorcycle`. Se a DB tiver `'carro_passageiros'` mas o enum não o reconhecer, o motorista vira `motorcycle` silenciosamente. **Decisão recomendada:** adicionar `VehicleType.carPassengers` e mapear explicitamente `carPassengers ↔ 'carro_passageiros'` num to/fromDb (manter `.name` para os 3 existentes). Confirmar no review.
- **R2 — motorista dual (delivery + passageiros):** por agora `vehicle_type` roteia (1 motorista = 1 modo). Dual fica como decisão de design futura (não implementar agora).
- **R3 — pagamento:** só CASH nos testes; assinatura concedida por `admin_grant_subscription` (sem Stripe). Deixar seam limpo para Stripe depois.
- **R4 — taxa de cancelamento:** valor final é decisão do Danilo; implementamos os estados + chave configurável (default 0).
- **R5 — legal:** licença IMT/legislação TVDE é decisão/responsabilidade do Danilo (fora do código).

## 7. BUGS/OBSERVAÇÕES ENCONTRADOS (recon)
- **B1:** Comentário em `platform_settings.sql` diz que o refactor pricing-from-settings "NÃO mergeada", mas existe `20260430210000_s3_pricing_from_settings.sql` → possível doc drift (fora de scope, só registo).
- **B2:** Tile "Reservar Mesa" mostra SnackBar e navega na mesma — UX menor pré-existente (fora de scope).
- **B3:** `VehicleType` fallback silencioso para `motorcycle` (ver R1) — risco real de integração, tratado no plano.

## 8. ORDEM DE EXECUÇÃO
Fase 1 (DB+RPCs+fare+settings+RLS) → Fase 2 (dispatch passageiros) → Fase 3 (cliente) → Fase 4 (estafeta) → Fase 5 (admin) → Fase 6 (verificação + checklist §9 + push). Gate por fase; máx 5 correções/item. Idiomas: app PT-PT, admin PT-BR.

---
**⛔ CHECKPOINT FASE 0 — aguarda OK do Claude.ai antes de executar Fase 1.**
