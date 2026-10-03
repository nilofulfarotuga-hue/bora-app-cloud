-- ============================================================================
-- BORA — FASE 2: cash settlement + driver_transactions standardização
-- ============================================================================
-- BUG A: apply_driver_cash_settlement usava NEW.final_purchase_value
--        (sempre NULL) → delta = final_total inteiro. Bora cobrava cash todo.
-- BUG B: driver_transactions.amount sem convenção de sinal → soma errada.
-- BUG C: fn_credit_driver_on_delivery inseria delivery_fee em vez de
--        driver_earnings (subestima ganho do estafeta).
--
-- Convenção:
--   driver_transactions.amount = SEMPRE POSITIVO (>=0)
--   type indica direcção:
--     'delivery_earning' → Bora deve ao driver (balance +=)
--     'cash_adjustment'  → driver deve à Bora (balance -=)
--
-- UNIQUE(order_id) substituído por UNIQUE(order_id, type) — permite 2 rows
-- por order (earning + adjustment).
-- ============================================================================

BEGIN;

-- ── 1) Composite unique (permite 2 rows por order) ─────────────────────────
ALTER TABLE public.driver_transactions
  DROP CONSTRAINT IF EXISTS driver_transactions_order_id_key;
DROP INDEX IF EXISTS public.driver_transactions_order_id_key;

CREATE UNIQUE INDEX IF NOT EXISTS driver_transactions_order_id_type_key
  ON public.driver_transactions (order_id, type);

-- ── 2) apply_driver_cash_settlement — usa driver_earnings + sinal balance ──
CREATE OR REPLACE FUNCTION public.apply_driver_cash_settlement()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_driver_uuid     UUID;
  v_total           NUMERIC;
  v_driver_earnings NUMERIC;
  v_delta_due       NUMERIC;
BEGIN
  IF NEW.status IS DISTINCT FROM 'delivered' THEN RETURN NEW; END IF;
  IF OLD.status = 'delivered' THEN RETURN NEW; END IF;
  IF NEW.payment_method IS DISTINCT FROM 'cash' THEN RETURN NEW; END IF;

  IF NEW.assigned_driver_id IS NULL THEN
    RAISE WARNING 'apply_driver_cash_settlement: order % has no assigned_driver_id — skipping', NEW.id;
    RETURN NEW;
  END IF;

  BEGIN
    v_driver_uuid := NEW.assigned_driver_id::UUID;
  EXCEPTION WHEN invalid_text_representation THEN
    RAISE WARNING 'apply_driver_cash_settlement: assigned_driver_id % is not a UUID — skipping', NEW.assigned_driver_id;
    RETURN NEW;
  END;

  v_total           := COALESCE(NEW.final_total, NEW.price, 0);
  v_driver_earnings := COALESCE(NEW.driver_earnings, 0);
  -- Driver recebeu v_total em cash, fica com earnings, devolve resto à Bora.
  v_delta_due := GREATEST(ROUND(v_total - v_driver_earnings, 2), 0);

  IF v_delta_due > 0 THEN
    BEGIN
      INSERT INTO public.driver_transactions (driver_id, order_id, amount, type)
      VALUES (v_driver_uuid, NEW.id::UUID, v_delta_due, 'cash_adjustment');
    EXCEPTION WHEN unique_violation THEN
      RAISE NOTICE 'apply_driver_cash_settlement: order % already settled — skipping', NEW.id;
      RETURN NEW;
    END;

    INSERT INTO public.driver_balances (driver_id, balance, updated_at)
    VALUES (v_driver_uuid, -v_delta_due, now())
    ON CONFLICT (driver_id) DO UPDATE
      SET balance    = public.driver_balances.balance - v_delta_due,
          updated_at = now();
  END IF;

  RETURN NEW;
END;
$function$;

-- ── 3) fn_credit_driver_on_delivery — driver_earnings + composite conflict ─
CREATE OR REPLACE FUNCTION public.fn_credit_driver_on_delivery()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
AS $function$
DECLARE
  v_earnings NUMERIC;
BEGIN
  IF NEW.status = 'delivered'
    AND (OLD.status IS DISTINCT FROM 'delivered')
    AND NEW.assigned_driver_id IS NOT NULL
  THEN
    v_earnings := COALESCE(NEW.driver_earnings, 0);
    IF v_earnings > 0 THEN
      INSERT INTO driver_transactions (driver_id, order_id, amount, type, status)
      VALUES (NEW.assigned_driver_id::uuid, NEW.id::uuid, v_earnings,
              'delivery_earning', 'completed')
      ON CONFLICT (order_id, type) DO NOTHING;

      INSERT INTO driver_balances (driver_id, balance, updated_at)
      VALUES (NEW.assigned_driver_id::uuid, v_earnings, NOW())
      ON CONFLICT (driver_id)
      DO UPDATE SET
        balance    = driver_balances.balance + EXCLUDED.balance,
        updated_at = NOW();
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

