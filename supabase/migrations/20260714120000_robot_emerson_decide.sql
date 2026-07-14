-- 2026-07-14: Robot B triage — Hermes/Emerson decide sozinho sobre robot_suggestions 'nova'.
-- Pedido do Danilo: "o Emerson é meu sócio, ele decide se aplica o que o Robot B sugeriu".
--
-- Novo status terminal 'aprovada-emerson' (distinto de 'aprovada' humana): a sugestão foi
-- decidida pelo agente Hermes/Emerson (sem sessão admin humana), não executada aqui — a
-- execução acontece via ordem no loop de orquestração (cortex_nova_ordem), sob o Juiz.
--
-- robot_emerson_decide() é o único caminho de escrita: gated por GRANT (só service_role,
-- NUNCA authenticated/anon — sem _admin_op_guard porque o Hermes não tem sessão admin humana).
-- Bloqueia no servidor qualquer aprovação que toque zona protegida (dispatch/dinheiro/RLS
-- financeira) — mesmo que o agente se engane, a Trava fica na base de dados.

ALTER TABLE public.robot_suggestions DROP CONSTRAINT IF EXISTS robot_suggestions_status_check;
ALTER TABLE public.robot_suggestions ADD CONSTRAINT robot_suggestions_status_check
  CHECK (status IN ('nova','aprovada','aprovada-emerson','aplicada','rejeitada','expirada'));

CREATE OR REPLACE FUNCTION public.robot_emerson_decide(
  p_suggestion_id uuid,
  p_decisao text,
  p_motivo text,
  p_ordem_id text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'pg_temp'
AS $function$
DECLARE
  v_s public.robot_suggestions%ROWTYPE;
  v_result jsonb;
  v_texto text;
  v_protected_kw text := '(dispatch|pricing|stripe|payment|pagamento|wallet|ledger|refund|reembolso|token|comiss|commission|settlement|finalizepurchase|platform_settings|mbway|payout|cobran|dep[oó]sito)';
  v_protected_categoria text[] := ARRAY['operacao_pedidos','pagamentos','financeiro','dispatch'];
BEGIN
  IF p_decisao NOT IN ('aprovada-emerson','rejeitada') THEN
    RAISE EXCEPTION 'decisao_invalida: %', p_decisao;
  END IF;
  IF p_motivo IS NULL OR length(trim(p_motivo)) < 3 THEN
    RAISE EXCEPTION 'motivo_obrigatorio';
  END IF;

  SELECT * INTO v_s FROM public.robot_suggestions WHERE id = p_suggestion_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'sugestao_nao_encontrada'; END IF;
  IF v_s.status <> 'nova' THEN
    RAISE EXCEPTION 'sugestao_nao_esta_nova: %', v_s.status;
  END IF;

  IF p_decisao = 'aprovada-emerson' THEN
    v_texto := lower(coalesce(v_s.titulo,'') || ' ' || coalesce(v_s.categoria,'') || ' ' || coalesce(v_s.proposta,''));
    IF v_s.categoria = ANY(v_protected_categoria) OR v_texto ~ v_protected_kw THEN
      RAISE EXCEPTION 'zona_protegida_requer_humano: categoria=% titulo=%', v_s.categoria, v_s.titulo;
    END IF;
    UPDATE public.robot_suggestions
       SET status = 'aprovada-emerson', reviewed_at = now()
     WHERE id = p_suggestion_id;
  ELSE
    UPDATE public.robot_suggestions
       SET status = 'rejeitada', motivo_rejeicao = left(trim(p_motivo), 500), reviewed_at = now()
     WHERE id = p_suggestion_id;
  END IF;

  v_result := jsonb_build_object('decisao', p_decisao, 'motivo', left(trim(p_motivo),500), 'ordem_id', p_ordem_id);

  INSERT INTO public.robot_audit_log (suggestion_id, run_id, operation, params, result, executed_by)
  VALUES (p_suggestion_id, v_s.ciclo, 'emerson_decide:' || p_decisao,
          jsonb_build_object('motivo', left(trim(p_motivo),500), 'ordem_id', p_ordem_id), v_result, 'emerson');

  RETURN v_result;
END;
$function$;

REVOKE ALL ON FUNCTION public.robot_emerson_decide(uuid, text, text, text) FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.robot_emerson_decide(uuid, text, text, text) TO service_role;

-- Evita que o Robot B regenere um duplicado do mesmo dedup_key enquanto o Emerson já decidiu
-- (a checagem original só olhava 'nova'/'aprovada'; 'aprovada-emerson' ficava de fora).
CREATE OR REPLACE FUNCTION public.robot_create_suggestion(p_run_id uuid, p_nivel smallint, p_severidade smallint, p_categoria text, p_titulo text, p_evidencia jsonb, p_proposta text, p_payload jsonb, p_benchmark text, p_dedup_key text)
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

  IF p_benchmark IS NULL OR length(trim(p_benchmark)) < 5 THEN
    RAISE EXCEPTION 'robot_sugestao_sem_benchmark';
  END IF;
  IF p_dedup_key IS NULL OR length(trim(p_dedup_key)) < 3 THEN
    RAISE EXCEPTION 'robot_sugestao_sem_dedup_key';
  END IF;

  IF EXISTS (SELECT 1 FROM public.robot_suggestions
              WHERE dedup_key = p_dedup_key AND status IN ('nova','aprovada','aprovada-emerson')) THEN
    RETURN NULL;
  END IF;
  IF EXISTS (SELECT 1 FROM public.robot_suggestions
              WHERE dedup_key = p_dedup_key AND status = 'rejeitada'
                AND reviewed_at > now() - interval '60 days') THEN
    RETURN NULL;
  END IF;

  v_cap := COALESCE(
    (SELECT (value #>> '{}')::integer FROM public.platform_settings
      WHERE key = 'robot_b_max_open_suggestions'), 15);
  SELECT count(*) INTO v_open FROM public.robot_suggestions WHERE status = 'nova';
  IF v_open >= v_cap THEN
    SELECT id, severidade INTO v_victim_id, v_victim_sev
      FROM public.robot_suggestions WHERE status = 'nova'
     ORDER BY severidade ASC, created_at ASC LIMIT 1;
    IF v_victim_sev >= v_sev THEN
      RETURN NULL;
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
