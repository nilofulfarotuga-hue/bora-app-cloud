-- 2026-05-16 — Fix stacked driver earnings (partner +€3.00 only; non-partner +€3.00 + 30% commission)
--
-- BUSINESS RULE (canonical, set by Danilo 2026-05-16):
--   1st order (any kind): normal calculation (€3.80 + €0.20×km + bonuses).
--   2nd / 3rd order STACKED for PARTNER (is_partner_store=true):
--     driver_earnings = €3.00 + apt_driver_share
--   2nd / 3rd order STACKED for NON-PARTNER (is_partner_store=false):
--     driver_earnings = €3.00 + 0.30 × platform_commission + apt_driver_share
--
-- IMPLEMENTATION:
--   1. Fix pricing_calculate(): partner branch now correctly returns only the
--      bonus (was: base + km + bonus — mathematically wrong).
--   2. New RPC recalc_driver_earnings_on_stack(p_order_id, p_driver_id): computes
--      the stacked earnings directly (handles partner + non-partner).
--   3. New trigger trg_recalc_earnings_on_assign on orders: fires AFTER UPDATE
--      when assigned_driver_id transitions NULL → not-NULL. Calls the RPC.
--      DB-side trigger chosen over Edge Function hook because:
--        - dispatch-engine only sets current_driver_offer_id (offer, not assignment).
--        - The actual assignment happens via direct UPDATE from Flutter
--          (order_store.dart:1399 and :2712).
--        - A trigger covers all paths (Flutter, RPC, admin, future agents).

-- ─────────────────────────────────────────────────────────────────────────────
-- 1) pricing_calculate: fix partner branch (stacked = bonus only, not base+km+bonus)
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.pricing_calculate(
  p_service_type text,
  p_subtotal numeric,
  p_distance_km numeric,
  p_is_partner_store boolean DEFAULT false,
  p_apartment_delivery boolean DEFAULT false,
  p_is_stacked_partner boolean DEFAULT false,
  p_bag_count integer DEFAULT 0
) RETURNS TABLE(
  delivery_fee numeric,
  service_fee numeric,
  platform_commission numeric,
  driver_earnings numeric,
  customer_total numeric,
  partner_markup_hidden numeric,
  bag_fee numeric
)
LANGUAGE plpgsql
STABLE
AS $function$
DECLARE
  v_settings jsonb;
  c_driver_base_pay              NUMERIC;
  c_driver_per_km                NUMERIC;
  c_partner_delivery_base        NUMERIC;
  c_partner_commission_rate      NUMERIC;
  c_partner_service_fee_rate     NUMERIC;
  c_partner_markup_hidden_rate   NUMERIC;
  c_partner_stacking_bonus       NUMERIC;
  c_non_partner_markup_rate      NUMERIC;
  c_non_partner_purchase_fee     NUMERIC;
  c_shopping_driver_bonus        NUMERIC;
  c_driver_profit_share_rate     NUMERIC;
  c_logistics_driver_base_pay    NUMERIC;
  c_logistics_driver_per_km      NUMERIC;
  c_package_base_fee             NUMERIC;
  c_package_base_distance_km     NUMERIC;
  c_package_extra_per_km         NUMERIC;
  c_package_platform_share       NUMERIC;
  c_apartment_surcharge_total    NUMERIC;
  c_apartment_driver_share       NUMERIC;
  c_apartment_platform_share     NUMERIC;
  c_restaurant_bag_fee           NUMERIC;
  c_supermarket_bag_fee_per_bag  NUMERIC;

  v_distance       NUMERIC;
  v_subtotal       NUMERIC;
  v_apt_surcharge  NUMERIC;
  v_apt_driver     NUMERIC;
  v_apt_platform   NUMERIC;
  v_extra_dist     NUMERIC;

  v_delivery_fee          NUMERIC := 0;
  v_service_fee           NUMERIC := 0;
  v_platform_commission   NUMERIC := 0;
  v_driver_earnings       NUMERIC := 0;
  v_partner_markup_hidden NUMERIC := 0;
  v_bag_fee               NUMERIC := 0;

  v_is_partner_order BOOLEAN;
  v_is_package       BOOLEAN;
  v_is_non_partner   BOOLEAN;
