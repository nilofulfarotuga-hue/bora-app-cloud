-- 17/11/2026 receita-cartao-mbway-17-11 (Claude Code no PC; a Claude.ai aplica).
-- Aplicar DEPOIS de receita_real_se (20261117073743 em produção). Não muda preços nem taxas:
-- o pedido é o MESMO Favor que prescricao_confirmar cria em dinheiro, a taxa vem do create_order.
--
-- Porquê: na farmácia aberta ao público (Sé) o servidor só aceitava dinheiro (SO_DINHEIRO).
-- Regra do Danilo: cartão, MB Way e dinheiro. Dinheiro continua em prescricao_confirmar (igual).
--
-- Como funciona (sem mexer nas Edge Functions de pagamento):
--   1. A app chama prescricao_preparar_pedido(p_id, 'card'|'mbway'). O SERVIDOR monta o input do
--      create_order (a app não escolhe valores) e reserva o código de levantamento (pagamento_ref).
--      - 'card'  → devolve cart_input; a app segue o caminho do cartão que já existe (rascunho
--                  payment_drafts + create-payment-intent; o pedido nasce no
--                  finalize-order-from-intent só depois de pago: nunca há cobrança sem pedido).
--      - 'mbway' → o servidor cria já o pedido (payment_method mbway, à espera de pagamento) e
--                  devolve order_id; a app pede o MB Way como no checkout normal. Toque duplo ou
--                  voltar ao ecrã devolve o MESMO pedido (não cria outro).
--   2. Gatilho _prescricao_liga_pedido_pago (orders, quando fica pago): encontra a receita pelo
--      código reservado (está na descrição do Favor) e confere o pedido contra o que o servidor
--      montou: mesmo cliente, valor da compra = valor_medicamentos, farmácia, morada, distância
--      meio de pagamento, Favor com compra e valor pago >= remédios + taxa. Confere → receita
--      'confirmado' com order_id, PIN de entrega e aviso à farmácia (igual ao dinheiro). Não confere
--      → pagamento_alerta + aviso urgente ao admin (o pedido pago segue: quem decide é o admin).
--   3. Gatilho _prescricao_pagamento_cancelado: pedido MB Way cancelado (não pagou) → a receita
--      volta a poder ser paga (por qualquer meio).
--   4. Guarda _prescricao_guarda_pagamento: não deixa confirmar em dinheiro nem cancelar a receita
--      com um MB Way vivo ou um cartão começado há menos de 10 min (evita dois pedidos pagos).
--   5. farmacia_consentimento devolve aberta/abre_as (o cliente sabe logo que está fechada).
--   6. farmacia_prescricoes_entrega: a farmácia vê o estado da entrega e o nome do estafeta.
--   7. admin_prescricoes_listar: + pedido ligado, estado do pedido, estafeta, alerta.
-- Cancelamento e "ninguém aceitou" do pedido pago seguem o reembolso normal do Favor.

-- ---------------------------------------------------------------- colunas
alter table public.pedidos_prescricao
  add column if not exists pagamento_metodo text,
  add column if not exists pagamento_ref text,
  add column if not exists pagamento_conferir jsonb,
  add column if not exists pagamento_order_id text,
  add column if not exists pagamento_iniciado_em timestamptz,
  add column if not exists pagamento_alerta text,
  add column if not exists pagamento_desistiu_em timestamptz;

do $$ begin
  alter table public.pedidos_prescricao add constraint pedidos_prescricao_pagamento_metodo_check
    check (pagamento_metodo is null or pagamento_metodo in ('card', 'mbway'));
exception when duplicate_object then null; end $$;

comment on column public.pedidos_prescricao.pagamento_ref is
  'Código de levantamento reservado quando o cliente começa a pagar com cartão/MB Way (vai na descrição do Favor e liga o pedido pago à receita).';
comment on column public.pedidos_prescricao.pagamento_conferir is
  'O que o servidor montou para o pedido pago (distância, compra, farmácia, morada, meio): o gatilho confere o pedido contra isto.';
comment on column public.pedidos_prescricao.pagamento_order_id is
  'MB Way: pedido criado à espera do pagamento (limpa-se se for cancelado sem pagar).';
comment on column public.pedidos_prescricao.pagamento_alerta is
  'Pedido pago que não confere com a receita (o admin vê e resolve).';
