# Reservas PRO F1 — Schema Design

## Decisões arquitecturais importantes

### `combinable_with uuid[]` sem FK constraint

Postgres não permite FK em arrays. Integridade fica à carga da app
(validar IDs existem antes de UPDATE). Trade-off: flexibilidade vs
segurança DB. Compensação: validação obrigatória nos endpoints F2.

### `preferences jsonb` em `client_restaurant_profiles`

Schema-less para alergias, mesa preferida, ocasiões, etc. Permite
evolução sem migrations. Trade-off: queries mais complexas (operadores
JSONB) vs flexibilidade. Aceitável dado que estas prefs raramente
são filtradas em massa — são lidas por reserva.

### `party_size` ranges em `restaurant_turn_times`

Em vez de 1 row por tamanho específico, ranges (`party_size_min`,
`party_size_max`) permitem definir buckets (2-3 = 90min, 4-5 = 120min,
6+ = 150min) sem multiplicar rows. Look-up: `WHERE party_size BETWEEN min AND max`.

### `floor_plan_id` snapshot em `reservations`

Quando cliente reserva, guardamos o `floor_plan_id` da altura. Se
restaurante mudar layout depois, reservas existentes não quebram
(admin pode trocar mesa manualmente). `ON DELETE SET NULL` para tolerar
remoções de floor plans antigos sem perder a reserva.

### `event_type` enum permite pacing especial

`valentines/christmas/etc` podem ter turn_times diferentes (jantar
romântico = 150min vs normal 120min). `event_type` permite queries
de analytics e configuração por ocasião. Default `'normal'` para
zero impacto em código existente.

## Modelo OpenTable Notify

`reservation_notify_list` segue padrão OpenTable Notify / Resy Notify:
cliente quer 20h sábado, cheio, entra na "lista de aviso", recebe push
se alguém cancelar dentro da janela `target_time +/- flexibility_minutes`.

`expires_at` evita acumulação infinita; CRON F2 marca `status='expired'`
após `reservation_notify_list_expiry_hours` (default 24h).

## RLS RGPD-compliant

| Tabela | Cliente | Parceiro | Admin |
|---|---|---|---|
| `restaurant_floor_plans` | SELECT (active=true) | ALL via `restaurants.user_` | service_role bypass |
| `restaurant_tables` | SELECT (active=true) | ALL via `restaurants.user_` | service_role bypass |
| `restaurant_pacing_rules` | — | ALL via `restaurants.user_` | service_role bypass |
| `restaurant_turn_times` | — | ALL via `restaurants.user_` | service_role bypass |
| `reservation_table_assignments` | SELECT (suas reservas) | ALL (seus restaurantes) | service_role bypass |
| `reservation_waitlist` | ALL (próprias) | ALL (seus restaurantes) | service_role bypass |
| `reservation_notify_list` | ALL (próprias) | SELECT (seus restaurantes) | service_role bypass |
| `client_restaurant_profiles` | SELECT (próprio) | ALL (seus restaurantes) | service_role bypass |

Anonymous role bloqueado em todas (RLS sem policy `TO anon` = deny).

## Índices por padrão de query

- `idx_floor_plans_one_default` UNIQUE WHERE `is_default=true` —
  garante 1 plano default por restaurante.
- `idx_reservations_availability` partial — exclui status terminais.
  Acelera "há mesa para party=4 às 20h sábado?".
- `idx_reservations_analytics` partial — só reservas seated.
  Acelera dashboards de turn time real.
- `idx_notify_expiring` partial — só active. Acelera CRON expiry.

## Próximos passos F2 (referência para sessão futura)

1. Edge Function `check_availability(restaurant, date, time, party)`
2. Edge Function `reserve_table(reservation_id, force_assign?)`
3. CRON daily reminders 24h e 2h antes
4. RPC `partner_seat_walk_in(restaurant, party, table_id)`
5. Trigger auto-update `client_restaurant_profiles` em `finished_at`
   (incrementa `total_visits`, actualiza `last_visit_at`)
6. CRON expiry para waitlist + notify list
