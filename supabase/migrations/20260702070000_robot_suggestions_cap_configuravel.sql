-- Cap de sugestões abertas do Robot B: de 15 hard-coded para configurável.
-- Motivo: o goal paridade-admin-360 tem itens_por_ciclo=20 (teto solto pelo Danilo
-- via MCP em 2026-07-01), mas robot_create_suggestion tinha cap 15 hard-coded —
-- tetos incoerentes impediam o lote de chegar à Central. O cap continua a existir
-- (proteção anti-flood); passa a ler platform_settings.robot_b_max_open_suggestions
-- (default 15 se a chave não existir). Chave NÃO-financeira (família robot_b_*).
-- Sessão O BANQUETE 2026-07-02.

INSERT INTO public.platform_settings (key, value)
VALUES ('robot_b_max_open_suggestions', '30'::jsonb)
ON CONFLICT (key) DO UPDATE SET value = EXCLUDED.value;

CREATE OR REPLACE FUNCTION public.robot_create_suggestion(
  p_run_id uuid, p_nivel smallint, p_severidade smallint, p_categoria text,
  p_titulo text, p_evidencia jsonb, p_proposta text, p_payload jsonb,
  p_benchmark text, p_dedup_key text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_id uuid; v_open integer; v_victim_id uuid; v_victim_sev smallint;
  v_sev smallint := LEAST(GREATEST(COALESCE(p_severidade,3),1),5);
  v_cap integer;
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

  -- cap de abertas: configurável (robot_b_max_open_suggestions, default 15);
  -- ao encher, substitui a de menor severidade
  v_cap := COALESCE(
    (SELECT (value #>> '{}')::integer FROM public.platform_settings
      WHERE key = 'robot_b_max_open_suggestions'), 15);
  SELECT count(*) INTO v_open FROM public.robot_suggestions WHERE status = 'nova';
  IF v_open >= v_cap THEN
    SELECT id, severidade INTO v_victim_id, v_victim_sev
      FROM public.robot_suggestions WHERE status = 'nova'
     ORDER BY severidade ASC, created_at ASC LIMIT 1;
    IF v_victim_sev >= v_sev THEN
      RETURN NULL; -- a nova não é mais severa que nenhuma aberta → não nasce
    END IF;
    UPDATE public.robot_suggestions
       SET status = 'expirada',
           motivo_rejeicao = 'substituida_por_cap (severidade ' || v_victim_sev || ' < ' || v_sev || ')'
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
$function$;
