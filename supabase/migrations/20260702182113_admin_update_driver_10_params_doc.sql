-- 20260702182113_admin_update_driver_10_params_doc.sql
--
-- DOCUMENTA O QUE JÁ ESTÁ NO AR. NÃO MUDA NADA. Escrito a 15/11/2026 (missão painel-admin-15-11,
-- proposta P5.5), lido em produção só com SELECT.
--
-- A migração 20260702182113 ("tvde_g_admin_vehicle_fields", em supabase_migrations.schema_migrations)
-- foi aplicada em produção a 02/07/2026, mas o ficheiro nunca entrou no repo. Ela trocou DUAS funções:
--   * public.admin_update_driver com 10 parâmetros (a cor e a marca/modelo do carro): o texto vivo está
--     abaixo, tal e qual o pg_get_functiondef de 15/11/2026;
--   * public.admin_tvde_drivers_list: NÃO está neste ficheiro (fora do âmbito). O repo só tem versões
--     anteriores dela (a última é 20260702170000); o texto vivo lê-se com
--     select pg_get_functiondef('public.admin_tvde_drivers_list()'::regprocedure);
--
-- Em produção esta versão já está registada como aplicada, por isso `supabase db push` não a volta a
-- correr. Num ambiente novo recria a função exatamente como está no ar (CREATE OR REPLACE, mesmo texto).
-- As permissões são as do ar: só authenticated e service_role (sem anon, sem PUBLIC).
-- A versão de 8 parâmetros é apagada pela proposta P1
-- (docs/propostas/painel-admin-15-11/P1_leitura_admin_pedidos_saldos.PROPOSTA.sql); este ficheiro não
-- lhe toca.
--
-- PROVA de que o texto abaixo é o que está no ar (do "CREATE" até ao "$function$" e a mudança de linha):
--   select md5(pg_get_functiondef(
--     'public.admin_update_driver(uuid,text,text,text,text,text,text,text,text,text)'::regprocedure));
--   -- 0b9debea3e7db8725fdf314344fd7d59   (4788 caracteres, lido a 15/11/2026)

CREATE OR REPLACE FUNCTION public.admin_update_driver(p_driver_id uuid, p_reason text, p_name text DEFAULT NULL::text, p_phone text DEFAULT NULL::text, p_vehicle_type text DEFAULT NULL::text, p_license_plate text DEFAULT NULL::text, p_iban text DEFAULT NULL::text, p_nif text DEFAULT NULL::text, p_vehicle_color text DEFAULT NULL::text, p_vehicle_make_model text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_admin RECORD; v_driver RECORD; v_changed TEXT[] := ARRAY[]::TEXT[]; v_reason_t TEXT;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'reason_required: update needs a reason (min 3 chars)' USING ERRCODE = '23502';
  END IF;
  v_reason_t := trim(p_reason);
  SELECT * INTO v_driver FROM public.drivers WHERE id = p_driver_id;
  IF NOT FOUND THEN RAISE EXCEPTION 'driver_not_found: %', p_driver_id USING ERRCODE = 'P0002'; END IF;
  IF v_driver.deleted_at IS NOT NULL THEN
    RAISE EXCEPTION 'driver_deleted: cannot edit soft-deleted driver (reactivate first)' USING ERRCODE = '23514';
  END IF;
  IF p_vehicle_type IS NOT NULL AND p_vehicle_type NOT IN ('motorcycle', 'car', 'bicycle', 'carro_passageiros') THEN
    RAISE EXCEPTION 'invalid_vehicle_type: %', p_vehicle_type USING ERRCODE = '22023';
  END IF;
  IF p_name IS NOT NULL AND p_name IS DISTINCT FROM v_driver.name THEN
    UPDATE public.drivers SET name = trim(p_name) WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(p_driver_id, v_driver.name, 'name', v_driver.name, trim(p_name), false, v_reason_t);
    v_changed := array_append(v_changed, 'name');
  END IF;
  IF p_phone IS NOT NULL AND p_phone IS DISTINCT FROM v_driver.phone THEN
    UPDATE public.drivers SET phone = trim(p_phone) WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(p_driver_id, v_driver.name, 'phone', v_driver.phone, trim(p_phone), false, v_reason_t);
    v_changed := array_append(v_changed, 'phone');
  END IF;
  IF p_vehicle_type IS NOT NULL AND p_vehicle_type IS DISTINCT FROM v_driver.vehicle_type THEN
    UPDATE public.drivers SET vehicle_type = p_vehicle_type WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(p_driver_id, v_driver.name, 'vehicle_type', v_driver.vehicle_type, p_vehicle_type, false, v_reason_t);
    v_changed := array_append(v_changed, 'vehicle_type');
  END IF;
  IF p_license_plate IS NOT NULL AND p_license_plate IS DISTINCT FROM v_driver.license_plate THEN
    UPDATE public.drivers SET license_plate = trim(p_license_plate) WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(p_driver_id, v_driver.name, 'license_plate', v_driver.license_plate, trim(p_license_plate), false, v_reason_t);
    v_changed := array_append(v_changed, 'license_plate');
  END IF;
  IF p_vehicle_color IS NOT NULL AND p_vehicle_color IS DISTINCT FROM v_driver.vehicle_color THEN
    UPDATE public.drivers SET vehicle_color = trim(p_vehicle_color) WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(p_driver_id, v_driver.name, 'vehicle_color', v_driver.vehicle_color, trim(p_vehicle_color), false, v_reason_t);
    v_changed := array_append(v_changed, 'vehicle_color');
  END IF;
  IF p_vehicle_make_model IS NOT NULL AND p_vehicle_make_model IS DISTINCT FROM v_driver.vehicle_make_model THEN
    UPDATE public.drivers SET vehicle_make_model = trim(p_vehicle_make_model) WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(p_driver_id, v_driver.name, 'vehicle_make_model', v_driver.vehicle_make_model, trim(p_vehicle_make_model), false, v_reason_t);
    v_changed := array_append(v_changed, 'vehicle_make_model');
  END IF;
  IF p_iban IS NOT NULL AND p_iban IS DISTINCT FROM v_driver.iban THEN
    UPDATE public.drivers SET iban = trim(p_iban) WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(p_driver_id, v_driver.name, 'iban', v_driver.iban, trim(p_iban), true, v_reason_t);
    v_changed := array_append(v_changed, 'iban');
  END IF;
  IF p_nif IS NOT NULL AND p_nif IS DISTINCT FROM v_driver.nif THEN
    UPDATE public.drivers SET nif = trim(p_nif) WHERE id = p_driver_id;
    PERFORM public._admin_log_driver_field_change(p_driver_id, v_driver.name, 'nif', v_driver.nif, trim(p_nif), true, v_reason_t);
    v_changed := array_append(v_changed, 'nif');
  END IF;
  IF array_length(v_changed, 1) IS NULL THEN
    RAISE EXCEPTION 'no_changes: all provided fields equal current values' USING ERRCODE = '23514';
  END IF;
  RETURN jsonb_build_object('success', true, 'driver_id', p_driver_id, 'fields_changed', v_changed, 'reason', v_reason_t, 'updated_at', now());
END; $function$
;

-- Permissões tal como estão no ar a 15/11/2026:
--   {postgres=X/postgres,authenticated=X/postgres,service_role=X/postgres}
REVOKE ALL ON FUNCTION public.admin_update_driver(uuid, text, text, text, text, text, text, text, text, text) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_driver(uuid, text, text, text, text, text, text, text, text, text) TO authenticated, service_role;
