-- Sessão 5A-1 B6 — support_agent_actions
-- Audit trail das acções propostas/executadas pelo agente IA.
-- 5A: skills read-only só inserem 'not_applicable'.
-- 5B: workflow shadow real (4 semanas admin aprova).

CREATE TABLE IF NOT EXISTS public.support_agent_actions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid REFERENCES public.support_chatbot_sessions(id) ON DELETE SET NULL,
  user_id uuid NOT NULL,
  skill_name text NOT NULL,
  action_type text NOT NULL,
  action_payload jsonb,
  proposed_at timestamptz DEFAULT now(),
  shadow_status text NOT NULL DEFAULT 'pending'
    CHECK (shadow_status IN
      ('pending','approved','rejected','executed','auto_executed','not_applicable')),
  reviewed_by uuid,
  reviewed_at timestamptz,
  executed_at timestamptz,
  result jsonb,
  notes text
);

CREATE INDEX IF NOT EXISTS idx_agent_actions_session
  ON public.support_agent_actions (session_id);
CREATE INDEX IF NOT EXISTS idx_agent_actions_status_time
  ON public.support_agent_actions (shadow_status, proposed_at DESC);

ALTER TABLE public.support_agent_actions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS agent_actions_select_own ON public.support_agent_actions;
CREATE POLICY agent_actions_select_own ON public.support_agent_actions
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS agent_actions_modify_admin ON public.support_agent_actions;
CREATE POLICY agent_actions_modify_admin ON public.support_agent_actions
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
