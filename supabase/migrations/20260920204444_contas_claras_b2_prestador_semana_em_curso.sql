-- APLICADA EM PRODUÇÃO pela Claude.ai (MCP) a 20/09/2026 21:44 — versão 20260920204444.
-- Espelho exacto de supabase_migrations.schema_migrations (lido a 20/09 21:55 pelo Claude Code).
-- Substitui a v0 (contas_claras_b2_semana_em_curso_v0) e a PROPOSTA 20260920204500 do repo.
CREATE OR REPLACE FUNCTION public._prestador_semana_em_curso(p_uid uuid)
RETURNS jsonb
LANGUAGE plpgsql STABLE SECURITY DEFINER SET search_path = public
AS $$
BEGIN
  RETURN public.compute_driver_settlement(p_uid, now(), false);
END;
$$;

REVOKE ALL ON FUNCTION public._prestador_semana_em_curso(uuid) FROM PUBLIC, anon, authenticated;

COMMENT ON FUNCTION public._prestador_semana_em_curso(uuid) IS
  'Contas claras (20/09/2026): previsao da semana em curso pela formula oficial do acerto, so leitura. Chamada por extrato_prestador().';
