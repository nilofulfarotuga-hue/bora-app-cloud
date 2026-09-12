-- RPC helper for notify-chat-message v2.
-- Returns active FCM tokens for the partner that owns a restaurant,
-- resolved via auth.users.email = restaurants.email.
-- Called by the Edge Function with service_role — never exposed to end users.
CREATE OR REPLACE FUNCTION public.get_partner_fcm_tokens_for_restaurant(
  p_restaurant_id text
)
RETURNS TABLE(fcm_token text, token_id uuid)
LANGUAGE sql SECURITY DEFINER
SET search_path = public, auth
AS $$
  SELECT ppt.fcm_token, ppt.id
  FROM public.partner_push_tokens ppt
  JOIN auth.users u ON ppt.partner_id = u.id
  JOIN public.restaurants r ON lower(u.email::text) = lower(r.email)
  WHERE r.id = p_restaurant_id AND ppt.active = true;
$$;

REVOKE ALL ON FUNCTION public.get_partner_fcm_tokens_for_restaurant(text)
  FROM public, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.get_partner_fcm_tokens_for_restaurant(text)
  TO service_role;
