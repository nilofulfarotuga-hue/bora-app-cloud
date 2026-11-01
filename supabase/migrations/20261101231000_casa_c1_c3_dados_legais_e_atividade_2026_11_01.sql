-- Missão app-fechar-2026-11-01 · B1 Casa & Manutenção · achados C1 e C3
-- (docs/propostas/revisao-casa-peso-convidado-2026-11-01.md).
--
-- C1: provider_update_legal_fields recusava p_role='handyman' ('invalid_role'): o nome legal,
--     NIF, morada, IBAN, data de nascimento e autocertificação do profissional da Casa nunca
--     chegavam a casa_profissionais, e o gatilho de conformidade nunca deixava aprovar.
-- C3: o comprovativo de atividade (provider_atividade_*) não conhecia a Casa: uma conta só
--     handyman levava 'nao_e_prestador'. Acrescenta-se casa_profissionais às três funções de
--     apoio e à lista de admin_conformidade_legal.
-- Não mexe em valores, preços, comissões nem dinheiro.

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
  IF p_role NOT IN ('driver','partner','cleaner','washer','provider','handyman') THEN
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
  ELSIF p_role = 'handyman' THEN
    -- C1 (01/11/2026): profissional da Casa & Manutenção.
    UPDATE public.casa_profissionais h SET
      legal_name = COALESCE(v_nome, h.legal_name), nif = COALESCE(v_nif, h.nif),
      address = COALESCE(v_morada, h.address), iban = COALESCE(v_iban, h.iban),
      birth_date = COALESCE(p_birth_date, h.birth_date),
      dsa_self_certified_at = COALESCE(v_cert, h.dsa_self_certified_at),
      dsa_self_cert_version = CASE WHEN v_cert IS NOT NULL THEN '2026-09-23' ELSE h.dsa_self_cert_version END,
      updated_at = now()
    WHERE h.user_id = v_uid
    RETURNING to_jsonb(h) INTO v_row;
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

CREATE OR REPLACE FUNCTION public._provider_atividade_papeis(p_uid uuid)
 RETURNS text[]
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT COALESCE(array_agg(DISTINCT x.p ORDER BY x.p), '{}'::text[])
  FROM (
    SELECT CASE WHEN d.vehicle_type = 'carro_passageiros' THEN 'motorista_tvde' ELSE 'estafeta' END AS p
      FROM public.drivers d
     WHERE d.user_id = p_uid AND d.deleted_at IS NULL
       AND COALESCE(d.approval_status, '') <> 'rejected'
    UNION ALL
    SELECT 'estafeta'
      FROM public.drivers d
      JOIN public.user_roles ur ON ur.user_id = d.user_id AND ur.role = 'delivery'
     WHERE d.user_id = p_uid AND d.deleted_at IS NULL
       AND COALESCE(d.approval_status, '') <> 'rejected'
    UNION ALL
    SELECT 'limpeza' FROM public.cleaners c
     WHERE c.user_id = p_uid AND c.approval_status <> 'rejected'
    UNION ALL
    SELECT 'lavagem' FROM public.washers w
     WHERE w.user_id = p_uid AND w.approval_status <> 'rejected'
    UNION ALL
    SELECT 'servicos' FROM public.service_providers s
     WHERE s.user_id = p_uid AND s.approval_status <> 'rejected'
    UNION ALL
    -- C3 (01/11/2026): Casa & Manutenção.
    SELECT 'casa' FROM public.casa_profissionais h
     WHERE h.user_id = p_uid AND h.approval_status <> 'rejected'
  ) x;
$function$;

