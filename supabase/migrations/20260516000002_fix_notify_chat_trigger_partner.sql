-- Fix _notify_chat_message_trigger to include sender_type='partner'.
-- Previous version only allowed 'client' and 'driver' — partner messages
-- were silently skipped, causing no push notification for the recipients.
CREATE OR REPLACE FUNCTION public._notify_chat_message_trigger()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER
SET search_path TO 'public', 'net'
AS $$
DECLARE
  v_url text;
  v_key text;
BEGIN
  -- Guard: process client, driver AND partner
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
    body    := jsonb_build_object('message_id', NEW.id)
  );

  RETURN NEW;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'notify-chat trigger error: %', SQLERRM;
  RETURN NEW;
END;
$$;
