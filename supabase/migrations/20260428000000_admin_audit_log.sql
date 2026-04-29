-- ============================================================================
-- BORA — Admin Audit Log
-- ============================================================================
-- Captures every administrative action so we can answer "who changed what,
-- when, from where". Append-only by design: the only way to insert is via
-- the SECURITY DEFINER RPC `public.log_admin_action(...)`.
--
-- Reads are gated by the `bora_role='admin'` claim already set in
-- `auth.users.raw_user_meta_data` (migration 20260424100000).
--
-- This is part of the FASE 1 of the admin panel audit (report:
-- .claude/.ai/reports/2026-04-28-admin-panel-audit.md).
-- ============================================================================

BEGIN;

-- ── Table ────────────────────────────────────────────────────────────────────
CREATE TABLE IF NOT EXISTS public.admin_audit_log (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  admin_id     UUID,
  admin_email  TEXT,
  action       TEXT        NOT NULL,
  entity_type  TEXT,
  entity_id    UUID,
  details      JSONB       NOT NULL DEFAULT '{}'::jsonb,
  ip_address   TEXT,
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now()
);

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_admin_created
  ON public.admin_audit_log (admin_id, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_entity
  ON public.admin_audit_log (entity_type, entity_id);

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_action_created
  ON public.admin_audit_log (action, created_at DESC);

COMMENT ON TABLE public.admin_audit_log IS
  'Append-only log of administrative actions. Inserts only via log_admin_action() RPC.';

-- ── Row-Level Security ───────────────────────────────────────────────────────
ALTER TABLE public.admin_audit_log ENABLE ROW LEVEL SECURITY;

-- Read: only users with bora_role='admin' in their JWT claims.
DROP POLICY IF EXISTS "admin_audit_log_select_admin" ON public.admin_audit_log;
CREATE POLICY "admin_audit_log_select_admin"
  ON public.admin_audit_log
  FOR SELECT
  TO authenticated
  USING (
    COALESCE(
      (auth.jwt() -> 'user_metadata' ->> 'bora_role'),
      (auth.jwt() ->> 'role')
    ) = 'admin'
  );

-- No INSERT / UPDATE / DELETE policies → table is locked for direct writes
-- from `authenticated`. Inserts must go through the SECURITY DEFINER RPC.
-- (The RPC bypasses RLS because it owns the table via postgres role.)

-- ── RPC: log_admin_action ────────────────────────────────────────────────────
-- Reads admin identity from auth context. NEVER trusts client-supplied
-- admin_id / admin_email — those are derived server-side.
CREATE OR REPLACE FUNCTION public.log_admin_action(
  p_action      TEXT,
  p_entity_type TEXT  DEFAULT NULL,
  p_entity_id   UUID  DEFAULT NULL,
  p_details     JSONB DEFAULT '{}'::jsonb
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin_id    UUID;
  v_admin_email TEXT;
  v_role        TEXT;
  v_log_id      UUID;
BEGIN
  v_admin_id := auth.uid();

  -- Pull email from JWT (auth.jwt() returns the full claims jsonb).
  v_admin_email := COALESCE(
    auth.jwt() ->> 'email',
    (auth.jwt() -> 'user_metadata' ->> 'email')
  );

  v_role := COALESCE(
    (auth.jwt() -> 'user_metadata' ->> 'bora_role'),
    (auth.jwt() ->> 'role')
  );

  -- Soft guard: must be authenticated. We don't enforce role='admin' here
  -- because the gate today is the client-side email allowlist; switching to
  -- a strict role check is tracked in the audit report (Fase B7).
  IF v_admin_id IS NULL THEN
    RAISE EXCEPTION 'log_admin_action: not authenticated';
  END IF;

  IF p_action IS NULL OR length(trim(p_action)) = 0 THEN
    RAISE EXCEPTION 'log_admin_action: action cannot be null or empty';
  END IF;

  INSERT INTO public.admin_audit_log (
    admin_id, admin_email, action, entity_type, entity_id, details
  ) VALUES (
    v_admin_id,
    v_admin_email,
    p_action,
    p_entity_type,
    p_entity_id,
    COALESCE(p_details, '{}'::jsonb)
  )
  RETURNING id INTO v_log_id;

  RETURN v_log_id;
END;
$$;

REVOKE ALL ON FUNCTION public.log_admin_action(TEXT, TEXT, UUID, JSONB) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.log_admin_action(TEXT, TEXT, UUID, JSONB) TO authenticated;

COMMENT ON FUNCTION public.log_admin_action(TEXT, TEXT, UUID, JSONB) IS
  'Append a row to admin_audit_log. Reads admin identity from auth.uid()/auth.jwt(). SECURITY DEFINER. Idempotency is the caller responsibility.';

COMMIT;
