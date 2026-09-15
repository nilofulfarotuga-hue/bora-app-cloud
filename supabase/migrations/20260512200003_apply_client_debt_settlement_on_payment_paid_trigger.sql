-- PROMPT 4a (2026-05-12) — trigger paralelo a apply_client_debt_settlement_on_cash_delivery
-- Para MBWay e Cartão LEGACY (pagamento via PI standalone do order já criado):
-- quando webhook seta payment_status='paid' explícito → settle.
-- CASH NÃO dispara aqui (filtro payment_method IN (mbway,card)) — usa trigger antigo em delivered.
-- Cartão NEW dispara inline em create_order (via payment_already_confirmed=true) — não passa por aqui.
CREATE OR REPLACE FUNCTION public.fn_apply_client_debt_settlement_on_payment_paid()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_balance INTEGER;
  v_debt    INTEGER;
BEGIN
  BEGIN
    SELECT free_balance_cents INTO v_balance
      FROM client_wallets WHERE user_id = NEW.user_id FOR UPDATE;

    IF v_balance IS NULL OR v_balance >= 0 THEN
      RETURN NEW;
    END IF;

    v_debt := -v_balance;

    PERFORM wallet_settle_debt(
      NEW.user_id, v_debt, 'payment_paid',
      'settle_paid_' || NEW.id
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'apply_client_debt_settlement_on_payment_paid failed for order %: %',
      NEW.id, SQLERRM;
  END;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS apply_client_debt_settlement_on_payment_paid ON public.orders;

CREATE TRIGGER apply_client_debt_settlement_on_payment_paid
  AFTER UPDATE OF payment_status ON public.orders
  FOR EACH ROW
  WHEN (NEW.payment_status = 'paid'
        AND OLD.payment_status IS DISTINCT FROM 'paid'
        AND NEW.payment_method IN ('mbway','card'))
  EXECUTE FUNCTION fn_apply_client_debt_settlement_on_payment_paid();

COMMENT ON FUNCTION public.fn_apply_client_debt_settlement_on_payment_paid IS
'Liquida dívida wallet do cliente quando pedido MBWay/Cartão LEGACY recebe payment_status=paid. Paralelo a apply_client_debt_settlement_on_cash_delivery (CASH em delivered). Catch defensivo nunca bloqueia UPDATE.';
