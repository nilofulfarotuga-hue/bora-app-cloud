-- 28/11/2026 (ordem do Danilo 09:38): entrar na app sem telemovel e sem morada pode;
-- fazer pedido NAO pode. Missao pedido-exige-telefone-e-morada-2026-11-28.
--
-- O que muda:
--  1) telefone_valido(text): numero de QUALQUER pais em formato internacional (+indicativo,
--     adendo do Danilo 10:10) ou o numero nacional de 9 digitos ja guardado. A validacao fina
--     por pais faz-se na app.
--  2) cliente_dados_em_falta(...): o que falta ao cliente ligado (a app e o robo leem).
--  3) _exigir_contacto_pedido(...): rebenta com SEM_TELEFONE / SEM_MORADA (codigos que a
--     app transforma no passo "Falta so isto").
--  4) Pedidos de entrega (restaurantes, mercados, farmacia, Favores, agendados): gatilho
--     BEFORE INSERT so de verificacao (a funcao de criar pedidos e zona do dinheiro e fica
--     intacta). So para a sessao do proprio cliente: o servidor (service_role, p.ex. o pedido
--     de cartao ja pago) e o admin passam sempre, para nunca se perder um pedido pago. A conta
--     de demonstracao da Boom passa. Se o pedido vier sem client_phone, leva o telemovel do
--     perfil (o estafeta precisa dele).
--  5) Gatilho BEFORE INSERT nas outras categorias (Casa, limpeza, lavagem, reservas de mesa,
--     marcacoes): telemovel sempre; o TVDE esta fechado desde 04/11 e fica de fora; morada com coordenadas so onde ha visita.
--  6) Registo de quem parou no passo "Falta so isto" (painel admin) e funcoes do admin.
-- Nao mexe em precos, comissoes nem taxas.

create or replace function public.telefone_normalizado(p text)
returns text language sql immutable as $$
  select nullif(regexp_replace(coalesce(p, ''), '[\s\-\.\(\)]', '', 'g'), '')
$$;

create or replace function public.telefone_valido(p text)
returns boolean language sql immutable as $$
  select coalesce(
    public.telefone_normalizado(p) ~ '^(\+|00)[1-9][0-9]{6,14}$'
    or public.telefone_normalizado(p) ~ '^[1-9][0-9]{8}$',
    false)
$$;

-- Morada boa = texto (rua ou morada completa) + coordenadas.
create or replace function public._cliente_tem_morada(p_user uuid)
returns boolean language sql stable security definer set search_path to 'public' as $$
  select exists (
    select 1 from public.client_addresses ca
     where ca.user_id = p_user
       and ca.lat is not null and ca.lng is not null
       and length(trim(coalesce(nullif(ca.street, ''), ca.address, ''))) >= 3)
$$;

create or replace function public._cliente_telefone(p_user uuid)
returns text language sql stable security definer set search_path to 'public' as $$
  select case when public.telefone_valido(u.phone) then public.telefone_normalizado(u.phone) end
    from public.users u where u.id = p_user
$$;

-- Quem esta ligado e um cliente a pedir para si (nao o servidor, nao o admin).
create or replace function public._e_sessao_de_cliente()
returns boolean language sql stable security definer set search_path to 'public' as $$
  select auth.uid() is not null
     and coalesce(auth.jwt() ->> 'role', '') <> 'service_role'
     and not coalesce(public.is_admin(), false)
$$;

-- Para a app e o robo: o que falta ao cliente ligado. O admin pode perguntar por outro.
create or replace function public.cliente_dados_em_falta(p_user uuid default null)
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
declare
  v_uid uuid := case when p_user is not null and coalesce(public.is_admin(), false) then p_user else auth.uid() end;
  v_tel text;
  v_mor boolean;
begin
  if v_uid is null then
    return jsonb_build_object('ok', false, 'error', 'AUTH_REQUIRED');
  end if;
  v_tel := public._cliente_telefone(v_uid);
  v_mor := public._cliente_tem_morada(v_uid);
  return jsonb_build_object(
    'ok', true,
    'falta_telefone', v_tel is null,
    'falta_morada', not v_mor,
    'telefone', v_tel);
end $$;

-- A guarda. p_precisa_morada = ha entrega ou visita. p_lat/p_lng = a morada do proprio pedido.
create or replace function public._exigir_contacto_pedido(
  p_user uuid, p_phone text, p_precisa_morada boolean,
  p_lat double precision default null, p_lng double precision default null,
  p_morada_texto text default null)
