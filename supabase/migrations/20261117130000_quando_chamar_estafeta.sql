-- ════════════════════════════════════════════════════════════════════════════
-- "QUANDO CHAMAMOS O ESTAFETA?" — lojas que não são de comida (17/11/2026)
-- Missão a3-parte2-quando-chamar-17-11 (caixa_guardados 115), pedido do Danilo 17/11 05:06,
-- ordem trazida pela Claude.ai ("autorizo e publica", 17/11 04:51). A mudança no despacho
-- (zona protegida) é a ordem explícita do item 2.2 dessa missão: "o despacho só chama o
-- estafeta perto dessa hora (mesma antecedência de hoje)".
-- Todos os corpos de função abaixo partem do pg_get_functiondef VIVO de 17/11 (não do repo).
-- ════════════════════════════════════════════════════════════════════════════
--
-- PORQUÊ: a A3 (papelaria) tem trabalhos rápidos e trabalhos demorados (impressões,
-- personalizados, encomendas). Hoje a loja só escolhe 10 a 60 min ao aceitar e o servidor
-- recusa mais de 120 min. Nas lojas que não são de comida (categoria principal store,
-- festas, pharmacy, supermarket, beauty) a loja passa a poder dizer "fica pronto daqui a
-- 3 h / amanhã / 2 dias / sexta às 15:00" (até 14 dias de calendário).
--
-- O QUE MUDA (só nessas lojas; restaurantes de comida ficam exatamente como estão):
--   A. _loja_nao_comida(restaurant_id) — a regra das lojas, numa função só.
--   B. _texto_dia_hora_lisboa(instante) — "hoje às 15:00" / "amanhã às 15:00" /
--      "sexta, 21/11, às 15:00" (hora de Lisboa), para os avisos ao cliente.
--   C. partner_aceitar_pedido(p_order_id, p_prep_minutes, p_pronto_em default null):
--      com p_pronto_em grava orders.ready_at_promised (até 15 dias, para o último dia do
--      calendário de 14 dias nunca ser recusado pela hora). Sem p_pronto_em: igual a hoje
--      (5 a 120 min). A assinatura antiga (text, integer) sai para não haver duas funções
--      com o mesmo nome a confundir o PostgREST; quem chamava com 2 argumentos continua a
--      funcionar (o 3.º tem valor por defeito): app e farmacia_chegada_marcar.
--   D. partner_set_ready_at: nessas lojas aceita até 15 dias (restaurantes: 4 h, como hoje),
--      não deixa apagar a hora (sem hora o despacho chamava logo) e avisa o cliente da hora nova.
--   E. partner_auto_dispatch_ready_orders (ZONA PROTEGIDA, ordem explícita na missão 2.2):
--      um ramo novo, PRIMEIRO no CASE, só para essas lojas: com ready_at_promised (e sem data
--      marcada pelo cliente ou com a promessa mais tarde que ela) chama em
--      ready_at_promised − dispatch_antecedencia_minutos (8, a mesma antecedência de hoje).
--      Restaurantes: a conta de hoje, sem tocar. Farmácia com "chega às" (scheduled_for =
--      ready_at_promised): igual a hoje (scheduled_for − 30).
--   F. Aviso ao cliente quando o estafeta é chamado nesses pedidos (gatilho novo, só avisa).
--   G. _cron_check_orphan_orders: não dá "pedido órfão" a pedido com hora prometida lá à frente.
--   H. mover_pedidos_demo: pedido de TESTE em loja escondida com hora prometida só se fecha
--      6 h depois da hora prometida (antes fechava 6 h depois de criado, e o teste "2 dias"
--      da A3 morria a meio). Pedidos reais: nada muda.
--
-- NADA DE DINHEIRO: não mexe em preços, comissões, ganhos, pagamentos nem cobranças (o que
-- se viu dos pagamentos está no relatório da missão, e2e_log passo b2-5-cancelamentos).
--
-- BACKUP: as 5 funções mexidas ficam em bkp_fn_<nome>_20261117 (definição completa).
-- COMO DESFAZER (por esta ordem):
--   drop trigger if exists trg_zz_pedido_loja_avisar_chamada on public.orders;
--   drop function if exists public.partner_aceitar_pedido(text, integer, timestamptz);
--   do $$ declare r record; begin
--     for r in select definicao from public.bkp_fn_partner_aceitar_pedido_20261117
--      union all select definicao from public.bkp_fn_partner_set_ready_at_20261117
--      union all select definicao from public.bkp_fn_partner_auto_dispatch_ready_orders_20261117
--      union all select definicao from public.bkp_fn__cron_check_orphan_orders_20261117
--      union all select definicao from public.bkp_fn_mover_pedidos_demo_20261117
--     loop execute r.definicao; end loop; end $$;
--   revoke all on function public.partner_aceitar_pedido(text, integer) from public, anon;
--   grant execute on function public.partner_aceitar_pedido(text, integer) to authenticated, service_role;
--   (o interruptor parceiro_quando_chamar_ligado pode ficar ou sair da platform_settings;
--    as funções novas _loja_nao_comida, _texto_dia_hora_lisboa, _pedido_avisar_cliente e
--    _pedido_loja_avisar_chamada podem ficar: sem uso não fazem nada.)
--
-- PROVA: supabase/tests/quando_chamar_estafeta_test.sql (transação desfeita, corre com esta
-- migração dentro da mesma transação; acaba em "RESULT {...}" com todos os casos ok).
-- ════════════════════════════════════════════════════════════════════════════

