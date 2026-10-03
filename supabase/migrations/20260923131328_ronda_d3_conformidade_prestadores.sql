-- =============================================================================
-- ronda-fecho-2026-09-22 · D3 — mínimo legal dos prestadores (DSA art. 30 +
-- DAC7): campos obrigatórios (nome, NIF, morada, IBAN, data de nascimento) e
-- autocertificação ANTES de ativar; opt-in separado para marketing.
--
--   1) colunas: legal_name, birth_date, dsa_self_certified_at (todas as tabelas
--      de prestador); iban e address em cleaners/washers; users.marketing_opt_in.
--   2) platform_settings.conformidade_ativacao_obrigatoria (true): o gatilho
--      fn_conformidade_antes_de_ativar bloqueia approval_status -> 'approved'
--      enquanto faltar um campo ou a autocertificação. Emergência:
--      SELECT set_config('bora.forcar_ativacao','1',true) na mesma transação.
--   3) provider_update_legal_fields(...): a app grava os campos legais da própria
--      pessoa (por auth.uid()) e devolve o que ainda falta.
--   4) set_marketing_opt_in(p_opt_in): opt-in separado; admin_broadcast_notification
--      só manda 'promo'/'cashback'/'referral' a quem aceitou (in-app) e marca a
--      fila FCM com only_marketing_opt_in.
-- =============================================================================

ALTER TABLE public.drivers
  ADD COLUMN IF NOT EXISTS legal_name text,
  ADD COLUMN IF NOT EXISTS birth_date date,
  ADD COLUMN IF NOT EXISTS dsa_self_certified_at timestamptz,
  ADD COLUMN IF NOT EXISTS dsa_self_cert_version text;
ALTER TABLE public.restaurants
  ADD COLUMN IF NOT EXISTS legal_name text,
  ADD COLUMN IF NOT EXISTS birth_date date,
  ADD COLUMN IF NOT EXISTS business_registration_number text,
  ADD COLUMN IF NOT EXISTS dsa_self_certified_at timestamptz,
  ADD COLUMN IF NOT EXISTS dsa_self_cert_version text;
ALTER TABLE public.cleaners
  ADD COLUMN IF NOT EXISTS legal_name text,
  ADD COLUMN IF NOT EXISTS iban text,
  ADD COLUMN IF NOT EXISTS address text,
  ADD COLUMN IF NOT EXISTS birth_date date,
  ADD COLUMN IF NOT EXISTS dsa_self_certified_at timestamptz,
  ADD COLUMN IF NOT EXISTS dsa_self_cert_version text;
ALTER TABLE public.washers
  ADD COLUMN IF NOT EXISTS legal_name text,
  ADD COLUMN IF NOT EXISTS iban text,
  ADD COLUMN IF NOT EXISTS address text,
  ADD COLUMN IF NOT EXISTS birth_date date,
  ADD COLUMN IF NOT EXISTS dsa_self_certified_at timestamptz,
  ADD COLUMN IF NOT EXISTS dsa_self_cert_version text;
ALTER TABLE public.service_providers
  ADD COLUMN IF NOT EXISTS legal_name text,
  ADD COLUMN IF NOT EXISTS birth_date date,
  ADD COLUMN IF NOT EXISTS dsa_self_certified_at timestamptz,
  ADD COLUMN IF NOT EXISTS dsa_self_cert_version text;
ALTER TABLE public.users
  ADD COLUMN IF NOT EXISTS marketing_opt_in boolean NOT NULL DEFAULT false,
  ADD COLUMN IF NOT EXISTS marketing_opt_in_at timestamptz;
ALTER TABLE public.push_broadcasts
  ADD COLUMN IF NOT EXISTS only_marketing_opt_in boolean NOT NULL DEFAULT false;

INSERT INTO public.platform_settings (key, value, description, category)
VALUES ('conformidade_ativacao_obrigatoria', 'true'::jsonb,
        'DSA art. 30 + DAC7: um prestador (estafeta, parceiro, faxineiro, lavador, salão) só pode ser ativado com nome, NIF, morada, IBAN, data de nascimento e autocertificação. false = só avisa (não bloqueia).',
        'legal')
ON CONFLICT (key) DO NOTHING;

-- ── o que falta a um prestador ──────────────────────────────────────────────
CREATE OR REPLACE FUNCTION public._conformidade_em_falta(p_row jsonb)
 RETURNS text[]
 LANGUAGE sql
 IMMUTABLE