returns void language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not public._e_sessao_de_cliente() or p_user is distinct from auth.uid() then
    return;
  end if;
  -- A demonstracao da Boom (telemovel 1 da demo) continua a funcionar como sempre.
  begin
    if p_user = (public._modo_demo_def()->>'cliente_user_id')::uuid then
      return;
    end if;
  exception when others then null;
  end;
  if not public.telefone_valido(p_phone) and public._cliente_telefone(p_user) is null then
    raise exception 'SEM_TELEFONE: falta o telemovel para o estafeta te contactar'
      using errcode = 'P0001', hint = 'falta_so_isto';
  end if;
  if p_precisa_morada and (
       p_lat is null or p_lng is null
       or (p_morada_texto is not null and length(trim(p_morada_texto)) < 3)) then
    raise exception 'SEM_MORADA: falta a morada exata da entrega'
      using errcode = 'P0001', hint = 'falta_so_isto';
  end if;
end $$;

-- Pedidos de entrega: so verifica e, se faltar, poe o telemovel do perfil no pedido.
create or replace function public._trg_pedido_exige_contacto()
returns trigger language plpgsql security definer set search_path to 'public' as $$
begin
  perform public._exigir_contacto_pedido(
    new.user_id, new.client_phone,
    coalesce(new.service_type, '') <> 'takeaway',
    new.dropoff_lat, new.dropoff_lng,
    coalesce(nullif(new.dropoff_address, ''), nullif(new.dropoff_street, ''), ''));
  if not public.telefone_valido(new.client_phone)
     and public._e_sessao_de_cliente() and new.user_id = auth.uid() then
    new.client_phone := coalesce(public._cliente_telefone(new.user_id), new.client_phone);
  end if;
  return new;
end $$;

create or replace trigger _a0_pedido_exige_contacto before insert on public.orders
  for each row execute function public._trg_pedido_exige_contacto();

-- Gatilho comum das outras categorias. TG_ARGV[0] = coluna do cliente; TG_ARGV[1] = 'morada'
-- quando ha visita (lat, lng e address_street do proprio registo).
create or replace function public._trg_exige_contacto()
returns trigger language plpgsql security definer set search_path to 'public' as $$
declare
  v_row jsonb := to_jsonb(new);
  v_user uuid := nullif(v_row->>tg_argv[0], '')::uuid;
  v_morada boolean := coalesce(tg_argv[1], '') = 'morada';
begin
  perform public._exigir_contacto_pedido(
    v_user, v_row->>'client_phone', v_morada,
    nullif(v_row->>'lat', '')::double precision,
    nullif(v_row->>'lng', '')::double precision,
    case when v_morada then coalesce(v_row->>'address_street', '') end);
  -- O telemovel do perfil vai no registo quando a tabela o guarda e veio vazio.
  if v_row ? 'client_phone' and not public.telefone_valido(v_row->>'client_phone')
     and public._e_sessao_de_cliente() and v_user = auth.uid() then
    new := jsonb_populate_record(new, jsonb_build_object('client_phone',
      coalesce(public._cliente_telefone(v_user), v_row->>'client_phone')));
  end if;
  return new;
end $$;

create or replace trigger trg_00a_exige_contacto before insert on public.casa_pedidos
  for each row execute function public._trg_exige_contacto('client_user_id', 'morada');
create or replace trigger trg_00a_exige_contacto before insert on public.cleaning_bookings
  for each row execute function public._trg_exige_contacto('client_user_id', 'morada');
create or replace trigger trg_00a_exige_contacto before insert on public.carwash_bookings
  for each row execute function public._trg_exige_contacto('client_user_id', 'morada');
create or replace trigger trg_00a_exige_contacto before insert on public.reservations
  for each row execute function public._trg_exige_contacto('client_user_id', '');
create or replace trigger trg_00a_exige_contacto before insert on public.appointments
  for each row execute function public._trg_exige_contacto('client_user_id', '');

-- ── Painel: quem parou no passo "Falta so isto" ──
create table if not exists public.falta_so_isto_eventos (
  id bigint generated always as identity primary key,
  user_id uuid not null default auth.uid(),
  criado_em timestamptz not null default now(),
  categoria text,
  faltava_telefone boolean not null default false,
  faltava_morada boolean not null default false,
  acao text not null default 'abriu' check (acao in ('abriu', 'completou', 'desistiu'))
);
create index if not exists falta_so_isto_eventos_user_idx on public.falta_so_isto_eventos (user_id, criado_em desc);
alter table public.falta_so_isto_eventos enable row level security;
create policy falta_so_isto_inserir_proprio on public.falta_so_isto_eventos
  for insert to authenticated with check (user_id = auth.uid());
create policy falta_so_isto_admin_ler on public.falta_so_isto_eventos
  for select to authenticated using (public.is_admin());

-- A app regista o passo (nunca rebenta o pedido se falhar).
create or replace function public.falta_so_isto_registar(
  p_categoria text, p_faltava_telefone boolean, p_faltava_morada boolean, p_acao text default 'abriu')
returns void language plpgsql security definer set search_path to 'public' as $$
begin
  if auth.uid() is null then return; end if;
  insert into public.falta_so_isto_eventos (user_id, categoria, faltava_telefone, faltava_morada, acao)
  values (auth.uid(), left(coalesce(p_categoria, ''), 40), coalesce(p_faltava_telefone, false),
          coalesce(p_faltava_morada, false),
          case when p_acao in ('abriu', 'completou', 'desistiu') then p_acao else 'abriu' end);
