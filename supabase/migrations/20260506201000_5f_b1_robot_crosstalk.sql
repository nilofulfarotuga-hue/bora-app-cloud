-- Sessão 5F B1 — Comunicação Robô A ↔ Robô B
-- Tabela robot_crosstalk + helper _anonymize_pii + 3 RPCs (ask, respond, list)
-- A4 decisão Opção A modificada:
--   - agent_ask_robot_b: GRANT authenticated (espelha 6 RPCs agent_* 5B)
--   - robot_b_respond:   GRANT service_role only (scripts via SERVICE_ROLE_KEY)
--   - admin_list_crosstalk: GRANT authenticated + is_admin() internal

-- ═══ Helper PII (reusable; espelha regexes Edge Fn 5D analyze-conversations) ═══
CREATE OR REPLACE FUNCTION public._anonymize_pii(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT regexp_replace(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          regexp_replace(coalesce(p_text, ''),
            '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
            '[email]', 'g'),
          '\+?351[\s.-]?9\d{2}[\s.-]?\d{3}[\s.-]?\d{3}',
          '[phone]', 'g'),
        '\+?[1-9]\d{6,14}',
        '[phone]', 'g'),
      '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
      '[uuid]', 'g'),
    '\y\d{4,}\y',
    '[number]', 'g');
$$;

-- ═══ Tabela robot_crosstalk ═══
CREATE TABLE IF NOT EXISTS public.robot_crosstalk (
  id               uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at       timestamptz NOT NULL DEFAULT now(),
  direction        text NOT NULL
                   CHECK (direction IN ('a_to_b','b_to_a')),
  status           text NOT NULL DEFAULT 'pending'
                   CHECK (status IN ('pending','answered','ignored')),
  question         text NOT NULL,
  question_context jsonb NOT NULL DEFAULT '{}'::jsonb,
  asked_by         text NOT NULL
                   CHECK (asked_by IN ('robot_a','robot_b','admin')),
  answer           text,
  answered_at      timestamptz,
  answered_by      text
                   CHECK (answered_by IS NULL
                          OR answered_by IN ('robot_a','robot_b','admin')),
  skill_triggered  text,
  rag_chunks_used  jsonb NOT NULL DEFAULT '[]'::jsonb,
  session_id       uuid REFERENCES public.support_chatbot_sessions(id)
                   ON DELETE SET NULL
);

ALTER TABLE public.robot_crosstalk ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "admin_all" ON public.robot_crosstalk;
CREATE POLICY "admin_all" ON public.robot_crosstalk
  FOR ALL USING (public.is_admin());

DROP POLICY IF EXISTS "service_role_all" ON public.robot_crosstalk;
CREATE POLICY "service_role_all" ON public.robot_crosstalk
  FOR ALL USING (auth.role() = 'service_role');

CREATE INDEX IF NOT EXISTS idx_crosstalk_status_pending
  ON public.robot_crosstalk (status)
  WHERE status = 'pending';

CREATE INDEX IF NOT EXISTS idx_crosstalk_direction
  ON public.robot_crosstalk (direction);

CREATE INDEX IF NOT EXISTS idx_crosstalk_created_at
  ON public.robot_crosstalk (created_at DESC);

-- Realtime publication (idempotente — DO block evita erro se já membro)
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname='supabase_realtime'
      AND schemaname='public'
      AND tablename='robot_crosstalk'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.robot_crosstalk;
  END IF;
END $$;

-- ═══ RPC: agent_ask_robot_b (chatbot regista pergunta técnica) ═══
CREATE OR REPLACE FUNCTION public.agent_ask_robot_b(
  p_question        text,
  p_session_id      uuid    DEFAULT NULL,
  p_skill_triggered text    DEFAULT NULL,
  p_context         jsonb   DEFAULT '{}'::jsonb
)
RETURNS uuid
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE v_id uuid;
BEGIN
  IF auth.uid() IS NULL THEN
    RAISE EXCEPTION 'NOT_AUTHENTICATED';
  END IF;

  IF p_question IS NULL OR length(trim(p_question)) = 0 THEN
    RAISE EXCEPTION 'INVALID_QUESTION';
  END IF;

  INSERT INTO robot_crosstalk (
    direction, question, question_context,
    asked_by, session_id, skill_triggered
  ) VALUES (
    'a_to_b',
    public._anonymize_pii(p_question),
    coalesce(p_context, '{}'::jsonb),
    'robot_a',
    p_session_id,
    p_skill_triggered
  ) RETURNING id INTO v_id;

  RETURN v_id;
END;
$$;

REVOKE ALL ON FUNCTION public.agent_ask_robot_b(text, uuid, text, jsonb)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.agent_ask_robot_b(text, uuid, text, jsonb)
  TO authenticated, service_role;

-- ═══ RPC: robot_b_respond (Robô B → A via scripts) ═══
CREATE OR REPLACE FUNCTION public.robot_b_respond(
  p_crosstalk_id uuid,
  p_answer       text,
  p_rag_chunks   jsonb DEFAULT '[]'::jsonb
)
RETURNS void
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF p_answer IS NULL OR length(trim(p_answer)) = 0 THEN
    RAISE EXCEPTION 'INVALID_ANSWER';
  END IF;

  UPDATE robot_crosstalk
  SET answer          = p_answer,
      answered_at     = now(),
      answered_by     = 'robot_b',
      status          = 'answered',
      rag_chunks_used = coalesce(p_rag_chunks, '[]'::jsonb)
  WHERE id = p_crosstalk_id
    AND status = 'pending';

  IF NOT FOUND THEN
    RAISE EXCEPTION 'CROSSTALK_NOT_FOUND_OR_NOT_PENDING';
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.robot_b_respond(uuid, text, jsonb)
  FROM PUBLIC, anon, authenticated;
GRANT EXECUTE ON FUNCTION public.robot_b_respond(uuid, text, jsonb)
  TO service_role;

-- ═══ RPC: admin_list_crosstalk (Flutter observador) ═══
CREATE OR REPLACE FUNCTION public.admin_list_crosstalk(
  p_status    text DEFAULT 'pending',
  p_direction text DEFAULT 'all',
  p_limit     int  DEFAULT 50
)
RETURNS TABLE (
  id               uuid,
  created_at       timestamptz,
  direction        text,
  status           text,
  question         text,
  answer           text,
  asked_by         text,
  answered_by      text,
  answered_at      timestamptz,
  skill_triggered  text,
  rag_chunks_count int,
  rag_chunks_used  jsonb,
  session_id       uuid,
  question_context jsonb
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;

  RETURN QUERY
  SELECT c.id, c.created_at, c.direction, c.status,
         c.question, c.answer, c.asked_by, c.answered_by,
         c.answered_at, c.skill_triggered,
         COALESCE(jsonb_array_length(c.rag_chunks_used), 0)::int,
         c.rag_chunks_used, c.session_id, c.question_context
  FROM robot_crosstalk c
  WHERE (p_status = 'all'    OR c.status = p_status)
    AND (p_direction = 'all' OR c.direction = p_direction)
  ORDER BY c.created_at DESC
  LIMIT p_limit;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_crosstalk(text, text, int)
  FROM PUBLIC, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_crosstalk(text, text, int)
  TO authenticated;
