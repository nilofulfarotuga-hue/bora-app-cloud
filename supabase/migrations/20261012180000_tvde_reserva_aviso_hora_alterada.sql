-- =============================================================================
-- RESERVA DE CORRIDA (TVDE) — aviso CERTO ao motorista quando o cliente muda a
-- HORA (Bloco 3 da missão reserva-tvde-robo-2026-10-12).
--
-- Antes, tvde_reservation_reschedule usava o kind 'reservation_assigned'
-- ("Ficaste com uma reserva marcada para…") como remendo e, quando o motorista
-- perdia a reserva por conflito, mandava 'reservation_cancelled' ("O cliente
-- cancelou a reserva") — mentira. A Edge notify-tvde-driver v22 passa a tratar:
--   · reservation_rescheduled      → "A reserva passou para DD/MM às HH:MM • rota • Ganhas €X"
--   · reservation_rescheduled_lost → "O cliente mudou a hora e já tens outra reserva
--                                     perto — passou a outro motorista"
-- Só muda o kind enviado; regras de hora, motorista e rotação ficam iguais à
-- versão de 20261012162206.
--
-- Prova: tvde_ride_events status='push_enviado' com meta->>'kind' =
-- 'reservation_rescheduled' depois de uma mudança de hora.
-- =============================================================================

CREATE OR REPLACE FUNCTION public.tvde_reservation_reschedule(p_ride uuid, p_nova_hora_local text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_r public.tvde_rides;
  v_new timestamptz;
  v_min int := COALESCE((public.get_setting('tvde_reservation_min_advance_minutes') #>> '{}')::int, 30);
  v_max int := COALESCE((public.get_setting('tvde_reservation_max_advance_days') #>> '{}')::int, 30);
  v_driver uuid;
  v_mantem boolean := false;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT * INTO v_r FROM public.tvde_rides WHERE id = p_ride FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'reservation_not_found'; END IF;
  IF v_r.client_id <> v_uid AND NOT public.is_admin() THEN RAISE EXCEPTION 'reservation_not_yours'; END IF;
  IF v_r.scheduled_at IS NULL OR v_r.status <> 'agendada' THEN RAISE EXCEPTION 'too_late_to_change'; END IF;

  BEGIN
    v_new := (p_nova_hora_local::timestamp) AT TIME ZONE 'Europe/Lisbon';
  EXCEPTION WHEN others THEN RAISE EXCEPTION 'invalid_time'; END;

  IF v_new = v_r.scheduled_at THEN
    RETURN jsonb_build_object('ok', true, 'sem_mudanca', true);
  END IF;
  IF v_new < now() + make_interval(mins => v_min) THEN RAISE EXCEPTION 'too_soon'; END IF;
  IF v_new > now() + make_interval(days => v_max) THEN RAISE EXCEPTION 'too_far'; END IF;
  IF EXISTS (SELECT 1 FROM public.tvde_rides
              WHERE client_id = v_r.client_id AND id <> p_ride AND status = 'agendada'
                AND abs(extract(epoch FROM (scheduled_at - v_new))) < 1800) THEN
    RAISE EXCEPTION 'reservation_overlap'; END IF;

  v_driver := v_r.reservation_driver_id;
  IF v_driver IS NOT NULL THEN
    v_mantem := NOT EXISTS (
      SELECT 1 FROM public.tvde_rides o
       WHERE o.id <> p_ride AND o.status = 'agendada'
         AND o.reservation_driver_id = v_driver
         AND abs(extract(epoch FROM (o.scheduled_at - v_new))) < 3600);
  END IF;

  UPDATE public.tvde_rides SET
    scheduled_at = v_new,
    reservation_reminder_60_at = NULL,
    reservation_reminder_15_at = NULL,
    reservation_client_ask_at  = NULL,
    reservation_admin_alert_at = NULL,
    reservation_driver_ready_at = NULL,
    reservation_driver_id = CASE WHEN v_mantem THEN v_driver ELSE NULL END,
    reservation_status = CASE
       WHEN reservation_status = 'aguarda_pagamento' THEN reservation_status
       WHEN v_mantem THEN 'atribuida'
       ELSE 'a_procurar' END,
    reservation_offer_driver_id = NULL,
    reservation_offer_expires_at = NULL,
    reservation_tried_driver_ids = CASE WHEN v_mantem THEN reservation_tried_driver_ids ELSE '{}'::uuid[] END,
    updated_at = now()
  WHERE id = p_ride;

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
  VALUES (p_ride, 'reserva_hora_alterada', CASE WHEN v_r.client_id = v_uid THEN 'client' ELSE 'admin' END,
          jsonb_build_object('hora_antiga', v_r.scheduled_at, 'hora_nova', v_new,
                             'motorista', v_driver, 'motorista_mantem', v_mantem));

  -- 2026-10-12 (Bloco 3): kinds verdadeiros — notify-tvde-driver v22.
  IF v_driver IS NOT NULL AND v_mantem THEN
    PERFORM public.tvde_reservation_push(v_driver, p_ride, 'reservation_rescheduled');
  ELSIF v_driver IS NOT NULL THEN
    PERFORM public.tvde_reservation_push(v_driver, p_ride, 'reservation_rescheduled_lost');
  END IF;

  IF NOT v_mantem AND v_r.reservation_status <> 'aguarda_pagamento' THEN
    PERFORM public.tvde_reservation_offer_to_next(p_ride);
  END IF;

  RETURN jsonb_build_object('ok', true,
    'hora_nova', to_char(v_new AT TIME ZONE 'Europe/Lisbon', 'YYYY-MM-DD HH24:MI'),
    'motorista_mantem', v_mantem,
    'a_procurar_motorista', (NOT v_mantem));
END $function$;

REVOKE ALL ON FUNCTION public.tvde_reservation_reschedule(uuid, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.tvde_reservation_reschedule(uuid, text) TO authenticated, service_role;
