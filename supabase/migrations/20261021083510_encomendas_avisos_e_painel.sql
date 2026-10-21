-- 2026-10-21 · super-missão fechar-pendencias-2026-10-20 · BLOCO A1 (3/3)
-- Só PALAVRAS e LEITURA — nenhum valor, nenhum despacho:
--   1. aviso ao cliente nas mudanças de estado: numa encomenda o texto fala da
--      encomenda e do estafeta (a notify-tvde-client aceita titulo/corpo próprios
--      desde 25/09 — v7 no ar, lida a 21/10 — sem republicar a Edge). Passageiros:
--      o corpo enviado é EXACTAMENTE o de antes;
--   2. painel: as listas de corridas e de reservas passam a trazer ride_kind
--      (troca por âncora, aditiva: só acrescenta a chave);
--   3. painel: acerto da semana do Bora Motorista partido por tipo — leitura,
--      com a MESMA regra do compute_driver_settlement (finalizadas na semana,
--      driver_earn_cents, cash_in_hand_cents, + compensações de cancelamento).

create or replace function pg_temp._a1_troca(p_txt text, p_de text, p_para text, p_vezes int, p_onde text)
returns text language plpgsql as $f$
declare v_n int;
begin
  v_n := (length(p_txt) - length(replace(p_txt, p_de, ''))) / greatest(length(p_de), 1);
  if v_n <> p_vezes then
    raise exception 'A1 âncora % apareceu % vez(es), esperava % — nada foi mudado', p_onde, v_n, p_vezes;
  end if;
  return replace(p_txt, p_de, p_para);
end $f$;

-- 1. Aviso ao cliente -------------------------------------------------------------
do $a$
begin
  if (select md5(prosrc) from pg_proc where oid = 'public.fn_notify_tvde_client_on_status()'::regprocedure)
     <> 'f24ad29fa94b5dcd6b83288e2b18f5a8' then
    raise exception 'A1 fn_notify_tvde_client_on_status mudou no ar desde 21/10 — nada foi mudado';
  end if;
end $a$;

create or replace function public.fn_notify_tvde_client_on_status()
 returns trigger
 language plpgsql
 security definer
 set search_path to 'public', 'net', 'extensions'
as $function$
DECLARE v_jwt text; v_body jsonb; v_nome text; v_titulo text; v_corpo text;
BEGIN
  IF OLD.status IS NOT DISTINCT FROM NEW.status THEN RETURN NEW; END IF;
  IF NEW.status NOT IN (
       'motorista_atribuido','motorista_a_caminho','motorista_chegou',
       'em_andamento','finalizada','sem_motorista','cancelada_motorista'
     ) THEN
    RETURN NEW;
  END IF;

  v_body := jsonb_build_object('rideId', NEW.id::text, 'status', NEW.status);

  -- 21/10/2026 (fechar-pendencias A1): numa ENCOMENDA o texto fala da encomenda.
  IF NEW.ride_kind = 'encomendas' THEN
    IF NEW.driver_id IS NOT NULL THEN
      SELECT nullif(trim(d.name), '') INTO v_nome
        FROM public.drivers d WHERE d.user_id = NEW.driver_id;
    END IF;
    v_nome := coalesce(v_nome, 'O teu estafeta');
    CASE NEW.status
      WHEN 'motorista_atribuido', 'motorista_a_caminho' THEN
        v_titulo := '📦 Estafeta a caminho da recolha';
        v_corpo  := v_nome || ' vem buscar a tua encomenda.';
      WHEN 'motorista_chegou' THEN
        v_titulo := '📍 O estafeta chegou à recolha';
        v_corpo  := v_nome || ' está no local de recolha.';
      WHEN 'em_andamento' THEN
        v_titulo := '📦 Encomenda recolhida';
        v_corpo  := 'A tua encomenda vai a caminho da entrega. O preço é o que viste ao pedir.';
      WHEN 'finalizada' THEN
        v_titulo := '✅ Encomenda entregue';
        v_corpo  := 'A entrega foi concluída. Avalia a entrega na app.';
      WHEN 'sem_motorista' THEN
        v_titulo := '😕 Sem estafetas disponíveis';
        v_corpo  := 'Não encontrámos estafeta a tempo e o pedido foi cancelado. Se pagaste na app, o valor é devolvido. Podes tentar de novo.';
      WHEN 'cancelada_motorista' THEN
        v_titulo := 'Entrega cancelada';
        v_corpo  := 'O estafeta cancelou a entrega. Pedimos desculpa — tenta de novo.';
      ELSE
        v_titulo := NULL;
    END CASE;
    IF v_titulo IS NOT NULL THEN
      v_body := v_body || jsonb_build_object('titulo', v_titulo, 'corpo', v_corpo);
    END IF;
  END IF;

  v_jwt := public._dispatch_jwt();
  PERFORM net.http_post(
    url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/notify-tvde-client',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_jwt),
    body    := v_body
  );
  RETURN NEW;
END; $function$;
revoke all on function public.fn_notify_tvde_client_on_status() from public, anon;
grant execute on function public.fn_notify_tvde_client_on_status() to authenticated, service_role;

