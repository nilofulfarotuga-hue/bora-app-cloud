-- =====================================================================
-- CARWASH - permissoes (GRANT/REVOKE)  |  2026-08-27
--
-- PORQUE ESTE FICHEIRO EXISTE:
-- O Postgres da EXECUTE a PUBLIC por defeito em funcoes novas. Um
-- REVOKE ... FROM anon, authenticated NAO remove esse privilegio
-- herdado - foi verificado ao vivo e as funcoes continuavam abertas.
-- Sem isto, um ANONIMO podia chamar _carwash_notify_user e mandar
-- push a qualquer utilizador, ou disparar os crons.
-- A unica forma correta e REVOKE ... FROM PUBLIC.
-- =====================================================================

-- 1. Fechar TUDO (inclusive o PUBLIC herdado)
DO $do$
DECLARE r record;
BEGIN
  FOR r IN
    SELECT p.oid::regprocedure AS sig
    FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace
    WHERE n.nspname = 'public'
      AND (p.proname LIKE '%carwash%' OR p.proname LIKE 'washer\_%')
  LOOP
    EXECUTE format('REVOKE ALL ON FUNCTION %s FROM PUBLIC, anon, authenticated', r.sig);
  END LOOP;
END $do$;

-- 2. Reabrir SO o que a app precisa

-- usada dentro das policies RLS; devolve apenas o id do proprio utilizador
GRANT EXECUTE ON FUNCTION public._carwash_my_washer_id() TO authenticated;

-- preco visivel antes de haver sessao iniciada
GRANT EXECUTE ON FUNCTION public.carwash_quote(text) TO authenticated, anon;

-- cliente
GRANT EXECUTE ON FUNCTION public.create_carwash_booking(text,text,text,text,timestamptz,text,text,text,double precision,double precision,text,text,text,text,text,jsonb,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.carwash_confirm_completion(uuid,integer,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.cancel_carwash_booking(uuid,text) TO authenticated;

-- lavador
GRANT EXECUTE ON FUNCTION public.washer_accept_booking(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.washer_reject_booking(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.carwash_mark_on_the_way(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.carwash_mark_picked_up(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.carwash_mark_started(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.carwash_mark_delivering(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.carwash_mark_delivered(uuid,jsonb) TO authenticated;

-- admin (o gate real e o is_admin() dentro de cada funcao)
GRANT EXECUTE ON FUNCTION public.admin_list_carwash_bookings(text,date,uuid,text,int,int) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_carwash_booking_detail(uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_create_carwash_booking(text,text,text,timestamptz,text,text,double precision,double precision,text,text,text,text,text,uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_carwash_booking(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_cancel_carwash_booking(uuid,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_reassign_carwash_booking(uuid,uuid) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_washers(text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_update_washer(uuid,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_carwash_settings() TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_set_carwash_setting(text,jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_carwash_group_trips(timestamptz,timestamptz,numeric) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_carwash_recalc_settlement(uuid,date) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_list_carwash_settlements(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_mark_carwash_settlement_paid(uuid,text,text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.admin_export_carwash_csv(date,date) TO authenticated;

-- 3. search_path fixo (alerta function_search_path_mutable)
ALTER FUNCTION public._carwash_touch_updated_at() SET search_path TO 'public';
ALTER FUNCTION public._carwash_distance_km(double precision,double precision,double precision,double precision)
  SET search_path TO 'public';
