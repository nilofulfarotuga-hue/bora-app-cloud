-- =============================================================================
-- ronda-fecho-2026-09-22 · A5 — a criação de reserva pela central caiu em not_admin
--
-- Causa provada (postgres_logs 19/09 08:58:48Z, 09:00:44Z, 09:03:56Z):
--   select public.admin_tvde_counter_clients_list('Tatiana')  -- source: POST /mcp
--   -> PL/pgSQL function admin_tvde_counter_clients_list(text) line 4 at RAISE: not_admin
-- A "central" é a Claude.ai/Claude Code por MCP: liga-se como `postgres`, SEM JWT,
-- logo auth.uid() é NULL e is_admin() devolve false. A pesquisa do cliente já
-- falhava, por isso a reserva da Tatiana Sanha (19/09 12h40) nunca foi criada.
--
-- Correção (sem alargar is_admin nem os admin_*): o mesmo caminho seguro que já
-- existe para as entregas (ops_reassign_order, 16/09) — funções ops_tvde_* só
-- para agentes (service_role / MCP), que assumem o JWT do admin durante a
-- chamada, invocam a função admin_* de sempre e deixam registo em
-- admin_audit_log com o nome do agente. As guardas dos admin_* ficam iguais.
-- =============================================================================

-- Assume o JWT do admin (conta do painel) só dentro da transação; devolve o que
-- lá estava para repor no fim. Só é chamável pelas ops_* (não é exposta).
CREATE OR REPLACE FUNCTION public._ops_assume_admin()
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_antes text := current_setting('request.jwt.claims', true);
  c_admin_uid constant text := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
BEGIN
  -- Só sem JWT (MCP) ou com a chave service_role. Um utilizador normal nunca.
  IF auth.uid() IS NOT NULL THEN
    RAISE EXCEPTION 'ops_only_for_agents' USING ERRCODE = '42501';
  END IF;
  IF COALESCE(v_antes, '') NOT IN ('', 'null') AND COALESCE(auth.role(), '') <> 'service_role' THEN
    RAISE EXCEPTION 'ops_only_for_agents' USING ERRCODE = '42501';
  END IF;
  PERFORM set_config('request.jwt.claims',
    json_build_object('sub', c_admin_uid, 'role', 'authenticated',
                      'email', 'nilofulfarotuga@gmail.com',
                      'app_metadata', json_build_object('role', 'admin'))::text, true);
  RETURN COALESCE(v_antes, '');
END $function$;
REVOKE ALL ON FUNCTION public._ops_assume_admin() FROM PUBLIC;
REVOKE ALL ON FUNCTION public._ops_assume_admin() FROM anon, authenticated;

CREATE OR REPLACE FUNCTION public.ops_tvde_counter_clients_list(p_query text DEFAULT NULL::text, p_agente text DEFAULT 'claude-code'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_antes text; v_out jsonb;
BEGIN
  v_antes := public._ops_assume_admin();
  BEGIN
    v_out := public.admin_tvde_counter_clients_list(p_query);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claims', v_antes, true);
    RAISE;
  END;
  PERFORM set_config('request.jwt.claims', v_antes, true);
  RETURN v_out;
END $function$;

CREATE OR REPLACE FUNCTION public.ops_tvde_counter_client_save(p_client_id uuid DEFAULT NULL::uuid, p_name text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_agente text DEFAULT 'claude-code'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_antes text; v_id uuid;
BEGIN
  v_antes := public._ops_assume_admin();
  BEGIN
    v_id := public.admin_tvde_counter_client_save(p_client_id, p_name, p_phone);
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claims', v_antes, true);
    RAISE;
  END;
  PERFORM set_config('request.jwt.claims', v_antes, true);
  INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, admin_email, details)
  VALUES ('tvde_counter_client_saved_by_agent', 'user', v_id::text, 'agente:' || p_agente,
          jsonb_build_object('agente', p_agente, 'name', p_name, 'phone', p_phone));
  RETURN v_id;
END $function$;

CREATE OR REPLACE FUNCTION public.ops_tvde_create_counter_ride(p_client_id uuid DEFAULT NULL::uuid, p_client_name text DEFAULT NULL::text, p_client_phone text DEFAULT NULL::text, p_origin_label text DEFAULT NULL::text, p_origin_lat double precision DEFAULT NULL::double precision, p_origin_lng double precision DEFAULT NULL::double precision, p_dest_label text DEFAULT NULL::text, p_dest_lat double precision DEFAULT NULL::double precision, p_dest_lng double precision DEFAULT NULL::double precision, p_fare_cents integer DEFAULT NULL::integer, p_driver_earn_cents integer DEFAULT NULL::integer, p_est_distance_km numeric DEFAULT NULL::numeric, p_note text DEFAULT NULL::text, p_agente text DEFAULT 'claude-code'::text)
 RETURNS tvde_rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_antes text; v_ride public.tvde_rides;
BEGIN
  v_antes := public._ops_assume_admin();
  BEGIN
    v_ride := public.admin_tvde_create_counter_ride(p_client_id, p_client_name, p_client_phone,
                p_origin_label, p_origin_lat, p_origin_lng, p_dest_label, p_dest_lat, p_dest_lng,
                p_fare_cents, p_driver_earn_cents, p_est_distance_km,
                left('[agente ' || p_agente || '] ' || COALESCE(p_note, ''), 500));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claims', v_antes, true);
    RAISE;
  END;
  PERFORM set_config('request.jwt.claims', v_antes, true);
  INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, admin_email, details)
  VALUES ('tvde_counter_ride_created_by_agent', 'tvde_ride', v_ride.id::text, 'agente:' || p_agente,
          jsonb_build_object('agente', p_agente, 'client_id', v_ride.client_id,
                             'origin', p_origin_label, 'dest', p_dest_label,
                             'fare_cents', v_ride.agreed_fare_cents, 'driver_earn_cents', v_ride.agreed_driver_earn_cents));
  RETURN v_ride;
