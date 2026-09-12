-- ============================================================================
-- BORA MOTORISTA (TVDE) — FASE 5 · RPCs de LEITURA para o painel admin
-- ============================================================================
-- ADITIVO. Não toca em nenhuma RPC existente nem em zonas protegidas.
-- 4 RPCs read-only (SELECT) que resolvem o PERFIL do cliente a partir de
-- auth.users.raw_user_meta_data (bora_name/bora_phone/bora_photo_url) — algo
-- que o PostgREST não consegue fazer por embed (schema auth não exposto).
-- Identidade resolvida igual ao admin_list_clients (fonte da verdade).
-- Todas gated por _admin_op_guard() (app_metadata.role=admin) e
-- REVOKE public,anon + GRANT authenticated.
-- ============================================================================

BEGIN;

-- ── 1. Pedidos de acesso + PERFIL COMPLETO do cliente ───────────────────────
-- Prioridade do Danilo: saber QUEM é o cliente antes de aprovar.
CREATE OR REPLACE FUNCTION public.admin_tvde_access_requests_list()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_admin RECORD;
  v_out jsonb;
BEGIN
  SELECT admin_id INTO v_admin FROM public._admin_op_guard();

  SELECT COALESCE(jsonb_agg(s.row ORDER BY s.requested_at DESC), '[]'::jsonb)
    INTO v_out
  FROM (
    SELECT
      r.requested_at AS requested_at,
      jsonb_build_object(
        'request_id',    r.id,
        'status',        r.status,
        'requested_at',  r.requested_at,
        'decided_at',    r.decided_at,
        'decision_note', r.decision_note,
        'client_id',     au.id,
        'name',          COALESCE(au.raw_user_meta_data->>'bora_name', ''),
        'phone',         COALESCE(au.raw_user_meta_data->>'bora_phone', ''),
        'email',         au.email,
        'photo_url',     COALESCE(NULLIF(pu.photo_url, ''), au.raw_user_meta_data->>'bora_photo_url', ''),
        'created_at',    au.created_at,
        'tvde_access',   COALESCE(pu.tvde_access, false),
        'orders_count',  (SELECT count(*) FROM public.orders o WHERE o.user_id = au.id),
        'rides_count',   (SELECT count(*) FROM public.tvde_rides tr WHERE tr.client_id = au.id)
      ) AS row
    FROM public.tvde_access_requests r
    JOIN auth.users au       ON au.id = r.client_id
    LEFT JOIN public.users pu ON pu.id = r.client_id
  ) s;

  RETURN v_out;
END; $$;
REVOKE ALL ON FUNCTION public.admin_tvde_access_requests_list() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_access_requests_list() TO authenticated;

-- ── 2. Corridas (ao vivo + histórico + financeiro) ──────────────────────────
-- p_scope: 'live' (em curso) | 'history' (terminadas/canceladas) | 'all'
-- Posição ao vivo do motorista vem de driver_locations (mesmo live-ops do delivery).
CREATE OR REPLACE FUNCTION public.admin_tvde_rides_list(
  p_scope TEXT DEFAULT 'all',
  p_limit INTEGER DEFAULT 200
)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_admin RECORD;
  v_out jsonb;
BEGIN
  SELECT admin_id INTO v_admin FROM public._admin_op_guard();
  IF p_limit < 1 OR p_limit > 1000 THEN RAISE EXCEPTION 'limit 1..1000'; END IF;

  SELECT COALESCE(jsonb_agg(s.row ORDER BY s.created_at DESC), '[]'::jsonb)
    INTO v_out
  FROM (
    SELECT
      ride.created_at AS created_at,
      jsonb_build_object(
        'id',                     ride.id,
        'status',                 ride.status,
        'created_at',             ride.created_at,
        'updated_at',             ride.updated_at,
        'origin_label',           ride.origin_label,
        'dest_label',             ride.dest_label,
        'est_distance_km',        ride.est_distance_km,
        'est_fare_cents',         ride.est_fare_cents,
        'final_distance_km',      ride.final_distance_km,
        'final_fare_cents',       ride.final_fare_cents,
        'driver_earn_cents',      ride.driver_earn_cents,
        'bora_cut_cents',         ride.bora_cut_cents,
        'cancel_fee_cents',       ride.cancel_fee_cents,
        'cancel_reason',          ride.cancel_reason,
        'payment_method',         ride.payment_method,
        'used_subscription_ride', ride.used_subscription_ride,
        'offer_expires_at',       ride.offer_expires_at,
        'client_id',              ride.client_id,
        'client_name',            COALESCE(au.raw_user_meta_data->>'bora_name', ''),
        'client_phone',           COALESCE(au.raw_user_meta_data->>'bora_phone', ''),
        'driver_id',              ride.driver_id,
        'driver_name',            d.name,
        'driver_phone',           d.phone,
        'driver_is_online',       d.is_online,
        'driver_lat',             dl.latitude,
        'driver_lng',             dl.longitude,
        'driver_loc_updated_at',  dl.last_updated
      ) AS row
    FROM public.tvde_rides ride
    LEFT JOIN auth.users au           ON au.id = ride.client_id
    LEFT JOIN public.drivers d        ON d.id = ride.driver_id
    LEFT JOIN public.driver_locations dl ON dl.driver_id = ride.driver_id
    WHERE CASE
      WHEN p_scope = 'live' THEN ride.status IN
        ('solicitada','motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')
      WHEN p_scope = 'history' THEN ride.status IN
        ('finalizada','cancelada_cliente','cancelada_motorista','no_show','sem_motorista')
      ELSE true
    END
    ORDER BY ride.created_at DESC
    LIMIT p_limit
  ) s;

  RETURN v_out;
