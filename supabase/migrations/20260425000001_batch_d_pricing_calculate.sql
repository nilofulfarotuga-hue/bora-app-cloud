-- ============================================================
-- Batch D — pricing_calculate() rewrite
-- 2026-04-25
--
-- Changes:
--   • Partner commission split: 10% visible + 5% service fee + 5% hidden markup
--   • Partner stacking bonus: +€3 driver (isStackedPartnerBonus)
--   • Non-partner: conditional €0.80 (storeShopping only, not restaurant)
--   • Non-partner: driver gets 30% of Bora net profit
--   • Logistics (carry/send): adds €0.80 shopping bonus
-- ============================================================

CREATE OR REPLACE FUNCTION pricing_calculate(
  p_service_type        TEXT,
  p_subtotal            NUMERIC,
  p_distance_km         NUMERIC,
  p_is_partner_store    BOOLEAN DEFAULT FALSE,
  p_apartment_delivery  BOOLEAN DEFAULT FALSE,
  p_is_stacked_partner  BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
  delivery_fee           NUMERIC,
  service_fee            NUMERIC,
  platform_commission    NUMERIC,
  driver_earnings        NUMERIC,
  customer_total         NUMERIC,
  partner_markup_hidden  NUMERIC
)
LANGUAGE plpgsql IMMUTABLE
AS $$
DECLARE
  -- Base constants
  c_driver_base_pay              CONSTANT NUMERIC := 3.80;
  c_driver_per_km                CONSTANT NUMERIC := 0.20;

  -- Partner
  c_partner_delivery_base        CONSTANT NUMERIC := 2.50;
  c_partner_commission_rate      CONSTANT NUMERIC := 0.10;  -- visible to partner
  c_partner_service_fee_rate     CONSTANT NUMERIC := 0.05;  -- charged to client
  c_partner_markup_hidden_rate   CONSTANT NUMERIC := 0.05;  -- embedded in prices
  c_partner_stacking_bonus       CONSTANT NUMERIC := 3.00;

  -- Non-partner
  c_non_partner_markup_rate      CONSTANT NUMERIC := 0.15;
  c_non_partner_purchase_fee     CONSTANT NUMERIC := 2.50;
  c_shopping_driver_bonus        CONSTANT NUMERIC := 0.80;  -- storeShopping / carry / send
  c_driver_profit_share_rate     CONSTANT NUMERIC := 0.30;

  -- Logistics (carryGroceries / sendPackage)
  c_logistics_driver_base_pay    CONSTANT NUMERIC := 4.00;
  c_logistics_driver_per_km      CONSTANT NUMERIC := 0.50;
  c_package_base_fee             CONSTANT NUMERIC := 6.00;
  c_package_base_distance_km     CONSTANT NUMERIC := 4.00;
  c_package_extra_per_km         CONSTANT NUMERIC := 0.50;
  c_package_platform_share       CONSTANT NUMERIC := 2.00;

  -- Apartment surcharge
  c_apartment_surcharge_total    CONSTANT NUMERIC := 1.50;
  c_apartment_driver_share       CONSTANT NUMERIC := 1.00;
  c_apartment_platform_share     CONSTANT NUMERIC := 0.50;

  -- Restaurant bag fee
  c_restaurant_bag_fee           CONSTANT NUMERIC := 0.30;

  -- Working variables
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
  -- Sanitise inputs
  v_distance  := GREATEST(1.0, COALESCE(p_distance_km, 1.0));
  v_subtotal  := GREATEST(0.0, ROUND(COALESCE(p_subtotal, 0.0), 2));

  v_apt_surcharge := CASE WHEN p_apartment_delivery THEN c_apartment_surcharge_total ELSE 0 END;
  v_apt_driver    := CASE WHEN p_apartment_delivery THEN c_apartment_driver_share    ELSE 0 END;
  v_apt_platform  := CASE WHEN p_apartment_delivery THEN c_apartment_platform_share  ELSE 0 END;

  v_is_partner_order := p_is_partner_store AND p_service_type IN ('restaurant','storeShopping');
  v_is_package       := p_service_type IN ('sendPackage','carryGroceries');
  v_is_non_partner   := NOT p_is_partner_store AND p_service_type IN ('restaurant','storeShopping');

  IF v_is_partner_order THEN
    -- ── PARTNER ORDER ──────────────────────────────────────────────────────
    -- 10% visible commission + 5% client service fee + 5% hidden in prices
    v_extra_dist          := GREATEST(0, v_distance - c_package_base_distance_km);
    v_delivery_fee        := c_partner_delivery_base + (v_extra_dist * c_package_extra_per_km) + v_apt_surcharge;
    v_service_fee         := ROUND(v_subtotal * c_partner_service_fee_rate, 2);
    v_platform_commission := ROUND(v_subtotal * c_partner_commission_rate, 2) + v_apt_platform;
    v_partner_markup_hidden := ROUND(v_subtotal * c_partner_markup_hidden_rate, 2);
    v_driver_earnings     := ROUND(
      c_driver_base_pay
      + (c_driver_per_km * v_distance)
      + v_apt_driver
      + CASE WHEN p_is_stacked_partner THEN c_partner_stacking_bonus ELSE 0 END,
    2);

  ELSIF v_is_non_partner THEN
    -- ── NON-PARTNER ORDER ──────────────────────────────────────────────────
    -- 15% markup already in product prices; €2.50 purchase fee = service_fee
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
      -- €0.80 only for storeShopping (they shop AND deliver). Restaurant drivers don't shop.
      v_shopping_bonus := CASE WHEN p_service_type = 'storeShopping' THEN c_shopping_driver_bonus ELSE 0 END;
      v_driver_fixed   := ROUND(c_driver_base_pay + v_shopping_bonus + (c_driver_per_km * v_distance) + v_apt_driver, 2);

      -- 30% of Bora net profit share
      v_bora_markup := ROUND(v_subtotal * c_non_partner_markup_rate, 2);
      v_bora_gross  := v_bora_markup + v_delivery_fee + v_service_fee;
      v_bora_net    := GREATEST(0, v_bora_gross - v_driver_fixed);
      v_driver_earnings := ROUND(v_driver_fixed + ROUND(v_bora_net * c_driver_profit_share_rate, 2), 2);
    END;

  ELSIF v_is_package THEN
    -- ── LOGISTICS (carryGroceries / sendPackage) ───────────────────────────
    -- Logistics drivers carry/collect AND deliver → €0.80 bonus applies.
    v_extra_dist          := GREATEST(0, v_distance - c_package_base_distance_km);
    v_delivery_fee        := c_package_base_fee + (v_extra_dist * c_package_extra_per_km) + v_apt_surcharge;
    v_platform_commission := c_package_platform_share + v_apt_platform;
    v_driver_earnings     := ROUND(
      c_logistics_driver_base_pay
      + (c_logistics_driver_per_km * v_distance)
      + c_shopping_driver_bonus
      + v_apt_driver,
    2);

  ELSE
    -- ── FALLBACK ───────────────────────────────────────────────────────────
    v_delivery_fee        := c_partner_delivery_base + v_apt_surcharge;
    v_platform_commission := ROUND(v_subtotal * c_partner_commission_rate, 2) + v_apt_platform;
    v_driver_earnings     := ROUND(c_driver_base_pay + (c_driver_per_km * v_distance) + v_apt_driver, 2);
  END IF;

  -- Bag fee: restaurant orders only
  v_bag_fee := CASE WHEN p_service_type = 'restaurant' THEN c_restaurant_bag_fee ELSE 0 END;

  RETURN QUERY SELECT
    ROUND(v_delivery_fee, 2),
    ROUND(v_service_fee, 2),
    ROUND(v_platform_commission, 2),
    ROUND(v_driver_earnings, 2),
    ROUND(v_subtotal + v_service_fee + v_delivery_fee + v_bag_fee, 2),
    ROUND(v_partner_markup_hidden, 2);
END;
$$;
