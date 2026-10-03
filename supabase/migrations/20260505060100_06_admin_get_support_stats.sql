-- Sessão 6 B3 — RPC admin_get_support_stats
-- Métricas robô IA suporte: sessões, resolução, tokens, custo Gemini, top skills.
-- SECURITY DEFINER admin-only via is_admin().
-- Preços Gemini Flash 2026-05: $0.075/M input + $0.30/M output (USD→EUR ≈0.90).

CREATE OR REPLACE FUNCTION public.admin_get_support_stats(
  p_from timestamptz,
  p_to   timestamptz
) RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_result jsonb;
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  WITH
    sessions_total AS (
      SELECT COUNT(*) AS c FROM support_chatbot_sessions
      WHERE started_at BETWEEN p_from AND p_to
    ),
    sessions_resolved AS (
      SELECT COUNT(*) AS c FROM support_chatbot_sessions
      WHERE started_at BETWEEN p_from AND p_to
        AND escalated = false AND ended_at IS NOT NULL
    ),
    sessions_escalated AS (
      SELECT COUNT(*) AS c FROM support_chatbot_sessions
      WHERE started_at BETWEEN p_from AND p_to
        AND escalated = true
    ),
    tokens_breakdown AS (
      SELECT
        COALESCE(SUM(tokens_used) FILTER (WHERE role = 'user'), 0) AS input_tokens,
        COALESCE(SUM(tokens_used) FILTER (WHERE role = 'assistant'), 0) AS output_tokens,
        COALESCE(SUM(tokens_used), 0) AS total_tokens
      FROM support_chatbot_messages
      WHERE created_at BETWEEN p_from AND p_to
    ),
    avg_messages AS (
      SELECT COALESCE(AVG(messages_count)::numeric(10,2), 0) AS avg_msgs
      FROM support_chatbot_sessions
      WHERE started_at BETWEEN p_from AND p_to
    ),
    top_skills AS (
      SELECT active_skill, COUNT(*) AS uses,
        ROUND(
          (COUNT(*) FILTER (WHERE escalated = false))::numeric /
          NULLIF(COUNT(*), 0) * 100, 2
        ) AS success_rate_pct
      FROM support_chatbot_sessions
      WHERE started_at BETWEEN p_from AND p_to
        AND active_skill IS NOT NULL
      GROUP BY active_skill
      ORDER BY uses DESC LIMIT 10
    ),
    escalating_skills AS (
      SELECT active_skill, COUNT(*) AS escalations
      FROM support_chatbot_sessions
      WHERE started_at BETWEEN p_from AND p_to
        AND escalated = true AND active_skill IS NOT NULL
      GROUP BY active_skill
      ORDER BY escalations DESC LIMIT 5
    ),
    tickets_by_channel AS (
      SELECT channel, COUNT(*) AS c
      FROM support_tickets
      WHERE created_at BETWEEN p_from AND p_to
      GROUP BY channel
    ),
    avg_satisfaction AS (
      SELECT COALESCE(AVG(satisfaction)::numeric(10,2), 0) AS avg_sat,
             COUNT(satisfaction) AS rated
      FROM support_tickets
      WHERE created_at BETWEEN p_from AND p_to
        AND satisfaction IS NOT NULL
    )
  SELECT jsonb_build_object(
    'period', jsonb_build_object('from', p_from, 'to', p_to),
    'sessions_total', (SELECT c FROM sessions_total),
    'sessions_resolved', (SELECT c FROM sessions_resolved),
    'sessions_escalated', (SELECT c FROM sessions_escalated),
    'resolution_rate_pct',
      CASE WHEN (SELECT c FROM sessions_total) > 0
        THEN ROUND(((SELECT c FROM sessions_resolved)::numeric /
                    (SELECT c FROM sessions_total)) * 100, 2)
        ELSE 0 END,
    'avg_messages_per_session', (SELECT avg_msgs FROM avg_messages),
    'tokens', (SELECT row_to_json(t) FROM tokens_breakdown t),
    'cost_eur_estimated',
      ROUND(
        (SELECT
          (input_tokens::numeric / 1000000) * 0.067 +
          (output_tokens::numeric / 1000000) * 0.27
         FROM tokens_breakdown), 4
      ),
    'top_skills',
      COALESCE((SELECT jsonb_agg(row_to_json(s)) FROM top_skills s), '[]'::jsonb),
    'escalating_skills',
      COALESCE((SELECT jsonb_agg(row_to_json(e)) FROM escalating_skills e), '[]'::jsonb),
    'tickets_by_channel',
      COALESCE((SELECT jsonb_agg(row_to_json(t)) FROM tickets_by_channel t), '[]'::jsonb),
    'avg_satisfaction', (SELECT avg_sat FROM avg_satisfaction),
    'satisfaction_responses', (SELECT rated FROM avg_satisfaction)
  ) INTO v_result;

  RETURN v_result;
END$$;

REVOKE ALL ON FUNCTION public.admin_get_support_stats(timestamptz, timestamptz) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_get_support_stats(timestamptz, timestamptz) TO authenticated;

COMMENT ON FUNCTION public.admin_get_support_stats(timestamptz, timestamptz) IS
  'Sessão 6 B3 — Estatísticas robô IA suporte. Admin-only via is_admin(). '
  'Preços Gemini hardcoded — TODO migrar para support_settings.pricing_jsonb.';