END; $$;
REVOKE ALL ON FUNCTION public.admin_tvde_rides_list(TEXT, INTEGER) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_rides_list(TEXT, INTEGER) TO authenticated;

-- ── 3. Motoristas de passageiros (gerir / banir) ────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_tvde_drivers_list()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_admin RECORD;
  v_out jsonb;
BEGIN
  SELECT admin_id INTO v_admin FROM public._admin_op_guard();

  SELECT COALESCE(jsonb_agg(s.row ORDER BY s.is_online DESC, s.name ASC), '[]'::jsonb)
    INTO v_out
  FROM (
    SELECT
      d.is_online AS is_online,
      d.name AS name,
      jsonb_build_object(
        'id',              d.id,
        'name',            d.name,
        'phone',           d.phone,
        'vehicle_type',    d.vehicle_type,
        'is_online',       d.is_online,
        'approval_status', d.approval_status,
        'rating',          d.avg_rating,
        'ratings_count',   d.ratings_count,
        'is_banned',       (d.banned_until IS NOT NULL AND d.banned_until > now()) OR COALESCE(d.is_banned, false),
        'banned_until',    d.banned_until,
        'ban_reason',      d.ban_reason,
        'tvde_balance',    COALESCE(b.balance, 0),
        'active_rides',    (SELECT count(*) FROM public.tvde_rides r
                              WHERE r.driver_id = d.id
                                AND r.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')),
        'total_rides',     (SELECT count(*) FROM public.tvde_rides r
                              WHERE r.driver_id = d.id AND r.status = 'finalizada')
      ) AS row
    FROM public.drivers d
    LEFT JOIN public.tvde_driver_balances b ON b.driver_id = d.id
    WHERE d.vehicle_type = 'carro_passageiros'
  ) s;

  RETURN v_out;
END; $$;
REVOKE ALL ON FUNCTION public.admin_tvde_drivers_list() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_drivers_list() TO authenticated;

-- ── 4. Assinaturas (conceder / ver activas) ─────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_tvde_subscriptions_list()
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public, auth AS $$
DECLARE
  v_admin RECORD;
  v_out jsonb;
BEGIN
  SELECT admin_id INTO v_admin FROM public._admin_op_guard();

  SELECT COALESCE(jsonb_agg(s.row ORDER BY s.active DESC, s.created_at DESC), '[]'::jsonb)
    INTO v_out
  FROM (
    SELECT
      sub.active AS active,
      sub.created_at AS created_at,
      jsonb_build_object(
        'id',             sub.id,
        'client_id',      sub.client_id,
        'client_name',    COALESCE(au.raw_user_meta_data->>'bora_name', ''),
        'client_phone',   COALESCE(au.raw_user_meta_data->>'bora_phone', ''),
        'client_email',   au.email,
        'plan',           sub.plan,
        'rides_total',    sub.rides_total,
        'rides_used',     sub.rides_used,
        'daily_included', sub.daily_included,
        'price_cents',    sub.price_cents,
        'starts_at',      sub.starts_at,
        'ends_at',        sub.ends_at,
        'active',         sub.active,
        'created_at',     sub.created_at
      ) AS row
    FROM public.tvde_subscriptions sub
    LEFT JOIN auth.users au ON au.id = sub.client_id
  ) s;

  RETURN v_out;
END; $$;
REVOKE ALL ON FUNCTION public.admin_tvde_subscriptions_list() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_tvde_subscriptions_list() TO authenticated;

COMMIT;
