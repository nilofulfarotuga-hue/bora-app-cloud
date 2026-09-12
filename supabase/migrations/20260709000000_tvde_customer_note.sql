-- TVDE — nota opcional do cliente para o MOTORISTA (paridade com a "Nota para o
-- estafeta" do delivery/limpeza, que liga ao customerNotes).
-- NÃO-FINANCEIRO: só guarda um texto livre. Nunca toca em tarifa, split ou
-- payment_method. Por isso vive fora da RPC de cálculo `tvde_request_ride` e da
-- Edge Function de pagamento — é uma RPC dedicada chamada após a corrida criada.

-- 1) Coluna aditiva (nullable, reversível: DROP COLUMN).
ALTER TABLE public.tvde_rides
  ADD COLUMN IF NOT EXISTS customer_note TEXT;

-- 2) RPC dedicada: o dono da corrida grava a sua nota. Limite 200 chars (espelha
--    o maxLength do campo de delivery). Só enquanto a corrida ainda decorre.
CREATE OR REPLACE FUNCTION public.tvde_set_ride_note(p_ride_id UUID, p_note TEXT)
  RETURNS VOID
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE v_uid UUID := auth.uid(); v_client UUID; v_status TEXT;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT client_id, status INTO v_client, v_status
    FROM public.tvde_rides WHERE id = p_ride_id;
  IF v_client IS NULL THEN RAISE EXCEPTION 'ride_not_found'; END IF;
  IF v_client <> v_uid THEN RAISE EXCEPTION 'not_ride_owner'; END IF;
  IF v_status IN ('finalizada','cancelada_cliente','cancelada_motorista','no_show') THEN
    RAISE EXCEPTION 'ride_terminal';
  END IF;
  UPDATE public.tvde_rides
    SET customer_note = NULLIF(LEFT(TRIM(p_note), 200), '')
    WHERE id = p_ride_id;
END; $function$;

GRANT EXECUTE ON FUNCTION public.tvde_set_ride_note(UUID, TEXT) TO authenticated;
