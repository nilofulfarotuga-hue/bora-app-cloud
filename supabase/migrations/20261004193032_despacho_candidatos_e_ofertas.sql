-- Despacho das ENTREGAS (ronda de correção 04/10/2026, agente despacho)
-- A1  O matching ignorava GPS/heartbeat parados, aprovação e banimento
--     ("estafetas fantasma": Valdemir com GPS de há 1 dia recebia ofertas).
--     Agora quem tem GPS ou heartbeat mais velho que
--     dispatch_gps_fresh_seconds_entregas (900 s) fica FORA das ofertas, sem
--     ser posto offline (regra do Danilo: só o botão desliga).
-- #4  Uma oferta de cada vez ao mesmo estafeta (Uber/Glovo), salvo a regra de
--     agrupamento da mesma loja (outra oferta ativa da MESMA loja).
-- #5  Favores (service_type='errand') nunca se juntam a outros pedidos; raio
--     máximo de oferta (dispatch_raio_max_oferta_km).
-- #6  Os chamadores do banco (gatilhos/cron) passam a mandar a chave de
--     serviço ao dispatch-engine e ao notify-driver (que passam a exigi-la).

INSERT INTO public.platform_settings(key, value, description, category) VALUES
  ('dispatch_gps_fresh_seconds_entregas', '900'::jsonb,
   'Entregas: estafeta com GPS ou sinal (heartbeat) mais velho que isto (segundos) não recebe ofertas. Não o desliga.', 'dispatch'),
  ('dispatch_raio_max_oferta_km', '20'::jsonb,
   'Entregas: distância máxima (km) entre o estafeta e a loja/recolha para receber a oferta.', 'dispatch')
ON CONFLICT (key) DO NOTHING;

-- Chave para as chamadas do banco às Edge Functions do despacho.
CREATE OR REPLACE FUNCTION public._dispatch_service_jwt()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(nullif(public._service_role_key(), ''), public._dispatch_jwt());
$function$;
REVOKE ALL ON FUNCTION public._dispatch_service_jwt() FROM PUBLIC, anon, authenticated;

