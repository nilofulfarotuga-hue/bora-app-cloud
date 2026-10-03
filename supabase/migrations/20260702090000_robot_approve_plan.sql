-- Central de Autonomia: aprovar PLANO (nivel 3) sem executar nada.
-- Bug 2026-07-02: o botao da Central chamava robot_apply_suggestion para
-- sugestoes nao-executaveis -> payload_type_fora_da_whitelist (P0001).
-- Aprovacao de plano = ato humano de aceite; a implementacao acontece fora
-- (Claude Code) e depois fecha-se com robot_mark_suggestion_done.

CREATE OR REPLACE FUNCTION public.robot_approve_plan(p_suggestion_id uuid)
RETURNS void
LANGUAGE plpgsql SECURITY DEFINER
SET search_path = public, pg_temp
AS $$
DECLARE
  v_nivel smallint;
BEGIN
  PERFORM public._admin_op_guard();

  SELECT nivel INTO v_nivel
    FROM public.robot_suggestions
   WHERE id = p_suggestion_id
   FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'sugestao_nao_encontrada'; END IF;
  IF v_nivel < 3 THEN
    RAISE EXCEPTION 'nao_e_plano: nivel % usa robot_apply_suggestion ou robot_mark_suggestion_done', v_nivel;
  END IF;

  UPDATE public.robot_suggestions
     SET status = 'aprovada', reviewed_by = auth.uid(), reviewed_at = now()
   WHERE id = p_suggestion_id AND status = 'nova';
  IF NOT FOUND THEN RAISE EXCEPTION 'sugestao_nao_encontrada_ou_fechada'; END IF;

  PERFORM public.log_admin_action('robot_approve_plan', 'robot_suggestion',
          p_suggestion_id, '{}'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.robot_approve_plan(uuid) FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.robot_approve_plan(uuid) TO authenticated, service_role;