comment on column public.pedidos_prescricao.pagamento_desistiu_em is
  'O cliente fechou a folha do cartão sem pagar (ou foi recusado): os rascunhos de cartão anteriores deixam de travar o dinheiro e o cancelar.';

-- Rascunho de cartão desta receita começado há pouco e ainda por usar (depois da última desistência).
create or replace function public._prescricao_cartao_em_curso(p_user uuid, p_ref text, p_desde timestamptz)
 returns boolean
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select p_ref is not null and exists (
    select 1 from public.payment_drafts d
     where d.user_id = p_user and d.used_at is null
       and d.created_at > greatest(now() - interval '10 minutes', coalesce(p_desde, '-infinity'::timestamptz))
       and position('Código de levantamento: ' || p_ref || '.' in coalesce(d.payload->>'errand_description', '')) > 0)
$function$;
revoke all on function public._prescricao_cartao_em_curso(uuid, text, timestamptz) from public, anon, authenticated;

create index if not exists pedidos_prescricao_pagamento_order_idx
  on public.pedidos_prescricao (pagamento_order_id) where pagamento_order_id is not null;
create index if not exists pedidos_prescricao_pagamento_ref_idx
  on public.pedidos_prescricao (user_id, pagamento_ref) where pagamento_ref is not null;

-- ---------------------------------------------------------------- 1. preparar o pedido
create or replace function public.prescricao_preparar_pedido(p_id uuid, p_metodo text, p_so_disponiveis boolean default true)
 returns jsonb
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_uid uuid := auth.uid();
  v record;
  r record;
  u record;
  o record;
  v_lev text;
  v_lat double precision;
  v_lng double precision;
  v_dist numeric;
  v_valor text;
  v_desc text;
  v_input jsonb;
  v_res jsonb;
  v_order text;
  v_msg text;
