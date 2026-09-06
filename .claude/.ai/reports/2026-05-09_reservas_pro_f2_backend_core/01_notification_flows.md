# Reservas PRO F2 — Notification Flows (16 momentos)

Todas as notificações são via `_push_in_app_notification` (helper
existente da plataforma). Push FCM real está comentado em
`_reservas_pro_notify_partner_push` — activar pós-launch quando
Firebase Service Account configurado em secrets.

## 9 Push Parceiro automáticos

| # | Kind | Trigger | Origem | Mensagem |
|---|---|---|---|---|
| 1 | `reservation_new_pending` | INSERT `reservations` (status=pending) | `trg_reservation_notify_partner_new` | "Nova reserva pendente • {nome} • {N} pessoas • {data hora}" |
| 2 | `reservation_pending_alert` | CRON 1min, pending criado há 5-10min sem resposta | `_reservas_pro_cron_pending_too_long()` | "Reserva pendente >5min! Urgente: {nome} aguarda resposta • {N} pessoas" |
| 3 | `morning_summary` | CRON 8h UTC daily | `_reservas_pro_cron_morning_summary()` | "Reservas hoje: {total} • {N pessoas} no total • {V VIPs}" |
| 4 | `reservation_late_cancel` | UPDATE status → cancelled, <2h antes | `trg_reservation_late_cancel` | "Cancelamento tardio (oportunidade) • Mesa {N} pessoas livre as {hora}" |
| 5 | `reservation_arrived` | RPC `client_arrived(reservation_id)` | dentro do RPC | "Cliente chegou • {nome} • {N} pessoas • prepara mesa" |
| 6 | `waitlist_new` | INSERT `reservation_waitlist` (status=waiting) | `trg_waitlist_notify_partner_new` | "Novo cliente em espera • {nome} • {N} pessoas • {data}" |
| 7 | `reservation_notify_dispatched` | UPDATE status → cancelled + auto-match notify list | `trg_reservation_late_cancel` (after match) | "Notify list activada • {X} clientes notificados — possível substituição automática" |
| 8 | (VIP entrou) — TODO F4 | quando reserva criada por cliente com `is_vip=true` no profile | (F4) | "Cliente VIP {nome} reservou para {data hora}" |
| 9 | (Blocked tentou) — TODO F4 | quando RPC raise `client_blocked_at_restaurant` | (F4) | "Cliente bloqueado tentou reservar — auditar" |

## 7 Push Cliente automáticos

| # | Kind | Trigger | Origem | Mensagem |
|---|---|---|---|---|
| 1 | (Reserva confirmada) — fluxo existente | parceiro accept | já existente fora F2 | — |
| 2 | (Reserva rejeitada) — fluxo existente | parceiro reject | já existente fora F2 | — |
| 3 | `reservation_reminder_24h` | CRON 30min, reservas em 23-25h | `_reservas_pro_cron_send_reminders_24h()` | "Reserva amanhã! Lembramos a tua reserva amanhã as {hora} • {N} pessoas" |
| 4 | `reservation_reminder_2h` | CRON 15min, reservas em 105-135min | `_reservas_pro_cron_send_reminders_2h()` | "Reserva em 2 horas • A tua reserva e as {hora} • {N} pessoas" |
| 5 | `reservation_seated` | UPDATE `seated_at` IS NOT NULL | `trg_reservation_seated` | "Mesa pronta! O parceiro já te sentou. Bom apetite!" |
| 6 | `reservation_notify_match` | Auto-match notify list (max 5 FIFO) após cancelamento | `_reservas_pro_match_notify_list()` | "Vagou! Mesa disponível • Tens 15min para confirmar a reserva no horário que pediste." |
| 7 | (Waitlist chamado) — TODO F4 | parceiro promove cliente da fila | (F4) | "É a tua vez! Tens X min para confirmar." |

## Auto-Logic Disparado

### Auto-VIP

Trigger: `_reservas_pro_update_client_profile(client_id, restaurant_id, 'visit')`
chamado em `trg_reservation_finished` (UPDATE `finished_at`).
Após `total_visits >= 5` → `is_vip = true` (única transição).

### Auto-Block

Disparado pelo mesmo helper com `action='no_show'` ou `'late_cancel'`:

- `no_show`: incrementa `total_no_shows`. Se atingir threshold
  `reservation_no_show_threshold_count` (default 3) →
  `is_blocked=true`, `blocked_reason='auto_no_show_threshold'`.
- `late_cancel`: incrementa `total_late_cancels`. Disparado por
  `trg_reservation_late_cancel`. Se atingir threshold
  `reservation_late_cancel_threshold_count` (default 5) →
  `is_blocked=true`, `blocked_reason='auto_late_cancel_threshold'`.

Ambos thresholds configuráveis em `platform_settings`.

### Notify List Auto-Match (modelo OpenTable Notify)

Ao detectar late cancel (`trg_reservation_late_cancel`):
1. Push parceiro "oportunidade" (#4 acima).
2. `_reservas_pro_match_notify_list()` procura clientes na
   `reservation_notify_list` compatíveis:
   - Mesmo `restaurant_id`
   - `status='active'`
   - `target_date = slot_time::date`
   - `people <= cancelled_party`
   - `ABS(target_time - slot_time) ≤ flexibility_minutes`
   - `expires_at > NOW()`
3. Limita a 5 (FIFO por `created_at`).
4. Cada match: marca `status='notified'`, push cliente (#6 acima).
5. Se ≥1 match: push parceiro extra (#7 acima).

## CRON Schedule Resumido

| Job | Schedule | Função |
|---|---|---|
| `reservas_pro_reminders_24h` | `*/30 * * * *` | reminders 24h antes (cliente) |
| `reservas_pro_reminders_2h` | `*/15 * * * *` | reminders 2h antes (cliente) |
| `reservas_pro_pending_alert` | `* * * * *` | alerta parceiro >5min sem resposta |
| `reservas_pro_morning_summary` | `0 8 * * *` | sumário 8h UTC ao parceiro |
| `reservas_pro_expire_lists` | `0 * * * *` | expira waitlist + notify_list antigos |

## Activação FCM Real (post-launch)

Em `_reservas_pro_notify_partner_push`, descomentar bloco:

```sql
PERFORM net.http_post(
  url := current_setting('app.supabase_url') || '/functions/v1/notify-partner',
  headers := jsonb_build_object('Content-Type','application/json'),
  body := jsonb_build_object(
    'user_id', p_partner_user_id,
    'title', p_title,
    'body', p_body,
    'kind', p_kind
  )
);
```

Pré-requisitos:
1. Firebase Service Account configurado em Supabase secrets
2. Edge Function `notify-partner` deployed (já existe stub)
3. Setting `app.supabase_url` configurado via `ALTER SYSTEM SET`
4. Driver tokens FCM persistidos em `driver_fcm_tokens` (TODO separado)
