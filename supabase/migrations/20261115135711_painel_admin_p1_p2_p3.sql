-- Texto aplicado em produção a 15/11/2026 (schema_migrations.statements, versão 20261115135711); antes não estava em supabase/migrations.
-- No servidor, statements guardou um carregador (copiado abaixo, comentado) que executou, por esta ordem,
-- as cópias de P1, P2 e P3 de docs/propostas/painel-admin-15-11/ (commit c452aff4; net._http_response
-- 157548, 157549 e 157550), cada uma só depois de conferir o sha256. Cada parte abaixo é byte a byte o que correu.
--
-- >>> carregador gravado em schema_migrations.statements (versão 20261115135711):
-- -- Caixas 58, 59, 60 (commit c452aff4), lidas pela Claude.ai; executadas da copia byte a byte so com sha256 certo.
-- -- Ordem do Danilo 15/11 13:34 (painel: ver todos os pedidos, saldos, tickets; mapa ao vivo; editar estafeta).
-- do $aplicar$
-- declare
--   r record; v_sql text;
-- begin
--   for r in select * from (values
--       (157548::bigint, '8737404e4528659b3a13c2a9d85cfb00163a0c8ddafa3df950987aaf61a540b5'),
--       (157549::bigint, '924c42339cc621d70cece8b3def9dd3f9dd06e1ac94261865f5529b26ab1d542'),
--       (157550::bigint, '5aed6a23636edd37f7a7df3727bb2b2cc4208f0e8f7e673d4579d37aa8d158a7')) t(id, sha) order by 1
--   loop
--     select content into v_sql from net._http_response where id = r.id and status_code = 200;
--     if v_sql is null then raise exception 'painel: copia % nao encontrada', r.id; end if;
--     if encode(sha256(convert_to(v_sql,'UTF8')),'hex') <> r.sha then raise exception 'painel: sha256 diferente em %', r.id; end if;
--     execute v_sql;
--   end loop;
-- end
-- $aplicar$;
-- <<< fim do carregador; a seguir, o que ele executou.

