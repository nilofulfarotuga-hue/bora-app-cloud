-- 02/11/2026 (Danilo, pedido da Dona Isabel no Continente): o limite de 40 EUR em dinheiro
-- vale quando o CLIENTE cria o pedido (ou muda o meio para dinheiro). Depois de o pedido
-- existir em dinheiro, o que o estafeta acrescenta na loja, trocas e peso na balança podem
-- passar dos 40 EUR: o talao nunca fica preso por causa do limite.
CREATE OR REPLACE FUNCTION public.enforce_cash_payment_limit()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO 'public', 'extensions', 'pg_temp'
AS $function$
DECLARE
  v_total     NUMERIC;
  v_max_cents INTEGER;
BEGIN
  IF NEW.payment_method IS DISTINCT FROM 'cash' THEN RETURN NEW; END IF;
  -- "Ir buscar": paga-se na loja, sem estafeta a levar dinheiro.
  IF NEW.service_type = 'takeaway' THEN RETURN NEW; END IF;
  -- Pedido ja criado em dinheiro: ajustes do estafeta (acrescentar, trocar, peso) passam.
  IF TG_OP = 'UPDATE' AND OLD.payment_method IS NOT DISTINCT FROM NEW.payment_method THEN
    RETURN NEW;
  END IF;
  SELECT (value::text)::INTEGER INTO v_max_cents
    FROM public.platform_settings WHERE key = 'max_cash_amount_cents';
  v_max_cents := COALESCE(v_max_cents, 4000);
  v_total := COALESCE(NEW.final_total, NEW.price, 0);
  IF ROUND(v_total * 100) > v_max_cents THEN
    RAISE EXCEPTION 'CASH_LIMIT_EXCEEDED: pagamento em dinheiro disponivel apenas ate % EUR (pedido = % EUR)',
      ROUND(v_max_cents / 100.0, 2), v_total
      USING ERRCODE = 'check_violation';
  END IF;
  RETURN NEW;
END;
$function$;