end $$;

-- Painel (PT-BR): contadores e lista de quem parou no passo e nao completou.
create or replace function public.admin_clientes_contacto_resumo()
returns jsonb language plpgsql stable security definer set search_path to 'public' as $$
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'ADMIN_ONLY' using errcode = '42501';
  end if;
  return jsonb_build_object(
    'clientes', (select count(*) from public.users u where coalesce(u.role, 'client') = 'client'),
    'sem_telefone', (select count(*) from public.users u where coalesce(u.role, 'client') = 'client'
                      and not public.telefone_valido(u.phone)),
    'sem_morada', (select count(*) from public.users u where coalesce(u.role, 'client') = 'client'
                      and not public._cliente_tem_morada(u.id)),
    'parados', coalesce((
      select jsonb_agg(x order by x->>'quando' desc) from (
        select jsonb_build_object(
          'user_id', e.user_id, 'nome', u.name, 'email', u.email, 'telefone', u.phone,
          'categoria', e.categoria, 'faltava_telefone', e.faltava_telefone,
          'faltava_morada', e.faltava_morada, 'quando', e.criado_em,
          'falta_telefone_agora', not public.telefone_valido(u.phone),
          'falta_morada_agora', not public._cliente_tem_morada(e.user_id)) x
        from (select distinct on (user_id) * from public.falta_so_isto_eventos
               where criado_em > now() - interval '30 days'
               order by user_id, criado_em desc) e
        left join public.users u on u.id = e.user_id
        where e.acao <> 'completou'
        limit 100) s), '[]'::jsonb));
end $$;

-- Painel: o Danilo poe ou corrige o telemovel de um cliente.
create or replace function public.admin_cliente_definir_telefone(p_user uuid, p_phone text)
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_tel text := public.telefone_normalizado(p_phone);
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'ADMIN_ONLY' using errcode = '42501';
  end if;
  if v_tel ~ '^[29][0-9]{8}$' then v_tel := '+351' || v_tel; end if;
  if not public.telefone_valido(v_tel) then
    raise exception 'TELEFONE_INVALIDO' using errcode = '22023';
  end if;
  update public.users set phone = v_tel where id = p_user;
  return jsonb_build_object('ok', found, 'telefone', v_tel);
end $$;

-- Painel: o Danilo poe ou corrige a morada principal de um cliente.
create or replace function public.admin_cliente_definir_morada(
  p_user uuid, p_address text, p_lat double precision, p_lng double precision,
  p_details text default null, p_label text default 'Casa')
returns jsonb language plpgsql security definer set search_path to 'public' as $$
declare v_id uuid;
begin
  if not coalesce(public.is_admin(), false) then
    raise exception 'ADMIN_ONLY' using errcode = '42501';
  end if;
  if length(trim(coalesce(p_address, ''))) < 3 or p_lat is null or p_lng is null then
    raise exception 'MORADA_INVALIDA' using errcode = '22023';
  end if;
  select id into v_id from public.client_addresses
   where user_id = p_user order by is_default desc nulls last, updated_at desc nulls last limit 1;
  if v_id is null then
    insert into public.client_addresses (user_id, label, address, lat, lng, is_default, details)
    values (p_user, coalesce(p_label, 'Casa'), trim(p_address), p_lat, p_lng, true, p_details)
    returning id into v_id;
  else
    update public.client_addresses
       set address = trim(p_address), lat = p_lat, lng = p_lng,
           details = coalesce(p_details, details), updated_at = now()
     where id = v_id;
  end if;
  return jsonb_build_object('ok', true, 'id', v_id);
end $$;

revoke all on function public._exigir_contacto_pedido(uuid, text, boolean, double precision, double precision, text) from public, anon;
revoke all on function public._cliente_telefone(uuid) from public, anon, authenticated;
revoke all on function public._cliente_tem_morada(uuid) from public, anon, authenticated;
revoke all on function public.cliente_dados_em_falta(uuid) from public, anon;
grant execute on function public.cliente_dados_em_falta(uuid) to authenticated;
revoke all on function public.falta_so_isto_registar(text, boolean, boolean, text) from public, anon;
grant execute on function public.falta_so_isto_registar(text, boolean, boolean, text) to authenticated;
revoke all on function public.admin_clientes_contacto_resumo() from public, anon;
grant execute on function public.admin_clientes_contacto_resumo() to authenticated;
revoke all on function public.admin_cliente_definir_telefone(uuid, text) from public, anon;
grant execute on function public.admin_cliente_definir_telefone(uuid, text) to authenticated;
revoke all on function public.admin_cliente_definir_morada(uuid, text, double precision, double precision, text, text) from public, anon;
grant execute on function public.admin_cliente_definir_morada(uuid, text, double precision, double precision, text, text) to authenticated;
