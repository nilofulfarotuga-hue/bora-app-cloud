-- ============================================================
-- Batch D — token award rules fix
-- 2026-04-25
--
-- Fixes:
--   • Driver tokens: 50 for partner orders, 40 for non-partner (was flat 40)
--   • Client tokens: ROUND(price × 3) tokens per € — 3 tokens/€ = ~1.5% cashback
--     BUG FIX: was ROUND(price × 0.03) — factor-100 error giving ~0 tokens
-- ============================================================

CREATE OR REPLACE FUNCTION fn_award_tokens_on_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver_tokens  INTEGER;
  v_client_tokens  INTEGER;
BEGIN
  -- Only react to status becoming 'delivered'
  IF NEW.status <> 'delivered' OR OLD.status = 'delivered' THEN
    RETURN NEW;
  END IF;

  -- ── Driver tokens ─────────────────────────────────────────────────────────
  -- Partner orders: 50 tokens (harder work, partner relationship)
  -- Non-partner:    40 tokens
  IF NEW.assigned_driver_id IS NOT NULL THEN
    v_driver_tokens := CASE WHEN NEW.is_partner_store THEN 50 ELSE 40 END;
    PERFORM add_tokens(
      NEW.assigned_driver_id::UUID,
      'driver',
      v_driver_tokens,
      NEW.id
    );
  END IF;

  -- ── Client tokens (3 tokens per €, minimum 1) ────────────────────────────
  -- 100 tokens = €0.50 → 3 tokens/€ ≈ 1.5% cashback
  -- BUG FIX: was NEW.price * 0.03 → gives 3 tokens on €100 (0.03% effective)
  --          correct: NEW.price * 3  → gives 300 tokens on €100 (1.5% effective)
  IF NEW.user_id IS NOT NULL AND NEW.price IS NOT NULL AND NEW.price > 0 THEN
    v_client_tokens := GREATEST(1, ROUND(NEW.price * 3)::INTEGER);
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

-- Re-attach trigger (DROP IF EXISTS + CREATE is idempotent)
DROP TRIGGER IF EXISTS trg_award_tokens_on_delivery ON orders;

CREATE TRIGGER trg_award_tokens_on_delivery
  AFTER UPDATE OF status ON orders
  FOR EACH ROW
  EXECUTE FUNCTION fn_award_tokens_on_delivery();