-- Candidatos elegíveis para a oferta de UMA entrega, por ordem (mesma loja
-- primeiro, depois distância). O dispatch-engine só exclui os já tentados.
CREATE OR REPLACE FUNCTION public.dispatch_candidatos_entrega(p_order_id text)
 RETURNS TABLE(driver_id uuid, user_id uuid, lat double precision, lng double precision,
               vehicle_type text, dist_km double precision, mesma_loja boolean)
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  o          record;
  v_fresh    int     := COALESCE((public.get_setting('dispatch_gps_fresh_seconds_entregas') #>> '{}')::int, 900);
  v_raio     numeric := COALESCE((public.get_setting('dispatch_raio_max_oferta_km') #>> '{}')::numeric, 20);
  v_req_car  boolean;
  v_favor    boolean;
BEGIN
  SELECT x.id, x.service_type, x.requires_car, x.pickup_lat, x.pickup_lng, x.restaurant_id
    INTO o FROM public.orders x WHERE x.id = p_order_id;
  IF NOT FOUND THEN RETURN; END IF;
  v_req_car := COALESCE(o.requires_car, false) OR o.service_type = 'carryGroceries';
  v_favor   := o.service_type = 'errand';

  RETURN QUERY
  WITH base AS (
    SELECT d.id AS d_id, d.user_id AS d_uid, d.lat AS d_lat, d.lng AS d_lng, d.vehicle_type AS d_veh,
           ARRAY[d.id::text, COALESCE(d.user_id, d.id)::text] AS chaves
      FROM public.drivers d
     WHERE d.is_online
       AND d.approval_status = 'approved'
       AND (COALESCE(d.is_banned, false) = false
            OR (d.banned_until IS NOT NULL AND d.banned_until <= now()))
       AND d.deleted_at IS NULL
       AND (d.work_mode IS NULL OR d.work_mode <> 'rides_only')
       AND d.last_heartbeat_at > now() - make_interval(secs => v_fresh)
       AND public.driver_gps_last_at(d.user_id, d.id) > now() - make_interval(secs => v_fresh)
       AND (NOT v_req_car OR d.vehicle_type IN ('car', 'carro_passageiros'))
       AND public.aceita_papel(COALESCE(d.user_id, d.id), 'delivery')
       AND NOT EXISTS (SELECT 1 FROM public.tvde_rides r
                        WHERE r.driver_id = d.user_id
                          AND r.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento'))
  ), carga AS (
    SELECT b.*,
           (SELECT count(*) FROM public.orders a
             WHERE a.assigned_driver_id = ANY(b.chaves)
               AND a.status IN ('driverAccepted','pickedUp','onTheWay')) AS ativos,
           EXISTS (SELECT 1 FROM public.orders a
             WHERE a.assigned_driver_id = ANY(b.chaves)
               AND a.status IN ('driverAccepted','pickedUp','onTheWay')
               AND a.service_type = 'errand') AS tem_favor,
           EXISTS (SELECT 1 FROM public.orders a
             WHERE a.assigned_driver_id = ANY(b.chaves)
               AND a.status IN ('driverAccepted','pickedUp','onTheWay')
               AND o.restaurant_id IS NOT NULL AND a.restaurant_id = o.restaurant_id) AS leva_mesma_loja,
           -- outra oferta viva (noutro pedido) que NÃO é da mesma loja → ocupado
           EXISTS (SELECT 1 FROM public.orders a
             WHERE a.id <> o.id
               AND a.status = 'callingDriver'
               AND a.current_driver_offer_id = ANY(b.chaves)
               AND a.driver_offer_expires_at > now()
               AND (v_favor OR a.service_type = 'errand'
                    OR o.restaurant_id IS NULL OR a.restaurant_id IS DISTINCT FROM o.restaurant_id)) AS oferta_ocupada
      FROM base b
  ), dist AS (
    SELECT c.*,
           CASE WHEN o.pickup_lat IS NULL OR o.pickup_lng IS NULL OR c.d_lat IS NULL OR c.d_lng IS NULL THEN NULL
                ELSE 6371 * 2 * asin(sqrt(
                       power(sin(radians(o.pickup_lat::double precision - c.d_lat) / 2), 2)
                     + cos(radians(c.d_lat)) * cos(radians(o.pickup_lat::double precision))
                       * power(sin(radians(o.pickup_lng::double precision - c.d_lng) / 2), 2)))
           END AS km
      FROM carga c
  )
  SELECT x.d_id, x.d_uid, x.d_lat, x.d_lng, x.d_veh, x.km, x.leva_mesma_loja
    FROM dist x
   WHERE NOT x.oferta_ocupada
     AND x.ativos < 3
     AND NOT x.tem_favor
     AND (NOT v_favor OR x.ativos = 0)
     -- raio: com recolha conhecida, só quem tem posição e está dentro do raio
     AND (o.pickup_lat IS NULL OR o.pickup_lng IS NULL OR (x.km IS NOT NULL AND x.km <= v_raio))
   ORDER BY x.leva_mesma_loja DESC, x.km ASC NULLS LAST;
END;
$function$;
REVOKE ALL ON FUNCTION public.dispatch_candidatos_entrega(text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.dispatch_candidatos_entrega(text) TO service_role;

-- ── Chamadores do banco → chave de serviço ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.invoke_dispatch_engine(p_order_id text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'net', 'extensions'
AS $function$
DECLARE
  v_jwt text := public._dispatch_service_jwt();
  v_body jsonb;
BEGIN
  v_body := CASE
    WHEN p_order_id IS NULL THEN '{}'::jsonb
    ELSE jsonb_build_object('orderId', p_order_id)
  END;
  PERFORM net.http_post(
    url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/dispatch-engine',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || v_jwt
    ),
    body    := v_body
  );
END;
$function$;

CREATE OR REPLACE FUNCTION public.fn_dispatch_on_calling_driver()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
declare
  v_jwt text;
begin
  if new.status = 'callingDriver'
    and (old.status is distinct from 'callingDriver')
    and new.assigned_driver_id is null
    and (new.current_driver_offer_id is null
         or new.driver_offer_expires_at is null
         or new.driver_offer_expires_at <= now())
  then
    v_jwt := public._dispatch_service_jwt();
    perform net.http_post(
      url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/dispatch-engine',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_jwt
      ),
      body := jsonb_build_object('orderId', new.id::text)
    );
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.invoke_notify_driver(p_driver_id text, p_order_id text, p_vendor_name text DEFAULT 'Pedido'::text, p_total numeric DEFAULT 0)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'net', 'extensions'
AS $function$
DECLARE
  v_jwt text := public._dispatch_service_jwt();
BEGIN
  PERFORM net.http_post(
    url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/notify-driver',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_jwt
    ),
    body    := jsonb_build_object(
      'driverId',   p_driver_id,
      'orderId',    p_order_id,
      'vendorName', p_vendor_name,
      'total',      p_total
    )
  );
  RETURN jsonb_build_object('ok', true);
END;
$function$;

CREATE OR REPLACE FUNCTION public._notify_driver_offer_http(p_order_id text, p_driver text, p_vendor text, p_total numeric)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
begin
  perform net.http_post(
    url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/notify-driver',
    headers := jsonb_build_object(
      'Content-Type', 'application/json',
      'Authorization', 'Bearer ' || public._dispatch_service_jwt()),
    body    := jsonb_build_object(
      'driverId', p_driver, 'orderId', p_order_id,
      'vendorName', coalesce(p_vendor, 'Pedido'), 'total', coalesce(p_total, 0)));
exception when others then
  raise warning '_notify_driver_offer_http(%): %', p_order_id, sqlerrm;
end;
$function$;

CREATE OR REPLACE FUNCTION public.fn_notify_driver_on_offer()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'net', 'extensions'
AS $function$
DECLARE
  v_driver_id text;
  v_order_id  text;
  v_vendor    text;
  v_total     numeric;
  v_jwt       text;
BEGIN
  -- Só dispara quando current_driver_offer_id muda para valor não-null
  IF NEW.current_driver_offer_id IS NULL THEN
    RETURN NEW;
  END IF;
  -- Sem mudança real, não notificar
  IF OLD.current_driver_offer_id IS NOT DISTINCT FROM NEW.current_driver_offer_id THEN
    RETURN NEW;
  END IF;

  v_driver_id := NEW.current_driver_offer_id;
  v_order_id  := NEW.id::text;
  v_vendor    := COALESCE(NEW.vendor_name, 'Pedido');
  v_total     := COALESCE(NEW.price, 0);
  v_jwt       := public._dispatch_service_jwt();

  PERFORM net.http_post(
    url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/notify-driver',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_jwt
    ),
    body    := jsonb_build_object(
      'driverId',   v_driver_id,
      'orderId',    v_order_id,
      'vendorName', v_vendor,
      'total',      v_total
    )
  );

  RAISE LOG '[fn_notify_driver_on_offer] orderId=% driverId=% vendor=%', v_order_id, v_driver_id, v_vendor;

  RETURN NEW;
END;
$function$;

-- bora_dispatch_maintenance: igual à versão no ar; só muda a chave do pedido ao motor.
CREATE OR REPLACE FUNCTION public.bora_dispatch_maintenance()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_order             record;
  v_cancelled_count   int := 0;
  v_ttl_max_count     int := 0;
  v_ttl_safety_count  int := 0;
  v_released_count    int := 0;
  v_drivers_online    int;
  v_jwt               text := public._dispatch_service_jwt();
  v_max_total_s       int;
  v_safety_s          int;
  v_release_s         int;
BEGIN
  PERFORM set_config('bora.caminho_oficial', 'bora_dispatch_maintenance', true);

  SELECT (value::text)::int INTO v_max_total_s
    FROM public.platform_settings WHERE key = 'dispatch_max_total_seconds_with_drivers_online';
  v_max_total_s := COALESCE(v_max_total_s, 1200);

  SELECT (value::text)::int INTO v_safety_s
    FROM public.platform_settings WHERE key = 'dispatch_auto_cancel_safety_seconds';
  v_safety_s := COALESCE(v_safety_s, 1800);

  SELECT (value::text)::int INTO v_release_s
    FROM public.platform_settings WHERE key = 'dispatch_preassign_release_seconds';
  v_release_s := COALESCE(v_release_s, 180);

  SELECT count(*) INTO v_drivers_online
    FROM public.drivers
    WHERE is_online = true
      AND last_heartbeat_at > NOW() - INTERVAL '90 seconds';

  FOR v_order IN
    SELECT o.id, o.assigned_driver_id, d.name AS driver_name,
           EXTRACT(EPOCH FROM (NOW() - COALESCE(o.driver_assigned_at, o.status_updated_at, o.dispatch_calling_since)))::int AS espera_s
      FROM public.orders o
      LEFT JOIN public.drivers d
        ON d.user_id::text = o.assigned_driver_id OR d.id::text = o.assigned_driver_id
     WHERE o.status = 'callingDriver'
       AND o.assigned_driver_id IS NOT NULL
       AND COALESCE(o.driver_assigned_at, o.status_updated_at, o.dispatch_calling_since, NOW())
           < NOW() - make_interval(secs => v_release_s)
  LOOP
    UPDATE public.orders
       SET assigned_driver_id      = NULL,
           driver_id               = NULL,
           current_driver_offer_id = NULL,
           driver_offer_expires_at = NULL,
           preassigned_driver_id   = NULL,
           dispatch_last_tick_at   = NOW()
     WHERE id = v_order.id AND status = 'callingDriver';
    PERFORM public._preassign_released_alert(
      v_order.id::text,
      COALESCE(v_order.driver_name, v_order.assigned_driver_id),
      'atribuído há ' || v_order.espera_s || ' s sem aceitar (limite ' || v_release_s || ' s)',
      'rede de segurança');
    PERFORM public.invoke_dispatch_engine(v_order.id::text);
    v_released_count := v_released_count + 1;
  END LOOP;
  IF v_released_count > 0 THEN
    RAISE NOTICE '[dispatch_maintenance] libertou % pedido(s) preso(s) em estafeta sem aceitar', v_released_count;
  END IF;

  WITH abandoned AS (
    UPDATE public.orders
       SET status         = 'cancelled',
           payment_status = 'failed',
           cancel_reason  = 'payment_abandoned'
     WHERE status = 'created' AND payment_status = 'pending'
       AND payment_method IN ('card', 'mbway')
       AND created_at < NOW() - INTERVAL '10 minutes'
    RETURNING id
  )
  SELECT count(*) INTO v_cancelled_count FROM abandoned;
  IF v_cancelled_count > 0 THEN
    RAISE NOTICE '[dispatch_maintenance] auto-cancelled % abandoned payment(s)', v_cancelled_count;
  END IF;

  UPDATE public.orders
     SET dispatch_calling_since = NOW()
   WHERE status = 'callingDriver' AND dispatch_calling_since IS NULL;

  IF v_drivers_online > 0 THEN
    UPDATE public.orders
       SET dispatch_online_attempt_seconds =
             COALESCE(dispatch_online_attempt_seconds, 0)
             + LEAST(
                 EXTRACT(EPOCH FROM (NOW() - COALESCE(dispatch_last_tick_at, NOW())))::int,
                 180
               ),
           dispatch_last_tick_at = NOW()
     WHERE status = 'callingDriver'
       AND assigned_driver_id IS NULL;
  ELSE
    UPDATE public.orders
       SET dispatch_last_tick_at = NOW()
     WHERE status = 'callingDriver'
       AND assigned_driver_id IS NULL;
  END IF;

  UPDATE public.orders
     SET dispatch_partner_decision_at = NULL,
         dispatch_extended_until      = NULL
   WHERE status = 'callingDriver'
     AND assigned_driver_id IS NULL
     AND dispatch_extended_until IS NOT NULL
     AND dispatch_extended_until < NOW();

  IF v_drivers_online > 0 THEN
    FOR v_order IN
      SELECT id FROM public.orders
       WHERE status = 'callingDriver'
         AND assigned_driver_id IS NULL
         AND COALESCE(dispatch_online_attempt_seconds, 0) >= v_max_total_s
    LOOP
      IF public.dispatch_cancel_expired_order(v_order.id, 'dispatch_max_total_with_drivers_exceeded') THEN
        v_ttl_max_count := v_ttl_max_count + 1;
      END IF;
    END LOOP;
    IF v_ttl_max_count > 0 THEN
      RAISE NOTICE '[dispatch_maintenance] TTL max_total auto-cancel % order(s) (>=%s s)',
        v_ttl_max_count, v_max_total_s;
    END IF;
  END IF;

  FOR v_order IN
    SELECT id FROM public.orders
     WHERE status = 'callingDriver'
       AND assigned_driver_id IS NULL
       AND dispatch_calling_since IS NOT NULL
       AND dispatch_calling_since < NOW() - make_interval(secs => v_safety_s)
  LOOP
    IF public.dispatch_cancel_expired_order(v_order.id, 'dispatch_safety_timeout') THEN
      v_ttl_safety_count := v_ttl_safety_count + 1;
    END IF;
  END LOOP;
  IF v_ttl_safety_count > 0 THEN
    RAISE NOTICE '[dispatch_maintenance] TTL safety auto-cancel % order(s) (>=%s s em callingDriver)',
      v_ttl_safety_count, v_safety_s;
  END IF;

  UPDATE public.orders
     SET tried_driver_ids        = array_append(
                                     COALESCE(tried_driver_ids, '{}'::text[]),
                                     current_driver_offer_id
                                   ),
         current_driver_offer_id = NULL,
         driver_offer_expires_at = NULL
   WHERE status = 'callingDriver'
     AND assigned_driver_id IS NULL
     AND current_driver_offer_id IS NOT NULL
     AND driver_offer_expires_at IS NOT NULL
     AND driver_offer_expires_at < NOW();

  FOR v_order IN
    SELECT id FROM public.orders
     WHERE status = 'callingDriver'
       AND assigned_driver_id IS NULL
       AND current_driver_offer_id IS NULL
       AND (dispatch_extended_until IS NULL OR dispatch_extended_until > NOW())
       AND (dispatch_calling_since IS NULL
            OR dispatch_calling_since > NOW() - make_interval(secs => v_safety_s))
       AND COALESCE(dispatch_online_attempt_seconds, 0) < v_max_total_s
       AND (dispatch_next_retry_at IS NULL
            OR dispatch_next_retry_at < NOW() - INTERVAL '60 seconds')
  LOOP
    PERFORM net.http_post(
      url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/dispatch-engine',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_jwt
      ),
      body    := jsonb_build_object('orderId', v_order.id::text)
    );
  END LOOP;
END;
$function$;
