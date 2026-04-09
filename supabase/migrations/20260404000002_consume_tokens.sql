-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: consume_tokens — FIFO token consumption
-- Created:   2026-04-04
--
-- Architecture:
--   • FIFO: tokens ordered by expires_at ASC, created_at ASC (oldest first)
--   • Split: if a token has more than needed, mark it used and insert a
--     remainder row that preserves the original expires_at
--   • Atomic: entire operation runs inside the function's implicit transaction
--     (PL/pgSQL functions execute in a single transaction block)
--   • Idempotency: pre-check via get_user_tokens before any mutation;
--     returns FALSE without touching DB if balance insufficient
--   • No race condition: SELECT ... FOR UPDATE locks the rows being consumed
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION consume_tokens(
  p_user_id UUID,
  p_amount  INTEGER
)
RETURNS BOOLEAN
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_current_balance  INTEGER;
  v_remaining        INTEGER := p_amount;
  v_row              RECORD;
  v_consume          INTEGER;
BEGIN
  -- ── Guard: reject invalid amounts ────────────────────────────────────────
  IF p_amount <= 0 THEN
    RAISE EXCEPTION 'consume_tokens: p_amount must be > 0, got %', p_amount;
  END IF;

  -- ── Guard: verify sufficient balance before mutating anything ────────────
  v_current_balance := get_user_tokens(p_user_id);

  IF v_current_balance < p_amount THEN
    RAISE NOTICE
      'consume_tokens: insufficient balance for user %. Have %, need %',
      p_user_id, v_current_balance, p_amount;
    RETURN FALSE;
  END IF;

  -- ── FIFO loop: consume oldest-expiring tokens first ───────────────────────
  -- SELECT FOR UPDATE ensures no concurrent call can touch the same rows.
  FOR v_row IN
    SELECT id, amount, expires_at, role
    FROM   bora_tokens
    WHERE  user_id    = p_user_id
      AND  is_used    = FALSE
      AND  expires_at > now()
    ORDER BY expires_at ASC, created_at ASC
    FOR UPDATE
  LOOP
    EXIT WHEN v_remaining = 0;

    IF v_row.amount <= v_remaining THEN
      -- ── Case A: consume this token entirely ──────────────────────────────
      UPDATE bora_tokens
      SET    is_used = TRUE,
             used_at = now()
      WHERE  id = v_row.id;

      v_remaining := v_remaining - v_row.amount;

    ELSE
      -- ── Case B: partial — consume what's needed, keep the rest ───────────
      -- Mark the original row as fully used.
      UPDATE bora_tokens
      SET    is_used = TRUE,
             used_at = now()
      WHERE  id = v_row.id;

      -- Insert a remainder row with the same expiry so it doesn't gain
      -- artificial longevity. No source_order_id (it's a split, not a reward).
      INSERT INTO bora_tokens (user_id, role, amount, expires_at)
      VALUES (p_user_id, v_row.role, v_row.amount - v_remaining, v_row.expires_at);

      v_remaining := 0;
    END IF;

  END LOOP;

  -- ── Sanity check: should never happen given the pre-check above ──────────
  IF v_remaining > 0 THEN
    RAISE EXCEPTION
      'consume_tokens: consumed less than requested (remaining=%). Rolling back.',
      v_remaining;
  END IF;

  RETURN TRUE;
END;
$$;
