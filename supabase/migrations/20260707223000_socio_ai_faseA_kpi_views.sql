-- Socio-AI Fase A -- views KPI read-only (aplicada via MCP em 2026-07-07).
-- "olhos" para o Hermes/Robo B: GMV, funil, estafetas. NAO tocam logica financeira.
-- Reversiveis. Excluem is_test_order. Dia = fuso Europe/Lisbon. Acesso: service_role.

create or replace view public.v_kpis_diarios as
select
  (o.created_at at time zone 'Europe/Lisbon')::date                    as dia,
  count(*)                                                             as pedidos_criados,
  count(*) filter (where o.status = 'delivered')                      as pedidos_entregues,
  count(*) filter (where o.status in ('cancelled','rejected'))        as pedidos_cancelados,
  count(distinct o.user_id)                                           as clientes_unicos,
  round(coalesce(sum(coalesce(o.customer_total,o.total,o.final_total,o.price,0))
        filter (where o.status='delivered'),0),2)                     as gmv_eur,
  round(coalesce(avg(coalesce(o.customer_total,o.total,o.final_total,o.price))
        filter (where o.status='delivered'),0),2)                     as ticket_medio_eur,
  round(coalesce(sum(o.platform_commission)
        filter (where o.status='delivered'),0),2)                     as comissao_plataforma_eur,
  count(*) filter (where o.is_partner_store)                          as pedidos_parceiro,
  count(*) filter (where o.payment_method='cash')                     as pedidos_dinheiro,
  count(*) filter (where o.payment_method in ('card','mbway'))        as pedidos_online
from public.orders o
where coalesce(o.is_test_order,false) = false
group by 1;

create or replace view public.v_funil_checkout as
select
  (o.created_at at time zone 'Europe/Lisbon')::date                    as dia,
  count(*)                                                             as criados,
  count(*) filter (where o.payment_status='paid' or o.payment_method='cash') as comprometidos_pagamento,
  count(*) filter (where o.status in ('driverAccepted','pickedUp','onTheWay','delivered')) as despachados,
  count(*) filter (where o.status='delivered')                        as entregues,
  count(*) filter (where o.status in ('cancelled','rejected'))        as cancelados,
  round(100.0 * count(*) filter (where o.status='delivered')
        / nullif(count(*),0), 1)                                      as taxa_conversao_pct,
  round(100.0 * count(*) filter (where o.status in ('cancelled','rejected'))
        / nullif(count(*),0), 1)                                      as taxa_cancelamento_pct
from public.orders o
where coalesce(o.is_test_order,false) = false
group by 1;

create or replace view public.v_drivers_online_agora as
select
  count(*) filter (where d.is_online and coalesce(d.is_banned,false)=false)              as online_agora,
  count(*) filter (where d.is_online and d.last_heartbeat_at > now() - interval '2 minutes') as online_heartbeat_2min,
  count(*) filter (where d.approval_status='approved')                                   as aprovados,
  count(*) filter (where d.approval_status='pending')                                    as pendentes_aprovacao,
  count(*) filter (where coalesce(d.is_banned,false))                                     as banidos
from public.drivers d
where d.deleted_at is null;

comment on view public.v_kpis_diarios         is 'Socio-AI Fase A: KPIs diarios. Read-only.';
comment on view public.v_funil_checkout       is 'Socio-AI Fase A: funil + taxas. Read-only.';
comment on view public.v_drivers_online_agora is 'Socio-AI Fase A: snapshot estafetas. Read-only.';

revoke all on public.v_kpis_diarios, public.v_funil_checkout, public.v_drivers_online_agora from anon, authenticated;
grant select on public.v_kpis_diarios, public.v_funil_checkout, public.v_drivers_online_agora to service_role;
