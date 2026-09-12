-- Sessão 5B-α B1 — Tabela fila aprovação shadow mode
CREATE TABLE IF NOT EXISTS public.support_pending_actions (
  id              uuid        PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id      uuid        REFERENCES public.support_chatbot_sessions(id),
  user_id         uuid        REFERENCES public.users(id),
  skill_name      text        NOT NULL,
  action_type     text        NOT NULL,
  action_payload  jsonb       NOT NULL DEFAULT '{}',
  status          text        NOT NULL DEFAULT 'pending'
                  CHECK (status IN ('pending','executed','failed','rejected')),
  proposed_at     timestamptz DEFAULT now(),
  reviewed_at     timestamptz,
  reviewed_by     uuid,
  executed_at     timestamptz,
  execution_result jsonb,
  rejection_reason text,
  user_message    text,
  agent_reasoning text
);

ALTER TABLE public.support_pending_actions ENABLE ROW LEVEL SECURITY;

CREATE POLICY "client_own_actions"
  ON public.support_pending_actions
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "admin_all_actions"
  ON public.support_pending_actions
  FOR ALL USING (public.is_admin());

CREATE POLICY "service_role_insert"
  ON public.support_pending_actions
  FOR INSERT WITH CHECK (auth.role() = 'service_role');

CREATE INDEX IF NOT EXISTS idx_pending_actions_status
  ON public.support_pending_actions (status)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_pending_actions_user
  ON public.support_pending_actions (user_id);

CREATE INDEX IF NOT EXISTS idx_pending_actions_proposed_at
  ON public.support_pending_actions (proposed_at DESC);

ALTER PUBLICATION supabase_realtime
  ADD TABLE public.support_pending_actions;
