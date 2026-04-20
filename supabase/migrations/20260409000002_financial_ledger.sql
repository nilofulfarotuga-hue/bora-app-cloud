-- ============================================================================
-- BORA — Financial Ledger (fintech-grade)
-- ============================================================================
-- Single source of truth for all money movement. Append-only, NUMERIC(12,2),
-- idempotent, atomic, server-trusted.
--
-- SIGN CONVENTION (global, immutable):
--    + amount  → platform OWES the user
--    - amount  → user OWES the platform
--
--   driver.earning         > 0    (platform owes driver)
--   driver.cash_adjustment < 0    (driver collected cash on behalf of platform)
--   driver.payout          < 0    (platform settled driver)
--   restaurant.earning     > 0    (platform owes restaurant)
--   restaurant.payout      < 0    (platform settled restaurant)
--   platform.commission    > 0    (internal profit, by spec)
--
-- DEPRECATION NOTE:
--   `driver_balances` (20260409000000) and `order_financials`
--   (20260409000001) become read-only legacy. The ledger is now authoritative.
--   They are NOT dropped here — back-compat reads remain valid.
-- ============================================================================

BEGIN;

-- ─── Core ledger ────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.ledger_entries (
  id          UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     TEXT           NOT NULL,                              -- driver UUID, restaurant id, or 'platform'
  user_type   TEXT           NOT NULL CHECK (user_type IN ('driver','restaurant','platform')),
  order_id    UUID           NULL,                                  -- nullable for payouts/manual entries
  amount      NUMERIC(12, 2) NOT NULL CHECK (amount <> 0),
  type        TEXT           NOT NULL CHECK (type IN ('earning','cash_adjustment','commission','payout')),
  reference   TEXT           NOT NULL,
  created_at  TIMESTAMPTZ    NOT NULL DEFAULT now()
);

-- Idempotency (PG15+ NULLS NOT DISTINCT so order_id NULL still dedupes).
ALTER TABLE public.ledger_entries
  DROP CONSTRAINT IF EXISTS ux_ledger_idempotency;
ALTER TABLE public.ledger_entries
  ADD CONSTRAINT ux_ledger_idempotency
  UNIQUE NULLS NOT DISTINCT (order_id, user_id, type, reference);

CREATE INDEX IF NOT EXISTS idx_ledger_user        ON public.ledger_entries (user_id, user_type);
CREATE INDEX IF NOT EXISTS idx_ledger_order       ON public.ledger_entries (order_id);
CREATE INDEX IF NOT EXISTS idx_ledger_type        ON public.ledger_entries (type);
CREATE INDEX IF NOT EXISTS idx_ledger_created_at  ON public.ledger_entries (created_at DESC);

COMMENT ON TABLE public.ledger_entries IS
  'Append-only financial ledger. Single source of truth. Sign convention: + = platform owes user, - = user owes platform.';

-- ─── APPEND-ONLY ENFORCEMENT ────────────────────────────────────────────────
-- Hard guarantee: once a row is committed, no UPDATE/DELETE can touch it.
CREATE OR REPLACE FUNCTION public.ledger_append_only_guard()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  RAISE EXCEPTION 'ledger_entries is append-only (% rejected)', TG_OP
    USING ERRCODE = 'restrict_violation';
END;
$$;

DROP TRIGGER IF EXISTS ledger_no_update ON public.ledger_entries;
CREATE TRIGGER ledger_no_update BEFORE UPDATE ON public.ledger_entries
  FOR EACH ROW EXECUTE FUNCTION public.ledger_append_only_guard();

DROP TRIGGER IF EXISTS ledger_no_delete ON public.ledger_entries;
CREATE TRIGGER ledger_no_delete BEFORE DELETE ON public.ledger_entries
  FOR EACH ROW EXECUTE FUNCTION public.ledger_append_only_guard();

