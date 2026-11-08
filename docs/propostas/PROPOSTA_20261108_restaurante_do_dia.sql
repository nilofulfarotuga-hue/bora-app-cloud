-- PROPOSTA 08/11/2026 — notificação diária "restaurante do dia" (missão m6-crescimento-hermes-2026-11-08, bloco 3).
-- Ordem do Danilo (08/11): "Notificação diária com um restaurante por dia."
-- Quem aplica: a Claude.ai (modo automático seguro: migração em produção não é da sessão do PC).
-- Depois de aplicar: (1) correr a PROVA do fim deste ficheiro; (2) publicar a Edge push-clientes-alvo do ramo
-- ai/2026-11-08-m6-crescimento (aceita "extra" com o restaurant_id; sem ela o aviso chega e o toque abre só a app);
-- (3) copiar este ficheiro para supabase/migrations/<versão>_restaurante_do_dia.sql.
-- Zona verde: não mexe em preços, comissões, carteiras, tokens nem pedidos. Só lê lojas, produtos e quem tem
-- notificações ligadas, e chama a mesma Edge de push dos lembretes do check-in.
--
-- O QUE FAZ, todos os dias à hora do painel (17:30 de Lisboa por omissão):
--   * cada cliente com notificações ligadas (client_push_tokens.active) recebe UM aviso:
--     - se nos últimos 30 dias abriu produtos de restaurantes abertos hoje (product_view_daily), o restaurante que
--       mais abriu ("a que o cliente mais abriu");
--     - senão, o restaurante da rotação (o que há mais tempo não foi o do dia; parceiros primeiro no empate);
--   * o aviso tem 1 prato (com foto, o mais visto do restaurante nos 30 dias) e o toque abre a loja;
--   * só restaurantes ativos (coming_soon=false, is_active_admin, aprovados), abertos ao jantar nesse dia,
--     com pelo menos um prato com foto; nunca bebidas alcoólicas no aviso; lojas demo fora;
--   * janela de 2 h depois da hora (se o relógio parar, não manda às 23 h) e um aviso por pessoa por dia.

-- 1) Interruptor, hora e público (painel: Clientes > Restaurante do dia)
insert into public.platform_settings (key, value, category, description, is_secret, updated_at)
values
  ('restaurante_do_dia_ativo', 'true'::jsonb, 'marketing',
   'Restaurante do dia: envia o aviso diário com um restaurante e um prato (toque abre a loja).', false, now()),
  ('restaurante_do_dia_hora', '"17:30"'::jsonb, 'marketing',
   'Restaurante do dia: hora do aviso (HH:MM, hora de Lisboa).', false, now()),
  ('restaurante_do_dia_so_opt_in', 'false'::jsonb, 'marketing',
   'Restaurante do dia: ligado = só quem aceitou promoções; desligado = todos os clientes com notificações ligadas.', false, now())
on conflict (key) do nothing;

-- 2) Registo da rotação (o painel mostra-o) e anti-repetidos por pessoa
create table if not exists public.restaurante_do_dia_envios (
  id            bigint generated always as identity primary key,
  dia           date not null,
  restaurant_id text not null,
  loja_nome     text not null,
  produto_id    text,
  produto_nome  text,
  motivo        text not null check (motivo in ('rotacao', 'mais_vista')),
  pessoas       integer not null default 0,
  pedido_http   bigint,
  criado_em     timestamptz not null default now(),
  unique (dia, restaurant_id, motivo)
);
alter table public.restaurante_do_dia_envios enable row level security;
revoke all on public.restaurante_do_dia_envios from public, anon, authenticated;

create table if not exists public.restaurante_do_dia_pessoas (
  dia           date not null,
  user_id       uuid not null,
  restaurant_id text not null,
  criado_em     timestamptz not null default now(),
  primary key (dia, user_id)
);
alter table public.restaurante_do_dia_pessoas enable row level security;
revoke all on public.restaurante_do_dia_pessoas from public, anon, authenticated;

-- 3) Aberto ao jantar nesse dia? (business_hours: {"mon": {"open","close","closed",...}, ...}; sem horário = aberto)
create or replace function public._rdd_aberta_ao_jantar(p_bh jsonb, p_dia date)
returns boolean
language plpgsql
immutable
set search_path = public
as $$
declare
  d jsonb;
  v_open text;
  v_close text;
begin
  if p_bh is null or jsonb_typeof(p_bh) <> 'object' or p_bh = '{}'::jsonb then
    return true;
  end if;
  d := p_bh -> (array['sun','mon','tue','wed','thu','fri','sat'])[extract(dow from p_dia)::int + 1];
  if d is null or jsonb_typeof(d) <> 'object' then
    return false;
  end if;
  if coalesce((d ->> 'closed')::boolean, false) then
    return false;
  end if;
  v_open  := coalesce(nullif(d ->> 'open', ''), '00:00');
  v_close := coalesce(nullif(d ->> 'close', ''), '23:59');
  -- fecha depois da meia-noite (close < open) ou fecha depois das 19:30 = serve jantar
  return v_close < v_open or v_close >= '19:30';
