-- 01/11/2026 (Claude.ai): a tabela do vigia "pago sem pedido" estava aberta a qualquer visitante (RLS desligado,
-- anon com INSERT/UPDATE/DELETE). Quem tivesse a chave pública da app podia calar os avisos de pagamento sem pedido.
-- Só a função _cron_vigia_pago_sem_pedido (SECURITY DEFINER, dona postgres) a usa, e essa passa por cima do RLS.
-- (Aplicada em produção a 01/11/2026 — versão 20261101192326; espelho no repo escrito na missão
--  zona-vermelha-2026-11-01, SQL lido de schema_migrations.statements.)
alter table public.payment_drafts_alertados enable row level security;
do $do$
begin
  execute 'revoke all on table public.payment_drafts_alertados from anon, authenticated';
end
$do$;
