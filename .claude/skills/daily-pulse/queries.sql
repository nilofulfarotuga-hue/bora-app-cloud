-- daily-pulse — queries canónicas (read-only). Projeto: ojykpzwqrtusfeakzrna
-- Correr via MCP Supabase execute_sql. As views são socio_ai_faseA_kpi_views.

-- 1) Últimos 7 dias de KPIs
select dia, pedidos_criados, pedidos_entregues, pedidos_cancelados,
       clientes_unicos, gmv_eur, ticket_medio_eur, comissao_plataforma_eur,
       pedidos_parceiro, pedidos_dinheiro, pedidos_online
from public.v_kpis_diarios
order by dia desc
limit 7;

-- 2) GMV agregado dos últimos 7 dias (número único)
select round(coalesce(sum(gmv_eur),0),2) as gmv_7d,
       coalesce(sum(pedidos_entregues),0) as entregues_7d
from public.v_kpis_diarios
where dia >= (now() at time zone 'Europe/Lisbon')::date - 7;

-- 3) Funil dos últimos 7 dias
select dia, criados, comprometidos_pagamento, despachados, entregues, cancelados,
       taxa_conversao_pct, taxa_cancelamento_pct
from public.v_funil_checkout
order by dia desc
limit 7;

-- 4) Estafetas agora (snapshot)
select * from public.v_drivers_online_agora;
