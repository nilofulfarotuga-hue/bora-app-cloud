-- C6 · MODO OCUPADO DO PARCEIRO ("busy mode" da Uber Eats / Glovo / iFood) — 29/10/2026
-- Item 6 do plano do Danilo (adendo 5).
--
-- O que é: a loja está com muitos pedidos e carrega em +10 / +20 / +30 min.
-- Durante 2 horas (ou até desligar) os pedidos novos mostram ao cliente um tempo de
-- entrega maior. O despacho soma esse tempo à preparação — essa parte NÃO está aqui: está
-- na proposta docs/propostas/missao-geral-2026-10-28/C6_modo_ocupado/01_dispatch_proposta.sql,
-- porque a regra de quando se chama o estafeta é zona protegida e fica para revisão.
-- "Fica pronto às HH:MM" num pedido já aceite: grava orders.ready_at_promised.
--
-- NADA MEXE EM DINHEIRO. Interruptor `partner_busy_mode_enabled` nasce DESLIGADO:
--   * desligado, `partner_busy_extra_minutes` devolve sempre 0 e `partner_set_busy` recusa
--     ligar (só deixa desligar), por isso o servidor não muda nada;
--   * as apps só desenham o cartão e somam o tempo com o interruptor ligado.
-- Todas as funções são SECURITY DEFINER e fechadas a `anon`.
--
-- Como desfazer (tudo é novo, nada se altera noutras tabelas):
--   drop function if exists public.partner_set_ready_at(text, timestamptz);
--   drop function if exists public.admin_partner_busy_desligar(text);
--   drop function if exists public.admin_partner_busy_list();
--   drop function if exists public.partner_set_busy(text, integer);
--   drop function if exists public.partner_busy_extra_minutes(text);
--   drop function if exists public._partner_busy_mode_on();
--   alter table public.orders drop column if exists ready_at_promised;
--   alter table public.restaurants drop column if exists busy_until, drop column if exists busy_extra_minutes;
--   delete from public.platform_settings where key = 'partner_busy_mode_enabled';

-- ── 1) Interruptor (desligado por defeito; ON CONFLICT não desfaz escolha do admin) ──
insert into public.platform_settings (key, value, description, category, is_secret)
values (
  'partner_busy_mode_enabled',
  'false'::jsonb,
  'Modo ocupado do parceiro. Ligado: a loja pode carregar em +10, +20 ou +30 min quando está com muitos pedidos; os clientes veem um tempo de entrega maior e o aviso "Tempo maior do que o normal"; dura 2 horas ou até a loja desligar. Desligado: nada muda nas telas nem no servidor. Não mexe em nenhum valor cobrado ou pago.',
  'partners',
  false
)
on conflict (key) do nothing;

-- ── 2) Colunas novas (todas opcionais; quem não usa o modo não repara) ──
alter table public.restaurants
  add column if not exists busy_extra_minutes integer not null default 0,
  add column if not exists busy_until timestamptz;

alter table public.restaurants
  drop constraint if exists restaurants_busy_extra_minutes_ok;
alter table public.restaurants
  add constraint restaurants_busy_extra_minutes_ok
  check (busy_extra_minutes between 0 and 60);

comment on column public.restaurants.busy_extra_minutes is
  'Modo ocupado: minutos a somar ao tempo de entrega (0 = sem modo ocupado). So conta com partner_busy_mode_enabled ligado e busy_until no futuro: ler por partner_busy_extra_minutes().';
comment on column public.restaurants.busy_until is
  'Modo ocupado: ate esta hora (o RPC partner_set_busy poe agora + 2 h). Passada a hora, o modo expira sozinho sem cron.';

alter table public.orders
  add column if not exists ready_at_promised timestamptz;

comment on column public.orders.ready_at_promised is
  'Hora a que a loja prometeu ter o pedido pronto ("fica pronto as HH:MM"), posta pelo parceiro em partner_set_ready_at. Null = sem promessa. O despacho so a usa depois de revista a proposta C6 (01_dispatch_proposta.sql).';

-- ── 3) Funcoes ──

-- Interruptor geral lido no servidor. Interna: so as outras funcoes a chamam.
create or replace function public._partner_busy_mode_on()
returns boolean
language sql
stable
security definer
set search_path to 'public'
as $fn$
  select coalesce(
    (select (value #>> '{}') = 'true'
       from public.platform_settings
      where key = 'partner_busy_mode_enabled'),
    false);
$fn$;
revoke all on function public._partner_busy_mode_on() from public, anon, authenticated;
grant execute on function public._partner_busy_mode_on() to service_role;

-- Minutos a somar a esta loja AGORA. 0 se o interruptor esta desligado, se nunca
-- houve modo ocupado, ou se a hora de fim ja passou (expira sozinho, sem cron).
create or replace function public.partner_busy_extra_minutes(p_restaurant_id text)
returns integer
language sql
stable
security definer
set search_path to 'public'
as $fn$
  select case
    when not public._partner_busy_mode_on() then 0
    else coalesce(
      (select case when r.busy_until is not null and r.busy_until > now()
                   then greatest(r.busy_extra_minutes, 0) else 0 end
         from public.restaurants r
        where r.id = p_restaurant_id),
      0)
  end;
$fn$;
revoke all on function public.partner_busy_extra_minutes(text) from public, anon;
grant execute on function public.partner_busy_extra_minutes(text) to authenticated, service_role;

-- O parceiro (dono da loja) ou um admin liga o modo ocupado com +N minutos.
-- p_extra_minutes: 0 desliga; 1..60 liga (os botoes da app sao 10, 20 e 30).
-- Carregar noutro botao TROCA o valor (nao soma) e volta a contar 2 horas.
-- Ligar com o interruptor geral desligado e recusado; desligar e sempre permitido.
create or replace function public.partner_set_busy(p_restaurant_id text, p_extra_minutes integer)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_until timestamptz;
begin
  if not public._parceiro_pode_loja(p_restaurant_id) then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  if p_extra_minutes is null or p_extra_minutes < 0 or p_extra_minutes > 60 then
    return jsonb_build_object('ok', false, 'error', 'minutos_invalidos');
  end if;
  if p_extra_minutes > 0 and not public._partner_busy_mode_on() then
    return jsonb_build_object('ok', false, 'error', 'desligado');
  end if;

  v_until := case when p_extra_minutes = 0 then null else now() + interval '2 hours' end;

  update public.restaurants
     set busy_extra_minutes = p_extra_minutes,
         busy_until = v_until
   where id = p_restaurant_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'loja_nao_encontrada');
  end if;

  return jsonb_build_object(
    'ok', true,
    'extra_minutes', p_extra_minutes,
    'busy_until', v_until,
    'ate_as', case when v_until is null then null
                   else to_char(v_until at time zone 'Europe/Lisbon', 'HH24:MI') end);
