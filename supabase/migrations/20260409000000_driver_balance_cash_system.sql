-- ============================================================================
-- BORA — Driver Balance / Cash Settlement System
-- ============================================================================
-- PURPOSE:
--   1. Cap cash payments at 30 € (server-enforced).
--   2. Atomically settle driver cash exposure when an order is delivered.
--   3. Idempotent: UNIQUE(order_id) prevents double-settlement.
--   4. Audit trail via driver_transactions.
--
-- NOTE on types: orders.assigned_driver_id is TEXT (legacy). We cast to UUID
-- inside the trigger (same pattern used by bora_tokens_type_fix).
-- ============================================================================

BEGIN;

-- ─── Driver balances (running cash exposure) ────────────────────────────────
CREATE TABLE IF NOT EXISTS public.driver_balances (
  driver_id  UUID PRIMARY KEY,
  balance    NUMERIC(10, 2) NOT NULL DEFAULT 0,
  updated_at TIMESTAMPTZ     NOT NULL DEFAULT now()
);

COMMENT ON TABLE public.driver_balances IS
  'Running cash balance per driver. balance > 0 means the driver holds platform cash. Updated only by apply_driver_cash_settlement trigger.';

-- ─── Driver transactions (audit log, idempotency key) ───────────────────────
CREATE TABLE IF NOT EXISTS public.driver_transactions (
  id          UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  driver_id   UUID           NOT NULL,
  order_id    UUID           NOT NULL UNIQUE,   -- idempotency
  amount      NUMERIC(10, 2) NOT NULL,
  type        TEXT           NOT NULL DEFAULT 'cash_adjustment'
                             CHECK (type IN ('cash_adjustment')),
  created_at  TIMESTAMPTZ    NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_driver_transactions_driver
  ON public.driver_transactions (driver_id);

CREATE INDEX IF NOT EXISTS idx_driver_transactions_created_at
  ON public.driver_transactions (created_at DESC);

COMMENT ON TABLE public.driver_transactions IS
  'Financial audit log. UNIQUE(order_id) enforces single settlement per order.';

-- ─── RLS (read-only for authenticated clients) ──────────────────────────────
ALTER TABLE public.driver_balances     ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.driver_transactions ENABLE ROW LEVEL SECURITY;

-- Drivers can read only their own balance / transactions.
-- Writes are ONLY allowed via the SECURITY DEFINER trigger (bypasses RLS).
DROP POLICY IF EXISTS driver_balances_self_read ON public.driver_balances;
CREATE POLICY driver_balances_self_read
  ON public.driver_balances FOR SELECT
  USING (driver_id = auth.uid());

DROP POLICY IF EXISTS driver_transactions_self_read ON public.driver_transactions;
CREATE POLICY driver_transactions_self_read
  ON public.driver_transactions FOR SELECT
  USING (driver_id = auth.uid());

-- No INSERT / UPDATE / DELETE policies → client cannot touch these tables.

-- ============================================================================
-- PART 1 — Cash payment limit (30 €)
-- ============================================================================

CREATE OR REPLACE FUNCTION public.enforce_cash_payment_limit()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
  v_total NUMERIC;
BEGIN
  IF NEW.payment_method IS DISTINCT FROM 'cash' THEN
    RETURN NEW;
  END IF;

  -- Use final_total if already set, else the original price.
  v_total := COALESCE(NEW.final_total, NEW.price, 0);

  IF v_total > 30 THEN
    RAISE EXCEPTION 'CASH_LIMIT_EXCEEDED: pagamento em dinheiro disponivel apenas ate 30 EUR (pedido = % EUR)', v_total
      USING ERRCODE = 'check_violation';
  END IF;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_enforce_cash_limit ON public.orders;
CREATE TRIGGER orders_enforce_cash_limit
  BEFORE INSERT OR UPDATE OF payment_method, price, final_total ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.enforce_cash_payment_limit();

COMMENT ON FUNCTION public.enforce_cash_payment_limit() IS
  'Blocks any INSERT/UPDATE that would leave a cash order > 30 EUR. Server-enforced, cannot be bypassed by client.';

-- ============================================================================
-- PART 2 — Atomic driver cash settlement on delivery
-- ============================================================================

CREATE OR REPLACE FUNCTION public.apply_driver_cash_settlement()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver_uuid   UUID;
  v_total         NUMERIC;
  v_purchase_cost NUMERIC;
  v_delta         NUMERIC;
BEGIN
  -- Only act on transitions INTO 'delivered'. If already delivered, no-op.
  IF NEW.status IS DISTINCT FROM 'delivered' THEN
    RETURN NEW;
  END IF;
  IF OLD.status = 'delivered' THEN
    RETURN NEW;
  END IF;

  -- Only cash orders create driver cash exposure.
  IF NEW.payment_method IS DISTINCT FROM 'cash' THEN
    RETURN NEW;
  END IF;

  -- Must have an assigned driver.
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

  -- ── Cash collected ───────────────────────────────────────────────────────
  -- The driver receives the real amount the customer paid in cash:
  -- final_total (after store-shopping reconciliation) or the original price.
  v_total := COALESCE(NEW.final_total, NEW.price, 0);

  -- ── Driver out-of-pocket ─────────────────────────────────────────────────
  -- Money the driver already spent at the store on behalf of the platform.
  -- NOT the subtotal — only the confirmed purchase cost.
  v_purchase_cost := COALESCE(NEW.final_purchase_value, 0);

  v_delta := ROUND(v_total - v_purchase_cost, 2);

  -- ── Idempotent insert — UNIQUE(order_id) blocks duplicates ───────────────
  BEGIN
    INSERT INTO public.driver_transactions (driver_id, order_id, amount, type)
    VALUES (v_driver_uuid, NEW.id::UUID, v_delta, 'cash_adjustment');
  EXCEPTION WHEN unique_violation THEN
    -- Already settled — do nothing and keep the existing balance untouched.
    RAISE NOTICE 'apply_driver_cash_settlement: order % already settled — skipping', NEW.id;
    RETURN NEW;
  END;

  -- ── Atomic balance upsert (same transaction as the INSERT above) ─────────
  INSERT INTO public.driver_balances (driver_id, balance, updated_at)
  VALUES (v_driver_uuid, v_delta, now())
  ON CONFLICT (driver_id) DO UPDATE
    SET balance    = public.driver_balances.balance + EXCLUDED.balance,
        updated_at = now();

  RAISE NOTICE 'apply_driver_cash_settlement: order=% driver=% delta=% EUR', NEW.id, v_driver_uuid, v_delta;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_cash_settlement ON public.orders;
CREATE TRIGGER orders_cash_settlement
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (NEW.status = 'delivered' AND NEW.payment_method = 'cash')
  EXECUTE FUNCTION public.apply_driver_cash_settlement();

COMMENT ON FUNCTION public.apply_driver_cash_settlement() IS
  'Atomically credits/debits a driver''s cash balance when a cash order transitions to delivered. Idempotent via UNIQUE(driver_transactions.order_id). Runs as SECURITY DEFINER to bypass RLS.';

COMMIT;