begin
  if v_uid is null then
    raise exception 'SEM_SESSAO: Tem de entrar na sua conta.' using errcode = '42501';
  end if;
  select pp.*, rr.so_lista_permissao as escondida into v
    from public.pedidos_prescricao pp join public.restaurants rr on rr.id = pp.restaurant_id
   where pp.id = p_id for update of pp;
  if not found or v.user_id is distinct from v_uid then
    raise exception 'NAO_ENCONTRADO: Pedido não encontrado.' using errcode = 'P0002';
  end if;
  if v.estado not in ('aceite', 'aceite_parcial') then
    raise exception 'NAO_CONFIRMAVEL: Este pedido já não pode ser confirmado.' using errcode = 'P0001';
  end if;
  if p_metodo is null or p_metodo not in ('card', 'mbway') then
    raise exception 'METODO_INVALIDO: Escolha cartão ou MB Way (o dinheiro confirma-se direto).' using errcode = 'P0001';
  end if;
  if coalesce(v.escondida, false) then
    -- Loja escondida = demonstração: confirma-se sem cobrar (prescricao_confirmar).
    raise exception 'DEMONSTRACAO: Nesta farmácia de demonstração não se cobra nada. Toque outra vez em confirmar.' using errcode = 'P0001';
  end if;
  if public._setting_txt('pharmacy_prescription_real_orders_enabled', 'false') <> 'true' then
    raise exception 'RECEITA_REAL_POR_LIGAR: A entrega de receitas ainda não está disponível. Pode levantar na farmácia.' using errcode = 'P0001';
  end if;

  -- Pedido MB Way já criado e vivo: devolve o mesmo (toque duplo, rede a cair, voltar ao ecrã).
  if v.pagamento_order_id is not null then
    select id, status, payment_status, payment_method, price, payment_buffer_total into o
      from public.orders where id = v.pagamento_order_id;
    if found and coalesce(o.status, '') not in ('cancelled', 'rejected') then
      if p_metodo = 'mbway' then
        return jsonb_build_object('metodo', 'mbway', 'order_id', o.id, 'payment_status', o.payment_status,
                                  'total_cents', round(coalesce(o.price, 0) * 100)::integer,
                                  'cobrar_cents', round(coalesce(o.payment_buffer_total, o.price, 0) * 100)::integer,
                                  'codigo_levantamento', v.pagamento_ref, 'repetido', true);
      end if;
      raise exception 'PAGAMENTO_EM_CURSO: Tem um pagamento MB Way por concluir neste pedido. Aprove-o na app MB WAY ou espere que seja cancelado.'
        using errcode = 'P0001';
    end if;
  end if;
  -- Cartão começado há pouco (folha aberta, 3D Secure): o MB Way não cobra por cima.
  if p_metodo = 'mbway' and public._prescricao_cartao_em_curso(v.user_id, v.pagamento_ref, v.pagamento_desistiu_em) then
    raise exception 'PAGAMENTO_EM_CURSO: Começou a pagar com cartão há pouco. Termine esse pagamento ou espere alguns minutos e tente outra vez.'
      using errcode = 'P0001';
  end if;

  select id, name, address, lat, lng, coming_soon into r from public.restaurants where id = v.restaurant_id;
  if coalesce(r.coming_soon, false) or r.lat is null or r.lng is null then
    raise exception 'FARMACIA_INDISPONIVEL: Este serviço ainda não está disponível nesta farmácia.' using errcode = 'P0001';
  end if;
  select c.lat, c.lng into v_lat, v_lng from public._prescricao_morada_coords(v.user_id, v.morada, v.lat, v.lng) c;
  if v_lat is null or v_lng is null then
    raise exception 'FALTA_LOCALIZACAO: Não encontrámos a morada de entrega no mapa. Cancele e envie outra vez com a morada que aparece sozinha.'
      using errcode = 'P0001';
  end if;

  -- O código fica reservado de uma vez: um cartão pago mais tarde (3D Secure lento) continua a
  -- encontrar esta receita.
  v_lev := coalesce(v.pagamento_ref, public._prescricao_codigo(6));

  -- ===== O mesmo Favor de prescricao_confirmar (dinheiro); só muda o meio de pagamento =====
  v_dist := coalesce(public._prescricao_distancia_km(v.restaurant_id, v_lat, v_lng), 1);
  v_valor := replace(to_char(v.valor_medicamentos_cents / 100.0, 'FM999990.00'), '.', ',');
  v_desc := case when v.tipo = 'receita' then 'Receita' else 'Pedido à farmácia' end
    || ': levantar na ' || r.name || ' o pedido já preparado em nome do cliente. Código de levantamento: ' || v_lev
    || '. Pagar na farmácia: ' || v_valor || ' € (pedir o talão).'
    || case when v.estado = 'aceite_parcial' and nullif(btrim(coalesce(v.itens_disponiveis, '')), '') is not null
            then ' Leva só: ' || left(btrim(v.itens_disponiveis), 150) || '.' else '' end;
  select name, phone into u from public.users where id = v.user_id;
  v_input := jsonb_build_object(
    'service_type', 'errand',
    'payment_method', p_metodo,
    'distance_km', v_dist,
    'errand_speed', 'normal',
    'errand_home_stop', false,
    'errand_has_purchase', true,
    'errand_estimated_purchase_cents', v.valor_medicamentos_cents,
    'errand_description', left(v_desc, 480),
    'errand_location', r.name || coalesce(', ' || nullif(btrim(r.address), ''), ''),
    'errand_location_lat', r.lat,
    'errand_location_lng', r.lng,
    'dropoff_address', v.morada,
    'dropoff_lat', v_lat,
    'dropoff_lng', v_lng,
    'customer_name', u.name,
    'client_phone', u.phone,
    'items', '[]'::jsonb);

  update public.pedidos_prescricao set
    pagamento_metodo = p_metodo,
    pagamento_ref = v_lev,
    pagamento_conferir = jsonb_build_object(
      'metodo', p_metodo, 'distance_km', v_dist, 'compra_cents', v.valor_medicamentos_cents,
      'taxa_cents', v.taxa_servico_cents,
      'farmacia_lat', r.lat, 'farmacia_lng', r.lng, 'dropoff_lat', v_lat, 'dropoff_lng', v_lng),
    pagamento_iniciado_em = now(),
    so_disponiveis = coalesce(p_so_disponiveis, true)
  where id = p_id;

  if p_metodo = 'card' then
    -- Cartão: nada é criado aqui. O pedido nasce no servidor depois do pagamento confirmado.
    return jsonb_build_object('metodo', 'card', 'cart_input', v_input,
                              'codigo_levantamento', v_lev);
  end if;

  -- MB Way: o pedido nasce à espera de pagamento (como no checkout normal); o estafeta só é
  -- chamado quando o pagamento entra.
  begin
    v_res := public.create_order(v_input);
  exception when others then
    v_msg := sqlerrm;
    if v_msg like 'MBWAY_DISABLED%' then
      raise exception 'MBWAY_DESLIGADO: O MB Way está indisponível neste momento. Pague com cartão ou dinheiro.' using errcode = 'P0001';
    elsif v_msg like 'ERRAND_ADVANCE_LIMIT%' then
      raise exception 'LIMITE_VALOR: O estafeta só pode adiantar até 40 € na farmácia. Por agora não dá para este valor; pode levantar na farmácia.' using errcode = 'P0001';
    elsif v_msg like 'ERRAND_DISABLED%' then
      raise exception 'FAVORES_DESLIGADOS: As entregas da farmácia estão paradas neste momento. Tente daqui a pouco.' using errcode = 'P0001';
    elsif v_msg like 'duplicate_errand%' then
      raise exception 'PEDIDO_REPETIDO: Já criámos este pedido há instantes. Espere um minuto e veja em "Pedidos".' using errcode = 'P0001';
    end if;
    raise;
  end;
  v_order := v_res->>'order_id';
  update public.pedidos_prescricao set pagamento_order_id = v_order where id = p_id;
  select price, payment_buffer_total, payment_status into o from public.orders where id = v_order;
  -- cobrar_cents = o que o MB Way pede (payment_buffer_total, com a margem errand_buffer_multiplier
  -- do Favor). ATENÇÃO 17/11: trg_excedente_preautorizacao está DESLIGADO (decisão de 05/10), por
  -- isso a margem não volta sozinha. Decisão do Danilo pendente (e2e_log precisa-claude-ai).
  return jsonb_build_object('metodo', 'mbway', 'order_id', v_order,
                            'payment_status', coalesce(o.payment_status, 'pending'),
                            'total_cents', round(coalesce(o.price, 0) * 100)::integer,
                            'cobrar_cents', round(coalesce(o.payment_buffer_total, o.price, 0) * 100)::integer,
                            'codigo_levantamento', v_lev);
