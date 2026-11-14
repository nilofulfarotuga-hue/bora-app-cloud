-- Missão farmacias-loja-2026-11-14 · bloco 3 — produto que só chega daqui a umas horas.
-- Revisto e aplicado pela Claude.ai a 14/11/2026 (fonte: .claude/.ai/missoes/farmacias-loja-2026-11-14/a2_chegada_tardia.PROPOSTA.sql).
-- O 'cancelar' usa o caminho de sempre (status cancelled + initiator system + gatilho trg_reembolso_cancelado_pelo_sistema).

-- ── Tabela ──────────────────────────────────────────────────────────────────────────────────
create table if not exists public.pedido_chegada_tardia (
  id uuid primary key default gen_random_uuid(),
  order_id text not null references public.orders(id) on delete cascade,
  restaurant_id text not null references public.restaurants(id) on delete cascade,
  user_id uuid,                       -- cliente do pedido (cópia, para as regras de leitura)
  linha_idx integer,                  -- linha de orders.items (0 = 1.ª); null = o pedido todo
  product_id text,
  produto_nome text,
  chega_as timestamptz not null,
  estado text not null default 'pendente'
    check (estado in ('pendente', 'esperar', 'tirar', 'cancelar', 'anulado')),
  scheduled_for_antes timestamptz,    -- para voltar atrás em "tirar" / "anular"
  ready_at_antes timestamptz,
  criado_por uuid,
  criado_em timestamptz not null default now(),
  respondido_em timestamptz,
  respondido_por uuid
);
create index if not exists pedido_chegada_tardia_order_idx on public.pedido_chegada_tardia (order_id);
create index if not exists pedido_chegada_tardia_loja_idx on public.pedido_chegada_tardia (restaurant_id, criado_em desc);
-- Uma hora marcada viva de cada vez por pedido.
create unique index if not exists pedido_chegada_tardia_uma_viva
  on public.pedido_chegada_tardia (order_id) where estado in ('pendente', 'esperar');

alter table public.pedido_chegada_tardia enable row level security;
revoke all on table public.pedido_chegada_tardia from public, anon;
grant select on table public.pedido_chegada_tardia to authenticated;

drop policy if exists pedido_chegada_tardia_ler on public.pedido_chegada_tardia;
create policy pedido_chegada_tardia_ler on public.pedido_chegada_tardia
  for select to authenticated
  using (
    user_id = (select auth.uid())
    or exists (select 1 from public.restaurants r
                where r.id = pedido_chegada_tardia.restaurant_id
                  and coalesce(r.user_id, r.user_) = (select auth.uid()))
    or public._is_admin((select auth.uid()))
  );
-- Sem políticas de escrita: só as funções abaixo escrevem.

do $$
begin
  if not exists (select 1 from pg_publication_tables
                  where pubname = 'supabase_realtime' and schemaname = 'public'
                    and tablename = 'pedido_chegada_tardia') then
    alter publication supabase_realtime add table public.pedido_chegada_tardia;
  end if;
end $$;

-- ── Avisos (sininho + push) ─────────────────────────────────────────────────────────────────
-- Cliente: notify-client com orderId = o pedido e type 'farmacia_chegada' (o toque abre o pedido).
-- Farmácia: notify-partner com o pedido e kind 'farmacia_chegada_resposta'.
create or replace function public._farmacia_chegada_avisar(p_id uuid, p_para text, p_tipo text, p_titulo text, p_corpo text)
returns void
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v record; v_dono uuid; v_url text; v_key text;
begin
  select c.order_id, c.restaurant_id, c.user_id into v from public.pedido_chegada_tardia c where c.id = p_id;
  if not found then return; end if;
  select coalesce(r.user_id, r.user_) into v_dono from public.restaurants r where r.id = v.restaurant_id;
  begin
    perform public._push_in_app_notification(case when p_para = 'cliente' then v.user_id else v_dono end,
                                             p_tipo, p_titulo, p_corpo, v.order_id);
  exception when others then raise notice 'farmacia_chegada sininho: %', sqlerrm;
  end;
  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url';
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key';
  if v_url is null or v_key is null then return; end if;
  begin
    if p_para = 'cliente' then
      if v.user_id is not null then
        perform net.http_post(url := v_url || '/functions/v1/notify-client',
          headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
          body := jsonb_build_object('clientId', v.user_id, 'orderId', v.order_id, 'type', p_tipo,
                                     'status', p_tipo, 'title', p_titulo, 'body', p_corpo));
      end if;
    else
      perform net.http_post(url := v_url || '/functions/v1/notify-partner',
        headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
        body := jsonb_build_object('restaurantId', v.restaurant_id, 'orderId', v.order_id, 'kind', p_tipo,
                                   'customTitle', p_titulo, 'customBody', p_corpo, 'items', p_corpo));
    end if;
  exception when others then raise notice 'farmacia_chegada push: %', sqlerrm;
  end;