CREATE OR REPLACE FUNCTION public._provider_atividade_nif_conhecido(p_uid uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT n FROM (
    SELECT 1 AS o, regexp_replace(COALESCE(f.nif, ''), '\D', '', 'g') AS n
      FROM public.driver_fiscal_status f WHERE f.user_id = p_uid
    UNION ALL SELECT 2, regexp_replace(COALESCE(c.nif, ''), '\D', '', 'g') FROM public.cleaners c WHERE c.user_id = p_uid
    UNION ALL SELECT 3, regexp_replace(COALESCE(w.nif, ''), '\D', '', 'g') FROM public.washers w WHERE w.user_id = p_uid
    UNION ALL SELECT 4, regexp_replace(COALESCE(d.nif, ''), '\D', '', 'g') FROM public.drivers d WHERE d.user_id = p_uid
    UNION ALL SELECT 5, regexp_replace(COALESCE(s.nif, ''), '\D', '', 'g') FROM public.service_providers s WHERE s.user_id = p_uid
    UNION ALL SELECT 6, regexp_replace(COALESCE(h.nif, ''), '\D', '', 'g') FROM public.casa_profissionais h WHERE h.user_id = p_uid
  ) x
  WHERE public._nif_valido(x.n)
  ORDER BY x.o
  LIMIT 1;
$function$;

CREATE OR REPLACE FUNCTION public._provider_atividade_ultima_candidatura(p_uid uuid)
 RETURNS timestamp with time zone
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
  SELECT max(t) FROM (
    SELECT d.created_at AS t FROM public.drivers d
     WHERE d.user_id = p_uid AND d.deleted_at IS NULL AND COALESCE(d.approval_status, '') <> 'rejected'
    UNION ALL SELECT c.created_at FROM public.cleaners c
     WHERE c.user_id = p_uid AND c.approval_status <> 'rejected'
    UNION ALL SELECT w.created_at FROM public.washers w
     WHERE w.user_id = p_uid AND w.approval_status <> 'rejected'
    UNION ALL SELECT s.created_at FROM public.service_providers s
     WHERE s.user_id = p_uid AND s.approval_status <> 'rejected'
    UNION ALL SELECT h.created_at FROM public.casa_profissionais h
     WHERE h.user_id = p_uid AND h.approval_status <> 'rejected'
  ) x;
$function$;

CREATE OR REPLACE FUNCTION public.admin_conformidade_legal()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO 'public'
AS $function$
DECLARE
  v_prest jsonb; v_opt jsonb; v_obrig boolean; v_lojas jsonb; v_itens jsonb;
BEGIN
  IF NOT public.is_admin() THEN RAISE EXCEPTION 'not_admin'; END IF;
  v_obrig := COALESCE((public.get_setting('conformidade_ativacao_obrigatoria') #>> '{}')::boolean, true);

  WITH p AS (
    SELECT 'driver' AS tipo, d.id::text AS id, d.user_id, COALESCE(d.legal_name, d.name) AS nome, d.phone, d.approval_status,
           public._conformidade_em_falta(to_jsonb(d)) AS falta
      FROM public.drivers d WHERE d.deleted_at IS NULL AND NOT COALESCE(public.is_demo_user(COALESCE(d.user_id, d.id)), false)
    UNION ALL
    SELECT 'partner', r.id, r.user_id, COALESCE(r.legal_name, r.name), r.phone, r.approval_status,
           public._conformidade_em_falta(to_jsonb(r))
      FROM public.restaurants r WHERE COALESCE(r.is_partner, false)
    UNION ALL
    SELECT 'cleaner', c.id::text, c.user_id, COALESCE(c.legal_name, c.name), c.phone, c.approval_status,
           public._conformidade_em_falta(to_jsonb(c))
      FROM public.cleaners c
    UNION ALL
    SELECT 'washer', w.id::text, w.user_id, COALESCE(w.legal_name, w.name), w.phone, w.approval_status,
           public._conformidade_em_falta(to_jsonb(w))
      FROM public.washers w
    UNION ALL
    SELECT 'provider', s.id, s.user_id, COALESCE(s.legal_name, s.name), s.phone, s.approval_status,
           public._conformidade_em_falta(to_jsonb(s))
      FROM public.service_providers s
    UNION ALL
    -- C3 (01/11/2026): Casa & Manutenção.
    SELECT 'handyman', h.id::text, h.user_id, COALESCE(h.legal_name, h.name), h.phone, h.approval_status,
           public._conformidade_em_falta(to_jsonb(h))
      FROM public.casa_profissionais h)
  SELECT jsonb_build_object(
    'resumo', (SELECT jsonb_object_agg(tipo, jsonb_build_object(
                  'total', n, 'aprovados', n_apr, 'completos', n_ok, 'incompletos', n - n_ok,
                  'aprovados_incompletos', n_apr_inc))
                 FROM (SELECT tipo, count(*) n,
                              count(*) FILTER (WHERE approval_status = 'approved') n_apr,
                              count(*) FILTER (WHERE COALESCE(array_length(falta, 1), 0) = 0) n_ok,
                              count(*) FILTER (WHERE approval_status = 'approved' AND COALESCE(array_length(falta, 1), 0) > 0) n_apr_inc
                         FROM p GROUP BY tipo) g),
    'incompletos', (SELECT COALESCE(jsonb_agg(jsonb_build_object('tipo', tipo, 'id', id, 'user_id', user_id, 'nome', nome, 'phone', phone,
                                                                  'approval_status', approval_status, 'falta', to_jsonb(falta))
                                              ORDER BY (approval_status = 'approved') DESC, tipo, nome), '[]'::jsonb)
                      FROM p WHERE COALESCE(array_length(falta, 1), 0) > 0))
    INTO v_prest;

  SELECT jsonb_build_object(
    'clientes', count(*) FILTER (WHERE role = 'client'),
    'com_opt_in', count(*) FILTER (WHERE marketing_opt_in),
    'ultimo_opt_in', max(marketing_opt_in_at))
    INTO v_opt FROM public.users;

  SELECT jsonb_build_object(
    'aprovadas', count(*),
    'sem_nif', count(*) FILTER (WHERE regexp_replace(COALESCE(nif,''), '[^0-9]', '', 'g') !~ '^[0-9]{9}$'),
    'sem_morada', count(*) FILTER (WHERE NULLIF(btrim(COALESCE(address,'')), '') IS NULL))
    INTO v_lojas FROM public.restaurants WHERE approval_status = 'approved' AND COALESCE(is_partner, false);

  v_itens := jsonb_build_array(
    jsonb_build_object('codigo', 'd3_ativacao', 'titulo', 'Ativação bloqueada sem dados legais (DSA art. 30 + DAC7)',
                       'estado', CASE WHEN v_obrig THEN 'ok' ELSE 'parcial' END,
                       'detalhe', CASE WHEN v_obrig THEN 'Gatilho ligado: nome, NIF, morada, IBAN, data de nascimento e autocertificação são exigidos antes de aprovar.'
                                       ELSE 'conformidade_ativacao_obrigatoria=false: o gatilho só avisa.' END,
                       'rota', '/admin/configuracoes'),
    jsonb_build_object('codigo', 'd3_prestadores', 'titulo', 'Prestadores com dados completos',
                       'estado', CASE WHEN (SELECT bool_and((v->>'incompletos')::int = 0) FROM jsonb_each(v_prest->'resumo') AS e(k, v)) THEN 'ok' ELSE 'parcial' END,
                       'detalhe', 'Ver a lista de incompletos abaixo; os aprovados incompletos precisam de completar na app.',
                       'rota', NULL),
    jsonb_build_object('codigo', 'd3_recibo_vendedor', 'titulo', 'Nome, NIF e morada do vendedor no recibo do cliente',
                       'estado', CASE WHEN (v_lojas->>'sem_nif')::int = 0 AND (v_lojas->>'sem_morada')::int = 0 THEN 'ok' ELSE 'parcial' END,
                       'detalhe', format('%s lojas parceiras aprovadas: %s sem NIF, %s sem morada.', v_lojas->>'aprovadas', v_lojas->>'sem_nif', v_lojas->>'sem_morada'),
                       'rota', '/admin/parceiros'),
    jsonb_build_object('codigo', 'd3_opt_in', 'titulo', 'Opt-in separado para marketing',
                       'estado', 'ok',
                       'detalhe', format('%s clientes, %s com opt-in. Push comercial (promo/cashback/referral) só vai a estes.', v_opt->>'clientes', v_opt->>'com_opt_in'),
                       'rota', '/admin/notificacoes'),
    jsonb_build_object('codigo', 'd4_dac7', 'titulo', 'Exportação DAC7 anual (CSV)',
                       'estado', 'ok',
                       'detalhe', 'admin_dac7_export(ano): uma linha por vendedor com totais por trimestre; entregar à AT até 31 de janeiro do ano seguinte.',
                       'rota', '/admin/conformidade'));

  RETURN jsonb_build_object('gerado_em', now(), 'ativacao_obrigatoria', v_obrig, 'itens', v_itens,
                            'prestadores', v_prest, 'marketing', v_opt, 'lojas', v_lojas);
END;
$function$;
