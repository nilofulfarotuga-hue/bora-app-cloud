-- Sessão 5B-β1 B2 — Trigger push admin AFTER INSERT support_pending_actions
-- Guard: só envia se app.supabase_url configurado (silent skip se NULL).
-- Admin Danilo: c9fccf85-03ee-4efc-83bf-613f211a78ff (auth uid, fcm_token populated)

CREATE OR REPLACE FUNCTION public.fn_notify_admin_pending_action()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id uuid;
  v_supabase_url text;
  v_service_key text;
BEGIN
  IF NEW.status <> 'pending' THEN
    RETURN NEW;
  END IF;

  v_supabase_url := current_setting('app.supabase_url', true);
  v_service_key  := current_setting('app.service_role_key', true);

  IF v_supabase_url IS NULL OR v_service_key IS NULL THEN
    -- pg_net não configurado em prod — fallback Realtime badge (5B-α)
    RETURN NEW;
  END IF;

  SELECT u.id INTO v_admin_id
  FROM users u
  JOIN auth.users au ON au.id = u.id
  WHERE u.fcm_token IS NOT NULL
    AND au.email IN ('nilofulfarotuga@gmail.com','nilofulfaro@gmail.com')
  LIMIT 1;

  IF v_admin_id IS NULL THEN
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url := v_supabase_url || '/functions/v1/notify-client',
    headers := jsonb_build_object(
      'Authorization', 'Bearer ' || v_service_key,
      'Content-Type', 'application/json'
    ),
    body := jsonb_build_object(
      'clientId', v_admin_id,
      'title', 'Nova proposta IA',
      'body', NEW.skill_name || ' — abre o Inbox para aprovar/rejeitar'
    )
  );

  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_zz_pending_action_notify_admin
  ON public.support_pending_actions;

CREATE TRIGGER trg_zz_pending_action_notify_admin
AFTER INSERT ON public.support_pending_actions
FOR EACH ROW
EXECUTE FUNCTION public.fn_notify_admin_pending_action();
