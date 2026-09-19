# Reservas PRO F2 — Notification Flows (16 momentos)

Todas as notificações via `_push_in_app_notification` (helper plataforma).
FCM real comentado em `_reservas_pro_notify_partner_push` (post-launch).

## 9 Push Parceiro

| # | Kind | Trigger | Quando |
|---|---|---|---|
| 1 | `reservation_new_pending` | `trg_reservation_notify_partner_new` | INSERT reservation pending |
| 2 | `reservation_pending_alert` | CRON 1min `_reservas_pro_cron_pending_too_long` | pending 5-10min sem resposta |
| 3 | `morning_summary` | CRON 8h UTC `_reservas_pro_cron_morning_summary` | sumário diário |
| 4 | `reservation_late_cancel` | `trg_reservation_late_cancel` | cancelado <2h antes |
| 5 | `reservation_arrived` | RPC `client_arrived` | cliente carrega "estou aqui" |
| 6 | `waitlist_new` | `trg_waitlist_notify_partner_new` | INSERT waitlist |
| 7 | `reservation_notify_dispatched` | `trg_reservation_late_cancel` (after match) | notify list disparada |
| 8 | (VIP entrou) — TODO F4 | — | reserva por cliente VIP |
| 9 | (Blocked tentou) — TODO F4 | — | RPC raise blocked |

## 7 Push Cliente

| # | Kind | Trigger | Quando |
|---|---|---|---|
| 1 | reserva confirmada — fluxo existente | parceiro accept | — |
| 2 | reserva rejeitada — fluxo existente | parceiro reject | — |
| 3 | `reservation_reminder_24h` | CRON 30min | reservas em 23-25h |
| 4 | `reservation_reminder_2h` | CRON 15min | reservas em 105-135min |
| 5 | `reservation_seated` | `trg_reservation_seated` | UPDATE seated_at |
| 6 | `reservation_notify_match` | `_reservas_pro_match_notify_list` | match notify (15min para confirmar) |
| 7 | (Waitlist chamado) — TODO F4 | — | parceiro promove |

## Auto-Logic

- **Auto-VIP**: `total_visits >= 5` em `_reservas_pro_update_client_profile('visit')`.
- **Auto-Block no-show**: threshold `reservation_no_show_threshold_count` (default 3).
- **Auto-Block late_cancel**: threshold `reservation_late_cancel_threshold_count` (default 5).
- **Notify Match**: max 5 FIFO, modelo OpenTable Notify.

## CRON Schedule

| Job | Cron | Função |
|---|---|---|
| `reservas_pro_reminders_24h` | `*/30 * * * *` | reminders 24h |
| `reservas_pro_reminders_2h` | `*/15 * * * *` | reminders 2h |
| `reservas_pro_pending_alert` | `* * * * *` | alerta parceiro |
| `reservas_pro_morning_summary` | `0 8 * * *` | sumário 8h UTC |
| `reservas_pro_expire_lists` | `0 * * * *` | expira waitlist + notify |
