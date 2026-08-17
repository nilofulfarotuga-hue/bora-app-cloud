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

### MARCO F3.1–F3.3 (fundação + compilador + EF) — 2026-08-17 ✓
- **F3.1** aplicado: colunas `mbway_phone` em cleaners/restaurants/service_providers (drivers já tinha);
  tabela `weekly_digest_log` (RLS admin); settings `bora_mbway_phone`(vazia) + `weekly_digest_emails_enabled`(false).
- **F3.2** `weekly_closeout_compile(p_week_start)` (RPC): lê os 4 settlements, normaliza net SIGNED
  (positivo=Bora paga, negativo=deve), breakdown por vertical, upsert em weekly_digest_log.
  **PROVADO** semana 2026-08-09: `to_receive: Valdemir €0,80 (MB Way +351964235084)`, to_pay [], zerados 0.
- **F3.3** EF `weekly-closeout-digest` (v2, ACTIVE): chama o compilador → emails individuais com GATE
  (Valdemir → `aguarda_dominio`, correto) → resumo ao Danilo. **PROVADO**: `admin_push=true` (push
  persistente via notify-admin-urgent, fix = reencaminhar o authHeader). Telegram via vault (existe).
- ⚠️ **BLOQUEIO HUMANO — `RESEND_API_KEY` não está nas secrets das EFs** (`resend_key_present=false`;
  não está no backend/.env). Por isso NENHUM email das EFs sai (nem o da notify-admin-urgent crosstalk).
  O email está code-complete; falta o Danilo **definir RESEND_API_KEY** nas Edge Function secrets do
  Supabase. Sem isso: push+Telegram funcionam; emails ficam preparados (aguarda_dominio) e não saem.

### MARCO F3.4 (cron) + F3.5a (RPCs admin) — 2026-08-17 ✓
- **F3.4** cron `weekly-closeout-digest` `0 9 * * 1` (2.ª 09:00 UTC, depois de todos os settlements) →
  invoca a EF via pg_net (padrão project_url/service_role_key do vault).
- **F3.5a** RPCs admin (is_admin guard): `admin_weekly_closeout_list` (lista + join estado pago),
  `admin_mark_settlement_paid` (muda ESTADO do settlement, não valor + log_admin_action),
  `admin_update_weekly_closeout_settings` (MB Way + toggle), `admin_resend_weekly_digest` (re-invoca EF).
  **PROVADO** (identidade admin do Danilo): lista devolve Valdemir −80/owes_bora/pending/aguarda_dominio + breakdown.
- Migrations aplicadas via MCP; registo em `supabase/migrations/20260817090000_weekly_closeout_system_f3.sql`.

### MARCO F3.5b (tela Flutter) + F3.6 (prova) — 2026-08-17 ✓
- **F3.5b** `lib/screens/admin/admin_acertos_semana_screen.dart` (PT-BR): seletor de semana, card de config
  (MB Way do Bora editável + toggle envio externo + reenviar), KPIs, listas "A RECEBER (devem)" e "A PAGAR",
  cada item com valor/direção/MB Way/estado-email/estado-pago + botão "Marcar pago". Ligada no
  `admin_dashboard_screen` (import + _NavCard no topo do grupo de fechos). `analyze` 0 erros, 0 issues meus.
- **F3.6 PROVA consolidada** (semana 2026-08-09, Valdemir −€0,80): compilador → `to_receive Valdemir €0,80`;
  EF → `admin_push=true` (resumo persistente ao Danilo), Valdemir email `aguarda_dominio` (gate); lista admin
  devolve tudo. ⚠️ Email do Danilo NÃO recebido: `RESEND_API_KEY` não está nas EF secrets (ação humana).
- **F3 COMPLETO.** Falta F4 (fecho: relatório + vault + platform_settings + Córtex + Hermes + ctx).

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

### F2 (taxa TVDE) — PROPOSTA PRONTA + PROVA (💰 aguarda "vai")
- Migration completo + 3 mudanças em `.claude/.ai/reports/F2_TVDE_CANCEL_PROPOSTA.md`.
- **PROVA (simulação SQL da lógica proposta com settings reais 250/350/180)**: caso 1 (sem aceite, driver_id
  NULL) → **0**; caso 2 (pós-aceite, passada a graça) → **250**; caso 3 (no-show) → **350**. ✓
- ⚠️ **Falta só o "vai"**: aplicar a função (apply_migration) + `UPDATE platform_settings tvde_cancel_full_after_grace=true`.
  NÃO aplicado (dinheiro real). Nota pendente: cancelar corrida-de-plano pós-aceite passa de 350→250.
