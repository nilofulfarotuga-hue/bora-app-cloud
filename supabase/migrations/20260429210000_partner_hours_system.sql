-- ============================================================================
-- BORA — Partner hours system (T4 — sessão nocturna 2026-04-29)
-- ============================================================================
-- Adds:
--   1. partner_status_override          — admin override of open/closed state
--   2. admin_audit_log.entity_id_text   — workaround for non-UUID entities
--                                         (restaurants.id is TEXT)
--   3. is_partner_open(restaurant_id, at) — rich open/closed check returning
--                                           {is_open, override_active,
--                                            closes_in_minutes, opens_at}
--   4. RPCs:
--      - admin_set_partner_override(restaurant_id, state, reason, ends_at)
--      - admin_clear_partner_override(restaurant_id)
--      - admin_update_partner_hours(restaurant_id, hours)
--      - admin_set_partner_special_date(restaurant_id, date, day_hours)
--
-- All RPCs use _admin_op_guard() and write to admin_audit_log.
-- All RPCs trigger a notify-partner push when the change affects status.
-- ============================================================================

BEGIN;

-- ---------------------------------------------------------------------------
-- 1. partner_status_override table
-- ---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS public.partner_status_override (
  id            UUID        PRIMARY KEY DEFAULT gen_random_uuid(),
  restaurant_id TEXT        NOT NULL REFERENCES public.restaurants(id) ON DELETE CASCADE,
  forced_state  TEXT        NOT NULL CHECK (forced_state IN ('open', 'closed')),
  reason        TEXT        NOT NULL DEFAULT '',
  starts_at     TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  ends_at       TIMESTAMPTZ NULL,
  set_by_admin  UUID        REFERENCES auth.users(id) ON DELETE SET NULL,
  created_at    TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

COMMENT ON TABLE public.partner_status_override IS
  'Admin overrides of partner open/closed state. Active when starts_at <= NOW() < ends_at (or ends_at NULL = indefinite). Latest active override wins. Read by is_partner_open().';

-- Plain indexes (Postgres requires IMMUTABLE in index predicates; NOW()
-- breaks that). "Active = ends_at IS NULL OR ends_at > now()" is enforced
-- at query time by is_partner_open() instead.
CREATE INDEX IF NOT EXISTS idx_partner_status_override_restaurant
  ON public.partner_status_override (restaurant_id, starts_at DESC);
CREATE INDEX IF NOT EXISTS idx_partner_status_override_ends_at
  ON public.partner_status_override (ends_at) WHERE ends_at IS NOT NULL;

-- RLS: read by partner (own restaurant) + admin; write only via RPCs.
ALTER TABLE public.partner_status_override ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS partner_status_override_select_partner ON public.partner_status_override;
CREATE POLICY partner_status_override_select_partner
  ON public.partner_status_override
  FOR SELECT
  TO authenticated
  USING (true);  -- non-sensitive; everyone authenticated can see who's open
                 -- (used by client app to show "Fechado por administração")

-- No INSERT/UPDATE/DELETE policy → only RPCs (SECURITY DEFINER) can mutate.

-- ---------------------------------------------------------------------------
-- 2. admin_audit_log.entity_id_text — workaround for non-UUID entities
-- ---------------------------------------------------------------------------
-- restaurants.id is TEXT (legacy), but admin_audit_log.entity_id is UUID.
-- Add a parallel TEXT column for these cases. Existing entries (driver,
-- order — both UUID) keep using entity_id; new restaurant entries use
-- entity_id_text.
ALTER TABLE public.admin_audit_log
  ADD COLUMN IF NOT EXISTS entity_id_text TEXT NULL;

CREATE INDEX IF NOT EXISTS idx_admin_audit_log_entity_text
  ON public.admin_audit_log (entity_type, entity_id_text)
  WHERE entity_id_text IS NOT NULL;

COMMENT ON COLUMN public.admin_audit_log.entity_id_text IS
  'Optional TEXT id for entities whose primary key is not UUID (e.g. restaurants.id). Mutually exclusive with entity_id at the application layer.';


-- ---------------------------------------------------------------------------
-- 3. is_partner_open(restaurant_id, at) — rich state
-- ---------------------------------------------------------------------------
-- Returns JSONB:
--   { "is_open":              boolean,
--     "override_active":      boolean,
--     "closes_in_minutes":    int|null,    -- if open, minutes until close
--     "opens_at":             text|null    -- if closed, HH:MM of next open
--   }
--
-- Logic precedence:
--   1. Active override → return forced_state
--   2. special_dates entry for today → use it
--   3. Regular weekday hours (business_hours.{mon..sun})
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.is_partner_open(
  p_restaurant_id TEXT,
  p_at            TIMESTAMPTZ DEFAULT NOW()
)
RETURNS JSONB
LANGUAGE plpgsql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_override     RECORD;
  v_hours        JSONB;
  v_special      JSONB;
  v_day_key      TEXT;
  v_day_hours    JSONB;
  v_at_local     TIMESTAMP;       -- naive local timestamp
  v_at_minutes   INT;             -- minutes since midnight
  v_open_minutes INT;
  v_close_minutes INT;
  v_is_open      BOOLEAN;
  v_closes_in    INT;
  v_opens_at     TEXT;
BEGIN
  -- 1. Active override?
  SELECT forced_state, ends_at, reason
    INTO v_override
    FROM public.partner_status_override
   WHERE restaurant_id = p_restaurant_id
     AND starts_at <= p_at
     AND (ends_at IS NULL OR ends_at > p_at)
   ORDER BY starts_at DESC
   LIMIT 1;

  IF FOUND THEN
    RETURN jsonb_build_object(
      'is_open',           v_override.forced_state = 'open',
      'override_active',   true,
      'override_reason',   v_override.reason,
      'override_ends_at',  v_override.ends_at,
      'closes_in_minutes', NULL,
      'opens_at',          NULL
    );
  END IF;

  -- 2. Fetch business_hours
  SELECT business_hours INTO v_hours
    FROM public.restaurants
   WHERE id = p_restaurant_id;

  IF v_hours IS NULL OR jsonb_typeof(v_hours) != 'object' THEN
    -- No hours configured → assume open (legacy behaviour)
    RETURN jsonb_build_object(
      'is_open',           true,
      'override_active',   false,
      'closes_in_minutes', NULL,
      'opens_at',          NULL,
      'note',              'no_hours_configured'
    );
  END IF;

  -- Convert to local (Europe/Lisbon) for hour comparisons
  v_at_local   := (p_at AT TIME ZONE 'Europe/Lisbon')::TIMESTAMP;
  v_at_minutes := EXTRACT(HOUR FROM v_at_local)::INT * 60
                + EXTRACT(MINUTE FROM v_at_local)::INT;

  -- 3. Special dates? (jsonb array under 'special_dates' key)
  IF v_hours ? 'special_dates' AND jsonb_typeof(v_hours->'special_dates') = 'array' THEN
    SELECT elem INTO v_special
      FROM jsonb_array_elements(v_hours->'special_dates') elem
     WHERE (elem->>'date')::DATE = v_at_local::DATE
     LIMIT 1;
    IF FOUND THEN
      v_day_hours := v_special;
    END IF;
  END IF;

  -- 4. Regular weekday hours (if no special date matched)
  IF v_day_hours IS NULL THEN
    v_day_key := CASE EXTRACT(DOW FROM v_at_local)::INT
                   WHEN 0 THEN 'sun'
                   WHEN 1 THEN 'mon'
                   WHEN 2 THEN 'tue'
                   WHEN 3 THEN 'wed'
                   WHEN 4 THEN 'thu'
                   WHEN 5 THEN 'fri'
                   WHEN 6 THEN 'sat'
                 END;
    v_day_hours := v_hours->v_day_key;
  END IF;

  IF v_day_hours IS NULL OR jsonb_typeof(v_day_hours) != 'object'
     OR (v_day_hours->>'closed')::BOOLEAN IS TRUE THEN
    -- Closed today
    RETURN jsonb_build_object(
      'is_open',           false,
      'override_active',   false,
      'closes_in_minutes', NULL,
      'opens_at',          v_day_hours->>'open'
    );
  END IF;

  -- Parse open/close
  v_open_minutes  := _parse_hhmm_to_minutes(v_day_hours->>'open');
  v_close_minutes := _parse_hhmm_to_minutes(v_day_hours->>'close');

  IF v_open_minutes IS NULL OR v_close_minutes IS NULL THEN
    RETURN jsonb_build_object(
      'is_open',           true,
      'override_active',   false,
      'closes_in_minutes', NULL,
      'opens_at',          NULL,
      'note',              'unparseable_hours'
    );
  END IF;

  -- Determine if currently open (handles overnight spans like 20:00→02:00)
  IF v_close_minutes <= v_open_minutes THEN
    -- Overnight window
    v_is_open := v_at_minutes >= v_open_minutes OR v_at_minutes < v_close_minutes;
    IF v_is_open THEN
      v_closes_in := CASE
        WHEN v_at_minutes >= v_open_minutes THEN (1440 - v_at_minutes) + v_close_minutes
        ELSE v_close_minutes - v_at_minutes
      END;
    END IF;
  ELSE
    v_is_open := v_at_minutes >= v_open_minutes AND v_at_minutes < v_close_minutes;
    IF v_is_open THEN
      v_closes_in := v_close_minutes - v_at_minutes;
    END IF;
  END IF;

  IF v_is_open THEN
    RETURN jsonb_build_object(
      'is_open',           true,
      'override_active',   false,
      'closes_in_minutes', v_closes_in,
      'opens_at',          NULL
    );
  ELSE
    RETURN jsonb_build_object(
      'is_open',           false,
      'override_active',   false,
      'closes_in_minutes', NULL,
      'opens_at',          v_day_hours->>'open'
    );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.is_partner_open(TEXT, TIMESTAMPTZ) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.is_partner_open(TEXT, TIMESTAMPTZ) TO authenticated, service_role;

COMMENT ON FUNCTION public.is_partner_open(TEXT, TIMESTAMPTZ) IS
  'Returns rich open/closed state for a partner restaurant. Logic: active override > special_dates > regular hours. Used by dispatch-engine (BR §6.7) and client app (badges).';


-- helper for HH:MM parse (idempotent)
CREATE OR REPLACE FUNCTION public._parse_hhmm_to_minutes(p_hhmm TEXT)
RETURNS INT
LANGUAGE plpgsql
IMMUTABLE
AS $$
DECLARE
  v_h INT;
  v_m INT;
  v_parts TEXT[];
BEGIN
  IF p_hhmm IS NULL OR p_hhmm = '' THEN RETURN NULL; END IF;
  v_parts := string_to_array(p_hhmm, ':');
  IF array_length(v_parts, 1) <> 2 THEN RETURN NULL; END IF;
  v_h := NULLIF(v_parts[1], '')::INT;
  v_m := NULLIF(v_parts[2], '')::INT;
  IF v_h IS NULL OR v_m IS NULL THEN RETURN NULL; END IF;
  IF v_h NOT BETWEEN 0 AND 23 OR v_m NOT BETWEEN 0 AND 59 THEN RETURN NULL; END IF;
  RETURN v_h * 60 + v_m;
EXCEPTION WHEN OTHERS THEN
  RETURN NULL;
END;
$$;


-- ---------------------------------------------------------------------------
-- 4. Admin RPCs
-- ---------------------------------------------------------------------------
-- Helper: send notify-partner push (fire-and-forget) via pg_net.
-- ---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION public._notify_partner_status_change(
  p_restaurant_id TEXT,
  p_title         TEXT,
  p_body          TEXT
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_token TEXT;
  v_url   TEXT;
  v_jwt   TEXT;
BEGIN
  SELECT fcm_token INTO v_token FROM public.restaurants WHERE id = p_restaurant_id;
  IF v_token IS NULL OR v_token = '' THEN
    RETURN;  -- no token, skip silently
  END IF;

  -- Use the same anon JWT as the dispatch trigger (will move to vault in T1 cutover).
  v_url := 'https://ojykpzwqrtusfeakzrna.supabase.co/functions/v1/notify-partner';
  v_jwt := 'eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6Im9qeWtwendxcnR1c2ZlYWt6cm5hIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NzMwMDA3MjgsImV4cCI6MjA4ODU3NjcyOH0.-yrhHFZV4bfjBagI5W-c1AvmP8Xkzs1kf2xuxPwdBh4';

  PERFORM extensions.net.http_post(
    url     := v_url,
    headers := jsonb_build_object('Content-Type', 'application/json', 'Authorization', 'Bearer ' || v_jwt),
    body    := jsonb_build_object(
      'restaurant_id', p_restaurant_id,
      'title', p_title,
      'body',  p_body,
      'kind',  'status_change'
    )
  );
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE '_notify_partner_status_change: % (skipped)', SQLERRM;
END;
$$;

REVOKE ALL ON FUNCTION public._notify_partner_status_change(TEXT, TEXT, TEXT) FROM public, anon, authenticated;


-- 4.1 admin_set_partner_override
CREATE OR REPLACE FUNCTION public.admin_set_partner_override(
  p_restaurant_id TEXT,
  p_state         TEXT,         -- 'open' | 'closed'
  p_reason        TEXT,
  p_ends_at       TIMESTAMPTZ DEFAULT NULL
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin       RECORD;
  v_restaurant  RECORD;
  v_override_id UUID;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_state NOT IN ('open', 'closed') THEN
    RAISE EXCEPTION 'admin_set_partner_override: invalid state "%", must be open|closed', p_state;
  END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) < 3 THEN
    RAISE EXCEPTION 'admin_set_partner_override: reason required (>= 3 chars)';
  END IF;
  IF p_ends_at IS NOT NULL AND p_ends_at <= NOW() THEN
    RAISE EXCEPTION 'admin_set_partner_override: ends_at must be in the future';
  END IF;

  SELECT id, name INTO v_restaurant FROM public.restaurants WHERE id = p_restaurant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_set_partner_override: restaurant % not found', p_restaurant_id;
  END IF;

  -- Close any prior active override (set ends_at = NOW()).
  UPDATE public.partner_status_override
     SET ends_at = NOW()
   WHERE restaurant_id = p_restaurant_id
     AND (ends_at IS NULL OR ends_at > NOW());

  INSERT INTO public.partner_status_override (
    restaurant_id, forced_state, reason, ends_at, set_by_admin
  ) VALUES (
    p_restaurant_id, p_state, trim(p_reason), p_ends_at, v_admin.admin_id
  ) RETURNING id INTO v_override_id;

  -- Audit log
  INSERT INTO public.admin_audit_log (
    admin_id, admin_email, action, entity_type, entity_id_text, details
  ) VALUES (
    v_admin.admin_id, v_admin.admin_email, 'partner_status_override_set', 'restaurant',
    p_restaurant_id,
    jsonb_build_object(
      'forced_state', p_state, 'reason', trim(p_reason),
      'ends_at', p_ends_at, 'override_id', v_override_id
    )
  );

  -- Push partner (best-effort)
  PERFORM public._notify_partner_status_change(
    p_restaurant_id,
    CASE p_state WHEN 'closed' THEN 'Loja fechada por administração'
                 ELSE 'Loja reaberta por administração' END,
    CASE p_state WHEN 'closed' THEN 'A loja foi fechada por administração: ' || trim(p_reason)
                 ELSE 'A loja foi reaberta por administração: ' || trim(p_reason) END
  );

  RETURN jsonb_build_object(
    'success', true, 'override_id', v_override_id,
    'restaurant_id', p_restaurant_id, 'state', p_state, 'ends_at', p_ends_at
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_partner_override(TEXT, TEXT, TEXT, TIMESTAMPTZ) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_partner_override(TEXT, TEXT, TEXT, TIMESTAMPTZ) TO authenticated;


-- 4.2 admin_clear_partner_override
CREATE OR REPLACE FUNCTION public.admin_clear_partner_override(
  p_restaurant_id TEXT
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin     RECORD;
  v_cleared   INT;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  WITH cleared AS (
    UPDATE public.partner_status_override
       SET ends_at = NOW()
     WHERE restaurant_id = p_restaurant_id
       AND (ends_at IS NULL OR ends_at > NOW())
    RETURNING id
  )
  SELECT count(*) INTO v_cleared FROM cleared;

  INSERT INTO public.admin_audit_log (
    admin_id, admin_email, action, entity_type, entity_id_text, details
  ) VALUES (
    v_admin.admin_id, v_admin.admin_email, 'partner_status_override_cleared', 'restaurant',
    p_restaurant_id,
    jsonb_build_object('cleared_count', v_cleared)
  );

  IF v_cleared > 0 THEN
    PERFORM public._notify_partner_status_change(
      p_restaurant_id,
      'Estado da loja restaurado',
      'O override do administrador foi removido. Voltámos ao horário regular.'
    );
  END IF;

  RETURN jsonb_build_object('success', true, 'cleared_count', v_cleared);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_clear_partner_override(TEXT) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_clear_partner_override(TEXT) TO authenticated;


-- 4.3 admin_update_partner_hours
-- Replaces the entire business_hours JSONB. Validates structure server-side.
CREATE OR REPLACE FUNCTION public.admin_update_partner_hours(
  p_restaurant_id TEXT,
  p_hours         JSONB
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin RECORD;
  v_old   JSONB;
  v_day   TEXT;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_hours IS NULL OR jsonb_typeof(p_hours) != 'object' THEN
    RAISE EXCEPTION 'admin_update_partner_hours: hours must be a JSONB object';
  END IF;

  -- Validate days
  FOREACH v_day IN ARRAY ARRAY['mon','tue','wed','thu','fri','sat','sun'] LOOP
    IF p_hours ? v_day THEN
      IF jsonb_typeof(p_hours->v_day) != 'object' THEN
        RAISE EXCEPTION 'admin_update_partner_hours: %.% must be object', p_restaurant_id, v_day;
      END IF;
    END IF;
  END LOOP;

  SELECT business_hours INTO v_old FROM public.restaurants WHERE id = p_restaurant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_update_partner_hours: restaurant % not found', p_restaurant_id;
  END IF;

  UPDATE public.restaurants SET business_hours = p_hours WHERE id = p_restaurant_id;

  INSERT INTO public.admin_audit_log (
    admin_id, admin_email, action, entity_type, entity_id_text, details
  ) VALUES (
    v_admin.admin_id, v_admin.admin_email, 'partner_hours_updated', 'restaurant',
    p_restaurant_id,
    jsonb_build_object('old_hours', v_old, 'new_hours', p_hours)
  );

  -- Push partner
  PERFORM public._notify_partner_status_change(
    p_restaurant_id,
    'Horário actualizado',
    'O administrador actualizou o horário da loja.'
  );

  RETURN jsonb_build_object('success', true, 'restaurant_id', p_restaurant_id);
END;
$$;

REVOKE ALL ON FUNCTION public.admin_update_partner_hours(TEXT, JSONB) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_update_partner_hours(TEXT, JSONB) TO authenticated;


-- 4.4 admin_set_partner_special_date
-- Adds or replaces an entry in business_hours.special_dates for a single date.
CREATE OR REPLACE FUNCTION public.admin_set_partner_special_date(
  p_restaurant_id TEXT,
  p_date          DATE,
  p_day_hours     JSONB    -- {open, close, closed, reason}
)
RETURNS JSONB
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_admin    RECORD;
  v_hours    JSONB;
  v_special  JSONB;
  v_filtered JSONB;
  v_new_entry JSONB;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();

  IF p_day_hours IS NULL OR jsonb_typeof(p_day_hours) != 'object' THEN
    RAISE EXCEPTION 'admin_set_partner_special_date: day_hours must be JSONB object';
  END IF;

  SELECT business_hours INTO v_hours FROM public.restaurants WHERE id = p_restaurant_id;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'admin_set_partner_special_date: restaurant % not found', p_restaurant_id;
  END IF;
  IF v_hours IS NULL THEN v_hours := '{}'::jsonb; END IF;

  v_special := COALESCE(v_hours->'special_dates', '[]'::jsonb);

  -- Filter out existing entry for the same date.
  SELECT COALESCE(jsonb_agg(elem), '[]'::jsonb) INTO v_filtered
    FROM jsonb_array_elements(v_special) elem
   WHERE (elem->>'date') IS NULL OR (elem->>'date')::DATE != p_date;

  -- New entry = day_hours + date stamp
  v_new_entry := p_day_hours || jsonb_build_object('date', p_date::text);
  v_special := v_filtered || jsonb_build_array(v_new_entry);

  v_hours := v_hours || jsonb_build_object('special_dates', v_special);

  UPDATE public.restaurants SET business_hours = v_hours WHERE id = p_restaurant_id;

  INSERT INTO public.admin_audit_log (
    admin_id, admin_email, action, entity_type, entity_id_text, details
  ) VALUES (
    v_admin.admin_id, v_admin.admin_email, 'partner_special_date_set', 'restaurant',
    p_restaurant_id,
    jsonb_build_object('date', p_date, 'day_hours', p_day_hours)
  );

  RETURN jsonb_build_object(
    'success', true, 'restaurant_id', p_restaurant_id, 'date', p_date,
    'special_dates_count', jsonb_array_length(v_special)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_partner_special_date(TEXT, DATE, JSONB) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_set_partner_special_date(TEXT, DATE, JSONB) TO authenticated;


COMMIT;

-- ============================================================================
-- POST-APPLY VERIFICATION
-- ============================================================================
-- 1. Function works for an open partner:
--      SELECT public.is_partner_open('<restaurant-id>');
--    Returns {is_open: true, closes_in_minutes: 240, …} during business hours.
-- 2. Override workflow:
--      SELECT public.admin_set_partner_override('<id>', 'closed', 'manutenção', NULL);
--      SELECT public.is_partner_open('<id>');  -- expects override_active: true
--      SELECT public.admin_clear_partner_override('<id>');
-- 3. Special date workflow:
--      SELECT public.admin_set_partner_special_date('<id>', '2026-12-25',
--             '{"closed": true, "reason": "Natal"}'::jsonb);
-- 4. Audit log written:
--      SELECT action, entity_id_text, details FROM admin_audit_log
--       WHERE entity_type = 'restaurant' ORDER BY created_at DESC LIMIT 5;
-- ============================================================================