end $function$;

revoke all on function public.prescricao_preparar_pedido(uuid, text, boolean) from public, anon;
grant execute on function public.prescricao_preparar_pedido(uuid, text, boolean) to authenticated;

-- ---------------------------------------------------------------- 2. ligar o pedido pago
create or replace function public._prescricao_liga_pedido_pago()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v record;
  c jsonb;
  v_motivo text;
  v_ent text := lpad((floor(random() * 10000))::int::text, 4, '0');
  v_hex text;
begin
  if tg_op = 'UPDATE' and old.payment_status is not distinct from new.payment_status then
    return new;
  end if;
  if position('Código de levantamento: ' in coalesce(new.errand_description, '')) = 0 then
    return new;
  end if;
  -- Já ligado (ex.: pedido em dinheiro da receita que fica pago na entrega): nada a fazer.
  if exists (select 1 from public.pedidos_prescricao where order_id = new.id) then
    return new;
  end if;
  begin
    select pp.* into v from public.pedidos_prescricao pp
     where pp.user_id = new.user_id and pp.pagamento_ref is not null
       and position('Código de levantamento: ' || pp.pagamento_ref || '.' in new.errand_description) > 0
     order by pp.pagamento_iniciado_em desc nulls last
     limit 1
     for update;
    if not found then return new; end if;
    c := coalesce(v.pagamento_conferir, '{}'::jsonb);

    v_motivo := case
      when v.estado not in ('aceite', 'aceite_parcial') then 'a receita já estava "' || v.estado || '"'
      when v.order_id is not null then 'a receita já estava ligada ao pedido ' || v.order_id
      when new.payment_method is distinct from c->>'metodo' then 'meio de pagamento diferente (' || coalesce(new.payment_method, '-') || ')'
      when new.errand_estimated_purchase_cents is distinct from v.valor_medicamentos_cents then 'valor da compra diferente'
      -- Sem compra (ou com paragem em casa / outra rapidez) o preço do Favor muda: não liga.
      when new.errand_has_purchase is distinct from true then 'Favor sem compra'
      when coalesce(new.errand_home_stop, false) then 'Favor com paragem em casa'
      when coalesce(new.errand_speed, 'normal') <> 'normal' then 'rapidez diferente'
      -- O que o cliente pagou nunca pode ficar abaixo de remédios + taxa do Favor desta receita.
      when round(coalesce(new.price, 0) * 100) + 1
           < v.valor_medicamentos_cents + coalesce((c->>'taxa_cents')::integer, v.taxa_servico_cents, 0) then 'valor pago abaixo do previsto'
      when abs(coalesce(new.errand_location_lat, 0) - coalesce((c->>'farmacia_lat')::float8, 999)) > 0.00001
        or abs(coalesce(new.errand_location_lng, 0) - coalesce((c->>'farmacia_lng')::float8, 999)) > 0.00001 then 'farmácia diferente'
      when abs(coalesce(new.dropoff_lat, 0) - coalesce((c->>'dropoff_lat')::float8, 999)) > 0.00001
        or abs(coalesce(new.dropoff_lng, 0) - coalesce((c->>'dropoff_lng')::float8, 999)) > 0.00001 then 'morada de entrega diferente'
      when coalesce(new.distance_km, 0) + 0.01 < coalesce((c->>'distance_km')::numeric, 0) then 'distância menor que a calculada'
      else null end;

    if v_motivo is not null then
      update public.pedidos_prescricao
         set pagamento_alerta = left(to_char(now() at time zone 'Europe/Lisbon', 'DD/MM HH24:MI')
                                     || ' pedido ' || new.id || ' pago mas não ligado: ' || v_motivo, 500)
       where id = v.id;
      perform public.notify_admin_urgent_push(
        'prescricao_pagamento_alerta',
        'RECEITA: pedido pago que não confere com a receita (' || v_motivo || '). Ver e decidir reembolso.',
        'order', new.id::text,
        jsonb_build_object('order_id', new.id, 'prescricao_id', v.id, 'motivo', v_motivo),
        '/admin/orders/' || new.id);
      return new;
    end if;

    -- O código de entrega é o PIN do pedido (o mesmo que driver_validate_delivery_pin confere).
    v_hex := substr(replace(new.id, '-', ''), 1, 4);
    if v_hex ~ '^[0-9a-fA-F]{4}$' then
      v_ent := ((('x' || lpad(v_hex, 8, '0'))::bit(32)::bigint % 9000) + 1000)::text;
    end if;
    update public.pedidos_prescricao set
      estado = 'confirmado', metodo_pagamento = new.payment_method,
      taxa_servico_cents = round(coalesce(new.delivery_fee, 0) * 100)::integer,
      total_cents = round(coalesce(new.price, 0) * 100)::integer,
      confirmado_em = now(), codigo_levantamento = v.pagamento_ref, codigo_entrega = v_ent,
      order_id = new.id, is_demo = false, pagamento_order_id = new.id, pagamento_alerta = null
    where id = v.id;
    perform public._prescricao_avisar(v.id, 'loja', 'prescricao_confirmada',
      'O cliente pagou: prepare o pedido',
      'Um estafeta da Bora vai levantar e pagar na farmácia. Código de levantamento ' || v.pagamento_ref || '.');
  exception when others then
    -- Nunca deixar o pagamento falhar por causa da receita: fica no registo para o admin.
    raise warning '_prescricao_liga_pedido_pago %: %', new.id, sqlerrm;
  end;
  return new;
