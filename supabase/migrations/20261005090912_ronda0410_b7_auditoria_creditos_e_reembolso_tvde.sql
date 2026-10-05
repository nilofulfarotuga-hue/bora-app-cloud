-- Ronda 04/10 Bloco B item 7: auditoria em admin_mark_partner_credits_paid e admin_tvde_refund_ride.
-- Ambas passam a deixar linha em admin_audit_log (a tabela que as outras admin_* usam).
-- admin_mark_partner_credits_paid verificava admin por raw_user_meta_data->>'bora_role'
-- (metadados que o proprio utilizador pode editar) -> passa a public.is_admin().
-- Nenhum valor muda.

CREATE OR REPLACE FUNCTION public.admin_mark_partner_credits_paid(p_restaurant_id text, p_week_start timestamp with time zone, p_week_end timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin_id uuid := auth.uid();
  result     jsonb;
BEGIN
  IF v_admin_id IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'admin_only';
  END IF;

  WITH updated AS (
    UPDATE public.restaurant_menu_credits
    SET paid_to_partner_at = NOW(),
        paid_to_partner_by = v_admin_id
    WHERE restaurant_id = p_restaurant_id
      AND used_at IS NOT NULL
      AND paid_to_partner_at IS NULL
      AND used_at >= p_week_start
      AND used_at <  p_week_end
    RETURNING amount_cents
  )
  SELECT jsonb_build_object(
    'success', true,
    'count', COUNT(*),
    'total_cents', COALESCE(SUM(amount_cents), 0)
  ) INTO result FROM updated;

  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
  VALUES (v_admin_id, COALESCE(auth.jwt() ->> 'email', auth.jwt() -> 'user_metadata' ->> 'email'),
          'partner_credits_marked_paid', 'restaurant', p_restaurant_id,
          jsonb_build_object('week_start', p_week_start, 'week_end', p_week_end,
                             'count', result->'count', 'total_cents', result->'total_cents'));

  RETURN result;
END;
$function$;

CREATE OR REPLACE FUNCTION public.admin_tvde_refund_ride(p_ride_id uuid, p_valor_cents integer DEFAULT NULL::integer)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'vault'
AS $function$
DECLARE v_key text; v_url text; v_ride public.tvde_rides; v_pi text;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  SELECT * INTO v_ride FROM public.tvde_rides WHERE id = p_ride_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  v_pi := v_ride.payment_intent_id;
  IF v_pi IS NULL AND v_ride.roundtrip_credit_id IS NOT NULL THEN
    SELECT payment_intent_id INTO v_pi FROM public.tvde_roundtrip_credits WHERE id = v_ride.roundtrip_credit_id;
  END IF;
  IF v_pi IS NULL THEN RAISE EXCEPTION 'sem_pagamento_online'; END IF;

  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name='service_role_key';
  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name='project_url';
  IF v_key IS NULL THEN RAISE EXCEPTION 'sem_service_role_key'; END IF;

  PERFORM net.http_post(
    url := COALESCE(v_url,'https://ojykpzwqrtusfeakzrna.supabase.co') || '/functions/v1/tvde-payment',
    headers := jsonb_build_object('Content-Type','application/json','Authorization','Bearer '||v_key),
    body := jsonb_build_object('action','auto_refund_ride','ride_id', p_ride_id::text,
                               'motivo','reembolso pedido pelo admin no painel',
                               'valor_cents', COALESCE(p_valor_cents, 0)));

  INSERT INTO public.tvde_ride_events (ride_id, status, actor, meta)
    VALUES (p_ride_id, 'reembolso_pedido', 'admin',
            jsonb_build_object('motivo','pedido no painel','valor_cents', p_valor_cents, 'payment_intent', v_pi));

  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id, entity_id_text, details)
  VALUES (auth.uid(), COALESCE(auth.jwt() ->> 'email', auth.jwt() -> 'user_metadata' ->> 'email'),
          'tvde_reembolso_pedido', 'tvde_ride', p_ride_id, p_ride_id::text,
          jsonb_build_object('valor_cents', p_valor_cents, 'total', p_valor_cents IS NULL,
                             'payment_intent', v_pi, 'cliente', v_ride.client_id,
                             'tarifa_cents', COALESCE(v_ride.final_fare_cents, v_ride.est_fare_cents)));
  RETURN true;
END $function$;
