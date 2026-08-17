# FECHO SEMANAL DO SISTEMA + 2 tarefas do teste do Valdemir — ESTADO (retomável)

> Missão iniciada 2026-08-17 · Motor: Opus 4.8 (PC) · Branch: `autonomous-night/fase2-cortex-tasks`
> NÃO TOCAR (aplicado pela Claude.ai 17/08): FK settlements→drivers(user_id); `driver_earnings_summary` v3
> (devolve dia/semana/semana_passada/ultimo_acerto); settings `tvde_cancel_full_after_grace=false` e
> `tvde_cancel_fee_cents=250`. Verdade = produção via MCP. Cada fase: MARCO + commit + push + analyze 0 erros.

## Plano de fases
- [ ] **F1 — ECRÃ DE GANHOS** (Flutter, zona 🟢): tela exibe HOJE/ESTA SEMANA/SEMANA PASSADA/ÚLTIMO ACERTO
      + extrato; RPC `driver_earnings_summary` já manda tudo (zero contas no Dart); acessível do HOME do motorista; PT-PT.
- [ ] **F2 — TAXA TVDE (💰 PROPOSE-ONLY até "vai")**: `tvde_cancel_ride` — `v_had_driver` = SÓ `driver_id IS NOT NULL`;
      fee pós-aceite = taxa FIXA `tvde_cancel_fee_cents` (não `est_fare_cents`); religar `tvde_cancel_full_after_grace=true`.
      Prova SQL 3 casos: sem aceite→0; pós-aceite (pós-graça)→250; no-show→€3,50 (caminho próprio). NÃO aplicar sem "vai".
- [ ] **F3 — SISTEMA DE FECHO SEMANAL** (o pedido grande): camada de COMUNICAÇÃO pós-crons, cron novo 2.ª 09:00.
      1. Compilador `weekly-closeout-digest` (RPC/EF) → `weekly_digest_log` (RLS admin): por pessoa/parceiro, ganhos por
         item + tokens + saldo + DIREÇÃO (recebe/deve/zerado), lendo settlements+payouts das verticais.
      2. Emails individuais (HTML verde PT-PT, recibo). Quem deve: bloco MB Way (setting `bora_mbway_phone`, criar VAZIA;
         sem número → "entraremos em contacto"). GATE RESEND: enviar de verdade SÓ ao email do Danilo; resto grava
         `aguarda_dominio`. Setting `weekly_digest_emails_enabled` (default false).
      3. Resumo ao Danilo (funciona JÁ): push admin persistente (notify-admin-urgent data-only) + email Gmail + Telegram.
         "A PAGAR: nome €X (MB Way tel)… A RECEBER: nome €Y… Zerados: N". Tel = drivers.phone/partner; campo opc. `mbway_phone`.
      4. Painel admin PT-BR "Acertos da semana": lista (pessoa, valor, direção, estado), "Marcar pago" (auditoria),
         "Reenviar email", campo MB Way do Bora + toggle envio externo.
      5. Prova: compilador sobre a semana 11–17/08 real (Valdemir acerto -€0,80): mostrar weekly_digest_log, email do
         Danilo recebido, push persistente. Print do template.
- [ ] **F4 — FECHO**: relatório + vault + `platform_settings.relatorio_fecho_semanal_sistema` + Córtex (verde) + digest
      Hermes 8 linhas + ctx doctor/stats.

## Verdade de produção (confirmada via MCP 2026-08-17)
- `driver_earnings_summary()` → jsonb `{ok, dia:{total_cents,tokens}, semana:{}, semana_passada:{}, ultimo_acerto:<row>, itens:[{ts,tipo,descricao,valor_cents,tokens}]}`. Fontes: ledger_entries(earning)+tvde_rides(finalizada)+bora_tokens; settlement de `driver_weekly_settlements`.
- `tvde_cancel_ride(p_ride_id uuid, p_actor text, p_reason text)` → v_had_driver inclui offer/tried; fee pós-aceite = est_fare_cents. (A MUDAR em F2.)
- **Crons de fecho (2.ª feira)**: `close-weekly-settlements` 00:05 → `run_weekly_closeout()`; `bora_weekly_auto_payout` 03:00 → `auto_payout_pending(10.0)`; `appt-weekly-payout` 08:00 → `compute_all_provider_weekly_payouts()`; `cleaning-weekly-settlement` 08:00 → `compute_all_cleaner_weekly_settlements()`. Novo cron F3 = 09:00 (depois de todos).
- **Tabelas de settlement (shape consistente: week_start_at/end_at, direction, status, paid_at/by, notes)**: `driver_weekly_settlements` (driver_id, total_earnings, net_balance), `cleaner_weekly_settlements` (cleaner_id, net_payout_cents), `appointment_payouts` (provider_id, net_payout_cents), `partner_weekly_settlements` (partner_id, net_balance). `direction` já dá recebe/deve/zerado.

## MARCOS

### MARCO F1 (ecrã de ganhos) — 2026-08-17 ✓
- A tela `DriverEarningsScreen` já existia e já consumia `driver_earnings_summary`, mas só exibia HOJE + ESTA
  SEMANA. Acrescentei **SEMANA PASSADA** e **ÚLTIMO ACERTO** (helpers `_miniSemana` + `_acertoBlock`), tudo da
  RPC (zero contas no Dart; net_balance do settlement vem em euros → `eurRaw`).
- **Acesso do Valdemir (TVDE)**: o `_openEarnings` do `tvde_driver_home_screen` apontava para a
  `TvdeDriverEarningsScreen` (só `.from('tvde_rides')`, sem resumo nem settlement). Re-apontado para a
  **`DriverEarningsScreen` unificada** (o extrato dela já inclui as corridas TVDE). Import trocado.
- `TvdeDriverEarningsScreen` fica órfã (dead code, não apagada — nota). `flutter analyze`: **0 erros**,
  0 issues novos (driver_earnings_screen limpo; 12 info pré-existentes no tvde_home em linhas não tocadas).
- Ficheiros: `lib/screens/driver_earnings_screen.dart`, `lib/screens/driver/tvde/tvde_driver_home_screen.dart`.

### F2 (taxa TVDE) — PROPOSTA PRONTA (💰 aguarda "vai")
- Migration completo + 3 mudanças + plano de prova em `.claude/.ai/reports/F2_TVDE_CANCEL_PROPOSTA.md`.
  Falta: provar por rollback tx os 3 casos, e (só com "vai") aplicar função + religar `tvde_cancel_full_after_grace`.
