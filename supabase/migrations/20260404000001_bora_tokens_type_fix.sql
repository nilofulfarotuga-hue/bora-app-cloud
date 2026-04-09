-- ─────────────────────────────────────────────────────────────────────────────
-- Migration: fix type casts in bora_tokens trigger
-- Created:   2026-04-04
--
-- Reason:
--   orders.id             = TEXT  (bora_tokens.source_order_id = UUID)
--   orders.assigned_driver_id = TEXT  (bora_tokens.user_id = UUID)
--   Explicit ::UUID casts needed so the trigger can write to bora_tokens.
-- ─────────────────────────────────────────────────────────────────────────────

CREATE OR REPLACE FUNCTION fn_award_tokens_on_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_driver_tokens  INTEGER := 40;
  v_client_tokens  INTEGER;
  v_order_uuid     UUID;
  v_driver_uuid    UUID;
BEGIN
  -- Only react to status becoming 'delivered'
  IF NEW.status <> 'delivered' OR OLD.status = 'delivered' THEN
    RETURN NEW;
  END IF;

  -- Cast order id TEXT → UUID (orders.id is TEXT, bora_tokens.source_order_id is UUID)
  BEGIN
    v_order_uuid := NEW.id::UUID;
  EXCEPTION WHEN invalid_text_representation THEN
    -- orders.id is not a valid UUID — skip silently
    RETURN NEW;
  END;

  -- ── Driver tokens ─────────────────────────────────────────────────────────
  IF NEW.assigned_driver_id IS NOT NULL THEN
    BEGIN
      v_driver_uuid := NEW.assigned_driver_id::UUID;
      PERFORM add_tokens(
        v_driver_uuid,
        'driver',
        v_driver_tokens,
        v_order_uuid
      );
    EXCEPTION WHEN invalid_text_representation THEN
      -- assigned_driver_id is not a valid UUID — skip driver tokens
      NULL;
    END;
  END IF;

  -- ── Client tokens (3 % of order total, minimum 1) ────────────────────────
  IF NEW.user_id IS NOT NULL AND NEW.price IS NOT NULL AND NEW.price > 0 THEN
    v_client_tokens := GREATEST(1, ROUND(NEW.price * 0.03)::INTEGER);
    PERFORM add_tokens(
      NEW.user_id,       -- user_id in orders is already UUID
      'client',
      v_client_tokens,
      v_order_uuid
    );
  END IF;

  RETURN NEW;
END;
$$;
