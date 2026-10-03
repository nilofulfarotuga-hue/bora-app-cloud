-- =============================================================================
-- F2 — TAXA TVDE estilo Uber (APLICADO em produção via MCP a 2026-08-17,
-- após "vai" do Danilo). Registo da migration — NÃO re-aplicar às cegas.
-- =============================================================================
-- 3 mudanças vs. versão anterior (20260813200000):
--   1. v_had_driver = SÓ driver_id IS NOT NULL — oferta pendente
--      (current_offer_driver_id) ou tentativas (tried_driver_ids) NÃO são
--      motorista atribuído; não se cobra cancelamento de serviço que ninguém aceitou.
--   2. Fee pós-aceite (cliente, passada a graça) = taxa FIXA tvde_cancel_fee_cents
--      (250), NÃO est_fare_cents. Estilo Uber. Remove o fallback plano/0→350.
--   3. no_show = caminho próprio tvde_noshow_driver_fee_cents (350) — antes dava 0.
-- Depois da função: religado platform_settings.tvde_cancel_full_after_grace=true.
--
-- PROVA (rollback tx contra a função de produção, settings reais 250/180/350):
--   caso1 sem-aceite (driver_id NULL, com oferta+tentativas, pós-graça) → fee=0
--   caso2 pós-aceite (motorista_a_caminho, pós-graça, est_fare=700)     → fee=250
--   caso3 no-show (motorista_chegou)                                    → fee=350
-- =============================================================================

CREATE OR REPLACE FUNCTION public.tvde_cancel_ride(p_ride_id uuid, p_actor text, p_reason text DEFAULT NULL::text)
 RETURNS tvde_rides LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_uid UUID := auth.uid();
  v_ride public.tvde_rides;
  v_new_status TEXT;
  v_fee INT := 0;
  v_is_admin BOOLEAN := public.is_admin();
  v_was_active_of_driver BOOLEAN := false;
  v_next UUID;
  v_quit_driver UUID;
  v_grace INT;
  v_before_pickup BOOLEAN;
  v_had_driver BOOLEAN;
BEGIN
  IF p_actor NOT IN ('cliente','motorista','no_show') THEN RAISE EXCEPTION 'invalid_actor: %', p_actor; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF NOT (v_is_admin OR v_ride.client_id = v_uid OR v_ride.driver_id = v_uid) THEN RAISE EXCEPTION 'not_authorized'; END IF;
  IF v_ride.status IN ('finalizada','cancelada_cliente','cancelada_motorista','no_show') THEN RAISE EXCEPTION 'ride_already_terminal: %', v_ride.status; END IF;

  IF p_actor = 'motorista'
     AND v_ride.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou')
  THEN
    v_quit_driver := v_ride.driver_id;
    UPDATE public.tvde_rides
       SET status = 'solicitada', driver_id = NULL, is_queued = false,
           current_offer_driver_id = NULL, offer_expires_at = NULL, no_driver_since = NULL,
           tried_driver_ids = CASE WHEN v_quit_driver IS NOT NULL
             THEN array_append(COALESCE(tried_driver_ids, '{}'::uuid[]), v_quit_driver)
             ELSE tried_driver_ids END,
           updated_at = now()
     WHERE id = p_ride_id RETURNING * INTO v_ride;
    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (p_ride_id, 'motorista_desistiu', 'motorista',
        jsonb_build_object('reason', p_reason, 'released_driver', v_quit_driver, 'requeued', true));
    UPDATE public.tvde_rides
       SET is_queued = false, status = 'motorista_a_caminho', updated_at = now()
     WHERE id = (SELECT r3.id FROM public.tvde_rides r3
                 WHERE r3.driver_id = v_quit_driver AND r3.is_queued = true
                   AND r3.status = 'motorista_atribuido'
                 ORDER BY r3.created_at ASC LIMIT 1)
     RETURNING id INTO v_next;
    IF v_next IS NOT NULL THEN
      INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
        VALUES (v_next, 'motorista_a_caminho', 'system',
          jsonb_build_object('queued_activation', true, 'after_ride_id', p_ride_id, 'after_driver_giveup', true));
    END IF;
    PERFORM public.tvde_offer_to_next(p_ride_id);
    RETURN v_ride;
  END IF;

  v_was_active_of_driver := v_ride.driver_id IS NOT NULL AND v_ride.is_queued = false
    AND v_ride.status IN ('motorista_a_caminho','motorista_chegou','em_andamento');
  v_new_status := CASE p_actor WHEN 'cliente' THEN 'cancelada_cliente' WHEN 'motorista' THEN 'cancelada_motorista' ELSE 'no_show' END;
  v_before_pickup := v_ride.status IN ('solicitada','motorista_atribuido','motorista_a_caminho','motorista_chegou');

  -- MUDANÇA 1: só há motorista a compensar se um motorista ACEITOU (driver_id).
  v_had_driver := v_ride.driver_id IS NOT NULL;

  IF p_actor = 'no_show' AND v_before_pickup AND v_had_driver THEN
    -- MUDANÇA 3: no-show tem caminho próprio (compensa o motorista).
    v_fee := COALESCE((public.get_setting('tvde_noshow_driver_fee_cents') #>> '{}')::int, 350);
  ELSIF p_actor = 'cliente' AND v_before_pickup AND v_had_driver THEN
    v_grace := (public.get_setting('cancel_grace_seconds') #>> '{}')::int;
    IF COALESCE((public.get_setting('tvde_cancel_full_after_grace') #>> '{}')::boolean, false)
       AND EXTRACT(EPOCH FROM (now() - v_ride.created_at))::int > v_grace THEN
      -- MUDANÇA 2: taxa FIXA de cancelamento, não o valor da corrida.
      v_fee := COALESCE((public.get_setting('tvde_cancel_fee_cents') #>> '{}')::int, 250);
    ELSE
      v_fee := 0;
    END IF;
  ELSE
    v_fee := 0;
  END IF;

  UPDATE public.tvde_rides SET status = v_new_status, cancel_reason = p_reason, cancel_fee_cents = v_fee,
    is_queued = false, current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;
  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, v_new_status, CASE WHEN v_is_admin THEN 'admin' ELSE p_actor END,
            jsonb_build_object('reason', p_reason, 'cancel_fee_cents', v_fee,
              'grace_seconds', v_grace, 'had_driver', v_had_driver,
              'elapsed_seconds', EXTRACT(EPOCH FROM (now() - v_ride.created_at))::int));

  IF v_was_active_of_driver THEN
    UPDATE public.tvde_rides
       SET is_queued = false, status = 'motorista_a_caminho', updated_at = now()
     WHERE id = (SELECT r3.id FROM public.tvde_rides r3
                 WHERE r3.driver_id = v_ride.driver_id AND r3.is_queued = true
                   AND r3.status = 'motorista_atribuido'
                 ORDER BY r3.created_at ASC LIMIT 1)
     RETURNING id INTO v_next;
    IF v_next IS NOT NULL THEN
      INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
        VALUES (v_next, 'motorista_a_caminho', 'system',
                jsonb_build_object('queued_activation', true, 'after_ride_id', p_ride_id, 'after_cancel', true));
    END IF;
  END IF;

  RETURN v_ride;
END; $function$;

-- Religar a taxa pós-graça (estava false desde 17/08; sem isto a taxa nunca ativa).
UPDATE platform_settings SET value = 'true' WHERE key = 'tvde_cancel_full_after_grace';
