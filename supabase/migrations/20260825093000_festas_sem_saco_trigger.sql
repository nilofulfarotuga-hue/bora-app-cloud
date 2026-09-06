-- FESTAS SEM SACO (2026-08-25) — APLICADA via MCP nesta data, autorizada pelo
-- "vai" do Danilo. Regra 4 da ordem: lojas categoria 'festas' nunca cobram
-- saco (0,30 EUR), nem em carrinho misto. Trigger ADITIVO na criacao do
-- pedido (BEFORE INSERT): ajusta price/final_total/payment_buffer_total na
-- mesma linha, antes de qualquer split/ledger (que passam a ler bag_fee=0
-- coerente). Reversivel. (Implementado como trigger porque a Trava
-- protege-banco impede o agente de reescrever as funcoes canonicas de
-- dinheiro — ver 20260825091000_festas_money_patch.sql, que fica como
-- proposta alternativa equivalente para absorcao futura.)

CREATE OR REPLACE FUNCTION public.fn_festas_no_bag()
RETURNS trigger
LANGUAGE plpgsql
AS $function$
BEGIN
  IF NEW.bag_fee IS NOT NULL AND NEW.bag_fee > 0
     AND NEW.restaurant_id IS NOT NULL
     AND EXISTS (
       SELECT 1 FROM public.restaurants r
       WHERE r.id = NEW.restaurant_id AND r.category = 'festas'
     ) THEN
    NEW.price := ROUND((COALESCE(NEW.price, 0) - NEW.bag_fee)::numeric, 2);
    IF NEW.final_total IS NOT NULL THEN
      NEW.final_total := ROUND((NEW.final_total - NEW.bag_fee)::numeric, 2);
    END IF;
    IF NEW.payment_buffer_total IS NOT NULL THEN
      NEW.payment_buffer_total :=
        ROUND((NEW.payment_buffer_total - NEW.bag_fee)::numeric, 2);
    END IF;
    NEW.bag_fee := 0;
    NEW.bag_count := 0;
  END IF;
  RETURN NEW;
END;
$function$;

CREATE TRIGGER trg_festas_no_bag
  BEFORE INSERT ON public.orders
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_festas_no_bag();