end;
$$;

-- 4) Restaurantes que podem ser "o do dia" nesse dia
create or replace function public._rdd_candidatas(p_dia date)
returns table (restaurant_id text, nome text, parceiro boolean, ultima date)
language sql
stable
security definer
set search_path = public
as $$
  select r.id, r.name, coalesce(r.is_partner, false),
         (select max(e.dia) from public.restaurante_do_dia_envios e
           where e.restaurant_id = r.id and e.motivo = 'rotacao')
    from public.restaurants r
   where coalesce(r.coming_soon, false) = false
     and coalesce(r.is_active_admin, true) = true
     and coalesce(r.approval_status, 'approved') = 'approved'
     and r.category in ('restaurant', 'festas')
     and r.name not ilike '%demo%'
     and public._rdd_aberta_ao_jantar(r.business_hours, p_dia)
     and exists (select 1 from public.products p
                  where p.restaurant_id = r.id and p.is_available
                    and coalesce(p.photo_url, '') <> '' and coalesce(p.age_restricted, false) = false);
$$;

-- 5) O prato do aviso: com foto, sem álcool, de preferência o mais visto nos 30 dias; bebidas/extras só se não houver mais nada
create or replace function public._rdd_prato(p_restaurant text, p_dia date)
returns table (produto_id text, produto_nome text)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, p.name
    from public.products p
   where p.restaurant_id = p_restaurant and p.is_available
     and coalesce(p.photo_url, '') <> '' and coalesce(p.age_restricted, false) = false
   order by (coalesce(p.category, '') || ' ' || p.name) ~* '(bebida|refrigerante|água|agua|sumo|ice tea|extra|molho|\mdip\M|caf[eé]|ch[aá] )',
            length(btrim(p.name)) < 4,   -- nomes-código ("T7") só se não houver outro
            (select count(*) from public.product_view_daily v where v.product_id = p.id and v.day > p_dia - 30) desc,
            md5(p.id || p_dia::text)
   limit 1;
$$;