end;
$fn$;
revoke all on function public.partner_set_busy(text, integer) from public, anon;
grant execute on function public.partner_set_busy(text, integer) to authenticated, service_role;

-- Painel admin: quem esta ocupado agora, com quantos minutos e ate quando.
create or replace function public.admin_partner_busy_list()
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_lojas jsonb;
begin
  perform public._admin_op_guard();

  select coalesce(jsonb_agg(jsonb_build_object(
           'restaurant_id', r.id,
           'nome', r.name,
           'extra_minutes', r.busy_extra_minutes,
           'busy_until', r.busy_until,
           'ate_as', to_char(r.busy_until at time zone 'Europe/Lisbon', 'HH24:MI'),
           'minutos_restantes',
             greatest(0, ceil(extract(epoch from (r.busy_until - now())) / 60.0)::integer)
         ) order by r.busy_until desc), '[]'::jsonb)
    into v_lojas
    from public.restaurants r
   where r.busy_extra_minutes > 0
     and r.busy_until is not null
     and r.busy_until > now();

  return jsonb_build_object(
    'ok', true,
    'ligado', public._partner_busy_mode_on(),
    'lojas', v_lojas);
end;
$fn$;
revoke all on function public.admin_partner_busy_list() from public, anon;
grant execute on function public.admin_partner_busy_list() to authenticated, service_role;

-- Painel admin: desligar o modo ocupado de uma loja (fica no historico de acoes).
create or replace function public.admin_partner_busy_desligar(p_restaurant_id text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  v_antes integer;
begin
  perform public._admin_op_guard();

  select busy_extra_minutes into v_antes from public.restaurants where id = p_restaurant_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'loja_nao_encontrada');
  end if;

  update public.restaurants
     set busy_extra_minutes = 0, busy_until = null
   where id = p_restaurant_id;

  perform public.log_admin_action(
    'partner_busy_desligado', 'restaurant', p_restaurant_id,
    jsonb_build_object('extra_minutes_antes', v_antes));

  return jsonb_build_object('ok', true);
end;
$fn$;
revoke all on function public.admin_partner_busy_desligar(text) from public, anon;
grant execute on function public.admin_partner_busy_desligar(text) to authenticated, service_role;

-- "Fica pronto as HH:MM": o parceiro promete a hora num pedido de entrega JA ACEITE
-- (ainda em preparacao, estafeta ainda nao chamado). p_ready_at null apaga a promessa.
-- So grava a hora: nao muda o estado do pedido nem chama ninguem. A chamada do
-- estafeta so passa a usar esta hora depois da proposta C6 estar revista e aplicada.
create or replace function public.partner_set_ready_at(p_order_id text, p_ready_at timestamptz)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $fn$
declare
  o record;
begin
  select id, restaurant_id, status::text as status, service_type::text as service_type,
         coalesce(is_partner_store, false) as is_partner_store
    into o
    from public.orders
   where id = p_order_id;
  if not found then
    return jsonb_build_object('ok', false, 'error', 'pedido_nao_encontrado');
  end if;
  if o.restaurant_id is null or not public._parceiro_pode_loja(o.restaurant_id) then
    return jsonb_build_object('ok', false, 'error', 'forbidden');
  end if;
  if o.service_type <> 'restaurant' or not o.is_partner_store then
    return jsonb_build_object('ok', false, 'error', 'so_entregas_de_parceiro');
  end if;
  if o.status <> 'preparing' then
    return jsonb_build_object('ok', false, 'error', 'pedido_nao_esta_em_preparacao');
  end if;
  if p_ready_at is not null
     and (p_ready_at < now() - interval '1 minute' or p_ready_at > now() + interval '4 hours') then
    return jsonb_build_object('ok', false, 'error', 'hora_invalida');
  end if;

  update public.orders
     set ready_at_promised = p_ready_at
   where id = p_order_id and status::text = 'preparing';

  return jsonb_build_object(
    'ok', true,
    'ready_at_promised', p_ready_at,
    'pronto_as', case when p_ready_at is null then null
                      else to_char(p_ready_at at time zone 'Europe/Lisbon', 'HH24:MI') end);
end;
$fn$;
revoke all on function public.partner_set_ready_at(text, timestamptz) from public, anon;
grant execute on function public.partner_set_ready_at(text, timestamptz) to authenticated, service_role;