end $$;
revoke all on function public._farmacia_chegada_avisar(uuid, text, text, text, text) from public, anon, authenticated;

-- "14:30" em hora de Lisboa.
create or replace function public._farmacia_hhmm(p_ts timestamptz)
returns text
language sql stable
set search_path = public, pg_temp
as $$ select to_char(p_ts at time zone 'Europe/Lisbon', 'HH24:MI') $$;
revoke all on function public._farmacia_hhmm(timestamptz) from public, anon;
grant execute on function public._farmacia_hhmm(timestamptz) to authenticated;

-- ── Farmácia: marcar "chega às" (aceita o pedido se ainda não estava aceite) ───────────────
create or replace function public.farmacia_chegada_marcar(
  p_order_id text,
  p_chega_as timestamptz,
  p_linha_idx integer default null,
  p_prep_minutes integer default null)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_o record;
  v_r record;
  v_item jsonb;
  v_nome text;
  v_pid text;
  v_id uuid;
  v_res jsonb;
  v_ant integer;
  v_min integer;
begin
  if v_uid is null then
    raise exception 'SEM_SESSAO: Tem de entrar na sua conta.' using errcode = '42501';
  end if;

  select o.id, o.restaurant_id, o.user_id, o.status::text as status, o.service_type::text as service_type,
         coalesce(o.is_partner_store, false) as parceira, o.assigned_driver_id, o.driver_id,
         o.items, o.scheduled_for, o.ready_at_promised
    into v_o
    from public.orders o where o.id = p_order_id for update;
  if not found then
    raise exception 'PEDIDO_NAO_EXISTE: Pedido não encontrado.' using errcode = 'P0001';
  end if;

  select r.id, r.category, r.user_id, r.user_ into v_r from public.restaurants r where r.id = v_o.restaurant_id;
  if coalesce(v_r.category, '') <> 'pharmacy' then
    raise exception 'SO_FARMACIAS: Isto só existe nas farmácias.' using errcode = 'P0001';
  end if;
  if coalesce(v_r.user_id, v_r.user_) is distinct from v_uid and not public._is_admin(v_uid) then
    raise exception 'SEM_PERMISSAO: Este pedido não é da sua loja.' using errcode = '42501';
  end if;
  if not v_o.parceira or coalesce(v_o.service_type, '') <> 'restaurant' then
    raise exception 'PEDIDO_NAO_SERVE: Só nos pedidos com entrega feitos na app.' using errcode = 'P0001';
  end if;
  if v_o.status not in ('created', 'preparing')
     or v_o.assigned_driver_id is not null or v_o.driver_id is not null then
    raise exception 'ESTAFETA_JA_CHAMADO: O estafeta já foi chamado. Fale com o cliente pelo chat.' using errcode = 'P0001';
  end if;

  -- O despacho chama o estafeta em scheduled_for − antecedência: a hora tem de ficar depois disso
  -- com folga, senão o estafeta seria chamado antes de o cliente responder.
  v_ant := greatest(coalesce(public._setting_int('dispatch_antecedencia_agendado_minutos', 30), 30), 0);
  v_min := v_ant + 15;
  if p_chega_as is null or p_chega_as < now() + make_interval(mins => v_min) then
    raise exception 'HORA_CEDO: Escolha uma hora daqui a mais de % minutos. Se chega antes, aceite com mais tempo de preparação.', v_min
      using errcode = 'P0001';
  end if;
  if p_chega_as > now() + interval '12 hours' then
    raise exception 'HORA_TARDE: No máximo 12 horas a partir de agora.' using errcode = 'P0001';
  end if;
  if exists (select 1 from public.pedido_chegada_tardia c
              where c.order_id = p_order_id and c.estado in ('pendente', 'esperar')) then
    raise exception 'JA_MARCADO: Este pedido já tem uma hora marcada. Anule-a primeiro.' using errcode = 'P0001';
  end if;

  if p_linha_idx is not null then
    if jsonb_typeof(v_o.items) is distinct from 'array'
       or p_linha_idx < 0 or p_linha_idx >= jsonb_array_length(v_o.items) then
      raise exception 'LINHA_INVALIDA: Esse produto não está no pedido.' using errcode = 'P0001';
    end if;
    v_item := v_o.items -> p_linha_idx;
    v_nome := nullif(btrim(coalesce(v_item->>'name', '')), '');
    v_pid := coalesce(v_item->>'productId', v_item->>'product_id');
  end if;

  -- Aceitar pelo mesmo caminho do botão "Aceitar pedido" (partner_aceitar_pedido).
  if v_o.status = 'created' then
    v_res := public.partner_aceitar_pedido(p_order_id, p_prep_minutes);
    if not coalesce((v_res->>'ok')::boolean, false) then
      raise exception 'NAO_ACEITOU: Não foi possível aceitar o pedido (%).', coalesce(v_res->>'error', 'erro')
        using errcode = 'P0001';
    end if;
  end if;

  insert into public.pedido_chegada_tardia (
    order_id, restaurant_id, user_id, linha_idx, product_id, produto_nome, chega_as,
    scheduled_for_antes, ready_at_antes, criado_por)
  values (
    p_order_id, v_o.restaurant_id, v_o.user_id, p_linha_idx, v_pid, v_nome, p_chega_as,
    v_o.scheduled_for, v_o.ready_at_promised, v_uid)
  returning id into v_id;

  -- Segura o estafeta até perto da hora (enquanto o cliente não responde = esperar).
  update public.orders
     set scheduled_for = p_chega_as,
         ready_at_promised = p_chega_as
   where id = p_order_id;

  perform public._farmacia_chegada_avisar(v_id, 'cliente', 'farmacia_chegada',
    case when v_nome is null then 'O seu pedido só fica pronto às ' || public._farmacia_hhmm(p_chega_as)
         else '"' || v_nome || '" só chega às ' || public._farmacia_hhmm(p_chega_as) end,
    'Escolha: esperar, tirar o produto ou cancelar sem custo. Toque para responder.');

  return jsonb_build_object('ok', true, 'id', v_id, 'chega_as', p_chega_as);
