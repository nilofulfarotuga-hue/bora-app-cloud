-- TVDE — expõe drivers.work_mode no painel admin de motoristas (A8 paridade).
-- Alteração ADITIVA: acrescenta 'work_mode' ao jsonb de cada motorista.
-- (Mantém tudo o resto igual ao original.)

CREATE OR REPLACE FUNCTION public.admin_tvde_drivers_list()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $function$
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
        'work_mode',       COALESCE(d.work_mode, 'everything'),
        'is_online',       d.is_online,
        'approval_status', d.approval_status,
        'rating',          d.avg_rating,
        'ratings_count',   d.ratings_count,
        'is_banned',       (d.banned_until IS NOT NULL AND d.banned_until > now()) OR COALESCE(d.is_banned, false),
        'banned_until',    d.banned_until,
        'ban_reason',      d.ban_reason,
        'tvde_balance',    COALESCE(b.balance, 0),
        'last_heartbeat_at',   d.last_heartbeat_at,
        'location_updated_at', dl.last_updated,
        'has_fcm_token',       (d.fcm_token IS NOT NULL AND length(d.fcm_token) > 0),
        'active_rides',    (SELECT count(*) FROM public.tvde_rides r
                              WHERE r.driver_id = d.id
                                AND r.status IN ('motorista_atribuido','motorista_a_caminho','motorista_chegou','em_andamento')),
        'total_rides',     (SELECT count(*) FROM public.tvde_rides r
                              WHERE r.driver_id = d.id AND r.status = 'finalizada')
      ) AS row
    FROM public.drivers d
    LEFT JOIN public.tvde_driver_balances b ON b.driver_id = d.id
    LEFT JOIN public.driver_locations dl ON dl.driver_id = d.user_id
    WHERE d.vehicle_type = 'carro_passageiros'
  ) s;

  RETURN v_out;
END; $function$;