-- ── 0) BACKUP das 5 funções ──────────────────────────────────────────────────
create table if not exists public.bkp_fn_partner_aceitar_pedido_20261117 as
  select now() as guardado_em, 'partner_aceitar_pedido(text,integer)'::text as funcao,
         pg_get_functiondef('public.partner_aceitar_pedido(text,integer)'::regprocedure) as definicao;
create table if not exists public.bkp_fn_partner_set_ready_at_20261117 as
  select now() as guardado_em, 'partner_set_ready_at(text,timestamptz)'::text as funcao,
         pg_get_functiondef('public.partner_set_ready_at(text,timestamptz)'::regprocedure) as definicao;
create table if not exists public.bkp_fn_partner_auto_dispatch_ready_orders_20261117 as
  select now() as guardado_em, 'partner_auto_dispatch_ready_orders()'::text as funcao,
         pg_get_functiondef('public.partner_auto_dispatch_ready_orders()'::regprocedure) as definicao;
create table if not exists public.bkp_fn__cron_check_orphan_orders_20261117 as
  select now() as guardado_em, '_cron_check_orphan_orders()'::text as funcao,
         pg_get_functiondef('public._cron_check_orphan_orders()'::regprocedure) as definicao;
create table if not exists public.bkp_fn_mover_pedidos_demo_20261117 as
  select now() as guardado_em, 'mover_pedidos_demo()'::text as funcao,
         pg_get_functiondef('public.mover_pedidos_demo()'::regprocedure) as definicao;
alter table public.bkp_fn_partner_aceitar_pedido_20261117 enable row level security;
alter table public.bkp_fn_partner_set_ready_at_20261117 enable row level security;
alter table public.bkp_fn_partner_auto_dispatch_ready_orders_20261117 enable row level security;
alter table public.bkp_fn__cron_check_orphan_orders_20261117 enable row level security;
alter table public.bkp_fn_mover_pedidos_demo_20261117 enable row level security;
revoke all on table public.bkp_fn_partner_aceitar_pedido_20261117,
                    public.bkp_fn_partner_set_ready_at_20261117,
                    public.bkp_fn_partner_auto_dispatch_ready_orders_20261117,
                    public.bkp_fn__cron_check_orphan_orders_20261117,
                    public.bkp_fn_mover_pedidos_demo_20261117
  from public, anon, authenticated;