end $$;
revoke all on function public.farmacia_chegada_marcar(text, timestamptz, integer, integer) from public, anon;
grant execute on function public.farmacia_chegada_marcar(text, timestamptz, integer, integer) to authenticated;

-- ── Cliente: responder ─────────────────────────────────────────────────────────────────────
create or replace function public.farmacia_chegada_responder(p_id uuid, p_escolha text)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_c record;
  v_o record;
  v_hhmm text;
  v_curto text;
  v_feito integer;
begin
  if v_uid is null then
    raise exception 'SEM_SESSAO: Tem de entrar na sua conta.' using errcode = '42501';
  end if;
  if p_escolha is null or p_escolha not in ('esperar', 'tirar', 'cancelar') then
    raise exception 'ESCOLHA_INVALIDA: Escolha esperar, tirar ou cancelar.' using errcode = 'P0001';
  end if;

  select c.* into v_c from public.pedido_chegada_tardia c where c.id = p_id for update;
  if not found then
    raise exception 'NAO_EXISTE: Aviso não encontrado.' using errcode = 'P0001';
  end if;
  if v_c.user_id is distinct from v_uid then
    raise exception 'SEM_PERMISSAO: Este pedido não é seu.' using errcode = '42501';
  end if;
  if v_c.estado <> 'pendente' then
    raise exception 'JA_RESPONDIDO: Já respondeu a este aviso.' using errcode = 'P0001';
  end if;
  if p_escolha = 'tirar' and v_c.linha_idx is null then
    raise exception 'ESCOLHA_INVALIDA: Aqui é o pedido todo. Escolha esperar ou cancelar.' using errcode = 'P0001';
  end if;

  select o.id, o.status::text as status, o.assigned_driver_id, o.driver_id
    into v_o from public.orders o where o.id = v_c.order_id for update;
  if not found or v_o.status in ('delivered', 'cancelled', 'rejected') then
    raise exception 'PEDIDO_FECHADO: Este pedido já terminou.' using errcode = 'P0001';
  end if;

  v_hhmm := public._farmacia_hhmm(v_c.chega_as);
  v_curto := upper(right(v_c.order_id, 4));

  if p_escolha = 'esperar' then
    update public.pedido_chegada_tardia
       set estado = 'esperar', respondido_em = now(), respondido_por = v_uid
     where id = p_id;
    -- scheduled_for já está na hora marcada desde farmacia_chegada_marcar.
    perform public._farmacia_chegada_avisar(p_id, 'loja', 'farmacia_chegada_resposta',
      'O cliente espera pelo produto',
      'Pedido #' || v_curto || ' fica para as ' || v_hhmm || '. O estafeta é chamado perto da hora.');

  elsif p_escolha = 'tirar' then
    update public.pedido_chegada_tardia
       set estado = 'tirar', respondido_em = now(), respondido_por = v_uid
     where id = p_id;
    -- Volta ao horário de antes (o produto sai; o resto segue já).
    update public.orders
       set scheduled_for = v_c.scheduled_for_antes,
           ready_at_promised = v_c.ready_at_antes
     where id = v_c.order_id
       and status in ('created', 'preparing')
       and assigned_driver_id is null
       and scheduled_for is not distinct from v_c.chega_as;
    perform public._farmacia_chegada_avisar(p_id, 'loja', 'farmacia_chegada_resposta',
      'O cliente prefere sem o produto',
      'Pedido #' || v_curto || ': tire "' || coalesce(v_c.produto_nome, 'o produto') ||
      '" em "Marcar em falta". O cliente recebe a diferença.');

  else -- cancelar
    if v_o.status not in ('created', 'preparing')
       or v_o.assigned_driver_id is not null or v_o.driver_id is not null then
      raise exception 'ESTAFETA_JA_CHAMADO: O estafeta já foi chamado. Fale com a farmácia pelo chat.' using errcode = 'P0001';
    end if;
    update public.pedido_chegada_tardia
       set estado = 'cancelar', respondido_em = now(), respondido_por = v_uid
     where id = p_id;
    -- Caminho de sempre do cancelamento sem culpa do cliente (taxa 0; o gatilho
    -- trg_reembolso_cancelado_pelo_sistema devolve o que foi pago).
    update public.orders
       set status = 'cancelled',
           cancelled_at = now(),
           cancellation_initiator = 'system',
           cancel_reason = 'farmacia_produto_chega_mais_tarde',
           cancel_fee = 0,
           current_driver_offer_id = null,
           driver_offer_expires_at = null,
           dispatch_next_retry_at = null
     where id = v_c.order_id
       and status in ('created', 'preparing')
       and assigned_driver_id is null;
    get diagnostics v_feito = row_count;
    if v_feito = 0 then
      raise exception 'ESTAFETA_JA_CHAMADO: O estafeta já foi chamado. Fale com a farmácia pelo chat.' using errcode = 'P0001';
    end if;
    perform public._farmacia_chegada_avisar(p_id, 'loja', 'farmacia_chegada_resposta',
      'O cliente cancelou o pedido',
      'Pedido #' || v_curto || ' cancelado sem custo. Já não precisa de o preparar.');
  end if;

  return jsonb_build_object('ok', true, 'estado', p_escolha);
