-- Despacho — estafeta: cancelar pedido aceite, heartbeat e posição (ronda 04/10/2026, agente despacho)
--
-- A3  driver_cancel_order procurava assigned_driver_id = drivers.id, mas a app grava
--     auth.uid() (= drivers.user_id) ao aceitar → para estafetas com id <> user_id
--     (ex.: Valdemir) "cancelar" falhava sempre. Também deixava driver_id,
--     driver_phone e preassigned_driver_id preenchidos (o gatilho de pré-atribuição
--     voltava a oferecer o pedido ao MESMO estafeta) e chamava o motor sem chave.
-- A6  Os heartbeats (driver_heartbeat, driver_heartbeat_by_id) e a posição
--     (driver_update_location) punham is_online=true sozinhos. Regra do Danilo:
--     só o botão liga/desliga. Agora só atualizam o sinal/posição.
--     driver_heartbeat_by_id estava aberto a anon para QUALQUER estafeta: passa a
--     exigir que a sessão seja do próprio; sem sessão (serviço Android em segundo
--     plano das apps antigas) só renova o sinal de quem JÁ está online.
--     Novo caminho seguro: segredo por estafeta (driver_heartbeat_segredo_obter /
--     driver_heartbeat_segredo).
-- 08  driver_push_position mudava a posição GPS de QUALQUER estafeta (anon):
--     agora só o próprio, admin ou serviço.

-- ── A3 ─────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.driver_cancel_order(p_order_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid    uuid := auth.uid();
  v_drv    record;
  v_keys   text[];
  v_order  record;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unauthorized');
  END IF;

  SELECT id, user_id INTO v_drv FROM drivers WHERE user_id = v_uid OR id = v_uid LIMIT 1;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'Driver not found');
  END IF;
  -- O pedido pode ter qualquer dos dois formatos (user_id é o certo; id é legado).
  v_keys := ARRAY[v_drv.id::text, COALESCE(v_drv.user_id, v_drv.id)::text];

  -- §7.7 (decisão Danilo 2026-05-07): só antes de recolher; depois, suporte.
  SELECT * INTO v_order FROM orders
   WHERE id = p_order_id
     AND assigned_driver_id = ANY(v_keys)
     AND status = 'driverAccepted'
   FOR UPDATE;

  IF NOT FOUND THEN
    IF EXISTS (
      SELECT 1 FROM orders
       WHERE id = p_order_id
         AND assigned_driver_id = ANY(v_keys)
         AND status IN ('pickedUp', 'onTheWay')
    ) THEN
      RETURN jsonb_build_object(
        'ok', false,
        'error', 'cancel_blocked_after_pickup',
        'message', 'Após recolher o pedido, contacta o suporte para cancelar.',
        'support_required', true
      );
    END IF;
    RETURN jsonb_build_object('ok', false, 'error', 'Order not found or not assigned to this driver');
  END IF;

  PERFORM set_config('bora.caminho_oficial', 'driver_cancel_order', true);
  PERFORM set_config('app.order_transition_source', 'driver_cancel_order', true);

  -- Volta a callingDriver sem nenhum rasto do estafeta. tried_driver_ids guarda
  -- drivers.id (chave do matching) para não lhe voltar a oferecer este pedido.
  UPDATE orders SET
    status                  = 'callingDriver',
    assigned_driver_id      = NULL,
    driver_id               = NULL,
    driver_phone            = NULL,
    preassigned_driver_id   = NULL,
    current_driver_offer_id = NULL,
    driver_offer_expires_at = NULL,
    dispatch_next_retry_at  = NULL,
    tried_driver_ids        = CASE
      WHEN v_drv.id::text = ANY(COALESCE(tried_driver_ids, '{}'::text[])) THEN tried_driver_ids
      ELSE array_append(COALESCE(tried_driver_ids, '{}'::text[]), v_drv.id::text)
    END
  WHERE id = p_order_id;

  -- O gatilho trg_dispatch_on_calling_driver já chama o motor (com a chave de
  -- serviço); isto é a rede de segurança, também autenticada.
  PERFORM public.invoke_dispatch_engine(p_order_id);

  RETURN jsonb_build_object('ok', true);
