-- ─────────────────────────────────────────────────────────────────────────────
-- TVDE — Item L (bug de campo): motorista DESISTE depois de aceitar → a corrida
-- MORRIA para o cliente em vez de rotacionar.
--
-- Bug (device real): o motorista aceita, fica 'motorista_a_caminho', cancela →
-- tvde_cancel_ride setava 'cancelada_motorista' (TERMINAL). O cliente via a
-- corrida cancelada só porque o motorista desistiu.
--
-- Correção (mesmo espírito do E): quando p_actor='motorista' e a corrida ainda
-- NÃO foi recolhida/iniciada (motorista_atribuido/motorista_a_caminho/
-- motorista_chegou — ANTES do pickup), NÃO termina. Em vez disso:
--   • devolve a corrida ao pool → status='solicitada', driver_id=NULL;
--   • marca o desistente em tried_driver_ids (NÃO recebe a mesma logo → sem loop);
--   • re-oferece ao PRÓXIMO elegível (tvde_offer_to_next). Se for o único, a
--     pausa do sweep (~35s, migration 20260703170000) devolve-lhe depois.
-- O cliente NUNCA vê a corrida cancelada por desistência — volta a "à procura".
--
-- EXCEÇÃO deliberada: DEPOIS do pickup ('em_andamento') NÃO é tratado aqui —
-- é caso especial (decisão humana pendente); cai no cancelamento normal abaixo
-- (comportamento antigo, cancelada_motorista) até o Danilo decidir a regra.
--
-- Não mexe em dinheiro (tvde_cancel_fee_cents=0). Só rotação/dispatch.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION public.tvde_cancel_ride(p_ride_id uuid, p_actor text, p_reason text DEFAULT NULL::text)
RETURNS tvde_rides
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
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
BEGIN
  IF p_actor NOT IN ('cliente','motorista','no_show') THEN RAISE EXCEPTION 'invalid_actor: %', p_actor; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF NOT (v_is_admin OR v_ride.client_id = v_uid OR v_ride.driver_id = v_uid) THEN RAISE EXCEPTION 'not_authorized'; END IF;
  IF v_ride.status IN ('finalizada','cancelada_cliente','cancelada_motorista','no_show') THEN RAISE EXCEPTION 'ride_already_terminal: %', v_ride.status; END IF;

  -- ── [Item L] Motorista desiste ANTES do pickup → devolve ao dispatch ──────
  IF p_actor = 'motorista'
     AND v_ride.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou')
  THEN
    v_quit_driver := v_ride.driver_id;
    UPDATE public.tvde_rides
       SET status = 'solicitada',
           driver_id = NULL,
           is_queued = false,
           current_offer_driver_id = NULL,
           offer_expires_at = NULL,
           no_driver_since = NULL,
           tried_driver_ids = CASE WHEN v_quit_driver IS NOT NULL
             THEN array_append(COALESCE(tried_driver_ids, '{}'::uuid[]), v_quit_driver)
             ELSE tried_driver_ids END,
           updated_at = now()
     WHERE id = p_ride_id
     RETURNING * INTO v_ride;

    INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
      VALUES (p_ride_id, 'motorista_desistiu', 'motorista',
        jsonb_build_object('reason', p_reason, 'released_driver', v_quit_driver, 'requeued', true));

    -- Se o desistente tinha corrida EM FILA, ativa-a (ele segue com a outra).
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

    -- Re-oferece ESTA corrida ao próximo elegível (exclui o desistente via tried).
    PERFORM public.tvde_offer_to_next(p_ride_id);
    RETURN v_ride;
  END IF;

  -- ── Cancelamento normal (cliente, no_show, ou motorista JÁ em_andamento) ──
  v_was_active_of_driver := v_ride.driver_id IS NOT NULL AND v_ride.is_queued = false
    AND v_ride.status IN ('motorista_a_caminho','motorista_chegou','em_andamento');
  v_new_status := CASE p_actor WHEN 'cliente' THEN 'cancelada_cliente' WHEN 'motorista' THEN 'cancelada_motorista' ELSE 'no_show' END;
  IF v_ride.status <> 'solicitada' THEN v_fee := (public.get_setting('tvde_cancel_fee_cents') #>> '{}')::int; END IF;
  UPDATE public.tvde_rides SET status = v_new_status, cancel_reason = p_reason, cancel_fee_cents = v_fee,
    is_queued = false, current_offer_driver_id = NULL, offer_expires_at = NULL, updated_at = now()
   WHERE id = p_ride_id RETURNING * INTO v_ride;
  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, v_new_status, CASE WHEN v_is_admin THEN 'admin' ELSE p_actor END, jsonb_build_object('reason', p_reason, 'cancel_fee_cents', v_fee));

  -- back-to-back: a ativa caiu -> ativa a corrida em fila do motorista
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