end $$;
revoke all on function public.farmacia_chegada_responder(uuid, text) from public, anon;
grant execute on function public.farmacia_chegada_responder(uuid, text) to authenticated;

-- ── Farmácia: anular (enganou-se ou o produto chegou antes) ────────────────────────────────
create or replace function public.farmacia_chegada_anular(p_id uuid)
returns jsonb
language plpgsql security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_c record;
  v_dono uuid;
begin
  if v_uid is null then
    raise exception 'SEM_SESSAO: Tem de entrar na sua conta.' using errcode = '42501';
  end if;
  select c.* into v_c from public.pedido_chegada_tardia c where c.id = p_id for update;
  if not found then
    raise exception 'NAO_EXISTE: Aviso não encontrado.' using errcode = 'P0001';
  end if;
  select coalesce(r.user_id, r.user_) into v_dono from public.restaurants r where r.id = v_c.restaurant_id;
  if v_dono is distinct from v_uid and not public._is_admin(v_uid) then
    raise exception 'SEM_PERMISSAO: Este pedido não é da sua loja.' using errcode = '42501';
  end if;
  if v_c.estado not in ('pendente', 'esperar') then
    raise exception 'JA_RESPONDIDO: Já não dá para anular.' using errcode = 'P0001';
  end if;

  update public.pedido_chegada_tardia
     set estado = 'anulado', respondido_em = now(), respondido_por = v_uid
   where id = p_id;
  update public.orders
     set scheduled_for = v_c.scheduled_for_antes,
         ready_at_promised = v_c.ready_at_antes
   where id = v_c.order_id
     and status in ('created', 'preparing')
     and assigned_driver_id is null
     and scheduled_for is not distinct from v_c.chega_as;

  perform public._farmacia_chegada_avisar(p_id, 'cliente', 'farmacia_chegada',
    'A farmácia já tem tudo',
    'O seu pedido segue sem esperar. Não precisa de fazer nada.');
  return jsonb_build_object('ok', true);
end $$;
revoke all on function public.farmacia_chegada_anular(uuid) from public, anon;
grant execute on function public.farmacia_chegada_anular(uuid) to authenticated;
