-- 5F-β-α B2: Refactor _notify_admin_urgent_trigger (5F-β)
-- current_setting → vault.decrypted_secrets
-- Lógica preservada: filtros, gates, EXCEPTION wrappers, body
-- Aplicado via apply_migration: 5f_beta_alpha_b2_trigger_refactor (2026-05-07)

CREATE OR REPLACE FUNCTION public._notify_admin_urgent_trigger()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'net'
AS $function$
DECLARE
  v_url text;
  v_key text;
BEGIN
  IF NEW.direction <> 'a_to_b'
     OR NEW.urgency <> 'critical'
     OR NEW.status <> 'pending' THEN
    RETURN NEW;
  END IF;

  SELECT decrypted_secret INTO v_url
  FROM vault.decrypted_secrets WHERE name = 'project_url';

  SELECT decrypted_secret INTO v_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key';

  IF v_url IS NULL OR v_url = ''
     OR v_key IS NULL OR v_key = '' THEN
    RAISE NOTICE '5F-beta: vault secrets MISSING — skipping notify-admin-urgent for crosstalk %', NEW.id;
    RETURN NEW;
  END IF;

  PERFORM net.http_post(
    url     := v_url || '/functions/v1/notify-admin-urgent',
    headers := jsonb_build_object(
                 'Authorization', 'Bearer ' || v_key,
                 'Content-Type',  'application/json'
               ),
    body    := jsonb_build_object(
                 'crosstalk_id', NEW.id,
                 'question',     NEW.question,
                 'session_id',   NEW.session_id,
                 'context',      NEW.question_context
               )
  );

  RETURN NEW;

EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '5F-beta: notify-admin-urgent trigger error: %', SQLERRM;
  RETURN NEW;
END;
$function$;
