-- Sessão 2026-05-26 — admin_list_clients retorna photo_url
-- O admin panel não estava a mostrar fotos de cliente. Adiciona coluna
-- photo_url ao retorno do RPC; fonte primária public.users.photo_url
-- (escrita pelo profile_screen via AuthStore.updateCurrentUserPhoto),
-- fallback auth.users.raw_user_meta_data->>'bora_photo_url'.

DROP FUNCTION IF EXISTS public.admin_list_clients(text, boolean, integer, integer);

CREATE OR REPLACE FUNCTION public.admin_list_clients(
  p_search text DEFAULT NULL::text,
  p_banned_only boolean DEFAULT false,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  user_id uuid,
  email text,
  bora_name text,
  bora_phone text,
  photo_url text,
  created_at timestamp with time zone,
  last_sign_in_at timestamp with time zone,
  is_banned boolean,
  banned_until timestamp with time zone,
  total_orders bigint,
  total_spent numeric,
  token_balance integer
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_admin RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_limit < 1 OR p_limit > 500 THEN RAISE EXCEPTION 'limit 1..500'; END IF;

  RETURN QUERY
  WITH clients_base AS (
    SELECT
      u.id,
      u.email::TEXT AS email,
      COALESCE(u.raw_user_meta_data->>'bora_name', '')::TEXT  AS bora_name,
      COALESCE(u.raw_user_meta_data->>'bora_phone', '')::TEXT AS bora_phone,
      COALESCE(
        NULLIF(pu.photo_url, ''),
        u.raw_user_meta_data->>'bora_photo_url',
        ''
      )::TEXT AS photo_url,
      u.created_at,
      u.last_sign_in_at,
      (u.banned_until IS NOT NULL AND u.banned_until > now()) AS is_banned,
      u.banned_until
    FROM auth.users u
    LEFT JOIN public.users pu ON pu.id = u.id
    WHERE COALESCE(u.raw_user_meta_data->>'bora_role', 'client') = 'client'
      AND (
        p_search IS NULL
        OR u.email                                ILIKE '%' || p_search || '%'
        OR (u.raw_user_meta_data->>'bora_name')   ILIKE '%' || p_search || '%'
        OR (u.raw_user_meta_data->>'bora_phone')  ILIKE '%' || p_search || '%'
      )
      AND (NOT p_banned_only OR (u.banned_until IS NOT NULL AND u.banned_until > now()))
  )
  SELECT
    cb.id, cb.email, cb.bora_name, cb.bora_phone, cb.photo_url,
    cb.created_at, cb.last_sign_in_at, cb.is_banned, cb.banned_until,
    COALESCE(o.cnt, 0)            AS total_orders,
    COALESCE(o.total, 0)::NUMERIC AS total_spent,
    COALESCE(t.balance, 0)        AS token_balance
  FROM clients_base cb
  LEFT JOIN LATERAL (
    SELECT count(*) AS cnt, sum(orders.price) AS total
      FROM public.orders
      WHERE orders.user_id = cb.id AND orders.status = 'delivered'
  ) o ON true
  LEFT JOIN LATERAL (
    SELECT COALESCE(sum(bora_tokens.amount), 0)::INT AS balance
      FROM public.bora_tokens
      WHERE bora_tokens.user_id = cb.id
        AND COALESCE(bora_tokens.is_used, false) = false
        AND (bora_tokens.expires_at IS NULL OR bora_tokens.expires_at > now())
  ) t ON true
  ORDER BY cb.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$function$;
