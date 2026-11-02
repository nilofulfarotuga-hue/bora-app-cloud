-- APLICADA EM PRODUÇÃO (versão 20261102020808, pela Claude.ai por MCP). Reaplicada sem efeito
-- (é idempotente) na versão 20261102051537 com o mesmo nome. Copiar tal e qual para
-- supabase/migrations/ (a bora-tranca recusa esta escrita na sessão). Texto lido de
-- supabase_migrations.schema_migrations a 02/11/2026.
-- Missão stripe-empresa-2026-11-01 (autorização do Danilo 01/11/2026 22:03).
-- Aplicada pela Claude.ai por MCP (02/11/2026 ~02:15) porque o pedido de permissão da sessão
-- "Ligar app à Stripe empresa" ficou mais de 1 h sem resposta. SQL igual ao da sessão.
-- Duas contas Stripe: TVDE fica na PESSOAL; o resto passa para a EMPRESA.
-- Só ACRESCENTA: coluna stripe_account ('pessoal'|'empresa', default 'pessoal') nas tabelas
-- que guardam PaymentIntents (tudo o que já existe = 'pessoal') e users.stripe_customer_id_empresa.
-- Não mexe em preços, comissões, Connect, RLS nem em dados existentes. tvde_* não leva coluna.

do $$
declare
  t text;
begin
  foreach t in array array[
    'orders', 'payment_drafts', 'pending_charges', 'tips', 'cleaning_bookings',
    'carwash_bookings', 'reservations', 'appointments', 'pedido_morada_trocada',
    'stripe_webhook_events', 'payment_client_failures', 'stripe_extrato_contabilista'
  ] loop
    if to_regclass('public.' || t) is null then
      raise notice 'stripe_duas_contas: tabela % não existe, salta', t;
      continue;
    end if;
    execute format(
      'alter table public.%I add column if not exists stripe_account text not null default ''pessoal''', t);
    if not exists (
      select 1 from pg_constraint
      where conrelid = ('public.' || t)::regclass and conname = t || '_stripe_account_chk'
    ) then
      execute format(
        'alter table public.%I add constraint %I check (stripe_account in (''pessoal'',''empresa''))',
        t, t || '_stripe_account_chk');
    end if;
    execute format('comment on column public.%I.stripe_account is %L', t,
      'Conta Stripe onde o dinheiro entrou: pessoal (TVDE e cobranças antigas) ou empresa (Unipessoal Lda, desde 01/11/2026). Reembolsos e capturas usam SEMPRE esta conta.');
  end loop;
end $$;

create index if not exists orders_stripe_account_idx on public.orders (stripe_account) where payment_intent_id is not null;
create index if not exists stripe_webhook_events_stripe_account_idx on public.stripe_webhook_events (stripe_account, received_at desc);

alter table public.users add column if not exists stripe_customer_id_empresa text;
comment on column public.users.stripe_customer_id_empresa is
  'Stripe Customer na conta da EMPRESA (acct_1UX67LGWwQxC9wR2). stripe_customer_id é o da conta pessoal (TVDE).';
