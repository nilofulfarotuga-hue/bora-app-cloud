-- ═══════════════════════════════════════════════════════════════════════════
-- BUG-CHAT-01 root cause #1 — Trigger AFTER INSERT messages
-- Versão anterior (20260511100100) só disparava para sender_type IN ('client','driver').
-- Quando o parceiro envia mensagem (sender_type='partner') o trigger saía sem
-- chamar notify-chat-message → nenhum push chegava ao cliente nem ao estafeta.
--
-- Esta migration alarga o gate para incluir 'partner'. A Edge Function v3
-- (notify-chat-message) já suporta routing para sender_type='partner' nos
-- canais client_partner e driver_partner; estava apenas bloqueada no trigger.
--
-- Nenhuma outra lógica é alterada. Pattern continua igual a
-- _notify_admin_urgent_trigger: gate pg_net settings (silent skip se em falta),
-- nunca bloqueia o INSERT.
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
  IF NEW.sender_type IS NULL
     OR NEW.sender_type NOT IN ('client','driver','partner') THEN
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

COMMENT ON FUNCTION public._notify_chat_message_trigger() IS
  'AFTER INSERT messages → POST notify-chat-message via pg_net. v2: aceita sender_type partner (BUG-CHAT-01 fix 2026-05-20). Silent skip se pg_net settings MISSING; nunca bloqueia INSERT.';
