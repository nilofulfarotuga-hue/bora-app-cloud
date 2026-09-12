-- Parte C (2026-06-12): chat_mark_read v2  [APLICADA em prod via MCP 2026-06-12]
-- Fix 1 (CRÍTICO): o UPDATE falhava SEMPRE com "operator does not exist:
--   uuid = text" (messages.order_id é uuid; p_order_id é text). O erro era
--   engolido no app → read nunca marcado → badges nunca zeravam e ✓✓ nunca
--   aparecia, desde M11.
-- Fix 2: novo p_conversation_type — marca lidas APENAS do par aberto
--   (threads separadas por papel: abrir o chat do estafeta não pode zerar o
--   badge do parceiro). NULL = todos os pares (compat builds antigos).
--   Mensagens legacy com conversation_type NULL aparecem em todas as threads
--   na UI, por isso são marcadas em qualquer par.
DROP FUNCTION IF EXISTS public.chat_mark_read(text, text);

CREATE OR REPLACE FUNCTION public.chat_mark_read(
  p_order_id text,
  p_reader_type text,
  p_conversation_type text DEFAULT NULL
) RETURNS integer
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_order record;
  v_is_participant boolean := false;
  v_count int;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'auth_required'; END IF;
  IF p_reader_type NOT IN ('client','driver','partner') THEN
    RAISE EXCEPTION 'invalid_reader_type';
  END IF;
  IF p_conversation_type IS NOT NULL AND p_conversation_type NOT IN
     ('client_driver','client_partner','driver_partner') THEN
    RAISE EXCEPTION 'invalid_conversation_type';
  END IF;

  SELECT user_id, assigned_driver_id, restaurant_id INTO v_order
    FROM orders WHERE id = p_order_id;
  IF v_order IS NULL THEN RAISE EXCEPTION 'order_not_found'; END IF;

  v_is_participant := CASE p_reader_type
    WHEN 'client'  THEN v_order.user_id = v_uid
    WHEN 'driver'  THEN v_order.assigned_driver_id = v_uid::text
    WHEN 'partner' THEN EXISTS (
      SELECT 1 FROM restaurants r
       WHERE r.id = v_order.restaurant_id
         AND COALESCE(r.user_id, r.user_) = v_uid)
    END;
  IF NOT v_is_participant THEN RAISE EXCEPTION 'not_a_participant'; END IF;

  UPDATE messages
     SET read = true
   WHERE order_id::text = p_order_id
     AND sender_type <> p_reader_type
     AND COALESCE(read, false) = false
     AND (p_conversation_type IS NULL
          OR conversation_type IS NULL
          OR conversation_type = p_conversation_type);
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END $function$;

REVOKE ALL ON FUNCTION public.chat_mark_read(text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.chat_mark_read(text, text, text)
  TO authenticated, service_role;