-- ── Interruptor do painel admin (paridade): nasce LIGADO, pedido do Danilo ──
-- Desligado: a app volta aos minutos dos restaurantes e o servidor recusa p_pronto_em.
-- NÃO trava o despacho: os pedidos já marcados continuam a ser chamados à hora certa
-- (se o despacho o seguisse, desligar chamava todos os pedidos marcados de uma vez).
insert into public.platform_settings (key, value, description, category, is_secret)
values (
  'parceiro_quando_chamar_ligado',
  'true'::jsonb,
  'Lojas que não são de comida (loja, festas, farmácia, supermercado, beleza): ao aceitar um pedido, a loja escolhe quando fica pronto, de 10 minutos até 14 dias (amanhã, 2 dias, dia e hora), e o entregador é chamado 8 minutos antes. Desligado: essas lojas voltam aos 10 a 60 minutos dos restaurantes (os pedidos já marcados continuam à hora marcada). Não mexe em nenhum valor cobrado ou pago.',
  'partners',
  false
)
on conflict (key) do nothing;

-- ── A) Que lojas podem marcar dias (categoria PRINCIPAL; a da app é a mesma) ──
create or replace function public._loja_nao_comida(p_restaurant_id text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $fn$
  select coalesce(
    (select r.category in ('store', 'festas', 'pharmacy', 'supermarket', 'beauty')
       from public.restaurants r
      where r.id = p_restaurant_id),
    false);
$fn$;
comment on function public._loja_nao_comida(text) is
  'Lojas que nao sao de comida (categoria principal store/festas/pharmacy/supermarket/beauty): podem prometer o pedido pronto ate 14 dias (missao a3-parte2-quando-chamar-17-11). Igual a lojaNaoComida() da app.';
revoke all on function public._loja_nao_comida(text) from public, anon, authenticated;
grant execute on function public._loja_nao_comida(text) to service_role;

-- ── B) "hoje às 15:00" / "amanhã às 15:00" / "sexta, 21/11, às 15:00" ───────
create or replace function public._texto_dia_hora_lisboa(p_instante timestamptz)
returns text
language sql
stable
set search_path to ''
as $fn$
  select case
    when (p_instante at time zone 'Europe/Lisbon')::date = (now() at time zone 'Europe/Lisbon')::date
      then 'hoje às ' || to_char(p_instante at time zone 'Europe/Lisbon', 'HH24:MI')
    when (p_instante at time zone 'Europe/Lisbon')::date = (now() at time zone 'Europe/Lisbon')::date + 1
      then 'amanhã às ' || to_char(p_instante at time zone 'Europe/Lisbon', 'HH24:MI')
    else (array['segunda', 'terça', 'quarta', 'quinta', 'sexta', 'sábado', 'domingo'])
           [extract(isodow from p_instante at time zone 'Europe/Lisbon')::int]
         || ', ' || to_char(p_instante at time zone 'Europe/Lisbon', 'DD/MM')
         || ', às ' || to_char(p_instante at time zone 'Europe/Lisbon', 'HH24:MI')
  end;
$fn$;
revoke all on function public._texto_dia_hora_lisboa(timestamptz) from public, anon, authenticated;
grant execute on function public._texto_dia_hora_lisboa(timestamptz) to service_role;

-- ── Aviso ao cliente de um pedido (sininho + push), como _favor_avisar_cliente ─
create or replace function public._pedido_avisar_cliente(
  p_order_id text, p_tipo text, p_titulo text, p_corpo text)
returns void
language plpgsql
security definer
set search_path to 'public', 'net'
as $fn$
declare
  v_user uuid;
  v_url  text;
  v_key  text;