end $function$;

drop trigger if exists trg_zz_prescricao_liga_pedido_pago on public.orders;
create trigger trg_zz_prescricao_liga_pedido_pago
  after insert or update of payment_status on public.orders
  for each row when (new.payment_status = 'paid' and new.service_type = 'errand')
  execute function public._prescricao_liga_pedido_pago();

-- ---------------------------------------------------------------- 3. MB Way cancelado sem pagar
create or replace function public._prescricao_pagamento_cancelado()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  update public.pedidos_prescricao
     set pagamento_order_id = null
   where pagamento_order_id = new.id and order_id is null and estado in ('aceite', 'aceite_parcial');
  return new;
exception when others then
  raise warning '_prescricao_pagamento_cancelado %: %', new.id, sqlerrm;
  return new;
end $function$;

drop trigger if exists trg_zz_prescricao_pagamento_cancelado on public.orders;
create trigger trg_zz_prescricao_pagamento_cancelado
  after update of status on public.orders
  for each row when (old.status is distinct from new.status and new.status in ('cancelled', 'rejected'))
  execute function public._prescricao_pagamento_cancelado();

-- ---------------------------------------------------------------- 4. guarda contra dois pedidos pagos
create or replace function public._prescricao_guarda_pagamento()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  if old.estado not in ('aceite', 'aceite_parcial') or new.estado not in ('confirmado', 'cancelado') then
    return new;
  end if;
  -- A própria ligação do pedido pago passa sempre.
  if new.order_id is not null and new.order_id is not distinct from new.pagamento_order_id then
    return new;
  end if;
  if public.is_admin() then
    return new;
  end if;
  if old.pagamento_order_id is not null and exists (
       select 1 from public.orders o
        where o.id = old.pagamento_order_id and coalesce(o.status, '') not in ('cancelled', 'rejected')) then
    raise exception 'PAGAMENTO_EM_CURSO: Tem um pagamento MB Way por concluir neste pedido. Aprove-o na app MB WAY ou espere que seja cancelado.'
      using errcode = 'P0001';
  end if;
  -- Cartão começado há pouco: a app marca a desistência quando a folha fecha sem pagar
  -- (prescricao_pagamento_desistir), e aí o dinheiro e o cancelar passam logo.
  if public._prescricao_cartao_em_curso(old.user_id, old.pagamento_ref, old.pagamento_desistiu_em) then
    raise exception 'PAGAMENTO_EM_CURSO: Começou a pagar com cartão há pouco. Termine esse pagamento ou espere alguns minutos e tente outra vez.'
      using errcode = 'P0001';
  end if;
  return new;