-- 2. Painel: listas com o tipo ------------------------------------------------------
do $p$
declare v_def text; v_n int;
begin
  -- admin_tvde_rides_list_v2
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_tvde_rides_list_v2(text, integer)'::regprocedure)
     <> '45dfd895cec8f6fb3676d2ac9f980aac' then
    raise exception 'A1 admin_tvde_rides_list_v2 mudou no ar — nada foi mudado';
  end if;
  v_def := pg_get_functiondef('public.admin_tvde_rides_list_v2(text, integer)'::regprocedure);
  v_def := pg_temp._a1_troca(v_def,
    E'      SELECT r.id, r.created_at, r.status, r.payment_method, r.payment_status,',
    E'      SELECT r.id, r.created_at, r.status, r.ride_kind, r.payment_method, r.payment_status,', 1, 'v2:sem_reembolso');
  v_def := pg_temp._a1_troca(v_def,
    E'           linha || jsonb_build_object(\n             ''payment_status'', r.payment_status,',
    E'           linha || jsonb_build_object(''ride_kind'', r.ride_kind) || jsonb_build_object(\n             ''payment_status'', r.payment_status,', 1, 'v2:linha');
  execute v_def;

  -- admin_tvde_reservations_list
  if (select md5(prosrc) from pg_proc where oid = 'public.admin_tvde_reservations_list(text, integer)'::regprocedure)
     <> 'cf65cf9e0524254156aabd76cc3f5e72' then
    raise exception 'A1 admin_tvde_reservations_list mudou no ar — nada foi mudado';
  end if;
  v_def := pg_get_functiondef('public.admin_tvde_reservations_list(text, integer)'::regprocedure);
  v_def := pg_temp._a1_troca(v_def,
    E'    SELECT jsonb_build_object(\n      ''id'', r.id,',
    E'    SELECT jsonb_build_object(''ride_kind'', r.ride_kind) || jsonb_build_object(\n      ''id'', r.id,', 1, 'reservas:linha');
  execute v_def;
end $p$;

-- 3. Painel: acerto do Bora Motorista partido por tipo (só leitura) -------------------
create or replace function public.admin_tvde_acertos_por_tipo(p_week_start timestamptz default null)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
declare v_admin record; v_b record; v_out jsonb;
begin
  select admin_id into v_admin from public._admin_op_guard();
  select * into v_b from public.driver_settlement_week_bounds(coalesce(p_week_start, now()));

  with corridas as (
    select r.driver_id, r.ride_kind,
           count(*)                                              as corridas,
           coalesce(sum(coalesce(r.driver_earn_cents, 0)), 0)    as ganho_cents,
           coalesce(sum(coalesce(r.cash_in_hand_cents, 0)), 0)   as dinheiro_em_mao_cents,
           coalesce(sum(case when r.payment_method in ('card','mbway')
                             then coalesce(r.final_fare_cents, r.est_fare_cents, 0) else 0 end), 0) as online_cents
      from public.tvde_rides r
     where r.status = 'finalizada'
       and r.driver_id is not null
       and r.created_at >= v_b.week_start and r.created_at <= v_b.week_end
     group by 1, 2
  ), comps as (
    select c.driver_id, coalesce(r.ride_kind, 'passageiros') as ride_kind,
           coalesce(sum(c.driver_cents), 0) as compensacao_cents
      from public.tvde_cancel_compensations c
      left join public.tvde_rides r on r.id = c.ride_id
     where c.created_at >= v_b.week_start and c.created_at <= v_b.week_end
     group by 1, 2
  ), juntos as (
    select coalesce(a.driver_id, b.driver_id) as driver_id,
           coalesce(a.ride_kind, b.ride_kind) as ride_kind,
           coalesce(a.corridas, 0) as corridas,
           coalesce(a.ganho_cents, 0) + coalesce(b.compensacao_cents, 0) as ganho_cents,
           coalesce(a.dinheiro_em_mao_cents, 0) as dinheiro_em_mao_cents,
           coalesce(a.online_cents, 0) as online_cents,
           coalesce(b.compensacao_cents, 0) as compensacao_cents
      from corridas a
      full join comps b on b.driver_id = a.driver_id and b.ride_kind = a.ride_kind
  )
  select jsonb_build_object(
           'week_start', v_b.week_start,
           'week_end',   v_b.week_end,
           'linhas', coalesce(jsonb_agg(jsonb_build_object(
               'driver_id', j.driver_id,
               'driver_name', coalesce((select nullif(trim(d.name), '') from public.drivers d
                                         where d.user_id = j.driver_id limit 1), '(sem nome)'),
               'ride_kind', j.ride_kind,
               'corridas', j.corridas,
               'ganho_cents', j.ganho_cents,
               'compensacao_cents', j.compensacao_cents,
               'dinheiro_em_mao_cents', j.dinheiro_em_mao_cents,
               'online_cents', j.online_cents)
             order by j.ride_kind, j.ganho_cents desc), '[]'::jsonb))
    into v_out
    from juntos j;
  return v_out;
end $$;
revoke all on function public.admin_tvde_acertos_por_tipo(timestamptz) from public, anon;
grant execute on function public.admin_tvde_acertos_por_tipo(timestamptz) to authenticated, service_role;
comment on function public.admin_tvde_acertos_por_tipo(timestamptz) is
  'Painel (só leitura): o acerto semanal do Bora Motorista partido por tipo (passageiros/encomendas). Mesma regra do compute_driver_settlement para a parte TVDE. 21/10/2026 (A1).';
