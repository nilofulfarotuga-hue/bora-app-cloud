-- ============================================================================
-- Missão estafeta-web-2026-09-16 · BLOCO 5 — painel admin "Escolher estafeta"
-- (leituras para o painel; a escrita continua pelos caminhos oficiais
-- admin_reassign_order / admin_release_order_driver).
--
--  • admin_drivers_for_assignment(pedido, pesquisa) — todos os estafetas
--    aprovados: disponíveis primeiro, ordenados pela distância à loja; foto,
--    nome, telefone, ligado/desligado, último sinal, notificações, como usa
--    a Bora (última plataforma), pedidos em curso.
--  • admin_stuck_orders(minutos) — pedidos parados: callingDriver há mais de
--    N min (por defeito dispatch_preassign_release_seconds), INCLUINDO os que
--    têm estafeta atribuído; e pedidos ainda não prontos com estafeta reservado.
--  • admin_driver_presence(estafeta) — ficha: ligado, sinal, notificações,
--    plataforma, pedidos em curso.
--  • admin_driver_assignment_history(estafeta) — quem lhe passou pedidos
--    (painel ou qual agente) e o que foi libertado.
--  • driver_heartbeat_by_id: o foreground service só existe no Android — fica
--    registado android_app como plataforma.
-- ============================================================================

create or replace function public._haversine_km(lat1 double precision, lng1 double precision,
                                                lat2 double precision, lng2 double precision)
returns double precision
language sql
immutable
as $$
  select case
    when lat1 is null or lng1 is null or lat2 is null or lng2 is null then null
    else 6371.0 * 2 * asin(sqrt(
      power(sin(radians(lat2 - lat1) / 2), 2)
      + cos(radians(lat1)) * cos(radians(lat2)) * power(sin(radians(lng2 - lng1) / 2), 2)))
  end;
$$;

create or replace function public.admin_drivers_for_assignment(p_order_id text default null, p_search text default null)
returns table (
  user_id           text,
  driver_id         uuid,
  name              text,
  phone             text,
  photo_url         text,
  vehicle_type      text,
  is_online         boolean,
  online_agora      boolean,
  last_heartbeat_at timestamptz,
  tem_notificacoes  boolean,
  last_platform     text,
  pedidos_em_curso  integer,
  distancia_km      numeric
)
language plpgsql
security definer
set search_path to 'public'
as $$
DECLARE
  v_lat double precision;
  v_lng double precision;
BEGIN
  PERFORM public._admin_op_guard();

  IF p_order_id IS NOT NULL THEN
    SELECT o.pickup_lat, o.pickup_lng INTO v_lat, v_lng FROM orders o WHERE o.id = p_order_id;
  END IF;

  RETURN QUERY
  SELECT
    COALESCE(d.user_id, d.id)::text,
    d.id,
    d.name,
    d.phone,
    d.photo_url,
    d.vehicle_type,
    COALESCE(d.is_online, false),
    (COALESCE(d.is_online, false) AND d.last_heartbeat_at IS NOT NULL
       AND d.last_heartbeat_at > now() - interval '90 seconds'),
    d.last_heartbeat_at,
    (d.fcm_token IS NOT NULL
       OR EXISTS (SELECT 1 FROM driver_push_tokens t
                   WHERE t.user_id::text = COALESCE(d.user_id, d.id)::text AND t.active)),
    d.last_platform,
    (SELECT count(*)::int FROM orders o2
      WHERE o2.assigned_driver_id = COALESCE(d.user_id, d.id)::text
        AND o2.status IN ('driverAccepted', 'pickedUp', 'onTheWay')),
    CASE WHEN v_lat IS NULL THEN NULL
         ELSE round(public._haversine_km(v_lat, v_lng, d.lat, d.lng)::numeric, 1) END
  FROM drivers d
  WHERE d.approval_status = 'approved'
    AND COALESCE(d.is_banned, false) = false
    AND d.deleted_at IS NULL
    AND (p_search IS NULL OR btrim(p_search) = ''
         OR d.name ILIKE '%' || btrim(p_search) || '%'
         OR d.phone ILIKE '%' || btrim(p_search) || '%')
  ORDER BY
    (COALESCE(d.is_online, false) AND d.last_heartbeat_at > now() - interval '90 seconds') DESC,
    CASE WHEN v_lat IS NULL THEN NULL ELSE public._haversine_km(v_lat, v_lng, d.lat, d.lng) END ASC NULLS LAST,
    d.last_heartbeat_at DESC NULLS LAST,
    d.name;
