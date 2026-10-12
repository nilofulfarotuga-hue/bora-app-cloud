-- =============================================================================
-- RESERVA DE CORRIDA (TVDE): o cliente muda a hora e o robô lê as reservas
-- 2026-10-12 — APLICADA EM PRODUÇÃO por MCP (Claude.ai) com o nome
-- `tvde_reserva_cliente_muda_hora_e_robo_le_reservas_2026_10_12`
-- (supabase_migrations.schema_migrations version 20261012162206).
-- Esta é a CÓPIA para o repo (regra: toda migração aplicada em produção fica
-- em supabase/migrations). Não voltar a aplicar — idempotente na mesma.
--
-- Porquê (12/10): uma cliente teve de LIGAR ao Danilo para mudar a hora da
-- reserva de corrida (17:30 → 17:45). O robô de suporte só conhecia pedidos.
--
-- 1. agent_get_my_tvde_reservations() — lista as reservas futuras do cliente
--    da sessão (hora de Lisboa, recolha, destino, preço, pagamento, pago,
--    motorista atribuído, estado). Só `authenticated`.
-- 2. tvde_reservation_reschedule(p_ride, p_nova_hora_local 'YYYY-MM-DD HH:MI')
--    — só o dono (ou admin), só com status='agendada'; mesmas regras de marcar
--    (mín. 30 min, máx. 30 dias, sem sobreposição de 30 min). Se o motorista
--    não tem outra reserva a menos de 60 min da hora nova FICA com ela e
--    recebe push; senão volta à rotação. Limpa os lembretes.
--    (Os kinds de push desta versão — reservation_assigned / _cancelled — são
--    substituídos pelos verdadeiros em 20261012180000_tvde_reserva_aviso_hora_alterada.sql.)
-- =============================================================================

CREATE OR REPLACE FUNCTION public.agent_get_my_tvde_reservations()
 RETURNS TABLE(ride_id uuid, hora_local text, recolha text, destino text, preco_eur text, pagamento text, pago boolean, motorista_atribuido boolean, estado text)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT r.id,
         to_char(r.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'YYYY-MM-DD HH24:MI'),
         r.origin_label, r.dest_label,
         to_char(r.est_fare_cents / 100.0, 'FM990.00'),
         r.payment_method,
         (r.payment_status = 'succeeded'),
         (r.reservation_driver_id IS NOT NULL),
         r.reservation_status
    FROM public.tvde_rides r
   WHERE r.client_id = auth.uid()
     AND r.scheduled_at IS NOT NULL
     AND r.status IN ('agendada','motorista_atribuido','motorista_a_caminho')
     AND r.scheduled_at > now() - interval '30 minutes'
   ORDER BY r.scheduled_at;
$function$;

REVOKE ALL ON FUNCTION public.agent_get_my_tvde_reservations() FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.agent_get_my_tvde_reservations() TO authenticated, service_role;

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

  IF v_driver IS NOT NULL AND v_mantem THEN
    PERFORM public.tvde_reservation_push(v_driver, p_ride, 'reservation_assigned');
  ELSIF v_driver IS NOT NULL THEN
    PERFORM public.tvde_reservation_push(v_driver, p_ride, 'reservation_cancelled');
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
