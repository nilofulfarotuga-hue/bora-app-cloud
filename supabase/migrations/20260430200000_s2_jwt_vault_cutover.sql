-- S2: JWT vault cutover. Moves the dispatch anon JWT from hardcoded literals
-- in 4 source migrations to vault.decrypted_secrets. Helper _dispatch_jwt()
-- exposes it only to authenticated + service_role.
--
-- Pre-requisite (manual): SELECT vault.create_secret(<jwt>, 'dispatch_anon_jwt', '...');
-- This migration assumes the secret already exists.

CREATE OR REPLACE FUNCTION public._dispatch_jwt()
RETURNS text
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public, vault
AS $$
DECLARE
  v_jwt text;
BEGIN
  SELECT decrypted_secret INTO v_jwt
  FROM vault.decrypted_secrets
  WHERE name = 'dispatch_anon_jwt';
  IF v_jwt IS NULL THEN
    RAISE EXCEPTION 'dispatch_jwt_not_in_vault: run vault.create_secret first';
  END IF;
  RETURN v_jwt;
END;
$$;

REVOKE ALL ON FUNCTION public._dispatch_jwt FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._dispatch_jwt TO authenticated, service_role;

-- Refactor bora_dispatch_maintenance to read JWT from vault.
CREATE OR REPLACE FUNCTION public.bora_dispatch_maintenance()
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_order record;
  v_rejected_count int;
  v_cancelled_count int;
  v_jwt text := public._dispatch_jwt();
BEGIN
  WITH abandoned AS (
    UPDATE public.orders
    SET status = 'cancelled', payment_status = 'failed', cancel_reason = 'payment_abandoned'
    WHERE status = 'created' AND payment_status = 'pending'
      AND payment_method IN ('card', 'mbway')
      AND created_at < NOW() - INTERVAL '10 minutes'
    RETURNING id
  )
  SELECT count(*) INTO v_cancelled_count FROM abandoned;
  IF v_cancelled_count > 0 THEN
    RAISE NOTICE '[bora_dispatch_maintenance] auto-cancelled % abandoned payment(s)', v_cancelled_count;
  END IF;

  WITH expired AS (
    UPDATE public.orders
    SET status = 'rejected', current_driver_offer_id = NULL, driver_offer_expires_at = NULL
    WHERE status = 'callingDriver' AND assigned_driver_id IS NULL
      AND created_at < NOW() - INTERVAL '30 minutes'
    RETURNING id
  )
  SELECT count(*) INTO v_rejected_count FROM expired;
  IF v_rejected_count > 0 THEN
    RAISE NOTICE '[bora_dispatch_maintenance] auto-rejected % stale order(s)', v_rejected_count;
  END IF;

  UPDATE public.orders
  SET tried_driver_ids = array_append(COALESCE(tried_driver_ids, '{}'::text[]), current_driver_offer_id),
      current_driver_offer_id = NULL,
      driver_offer_expires_at = NULL
  WHERE status = 'callingDriver'
    AND assigned_driver_id IS NULL
    AND current_driver_offer_id IS NOT NULL
    AND driver_offer_expires_at IS NOT NULL
    AND driver_offer_expires_at < NOW();

  FOR v_order IN
    SELECT id FROM public.orders
    WHERE status = 'callingDriver' AND assigned_driver_id IS NULL
      AND current_driver_offer_id IS NULL
  LOOP
    PERFORM extensions.net.http_post(
      url     := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/dispatch-engine',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_jwt
      ),
      body    := jsonb_build_object('orderId', v_order.id::text)
    );
  END LOOP;
END;
$function$;

-- Refactor fn_dispatch_on_calling_driver trigger.
CREATE OR REPLACE FUNCTION public.fn_dispatch_on_calling_driver()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_jwt text;
BEGIN
  IF NEW.status = 'callingDriver'
    AND (OLD.status IS DISTINCT FROM 'callingDriver')
    AND NEW.assigned_driver_id IS NULL
  THEN
    v_jwt := public._dispatch_jwt();
    PERFORM net.http_post(
      url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/dispatch-engine',
      headers := jsonb_build_object(
        'Content-Type', 'application/json',
        'Authorization', 'Bearer ' || v_jwt
      ),
      body := jsonb_build_object('orderId', NEW.id::text)
    );
  END IF;
  RETURN NEW;
END;
$function$;
