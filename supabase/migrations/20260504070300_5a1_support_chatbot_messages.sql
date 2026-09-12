-- Sessão 5A-1 B4 — support_chatbot_messages
-- Histórico individual: user/assistant/tool/system com payload tool calls.

CREATE TABLE IF NOT EXISTS public.support_chatbot_messages (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  session_id uuid NOT NULL REFERENCES public.support_chatbot_sessions(id)
    ON DELETE CASCADE,
  role text NOT NULL CHECK (role IN ('user','assistant','tool','system')),
  content text NOT NULL,
  tool_name text,
  tool_input jsonb,
  tool_output jsonb,
  tokens_used int,
  created_at timestamptz DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_chatbot_messages_session_created
  ON public.support_chatbot_messages (session_id, created_at);

ALTER TABLE public.support_chatbot_messages ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS chatbot_messages_select_own ON public.support_chatbot_messages;
CREATE POLICY chatbot_messages_select_own ON public.support_chatbot_messages
  FOR SELECT TO authenticated
  USING (
    EXISTS (
      SELECT 1 FROM public.support_chatbot_sessions s
      WHERE s.id = session_id
        AND (s.user_id = auth.uid() OR public.is_admin())
    )
  );

DROP POLICY IF EXISTS chatbot_messages_modify_admin ON public.support_chatbot_messages;
CREATE POLICY chatbot_messages_modify_admin ON public.support_chatbot_messages
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());