END $function$;

CREATE OR REPLACE FUNCTION public.ops_tvde_reservation_create(p_client_id uuid, p_origin_lat double precision, p_origin_lng double precision, p_origin_label text, p_dest_lat double precision, p_dest_lng double precision, p_dest_label text, p_est_distance_km numeric, p_scheduled_at timestamp with time zone, p_note text DEFAULT NULL::text, p_agente text DEFAULT 'claude-code'::text)
 RETURNS tvde_rides
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_antes text; v_ride public.tvde_rides;
BEGIN
  v_antes := public._ops_assume_admin();
  BEGIN
    v_ride := public.admin_tvde_reservation_create(p_client_id, p_origin_lat, p_origin_lng, p_origin_label,
                p_dest_lat, p_dest_lng, p_dest_label, p_est_distance_km, p_scheduled_at,
                left('[agente ' || p_agente || '] ' || COALESCE(p_note, ''), 500));
  EXCEPTION WHEN OTHERS THEN
    PERFORM set_config('request.jwt.claims', v_antes, true);
    RAISE;
  END;
  PERFORM set_config('request.jwt.claims', v_antes, true);
  INSERT INTO public.admin_audit_log (action, entity_type, entity_id_text, admin_email, details)
  VALUES ('tvde_reservation_created_by_agent', 'tvde_ride', v_ride.id::text, 'agente:' || p_agente,
          jsonb_build_object('agente', p_agente, 'client_id', p_client_id, 'scheduled_at', p_scheduled_at,
                             'origin', p_origin_label, 'dest', p_dest_label, 'km', p_est_distance_km));
  RETURN v_ride;
END $function$;

-- Só agentes: nunca anon/authenticated (a app usa os admin_* com o JWT do admin).
REVOKE ALL ON FUNCTION public.ops_tvde_counter_clients_list(text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ops_tvde_counter_clients_list(text, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_tvde_counter_clients_list(text, text) TO service_role;
REVOKE ALL ON FUNCTION public.ops_tvde_counter_client_save(uuid, text, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ops_tvde_counter_client_save(uuid, text, text, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_tvde_counter_client_save(uuid, text, text, text) TO service_role;
REVOKE ALL ON FUNCTION public.ops_tvde_create_counter_ride(uuid, text, text, text, double precision, double precision, text, double precision, double precision, integer, integer, numeric, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ops_tvde_create_counter_ride(uuid, text, text, text, double precision, double precision, text, double precision, double precision, integer, integer, numeric, text, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_tvde_create_counter_ride(uuid, text, text, text, double precision, double precision, text, double precision, double precision, integer, integer, numeric, text, text) TO service_role;
REVOKE ALL ON FUNCTION public.ops_tvde_reservation_create(uuid, double precision, double precision, text, double precision, double precision, text, numeric, timestamp with time zone, text, text) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.ops_tvde_reservation_create(uuid, double precision, double precision, text, double precision, double precision, text, numeric, timestamp with time zone, text, text) FROM anon, authenticated;
GRANT EXECUTE ON FUNCTION public.ops_tvde_reservation_create(uuid, double precision, double precision, text, double precision, double precision, text, numeric, timestamp with time zone, text, text) TO service_role;

COMMENT ON FUNCTION public.ops_tvde_reservation_create(uuid, double precision, double precision, text, double precision, double precision, text, numeric, timestamp with time zone, text, text) IS
'Caminho da central (Claude.ai/Claude Code por MCP, agentes com service_role) para criar uma reserva TVDE em dinheiro em nome de um cliente. Assume o JWT do admin só durante a chamada e regista em admin_audit_log. A app continua a usar admin_tvde_reservation_create.';
