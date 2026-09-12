-- ============================================================================
-- BORA — Support tickets table (T13 — chatbot scaffold)
-- ============================================================================
-- Tabela `support_tickets` separada de `complaints` (complaints = formal queixa,
-- support = pergunta/dúvida/incident). Chatbot AI fica como TODO; por agora
-- regista perguntas para training futuro.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.support_tickets (
  id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id         UUID         REFERENCES auth.users(id) ON DELETE SET NULL,
  user_role       TEXT         NOT NULL CHECK (user_role IN ('client', 'driver', 'partner', 'guest')),
  question        TEXT         NOT NULL CHECK (length(question) BETWEEN 1 AND 2000),
  bot_answer      TEXT,
  human_answer    TEXT,
  satisfaction    INT          CHECK (satisfaction IS NULL OR satisfaction BETWEEN 1 AND 5),
  status          TEXT         NOT NULL DEFAULT 'open'
                               CHECK (status IN ('open', 'bot_answered', 'human_answered', 'closed')),
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  answered_at     TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_support_tickets_user
  ON public.support_tickets (user_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_support_tickets_status
  ON public.support_tickets (status, created_at DESC);

ALTER TABLE public.support_tickets ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS support_tickets_select_own ON public.support_tickets;
CREATE POLICY support_tickets_select_own
  ON public.support_tickets FOR SELECT TO authenticated
  USING (user_id = auth.uid());

DROP POLICY IF EXISTS support_tickets_insert_own ON public.support_tickets;
CREATE POLICY support_tickets_insert_own
  ON public.support_tickets FOR INSERT TO authenticated
  WITH CHECK (user_id = auth.uid());

CREATE OR REPLACE FUNCTION public.file_support_ticket(
  p_role     TEXT,
  p_question TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_uid UUID := auth.uid(); v_id UUID;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not authenticated'; END IF;
  INSERT INTO public.support_tickets (user_id, user_role, question)
  VALUES (v_uid, p_role, trim(p_question))
  RETURNING id INTO v_id;
  -- TODO: trigger AI bot answer here when chatbot integration ships.
  RETURN jsonb_build_object('success', true, 'ticket_id', v_id,
    'placeholder', 'Bot AI ainda não disponível. Um humano vai responder.');
END;
$$;
REVOKE ALL ON FUNCTION public.file_support_ticket(TEXT, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.file_support_ticket(TEXT, TEXT) TO authenticated;

COMMIT;