end $function$;

-- O cliente fechou a folha do cartão sem pagar (ou o cartão foi recusado).
create or replace function public.prescricao_pagamento_desistir(p_id uuid)
 returns void
 language plpgsql
 security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  update public.pedidos_prescricao set pagamento_desistiu_em = now()
   where id = p_id and user_id = auth.uid() and estado in ('aceite', 'aceite_parcial');
end $function$;
revoke all on function public.prescricao_pagamento_desistir(uuid) from public, anon;
grant execute on function public.prescricao_pagamento_desistir(uuid) to authenticated;

drop trigger if exists trg_prescricao_guarda_pagamento on public.pedidos_prescricao;
create trigger trg_prescricao_guarda_pagamento
  before update of estado on public.pedidos_prescricao
  for each row when (old.estado is distinct from new.estado)
  execute function public._prescricao_guarda_pagamento();

revoke all on function public._prescricao_liga_pedido_pago() from public, anon, authenticated;
revoke all on function public._prescricao_pagamento_cancelado() from public, anon, authenticated;
revoke all on function public._prescricao_guarda_pagamento() from public, anon, authenticated;

-- ---------------------------------------------------------------- 5. farmácia aberta ou fechada logo à entrada
create or replace function public.farmacia_consentimento(p_restaurant_id text)
 returns jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
declare
  v_nome text;
  v_escondida boolean;
  v_estado jsonb;
begin
  if not public.farmacia_botoes_visiveis(p_restaurant_id) then
    raise exception 'FARMACIA_INDISPONIVEL: Este serviço ainda não está disponível nesta farmácia.' using errcode = 'P0001';
  end if;
  select name, coalesce(so_lista_permissao, false) into v_nome, v_escondida from public.restaurants where id = p_restaurant_id;
  -- 17/11/2026: na loja real o pedido só passa com a farmácia aberta (prescricao_criar);
  -- o ecrã diz logo "A farmácia abre às 09:00" em vez de no fim, depois da foto e da assinatura.
  if not v_escondida then
    v_estado := public.is_partner_open(p_restaurant_id);
  end if;
  return jsonb_build_object(
    'versao', public._setting_txt('pharmacy_prescription_consent_version', 'v1-2026-11-11'),
    'texto', replace(public._setting_txt('pharmacy_prescription_consent_text',
       'Autorizo o estafeta da Bora a levantar os meus medicamentos em meu nome na {farmacia}. A farmácia valida a receita e é responsável pela dispensa.'),
       '{farmacia}', coalesce(v_nome, 'farmácia')),
    'taxa_servico_cents', public._setting_int('errand_fee_normal_cents', 600),
    'minutos_resposta', public._setting_int('pharmacy_prescription_response_minutes', 15),
    'aberta', coalesce((v_estado->>'is_open')::boolean, true),
    'abre_as', v_estado->>'opens_at',
    'abre_dia', v_estado->>'opens_dia'
  );
