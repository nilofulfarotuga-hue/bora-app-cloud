-- ============================================================================
-- BORA — Order Financial Split (Partner / Platform)
-- ============================================================================
-- PURPOSE:
--   Split the base product amount of partner-restaurant orders 90/10 between
--   the restaurant and the platform, atomically and idempotently.
--
-- RULES:
--   1. Partner orders only (is_partner_store = true).
--   2. Fires only on transition → delivered AND payment_status = 'paid'.
--   3. Uses base_amount — NEVER total_paid (which includes gateway/delivery).
--   4. Idempotent via UNIQUE(order_financials.order_id).
--   5. Atomic: all inserts share the trigger transaction.
--   6. No driver_balances coupling — this system is fully independent.
--
-- NOTE: This module is independent from driver_balances (cash system).
-- Both run AFTER UPDATE of the same column but touch disjoint tables, so
-- Postgres executes them sequentially inside the same UPDATE transaction
-- with full ACID guarantees.
-- ============================================================================

BEGIN;

-- ─── Main ledger: one row per settled order ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.order_financials (
  id                UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id          UUID           NOT NULL UNIQUE,        -- idempotency
  base_amount       NUMERIC(10, 2) NOT NULL CHECK (base_amount >= 0),
  total_paid        NUMERIC(10, 2) NOT NULL CHECK (total_paid >= 0),
  restaurant_amount NUMERIC(10, 2) NOT NULL CHECK (restaurant_amount >= 0),
  platform_amount   NUMERIC(10, 2) NOT NULL CHECK (platform_amount >= 0),
  created_at        TIMESTAMPTZ    NOT NULL DEFAULT now(),
  -- Consistency invariant: the two splits must reconstruct base_amount
  -- (to the cent — both sides are ROUNDed to 2dp in the function).
  CONSTRAINT order_financials_split_invariant
    CHECK (ROUND(restaurant_amount + platform_amount, 2) = ROUND(base_amount, 2))
);

CREATE INDEX IF NOT EXISTS idx_order_financials_created_at
  ON public.order_financials (created_at DESC);

COMMENT ON TABLE public.order_financials IS
  'Financial split ledger — one row per partner order, settled atomically on delivery. UNIQUE(order_id) enforces single settlement.';

-- ─── Audit journal: two rows per order (restaurant, platform) ──────────────
CREATE TABLE IF NOT EXISTS public.order_financial_transactions (
  id         UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  order_id   UUID           NOT NULL,
  type       TEXT           NOT NULL CHECK (type IN ('restaurant', 'platform')),
  amount     NUMERIC(10, 2) NOT NULL CHECK (amount >= 0),
  created_at TIMESTAMPTZ    NOT NULL DEFAULT now(),
  -- A given order can only have ONE row per split type (double idempotency).
  UNIQUE (order_id, type)
);

CREATE INDEX IF NOT EXISTS idx_order_financial_txn_order
  ON public.order_financial_transactions (order_id);

CREATE INDEX IF NOT EXISTS idx_order_financial_txn_type_created
  ON public.order_financial_transactions (type, created_at DESC);

COMMENT ON TABLE public.order_financial_transactions IS
  'Per-party audit journal. Two rows per settled order (restaurant + platform). UNIQUE(order_id, type) blocks double writes.';

-- ─── RLS: zero client write access ──────────────────────────────────────────
ALTER TABLE public.order_financials              ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.order_financial_transactions  ENABLE ROW LEVEL SECURITY;

-- No SELECT policies yet — tables are invisible to authenticated clients.
-- A future admin role can be granted read access explicitly.
-- No INSERT / UPDATE / DELETE policies → no client path can write.
-- The trigger function below runs as SECURITY DEFINER and bypasses RLS.

-- ============================================================================
-- Split function — atomic, idempotent, server-trusted
-- ============================================================================

CREATE OR REPLACE FUNCTION public.apply_order_financial_split()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_base          NUMERIC(10, 2);
  v_total_paid    NUMERIC(10, 2);
  v_restaurant    NUMERIC(10, 2);
  v_platform      NUMERIC(10, 2);
BEGIN
  -- ── Gate 1: must be transitioning INTO delivered ─────────────────────────
  IF NEW.status IS DISTINCT FROM 'delivered' THEN
    RETURN NEW;
  END IF;
  IF OLD.status = 'delivered' THEN
    RETURN NEW;  -- already delivered in a prior update — no-op
  END IF;

  -- ── Gate 2: payment must be confirmed server-side ────────────────────────
  IF NEW.payment_status IS DISTINCT FROM 'paid' THEN
    RAISE NOTICE 'apply_order_financial_split: order % delivered but payment_status=% — skipping split',
      NEW.id, NEW.payment_status;
    RETURN NEW;
  END IF;

  -- ── Gate 3: partner orders only ──────────────────────────────────────────
  IF COALESCE(NEW.is_partner_store, false) IS DISTINCT FROM true THEN
    RETURN NEW;
  END IF;

  -- ── Base amount (the REAL product value) ─────────────────────────────────
  -- Precedence, all partner-safe (none of these include gateway fees):
  --   1. final_purchase_value — actual store cost once reconciled
  --   2. subtotal             — original product subtotal before fees/delivery
  -- NEVER uses final_total / total / paymentBufferTotal (those include fees).
  v_base := ROUND(COALESCE(NEW.final_purchase_value, NEW.subtotal, 0)::NUMERIC, 2);

  IF v_base <= 0 THEN
    RAISE WARNING 'apply_order_financial_split: order % has no base amount — skipping', NEW.id;
    RETURN NEW;
  END IF;

  v_total_paid := ROUND(COALESCE(NEW.final_total, NEW.total, 0)::NUMERIC, 2);

  -- ── 90 / 10 split ────────────────────────────────────────────────────────
  v_restaurant := ROUND(v_base * 0.90, 2);
  -- Platform absorbs the rounding residue so the split invariant always holds.
  v_platform   := ROUND(v_base - v_restaurant, 2);

  -- ── Atomic, idempotent writes ────────────────────────────────────────────
  -- If UNIQUE(order_id) has already been taken, we catch and exit without
  -- touching the journal. All three writes share the UPDATE transaction.
  BEGIN
    INSERT INTO public.order_financials (
      order_id, base_amount, total_paid, restaurant_amount, platform_amount
    ) VALUES (
      NEW.id::UUID, v_base, v_total_paid, v_restaurant, v_platform
    );
  EXCEPTION WHEN unique_violation THEN
    RAISE NOTICE 'apply_order_financial_split: order % already settled — skipping', NEW.id;
    RETURN NEW;
  END;

  INSERT INTO public.order_financial_transactions (order_id, type, amount)
  VALUES
    (NEW.id::UUID, 'restaurant', v_restaurant),
    (NEW.id::UUID, 'platform',   v_platform);

  RAISE NOTICE 'apply_order_financial_split: order=% base=% restaurant=% platform=%',
    NEW.id, v_base, v_restaurant, v_platform;

  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.apply_order_financial_split() IS
  'Splits partner-order base amount 90/10 between restaurant and platform on delivery. Atomic, idempotent, payment-validated, SECURITY DEFINER. Independent from driver_balances.';

-- ─── Trigger: fires alongside the cash settlement on the same UPDATE ────────
DROP TRIGGER IF EXISTS orders_financial_split ON public.orders;
CREATE TRIGGER orders_financial_split
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (NEW.status = 'delivered'
        AND NEW.payment_status = 'paid'
        AND COALESCE(NEW.is_partner_store, false) = true)
  EXECUTE FUNCTION public.apply_order_financial_split();

COMMIT;
