-- ============================================================================
-- BORA — Complaints / inbox (T14)
-- ============================================================================
-- Simple schema + RPCs for clients/drivers/partners to file complaints,
-- and admin to triage them. No chatbot — just inbox + status changes.
--
-- Status flow: open → in_progress → resolved | dismissed
-- ============================================================================

BEGIN;

CREATE TABLE IF NOT EXISTS public.complaints (
  id              UUID         PRIMARY KEY DEFAULT gen_random_uuid(),
  reporter_id     UUID         NOT NULL REFERENCES auth.users(id) ON DELETE CASCADE,
  reporter_role   TEXT         NOT NULL CHECK (reporter_role IN ('client', 'driver', 'partner')),
  category        TEXT         NOT NULL CHECK (category IN (
                                'order_issue', 'payment_issue', 'driver_behavior',
                                'partner_behavior', 'app_bug', 'other')),
  subject         TEXT         NOT NULL CHECK (length(subject) BETWEEN 3 AND 200),
  body            TEXT         NOT NULL CHECK (length(body) BETWEEN 5 AND 5000),
  related_order_id UUID        REFERENCES public.orders(id) ON DELETE SET NULL,
  status          TEXT         NOT NULL DEFAULT 'open'
                               CHECK (status IN ('open', 'in_progress', 'resolved', 'dismissed')),
  admin_notes     TEXT         NOT NULL DEFAULT '',
  resolved_at     TIMESTAMPTZ,
  resolved_by     UUID         REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at      TIMESTAMPTZ  NOT NULL DEFAULT now(),
  updated_at      TIMESTAMPTZ  NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_complaints_status_created
  ON public.complaints (status, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_complaints_reporter
  ON public.complaints (reporter_id, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_complaints_related_order
  ON public.complaints (related_order_id) WHERE related_order_id IS NOT NULL;

-- RLS: reporter sees own; admin sees all (via SECURITY DEFINER RPCs).
ALTER TABLE public.complaints ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS complaints_select_own ON public.complaints;
CREATE POLICY complaints_select_own
  ON public.complaints
  FOR SELECT
  TO authenticated
  USING (reporter_id = auth.uid());

DROP POLICY IF EXISTS complaints_insert_own ON public.complaints;
CREATE POLICY complaints_insert_own
  ON public.complaints
  FOR INSERT
  TO authenticated
  WITH CHECK (reporter_id = auth.uid());

-- No UPDATE/DELETE policy — admin operates via RPCs.

-- ─── Trigger: bump updated_at on UPDATE ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.fn_complaints_set_updated_at()
RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at := now();
  RETURN NEW;
END $$;

DROP TRIGGER IF EXISTS trg_complaints_updated_at ON public.complaints;
CREATE TRIGGER trg_complaints_updated_at
  BEFORE UPDATE ON public.complaints
  FOR EACH ROW EXECUTE FUNCTION public.fn_complaints_set_updated_at();


-- ─── RPC: admin_list_complaints (filter + paginate) ──────────────────────────
CREATE OR REPLACE FUNCTION public.admin_list_complaints(
  p_status_filter TEXT DEFAULT NULL,   -- 'open' | 'in_progress' | 'resolved' | 'dismissed' | NULL
  p_limit         INT  DEFAULT 50,
  p_offset        INT  DEFAULT 0
)
RETURNS TABLE (
  id              UUID,
  reporter_id     UUID,
  reporter_email  TEXT,
  reporter_role   TEXT,
  category        TEXT,
  subject         TEXT,
  body            TEXT,
  related_order_id UUID,
  status          TEXT,
  created_at      TIMESTAMPTZ,
  resolved_at     TIMESTAMPTZ
)
LANGUAGE plpgsql
SECURITY DEFINER
STABLE
SET search_path = public, auth
AS $$
DECLARE
  v_admin RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_limit < 1 OR p_limit > 500 THEN p_limit := 50; END IF;

  RETURN QUERY
  SELECT
    c.id, c.reporter_id,
    u.email::TEXT,
    c.reporter_role, c.category, c.subject, c.body,
    c.related_order_id, c.status, c.created_at, c.resolved_at
  FROM public.complaints c
  LEFT JOIN auth.users u ON u.id = c.reporter_id
  WHERE p_status_filter IS NULL OR c.status = p_status_filter
  ORDER BY
    CASE c.status WHEN 'open' THEN 0 WHEN 'in_progress' THEN 1 ELSE 2 END,
    c.created_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$$;

REVOKE ALL ON FUNCTION public.admin_list_complaints(TEXT, INT, INT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_list_complaints(TEXT, INT, INT) TO authenticated;


-- ─── RPC: admin_update_complaint_status ──────────────────────────────────────
CREATE OR REPLACE FUNCTION public.admin_update_complaint_status(
  p_complaint_id UUID,
  p_new_status   TEXT,
  p_admin_notes  TEXT DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin RECORD;
  v_old   RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_new_status NOT IN ('open', 'in_progress', 'resolved', 'dismissed') THEN
    RAISE EXCEPTION 'admin_update_complaint_status: invalid status %', p_new_status;
  END IF;

  SELECT id, status, admin_notes INTO v_old FROM public.complaints WHERE id = p_complaint_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_update_complaint_status: complaint % not found', p_complaint_id;
  END IF;

  UPDATE public.complaints
     SET status      = p_new_status,
         admin_notes = COALESCE(p_admin_notes, admin_notes),
         resolved_at = CASE WHEN p_new_status IN ('resolved', 'dismissed')
                            THEN now() ELSE resolved_at END,
         resolved_by = CASE WHEN p_new_status IN ('resolved', 'dismissed')
                            THEN v_admin.admin_id ELSE resolved_by END
   WHERE id = p_complaint_id;

  INSERT INTO public.admin_audit_log (
    admin_id, admin_email, action, entity_type, entity_id, details
  ) VALUES (
    v_admin.admin_id, v_admin.admin_email, 'complaint_status_update', 'complaint', p_complaint_id,
    jsonb_build_object(
      'old_status', v_old.status,
      'new_status', p_new_status,
      'admin_notes_appended', p_admin_notes IS NOT NULL
    )
  );

  RETURN jsonb_build_object('success', true, 'complaint_id', p_complaint_id, 'status', p_new_status);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_complaint_status(UUID, TEXT, TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_complaint_status(UUID, TEXT, TEXT) TO authenticated;


-- ─── RPC: file_complaint (used by client/driver/partner) ────────────────────
CREATE OR REPLACE FUNCTION public.file_complaint(
  p_role             TEXT,
  p_category         TEXT,
  p_subject          TEXT,
  p_body             TEXT,
  p_related_order_id UUID DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_uid UUID := auth.uid();
  v_id  UUID;
BEGIN
  IF v_uid IS NULL THEN
    RAISE EXCEPTION 'file_complaint: not authenticated';
  END IF;

  INSERT INTO public.complaints (
    reporter_id, reporter_role, category, subject, body, related_order_id
  ) VALUES (
    v_uid, p_role, p_category, trim(p_subject), trim(p_body), p_related_order_id
  ) RETURNING id INTO v_id;

  RETURN jsonb_build_object('success', true, 'complaint_id', v_id);
END;
$$;

REVOKE ALL ON FUNCTION public.file_complaint(TEXT, TEXT, TEXT, TEXT, UUID) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.file_complaint(TEXT, TEXT, TEXT, TEXT, UUID) TO authenticated;


COMMIT;
