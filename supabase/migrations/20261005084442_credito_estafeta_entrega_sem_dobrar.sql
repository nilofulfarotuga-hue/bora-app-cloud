-- Ronda 04/10, Bloco A.8 (05/10/2026): o saldo do estafeta só sobe quando o ganho da entrega
-- é registado pela primeira vez. Antes, driver_transactions tinha ON CONFLICT DO NOTHING mas
-- driver_balances somava sempre: pedido que saísse de 'delivered' e voltasse creditava outra vez.
-- Prova (transacção desfeita, tabela temporária com o mesmo gatilho): antes=20.25,
-- depois da 1.ª entrega=24.25, depois da 2.ª=24.25, transacções=1.
CREATE OR REPLACE FUNCTION public.fn_credit_driver_on_delivery()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_earnings NUMERIC;
  v_novo INT;
BEGIN
  IF NEW.status = 'delivered'
    AND (OLD.status IS DISTINCT FROM 'delivered')
    AND NEW.assigned_driver_id IS NOT NULL
  THEN
    v_earnings := COALESCE(NEW.driver_earnings, 0);
    IF v_earnings > 0 THEN
      INSERT INTO driver_transactions (driver_id, order_id, amount, type, status)
      VALUES (NEW.assigned_driver_id::uuid, NEW.id::uuid, v_earnings,
              'delivery_earning', 'completed')
      ON CONFLICT (order_id, type) DO NOTHING;
      GET DIAGNOSTICS v_novo = ROW_COUNT;

      -- Ronda 04/10 A.8: o saldo só sobe quando o ganho é registado pela primeira vez.
      -- Pedido que sai de entregue e volta não credita outra vez.
      IF v_novo > 0 THEN
        INSERT INTO driver_balances (driver_id, balance, updated_at)
        VALUES (NEW.assigned_driver_id::uuid, v_earnings, NOW())
        ON CONFLICT (driver_id)
        DO UPDATE SET
          balance    = driver_balances.balance + EXCLUDED.balance,
          updated_at = NOW();
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;
