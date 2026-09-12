# Repasse Semanal da Limpeza — Relatório

**Data:** 2026-07-19 · **Branch:** `autonomous-night-2026-04-29` · Modo Protecção Total.
**Estado do dinheiro:** aditivo e reversível — **não altera** nenhum valor cobrado ou pago;
apenas **consolida** por semana o `cleaner_earnings_cents` que já era calculado por booking.

## 1. O buraco que este trabalho fecha
Todas as verticais tinham fecho/repasse semanal **menos a limpeza**:

| Vertical | Fecho semanal |
|---|---|
| Estafeta | ✅ `driver_weekly_settlements` (cron seg) |
| Restaurante | ✅ `partner_weekly_settlements` |
| Beleza | ✅ `appointment_payouts` (cron seg 8h) |
| TVDE | ✅ `tvde_driver_balances` |
| **Limpeza** | ❌ **nada consolidava** → agora ✅ `cleaner_weekly_settlements` |

Cada `cleaning_booking` gravava `cleaner_earnings_cents` (85% + produtos, no ato), mas não
havia como saber **quanto a Bora deve a cada profissional de limpeza por semana**. Agora há.

## 2. O que foi criado (copiando o padrão comprovado do estafeta/beleza)

### Banco — `supabase/migrations/20260719000000_cleaner_weekly_settlements.sql` (aplicada em prod)
- **Tabela `cleaner_weekly_settlements`**: `cleaner_id`, `week_start_at`, `week_end_at`,
  `total_jobs`, `total_earnings_cents`, `total_bora_fee_cents`, `net_payout_cents`,
  `direction` (`bora_to_cleaner`), `status` (`pending`/`paid`/`received`/`disputed`),
  `payment_method`, `payment_reference`, `paid_at`, `paid_by`, `notes`.
  `UNIQUE(cleaner_id, week_start_at)`.
  - **RLS:** leitura pela **própria** profissional (`cleaner_id → cleaners.user_id`) **OU** admin
    (`is_admin()`); escrita só admin. Espelha `appointment_payouts`.
- **`compute_cleaner_weekly_settlement(p_cleaner_id, p_week_start=NULL, p_persist=true)`** e
  **`compute_all_cleaner_weekly_settlements()`**:
  - Usam a função de bounds **reutilizada** `driver_settlement_week_bounds(anchor)`
    (semana **seg→dom Europe/Lisbon**) — **não** foi duplicado cálculo de semana.
  - Upsert `ON CONFLICT (cleaner_id, week_start_at)` (preserva `status`/`paid_at` de fechos
    já pagos), igual ao padrão beleza.
- **Cron `cleaning-weekly-settlement`** — `0 8 * * 1` (segunda 8h), idempotente
  (unschedule antes). Confirmado instalado (`cron.job` = 1 linha).
- **RPCs admin** (espelham o trio da beleza, guardadas por `_admin_op_guard()` + `log_admin_action`):
  `admin_list_cleaner_settlements`, `admin_mark_cleaner_settlements_paid`,
  `admin_recompute_cleaner_week`.

### Admin (PT-BR) — `lib/screens/admin/admin_cleaner_settlements_screen.dart`
Espelha `admin_appointments_payouts_screen.dart`. Ligado no dashboard, secção **"Limpeza doméstica"**.
- Lista fechos por semana e por profissional: nº de serviços, líquido a repassar, taxa Bora, status.
- Filtros por **status** (pendente/pago/todos) e por **profissional**.
- **"Marcar como pago"** (dupla confirmação → RPC grava `status='paid'`, `paid_at`, `paid_by`,
  `payment_method`, `payment_reference`).
- **"Recalcular semana atual"** (header) e **recalcular a semana de um fecho** (ícone por linha).

## 3. A fórmula (regra crítica de dinheiro)
```
Para cada semana (seg→dom Lisbon) e cada profissional:
  bookings elegíveis = status='completed' E is_test_order=false
                       E data_do_serviço ∈ [week_start, week_end]
  data_do_serviço = COALESCE(completed_at, scheduled_at)   -- SERVIÇO FEITO, nunca a data do pagamento
  total_jobs           = COUNT(bookings elegíveis)
  total_earnings_cents = SUM(cleaner_earnings_cents)        -- já é 85% + produtos
  net_payout_cents     = total_earnings_cents               -- o que a Bora deve à profissional
```
**Conservador (documentado para o Danilo rever):** cancelados / no-show **não** entram no ganho —
não existe regra de compensação de limpeza documentada, logo **não se paga em dúvida**. Bookings
marcados `is_test_order=true` também são **excluídos** (a coluna existe em `cleaning_bookings`;
o modelo do estafeta não a tinha).

## 4. Prova do teste da soma (executado em prod, com rollback automático)
Inseri 5 bookings numa semana isolada (2030-06-03→09) e chamei `compute_...(persist=false)`:

| Booking | status | is_test | semana | earnings | conta? |
|---|---|---|---|---|---|
| A | completed | não | dentro | **2000** | ✅ |
| B | completed | não | dentro | **3000** | ✅ |
| C | cancelled_client | não | dentro | 9999 | ❌ (não-completo) |
| D | completed | **sim** | dentro | 7777 | ❌ (teste) |
| E | completed | não | **fora** (semana anterior) | 8888 | ❌ (fora da janela) |

**Resultado devolvido pela função:**
```json
{ "total_jobs": 2, "total_earnings_cents": 5000, "net_payout_cents": 5000,
  "total_bora_fee_cents": 750, "week_start": "2026-...03 00:00 Lisbon",
  "week_end": "...09 23:59 Lisbon" }
```
Soma **apenas os 2 completos** (2000+3000 = **5000**; taxa 300+450 = 750). Cancelado, teste e
fora-da-semana **ignorados**. Bounds seg→dom Lisbon corretos. O `RAISE` abortou a transação →
**nada de teste persistiu** (confirmado: `cleaner_weekly_settlements` = 0 linhas,
0 bookings de 2030 na base).

## 5. Como o admin usa
1. Painel admin → **Limpeza doméstica** → **"Fechamento Semanal — Limpeza"**.
2. O cron cria os fechos automaticamente toda segunda 8h; ou o admin usa **"Recalcular semana atual"**.
3. Filtra por profissional/status, confere o líquido, paga por MB WAY, e clica **"Marcar como pago"**
   (dupla confirmação; regista `paid_at`/`paid_by` + `log_admin_action`).

## 6. Qualidade / segurança
- `flutter analyze` nos ficheiros tocados: **0 erros, 0 issues no ecrã novo** (o único `info`
  `prefer_const` em `admin_dashboard_screen.dart:239` é pré-existente, fora das linhas alteradas).
- **Nenhuma zona protegida tocada:** não mexe em `dispatch_engine`, `pricing_service`,
  `finalizePurchase`, `bora_tokens`, Stripe/webhook, nem RLS de `orders`/`wallets`/`ledger`.
- Reutiliza `driver_settlement_week_bounds` (sem duplicar cálculo de semana).
- Tudo idempotente e reversível (CREATE ... IF NOT EXISTS, CREATE OR REPLACE, cron unschedule/schedule).
