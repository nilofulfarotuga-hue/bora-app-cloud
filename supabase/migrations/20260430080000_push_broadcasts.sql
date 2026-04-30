-- ============================================================================
-- BORA — Push broadcasts (T12 — sessão final 2026-04-30)
-- ============================================================================
-- Scaffold para broadcasts segmentados (todos / só clientes / só estafetas).
-- Tabela de intents + RPC admin para criar. Edge Function consome.
--
-- IMPORTANTE: FCM é launch blocker (#1). Esta migration cria o esqueleto;
-- envio efectivo só funciona após `google-services.json` + secrets Firebase.
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.push_broadcasts (
  id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  segment         TEXT         NOT NULL CHECK (segment IN ('all', 'clients', 'drivers', 'partners')),
  title           TEXT         NOT NULL CHECK (length(title) BETWEEN 1 AND 100),
  body            TEXT         NOT NULL CHECK (length(body) BETWEEN 1 AND 500),
  scheduled_at    TIMESTAMPTZ  NOT NULL DEFAULT now(),
  status          TEXT         NOT NULL DEFAULT 'pending'
                               CHECK (status IN ('pending', 'sending', 'sent', 'failed')),
  sent_count      INT          NOT NULL DEFAULT 0,
  failed_count    INT          NOT NULL DEFAULT 0,
  created_by      UUID         REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  completed_at    TIMESTAMPTZ
);

CREATE INDEX IF NOT EXISTS idx_push_broadcasts_status_scheduled
  ON public.push_broadcasts (status, scheduled_at);

ALTER TABLE public.push_broadcasts ENABLE ROW LEVEL SECURITY;
-- No SELECT/INSERT/UPDATE policy — admin via RPCs only.

CREATE OR REPLACE FUNCTION public.admin_create_broadcast(
  p_segment      TEXT,
  p_title        TEXT,
  p_body         TEXT,
  p_scheduled_at TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin RECORD;
  v_id    UUID;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_segment NOT IN ('all', 'clients', 'drivers', 'partners') THEN
    RAISE EXCEPTION 'admin_create_broadcast: invalid segment';
  END IF;

  INSERT INTO public.push_broadcasts (segment, title, body, scheduled_at, created_by)
  VALUES (p_segment, trim(p_title), trim(p_body), COALESCE(p_scheduled_at, now()), v_admin.admin_id)
  RETURNING id INTO v_id;

  INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id, details)
  VALUES (v_admin.admin_id, v_admin.admin_email, 'broadcast_create', 'push_broadcast', v_id,
    jsonb_build_object('segment', p_segment, 'title', trim(p_title), 'scheduled_at', p_scheduled_at));

  RETURN jsonb_build_object('success', true, 'broadcast_id', v_id);
END;
$$;
REVOKE ALL ON FUNCTION public.admin_create_broadcast(TEXT, TEXT, TEXT, TIMESTAMPTZ) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_create_broadcast(TEXT, TEXT, TEXT, TIMESTAMPTZ) TO authenticated;

CREATE OR REPLACE FUNCTION public.admin_list_broadcasts(p_limit INT DEFAULT 50)
RETURNS TABLE (
  id UUID, segment TEXT, title TEXT, body TEXT,
  status TEXT, sent_count INT, failed_count INT,
  scheduled_at TIMESTAMPTZ, completed_at TIMESTAMPTZ, created_at TIMESTAMPTZ
)
LANGUAGE plpgsql SECURITY DEFINER STABLE SET search_path = public
AS $$
DECLARE v_admin RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_limit < 1 OR p_limit > 500 THEN p_limit := 50; END IF;
  RETURN QUERY
  SELECT b.id, b.segment, b.title, b.body, b.status,
         b.sent_count, b.failed_count, b.scheduled_at, b.completed_at, b.created_at
  FROM public.push_broadcasts b
  ORDER BY b.scheduled_at DESC
  LIMIT p_limit;
END;
$$;
REVOKE ALL ON FUNCTION public.admin_list_broadcasts(INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_broadcasts(INT) TO authenticated;

COMMIT;

-- TODO: Edge Function `broadcast-push` consumes status='pending' rows, fans
-- out to FCM tokens by segment, marks status='sent'/'failed' with counts.
-- Blocked by Firebase setup (launch blocker #1).