-- ─── Payouts ────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.payouts (
  id          UUID           PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id     TEXT           NOT NULL,
  user_type   TEXT           NOT NULL CHECK (user_type IN ('driver','restaurant')),
  amount      NUMERIC(12, 2) NOT NULL CHECK (amount > 0),           -- always recorded as gross positive
  status      TEXT           NOT NULL DEFAULT 'pending'
                             CHECK (status IN ('pending','paid','failed')),
  created_at  TIMESTAMPTZ    NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_payouts_user    ON public.payouts (user_id, user_type);
CREATE INDEX IF NOT EXISTS idx_payouts_status  ON public.payouts (status);
CREATE INDEX IF NOT EXISTS idx_payouts_created ON public.payouts (created_at DESC);

COMMENT ON TABLE public.payouts IS
  'Payout requests. Always paired with a negative ledger entry (type=payout, reference=payout:<id>) created in the same transaction.';

-- ─── Balance snapshot (read optimization, NEVER source of truth) ────────────
CREATE TABLE IF NOT EXISTS public.user_balance_snapshots (
  user_id     TEXT           NOT NULL,
  user_type   TEXT           NOT NULL CHECK (user_type IN ('driver','restaurant','platform')),
  balance     NUMERIC(12, 2) NOT NULL DEFAULT 0,
  updated_at  TIMESTAMPTZ    NOT NULL DEFAULT now(),
  PRIMARY KEY (user_id, user_type)
);

COMMENT ON TABLE public.user_balance_snapshots IS
  'Cached running balance per user. Optimization layer ONLY — the ledger remains authoritative. Refreshed by recompute_user_balance().';

-- ─── RLS ────────────────────────────────────────────────────────────────────
ALTER TABLE public.ledger_entries          ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.payouts                 ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.user_balance_snapshots  ENABLE ROW LEVEL SECURITY;

-- Drivers can read their own ledger / payouts / balance.
DROP POLICY IF EXISTS ledger_self_read   ON public.ledger_entries;
CREATE POLICY ledger_self_read   ON public.ledger_entries   FOR SELECT
  USING (user_type = 'driver' AND user_id = auth.uid()::text);

DROP POLICY IF EXISTS payouts_self_read  ON public.payouts;
CREATE POLICY payouts_self_read  ON public.payouts          FOR SELECT
  USING (user_type = 'driver' AND user_id = auth.uid()::text);

DROP POLICY IF EXISTS snapshots_self_read ON public.user_balance_snapshots;
CREATE POLICY snapshots_self_read ON public.user_balance_snapshots FOR SELECT
  USING (user_type = 'driver' AND user_id = auth.uid()::text);

-- No INSERT/UPDATE/DELETE policies anywhere. Only SECURITY DEFINER fns write.
-- Restaurant + platform reads are admin-only (future role).

-- ============================================================================
-- post_order_to_ledger — atomic, idempotent settlement on delivery
-- ============================================================================

CREATE OR REPLACE FUNCTION public.post_order_to_ledger()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver           TEXT;
  v_total            NUMERIC(12, 2);
  v_purchase         NUMERIC(12, 2);
  v_base             NUMERIC(12, 2);
  v_driver_earn      NUMERIC(12, 2);
  v_cash_adj         NUMERIC(12, 2);
  v_restaurant_earn  NUMERIC(12, 2);
  v_platform_comm    NUMERIC(12, 2);
  v_vendor_ref       TEXT;
  v_is_partner       BOOLEAN;
  v_is_cash          BOOLEAN;
BEGIN
  -- ── Gates ────────────────────────────────────────────────────────────────
  IF NEW.status IS DISTINCT FROM 'delivered'        THEN RETURN NEW; END IF;
  IF OLD.status = 'delivered'                       THEN RETURN NEW; END IF;
  IF NEW.payment_status IS DISTINCT FROM 'paid'     THEN
    RAISE NOTICE 'post_order_to_ledger: order % delivered but payment_status=% — skipping', NEW.id, NEW.payment_status;
    RETURN NEW;
  END IF;

  v_driver     := NEW.assigned_driver_id;
  v_is_partner := COALESCE(NEW.is_partner_store, false);
  v_is_cash    := (NEW.payment_method = 'cash');
  v_total      := ROUND(COALESCE(NEW.final_total, NEW.price, 0)::NUMERIC, 2);
  v_purchase   := ROUND(COALESCE(NEW.final_purchase_value, 0)::NUMERIC, 2);
  -- Base = real product value, NEVER total_paid / gateway-inclusive amounts
  v_base       := ROUND(COALESCE(NEW.final_purchase_value, NEW.subtotal, 0)::NUMERIC, 2);

  -- ── Driver: delivery earning (positive) ──────────────────────────────────
  v_driver_earn := ROUND(COALESCE(NEW.driver_earnings, 0)::NUMERIC, 2);
  IF v_driver IS NOT NULL AND v_driver_earn > 0 THEN
    INSERT INTO public.ledger_entries (user_id, user_type, order_id, amount, type, reference)
    VALUES (v_driver, 'driver', NEW.id::UUID, v_driver_earn, 'earning', 'delivery_earning')
    ON CONFLICT (order_id, user_id, type, reference) DO NOTHING;
  END IF;

  -- ── Driver: cash adjustment (negative, only when payment_method=cash) ────
  IF v_driver IS NOT NULL AND v_is_cash THEN
    -- Driver received cash from customer → owes (cash collected − purchase cost) to platform
    v_cash_adj := -ROUND(v_total - v_purchase, 2);
    IF v_cash_adj <> 0 THEN
      INSERT INTO public.ledger_entries (user_id, user_type, order_id, amount, type, reference)
      VALUES (v_driver, 'driver', NEW.id::UUID, v_cash_adj, 'cash_adjustment', 'cash_adjustment')
      ON CONFLICT (order_id, user_id, type, reference) DO NOTHING;
    END IF;
  END IF;

  -- ── Restaurant + Platform commission ─────────────────────────────────────
  IF v_is_partner THEN
    v_vendor_ref     := COALESCE(NEW.vendor_name, 'unknown');
    v_restaurant_earn := ROUND(v_base * 0.90, 2);
    v_platform_comm   := ROUND(v_base - v_restaurant_earn, 2);  -- platform absorbs rounding residue

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
    -- Non-partner orders: platform commission already pre-computed by the app
    v_platform_comm := ROUND(COALESCE(NEW.platform_commission, 0)::NUMERIC, 2);
    IF v_platform_comm > 0 THEN
      INSERT INTO public.ledger_entries (user_id, user_type, order_id, amount, type, reference)
      VALUES ('platform', 'platform', NEW.id::UUID, v_platform_comm, 'commission', 'service_commission')
      ON CONFLICT (order_id, user_id, type, reference) DO NOTHING;
    END IF;
  END IF;

  RAISE NOTICE 'post_order_to_ledger: order=% driver=% partner=% cash=% base=%',
    NEW.id, v_driver, v_is_partner, v_is_cash, v_base;

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS orders_post_to_ledger ON public.orders;
CREATE TRIGGER orders_post_to_ledger
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (NEW.status = 'delivered' AND NEW.payment_status = 'paid')
  EXECUTE FUNCTION public.post_order_to_ledger();

COMMENT ON FUNCTION public.post_order_to_ledger() IS
  'Posts all financial entries (driver earning, cash adjustment, restaurant share, platform commission) for a delivered+paid order. Atomic + idempotent + SECURITY DEFINER.';

-- ============================================================================
-- create_payout — atomic payout + ledger entry pair
-- ============================================================================

CREATE OR REPLACE FUNCTION public.create_payout(
  p_user_id   TEXT,
  p_user_type TEXT,
  p_amount    NUMERIC
) RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_payout_id UUID;
  v_amount    NUMERIC(12, 2);
BEGIN
  IF p_user_type NOT IN ('driver','restaurant') THEN
    RAISE EXCEPTION 'create_payout: invalid user_type %', p_user_type;
  END IF;
  IF p_amount IS NULL OR p_amount <= 0 THEN
    RAISE EXCEPTION 'create_payout: amount must be > 0';
  END IF;

  v_amount := ROUND(p_amount::NUMERIC, 2);

  -- 1. Insert payout request
  INSERT INTO public.payouts (user_id, user_type, amount, status)
  VALUES (p_user_id, p_user_type, v_amount, 'pending')
  RETURNING id INTO v_payout_id;

  -- 2. Insert paired ledger entry (negative — debt being settled)
  --    reference includes payout id → unique per payout, idempotent on retry
  INSERT INTO public.ledger_entries (user_id, user_type, order_id, amount, type, reference)
  VALUES (p_user_id, p_user_type, NULL, -v_amount, 'payout', 'payout:' || v_payout_id::text);

  RAISE NOTICE 'create_payout: id=% user=% type=% amount=%', v_payout_id, p_user_id, p_user_type, v_amount;

  RETURN v_payout_id;
END;
$$;

COMMENT ON FUNCTION public.create_payout(TEXT,TEXT,NUMERIC) IS
  'Creates a payout request and the matching negative ledger entry atomically. Both rows share the same UPDATE transaction — partial state is impossible.';

-- ============================================================================
-- recompute_user_balance — refreshes the snapshot from the ledger
-- ============================================================================

CREATE OR REPLACE FUNCTION public.recompute_user_balance(
  p_user_id   TEXT,
  p_user_type TEXT
) RETURNS NUMERIC
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_balance NUMERIC(12, 2);
BEGIN
  SELECT COALESCE(SUM(amount), 0)::NUMERIC(12,2)
    INTO v_balance
  FROM public.ledger_entries
  WHERE user_id = p_user_id AND user_type = p_user_type;

  INSERT INTO public.user_balance_snapshots (user_id, user_type, balance, updated_at)
  VALUES (p_user_id, p_user_type, v_balance, now())
  ON CONFLICT (user_id, user_type) DO UPDATE
    SET balance    = EXCLUDED.balance,
        updated_at = now();

  RETURN v_balance;
END;
$$;

COMMENT ON FUNCTION public.recompute_user_balance(TEXT,TEXT) IS
  'Recomputes a user balance by SUMming the ledger and updates the snapshot cache. Snapshot is for read perf only — ledger is the source of truth.';

-- ============================================================================
-- Reconciliation view — entrada = saída + lucro
-- ============================================================================

CREATE OR REPLACE VIEW public.v_ledger_reconciliation AS
SELECT
  COALESCE(SUM(amount) FILTER (WHERE user_type = 'driver'     AND type = 'earning'),         0)::NUMERIC(12,2) AS driver_earnings,
  COALESCE(SUM(amount) FILTER (WHERE user_type = 'driver'     AND type = 'cash_adjustment'), 0)::NUMERIC(12,2) AS driver_cash_held,
  COALESCE(SUM(amount) FILTER (WHERE user_type = 'driver'     AND type = 'payout'),          0)::NUMERIC(12,2) AS driver_payouts,
  COALESCE(SUM(amount) FILTER (WHERE user_type = 'restaurant' AND type = 'earning'),         0)::NUMERIC(12,2) AS restaurant_earnings,
  COALESCE(SUM(amount) FILTER (WHERE user_type = 'restaurant' AND type = 'payout'),          0)::NUMERIC(12,2) AS restaurant_payouts,
  COALESCE(SUM(amount) FILTER (WHERE user_type = 'platform'   AND type = 'commission'),      0)::NUMERIC(12,2) AS platform_commission,
  COALESCE(SUM(amount), 0)::NUMERIC(12,2) AS net_ledger_total
FROM public.ledger_entries;

COMMENT ON VIEW public.v_ledger_reconciliation IS
  'Aggregate totals per user_type/type. Use to verify entrada = saida + lucro invariant.';

COMMIT;