begin
  select user_id into v_user from public.orders where id = p_order_id;
  if v_user is null then return; end if;
  begin
    if public.is_demo_user(v_user) then return; end if;
  exception when others then null;
  end;
  begin
    perform public._push_in_app_notification(v_user, p_tipo, p_titulo, p_corpo, p_order_id);
  exception when others then
    raise notice '_pedido_avisar_cliente sininho: %', sqlerrm;
  end;
  begin
    v_key := nullif(public._service_role_key(), '');
    v_url := (select decrypted_secret from vault.decrypted_secrets where name = 'project_url' limit 1);
    if v_url is not null and v_key is not null then
      perform net.http_post(
        url     := v_url || '/functions/v1/notify-client',
        headers := jsonb_build_object('Authorization', 'Bearer ' || v_key,
                                      'Content-Type', 'application/json'),
        body    := jsonb_build_object('clientId', v_user, 'orderId', p_order_id,
                                      'type', p_tipo, 'title', p_titulo, 'body', p_corpo));
    end if;
  exception when others then
    raise notice '_pedido_avisar_cliente notify-client: %', sqlerrm;
  end;
end;
$fn$;
revoke all on function public._pedido_avisar_cliente(text, text, text, text) from public, anon, authenticated;
grant execute on function public._pedido_avisar_cliente(text, text, text, text) to service_role;

-- ── C) Aceitar com "fica pronto em" (minutos, como hoje) OU "pronto em" (instante) ─
drop function if exists public.partner_aceitar_pedido(text, integer);
create function public.partner_aceitar_pedido(
  p_order_id text,
  p_prep_minutes integer,
  p_pronto_em timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
DECLARE
  v_res  jsonb;
  v_rest text;
BEGIN
  IF auth.uid() IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'auth_required');
  END IF;

  -- 17/11/2026: lojas que não são de comida podem marcar um instante (até 14 dias).
  IF p_pronto_em IS NOT NULL THEN
    IF COALESCE((SELECT s.value #>> '{}' FROM public.platform_settings s
                  WHERE s.key = 'parceiro_quando_chamar_ligado'), 'true') = 'false' THEN
      RETURN jsonb_build_object('ok', false, 'error', 'funcao_desligada');
    END IF;
    SELECT restaurant_id INTO v_rest FROM public.orders WHERE id = p_order_id;
    IF v_rest IS NULL OR NOT public._loja_nao_comida(v_rest) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'so_lojas_nao_comida');
    END IF;
    IF p_pronto_em < now() - interval '1 minute' OR p_pronto_em > now() + interval '15 days' THEN
      RETURN jsonb_build_object('ok', false, 'error', 'invalid_pronto_em');
    END IF;
    v_res := public.partner_accept_order(p_order_id);
    -- Um segundo toque em "Aceitar" (pedido já aceite) NÃO apaga a hora já marcada:
    -- para mudar a hora há o "Mudar quando fica pronto" (que avisa o cliente).
    IF COALESCE((v_res->>'ok')::boolean, false) AND v_res->>'idempotent' IS NULL THEN
      UPDATE public.orders
         SET ready_at_promised = p_pronto_em,
             prep_time_minutes = NULL
       WHERE id = p_order_id AND status = 'preparing';
      v_res := v_res || jsonb_build_object(
        'ready_at_promised', p_pronto_em,
        'pronto_texto', public._texto_dia_hora_lisboa(p_pronto_em));
    END IF;
    RETURN v_res;
  END IF;

  -- Igual a 20261004213500 (restaurantes e minutos curtos).
  IF p_prep_minutes IS NOT NULL AND (p_prep_minutes < 5 OR p_prep_minutes > 120) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'invalid_prep_minutes');
  END IF;
  v_res := public.partner_accept_order(p_order_id);
  IF COALESCE((v_res->>'ok')::boolean, false) AND p_prep_minutes IS NOT NULL THEN
    UPDATE public.orders SET prep_time_minutes = p_prep_minutes
     WHERE id = p_order_id AND status = 'preparing';
    v_res := v_res || jsonb_build_object('prep_time_minutes', p_prep_minutes);
  END IF;
  RETURN v_res;