end $function$;

-- ---------------------------------------------------------------- 6. a farmácia vê a entrega
create or replace function public.farmacia_prescricoes_entrega(p_ids uuid[])
 returns table (prescricao_id uuid, order_id text, estado_pedido text, estafeta_nome text)
 language sql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
  select pp.id, pp.order_id, o.status,
         -- Só o primeiro nome do estafeta (a farmácia não precisa de mais).
         split_part(btrim(coalesce(d.name, '')), ' ', 1)
    from public.pedidos_prescricao pp
    join public.restaurants r on r.id = pp.restaurant_id
    left join public.orders o on o.id = pp.order_id
    left join public.drivers d on d.user_id = o.driver_id
   where pp.id = any(p_ids) and pp.order_id is not null
     and (public.is_admin() or r.user_id = auth.uid() or r.user_ = auth.uid())
$function$;

revoke all on function public.farmacia_prescricoes_entrega(uuid[]) from public, anon;
grant execute on function public.farmacia_prescricoes_entrega(uuid[]) to authenticated;

-- ---------------------------------------------------------------- 7. painel admin
create or replace function public.admin_prescricoes_listar(p_estado text default null, p_restaurant_id text default null, p_limite integer default 200)
 returns setof jsonb
 language plpgsql
 stable security definer
 set search_path to 'public', 'pg_temp'
as $function$
begin
  if not public.is_admin() then
    raise exception 'Somente admin.' using errcode = '42501';
  end if;
  return query
  select jsonb_build_object(
    'id', pp.id, 'created_at', pp.created_at, 'restaurant_id', pp.restaurant_id, 'loja', r.name,
    'cliente_email', u.email, 'cliente_nome', coalesce(u.raw_user_meta_data->>'name', u.raw_user_meta_data->>'full_name'),
    'tipo', pp.tipo, 'estado', pp.estado,
    'respondido_por_email', ru.email, 'respondido_em', pp.respondido_em,
    'valor_medicamentos_cents', pp.valor_medicamentos_cents, 'taxa_servico_cents', pp.taxa_servico_cents,
    'total_cents', pp.total_cents, 'metodo_pagamento', pp.metodo_pagamento, 'is_demo', pp.is_demo,
    'motivo_recusa', pp.motivo_recusa, 'expira_em', pp.expira_em, 'confirmado_em', pp.confirmado_em,
    'tem_foto', (pp.receita_foto_path is not null or pp.pedido_foto_path is not null),
    'tem_codigos', (pp.receita_numero is not null),
    'dados_apagados_em', pp.dados_apagados_em,
    -- 17/11/2026: pedido ligado, estafeta e pagamento em curso.
    'order_id', pp.order_id,
    'pedido_estado', o.status,
    'pedido_pagamento', o.payment_status,
    'estafeta_nome', d.name,
    'pagamento_metodo', pp.pagamento_metodo,
    'pagamento_order_id', pp.pagamento_order_id,
    'pagamento_iniciado_em', pp.pagamento_iniciado_em,
    'pagamento_alerta', pp.pagamento_alerta)
  from public.pedidos_prescricao pp
  join public.restaurants r on r.id = pp.restaurant_id
  left join auth.users u on u.id = pp.user_id
  left join auth.users ru on ru.id = pp.respondido_por
  left join public.orders o on o.id = coalesce(pp.order_id, pp.pagamento_order_id)
  left join public.drivers d on d.user_id = o.driver_id
  where (p_estado is null or pp.estado = p_estado)
    and (p_restaurant_id is null or pp.restaurant_id = p_restaurant_id)
  order by pp.created_at desc
  limit greatest(1, least(coalesce(p_limite, 200), 1000));
end $function$;