AS $function$
  SELECT ARRAY(
    SELECT x FROM unnest(ARRAY[
      CASE WHEN NULLIF(btrim(COALESCE(p_row->>'legal_name', p_row->>'name', '')), '') IS NULL THEN 'nome' END,
      CASE WHEN regexp_replace(COALESCE(p_row->>'nif', ''), '[^0-9]', '', 'g') !~ '^[0-9]{9}$' THEN 'nif' END,
      CASE WHEN NULLIF(btrim(COALESCE(p_row->>'address', p_row->>'base_address', '')), '') IS NULL THEN 'morada' END,
      CASE WHEN upper(regexp_replace(COALESCE(p_row->>'iban', ''), '\s', '', 'g')) !~ '^PT[0-9]{23}$' THEN 'iban' END,
      CASE WHEN NULLIF(p_row->>'birth_date', '') IS NULL THEN 'data_nascimento' END,
      CASE WHEN NULLIF(p_row->>'dsa_self_certified_at', '') IS NULL THEN 'autocertificacao' END
    ]) AS x WHERE x IS NOT NULL);
$function$;

CREATE OR REPLACE FUNCTION public.fn_conformidade_antes_de_ativar()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_falta text[];
  v_obrig boolean := COALESCE((public.get_setting('conformidade_ativacao_obrigatoria') #>> '{}')::boolean, true);
BEGIN
  IF NEW.approval_status = 'approved' AND OLD.approval_status IS DISTINCT FROM 'approved' THEN
    v_falta := public._conformidade_em_falta(to_jsonb(NEW));
    IF array_length(v_falta, 1) > 0 THEN
      IF v_obrig AND COALESCE(current_setting('bora.forcar_ativacao', true), '') <> '1' THEN
        RAISE EXCEPTION 'conformidade_incompleta: faltam %', array_to_string(v_falta, ', ')
          USING HINT = 'DSA art. 30 + DAC7: completar nome, NIF, morada, IBAN, data de nascimento e autocertificação antes de ativar (ou desligar conformidade_ativacao_obrigatoria).';
      ELSE
        RAISE NOTICE 'conformidade_incompleta (nao bloqueante): % faltam %', TG_TABLE_NAME, array_to_string(v_falta, ', ');
      END IF;
    END IF;
  END IF;
  RETURN NEW;
END;
$function$;

DROP TRIGGER IF EXISTS trg_conformidade_antes_de_ativar ON public.drivers;
CREATE TRIGGER trg_conformidade_antes_de_ativar BEFORE UPDATE OF approval_status ON public.drivers
FOR EACH ROW EXECUTE FUNCTION public.fn_conformidade_antes_de_ativar();
DROP TRIGGER IF EXISTS trg_conformidade_antes_de_ativar ON public.restaurants;
CREATE TRIGGER trg_conformidade_antes_de_ativar BEFORE UPDATE OF approval_status ON public.restaurants
FOR EACH ROW EXECUTE FUNCTION public.fn_conformidade_antes_de_ativar();
DROP TRIGGER IF EXISTS trg_conformidade_antes_de_ativar ON public.cleaners;
CREATE TRIGGER trg_conformidade_antes_de_ativar BEFORE UPDATE OF approval_status ON public.cleaners
FOR EACH ROW EXECUTE FUNCTION public.fn_conformidade_antes_de_ativar();
DROP TRIGGER IF EXISTS trg_conformidade_antes_de_ativar ON public.washers;
CREATE TRIGGER trg_conformidade_antes_de_ativar BEFORE UPDATE OF approval_status ON public.washers
FOR EACH ROW EXECUTE FUNCTION public.fn_conformidade_antes_de_ativar();
DROP TRIGGER IF EXISTS trg_conformidade_antes_de_ativar ON public.service_providers;
CREATE TRIGGER trg_conformidade_antes_de_ativar BEFORE UPDATE OF approval_status ON public.service_providers
FOR EACH ROW EXECUTE FUNCTION public.fn_conformidade_antes_de_ativar();

-- ── a app grava os campos legais da própria pessoa ──────────────────────────
CREATE OR REPLACE FUNCTION public.provider_update_legal_fields(p_role text, p_legal_name text DEFAULT NULL::text, p_nif text DEFAULT NULL::text, p_address text DEFAULT NULL::text, p_iban text DEFAULT NULL::text, p_birth_date date DEFAULT NULL::date, p_self_certify boolean DEFAULT false)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_uid uuid := auth.uid();
  v_nif text := NULLIF(regexp_replace(COALESCE(p_nif, ''), '[^0-9]', '', 'g'), '');
  v_iban text := NULLIF(upper(regexp_replace(COALESCE(p_iban, ''), '\s', '', 'g')), '');
  v_nome text := NULLIF(btrim(COALESCE(p_legal_name, '')), '');
  v_morada text := NULLIF(btrim(COALESCE(p_address, '')), '');
  v_row jsonb;
  v_cert timestamptz;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501'; END IF;
  IF p_role NOT IN ('driver','partner','cleaner','washer','provider') THEN
    RAISE EXCEPTION 'invalid_role: %', p_role;
  END IF;
  IF v_nif IS NOT NULL AND v_nif !~ '^[0-9]{9}$' THEN RAISE EXCEPTION 'nif_invalido'; END IF;
  IF v_iban IS NOT NULL AND v_iban !~ '^PT[0-9]{23}$' THEN RAISE EXCEPTION 'iban_invalido'; END IF;
  IF p_birth_date IS NOT NULL AND p_birth_date > (current_date - interval '18 years') THEN
    RAISE EXCEPTION 'menor_de_idade';
  END IF;
  v_cert := CASE WHEN COALESCE(p_self_certify, false) THEN now() END;

  IF p_role = 'driver' THEN
    UPDATE public.drivers d SET
      legal_name = COALESCE(v_nome, d.legal_name), nif = COALESCE(v_nif, d.nif),
      address = COALESCE(v_morada, d.address), iban = COALESCE(v_iban, d.iban),
      birth_date = COALESCE(p_birth_date, d.birth_date),
      dsa_self_certified_at = COALESCE(v_cert, d.dsa_self_certified_at),
      dsa_self_cert_version = CASE WHEN v_cert IS NOT NULL THEN '2026-09-23' ELSE d.dsa_self_cert_version END
    WHERE d.user_id = v_uid OR d.id = v_uid
    RETURNING to_jsonb(d) INTO v_row;
  ELSIF p_role = 'partner' THEN
    UPDATE public.restaurants r SET
      legal_name = COALESCE(v_nome, r.legal_name), nif = COALESCE(v_nif, r.nif),
      address = COALESCE(v_morada, r.address), iban = COALESCE(v_iban, r.iban),
      birth_date = COALESCE(p_birth_date, r.birth_date),
      dsa_self_certified_at = COALESCE(v_cert, r.dsa_self_certified_at),
      dsa_self_cert_version = CASE WHEN v_cert IS NOT NULL THEN '2026-09-23' ELSE r.dsa_self_cert_version END
    WHERE r.user_id = v_uid OR r.user_ = v_uid
    RETURNING to_jsonb(r) INTO v_row;
  ELSIF p_role = 'cleaner' THEN
    UPDATE public.cleaners c SET
      legal_name = COALESCE(v_nome, c.legal_name), nif = COALESCE(v_nif, c.nif),
      address = COALESCE(v_morada, c.address), iban = COALESCE(v_iban, c.iban),
      birth_date = COALESCE(p_birth_date, c.birth_date),
      dsa_self_certified_at = COALESCE(v_cert, c.dsa_self_certified_at),
      dsa_self_cert_version = CASE WHEN v_cert IS NOT NULL THEN '2026-09-23' ELSE c.dsa_self_cert_version END
    WHERE c.user_id = v_uid
    RETURNING to_jsonb(c) INTO v_row;
  ELSIF p_role = 'washer' THEN
    UPDATE public.washers w SET
      legal_name = COALESCE(v_nome, w.legal_name), nif = COALESCE(v_nif, w.nif),
      address = COALESCE(v_morada, w.address), iban = COALESCE(v_iban, w.iban),
      birth_date = COALESCE(p_birth_date, w.birth_date),
      dsa_self_certified_at = COALESCE(v_cert, w.dsa_self_certified_at),
      dsa_self_cert_version = CASE WHEN v_cert IS NOT NULL THEN '2026-09-23' ELSE w.dsa_self_cert_version END
    WHERE w.user_id = v_uid
    RETURNING to_jsonb(w) INTO v_row;
  ELSE
    UPDATE public.service_providers s SET
      legal_name = COALESCE(v_nome, s.legal_name), nif = COALESCE(v_nif, s.nif),
      address = COALESCE(v_morada, s.address), iban = COALESCE(v_iban, s.iban),
      birth_date = COALESCE(p_birth_date, s.birth_date),
      dsa_self_certified_at = COALESCE(v_cert, s.dsa_self_certified_at),
      dsa_self_cert_version = CASE WHEN v_cert IS NOT NULL THEN '2026-09-23' ELSE s.dsa_self_cert_version END
    WHERE s.user_id = v_uid
    RETURNING to_jsonb(s) INTO v_row;
  END IF;

  IF v_row IS NULL THEN
    RETURN jsonb_build_object('ok', false, 'role', p_role, 'error', 'registo_nao_encontrado',
                              'missing', to_jsonb(ARRAY['registo']));
  END IF;
  RETURN jsonb_build_object('ok', true, 'role', p_role,
                            'missing', to_jsonb(public._conformidade_em_falta(v_row)),
                            'self_certified_at', v_row->>'dsa_self_certified_at');
END;
$function$;
REVOKE ALL ON FUNCTION public.provider_update_legal_fields(text, text, text, text, text, date, boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.provider_update_legal_fields(text, text, text, text, text, date, boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.provider_update_legal_fields(text, text, text, text, text, date, boolean) TO authenticated;

-- ── opt-in separado para marketing ──────────────────────────────────────────
CREATE OR REPLACE FUNCTION public.set_marketing_opt_in(p_opt_in boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE v_uid uuid := auth.uid();
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501'; END IF;
  UPDATE public.users SET marketing_opt_in = COALESCE(p_opt_in, false),
                          marketing_opt_in_at = CASE WHEN COALESCE(p_opt_in, false) THEN now() ELSE marketing_opt_in_at END
   WHERE id = v_uid;
  IF NOT FOUND THEN
    INSERT INTO public.users (id, role, marketing_opt_in, marketing_opt_in_at)
    VALUES (v_uid, 'client', COALESCE(p_opt_in, false), CASE WHEN COALESCE(p_opt_in, false) THEN now() END)
    ON CONFLICT (id) DO UPDATE SET marketing_opt_in = EXCLUDED.marketing_opt_in, marketing_opt_in_at = EXCLUDED.marketing_opt_in_at;
  END IF;
  RETURN jsonb_build_object('ok', true, 'marketing_opt_in', COALESCE(p_opt_in, false));
END;
$function$;
REVOKE ALL ON FUNCTION public.set_marketing_opt_in(boolean) FROM PUBLIC;
REVOKE ALL ON FUNCTION public.set_marketing_opt_in(boolean) FROM anon;
GRANT EXECUTE ON FUNCTION public.set_marketing_opt_in(boolean) TO authenticated;

-- promo/cashback/referral só a quem aceitou (in-app); a fila FCM fica marcada
CREATE OR REPLACE FUNCTION public.admin_broadcast_notification(p_segment text, p_kind text, p_title text, p_body text DEFAULT NULL::text)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_user_ids    uuid[];
  v_count       int;
  v_fcm_segment text;
  v_marketing   boolean := p_kind IN ('promo', 'cashback', 'referral');
BEGIN
  PERFORM public._admin_op_guard();

  CASE p_segment
    WHEN 'all_clients' THEN
      SELECT array_agg(id) INTO v_user_ids FROM users WHERE role = 'client';
      v_fcm_segment := 'clients';
    WHEN 'drivers_online' THEN
      SELECT array_agg(id) INTO v_user_ids FROM drivers WHERE COALESCE(is_online, false);
      v_fcm_segment := 'drivers';
    WHEN 'partners' THEN
      SELECT array_agg(id) INTO v_user_ids FROM users WHERE role = 'partner';
      v_fcm_segment := 'partners';
    WHEN 'all_users' THEN
      SELECT array_agg(id) INTO v_user_ids FROM users WHERE role IN ('client','partner');
      v_fcm_segment := 'all';
    WHEN 'recent_clients_30d' THEN
      SELECT array_agg(DISTINCT user_id) INTO v_user_ids FROM orders
       WHERE created_at > NOW() - INTERVAL '30 days' AND user_id IS NOT NULL;
      v_fcm_segment := 'clients';
    ELSE
      RAISE EXCEPTION 'invalid_segment: %', p_segment;
  END CASE;

  -- 2026-09-23 (D3): comunicação comercial só a quem deu opt-in separado.
  IF v_marketing AND v_user_ids IS NOT NULL THEN
    SELECT array_agg(u) INTO v_user_ids
      FROM unnest(v_user_ids) AS u
     WHERE EXISTS (SELECT 1 FROM public.users pu WHERE pu.id = u AND pu.marketing_opt_in);
  END IF;

  -- 1. In-app notification (sininho)
  IF v_user_ids IS NOT NULL AND array_length(v_user_ids, 1) IS NOT NULL THEN
    INSERT INTO in_app_notifications (user_id, kind, title, body)
      SELECT u, p_kind, p_title, p_body FROM unnest(v_user_ids) AS u
      WHERE EXISTS (SELECT 1 FROM auth.users au WHERE au.id = u);  -- guard órfãos
    GET DIAGNOSTICS v_count = ROW_COUNT;
  ELSE
    v_count := 0;
  END IF;

  -- 2. Fila FCM — execute-broadcast cron processa em <2 min
  INSERT INTO push_broadcasts (segment, title, body, status, created_by, only_marketing_opt_in)
  VALUES (v_fcm_segment, p_title, p_body, 'pending', auth.uid(), v_marketing);

  PERFORM log_admin_action('broadcast_notification', 'segment', p_segment,
    jsonb_build_object('kind', p_kind, 'title', p_title, 'in_app_count', v_count,
                       'only_marketing_opt_in', v_marketing));

  RETURN v_count;
END;
$function$;
