-- M11.A — ROOT CAUSE push de chat: o trigger enviava só {message_id} mas a
-- Edge notify-chat-message v9 exige message_id+order_id+sender_id → 400 em
-- TODAS as invocações (push nunca saía). Trigger v2 envia o payload completo.
-- (Par na Edge v10: order.driver_id→assigned_driver_id, restaurants.user_→
--  COALESCE(user_id,user_), +client_push_tokens, partner_push_tokens.partner_id
--  — outros 4 elos quebrados na resolução do destinatário/tokens.)

CREATE OR REPLACE FUNCTION public._notify_chat_message_trigger()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'net'
AS $function$
DECLARE
  v_url text;
  v_key text;
BEGIN
  IF NEW.sender_type IS NULL OR
     NEW.sender_type NOT IN ('client', 'driver', 'partner') THEN
    RETURN NEW;
  END IF;

  IF NEW.order_id IS NULL THEN RETURN NEW; END IF;

  SELECT decrypted_secret INTO v_url FROM vault.decrypted_secrets WHERE name = 'project_url';
  SELECT decrypted_secret INTO v_key FROM vault.decrypted_secrets WHERE name = 'service_role_key';

  IF v_url IS NULL OR v_key IS NULL THEN
    RAISE NOTICE 'notify-chat: vault secrets MISSING — skipping for message %', NEW.id;
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url     := v_url || '/functions/v1/notify-chat-message',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_key,
      'Content-Type', 'application/json'
    ),
    -- v2 (M11): payload COMPLETO exigido pela Edge (messages não tem sender_id
    -- — envia-se sender_type também nesse campo; o device usa sender_type/name).
    body    := jsonb_build_object(
      'message_id',        NEW.id,
      'order_id',          NEW.order_id,
      'sender_id',         NEW.sender_type,
      'sender_type',       NEW.sender_type,
      'conversation_type', COALESCE(NEW.conversation_type, ''),
      'body',              LEFT(COALESCE(NEW.message, ''), 140)
    )
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'notify-chat trigger error: %', SQLERRM;
  RETURN NEW;
END;
$function$;

-- M11.B — marcar mensagens como lidas (badge de não-lidas usa messages.read).
-- Valida que o leitor é participante do pedido no papel que declara.
CREATE OR REPLACE FUNCTION public.chat_mark_read(p_order_id text, p_reader_type text)
 RETURNS integer
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
   WHERE order_id = p_order_id
     AND sender_type <> p_reader_type
     AND COALESCE(read, false) = false;
  GET DIAGNOSTICS v_count = ROW_COUNT;
  RETURN v_count;
END $function$;

-- M11 (admin) — viewer read-only de conversas com audit no acesso.
CREATE OR REPLACE FUNCTION public.admin_list_order_messages(p_order_id text)
 RETURNS SETOF messages
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
BEGIN
  PERFORM public._admin_op_guard();
  INSERT INTO admin_audit_log (action, entity_type, entity_id_text, details)
  VALUES ('chat_viewed', 'order', p_order_id,
          jsonb_build_object('mechanism', 'admin_list_order_messages'));
  RETURN QUERY
    SELECT * FROM messages WHERE order_id = p_order_id
     ORDER BY created_at ASC LIMIT 500;
END $function$;

-- Grants pós-hardening (novas funções nascem com EXECUTE p/ PUBLIC — fechar):
REVOKE EXECUTE ON FUNCTION public.chat_mark_read(text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.chat_mark_read(text, text) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public.admin_list_order_messages(text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_order_messages(text) TO authenticated, service_role;
REVOKE EXECUTE ON FUNCTION public._notify_chat_message_trigger() FROM PUBLIC, anon, authenticated;
