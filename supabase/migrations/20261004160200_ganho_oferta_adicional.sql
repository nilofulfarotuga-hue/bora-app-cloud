-- [ronda 04/10 · app-estafeta #4] Ganho mostrado na oferta de PEDIDO ADICIONAL
-- (estafeta já com pedido em curso). A app tinha a fórmula com constantes
-- próprias (3,00 € + 1,00 € apartamento) — se o Danilo mudasse
-- partner_driver_stacking_bonus_cents ou apartment_driver_share_cents, a
-- oferta mostrava um número e o pedido pagava outro. Esta RPC devolve o MESMO
-- cálculo que `recalc_driver_earnings_on_stack` aplica ao aceitar, só que sem
-- gravar nada (pré-visualização). Só responde ao estafeta a quem o pedido
-- está a ser oferecido (ou que já o tem) e ao admin.
CREATE OR REPLACE FUNCTION public.ganho_oferta_adicional(p_order_id text)
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_order public.orders%ROWTYPE;
  v_active int;
  c_bonus numeric;
  c_apt numeric;
  v_apt numeric;
  v_ganho numeric;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'order_not_found');
  END IF;
  IF NOT (COALESCE(v_order.current_driver_offer_id, '') = v_uid::text
          OR COALESCE(v_order.assigned_driver_id, '') = v_uid::text
          OR public.is_admin()) THEN
    RETURN jsonb_build_object('ok', false, 'error', 'forbidden');
  END IF;

  SELECT count(*) INTO v_active
    FROM public.orders
   WHERE assigned_driver_id = v_uid::text
     AND id <> p_order_id
     AND status IN ('driverAccepted','pickedUp','onTheWay');

  IF v_active < 1 THEN
    -- Não fica empilhado: vale o ganho normal gravado no pedido.
    RETURN jsonb_build_object('ok', true, 'stacked', false,
      'driver_earnings', v_order.driver_earnings);
  END IF;

  SELECT (value #>> '{}')::numeric / 100.0 INTO c_bonus
    FROM public.platform_settings WHERE key = 'partner_driver_stacking_bonus_cents';
  SELECT (value #>> '{}')::numeric / 100.0 INTO c_apt
    FROM public.platform_settings WHERE key = 'apartment_driver_share_cents';
  v_apt := CASE WHEN COALESCE(v_order.apartment_delivery, false)
                THEN COALESCE(c_apt, 0) ELSE 0 END;
  IF v_order.is_partner_store THEN
    v_ganho := ROUND(COALESCE(c_bonus, 0) + v_apt, 2);
  ELSE
    v_ganho := ROUND(COALESCE(c_bonus, 0)
                     + (0.30 * COALESCE(v_order.platform_commission, 0))
                     + v_apt, 2);
  END IF;
  RETURN jsonb_build_object('ok', true, 'stacked', true,
    'active_count', v_active, 'driver_earnings', v_ganho);
END $function$;

REVOKE ALL ON FUNCTION public.ganho_oferta_adicional(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.ganho_oferta_adicional(text) TO authenticated;
