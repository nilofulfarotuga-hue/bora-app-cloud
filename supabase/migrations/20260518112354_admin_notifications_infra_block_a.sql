-- Admin notifications infrastructure: table + helper function
-- Applied via MCP on 2026-05-18, local file created on same date

CREATE TABLE IF NOT EXISTS public.admin_notifications (
  id           UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  created_at   TIMESTAMPTZ NOT NULL DEFAULT now(),
  event_type   TEXT NOT NULL,
  severity     TEXT NOT NULL,
  entity_type  TEXT,
  entity_id    TEXT,
  summary      TEXT NOT NULL,
  payload      JSONB DEFAULT '{}'::jsonb,
  deep_link    TEXT,
  read_at      TIMESTAMPTZ,
  archived_at  TIMESTAMPTZ
);

CREATE OR REPLACE FUNCTION public.notify_admin_event(
  p_event_type  TEXT,
  p_severity    TEXT,
  p_summary     TEXT,
  p_entity_type TEXT DEFAULT NULL,
  p_entity_id   TEXT DEFAULT NULL,
  p_payload     JSONB DEFAULT '{}'::jsonb,
  p_deep_link   TEXT DEFAULT NULL
) RETURNS UUID
  LANGUAGE plpgsql
  SECURITY DEFINER
  SET search_path TO 'public'
AS $function$
DECLARE v_id uuid;
BEGIN
  INSERT INTO public.admin_notifications (
    event_type, severity, summary,
    entity_type, entity_id, payload, deep_link
  ) VALUES (
    p_event_type, p_severity, p_summary,
    p_entity_type, p_entity_id, COALESCE(p_payload, '{}'::jsonb), p_deep_link
  ) RETURNING id INTO v_id;
  RETURN v_id;
END;
$function$;
