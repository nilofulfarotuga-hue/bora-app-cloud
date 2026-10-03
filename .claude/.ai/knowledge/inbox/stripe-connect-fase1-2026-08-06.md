# Handoff → bibliotecario-cerebro: Stripe Connect Fase 1 FECHADA (2026-08-06)

Factos novos para o Cérebro (verificar e arquivar):

1. **Stripe Connect Fase 1 em produção** (commit `c760a5b`, push confirmado):
   colunas `stripe_*` nas 4 tabelas de dono + `partner_statement_lines` +
   `stripe_connect_events` + RPCs (`get_statement`, `get_my_connect_status`,
   `apply_stripe_account_update`, `admin_list_connect_accounts`,
   `stripe_connect_fee_cents` = função ÚNICA da taxa). 3 Edge Functions novas:
   `stripe-connect-onboard` (JWT), `stripe-connect-webhook` (secret próprio
   `STRIPE_CONNECT_WEBHOOK_SECRET`, SEPARADO do stripe-webhook), `stripe-connect-admin`.
2. **Nada de dinheiro se move nesta fase** — `stripe_connect_enabled=false`;
   acerto semanal continua manual. Transferências automáticas = Fase 2.
3. **Gotchas aprendidos:**
   - Stripe Account Links só aceitam http(s) — deep link nativo não serve;
     retorno é `bora-app-web.pages.dev/connect/*`.
   - plpgsql: `array_text || 'literal'` é ambíguo (malformed array literal);
     usar `array_append`. Apanhado por prova real antes do commit.
   - A Trava bloqueia `DROP POLICY` em tabela com nome "financeiro" mesmo em
     migration nova — não incluir DROPs cosméticos.
   - `platform_settings`: escrita só via RPC `admin_update_setting` (já existia).
4. **Pendências humanas (Danilo):** ativar Connect no dashboard + webhook novo +
   colar `STRIPE_CONNECT_WEBHOOK_SECRET`; teste em modo teste antes de ligar.
   Guia: `GUIA_DANILO_STRIPE_CONNECT.md` (raiz do repo).

Relatório completo: `.claude/.ai/relatorios/stripe-connect-fase1-2026-08-06.md`
