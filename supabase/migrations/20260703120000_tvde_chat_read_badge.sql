-- [Item I / TVDE-CAMPO-01] Badge de mensagem nao lida no chat da corrida.
--
-- A coluna tvde_messages.read JA EXISTE em producao (a migration original
-- `tvde_e_chat_messages` foi aplicada fora do repo -> drift). Reafirma-se aqui
-- de forma IDEMPOTENTE para o repo voltar a ser a fonte da verdade, e adiciona-se
-- o RPC de marcar-como-lidas: a tabela nao tem policy de UPDATE por design, por
-- isso o participante marca via SECURITY DEFINER com verificacao de participante.

ALTER TABLE public.tvde_messages
  ADD COLUMN IF NOT EXISTS read boolean NOT NULL DEFAULT false;

CREATE OR REPLACE FUNCTION public.tvde_mark_messages_read(
  p_ride_id uuid,
  p_my_role text
) RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  -- So um participante da corrida (cliente ou motorista) pode marcar lidas.
  IF NOT EXISTS (
    SELECT 1 FROM tvde_rides r
    WHERE r.id = p_ride_id
      AND (r.client_id = auth.uid() OR r.driver_id = auth.uid())
  ) THEN
    RAISE EXCEPTION 'tvde_mark_messages_read: caller % nao e participante da corrida %',
      auth.uid(), p_ride_id;
  END IF;

  -- Marca lidas apenas as mensagens recebidas do OUTRO lado.
  UPDATE public.tvde_messages
     SET read = true
   WHERE tvde_ride_id = p_ride_id
     AND sender_role <> p_my_role
     AND read = false;
END;
$$;

GRANT EXECUTE ON FUNCTION public.tvde_mark_messages_read(uuid, text) TO authenticated;
