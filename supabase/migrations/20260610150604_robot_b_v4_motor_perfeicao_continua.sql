-- =============================================================================
-- ROBOT B v4 — "Motor de Perfeição Contínua"
-- Tabelas: robot_runs, robot_suggestions, robot_audit_log
-- Guard: _robot_op_guard (kill switches + whitelist FECHADA nível 1)
-- RPCs robô (service_role): start/finish run, create_suggestion, auto_execute, digest
-- RPCs admin (authenticated + _admin_op_guard): list/metrics/apply/reject/mark_done
-- Limites HARD-CODED: máx 10 auto-exec/ciclo, máx 15 sugestões abertas,
--   benchmark obrigatório, dedup + não-repetição de rejeitadas.
-- ⚠️ TODA função nova: REVOKE FROM PUBLIC + GRANTs explícitos (armadilha M3.5).
-- =============================================================================

-- 1. TABELAS ------------------------------------------------------------------

CREATE TABLE IF NOT EXISTS public.robot_runs (
  id                  uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  started_at          timestamptz NOT NULL DEFAULT now(),
  finished_at         timestamptz,
  mode                text NOT NULL DEFAULT 'cycle' CHECK (mode IN ('cycle','digest','crosstalk')),
  dry_run             boolean NOT NULL DEFAULT false,
  status              text NOT NULL DEFAULT 'running'
                        CHECK (status IN ('running','ok','skipped_kill_switch','error')),
  observations        jsonb NOT NULL DEFAULT '{}'::jsonb,
  auto_exec_count     integer NOT NULL DEFAULT 0,
  suggestions_created integer NOT NULL DEFAULT 0,
  error               text
);

CREATE TABLE IF NOT EXISTS public.robot_suggestions (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  ciclo            uuid REFERENCES public.robot_runs(id),
  nivel            smallint NOT NULL CHECK (nivel IN (1,2,3)),
  severidade       smallint NOT NULL DEFAULT 3 CHECK (severidade BETWEEN 1 AND 5),
  categoria        text NOT NULL,
  titulo           text NOT NULL,
  evidencia        jsonb NOT NULL DEFAULT '{}'::jsonb,
  proposta         text NOT NULL,
  payload_execucao jsonb,
  benchmark        text NOT NULL,
  status           text NOT NULL DEFAULT 'nova'
                     CHECK (status IN ('nova','aprovada','aplicada','rejeitada','expirada')),
  motivo_rejeicao  text,
  dedup_key        text NOT NULL,
  reviewed_by      uuid,
  reviewed_at      timestamptz,
  created_at       timestamptz NOT NULL DEFAULT now(),
  expires_at       timestamptz NOT NULL DEFAULT now() + interval '14 days'
);

