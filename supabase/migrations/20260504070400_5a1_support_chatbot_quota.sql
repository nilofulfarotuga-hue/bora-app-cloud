-- Sessão 5A-1 B5 — support_chatbot_quota + RPC atómico
-- Rate limit diário por user. Increment via UPSERT atómico (anti race-condition).

CREATE TABLE IF NOT EXISTS public.support_chatbot_quota (
  user_id uuid NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  day date NOT NULL DEFAULT CURRENT_DATE,
  messages_count int NOT NULL DEFAULT 0,
  PRIMARY KEY (user_id, day)
);

ALTER TABLE public.support_chatbot_quota ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS chatbot_quota_select_own ON public.support_chatbot_quota;
CREATE POLICY chatbot_quota_select_own ON public.support_chatbot_quota
  FOR SELECT TO authenticated
  USING (user_id = auth.uid() OR public.is_admin());

DROP POLICY IF EXISTS chatbot_quota_modify_admin ON public.support_chatbot_quota;
CREATE POLICY chatbot_quota_modify_admin ON public.support_chatbot_quota
  FOR ALL TO authenticated
  USING (public.is_admin())
  WITH CHECK (public.is_admin());

-- RPC increment atómico — usa auth.uid() directo (sem p_user_id, defesa impersonation).
CREATE OR REPLACE FUNCTION public.increment_chatbot_quota()
RETURNS int
LANGUAGE sql
SECURITY DEFINER
SET search_path = public
AS $$
  INSERT INTO public.support_chatbot_quota (user_id, day, messages_count)
  VALUES (auth.uid(), CURRENT_DATE, 1)
  ON CONFLICT (user_id, day)
  DO UPDATE SET messages_count =
    public.support_chatbot_quota.messages_count + 1
  RETURNING messages_count;
$$;

REVOKE ALL ON FUNCTION public.increment_chatbot_quota() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.increment_chatbot_quota() TO authenticated;