END;
$function$;
revoke all on function public.partner_aceitar_pedido(text, integer, timestamptz) from public, anon;
grant execute on function public.partner_aceitar_pedido(text, integer, timestamptz) to authenticated, service_role;

-- ── D) Mudar a hora prometida depois de aceitar ─────────────────────────────
create or replace function public.partner_set_ready_at(p_order_id text, p_ready_at timestamp with time zone)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $function$
declare
  o         record;
  v_longo   boolean;
  v_limite  interval;
  v_texto   text;
begin
  select id, restaurant_id, status::text as status, service_type::text as service_type,
         coalesce(is_partner_store, false) as is_partner_store, ready_at_promised
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

  -- 17/11/2026: lojas que não são de comida marcam até 14 dias e não ficam sem hora
  -- (sem hora nem tempo de preparação o despacho chamava o estafeta logo).
  v_longo := public._loja_nao_comida(o.restaurant_id);
  v_limite := case when v_longo then interval '15 days' else interval '4 hours' end;
  if v_longo and p_ready_at is null then
    return jsonb_build_object('ok', false, 'error', 'hora_obrigatoria');
  end if;
  if p_ready_at is not null
     and (p_ready_at < now() - interval '1 minute' or p_ready_at > now() + v_limite) then
    return jsonb_build_object('ok', false, 'error', 'hora_invalida');
  end if;

  update public.orders
     set ready_at_promised = p_ready_at
   where id = p_order_id and status::text = 'preparing';

  -- Aviso ao cliente da hora nova (só nas lojas que não são de comida; restaurantes como hoje).
  if v_longo and p_ready_at is distinct from o.ready_at_promised then
    v_texto := public._texto_dia_hora_lisboa(p_ready_at);
    perform public._pedido_avisar_cliente(p_order_id, 'pedido_hora_mudou',
      'Nova hora para o seu pedido',
      'A loja mudou a hora: fica pronto ' || v_texto || '.');
  end if;

  return jsonb_build_object(
    'ok', true,
    'ready_at_promised', p_ready_at,
    'pronto_as', case when p_ready_at is null then null
                      else to_char(p_ready_at at time zone 'Europe/Lisbon', 'HH24:MI') end,
    'pronto_texto', case when p_ready_at is null then null
                         else public._texto_dia_hora_lisboa(p_ready_at) end);
end;
$function$;

-- ── E) O despacho: um ramo novo, só para as lojas que não são de comida ─────
-- Corpo VIVO de 17/11 (pg_get_functiondef) + o ramo marcado "17/11". Nada mais muda.
CREATE OR REPLACE FUNCTION public.partner_auto_dispatch_ready_orders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
DECLARE
  v_min     integer;
  v_ant     integer;
  v_ant_ag  integer;
  v_order   record;