BEGIN
  SELECT jsonb_object_agg(key, value) INTO v_settings FROM platform_settings;

  c_driver_base_pay              := ((v_settings->>'driver_base_fee_cents')::NUMERIC) / 100.0;
  c_driver_per_km                := ((v_settings->>'driver_per_km_cents')::NUMERIC) / 100.0;
  c_partner_delivery_base        := ((v_settings->>'delivery_base_fee_cents')::NUMERIC) / 100.0;
  c_partner_commission_rate      := (v_settings->>'partner_visible_commission_pct')::NUMERIC;
  c_partner_service_fee_rate     := (v_settings->>'client_service_fee_pct')::NUMERIC;
  c_partner_markup_hidden_rate   := (v_settings->>'partner_hidden_markup_pct')::NUMERIC;
  c_partner_stacking_bonus       := ((v_settings->>'partner_driver_stacking_bonus_cents')::NUMERIC) / 100.0;
  c_non_partner_markup_rate      := (v_settings->>'non_partner_markup_pct')::NUMERIC;
  c_non_partner_purchase_fee     := ((v_settings->>'delivery_base_fee_cents')::NUMERIC) / 100.0;
  c_shopping_driver_bonus        := ((v_settings->>'driver_surcharge_cents')::NUMERIC) / 100.0;
  c_driver_profit_share_rate     := (v_settings->>'driver_profit_share_pct')::NUMERIC;
  c_logistics_driver_base_pay    := ((v_settings->>'logistics_driver_base_cents')::NUMERIC) / 100.0;
  c_logistics_driver_per_km      := ((v_settings->>'logistics_driver_per_km_cents')::NUMERIC) / 100.0;
  c_package_base_fee             := ((v_settings->>'package_base_fee_cents')::NUMERIC) / 100.0;
  c_package_base_distance_km     := (v_settings->>'delivery_base_distance_km')::NUMERIC;
  c_package_extra_per_km         := ((v_settings->>'delivery_per_km_cents')::NUMERIC) / 100.0;
  c_package_platform_share       := ((v_settings->>'package_platform_share_cents')::NUMERIC) / 100.0;
  c_apartment_surcharge_total    := ((v_settings->>'apartment_surcharge_total_cents')::NUMERIC) / 100.0;
  c_apartment_driver_share       := ((v_settings->>'apartment_driver_share_cents')::NUMERIC) / 100.0;
  c_apartment_platform_share     := ((v_settings->>'apartment_platform_share_cents')::NUMERIC) / 100.0;
  c_restaurant_bag_fee           := ((v_settings->>'bag_fee_restaurant_cents')::NUMERIC) / 100.0;
  c_supermarket_bag_fee_per_bag  := ((v_settings->>'bag_fee_supermarket_per_bag_cents')::NUMERIC) / 100.0;

  v_distance := GREATEST(1.0, COALESCE(p_distance_km, 1.0));
  v_subtotal := GREATEST(0.0, ROUND(COALESCE(p_subtotal, 0.0), 2));

  v_apt_surcharge := CASE WHEN p_apartment_delivery THEN c_apartment_surcharge_total ELSE 0 END;
  v_apt_driver    := CASE WHEN p_apartment_delivery THEN c_apartment_driver_share    ELSE 0 END;
  v_apt_platform  := CASE WHEN p_apartment_delivery THEN c_apartment_platform_share  ELSE 0 END;

  v_is_partner_order := p_is_partner_store AND p_service_type IN ('restaurant','storeShopping');
  v_is_package       := p_service_type IN ('sendPackage','carryGroceries');
  v_is_non_partner   := NOT p_is_partner_store AND p_service_type IN ('restaurant','storeShopping');

  IF v_is_partner_order THEN
    v_extra_dist            := GREATEST(0, v_distance - c_package_base_distance_km);
    v_delivery_fee          := c_partner_delivery_base + (v_extra_dist * c_package_extra_per_km) + v_apt_surcharge;
    v_service_fee           := ROUND(v_subtotal * c_partner_service_fee_rate, 2);
    v_platform_commission   := ROUND(v_subtotal * c_partner_commission_rate, 2) + v_apt_platform;
    v_partner_markup_hidden := ROUND(v_subtotal * c_partner_markup_hidden_rate, 2);
    -- 2026-05-16 FIX: stacked = bonus ONLY (was base+km+bonus, mathematically wrong).
    IF p_is_stacked_partner THEN
      v_driver_earnings := ROUND(c_partner_stacking_bonus + v_apt_driver, 2);
    ELSE
      v_driver_earnings := ROUND(c_driver_base_pay + (c_driver_per_km * v_distance) + v_apt_driver, 2);
    END IF;

  ELSIF v_is_non_partner THEN
    v_extra_dist          := GREATEST(0, v_distance - c_package_base_distance_km);
    v_service_fee         := c_non_partner_purchase_fee;
    v_delivery_fee        := c_partner_delivery_base + (v_extra_dist * c_package_extra_per_km) + v_apt_surcharge;
    v_platform_commission := c_non_partner_purchase_fee + v_apt_platform;

    DECLARE
      v_shopping_bonus NUMERIC;
      v_driver_fixed   NUMERIC;
      v_bora_markup    NUMERIC;
      v_bora_gross     NUMERIC;
      v_bora_net       NUMERIC;
    BEGIN
      v_shopping_bonus := CASE WHEN p_service_type = 'storeShopping' THEN c_shopping_driver_bonus ELSE 0 END;
      v_driver_fixed   := ROUND(c_driver_base_pay + v_shopping_bonus + (c_driver_per_km * v_distance) + v_apt_driver, 2);
      v_bora_markup    := ROUND(v_subtotal * c_non_partner_markup_rate, 2);
      v_bora_gross     := v_bora_markup + v_delivery_fee + v_service_fee;
      v_bora_net       := GREATEST(0, v_bora_gross - v_driver_fixed);
      v_driver_earnings := ROUND(v_driver_fixed + ROUND(v_bora_net * c_driver_profit_share_rate, 2), 2);
    END;

  ELSIF v_is_package THEN
    v_extra_dist          := GREATEST(0, v_distance - c_package_base_distance_km);
    v_delivery_fee        := c_package_base_fee + (v_extra_dist * c_package_extra_per_km) + v_apt_surcharge;
    v_platform_commission := c_package_platform_share + v_apt_platform;
    v_driver_earnings     := ROUND(c_logistics_driver_base_pay + (c_logistics_driver_per_km * v_distance) + c_shopping_driver_bonus + v_apt_driver, 2);

  ELSE
    v_delivery_fee        := c_partner_delivery_base + v_apt_surcharge;
    v_platform_commission := ROUND(v_subtotal * c_partner_commission_rate, 2) + v_apt_platform;
    v_driver_earnings     := ROUND(c_driver_base_pay + (c_driver_per_km * v_distance) + v_apt_driver, 2);
  END IF;

  v_bag_fee := CASE
    WHEN p_service_type = 'restaurant' THEN c_restaurant_bag_fee
    WHEN p_service_type = 'storeShopping' THEN c_supermarket_bag_fee_per_bag * GREATEST(1, p_bag_count)
    ELSE 0
  END;

  RETURN QUERY SELECT
    ROUND(v_delivery_fee, 2),
    ROUND(v_service_fee, 2),
    ROUND(v_platform_commission, 2),
    ROUND(v_driver_earnings, 2),
    ROUND(v_subtotal + v_service_fee + v_delivery_fee + v_bag_fee, 2),
    ROUND(v_partner_markup_hidden, 2),
    ROUND(v_bag_fee, 2);