CREATE TABLE IF NOT EXISTS public.robot_audit_log (
  id            uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  run_id        uuid REFERENCES public.robot_runs(id),
  suggestion_id uuid REFERENCES public.robot_suggestions(id),
  operation     text NOT NULL,
  params        jsonb NOT NULL DEFAULT '{}'::jsonb,
  result        jsonb NOT NULL DEFAULT '{}'::jsonb,
  executed_by   text NOT NULL,  -- 'robot' | email do admin
  created_at    timestamptz NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_robot_suggestions_nova
  ON public.robot_suggestions (created_at DESC) WHERE status = 'nova';
CREATE INDEX IF NOT EXISTS idx_robot_suggestions_dedup
  ON public.robot_suggestions (dedup_key, status);
CREATE INDEX IF NOT EXISTS idx_robot_audit_run ON public.robot_audit_log (run_id);
CREATE INDEX IF NOT EXISTS idx_robot_audit_created ON public.robot_audit_log (created_at DESC);
CREATE INDEX IF NOT EXISTS idx_robot_runs_started ON public.robot_runs (started_at DESC);

-- RLS fechado: sem policies — acesso APENAS via RPCs SECURITY DEFINER / service_role.
ALTER TABLE public.robot_runs        ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.robot_suggestions ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.robot_audit_log   ENABLE ROW LEVEL SECURITY;

REVOKE ALL ON public.robot_runs        FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.robot_suggestions FROM PUBLIC, anon, authenticated;
REVOKE ALL ON public.robot_audit_log   FROM PUBLIC, anon, authenticated;
GRANT ALL ON public.robot_runs, public.robot_suggestions, public.robot_audit_log TO service_role;

-- 2. KILL SWITCHES em platform_settings --------------------------------------

INSERT INTO public.platform_settings (key, value, description, category)
VALUES
  ('robot_b_enabled', 'true'::jsonb,
   'Kill switch geral do Robot B (Motor de Perfeição Contínua). false = ciclo não age nem sugere.',
   'robot'),
  ('robot_b_auto_level1_enabled', 'true'::jsonb,
   'Permite auto-execuções nível 1 (whitelist fechada, dados reversíveis). false = nível 1 vira sugestão 1-clique.',
   'robot')
ON CONFLICT (key) DO NOTHING;

-- 3. GUARD --------------------------------------------------------------------

CREATE OR REPLACE FUNCTION public._robot_setting_enabled(p_key text)
RETURNS boolean
LANGUAGE sql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
  SELECT COALESCE((SELECT (value #>> '{}')::boolean FROM public.platform_settings WHERE key = p_key), false);
$$;

CREATE OR REPLACE FUNCTION public._robot_op_guard(p_operation text, p_level integer)
RETURNS void
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  IF NOT public._robot_setting_enabled('robot_b_enabled') THEN
    RAISE EXCEPTION 'robot_b_disabled: kill switch geral desligado (robot_b_enabled=false)';
  END IF;
  IF p_level = 1 THEN
    IF NOT public._robot_setting_enabled('robot_b_auto_level1_enabled') THEN
      RAISE EXCEPTION 'robot_b_auto_level1_disabled: auto-execuções nível 1 desligadas';
    END IF;
    -- WHITELIST FECHADA nível 1 (hard-coded; o robô NUNCA a altera)
    IF p_operation NOT IN (
      'flag_products_review',
      'disable_unpriced_market_products',
      'clean_test_notifications',
      'expire_stale_suggestions'
    ) THEN
      RAISE EXCEPTION 'robot_op_fora_da_whitelist_nivel1: %', p_operation;
    END IF;
  END IF;
END;
$$;

-- 4. RPCs DO ROBÔ (service_role) ----------------------------------------------

CREATE OR REPLACE FUNCTION public.robot_start_run(p_mode text, p_dry_run boolean DEFAULT false)
RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.robot_runs (mode, dry_run)
  VALUES (COALESCE(p_mode,'cycle'), COALESCE(p_dry_run,false))
  RETURNING id INTO v_id;
  RETURN v_id;
END;
$$;

CREATE OR REPLACE FUNCTION public.robot_finish_run(
  p_run_id uuid, p_status text, p_observations jsonb DEFAULT '{}'::jsonb,
  p_auto_exec_count integer DEFAULT 0, p_suggestions_created integer DEFAULT 0,
  p_error text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  UPDATE public.robot_runs
     SET finished_at = now(), status = p_status,
         observations = COALESCE(p_observations,'{}'::jsonb),
         auto_exec_count = COALESCE(p_auto_exec_count,0),
         suggestions_created = COALESCE(p_suggestions_created,0),
         error = p_error
   WHERE id = p_run_id;
END;
$$;

-- Cria sugestão: benchmark OBRIGATÓRIO, dedup, não-repete rejeitadas (60d),
-- cap 15 abertas (substitui a de menor severidade), sino admin nível 2/3.
CREATE OR REPLACE FUNCTION public.robot_create_suggestion(
  p_run_id uuid, p_nivel smallint, p_severidade smallint,
  p_categoria text, p_titulo text, p_evidencia jsonb, p_proposta text,
  p_payload jsonb, p_benchmark text, p_dedup_key text
) RETURNS uuid
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_id uuid; v_open integer; v_victim_id uuid; v_victim_sev smallint;
  v_sev smallint := LEAST(GREATEST(COALESCE(p_severidade,3),1),5);
BEGIN
  PERFORM public._robot_op_guard('create_suggestion', NULL);

  -- "Sugestão sem benchmark citado não nasce" (limite no código)
  IF p_benchmark IS NULL OR length(trim(p_benchmark)) < 5 THEN
    RAISE EXCEPTION 'robot_sugestao_sem_benchmark';
  END IF;
  IF p_dedup_key IS NULL OR length(trim(p_dedup_key)) < 3 THEN
    RAISE EXCEPTION 'robot_sugestao_sem_dedup_key';
  END IF;

  -- dedup: já existe aberta igual → não duplica
  IF EXISTS (SELECT 1 FROM public.robot_suggestions
              WHERE dedup_key = p_dedup_key AND status IN ('nova','aprovada')) THEN
    RETURN NULL;
  END IF;
  -- aprendizagem: rejeitada com motivo nos últimos 60d → tipo não se repete
  IF EXISTS (SELECT 1 FROM public.robot_suggestions
              WHERE dedup_key = p_dedup_key AND status = 'rejeitada'
                AND reviewed_at > now() - interval '60 days') THEN
    RETURN NULL;
  END IF;

  -- cap 15 abertas: substitui a de menor severidade (hard-coded)
  SELECT count(*) INTO v_open FROM public.robot_suggestions WHERE status = 'nova';
  IF v_open >= 15 THEN
    SELECT id, severidade INTO v_victim_id, v_victim_sev
      FROM public.robot_suggestions WHERE status = 'nova'
     ORDER BY severidade ASC, created_at ASC LIMIT 1;
    IF v_victim_sev >= v_sev THEN
      RETURN NULL; -- a nova não é mais severa que nenhuma aberta → não nasce
    END IF;
    UPDATE public.robot_suggestions
       SET status = 'expirada',
           motivo_rejeicao = 'substituida_por_cap_15 (severidade ' || v_victim_sev || ' < ' || v_sev || ')'
     WHERE id = v_victim_id;
  END IF;

  INSERT INTO public.robot_suggestions
    (ciclo, nivel, severidade, categoria, titulo, evidencia, proposta,
     payload_execucao, benchmark, dedup_key)
  VALUES
    (p_run_id, p_nivel, v_sev, p_categoria, left(p_titulo, 200),
     COALESCE(p_evidencia,'{}'::jsonb), p_proposta, p_payload, p_benchmark, p_dedup_key)
  RETURNING id INTO v_id;

  -- sino admin (nível 2/3; nível 1 só vira sugestão quando auto está OFF — também avisa)
  PERFORM public.notify_admin_event(
    'robot_b_suggestion',
    CASE WHEN p_nivel >= 3 THEN 'high' ELSE 'medium' END,
    '🤖 Sugestão nível ' || p_nivel || ': ' || left(p_titulo, 140),
    'robot_suggestion', v_id::text,
    jsonb_build_object('nivel', p_nivel, 'severidade', v_sev, 'categoria', p_categoria),
    '/admin/robot-suggestions');

  RETURN v_id;
END;
$$;

-- Auto-execução nível 1: whitelist FECHADA, máx 10/ciclo, audit + sino SEMPRE.
CREATE OR REPLACE FUNCTION public.robot_auto_execute(
  p_run_id uuid, p_operation text, p_params jsonb DEFAULT '{}'::jsonb
) RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_count integer; v_rows integer := 0; v_result jsonb; v_ids text[];
BEGIN
  PERFORM public._robot_op_guard(p_operation, 1);

  -- limite duro: máx 10 auto-execuções por ciclo (NO CÓDIGO)
  SELECT count(*) INTO v_count FROM public.robot_audit_log
   WHERE run_id = p_run_id AND executed_by = 'robot';
  IF v_count >= 10 THEN
    RAISE EXCEPTION 'robot_max_10_auto_exec_por_ciclo';
  END IF;

  IF p_operation = 'flag_products_review' THEN
    v_ids := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_params->'product_ids','[]'::jsonb)) LIMIT 50);
    UPDATE public.products SET needs_review = true
     WHERE id = ANY(v_ids) AND COALESCE(needs_review,false) = false;
    GET DIAGNOSTICS v_rows = ROW_COUNT;

  ELSIF p_operation = 'disable_unpriced_market_products' THEN
    v_ids := ARRAY(SELECT jsonb_array_elements_text(COALESCE(p_params->'product_ids','[]'::jsonb)) LIMIT 50);
    UPDATE public.products p SET is_available = false
      FROM public.restaurants r
     WHERE p.restaurant_id = r.id AND COALESCE(r.is_partner,false) = false
       AND (p.price IS NULL OR p.price <= 0)
       AND p.is_available = true AND p.id = ANY(v_ids);
    GET DIAGNOSTICS v_rows = ROW_COUNT;

  ELSIF p_operation = 'clean_test_notifications' THEN
    DELETE FROM public.in_app_notifications
     WHERE ctid IN (
       SELECT ctid FROM public.in_app_notifications
        WHERE (title ILIKE '%teste%' OR title ILIKE '%[test]%')
          AND created_at < now() - interval '7 days'
        LIMIT 100);
    GET DIAGNOSTICS v_rows = ROW_COUNT;

  ELSIF p_operation = 'expire_stale_suggestions' THEN
    UPDATE public.robot_suggestions SET status = 'expirada'
     WHERE status = 'nova' AND expires_at < now();
    GET DIAGNOSTICS v_rows = ROW_COUNT;

  ELSE
    RAISE EXCEPTION 'robot_op_fora_da_whitelist_nivel1: %', p_operation;
  END IF;

  v_result := jsonb_build_object('operation', p_operation, 'rows_affected', v_rows);

  INSERT INTO public.robot_audit_log (run_id, operation, params, result, executed_by)
  VALUES (p_run_id, p_operation, COALESCE(p_params,'{}'::jsonb), v_result, 'robot');

  -- sino admin: TODA auto-execução nível 1 avisa
  PERFORM public.notify_admin_event(
    'robot_b_auto_fix', 'low',
    '🤖 Auto-fix nível 1: ' || p_operation || ' (' || v_rows || ' registos)',
    'robot_run', p_run_id::text, v_result, '/admin/robot-suggestions');

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.robot_notify_digest(p_run_id uuid, p_summary text, p_payload jsonb DEFAULT '{}'::jsonb)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public._robot_op_guard('digest', NULL);
  PERFORM public.notify_admin_event(
    'robot_b_digest', 'medium', left(p_summary, 280),
    'robot_run', p_run_id::text, COALESCE(p_payload,'{}'::jsonb), '/admin/robot-suggestions');
END;
$$;

-- 5. RPCs ADMIN (authenticated + _admin_op_guard) ------------------------------

CREATE OR REPLACE FUNCTION public.admin_list_robot_suggestions(
  p_status text DEFAULT NULL, p_nivel integer DEFAULT NULL,
  p_limit integer DEFAULT 100, p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN COALESCE((
    SELECT jsonb_agg(to_jsonb(s) ORDER BY s.created_at DESC)
      FROM (
        SELECT id, ciclo, nivel, severidade, categoria, titulo, evidencia, proposta,
               payload_execucao, benchmark, status, motivo_rejeicao, created_at, expires_at,
               reviewed_at
          FROM public.robot_suggestions
         WHERE (p_status IS NULL OR status = p_status)
           AND (p_nivel IS NULL OR nivel = p_nivel)
         ORDER BY created_at DESC
         LIMIT LEAST(GREATEST(COALESCE(p_limit,100),1),500)
        OFFSET GREATEST(COALESCE(p_offset,0),0)
      ) s
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_list_robot_audit(
  p_limit integer DEFAULT 100, p_offset integer DEFAULT 0
) RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public._admin_op_guard();
  RETURN COALESCE((
    SELECT jsonb_agg(to_jsonb(a) ORDER BY a.created_at DESC)
      FROM (
        SELECT id, run_id, suggestion_id, operation, params, result, executed_by, created_at
          FROM public.robot_audit_log
         ORDER BY created_at DESC
         LIMIT LEAST(GREATEST(COALESCE(p_limit,100),1),500)
        OFFSET GREATEST(COALESCE(p_offset,0),0)
      ) a
  ), '[]'::jsonb);
END;
$$;

CREATE OR REPLACE FUNCTION public.admin_robot_metrics()
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE v jsonb;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT jsonb_build_object(
    'abertas',           (SELECT count(*) FROM public.robot_suggestions WHERE status='nova'),
    'sugestoes_7d',      (SELECT count(*) FROM public.robot_suggestions WHERE created_at > now()-interval '7 days'),
    'auto_fixes_7d',     (SELECT count(*) FROM public.robot_audit_log WHERE executed_by='robot' AND created_at > now()-interval '7 days'),
    'taxa_aprovacao_pct',(SELECT CASE WHEN count(*) FILTER (WHERE status IN ('aplicada','aprovada','rejeitada')) = 0 THEN NULL
                                 ELSE round(100.0 * count(*) FILTER (WHERE status IN ('aplicada','aprovada'))
                                      / count(*) FILTER (WHERE status IN ('aplicada','aprovada','rejeitada')), 1) END
                            FROM public.robot_suggestions),
    'ultimo_ciclo',      (SELECT to_jsonb(r) FROM (SELECT started_at, finished_at, status, dry_run, mode,
                                 auto_exec_count, suggestions_created FROM public.robot_runs
                                 ORDER BY started_at DESC LIMIT 1) r),
    'robot_b_enabled',             public._robot_setting_enabled('robot_b_enabled'),
    'robot_b_auto_level1_enabled', public._robot_setting_enabled('robot_b_auto_level1_enabled')
  ) INTO v;
  RETURN v;
END;
$$;

-- Aprovar nível 1/2: executa o payload (whitelist FECHADA de tipos) + audit.
CREATE OR REPLACE FUNCTION public.robot_apply_suggestion(p_suggestion_id uuid)
RETURNS jsonb
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_s public.robot_suggestions%ROWTYPE;
  v_type text; v_rows integer := 0; v_result jsonb; v_ids text[];
  v_key text; v_val jsonb; v_admin_email text;
BEGIN
  PERFORM public._admin_op_guard();
  SELECT email INTO v_admin_email FROM auth.users WHERE id = auth.uid();

  SELECT * INTO v_s FROM public.robot_suggestions WHERE id = p_suggestion_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'sugestao_nao_encontrada'; END IF;
  IF v_s.status NOT IN ('nova','aprovada') THEN
    RAISE EXCEPTION 'sugestao_nao_esta_aberta: %', v_s.status;
  END IF;
  IF v_s.nivel >= 3 THEN
    RAISE EXCEPTION 'nivel_3_nao_executavel: usar robot_mark_suggestion_done apos implementar';
  END IF;
  IF v_s.payload_execucao IS NULL THEN
    RAISE EXCEPTION 'sugestao_sem_payload_execucao';
  END IF;

  v_type := v_s.payload_execucao->>'type';

  IF v_type = 'update_setting' THEN
    v_key := v_s.payload_execucao->>'key';
    v_val := v_s.payload_execucao->'value';
    IF v_key IS NULL OR v_val IS NULL THEN RAISE EXCEPTION 'payload_update_setting_invalido'; END IF;
    -- espelha a whitelist editável do admin (M5) + chaves do robô; NUNCA financeiras
    IF NOT (
      v_key LIKE 'robot\_b\_%'
      OR v_key LIKE 'dispatch\_%'
      OR (v_key LIKE 'reservation\_%'
          AND v_key NOT LIKE '%cents%' AND v_key NOT LIKE '%payout%'
          AND v_key NOT LIKE '%prepayment%' AND v_key NOT LIKE '%bora_service%'
          AND v_key NOT LIKE '%credit%')
    ) THEN
      RAISE EXCEPTION 'setting_fora_da_whitelist_robot: %', v_key;
    END IF;
    PERFORM public.admin_update_setting(v_key, v_val);
    v_rows := 1;

  ELSIF v_type = 'hide_store' THEN
    UPDATE public.restaurants SET is_active_admin = false
     WHERE id = (v_s.payload_execucao->>'restaurant_id');
    GET DIAGNOSTICS v_rows = ROW_COUNT;
    IF v_rows = 0 THEN RAISE EXCEPTION 'restaurante_nao_encontrado'; END IF;

  ELSIF v_type = 'disable_products' THEN
    v_ids := ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_s.payload_execucao->'product_ids','[]'::jsonb)) LIMIT 100);
    UPDATE public.products SET is_available = false
     WHERE id = ANY(v_ids) AND is_available = true;
    GET DIAGNOSTICS v_rows = ROW_COUNT;

  ELSIF v_type = 'flag_products_review' THEN
    v_ids := ARRAY(SELECT jsonb_array_elements_text(COALESCE(v_s.payload_execucao->'product_ids','[]'::jsonb)) LIMIT 100);
    UPDATE public.products SET needs_review = true
     WHERE id = ANY(v_ids) AND COALESCE(needs_review,false) = false;
    GET DIAGNOSTICS v_rows = ROW_COUNT;

  ELSE
    RAISE EXCEPTION 'payload_type_fora_da_whitelist: %', COALESCE(v_type,'(null)');
  END IF;

  v_result := jsonb_build_object('type', v_type, 'rows_affected', v_rows);

  UPDATE public.robot_suggestions
     SET status = 'aplicada', reviewed_by = auth.uid(), reviewed_at = now()
   WHERE id = p_suggestion_id;

  INSERT INTO public.robot_audit_log (suggestion_id, run_id, operation, params, result, executed_by)
  VALUES (p_suggestion_id, v_s.ciclo, 'apply_suggestion:' || v_type,
          v_s.payload_execucao, v_result, COALESCE(v_admin_email, auth.uid()::text));

  PERFORM public.log_admin_action('robot_apply_suggestion', 'robot_suggestion',
          p_suggestion_id, v_result);

  RETURN v_result;
END;
$$;

CREATE OR REPLACE FUNCTION public.robot_reject_suggestion(p_suggestion_id uuid, p_motivo text)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public._admin_op_guard();
  IF p_motivo IS NULL OR length(trim(p_motivo)) < 3 THEN
    RAISE EXCEPTION 'motivo_rejeicao_obrigatorio';
  END IF;
  UPDATE public.robot_suggestions
     SET status = 'rejeitada', motivo_rejeicao = left(trim(p_motivo), 500),
         reviewed_by = auth.uid(), reviewed_at = now()
   WHERE id = p_suggestion_id AND status IN ('nova','aprovada');
  IF NOT FOUND THEN RAISE EXCEPTION 'sugestao_nao_encontrada_ou_fechada'; END IF;
  PERFORM public.log_admin_action('robot_reject_suggestion', 'robot_suggestion',
          p_suggestion_id, jsonb_build_object('motivo', left(trim(p_motivo),500)));
END;
$$;

-- Nível 3 "Marcar feita" (implementada fora, ex. via Claude Code)
CREATE OR REPLACE FUNCTION public.robot_mark_suggestion_done(p_suggestion_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
BEGIN
  PERFORM public._admin_op_guard();
  UPDATE public.robot_suggestions
     SET status = 'aplicada', reviewed_by = auth.uid(), reviewed_at = now()
   WHERE id = p_suggestion_id AND status IN ('nova','aprovada');
  IF NOT FOUND THEN RAISE EXCEPTION 'sugestao_nao_encontrada_ou_fechada'; END IF;
  PERFORM public.log_admin_action('robot_mark_suggestion_done', 'robot_suggestion',
          p_suggestion_id, '{}'::jsonb);
END;
$$;

-- 6. GRANTS (⚠️ REVOKE FROM PUBLIC primeiro — grant default existe!) ----------

REVOKE ALL ON FUNCTION public._robot_setting_enabled(text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public._robot_op_guard(text, integer) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.robot_start_run(text, boolean) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.robot_finish_run(uuid, text, jsonb, integer, integer, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.robot_create_suggestion(uuid, smallint, smallint, text, text, jsonb, text, jsonb, text, text) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.robot_auto_execute(uuid, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.robot_notify_digest(uuid, text, jsonb) FROM PUBLIC, anon, authenticated;
REVOKE ALL ON FUNCTION public.admin_list_robot_suggestions(text, integer, integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_list_robot_audit(integer, integer) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.admin_robot_metrics() FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.robot_apply_suggestion(uuid) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.robot_reject_suggestion(uuid, text) FROM PUBLIC, anon;
REVOKE ALL ON FUNCTION public.robot_mark_suggestion_done(uuid) FROM PUBLIC, anon;

GRANT EXECUTE ON FUNCTION public.robot_start_run(text, boolean) TO service_role;
GRANT EXECUTE ON FUNCTION public.robot_finish_run(uuid, text, jsonb, integer, integer, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.robot_create_suggestion(uuid, smallint, smallint, text, text, jsonb, text, jsonb, text, text) TO service_role;
GRANT EXECUTE ON FUNCTION public.robot_auto_execute(uuid, text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public.robot_notify_digest(uuid, text, jsonb) TO service_role;
GRANT EXECUTE ON FUNCTION public._robot_setting_enabled(text) TO service_role;
GRANT EXECUTE ON FUNCTION public._robot_op_guard(text, integer) TO service_role;

GRANT EXECUTE ON FUNCTION public.admin_list_robot_suggestions(text, integer, integer, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_list_robot_audit(integer, integer) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.admin_robot_metrics() TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.robot_apply_suggestion(uuid) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.robot_reject_suggestion(uuid, text) TO authenticated, service_role;
GRANT EXECUTE ON FUNCTION public.robot_mark_suggestion_done(uuid) TO authenticated, service_role;

-- _admin_op_guard interno usa auth.uid(); admin_robot_metrics chama _robot_setting_enabled:
GRANT EXECUTE ON FUNCTION public._robot_setting_enabled(text) TO authenticated;