-- ── 4) post_order_to_ledger — cash_adj usa driver_earnings ─────────────────
CREATE OR REPLACE FUNCTION public.post_order_to_ledger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_driver           TEXT;
  v_total            NUMERIC(12, 2);
  v_base             NUMERIC(12, 2);
  v_driver_earn      NUMERIC(12, 2);
  v_cash_adj         NUMERIC(12, 2);
  v_restaurant_earn  NUMERIC(12, 2);
  v_platform_comm    NUMERIC(12, 2);
  v_vendor_ref       TEXT;
  v_is_partner       BOOLEAN;
  v_is_cash          BOOLEAN;
BEGIN
  IF NEW.status IS DISTINCT FROM 'delivered'    THEN RETURN NEW; END IF;
  IF OLD.status = 'delivered'                   THEN RETURN NEW; END IF;
  IF NEW.payment_status IS DISTINCT FROM 'paid' THEN RETURN NEW; END IF;

  v_driver     := NEW.assigned_driver_id;
  v_is_partner := COALESCE(NEW.is_partner_store, false);
  v_is_cash    := (NEW.payment_method = 'cash');
  v_total      := ROUND(COALESCE(NEW.final_total, NEW.price, 0)::NUMERIC, 2);
  v_base       := ROUND(COALESCE(NEW.subtotal, 0)::NUMERIC, 2);

  v_driver_earn := ROUND(COALESCE(NEW.driver_earnings, 0)::NUMERIC, 2);
  IF v_driver IS NOT NULL AND v_driver_earn > 0 THEN
    INSERT INTO public.ledger_entries (user_id, user_type, order_id, amount, type, reference)
    VALUES (v_driver, 'driver', NEW.id::UUID, v_driver_earn, 'earning', 'delivery_earning')
    ON CONFLICT (order_id, user_id, type, reference) DO NOTHING;
  END IF;

  IF v_driver IS NOT NULL AND v_is_cash THEN
    -- Sinal NEGATIVO em ledger = driver deve à Bora.
    v_cash_adj := -GREATEST(ROUND(v_total - v_driver_earn, 2), 0);
    IF v_cash_adj <> 0 THEN
      INSERT INTO public.ledger_entries (user_id, user_type, order_id, amount, type, reference)
      VALUES (v_driver, 'driver', NEW.id::UUID, v_cash_adj, 'cash_adjustment', 'cash_adjustment')
      ON CONFLICT (order_id, user_id, type, reference) DO NOTHING;
    END IF;
  END IF;

  IF v_is_partner THEN
    SELECT id::TEXT INTO v_vendor_ref
    FROM public.restaurants
    WHERE name = COALESCE(NEW.vendor_name, '')
    LIMIT 1;

    IF v_vendor_ref IS NULL THEN
      v_vendor_ref := COALESCE(NEW.vendor_name, 'unknown');
    END IF;

    v_restaurant_earn := ROUND(v_base * 0.90, 2);
    v_platform_comm   := ROUND(v_base - v_restaurant_earn, 2);

    IF v_restaurant_earn > 0 THEN
      INSERT INTO public.ledger_entries (user_id, user_type, order_id, amount, type, reference)
      VALUES (v_vendor_ref, 'restaurant', NEW.id::UUID, v_restaurant_earn, 'earning', 'partner_share')
      ON CONFLICT (order_id, user_id, type, reference) DO NOTHING;
    END IF;

    IF v_platform_comm > 0 THEN
      INSERT INTO public.ledger_entries (user_id, user_type, order_id, amount, type, reference)
      VALUES ('platform', 'platform', NEW.id::UUID, v_platform_comm, 'commission', 'partner_commission')
      ON CONFLICT (order_id, user_id, type, reference) DO NOTHING;
    END IF;
  ELSE
    v_platform_comm := ROUND(COALESCE(NEW.platform_commission, 0)::NUMERIC, 2);
    IF v_platform_comm > 0 THEN
      INSERT INTO public.ledger_entries (user_id, user_type, order_id, amount, type, reference)
      VALUES ('platform', 'platform', NEW.id::UUID, v_platform_comm, 'commission', 'service_commission')
      ON CONFLICT (order_id, user_id, type, reference) DO NOTHING;
    END IF;
  END IF;

  RETURN NEW;
END;
$function$;

-- ── 5) Convention comment ──────────────────────────────────────────────────
COMMENT ON COLUMN public.driver_transactions.amount IS
  'Montante absoluto SEMPRE POSITIVO (>=0). type indica direcção: '
  'delivery_earning = Bora deve ao driver (balance +=), '
  'cash_adjustment = driver deve à Bora (balance -=).';

COMMIT;
