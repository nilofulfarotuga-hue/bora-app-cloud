-- =====================================================================
-- CARWASH — PORTAO ANTES DO STRIPE  |  2026-08-27
--
-- Licao de 31/07: o PaymentIntent nasceu antes da order e o cliente pagou
-- por um pedido que rebentou. Aqui a ordem e a inversa e o portao esta num
-- sitio so, para a Edge nao poder esquecer nenhuma validacao.
--
-- Chamada por: supabase/functions/carwash-checkout/index.ts, ANTES de
-- qualquer chamada a Stripe. Devolve o valor a cobrar — que vem sempre do
-- servidor, nunca do Dart.
-- =====================================================================

CREATE OR REPLACE FUNCTION public.carwash_payment_precheck(p_booking_id uuid, p_user_id uuid)
RETURNS jsonb LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path TO 'public' AS $fn$
DECLARE
  v_b carwash_bookings;
  v_quote jsonb;
  v_radius numeric := public._carwash_setting_num('carwash_service_radius_km', 8);
  v_blat double precision := public._carwash_setting_num('carwash_base_lat', 40.5373);
  v_blng double precision := public._carwash_setting_num('carwash_base_lng', -7.2676);
  v_dist double precision;
BEGIN
  -- 1. a categoria esta aberta?
  IF NOT public._carwash_setting_bool('carwash_enabled', true) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'carwash_disabled');
  END IF;

  -- 2. cartao/MB WAY ligados?
  IF NOT public._carwash_setting_bool('carwash_stripe_enabled', false) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'card_mbway_not_enabled');
  END IF;

  -- 3. o pedido existe e e do proprio?
  SELECT * INTO v_b FROM carwash_bookings WHERE id = p_booking_id;
  IF v_b.id IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'error', 'booking_not_found');
  END IF;
  IF v_b.client_user_id <> p_user_id THEN
    RETURN jsonb_build_object('ok', false, 'error', 'booking_not_yours');
  END IF;

  -- 4. ainda por pagar?
  IF v_b.payment_status <> 'unpaid' THEN
    RETURN jsonb_build_object('ok', false, 'error', 'already_paid',
                              'payment_status', v_b.payment_status);
  END IF;

  -- 5. o pedido ainda esta vivo?
  IF v_b.status IN ('completed', 'cancelled_client') THEN
    RETURN jsonb_build_object('ok', false, 'error', 'booking_closed', 'status', v_b.status);
  END IF;

  -- 6. o servico continua a existir e ligado (carwash_quote rebenta se nao)
  BEGIN
    v_quote := public.carwash_quote(v_b.service_type);
  EXCEPTION WHEN OTHERS THEN
    RETURN jsonb_build_object('ok', false, 'error', 'service_not_available');
  END;

  -- 7. o PRECO gravado bate com o preco de agora? (nunca cobrar valor velho)
  IF (v_quote ->> 'total_cents')::int <> v_b.total_cents THEN
    RETURN jsonb_build_object('ok', false, 'error', 'price_changed',
                              'gravado', v_b.total_cents,
                              'agora', (v_quote ->> 'total_cents')::int);
  END IF;

  -- 8. a morada continua dentro da zona de servico
  IF v_b.lat IS NOT NULL AND v_b.lng IS NOT NULL THEN
    v_dist := public._carwash_distance_km(v_blat, v_blng, v_b.lat, v_b.lng);
    IF v_dist > v_radius THEN
      RETURN jsonb_build_object('ok', false, 'error', 'out_of_service_area',
                                'km', round(v_dist::numeric, 1));
    END IF;
  END IF;

  -- 9. minimo da Stripe
  IF v_b.total_cents < 50 THEN
    RETURN jsonb_build_object('ok', false, 'error', 'amount_below_minimum');
  END IF;

  RETURN jsonb_build_object(
    'ok', true,
    'amount_cents', v_b.total_cents,
    'payment_method', v_b.payment_method,
    'service_type', v_b.service_type,
    'plate', v_b.plate
  );
END $fn$;

-- So a Edge (service_role) a chama. Nunca a app directamente.
REVOKE ALL ON FUNCTION public.carwash_payment_precheck(uuid,uuid) FROM PUBLIC, anon, authenticated;
