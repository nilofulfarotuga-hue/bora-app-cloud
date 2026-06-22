-- FAVORES (errand) 8.1 — foto opcional "do que comprar" enviada pelo cliente.
-- ADITIVA: coluna nova + RPC de persistência própria. NÃO toca create_order
-- nem em colunas/lógica financeira (MODO PROTECÇÃO TOTAL).
--
-- Fluxo: cliente tira/escolhe foto no wizard → OrderPhotoUploadService
-- (Edge Fn upload-order-photo, bucket order-photos) devolve URL → após o
-- pedido ser criado, o cliente chama client_set_errand_request_photo para
-- gravar a URL na própria order. O estafeta vê a foto no execution sheet.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS errand_request_photo_url text;

-- Persistência da foto SEM tocar em create_order. SECURITY DEFINER com
-- verificação de dono (orders.user_id = auth.uid()) e só para service_type
-- 'errand'. Coluna NÃO financeira → não colide com enforce_financial_immutability.
CREATE OR REPLACE FUNCTION public.client_set_errand_request_photo(
  p_order_id text,
  p_url text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid   uuid := auth.uid();
  v_owner uuid;
  v_type  text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT user_id, service_type INTO v_owner, v_type
  FROM public.orders
  WHERE id = p_order_id;

  IF v_owner IS NULL THEN
    RAISE EXCEPTION 'order_not_found';
  END IF;
  IF v_owner IS DISTINCT FROM v_uid THEN
    RAISE EXCEPTION 'not_order_owner' USING ERRCODE = '42501';
  END IF;
  IF v_type IS DISTINCT FROM 'errand' THEN
    RAISE EXCEPTION 'not_errand_order';
  END IF;

  UPDATE public.orders
  SET errand_request_photo_url = p_url
  WHERE id = p_order_id;
END;
$$;

GRANT EXECUTE ON FUNCTION public.client_set_errand_request_photo(text, text)
  TO authenticated;
