-- BUG 2A Parte 2 — Reactivate FCM push for reservation/waitlist triggers.
--
-- Context:
--   Triggers `trg_reservation_notify_partner_new` and
--   `trg_waitlist_notify_partner_new` already fire on INSERT and call
--   `_reservas_pro_notify_partner_push`. That helper has been doing the
--   in-app notification only — the FCM call was commented out, waiting
--   for proper secret plumbing.
--
-- Change:
--   • Resolve restaurant_id from the partner user_id so the existing
--     `notify-partner` Edge Function (which keys off `restaurants.fcm_token`)
--     can be reused as-is.
--   • Pull `project_url` and `service_role_key` from `vault.decrypted_secrets`
--     instead of `current_setting()` — both already exist in the project Vault.
--   • Fire-and-forget via `pg_net.http_post`. If anything is missing
--     (no restaurant, no Vault entry, etc.) the function returns silently
--     so the trigger never blocks the surrounding INSERT.
--   • In-app notification path is unchanged.
--   • New optional fields `customTitle`/`customBody`/`kind` map directly to
--     the Edge Function v12 contract (deployed in Parte 1).

CREATE OR REPLACE FUNCTION public._reservas_pro_notify_partner_push(
  p_partner_user_id uuid,
  p_kind            text,
  p_title           text,
  p_body            text,
  p_related_id      text
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
DECLARE
  v_restaurant_id text;
  v_supabase_url  text;
  v_service_key   text;
BEGIN
  IF p_partner_user_id IS NULL THEN RETURN; END IF;

  -- 1) In-app notification (sempre)
  PERFORM _push_in_app_notification(
    p_partner_user_id, p_kind, p_title, p_body, p_related_id
  );

  -- 2) Resolve restaurant_id (notify-partner consome restaurants.fcm_token)
  SELECT id INTO v_restaurant_id
  FROM restaurants
  WHERE user_ = p_partner_user_id
  LIMIT 1;
  IF v_restaurant_id IS NULL THEN RETURN; END IF;

  -- 3) Read Edge Function URL + auth from Vault. Silent fail if missing.
  SELECT decrypted_secret INTO v_supabase_url
  FROM vault.decrypted_secrets WHERE name = 'project_url' LIMIT 1;
  SELECT decrypted_secret INTO v_service_key
  FROM vault.decrypted_secrets WHERE name = 'service_role_key' LIMIT 1;
  IF v_supabase_url IS NULL OR v_service_key IS NULL THEN RETURN; END IF;

  -- 4) FCM via pg_net (fire-and-forget; failure does not block the INSERT)
  PERFORM net.http_post(
    url     := v_supabase_url || '/functions/v1/notify-partner',
    headers := jsonb_build_object(
      'Content-Type',  'application/json',
      'Authorization', 'Bearer ' || v_service_key
    ),
    body := jsonb_build_object(
      'orderId',      COALESCE(p_related_id, ''),
      'restaurantId', v_restaurant_id,
      'items',        '',
      'total',        0,
      'customTitle',  p_title,
      'customBody',   p_body,
      'kind',         p_kind
    )
  );
END;
$function$;
