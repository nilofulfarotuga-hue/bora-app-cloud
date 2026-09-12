-- S3: pricing_calculate refactor — reads constants from platform_settings.
-- Strategy: parallel v2 + smoke tests + atomic rename switchover. Legacy
-- function kept as pricing_calculate_legacy_pre_settings for emergency rollback.
--
-- 49/49 smoke cenários (partner/non-partner/logistics/edge cases) produced
-- byte-identical JSON output for v1 vs v2 BEFORE switchover.

-- Seed missing constants into platform_settings.
INSERT INTO platform_settings (key, value, description, category) VALUES
  ('apartment_surcharge_total_cents', '150'::jsonb, 'Apartment delivery total surcharge (cents)', 'delivery'),
  ('apartment_driver_share_cents', '100'::jsonb, 'Apartment driver share (cents)', 'delivery'),
  ('apartment_platform_share_cents', '50'::jsonb, 'Apartment Bora share (cents)', 'delivery'),
  ('logistics_driver_base_cents', '400'::jsonb, 'sendPackage / carryGroceries driver base (cents)', 'drivers'),
  ('logistics_driver_per_km_cents', '50'::jsonb, 'Logistics driver per km (cents)', 'drivers'),
  ('package_base_fee_cents', '600'::jsonb, 'sendPackage base fee (cents)', 'delivery'),
  ('package_platform_share_cents', '200'::jsonb, 'sendPackage Bora share (cents)', 'delivery')
ON CONFLICT (key) DO NOTHING;

-- pricing_calculate_v2 (settings-driven). After verification, this gets
-- renamed to `pricing_calculate` (atomic switchover).
CREATE OR REPLACE FUNCTION public.pricing_calculate(
  p_service_type text,
  p_subtotal numeric,
  p_distance_km numeric,
  p_is_partner_store boolean DEFAULT false,
  p_apartment_delivery boolean DEFAULT false,
  p_is_stacked_partner boolean DEFAULT false
)
RETURNS TABLE (
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
    v_driver_earnings       := ROUND(c_driver_base_pay + (c_driver_per_km * v_distance) + v_apt_driver
                                + CASE WHEN p_is_stacked_partner THEN c_partner_stacking_bonus ELSE 0 END, 2);

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

  v_bag_fee := CASE WHEN p_service_type = 'restaurant' THEN c_restaurant_bag_fee ELSE 0 END;

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

COMMENT ON FUNCTION public.pricing_calculate(text, numeric, numeric, boolean, boolean, boolean) IS
  'Reads pricing constants from platform_settings (S3 cutover 2026-04-30). Rollback: rename pricing_calculate -> pricing_calculate_v2_broken, pricing_calculate_legacy_pre_settings -> pricing_calculate.';