-- 6) O envio do dia (o relógio chama de 10 em 10 min; só faz alguma coisa uma vez por dia, à hora do painel)
create or replace function public.restaurante_do_dia_processar(p_forcar boolean default false)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
declare
  v_hoje      date := (now() at time zone 'Europe/Lisbon')::date;
  v_agora     time := (now() at time zone 'Europe/Lisbon')::time;
  v_ativo     boolean := coalesce((select (value #>> '{}')::boolean from public.platform_settings
                                    where key = 'restaurante_do_dia_ativo'), false);
  v_hora      time := coalesce((select (value #>> '{}')::time from public.platform_settings
                                 where key = 'restaurante_do_dia_hora'), '17:30'::time);
  v_so_opt_in boolean := coalesce((select (value #>> '{}')::boolean from public.platform_settings
                                    where key = 'restaurante_do_dia_so_opt_in'), false);
  v_rot       text;
  v_rot_nome  text;
  v_url       text;
  v_key       text;
  v_nome      text;
  v_prod_id   text;
  v_prod      text;
  v_titulo    text;
  v_texto     text;
  v_req       bigint;
  v_pessoas   integer := 0;
  v_pedidos   integer := 0;
  g           record;
begin
  if not v_ativo and not p_forcar then
    return jsonb_build_object('ok', true, 'enviados', 0, 'motivo', 'desligado');
  end if;
  if not p_forcar and (v_agora < v_hora or v_agora > v_hora + interval '2 hours') then
    return jsonb_build_object('ok', true, 'enviados', 0, 'motivo', 'fora_de_hora', 'hora_lisboa', v_agora);
  end if;
  if not p_forcar and exists (select 1 from public.restaurante_do_dia_envios where dia = v_hoje) then
    return jsonb_build_object('ok', true, 'enviados', 0, 'motivo', 'ja_enviado_hoje');
  end if;

  select c.restaurant_id, c.nome into v_rot, v_rot_nome
    from public._rdd_candidatas(v_hoje) c
   order by c.ultima nulls first, c.parceiro desc, c.nome
   limit 1;
  if v_rot is null then
    return jsonb_build_object('ok', true, 'enviados', 0, 'motivo', 'sem_restaurante_aberto');
  end if;

  select decrypted_secret into v_url from vault.decrypted_secrets where name = 'project_url' limit 1;
  select decrypted_secret into v_key from vault.decrypted_secrets where name = 'service_role_key' limit 1;
  if v_url is null or v_key is null then
    return jsonb_build_object('ok', false, 'erro', 'segredos_em_falta');
  end if;

  for g in
    with alvo as (
      select u.id as user_id
        from public.users u
       where public._checkin_e_cliente(u.id)
         and exists (select 1 from public.client_push_tokens t where t.user_id = u.id and t.active)
         and (not v_so_opt_in or coalesce(u.marketing_opt_in, false))
         and not exists (select 1 from public.restaurante_do_dia_pessoas x where x.dia = v_hoje and x.user_id = u.id)
    ), cand as (
      select c.restaurant_id from public._rdd_candidatas(v_hoje) c
    ), vista as (
      select distinct on (v.user_id) v.user_id, v.restaurant_id
        from public.product_view_daily v
        join cand c on c.restaurant_id = v.restaurant_id
       where v.day > v_hoje - 30
         and v.user_id in (select a.user_id from alvo a)
       group by v.user_id, v.restaurant_id
       order by v.user_id, count(*) desc, max(v.day) desc
    ), escolha as (
      select a.user_id,
             coalesce(vs.restaurant_id, v_rot) as restaurant_id,
             case when vs.restaurant_id is null then 'rotacao' else 'mais_vista' end as motivo
        from alvo a
        left join vista vs on vs.user_id = a.user_id
    ), lotes as (
      select e.*, (row_number() over (partition by e.restaurant_id, e.motivo order by e.user_id) - 1) / 150 as lote
        from escolha e
    )
    select l.restaurant_id, l.motivo, array_agg(l.user_id) as ids
      from lotes l
     group by l.restaurant_id, l.motivo, l.lote
  loop
    select r.name into v_nome from public.restaurants r where r.id = g.restaurant_id;
    v_nome := split_part(v_nome, ' - ', 1);
    select p.produto_id, p.produto_nome into v_prod_id, v_prod from public._rdd_prato(g.restaurant_id, v_hoje) p;
    if g.motivo = 'rotacao' then
      v_titulo := 'O restaurante do dia: ' || v_nome;
      v_texto  := 'Hoje sugerimos ' || coalesce(v_prod, 'o que te apetecer') ||
                  '. Pedes na app e nós vamos buscar e levamos-to a casa.';
    else
      v_titulo := v_nome || ' ao jantar?';
      v_texto  := 'Hoje há ' || coalesce(v_prod, 'de tudo um pouco') || ' na ' || v_nome ||
                  '. Pedes na app e nós levamos-to a casa.';
    end if;

    -- regista primeiro: se o envio falhar, ninguém recebe o mesmo aviso duas vezes
    insert into public.restaurante_do_dia_pessoas (dia, user_id, restaurant_id)
    select v_hoje, x, g.restaurant_id from unnest(g.ids) as x
    on conflict do nothing;

    select net.http_post(
      url := v_url || '/functions/v1/push-clientes-alvo',
      headers := jsonb_build_object('Authorization', 'Bearer ' || v_key, 'Content-Type', 'application/json'),
      body := jsonb_build_object('user_ids', to_jsonb(g.ids), 'title', v_titulo, 'body', v_texto,
                                 'type', 'restaurante_do_dia',
                                 'extra', jsonb_build_object('restaurant_id', g.restaurant_id)),
      timeout_milliseconds := 60000
    ) into v_req;

    insert into public.restaurante_do_dia_envios (dia, restaurant_id, loja_nome, produto_id, produto_nome, motivo, pessoas, pedido_http)
    values (v_hoje, g.restaurant_id, v_nome, v_prod_id, v_prod, g.motivo, array_length(g.ids, 1), v_req)
    on conflict (dia, restaurant_id, motivo) do update
       set pessoas = public.restaurante_do_dia_envios.pessoas + excluded.pessoas,
           pedido_http = excluded.pedido_http;

    v_pessoas := v_pessoas + array_length(g.ids, 1);
    v_pedidos := v_pedidos + 1;
  end loop;

  -- dia sem ninguém a receber: a rotação avança na mesma e o painel mostra o dia
  if v_pedidos = 0 then
    insert into public.restaurante_do_dia_envios (dia, restaurant_id, loja_nome, motivo, pessoas)
    values (v_hoje, v_rot, split_part(v_rot_nome, ' - ', 1), 'rotacao', 0)
    on conflict (dia, restaurant_id, motivo) do nothing;
  end if;

  return jsonb_build_object('ok', true, 'dia', v_hoje, 'rotacao', v_rot, 'pessoas', v_pessoas,
                            'pedidos_http', v_pedidos);
end;
$$;

-- 7) Painel (PT-BR): ver e configurar
create or replace function public.admin_restaurante_do_dia_estado(p_dias integer default 14)
returns jsonb
language plpgsql
stable
security definer
set search_path = public
as $$
declare
  v_amanha date := (now() at time zone 'Europe/Lisbon')::date + 1;
begin
  perform public._admin_op_guard();
  return jsonb_build_object(
    'ativo', coalesce((select (value #>> '{}')::boolean from public.platform_settings where key = 'restaurante_do_dia_ativo'), false),
    'hora', coalesce((select value #>> '{}' from public.platform_settings where key = 'restaurante_do_dia_hora'), '17:30'),
    'so_opt_in', coalesce((select (value #>> '{}')::boolean from public.platform_settings where key = 'restaurante_do_dia_so_opt_in'), false),
    'proxima', (select jsonb_build_object('restaurant_id', c.restaurant_id, 'loja', c.nome)
                  from public._rdd_candidatas(v_amanha) c
                 order by c.ultima nulls first, c.parceiro desc, c.nome limit 1),
    'rotacao', (select coalesce(jsonb_agg(jsonb_build_object('restaurant_id', c.restaurant_id, 'loja', c.nome,
                                                            'parceiro', c.parceiro, 'ultima', c.ultima)
                                          order by c.ultima nulls first, c.parceiro desc, c.nome), '[]'::jsonb)
                  from public._rdd_candidatas(v_amanha) c),
    'envios', (select coalesce(jsonb_agg(jsonb_build_object('dia', e.dia, 'restaurant_id', e.restaurant_id,
                                                           'loja', e.loja_nome, 'prato', e.produto_nome,
                                                           'motivo', e.motivo, 'pessoas', e.pessoas)
                                         order by e.dia desc, e.pessoas desc), '[]'::jsonb)
                 from public.restaurante_do_dia_envios e
                where e.dia > (now() at time zone 'Europe/Lisbon')::date - greatest(coalesce(p_dias, 14), 1))
  );
end;
$$;

create or replace function public.admin_restaurante_do_dia_configurar(
  p_ativo boolean default null, p_hora text default null, p_so_opt_in boolean default null)
returns jsonb
language plpgsql
security definer
set search_path = public
as $$
begin
  perform public._admin_op_guard();
  if p_hora is not null and p_hora !~ '^([01][0-9]|2[0-3]):[0-5][0-9]$' then
    raise exception 'hora inválida: % (usa HH:MM)', p_hora;
  end if;
  if p_ativo is not null then
    update public.platform_settings set value = to_jsonb(p_ativo), updated_at = now(), updated_by = auth.uid()
     where key = 'restaurante_do_dia_ativo';
  end if;
  if p_hora is not null then
    update public.platform_settings set value = to_jsonb(p_hora), updated_at = now(), updated_by = auth.uid()
     where key = 'restaurante_do_dia_hora';
  end if;
  if p_so_opt_in is not null then
    update public.platform_settings set value = to_jsonb(p_so_opt_in), updated_at = now(), updated_by = auth.uid()
     where key = 'restaurante_do_dia_so_opt_in';
  end if;
  return public.admin_restaurante_do_dia_estado(14);
end;
$$;

-- 8) Acesso: funções novas nascem fechadas (regra da casa); só o painel (authenticated + guarda de admin)
revoke all on function public._rdd_aberta_ao_jantar(jsonb, date) from public, anon, authenticated;
revoke all on function public._rdd_candidatas(date) from public, anon, authenticated;
revoke all on function public._rdd_prato(text, date) from public, anon, authenticated;
revoke all on function public.restaurante_do_dia_processar(boolean) from public, anon, authenticated;
revoke all on function public.admin_restaurante_do_dia_estado(integer) from public, anon;
revoke all on function public.admin_restaurante_do_dia_configurar(boolean, text, boolean) from public, anon;
grant execute on function public.admin_restaurante_do_dia_estado(integer) to authenticated;
grant execute on function public.admin_restaurante_do_dia_configurar(boolean, text, boolean) to authenticated;

-- 9) Relógio: de 10 em 10 min (a função só envia uma vez por dia, entre a hora do painel e 2 h depois)
select cron.schedule('restaurante-do-dia', '*/10 * * * *', 'select public.restaurante_do_dia_processar();');

-- ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
-- PROVA (correr DEPOIS de aplicar; não envia nada a ninguém: o RAISE desfaz tudo, incluindo o pedido do pg_net)
-- do $$
-- declare r jsonb; n int;
-- begin
--   r := public.restaurante_do_dia_processar(true);
--   select count(*) into n from public.restaurante_do_dia_pessoas where dia = (now() at time zone 'Europe/Lisbon')::date;
--   raise exception 'PROVA (desfeita): % | pessoas registadas % | envios %', r, n,
--     (select jsonb_agg(jsonb_build_object('loja', loja_nome, 'prato', produto_nome, 'motivo', motivo, 'pessoas', pessoas))
--        from public.restaurante_do_dia_envios where dia = (now() at time zone 'Europe/Lisbon')::date);
-- end $$;
