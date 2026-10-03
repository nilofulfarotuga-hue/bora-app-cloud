-- ============================================================================
-- BORA — Cashback automático (Feature 11)
-- ============================================================================
-- Trigger em orders quando status→delivered: credita cashback_pct * total
-- ao saldo livre do cliente. Setting cashback_pct em platform_settings.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.fn_award_cashback_on_delivery()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_pct      NUMERIC;
  v_total_cents INTEGER;
  v_cashback INTEGER;
BEGIN
  IF NEW.status <> 'delivered' OR OLD.status = 'delivered' THEN
    RETURN NEW;
  END IF;
  IF NEW.user_id IS NULL THEN
    RETURN NEW;
  END IF;

  SELECT COALESCE((public.get_setting('cashback_pct'))::numeric, 0.01) INTO v_pct;
  IF v_pct <= 0 THEN RETURN NEW; END IF;

  v_total_cents := COALESCE(
    ROUND(COALESCE(NEW.customer_total, NEW.final_total, NEW.total, 0)::numeric * 100),
    0);
  IF v_total_cents <= 0 THEN RETURN NEW; END IF;

  v_cashback := ROUND(v_total_cents * v_pct);
  IF v_cashback < 1 THEN RETURN NEW; END IF;

  -- Idempotência: não creditar se já houve cashback para esta order
  IF EXISTS (
    SELECT 1 FROM public.wallet_transactions
    WHERE related_order_id = NEW.id AND kind = 'cashback'
  ) THEN
    RETURN NEW;
  END IF;

  PERFORM public.wallet_credit_generic(
    NEW.user_id,
    v_cashback,
    'cashback',
    'Cashback ' || (v_pct * 100)::text || '% pedido ' || NEW.id,
    NEW.id
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE WARNING 'fn_award_cashback_on_delivery failed: %', SQLERRM;
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_award_cashback ON public.orders;
CREATE TRIGGER trg_award_cashback
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (NEW.status = 'delivered' AND OLD.status IS DISTINCT FROM 'delivered')
  EXECUTE FUNCTION public.fn_award_cashback_on_delivery();

COMMIT;
