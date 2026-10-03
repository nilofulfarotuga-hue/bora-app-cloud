-- =====================================================================
-- CARWASH — so se oferece o que ja esta pago  |  2026-08-27
--
-- PORQUE EXISTE:
-- a app publicada (build 550) mostra os botoes de cartao/MB WAY mas ainda
-- nao traz o codigo que cobra (esse entrou no 551). Sem esta guarda, um
-- cliente com a versao antiga escolhia cartao, o pedido nascia por pagar,
-- e o lavador ia buscar o carro de graca.
--
-- Em vez de depender de quem tem que versao instalada, resolve-se no
-- servidor: um pedido de cartao/MB WAY POR PAGAR nao chega a ser oferecido
-- a ninguem. Dinheiro segue como sempre (paga-se na entrega).
-- Quando o pagamento fecha, o confirm_carwash_payment_webhook volta a
-- chamar o _carwash_next_offer e ai sim procura-se lavador.
--
-- Provado ao vivo: pedido a cartao por pagar -> offer_washer_id NULL;
-- pedido a dinheiro -> oferecido de imediato.
-- =====================================================================

CREATE OR REPLACE FUNCTION public._carwash_next_offer(p_booking_id uuid)
RETURNS void LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_b carwash_bookings;
  v_next uuid;
  v_next_user uuid;
  v_timeout int := public._carwash_setting_int('carwash_offer_timeout_min', 10);
BEGIN
  SELECT * INTO v_b FROM carwash_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_b.id IS NULL OR v_b.status <> 'scheduled' THEN RETURN; END IF;

  -- guarda: cartao/MB WAY por pagar nao e oferecido
  IF v_b.payment_method IN ('card','mbway') AND v_b.payment_status = 'unpaid' THEN
    RETURN;
  END IF;

  SELECT w.id, w.user_id INTO v_next, v_next_user
  FROM washers w
  WHERE w.approval_status = 'approved' AND w.is_active AND NOT w.is_banned
    AND w.user_id <> v_b.client_user_id
    AND NOT (w.id = ANY (v_b.offered_washer_ids))
    AND (w.base_lat IS NULL OR v_b.lat IS NULL
         OR public._carwash_distance_km(w.base_lat, w.base_lng, v_b.lat, v_b.lng) <= w.service_radius_km)
    AND public._carwash_is_available(w.id, v_b.scheduled_at, v_b.duration_min)
  ORDER BY (w.id = v_b.requested_washer_id) DESC, w.rating_avg DESC, w.washes_done DESC
  LIMIT 1;

  IF v_next IS NULL THEN
    UPDATE carwash_bookings SET offer_washer_id = NULL, offer_expires_at = NULL
    WHERE id = p_booking_id;
    PERFORM public._carwash_notify_admin(
      'Lavagem sem lavador',
      'Pedido ' || p_booking_id::text || ' (' || v_b.plate || ') para ' ||
      to_char(v_b.scheduled_at AT TIME ZONE 'Europe/Lisbon', 'DD/MM HH24:MI') ||
      ' sem lavador disponivel.');
    RETURN;
  END IF;

  UPDATE carwash_bookings
  SET offer_washer_id = v_next,
      offer_expires_at = now() + make_interval(mins => v_timeout),
      offered_washer_ids = offered_washer_ids || v_next
  WHERE id = p_booking_id;

  PERFORM public._carwash_notify_user(
    v_next_user, 'carwash_offer', 'Nova lavagem disponivel',
    'Lavagem ' || CASE v_b.service_type WHEN 'exterior' THEN 'exterior'
                                        WHEN 'full' THEN 'completa'
                                        ELSE 'so interior' END ||
    ' - ' || (v_b.total_cents / 100.0)::numeric(10,2) || ' EUR. Tens ' || v_timeout || ' min para aceitar.',
    p_booking_id::text);
END $fn$;

REVOKE ALL ON FUNCTION public._carwash_next_offer(uuid) FROM PUBLIC, anon, authenticated;

CREATE OR REPLACE FUNCTION public.confirm_carwash_payment_webhook(p_booking_id uuid,
                                                                  p_payment_intent_id text,
                                                                  p_amount_cents integer)
RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE v_booking record;
BEGIN
  SELECT * INTO v_booking FROM public.carwash_bookings WHERE id = p_booking_id FOR UPDATE;
  IF v_booking IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'booking_not_found');
  END IF;
  IF v_booking.payment_status <> 'unpaid' THEN
    RETURN jsonb_build_object('ok', true, 'already_marked', true,
                              'payment_status', v_booking.payment_status);
  END IF;
  IF COALESCE(v_booking.total_cents, 0) <> COALESCE(p_amount_cents, -1) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'amount_mismatch',
                              'expected', v_booking.total_cents, 'received', p_amount_cents);
  END IF;

  UPDATE public.carwash_bookings
  SET payment_status = 'held', stripe_payment_intent_id = p_payment_intent_id
  WHERE id = p_booking_id AND payment_status = 'unpaid';

  -- ja pago -> agora sim, procura lavador
  IF v_booking.status = 'scheduled' AND v_booking.offer_washer_id IS NULL THEN
    PERFORM public._carwash_next_offer(p_booking_id);
  END IF;

  RETURN jsonb_build_object('ok', true, 'booking_id', p_booking_id);
END $fn$;

REVOKE ALL ON FUNCTION public.confirm_carwash_payment_webhook(uuid,text,integer) FROM PUBLIC, anon, authenticated;
