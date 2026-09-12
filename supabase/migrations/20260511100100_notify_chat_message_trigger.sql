-- ═══════════════════════════════════════════════════════════════════════════
-- BLOCO 1.6 — Trigger AFTER INSERT messages → notify-chat-message
-- Pattern: igual a _notify_admin_urgent_trigger (5F-β)
-- Gate pg_net settings (app.supabase_url + app.service_role_key); skip silent
-- se settings em falta. NUNCA bloqueia o INSERT.
-- ═══════════════════════════════════════════════════════════════════════════

CREATE OR REPLACE FUNCTION public._notify_chat_message_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, net
AS $trg$
DECLARE
  v_url text;
  v_key text;
BEGIN
  -- Só client→driver ou driver→client (system/admin não dispara push)
  IF NEW.sender_type IS NULL
     OR NEW.sender_type NOT IN ('client','driver') THEN
    RETURN NEW;
  END IF;

  IF NEW.order_id IS NULL THEN
    RETURN NEW;
  END IF;

  v_url := current_setting('app.supabase_url', true);
  v_key := current_setting('app.service_role_key', true);

  IF v_url IS NULL OR v_url = ''
     OR v_key IS NULL OR v_key = '' THEN
    RAISE NOTICE '5G: pg_net settings MISSING — skipping notify-chat-message for message %', NEW.id;
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url     := v_url || '/functions/v1/notify-chat-message',
    headers := jsonb_build_object(
                 'Authorization', 'Bearer ' || v_key,
                 'Content-Type',  'application/json'
               ),
    body    := jsonb_build_object('message_id', NEW.id)
  );

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '5G: notify-chat-message trigger error: %', SQLERRM;
  RETURN NEW;
END;
$trg$;

DROP TRIGGER IF EXISTS trg_messages_notify_chat ON public.messages;
CREATE TRIGGER trg_messages_notify_chat
  AFTER INSERT ON public.messages
  FOR EACH ROW
  EXECUTE FUNCTION public._notify_chat_message_trigger();

COMMENT ON FUNCTION public._notify_chat_message_trigger() IS
  '5G: AFTER INSERT messages → POST notify-chat-message via pg_net (silent skip se pg_net settings MISSING; nunca bloqueia INSERT). Decisão B (dispara sempre), Decisão C (Edge Fn marca tokens inactivos após 3 falhas).';