END;
$function$;

-- ─────────────────────────────────────────────────────────────────────────────
-- 2) RPC recalc_driver_earnings_on_stack
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.recalc_driver_earnings_on_stack(
  p_order_id text,
  p_driver_id text
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_order            public.orders%ROWTYPE;
  v_active_count     int;
  v_settings         jsonb;
  c_bonus            numeric;
  c_apt_driver_share numeric;
  v_apt_driver       numeric;
  v_new_earnings     numeric;
  v_old_earnings     numeric;
BEGIN
  SELECT * INTO v_order FROM public.orders WHERE id = p_order_id;
  IF NOT FOUND THEN
    RETURN jsonb_build_object('ok', false, 'error', 'order_not_found');
  END IF;

  v_old_earnings := v_order.driver_earnings;

  -- Count driver's OTHER active orders (excluding this one).
  SELECT COUNT(*) INTO v_active_count
  FROM public.orders
  WHERE assigned_driver_id = p_driver_id
    AND id <> p_order_id
    AND status IN ('driverAccepted','pickedUp','onTheWay');

  IF v_active_count < 1 THEN
    RETURN jsonb_build_object('ok', true, 'not_stacked', true,
                              'active_count', v_active_count);
  END IF;

  -- Stacking detected: compute new earnings.
  SELECT jsonb_object_agg(key, value) INTO v_settings FROM public.platform_settings;
  c_bonus            := ((v_settings->>'partner_driver_stacking_bonus_cents')::numeric) / 100.0;
  c_apt_driver_share := ((v_settings->>'apartment_driver_share_cents')::numeric) / 100.0;
  v_apt_driver       := CASE WHEN COALESCE(v_order.apartment_delivery, false)
                              THEN c_apt_driver_share ELSE 0 END;

  IF v_order.is_partner_store THEN
    -- Partner stacked: bonus only.
    v_new_earnings := ROUND(c_bonus + v_apt_driver, 2);
  ELSE
    -- Non-partner stacked: bonus + 30% of platform_commission.
    v_new_earnings := ROUND(
      c_bonus
      + (0.30 * COALESCE(v_order.platform_commission, 0))
      + v_apt_driver,
    2);
  END IF;

  -- Bypass financial immutability lock for this UPDATE (transactional).
  PERFORM set_config('app.financial_bypass', 'true', true);
  UPDATE public.orders
    SET driver_earnings = v_new_earnings
    WHERE id = p_order_id;

  RETURN jsonb_build_object('ok', true, 'stacked', true,
                            'active_count', v_active_count,
                            'is_partner', v_order.is_partner_store,
                            'old_earnings', v_old_earnings,
                            'new_earnings', v_new_earnings);
END;
$$;

REVOKE ALL ON FUNCTION public.recalc_driver_earnings_on_stack(text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.recalc_driver_earnings_on_stack(text, text) TO service_role;

-- ─────────────────────────────────────────────────────────────────────────────
-- 3) Trigger: auto-fire on assigned_driver_id NULL → not-NULL
-- ─────────────────────────────────────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_recalc_earnings_on_assign()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
BEGIN
  IF OLD.assigned_driver_id IS NULL
     AND NEW.assigned_driver_id IS NOT NULL
  THEN
    PERFORM public.recalc_driver_earnings_on_stack(
      NEW.id, NEW.assigned_driver_id
    );
  END IF;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_recalc_earnings_on_assign ON public.orders;
CREATE TRIGGER trg_recalc_earnings_on_assign
AFTER UPDATE OF assigned_driver_id ON public.orders
FOR EACH ROW
EXECUTE FUNCTION public.fn_recalc_earnings_on_assign();

COMMENT ON FUNCTION public.recalc_driver_earnings_on_stack(text, text) IS
'Recalculates driver_earnings for a stacked order (driver already has >=1 active partner/non-partner order). Partner: +€3.00 only. Non-partner: +€3.00 + 30% × platform_commission. Plus apt_driver_share if applicable.';

COMMENT ON TRIGGER trg_recalc_earnings_on_assign ON public.orders IS
'2026-05-16: auto-recalculates driver_earnings when a driver accepts a 2nd/3rd order (NULL → driver_id). DB-side trigger covers all assignment paths (Flutter UPDATE, RPC, admin).';