END;
$function$;
REVOKE ALL ON FUNCTION public.driver_cancel_order(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_cancel_order(text) TO authenticated, service_role;

-- ── A6: heartbeats não ligam ninguém ────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.driver_heartbeat()
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID;
  v_now TIMESTAMPTZ := now();
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;

  -- 2026-10-04 (A6): o sinal NUNCA liga o estafeta — só o botão.
  UPDATE public.drivers d
     SET last_heartbeat_at = v_now
   WHERE d.user_id = v_uid OR d.id = v_uid;

  RETURN jsonb_build_object(
    'success', true,
    'driver_id', v_uid,
    'heartbeat_at', v_now
  );
END;
$function$;
REVOKE ALL ON FUNCTION public.driver_heartbeat() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_heartbeat() TO authenticated, service_role;

CREATE OR REPLACE FUNCTION public.driver_heartbeat(p_platform text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID;
  v_now TIMESTAMPTZ := now();
  v_plat text := lower(btrim(coalesce(p_platform, '')));
  v_gps boolean;
BEGIN
  v_uid := auth.uid();
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;
  IF v_plat NOT IN ('android_app','ios_app','web_ios','web_android','web_desktop') THEN
    v_plat := NULL;
  END IF;

  -- 2026-10-04 (A6): o sinal NUNCA liga o estafeta — só o botão.
  UPDATE public.drivers d
     SET last_heartbeat_at = v_now,
         last_platform    = COALESCE(v_plat, last_platform),
         last_platform_at = CASE WHEN v_plat IS NULL THEN last_platform_at ELSE v_now END
   WHERE d.user_id = v_uid OR d.id = v_uid;

  SELECT public.driver_gps_fresh(d.user_id, d.id) INTO v_gps
    FROM public.drivers d WHERE d.user_id = v_uid OR d.id = v_uid LIMIT 1;
  RETURN jsonb_build_object('success', true, 'driver_id', v_uid, 'heartbeat_at', v_now, 'platform', v_plat,
                            'gps_fresco', COALESCE(v_gps, false));
END;
$function$;
REVOKE ALL ON FUNCTION public.driver_heartbeat(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_heartbeat(text) TO authenticated, service_role;

-- Forma ANTIGA (apps já instaladas): o serviço Android em segundo plano chama-a
-- com a chave anónima e o id do estafeta. Durante a transição continua a
-- responder, mas: com sessão → só o próprio; sem sessão → só renova o sinal de
-- quem já está online (nunca liga ninguém, nunca mexe na posição).
CREATE OR REPLACE FUNCTION public.driver_heartbeat_by_id(p_driver_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_now     timestamptz := now();
  v_uid     uuid := auth.uid();
  v_id      uuid;
  v_updated int;
BEGIN
  IF p_driver_id IS NULL OR length(trim(p_driver_id)) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'driver_id_required');
  END IF;
  BEGIN
    v_id := trim(p_driver_id)::uuid;
  EXCEPTION WHEN others THEN
    RETURN jsonb_build_object('ok', false, 'error', 'driver_not_found');
  END;

  UPDATE public.drivers d
     SET last_heartbeat_at = v_now,
         last_platform     = 'android_app',
         last_platform_at  = v_now
   WHERE (d.id = v_id OR d.user_id = v_id)
     AND (
       (v_uid IS NOT NULL AND (d.user_id = v_uid OR d.id = v_uid))
       OR (v_uid IS NULL AND d.is_online)
     );

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'driver_not_found');
  END IF;

  RETURN jsonb_build_object('ok', true, 'driver_id', p_driver_id, 'heartbeat_at', v_now);
END;
$function$;

-- Segredo por estafeta para o serviço em segundo plano (sem sessão).
CREATE TABLE IF NOT EXISTS public.driver_heartbeat_segredos (
  user_id     uuid PRIMARY KEY,
  segredo     text NOT NULL,
  criado_em   timestamptz NOT NULL DEFAULT now(),
  usado_em    timestamptz
);
ALTER TABLE public.driver_heartbeat_segredos ENABLE ROW LEVEL SECURITY;
REVOKE ALL ON public.driver_heartbeat_segredos FROM PUBLIC, anon, authenticated;
COMMENT ON TABLE public.driver_heartbeat_segredos IS
  'Segredo do heartbeat em segundo plano (Android, sem sessão). Só se lê por driver_heartbeat_segredo_obter (o próprio, com sessão).';

-- Com sessão: devolve o segredo do estafeta (cria-o se não houver; p_renovar=true troca-o).
CREATE OR REPLACE FUNCTION public.driver_heartbeat_segredo_obter(p_renovar boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_seg text;
BEGIN
  IF v_uid IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'unauthorized');
  END IF;
  IF NOT EXISTS (SELECT 1 FROM public.drivers WHERE user_id = v_uid) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'driver_not_found');
  END IF;
  v_seg := replace(gen_random_uuid()::text, '-', '') || replace(gen_random_uuid()::text, '-', '');
  IF COALESCE(p_renovar, false) THEN
    INSERT INTO public.driver_heartbeat_segredos(user_id, segredo) VALUES (v_uid, v_seg)
    ON CONFLICT (user_id) DO UPDATE SET segredo = EXCLUDED.segredo, criado_em = now(), usado_em = NULL;
  ELSE
    INSERT INTO public.driver_heartbeat_segredos(user_id, segredo) VALUES (v_uid, v_seg)
    ON CONFLICT (user_id) DO NOTHING;
  END IF;
  SELECT segredo INTO v_seg FROM public.driver_heartbeat_segredos WHERE user_id = v_uid;
  RETURN jsonb_build_object('ok', true, 'driver_id', v_uid, 'segredo', v_seg);
END;
$function$;
REVOKE ALL ON FUNCTION public.driver_heartbeat_segredo_obter(boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_heartbeat_segredo_obter(boolean) TO authenticated, service_role;

-- Sem sessão (serviço Android): id + segredo. Só renova o sinal; nunca liga.
CREATE OR REPLACE FUNCTION public.driver_heartbeat_segredo(p_driver_id text, p_segredo text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_now timestamptz := now();
  v_id  uuid;
  v_ok  boolean;
  v_n   int;
BEGIN
  BEGIN
    v_id := trim(p_driver_id)::uuid;
  EXCEPTION WHEN others THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END;
  SELECT (s.segredo = p_segredo) INTO v_ok
    FROM public.driver_heartbeat_segredos s
    JOIN public.drivers d ON d.user_id = s.user_id
   WHERE d.user_id = v_id OR d.id = v_id
   LIMIT 1;
  IF NOT COALESCE(v_ok, false) OR p_segredo IS NULL OR length(p_segredo) < 32 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  UPDATE public.drivers d
     SET last_heartbeat_at = v_now,
         last_platform     = 'android_app',
         last_platform_at  = v_now
   WHERE d.user_id = v_id OR d.id = v_id;
  GET DIAGNOSTICS v_n = ROW_COUNT;
  UPDATE public.driver_heartbeat_segredos s SET usado_em = v_now
    FROM public.drivers d WHERE d.user_id = s.user_id AND (d.user_id = v_id OR d.id = v_id);

  RETURN jsonb_build_object('ok', v_n > 0, 'driver_id', p_driver_id, 'heartbeat_at', v_now);
END;
$function$;
REVOKE ALL ON FUNCTION public.driver_heartbeat_segredo(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.driver_heartbeat_segredo(text, text) TO anon, authenticated, service_role;

-- ── A6: a posição também não liga ninguém ──────────────────────────────────
-- p_is_online=false continua a desligar (é o ping do botão "ficar offline");
-- p_is_online=true já não liga: só o botão liga.
CREATE OR REPLACE FUNCTION public.driver_update_location(p_latitude numeric, p_longitude numeric, p_heading numeric DEFAULT NULL::numeric, p_speed_kmh numeric DEFAULT NULL::numeric, p_is_online boolean DEFAULT true)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_online boolean;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'driver_required: not authenticated' USING ERRCODE = '42501';
  END IF;
  IF p_latitude IS NULL OR p_longitude IS NULL THEN
    RAISE EXCEPTION 'invalid_coords: latitude/longitude required' USING ERRCODE = '22023';
  END IF;
  IF p_latitude < -90 OR p_latitude > 90 OR p_longitude < -180 OR p_longitude > 180 THEN
    RAISE EXCEPTION 'invalid_coords: out of range' USING ERRCODE = '22023';
  END IF;

  UPDATE public.drivers
  SET lat = p_latitude,
      lng = p_longitude,
      is_online = CASE WHEN p_is_online IS FALSE THEN false ELSE is_online END,
      last_heartbeat_at = NOW(),
      updated_at = NOW()
  WHERE user_id = v_uid OR id = v_uid
  RETURNING is_online INTO v_online;

  INSERT INTO public.driver_locations (
    driver_id, latitude, longitude, heading, speed_kmh, is_online, last_updated
  ) VALUES (
    v_uid, p_latitude, p_longitude, p_heading, p_speed_kmh,
    COALESCE(p_is_online, true) AND COALESCE(v_online, false), NOW()
  )
  ON CONFLICT (driver_id) DO UPDATE SET
    latitude = EXCLUDED.latitude,
    longitude = EXCLUDED.longitude,
    heading = EXCLUDED.heading,
    speed_kmh = EXCLUDED.speed_kmh,
    is_online = EXCLUDED.is_online,
    last_updated = NOW();
END;
$function$;
REVOKE ALL ON FUNCTION public.driver_update_location(numeric, numeric, numeric, numeric, boolean) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_update_location(numeric, numeric, numeric, numeric, boolean) TO authenticated, service_role;

-- ── 08: posição de QUALQUER estafeta → só o próprio, admin ou serviço ──────
CREATE OR REPLACE FUNCTION public.driver_push_position(p_driver_id text, p_lat numeric, p_lng numeric)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_updated int;
  v_uid     uuid := auth.uid();
  v_role    text := COALESCE(auth.role(), '');
  v_id      uuid;
BEGIN
  IF p_driver_id IS NULL OR length(trim(p_driver_id)) = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'driver_id_required');
  END IF;
  IF p_lat IS NULL OR p_lng IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'coords_required');
  END IF;
  IF p_lat < -90 OR p_lat > 90 OR p_lng < -180 OR p_lng > 180 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'coords_out_of_range');
  END IF;
  BEGIN
    v_id := trim(p_driver_id)::uuid;
  EXCEPTION WHEN others THEN
    RETURN jsonb_build_object('ok', false, 'error', 'driver_not_found');
  END;
  IF v_role <> 'service_role' AND NOT public.is_admin() THEN
    IF v_uid IS NULL THEN
      RETURN jsonb_build_object('ok', false, 'error', 'unauthorized');
    END IF;
    IF NOT EXISTS (SELECT 1 FROM public.drivers WHERE id = v_id AND (user_id = v_uid OR id = v_uid)) THEN
      RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
    END IF;
  END IF;

  UPDATE public.drivers
     SET lat        = p_lat,
         lng        = p_lng,
         updated_at = now()
   WHERE id = v_id;

  GET DIAGNOSTICS v_updated = ROW_COUNT;
  IF v_updated = 0 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'driver_not_found');
  END IF;

  RETURN jsonb_build_object('ok', true);
END;
$function$;
REVOKE ALL ON FUNCTION public.driver_push_position(text, numeric, numeric) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.driver_push_position(text, numeric, numeric) TO authenticated, service_role;
