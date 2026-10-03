-- Bloco 0 — MAPA DO DINHEIRO — consultas corridas em produção a 20/09/2026 (MCP execute_sql).
-- Resultados transcritos em docs/MAPA-DO-DINHEIRO.md. Só SELECT.

-- 0.1 quem escreve em cada arca (pg_proc)
with t as (select unnest(array['wallet_transactions','client_wallets','driver_transactions','driver_balances','driver_weekly_settlements','order_receipts_v2','bora_tokens','ledger_entries','payouts','partner_weekly_settlements','cleaner_weekly_settlements','washer_weekly_settlements']) as tbl),
f as (select p.proname, lower(p.prosrc) as src from pg_proc p where p.pronamespace = 'public'::regnamespace and p.prokind='f')
select t.tbl,
  string_agg(distinct f.proname, ', ' order by f.proname) filter (where f.src like '%insert into ' || t.tbl || '%' or f.src like '%insert into public.' || t.tbl || '%') as inserters,
  string_agg(distinct f.proname, ', ' order by f.proname) filter (where f.src like '%update ' || t.tbl || '%' or f.src like '%update public.' || t.tbl || '%') as updaters
from t left join f on f.src like '%' || t.tbl || '%' group by t.tbl order by t.tbl;

-- 0.2 totais por arca e tipo
select 'wallet_transactions' as arca, kind as tipo, count(*) as n, sum(amount_cents) as soma_cents from public.wallet_transactions group by kind
union all select 'driver_transactions', type || '/' || coalesce(status,'null'), count(*), round(sum(amount)*100)::bigint from public.driver_transactions group by type, status
union all select 'ledger_entries', user_type || '/' || type, count(*), round(sum(amount)*100)::bigint from public.ledger_entries group by user_type, type
union all select 'payouts', user_type || '/' || status, count(*), round(sum(amount)*100)::bigint from public.payouts group by user_type, status
union all select 'bora_tokens', role || '/' || (case when is_used then 'used' else 'unused' end), count(*), sum(amount) from public.bora_tokens group by role, is_used
union all select 'order_receipts_v2', reimbursement_status, count(*), sum(coalesce(reimbursement_amount_cents, driver_typed_total_cents)) from public.order_receipts_v2 group by reimbursement_status
union all select 'client_wallets', (case when free_balance_cents>0 then 'positivo' when free_balance_cents<0 then 'negativo' else 'zero' end), count(*), sum(free_balance_cents) from public.client_wallets group by 2
union all select 'driver_balances', (case when balance>0 then 'positivo' when balance<0 then 'negativo' else 'zero' end), count(*), round(sum(balance)*100)::bigint from public.driver_balances group by 2
order by 1,2;

-- 0.3 cliente: histórico (sem tokens) × saldo
with h as (select user_id, sum(amount_cents) filter (where kind <> 'refund_credit_tokens') as hist_livre_cents, sum(amount_cents) filter (where kind = 'refund_credit_tokens') as hist_tokens_cents, count(*) as n from public.wallet_transactions group by user_id)
select coalesce(h.user_id, w.user_id) as user_id, u.email, h.n, h.hist_livre_cents, h.hist_tokens_cents, w.free_balance_cents as saldo_app, (coalesce(h.hist_livre_cents,0) - coalesce(w.free_balance_cents,0)) as desacerto_cents
from h full outer join public.client_wallets w on w.user_id = h.user_id left join auth.users u on u.id = coalesce(h.user_id, w.user_id) order by abs(coalesce(h.hist_livre_cents,0) - coalesce(w.free_balance_cents,0)) desc;