BEGIN
  SELECT (value::text)::integer INTO v_min
    FROM public.platform_settings
   WHERE key = 'partner_auto_dispatch_after_minutes';
  v_min := COALESCE(v_min, 5);
  IF v_min <= 0 THEN RETURN; END IF;

  SELECT (value::text)::integer INTO v_ant
    FROM public.platform_settings WHERE key = 'dispatch_antecedencia_minutos';
  v_ant := GREATEST(COALESCE(v_ant, 8), 0);
  SELECT (value::text)::integer INTO v_ant_ag
    FROM public.platform_settings WHERE key = 'dispatch_antecedencia_agendado_minutos';
  v_ant_ag := GREATEST(COALESCE(v_ant_ag, 30), 0);

  FOR v_order IN
    SELECT id
      FROM public.orders
     WHERE status = 'preparing'
       AND COALESCE(is_partner_store, false)
       AND service_type = 'restaurant'
       AND assigned_driver_id IS NULL
       AND driver_id IS NULL
       AND (COALESCE(payment_method, 'cash') = 'cash' OR payment_status = 'paid')
       AND now() >= CASE
             -- 17/11: loja que não é de comida prometeu "pronto em" (até 14 dias):
             -- chama com a antecedência de sempre (8 min). Restaurantes não entram aqui.
             WHEN ready_at_promised IS NOT NULL
                  AND (scheduled_for IS NULL OR ready_at_promised > scheduled_for)
                  AND public._loja_nao_comida(restaurant_id)
               THEN ready_at_promised - make_interval(mins => v_ant)
             WHEN scheduled_for IS NOT NULL
               THEN scheduled_for - make_interval(mins => v_ant_ag)
             WHEN prep_time_minutes IS NOT NULL
               THEN COALESCE(accepted_at, status_updated_at)
                    + make_interval(mins => GREATEST(0, prep_time_minutes - v_ant))
             ELSE COALESCE(accepted_at, status_updated_at) + make_interval(mins => v_min)
           END
     ORDER BY COALESCE(accepted_at, status_updated_at)
     LIMIT 50
     FOR UPDATE SKIP LOCKED
  LOOP
    BEGIN
      PERFORM set_config('app.order_transition_source',
                         'partner_auto_dispatch_ready_orders', true);
      UPDATE public.orders SET status = 'callingDriver'
       WHERE id = v_order.id AND status = 'preparing';
    EXCEPTION WHEN OTHERS THEN
      INSERT INTO public.order_lifecycle_errors(
        order_id, component, error_message
      ) VALUES (
        v_order.id, 'partner_auto_dispatch_ready_orders', SQLERRM
      );
    END;
  END LOOP;
END;
$function$;

-- ── F) Aviso ao cliente: "já estamos a chamar o estafeta" ───────────────────
create or replace function public._pedido_loja_avisar_chamada()
returns trigger
language plpgsql
security definer
set search_path to 'public'
as $fn$
begin
  begin
    -- Só quando foi a hora prometida pela loja a mandar chamar (a mesma condição do
    -- ramo novo do despacho): a farmácia com "chega às" (scheduled_for = ready_at_promised)
    -- não recebe este aviso.
    if new.ready_at_promised is not null
       and (new.scheduled_for is null or new.ready_at_promised > new.scheduled_for)
       and coalesce(new.is_partner_store, false)
       and new.service_type = 'restaurant'
       and public._loja_nao_comida(new.restaurant_id) then
      perform public._pedido_avisar_cliente(new.id, 'pedido_estafeta_chamado',
        'Estamos a chamar o estafeta 🛵',
        'O seu pedido de ' || coalesce(nullif(new.vendor_name, ''), 'a loja')
          || ' está quase pronto. Já estamos a chamar o estafeta.');
    end if;
  exception when others then
    raise notice '_pedido_loja_avisar_chamada: %', sqlerrm;
  end;
  return null;
end;
$fn$;
revoke all on function public._pedido_loja_avisar_chamada() from public, anon, authenticated;

drop trigger if exists trg_zz_pedido_loja_avisar_chamada on public.orders;
create trigger trg_zz_pedido_loja_avisar_chamada
  after update of status on public.orders
  for each row
  when (old.status = 'preparing' and new.status = 'callingDriver')
  execute function public._pedido_loja_avisar_chamada();

