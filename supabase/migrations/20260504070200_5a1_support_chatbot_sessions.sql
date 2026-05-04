-- Sessão 5A-1 B3 — support_chatbot_sessions
-- Sessão de conversa do user com agente IA. Liga a order opcional + ticket opcional.

CREATE TABLE IF NOT EXISTS public.support_chatbot_sessions (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  user_role text NOT NULL,
  order_id text REFERENCES public.orders(id) ON DELETE SET NULL,
  active_skill text,
  messages_count int NOT NULL DEFAULT 0,
  started_at timestamptz DEFAULT now(),
  ended_at timestamptz,
  escalated bool NOT NULL DEFAULT false,
  escalation_reason text,
  ticket_id uuid REFERENCES public.support_tickets(id) ON DELETE SET NULL
);

CREATE INDEX IF NOT EXISTS idx_chatbot_sessions_user_started
  ON public.support_chatbot_sessions (user_id, started_at DESC);
CREATE INDEX IF NOT EXISTS idx_chatbot_sessions_order
  ON public.support_chatbot_sessions (order_id) WHERE order_id IS NOT NULL;

ALTER TABLE public.support_chatbot_sessions ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS chatbot_sessions_select_own ON public.support_chatbot_sessions;
CREATE POLICY chatbot_sessions_select_own ON public.support_chatbot_sessions
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS chatbot_sessions_modify_admin ON public.support_chatbot_sessions;
CREATE POLICY chatbot_sessions_modify_admin ON public.support_chatbot_sessions
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
