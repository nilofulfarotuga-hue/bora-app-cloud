-- Missão única 2026-10-03 · Bloco 2 (escrita 04/10; aplicar pela Claude.ai — o conector
-- do PC prende nas escritas e o PAT do CLI expirou).
-- Mesmo defeito do Favor (corrigido 03/10 em 20261003201000): dois toques em
-- "Continuar para pagamento" criavam dois pedidos. A app já tem trava no botão
-- (send_package_form_screen / carry_groceries_form_screen); isto é a rede no servidor.
-- Alarga o gatilho BEFORE INSERT existente aos tipos sendPackage e carryGroceries,
-- com a MESMA chave errand_duplicate_window_seconds (60 s; 0 = desliga).
-- Compara price (total/customer_total são colunas geradas de price — vazias num BEFORE).
-- Para pacote/compras compara também a morada de recolha (dois envios diferentes para a
-- mesma morada de entrega no mesmo minuto continuam permitidos).

UPDATE public.platform_settings
SET description = 'Segundos em que o servidor recusa um pedido IGUAL de Favor, Enviar pacote ou Levar compras (mesmo cliente, mesmas moradas e mesmo preço) — evita pedido duplicado por toque duplo. 0 = desliga.'
WHERE key = 'errand_duplicate_window_seconds';

CREATE OR REPLACE FUNCTION public.fn_orders_errand_duplicado()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $f$
DECLARE
  v_janela int := COALESCE((public.get_setting('errand_duplicate_window_seconds') #>> '{}')::int, 60);
  v_outro text;
BEGIN
  IF NEW.service_type IS NULL
     OR NEW.service_type NOT IN ('errand', 'sendPackage', 'carryGroceries')
     OR v_janela <= 0
     OR auth.uid() IS NULL OR auth.uid() IS DISTINCT FROM NEW.user_id THEN
    RETURN NEW;
  END IF;
  SELECT o.id INTO v_outro FROM public.orders o
  WHERE o.user_id = NEW.user_id
    AND o.service_type = NEW.service_type
    AND o.id IS DISTINCT FROM NEW.id
    AND COALESCE(o.dropoff_address, '') = COALESCE(NEW.dropoff_address, '')
    AND (NEW.service_type = 'errand'
         OR COALESCE(o.pickup_address, '') = COALESCE(NEW.pickup_address, ''))
    AND o.price IS NOT DISTINCT FROM NEW.price
    AND o.created_at > now() - make_interval(secs => v_janela)
    AND o.status NOT IN ('cancelled', 'rejected')
  LIMIT 1;
  IF v_outro IS NOT NULL THEN
    RAISE EXCEPTION 'duplicate_errand: já há um pedido igual (%) criado há menos de % s', v_outro, v_janela
      USING ERRCODE = 'P0001';
  END IF;
  RETURN NEW;
END $f$;

-- O gatilho trg_orders_errand_duplicado (BEFORE INSERT ON orders) já existe e
-- chama esta função; não é preciso recriá-lo.
