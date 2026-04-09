-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: bora_tokens system
-- Created:   2026-04-04
--
-- Architecture: entry-based (FIFO-compatible, expiry-aware)
--   • Each token award creates a NEW row (never aggregated)
--   • Balance = SUM of active (is_used=false, expires_at > now()) entries
--   • FIFO consumption reads entries ordered by expires_at ASC
--   • Duplicate prevention: UNIQUE index on (source_order_id, role)
--   • Award trigger fires server-side when orders.status → 'delivered'
-- ─────────────────────────────────────────────────────────────────────────────


-- ─── PASSO 1: Tabela principal ────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS bora_tokens (
  id              UUID    PRIMARY KEY DEFAULT gen_random_uuid(),

  user_id         UUID    NOT NULL,
  role            TEXT    NOT NULL CHECK (role IN ('client', 'driver')),

  amount          INTEGER NOT NULL CHECK (amount > 0),

  created_at      TIMESTAMPTZ DEFAULT now(),
  expires_at      TIMESTAMPTZ NOT NULL,

  -- Which order originated this entry (NULL only for manual/promo grants).
  source_order_id UUID,

  is_used         BOOLEAN     DEFAULT FALSE,
  used_at         TIMESTAMPTZ
);

-- ─── PASSO 2: Indexes ─────────────────────────────────────────────────────────

-- Lookup by user (balance queries, history)
CREATE INDEX IF NOT EXISTS idx_bora_tokens_user
  ON bora_tokens(user_id);

-- Lookup by expiry (cleanup jobs, active-only filters)
CREATE INDEX IF NOT EXISTS idx_bora_tokens_expiry
  ON bora_tokens(expires_at);

-- Lookup for active tokens (balance + FIFO consumption)
CREATE INDEX IF NOT EXISTS idx_bora_tokens_unused
  ON bora_tokens(user_id, is_used);

-- Idempotency guard: ONE entry per (order × role).
-- Prevents double-award if the trigger ever fires twice (e.g. concurrent update).
CREATE UNIQUE INDEX IF NOT EXISTS idx_bora_tokens_order_role
  ON bora_tokens(source_order_id, role)
  WHERE source_order_id IS NOT NULL;


-- ─── PASSO 3: Função add_tokens ───────────────────────────────────────────────
--
-- Inserts a token entry for a user.
-- ON CONFLICT DO NOTHING ensures idempotency — safe to call multiple times
-- for the same (order_id, role) pair.
--
-- Returns the new row UUID, or NULL if the entry already existed (conflict).

CREATE OR REPLACE FUNCTION add_tokens(
  p_user_id   UUID,
  p_role      TEXT,
  p_amount    INTEGER,
  p_order_id  UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_id UUID;
BEGIN
  INSERT INTO bora_tokens (
    user_id,
    role,
    amount,
    expires_at,
    source_order_id
  )
  VALUES (
    p_user_id,
    p_role,
    p_amount,
    now() + INTERVAL '60 days',
    p_order_id
  )
  ON CONFLICT (source_order_id, role)
    WHERE source_order_id IS NOT NULL
    DO NOTHING
  RETURNING id INTO v_id;

  RETURN v_id;   -- NULL when DO NOTHING fired (already awarded)
END;
$$;


-- ─── PASSO 5: Função get_user_tokens ─────────────────────────────────────────
--
-- Returns the current active token balance for a user.
-- Active = not used AND not expired.

CREATE OR REPLACE FUNCTION get_user_tokens(
  p_user_id UUID
)
RETURNS INTEGER
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT COALESCE(SUM(amount), 0)::INTEGER
  FROM   bora_tokens
  WHERE  user_id    = p_user_id
    AND  is_used    = FALSE
    AND  expires_at > now();
$$;


-- ─── PASSO 4: Trigger de entrega ─────────────────────────────────────────────
--
-- Fires AFTER UPDATE on orders when status transitions to 'delivered'.
-- Awards tokens server-side — no Flutter involvement, no race conditions.
--
-- Token rules:
--   • Driver  → 40 tokens flat per delivery
--   • Client  → ROUND(price * 0.03) tokens  (3 % of order total, min 1)
--
-- Idempotency is guaranteed by the UNIQUE index on (source_order_id, role):
-- even if the trigger somehow fires twice, add_tokens → ON CONFLICT DO NOTHING
-- prevents duplicate entries.

CREATE OR REPLACE FUNCTION fn_award_tokens_on_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver_tokens  INTEGER := 40;
  v_client_tokens  INTEGER;
BEGIN
  -- Only react to status becoming 'delivered'
  IF NEW.status <> 'delivered' OR OLD.status = 'delivered' THEN
    RETURN NEW;
  END IF;

  -- ── Driver tokens ─────────────────────────────────────────────────────────
  IF NEW.assigned_driver_id IS NOT NULL THEN
    PERFORM add_tokens(
      NEW.assigned_driver_id,
      'driver',
      v_driver_tokens,
      NEW.id
    );
  END IF;

  -- ── Client tokens (3 % of order total, minimum 1) ────────────────────────
  IF NEW.user_id IS NOT NULL AND NEW.price IS NOT NULL AND NEW.price > 0 THEN
    v_client_tokens := GREATEST(1, ROUND(NEW.price * 0.03)::INTEGER);
    PERFORM add_tokens(
      NEW.user_id,
      'client',
      v_client_tokens,
      NEW.id
    );
  END IF;

  RETURN NEW;
END;
$$;

-- Attach trigger to orders table
DROP TRIGGER IF EXISTS trg_award_tokens_on_delivery ON orders;

CREATE TRIGGER trg_award_tokens_on_delivery
  AFTER UPDATE OF status ON orders
  FOR EACH ROW
  EXECUTE FUNCTION fn_award_tokens_on_delivery();