-- ── G) "Pedido órfão" não conta pedidos com hora prometida lá à frente ──────
CREATE OR REPLACE FUNCTION public._cron_check_orphan_orders()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT o.id, o.created_at, o.status, o.price
    FROM public.orders o
    WHERE o.status IN ('callingDriver', 'created', 'preparing')
      AND o.driver_id IS NULL
      AND o.created_at < now() - interval '10 minutes'
      AND o.created_at > now() - interval '2 hours'  -- evita re-alertar pedidos antigos
      AND (o.scheduled_for IS NULL OR o.scheduled_for <= now() + interval '30 minutes')  -- 30/10: agendados so na hora
      -- 17/11: a loja prometeu o pedido pronto mais tarde: nao e orfao ate perto dessa hora.
      AND (o.ready_at_promised IS NULL OR o.ready_at_promised <= now() + interval '30 minutes')
      AND NOT EXISTS (
        SELECT 1 FROM public.admin_notifications n
        WHERE n.event_type = 'order_orphan'
          AND n.entity_id = o.id::text
          AND n.created_at > now() - interval '1 hour'  -- dedup 1h
      )
  LOOP
    PERFORM public.notify_admin_event(
      'order_orphan',
      'high',
      format('Pedido órfão há %s min: #%s (status=%s)',
        EXTRACT(EPOCH FROM (now() - r.created_at))::int / 60,
        substring(r.id::text, 1, 8),
        r.status),
      'order',
      r.id::text,
      jsonb_build_object('status', r.status, 'price', r.price, 'age_minutes',
        EXTRACT(EPOCH FROM (now() - r.created_at))::int / 60),
      '/admin/orders/' || r.id::text
    );
  END LOOP;
END;
$function$;

-- ── H) Pedido de teste com hora prometida: as 6 h contam a partir dessa hora ─
CREATE OR REPLACE FUNCTION public.mover_pedidos_demo()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare v_aceites int; v_avancados int; v_cancelados int; v_fim_janela int; v_escondidas int;
begin
  update public.orders
     set status = 'driverAccepted'
   where is_test_order
     and status in ('preparing', 'callingDriver')
     and assigned_driver_id is not null
     and created_at > now() - interval '6 hours'
     and not public._e_pedido_demo_loja(id);
  get diagnostics v_aceites = row_count;

  update public.orders
     set status = case status
                    when 'driverAccepted' then 'pickedUp'
                    when 'pickedUp'       then 'onTheWay'
                    else status end
   where is_test_order
     and status in ('driverAccepted','pickedUp')
     and created_at > now() - interval '6 hours'
     and not (service_type = 'storeShopping'
              and coalesce(is_partner_store, false) = false
              and coalesce(is_purchase_finalized, false) = false)
     and not public._e_pedido_demo_loja(id);
  get diagnostics v_avancados = row_count;

  -- 17/11: com hora prometida pela loja, as 6 h contam a partir dessa hora.
  update public.orders
     set status = 'cancelled', cancelled_at = now(),
         cancel_reason = 'Pedido de demonstracao encerrado automaticamente',
         cancel_fee = 0
   where is_test_order
     and status not in ('delivered','cancelled','rejected')
     and greatest(created_at, coalesce(ready_at_promised, created_at)) <= now() - interval '6 hours'
     and not public._e_pedido_demo_loja(id);
  get diagnostics v_cancelados = row_count;

  update public.orders
     set status = 'cancelled', cancelled_at = now(),
         cancel_reason = 'Demonstracao terminada (fim da janela): sem custo',
         cancel_fee = 0
   where is_test_order
     and status not in ('delivered','cancelled','rejected')
     and restaurant_id = public._modo_demo_def()->>'restaurant_id'
     and public._e_pedido_demo_loja(id)
     and not public._modo_demo_loja(public._modo_demo_def()->>'restaurant_id');
  get diagnostics v_fim_janela = row_count;

  -- 17/11: idem nas lojas escondidas (o teste "2 dias" da A3 já não morre às 6 h).
  update public.orders o
     set status = 'cancelled', cancelled_at = now(),
         cancel_reason = 'Demonstracao terminada: sem custo',
         cancel_fee = 0
    from public.restaurants r
   where r.id = o.restaurant_id and r.so_lista_permissao
     and o.is_test_order
     and o.status not in ('delivered','cancelled','rejected')
     and greatest(o.created_at, coalesce(o.ready_at_promised, o.created_at)) <= now() - interval '6 hours';
  get diagnostics v_escondidas = row_count;

  return 'aceites=' || v_aceites || ' avancados=' || v_avancados
         || ' cancelados=' || v_cancelados || ' fim_janela=' || v_fim_janela
         || ' escondidas=' || v_escondidas;
end;
$function$;
