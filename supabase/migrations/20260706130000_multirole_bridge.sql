-- ============================================================================
-- MULTI-PAPEL — ponte estafeta/motorista ⇄ profissional de limpeza
-- ----------------------------------------------------------------------------
-- Contexto: `drivers` e `cleaners` são independentes, ambas ligadas por
-- `user_id` ao mesmo auth user. Não há exclusividade. `cleaner_apply` e
-- `driver_register_or_update` já usam auth.uid() → um user autenticado pode
-- ganhar o 2.º papel sem criar conta nova. Falta só:
--   (1) uma leitura única do "estado dos meus papéis" (para os cards + prefill);
--   (2) o admin saber, na candidatura, se o candidato já tem o outro papel.
-- NÃO toca em dinheiro (tokens/pricing/stripe). Só leitura/derivação.
-- ============================================================================

-- (1) Resumo dos papéis do próprio utilizador + dados comuns para pré-preencher.
CREATE OR REPLACE FUNCTION public.my_roles_summary()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_uid uuid := auth.uid();
  v_has_driver boolean; v_driver_status text;
  v_dn text; v_dp text; v_de text; v_dnif text; v_dphoto text;
  v_has_cleaner boolean; v_cleaner_status text;
  v_cn text; v_cp text; v_ce text; v_cnif text; v_cphoto text;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'not_authenticated' USING ERRCODE = '42501';
  END IF;

  SELECT true, approval_status, name, phone, email, nif, photo_url
    INTO v_has_driver, v_driver_status, v_dn, v_dp, v_de, v_dnif, v_dphoto
    FROM drivers WHERE user_id = v_uid LIMIT 1;

  SELECT true, approval_status, name, phone, email, nif, photo_url
    INTO v_has_cleaner, v_cleaner_status, v_cn, v_cp, v_ce, v_cnif, v_cphoto
    FROM cleaners WHERE user_id = v_uid LIMIT 1;

  RETURN jsonb_build_object(
    'has_driver',     COALESCE(v_has_driver, false),
    'driver_status',  v_driver_status,
    'has_cleaner',    COALESCE(v_has_cleaner, false),
    'cleaner_status', v_cleaner_status,
    'driver_profile', CASE WHEN v_has_driver THEN jsonb_build_object(
        'name', v_dn, 'phone', v_dp, 'email', v_de, 'nif', v_dnif, 'photo_url', v_dphoto) ELSE NULL END,
    'cleaner_profile', CASE WHEN v_has_cleaner THEN jsonb_build_object(
        'name', v_cn, 'phone', v_cp, 'email', v_ce, 'nif', v_cnif, 'photo_url', v_cphoto) ELSE NULL END
  );
END $$;

GRANT EXECUTE ON FUNCTION public.my_roles_summary() TO authenticated;

-- (2) Para o admin: dado um user_id, que OUTROS papéis já tem e em que estado.
-- Usado como badge nas telas de aprovação (candidatura de limpeza / de estafeta).
-- Guarda de admin igual ao resto do painel (_admin_op_guard).
CREATE OR REPLACE FUNCTION public.admin_user_role_flags(p_user_id uuid)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public'
AS $$
DECLARE
  v_driver_status text;
  v_cleaner_status text;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT approval_status INTO v_driver_status  FROM drivers  WHERE user_id = p_user_id LIMIT 1;
  SELECT approval_status INTO v_cleaner_status FROM cleaners WHERE user_id = p_user_id LIMIT 1;
  RETURN jsonb_build_object(
    'driver_status',  v_driver_status,   -- NULL = não é estafeta
    'cleaner_status', v_cleaner_status   -- NULL = não é profissional de limpeza
  );
END $$;