-- 0.4 estafeta: driver_transactions × driver_balances × ledger
with dt as (select driver_id, round(sum(amount) filter (where type='delivery_earning')*100)::bigint as ganhos_cents, round(sum(amount) filter (where type='cash_adjustment')*100)::bigint as cash_adj_cents, round(sum(amount) filter (where type='token_conversion')*100)::bigint as tokens_conv_cents from public.driver_transactions group by driver_id),
le as (select user_id::uuid as driver_id, round(sum(amount)*100)::bigint as ledger_cents, round(sum(amount) filter (where type='earning')*100)::bigint as ledger_earn, round(sum(amount) filter (where type='cash_adjustment')*100)::bigint as ledger_cash_adj, round(sum(amount) filter (where type='payout')*100)::bigint as ledger_payout from public.ledger_entries where user_type='driver' and user_id ~ '^[0-9a-f-]{36}$' group by user_id)
select coalesce(dt.driver_id, db.driver_id, le.driver_id) as driver_id, d.name, dt.ganhos_cents, dt.cash_adj_cents, dt.tokens_conv_cents, round(db.balance*100)::bigint as saldo_driver_balances,
  (coalesce(dt.ganhos_cents,0)+coalesce(dt.tokens_conv_cents,0)-coalesce(dt.cash_adj_cents,0)) - coalesce(round(db.balance*100)::bigint,0) as desacerto_regra_sinal, le.ledger_cents, le.ledger_earn, le.ledger_cash_adj, le.ledger_payout
from dt full outer join public.driver_balances db on db.driver_id = dt.driver_id full outer join le on le.driver_id = coalesce(dt.driver_id, db.driver_id)
left join public.drivers d on d.user_id = coalesce(dt.driver_id, db.driver_id, le.driver_id) order by 2;

-- 0.5 ledger earning × driver_transactions delivery_earning, por pedido (os que diferem)
with l as (select order_id::text as oid, user_id as drv, round(amount*100)::int as ledger_cents from public.ledger_entries where user_type='driver' and type='earning'),
d as (select order_id::text as oid, driver_id::text as drv, round(amount*100)::int as dt_cents from public.driver_transactions where type='delivery_earning')
select coalesce(l.oid, d.oid) as order_id, coalesce(l.drv, d.drv) as driver, l.ledger_cents, d.dt_cents, o.status, o.payment_method, o.payment_status
from l full outer join d on d.oid = l.oid and d.drv = l.drv left join public.orders o on o.id = coalesce(l.oid, d.oid) where l.ledger_cents is distinct from d.dt_cents;

-- 0.6 TVDE: soma dos settle_cents dos eventos × tvde_driver_balances
with ev as (select r.driver_id, count(*) as n_eventos, sum((e.meta->>'settle_cents')::int) as soma_settle_cents from public.tvde_ride_events e join public.tvde_rides r on r.id = e.ride_id where e.status='finalizada' group by r.driver_id)
select coalesce(b.driver_id, ev.driver_id) as driver_id, d.name, round(b.balance*100)::bigint as tvde_balance_cents, ev.n_eventos, ev.soma_settle_cents, round(b.balance*100)::bigint - coalesce(ev.soma_settle_cents,0) as desacerto_cents
from public.tvde_driver_balances b full outer join ev on ev.driver_id = b.driver_id left join public.drivers d on d.user_id = coalesce(b.driver_id, ev.driver_id) order by 2;

-- 0.7 parceiro: acertos × ledger × payouts
select 'settlements' as arca, s.partner_id, s.week_start_at::date, s.total_orders, round(s.net_balance*100)::bigint as liquido_cents, s.direction||'/'||s.status, s.paid_at::date from public.partner_weekly_settlements s
union all select 'ledger', l.user_id, null, count(*)::int, round(sum(amount) filter (where type='earning')*100)::bigint, string_agg(distinct type, ','), null from public.ledger_entries l where l.user_type='restaurant' group by l.user_id
union all select 'payouts', p.user_id, null, count(*)::int, round(sum(amount)*100)::bigint, string_agg(distinct status, ','), null from public.payouts p where p.user_type='restaurant' group by p.user_id;

-- 0.8 tokens no histórico × bora_tokens
select wt.user_id, wt.related_order_id, wt.amount_cents, (select sum(t.amount) from public.bora_tokens t where t.user_id = wt.user_id and t.source_order_id = wt.related_order_id and t.role='client') as tokens_reais
from public.wallet_transactions wt where wt.kind='refund_credit_tokens';