END $$;
revoke all on function public.admin_drivers_for_assignment(text, text) from public;
revoke all on function public.admin_drivers_for_assignment(text, text) from anon;
grant execute on function public.admin_drivers_for_assignment(text, text) to authenticated;

create or replace function public.admin_stuck_orders(p_minutes integer default null)
returns table (
  id                      text,
  status                  text,
  vendor_name             text,
  customer_name           text,
  price                   numeric,
  service_type            text,
  is_test_order           boolean,
  status_updated_at       timestamptz,
  espera_s                integer,
  assigned_driver_id      text,
  assigned_driver_name    text,
  driver_assigned_at      timestamptz,
  preassigned_driver_id   text,
  preassigned_driver_name text,
  current_driver_offer_id text,
  offer_driver_name       text,
  driver_offer_expires_at timestamptz,
  tentativas              integer,
  motivo                  text
)
language plpgsql
security definer
set search_path to 'public'
as $$
DECLARE
  v_secs integer;
BEGIN
  PERFORM public._admin_op_guard();
  IF p_minutes IS NULL THEN
    SELECT (value #>> '{}')::int INTO v_secs FROM platform_settings WHERE key = 'dispatch_preassign_release_seconds';
    v_secs := COALESCE(v_secs, 180);
  ELSE
    v_secs := p_minutes * 60;
  END IF;

  RETURN QUERY
  SELECT
    o.id::text, o.status, o.vendor_name, o.customer_name, o.price, o.service_type,
    COALESCE(o.is_test_order, false),
    o.status_updated_at,
    EXTRACT(EPOCH FROM (now() - COALESCE(o.status_updated_at, o.dispatch_calling_since, o.created_at)))::int,
    o.assigned_driver_id,
    da.name,
    o.driver_assigned_at,
    o.preassigned_driver_id,
    dp.name,
    o.current_driver_offer_id,
    dof.name,
    o.driver_offer_expires_at,
    COALESCE(array_length(o.tried_driver_ids, 1), 0),
    CASE
      WHEN o.status = 'callingDriver' AND o.assigned_driver_id IS NOT NULL THEN 'estafeta atribuído sem aceitar'
      WHEN o.status = 'callingDriver' AND o.current_driver_offer_id IS NOT NULL THEN 'oferta em curso'
      WHEN o.status = 'callingDriver' THEN 'ninguém aceitou ainda'
      WHEN o.preassigned_driver_id IS NOT NULL THEN 'reservado, à espera de ficar pronto'
      ELSE o.status
    END
  FROM orders o
  LEFT JOIN drivers da  ON da.user_id::text  = o.assigned_driver_id      OR da.id::text  = o.assigned_driver_id
  LEFT JOIN drivers dp  ON dp.user_id::text  = o.preassigned_driver_id   OR dp.id::text  = o.preassigned_driver_id
  LEFT JOIN drivers dof ON dof.user_id::text = o.current_driver_offer_id OR dof.id::text = o.current_driver_offer_id
  WHERE (o.status = 'callingDriver'
           AND COALESCE(o.status_updated_at, o.dispatch_calling_since, o.created_at) < now() - make_interval(secs => v_secs))
     OR (o.status IN ('created', 'preparing') AND o.preassigned_driver_id IS NOT NULL)
  ORDER BY o.status_updated_at NULLS LAST;
END $$;
revoke all on function public.admin_stuck_orders(integer) from public;
revoke all on function public.admin_stuck_orders(integer) from anon;
grant execute on function public.admin_stuck_orders(integer) to authenticated;

create or replace function public.admin_driver_presence(p_driver text)
returns table (
  user_id           text,
  driver_id         uuid,
  name              text,
  is_online         boolean,
  online_agora      boolean,
  last_heartbeat_at timestamptz,
  tem_notificacoes  boolean,
  tokens_ativos     integer,
  last_platform     text,
  last_platform_at  timestamptz,
  pedidos_em_curso  integer
)
language plpgsql
security definer
set search_path to 'public'
as $$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN QUERY
  SELECT
    COALESCE(d.user_id, d.id)::text, d.id, d.name,
    COALESCE(d.is_online, false),
    (COALESCE(d.is_online, false) AND d.last_heartbeat_at IS NOT NULL
       AND d.last_heartbeat_at > now() - interval '90 seconds'),
    d.last_heartbeat_at,
    (d.fcm_token IS NOT NULL
       OR EXISTS (SELECT 1 FROM driver_push_tokens t
                   WHERE t.user_id::text = COALESCE(d.user_id, d.id)::text AND t.active)),
    ((CASE WHEN d.fcm_token IS NOT NULL THEN 1 ELSE 0 END)
       + (SELECT count(*)::int FROM driver_push_tokens t
           WHERE t.user_id::text = COALESCE(d.user_id, d.id)::text AND t.active)),
    d.last_platform, d.last_platform_at,
    (SELECT count(*)::int FROM orders o2
      WHERE o2.assigned_driver_id = COALESCE(d.user_id, d.id)::text
        AND o2.status IN ('driverAccepted', 'pickedUp', 'onTheWay'))
  FROM drivers d
  WHERE d.user_id::text = p_driver OR d.id::text = p_driver
  LIMIT 1;
END $$;
revoke all on function public.admin_driver_presence(text) from public;
revoke all on function public.admin_driver_presence(text) from anon;
grant execute on function public.admin_driver_presence(text) to authenticated;

create or replace function public.admin_driver_assignment_history(p_driver text, p_limit integer default 50)
returns table (
  created_at timestamptz,
  action     text,
  order_id   text,
  quem       text,
  details    jsonb
)
language plpgsql
security definer
set search_path to 'public'
as $$
DECLARE
  v_uid text;
  v_id  text;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT COALESCE(d.user_id, d.id)::text, d.id::text INTO v_uid, v_id
    FROM drivers d WHERE d.user_id::text = p_driver OR d.id::text = p_driver LIMIT 1;
  IF v_uid IS NULL THEN RETURN; END IF;

  RETURN QUERY
  SELECT a.created_at, a.action, a.entity_id_text, COALESCE(a.admin_email, 'sistema'), a.details
  FROM admin_audit_log a
  WHERE a.action IN ('order_reassigned', 'order_preassigned', 'order_reassigned_by_agent',
                     'order_driver_released', 'order_driver_released_by_agent', 'preassign_released')
    AND (a.details ->> 'para' IN (v_uid, v_id)
         OR a.details ->> 'de' IN (v_uid, v_id)
         OR a.details ->> 'estafeta' = (SELECT d.name FROM drivers d WHERE d.id::text = v_id))
  ORDER BY a.created_at DESC
  LIMIT GREATEST(1, LEAST(COALESCE(p_limit, 50), 500));
END $$;
revoke all on function public.admin_driver_assignment_history(text, integer) from public;
revoke all on function public.admin_driver_assignment_history(text, integer) from anon;
grant execute on function public.admin_driver_assignment_history(text, integer) to authenticated;

-- O foreground service só existe no Android: fica a plataforma registada.
create or replace function public.driver_heartbeat_by_id(p_driver_id text)
returns jsonb
language plpgsql
security definer
set search_path to 'public'
as $$
DECLARE
  v_now     timestamptz := now();
  v_updated int;
BEGIN
  IF p_driver_id IS NULL OR length(trim(p_driver_id)) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'driver_id_required');
  END IF;

  UPDATE public.drivers
     SET last_heartbeat_at = v_now,
         is_online         = true,
         last_platform     = 'android_app',
         last_platform_at  = v_now
   WHERE id = p_driver_id::uuid OR user_id = p_driver_id::uuid;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'driver_not_found');
  END IF;

  RETURN jsonb_build_object('ok', true, 'driver_id', p_driver_id, 'heartbeat_at', v_now);
END;
$$;
