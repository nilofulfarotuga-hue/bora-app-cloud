-- Trigger paralelo a orders_cash_settlement (tabelas independentes, zero conflito).
-- Liquida dívida do CLIENTE quando pedido CASH é entregue.
-- Ordem alfabética dispara este (apply_client_*) ANTES de orders_cash_settlement.
-- Defensivo: catch SQLERRM nunca bloqueia UPDATE de status.
CREATE OR REPLACE FUNCTION public.fn_apply_client_debt_settlement_on_cash_delivery()
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
      NEW.user_id, v_debt, 'cash_delivery',
      'settle_cash_' || NEW.id
    );
  EXCEPTION WHEN OTHERS THEN
    RAISE WARNING 'apply_client_debt_settlement_on_cash_delivery failed for order %: %',
      NEW.id, SQLERRM;
  END;

  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS apply_client_debt_settlement_on_cash_delivery ON public.orders;

CREATE TRIGGER apply_client_debt_settlement_on_cash_delivery
  AFTER UPDATE OF status ON public.orders
  FOR EACH ROW
  WHEN (NEW.status = 'delivered'
        AND OLD.status IS DISTINCT FROM 'delivered'
        AND NEW.payment_method = 'cash')
  EXECUTE FUNCTION fn_apply_client_debt_settlement_on_cash_delivery();

COMMENT ON FUNCTION public.fn_apply_client_debt_settlement_on_cash_delivery IS
'Liquida dívida wallet do cliente quando pedido CASH é entregue. Paralelo a orders_cash_settlement (tabelas independentes). Catch defensivo nunca bloqueia UPDATE.';