-- ===== Parte 1 de 3: P1_leitura_admin_pedidos_saldos.PROPOSTA.sql (sha256 8737404e4528659b3a13c2a9d85cfb00163a0c8ddafa3df950987aaf61a540b5) =====
-- PROPOSTA P1 (missão painel-admin-15-11, 15/11/2026, Claude Code). Aplica a Claude.ai com execute_sql.
-- ZONA PROTEGIDA: mexe em RLS de orders (e de duas tabelas de saldo). A ordem explícita existe: Danilo
-- 15/11 13:34, transmitida pela Claude.ai às 13:38 (caixa 57, ponto A: "regra de leitura de admin em
-- orders, driver_balances, driver_transactions, support_tickets"; "admin_update_driver uma versão só").
-- É só LEITURA para o admin: não muda escrita, valores, comissões nem quem paga o quê.
--
-- O problema (provado a 15/11 por SELECT em pg_policies e pelos relatórios S1, S2, S3 e S4):
--   * orders só tem regras de leitura para o cliente, o estafeta e o parceiro. Nenhuma migração criou
--     uma regra de admin. O painel lê orders diretamente em 11 sítios (ecrã Pedidos, detalhe do pedido,
--     ficha do estafeta, pesquisa global, avaliações, reembolsos de estafetas, substituições) e o admin
--     vê só os pedidos da própria conta: no ecrã Pedidos, 10 de 108 (S1; o registo da API de 14/11
--     18:50 mostra content-range 0-9). Abrir o pedido de outra pessoa dá "Pedido não encontrado".
--   * driver_balances e driver_transactions só deixam ler "o próprio" (driver_id = auth.uid()): o saldo
--     na ficha do estafeta e o ecrã "Saques dos estafetas" mostram sempre zero (0 de 5 saldos, 0 de 122
--     transações com um JWT de admin simulado, S2 e S3).
--   * appointment_reschedules só tem regras para cliente e parceiro: o "Histórico" da agenda de
--     marcações mostra "Sem registos" (S4).
--   * support_tickets só deixa cada pessoa ler os seus: o ecrã "Suporte — Tickets" fica vazio (25
--     tickets, 7 abertos; S6). A regra abaixo é a mesma da proposta das conversas ao vivo (caixa 55,
--     mesmo nome support_tickets_admin_ler): aplicar uma ou as duas não duplica nada.
--   * admin_update_driver tem 2 versões (8 e 10 parâmetros, todos com valor por defeito a partir do
--     3.º). Quando a cor e o modelo do veículo não mudam, a app manda 8 chaves e as duas versões servem:
--     o servidor recusa por ambiguidade (PGRST203) e "Editar dados" do estafeta dá erro (S3). A versão
--     de 10 só muda a cor e o modelo quando vêm preenchidos (IF p_vehicle_color IS NOT NULL ...,
--     conferido a 15/11), por isso apagar a de 8 resolve já, também para a app que está publicada.
--     A de 10 fica igual; o texto dela vai para o repo em
--     supabase/migrations/20260702182113_admin_update_driver_10_params_doc.sql.
-- As regras de leitura têm a mesma forma das outras 266 regras do projeto que usam is_admin(). O
-- (select ...) faz o Postgres avaliar is_admin() uma vez por consulta, não uma vez por linha.

drop policy if exists orders_select_admin on public.orders;
create policy orders_select_admin on public.orders
  for select to authenticated using ((select public.is_admin()));

drop policy if exists driver_balances_select_admin on public.driver_balances;
create policy driver_balances_select_admin on public.driver_balances
  for select to authenticated using ((select public.is_admin()));

drop policy if exists driver_transactions_select_admin on public.driver_transactions;
create policy driver_transactions_select_admin on public.driver_transactions
  for select to authenticated using ((select public.is_admin()));

drop policy if exists appointment_reschedules_select_admin on public.appointment_reschedules;
create policy appointment_reschedules_select_admin on public.appointment_reschedules
  for select to authenticated using ((select public.is_admin()));

drop policy if exists support_tickets_admin_ler on public.support_tickets;
create policy support_tickets_admin_ler on public.support_tickets
  for select to authenticated using (coalesce(public.is_admin(), false));

-- admin_update_driver: fica só a versão de 10 parâmetros.
drop function if exists public.admin_update_driver(uuid, text, text, text, text, text, text, text);

-- PROVA depois de aplicar:
--   select tablename, policyname from pg_policies
--    where schemaname = 'public' and policyname in ('orders_select_admin', 'driver_balances_select_admin',
--          'driver_transactions_select_admin', 'appointment_reschedules_select_admin',
--          'support_tickets_admin_ler');                                                      -- 5 linhas
--   select count(*) from pg_proc where proname = 'admin_update_driver';                       -- 1
--   No painel (conta admin): Pedidos mostra os pedidos de todos; a ficha de um estafeta mostra o saldo
--   e as transações dele (o código do ramo ai/2026-11-15-app já filtra pelos dois ids do estafeta).
--
-- ALTERNATIVA sem tocar em RLS (se o Danilo não quiser a regra): funções SECURITY DEFINER com
-- is_admin() (admin_list_orders, admin_get_order, admin_saldo_estafeta) e mudar o código dos 11 sítios.
-- Dá o mesmo acesso ao admin, mas demora mais a pôr no ar (código novo, CI, publicação nas 3 lojas).
-- ===== Parte 2 de 3: P2_mapa_ao_vivo.PROPOSTA.sql (sha256 924c42339cc621d70cece8b3def9dd3f9dd06e1ac94261865f5529b26ab1d542) =====
-- PROPOSTA P2 (missão painel-admin-15-11, 15/11/2026, Claude Code). Aplica a Claude.ai com execute_sql.
-- Só funções de LEITURA do painel (mapa ao vivo). Não mexe em pedidos, despacho, dinheiro nem RLS.
--
-- Porque é que o mapa ao vivo mostra "3" (relatório S1, conferido por SELECT a 15/11):
--   * Havia 2 estafetas ligados (drivers.is_online), os dois reais e com sinal recente.
--   * Um deles tem DUAS linhas em driver_locations, uma com drivers.id e outra com o user_id, as duas
--     recentes e a 1 m uma da outra. A admin_live_drivers junta driver_locations com drivers por
--     "d.user_id = dl.driver_id OR d.id = dl.driver_id" e devolve uma linha por posição, sem tirar os
--     repetidos: 3 linhas, dois pinos azuis um em cima do outro. O cartão AGORA do início conta
--     drivers.is_online e diz 2; por isso os números não batiam.
--   * A causa de fundo é o gatilho trg_sync_drivers_to_driver_locations, que grava com drivers.id,
--     enquanto a app grava pela driver_update_location com auth.uid() (o user_id). 17 de 22 estafetas
--     têm id diferente do user_id; já há 11 linhas repetidas e 2 órfãs. Esse gatilho alimenta o
--     despacho (proximidade), por isso NÃO se mexe aqui: fica descrito no fim, só com ordem do Danilo.
--
-- O que muda:
--   1. admin_live_drivers: uma linha por estafeta (drivers.id, o id que abre a ficha), a posição mais
--      recente, e só quem está mesmo ligado: drivers.is_online, não banido, não apagado, GPS nos
--      últimos 5 minutos. As linhas de posição sem estafeta (órfãs) deixam de aparecer. Mesmas colunas
--      e o mesmo guarda.
--   2. admin_live_orders: passa a incluir 'readyForPickup' (pronto na loja), estado válido em
--      orders_status_canonical_check que hoje desaparece do mapa.

create or replace function public.admin_live_drivers()
 returns table(driver_id uuid, driver_name text, driver_phone text, latitude numeric, longitude numeric,
               heading numeric, speed_kmh numeric, last_updated timestamp with time zone,
               active_order_id text, vehicle_type text)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public._admin_op_guard();
  return query
  select x.driver_id, x.driver_name, x.driver_phone, x.latitude, x.longitude, x.heading,
         x.speed_kmh, x.last_updated, x.active_order_id, x.vehicle_type
    from (
      -- driver_id = drivers.id: é o id que a ficha do estafeta abre (AdminDriverDetailScreen
      -- procura drivers por id). Hoje a função devolvia o id da linha de posição, que para 17 de 22
      -- estafetas é o user_id e não abre a ficha.
      select distinct on (d.id)
             d.id as driver_id,
             d.name as driver_name,
             d.phone as driver_phone,
             dl.latitude, dl.longitude, dl.heading, dl.speed_kmh, dl.last_updated,
             (select o.id from public.orders o
               where (o.assigned_driver_id::text = d.user_id::text or o.assigned_driver_id::text = d.id::text)
                 and o.status in ('driverAccepted', 'pickedUp', 'onTheWay')
               order by o.created_at desc
               limit 1) as active_order_id,
             d.vehicle_type
        from public.driver_locations dl
        join public.drivers d on (d.user_id = dl.driver_id or d.id = dl.driver_id)
       where dl.is_online = true
         and d.is_online = true
         and coalesce(d.is_banned, false) = false
         and d.deleted_at is null
         and dl.last_updated > now() - interval '5 minutes'
       order by d.id, dl.last_updated desc
    ) x;
end;
$function$;

create or replace function public.admin_live_orders(p_include_test_orders boolean default false)
 returns table(id text, status text, service_type text, vendor_name text, customer_name text, total numeric,
               created_at timestamp with time zone, pickup_lat numeric, pickup_lng numeric, dropoff_lat numeric,
               dropoff_lng numeric, pickup_address text, dropoff_address text, assigned_driver_id text,
               is_partner_store boolean, is_test_order boolean)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
begin
  perform public._admin_op_guard();
  return query
  select
    o.id,
    o.status,
    o.service_type,
    o.vendor_name,
    o.customer_name,
    coalesce(o.price, 0)::numeric,
    o.created_at,
    o.pickup_lat::numeric,
    o.pickup_lng::numeric,
    o.dropoff_lat::numeric,
    o.dropoff_lng::numeric,
    o.pickup_address,
    o.dropoff_address,
    o.assigned_driver_id,
    coalesce(o.is_partner_store, false),
    coalesce(o.is_test_order, false)
  from public.orders o
  where o.status in ('created', 'preparing', 'readyForPickup', 'callingDriver',
                     'driverAccepted', 'pickedUp', 'onTheWay')
    and (
      p_include_test_orders = true
      or coalesce(o.is_test_order, false) = false
    )
  order by o.created_at desc
  limit 100;
end;
$function$;

-- PROVA depois de aplicar (como admin no painel): o contador "Entregadores ligados" do mapa passa a
-- bater com o cartão AGORA do início. Por SQL, a contagem que a função vai devolver:
--   select count(distinct d.id)
--     from public.driver_locations dl
--     join public.drivers d on (d.user_id = dl.driver_id or d.id = dl.driver_id)
--    where dl.is_online and d.is_online and not coalesce(d.is_banned, false) and d.deleted_at is null
--      and dl.last_updated > now() - interval '5 minutes';
--
-- SÓ COM ORDEM DO DANILO (entrada do despacho, não incluído acima): o gatilho
-- fn_sync_drivers_to_driver_locations passar a gravar coalesce(NEW.user_id, NEW.id), e juntar as 11
-- linhas repetidas de driver_locations (com cópia antes em bkp_driver_locations_20261115). Mexe na
-- tabela que o despacho usa para escolher o estafeta mais perto: precisa de teste real.
-- ===== Parte 3 de 3: P3_guarda_admin_igual.PROPOSTA.sql (sha256 5aed6a23636edd37f7a7df3727bb2b2cc4208f0e8f7e673d4579d37aa8d158a7) =====
-- PROPOSTA P3 (missão painel-admin-15-11, 15/11/2026, Claude Code). Aplica a Claude.ai com execute_sql.
-- Segurança: decide QUEM passa nas funções de admin. Pede a ordem da Claude.ai; não mexe em dinheiro.
--
-- O problema (relatórios S1 e S2, conferido por pg_get_functiondef a 15/11):
--   O painel tem dois porteiros diferentes.
--   * is_admin() (usado em 266 regras de acesso) aceita app_metadata.role = 'admin' OU os dois emails
--     do dono.
--   * _admin_op_guard() (usado pelo mapa ao vivo, Pedidos parados, Cancelamentos, carteiras, códigos
--     promocionais, tokens, repasses e os interruptores de Stripe e Farmácias) só aceita
--     app_metadata.role = 'admin' no token.
--   A segunda conta de email do dono não tem esse papel: se ele entrar com ela, metade dos botões dá
--   "admin_required" (o painel abre, porque o resto usa is_admin()).
-- O que muda: _admin_op_guard passa a aceitar também is_admin(). Não abre nada a mais do que já está
-- aberto pelas 266 regras: são as mesmas pessoas.
-- Alternativa sem mudar código: dar app_metadata.role = 'admin' à segunda conta (Papéis da pessoa).

create or replace function public._admin_op_guard()
 returns table(admin_id uuid, admin_email text)
 language plpgsql
 security definer
 set search_path to 'public'
as $function$
declare v_uid uuid; v_email text; v_app_role text;
begin
  v_uid := auth.uid();
  if v_uid is null then
    raise exception 'admin_required: not authenticated' using errcode = '42501';
  end if;
  v_email := coalesce(
    auth.jwt() ->> 'email',
    auth.jwt() -> 'user_metadata' ->> 'email'
  );
  v_app_role := auth.jwt() -> 'app_metadata' ->> 'role';
  -- 15/11/2026: o mesmo porteiro das regras de acesso (is_admin) também passa aqui.
  if v_app_role is distinct from 'admin' and not public.is_admin() then
    raise exception 'admin_required: app_metadata.role=% (need admin)',
      coalesce(v_app_role, 'NULL') using errcode = '42501';
  end if;
  return query select v_uid, v_email;
end;
$function$;

-- PROVA: select position('is_admin()' in prosrc) > 0 from pg_proc where proname = '_admin_op_guard';  -- true
-- E no painel, com a segunda conta do dono: o mapa ao vivo abre sem "admin_required".
--
-- NOTA (falso alarme do relatório S6, conferido): "log_admin_action não confirma que quem chama é admin"
-- NÃO é verdade. As duas versões começam por _audit_chamada_direta_nao_admin(): uma chamada direta de
-- quem não é admin é ignorada sem gravar. Nada a mudar aí.
