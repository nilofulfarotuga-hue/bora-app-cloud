-- 05/10 (Danilo autorizou): o cron bora_weekly_auto_payout (jobid 2) criava "pagamentos" fantasma toda a
-- segunda às 03:00 (tabela payouts, que ninguém paga) e lançava linhas NEGATIVAS type='payout' no ledger
-- (10 linhas, 173,50 € de 07/09 a 05/10) sem nenhum dinheiro ter saído. O acerto semanal real não usa isto.
select cron.alter_job(2, active := false);
create table if not exists public.bkp_payouts_20261005 as select * from public.payouts;
alter table public.bkp_payouts_20261005 enable row level security;
-- ledger é só-acrescentar: anula-se cada fantasma com a linha inversa (+valor), mesma referência marcada
insert into public.ledger_entries (user_id, user_type, order_id, amount, type, reference)
select le.user_id, le.user_type, null, -le.amount, 'payout', le.reference || ' (estorno fantasma 2026-10-05)'
  from public.ledger_entries le
 where le.type='payout' and le.order_id is null and le.reference like 'payout:%' and le.amount < 0
   and not exists (select 1 from public.ledger_entries e where e.reference = le.reference || ' (estorno fantasma 2026-10-05)');
update public.payouts set status='failed' where status='pending';
revoke all on function public.auto_payout_pending(numeric) from public, anon, authenticated;
comment on function public.auto_payout_pending(numeric) is 'DESLIGADA 05/10/2026 — gerava payouts fantasma; o acerto semanal real é por partner_weekly_settlements/compute_driver_settlement.';
