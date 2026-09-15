-- MEGA-FIX 2026-07-18 Parte 4 — admin deixa de ser cego para candidaturas de serviço (beleza).
--
-- Problema: candidatura de beleza vai para `service_providers`, mas as RPCs do admin só liam
-- `restaurants` → candidatura invisível, sem forma de aprovar/rejeitar, e o gatilho de
-- notificação de "novo parceiro pendente" (Gatilho 3, 2026-07-17) só existia para restaurants.
--
-- Correções:
--   1. admin_list_partners_detailed + list_partners_by_status → UNION restaurants + service_providers,
--      com coluna `source` ('restaurant' | 'service_provider'). (RETURNS TABLE muda → DROP+CREATE.)
--   2. approve_service_provider / reject_service_provider — gémeas das de restaurant, sem quebrar
--      approve_partner / reject_partner existentes (o Flutter escolhe pela `source`).
--   3. Gatilho AFTER INSERT/UPDATE OF approval_status em service_providers → notify_admin_urgent_push
--      (mesma plumbing dos 5 gatilhos de 2026-07-17: linha HIGH in-app + FCM best-effort).
-- Ver .claude/.ai/knowledge/wiki/licoes/licao-dual-owner-column.md (mesma família de bug: dado
-- que existe em duas tabelas e o leitor só olhava uma).

-- ─── 1a. admin_list_partners_detailed (UNION + source) ──────────────────────
DROP FUNCTION IF EXISTS public.admin_list_partners_detailed(text, integer, integer);
CREATE FUNCTION public.admin_list_partners_detailed(
  p_status text DEFAULT NULL::text, p_limit integer DEFAULT 50, p_offset integer DEFAULT 0)
 RETURNS TABLE(id text, name text, email text, phone text, nif text, iban text,
   owner_doc_url text, activity_doc_url text, approval_status text, rejection_reason text,
   submitted_at timestamp with time zone, reviewed_at timestamp with time zone,
   approved_at timestamp with time zone, owner_name text, created_at timestamp with time zone,
   source text)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_admin RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_limit < 1 OR p_limit > 500 THEN RAISE EXCEPTION 'limit 1..500'; END IF;

  RETURN QUERY
  SELECT * FROM (
    SELECT
      r.id, r.name, r.email, r.phone, r.nif, r.iban, r.owner_doc_url, r.activity_doc_url,
      r.approval_status, r.rejection_reason, r.submitted_at, r.reviewed_at, r.approved_at,
      COALESCE(au.raw_user_meta_data->>'bora_name', au.email)::TEXT AS owner_name,
      r.created_at, 'restaurant'::text AS source
    FROM public.restaurants r
    LEFT JOIN auth.users au ON au.email = r.email
    WHERE r.is_partner = true
      AND (p_status IS NULL OR r.approval_status = p_status)
    UNION ALL
    SELECT
      sp.id, sp.name, au2.email AS email, sp.phone, sp.nif, sp.iban,
      NULL::text AS owner_doc_url, NULL::text AS activity_doc_url,
      sp.approval_status, sp.rejection_reason, sp.created_at AS submitted_at,
      NULL::timestamptz AS reviewed_at, sp.approved_at,
      COALESCE(au2.raw_user_meta_data->>'bora_name', au2.email)::TEXT AS owner_name,
      sp.created_at, 'service_provider'::text AS source
    FROM public.service_providers sp
    LEFT JOIN auth.users au2 ON au2.id = sp.user_id
    WHERE (p_status IS NULL OR sp.approval_status = p_status)
  ) u
  ORDER BY u.submitted_at DESC NULLS LAST
  LIMIT p_limit OFFSET p_offset;
END;
$function$;

-- ─── 1b. list_partners_by_status (UNION + source, fallback do ecrã) ─────────
DROP FUNCTION IF EXISTS public.list_partners_by_status(text);
CREATE FUNCTION public.list_partners_by_status(p_status text DEFAULT NULL::text)
 RETURNS TABLE(id text, name text, email text, phone text, address text, category text,
   is_partner boolean, is_active_admin boolean, approval_status text,
   approved_at timestamp with time zone, approved_by uuid, rejection_reason text,
   created_at timestamp with time zone, source text)
 LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller       UUID := auth.uid();
  v_caller_email TEXT;
  v_is_admin     BOOLEAN := false;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501';
  END IF;
  SELECT au.email, COALESCE(au.raw_app_meta_data->>'role', '') = 'admin'
    INTO v_caller_email, v_is_admin
  FROM auth.users au WHERE au.id = v_caller;
  IF NOT v_is_admin AND v_caller_email NOT IN ('nilofulfarotuga@gmail.com','nilofulfaro@gmail.com') THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;

  RETURN QUERY
  SELECT * FROM (
    SELECT r.id, r.name, r.email, r.phone, r.address, r.category,
           r.is_partner, r.is_active_admin, r.approval_status, r.approved_at,
           r.approved_by, r.rejection_reason, r.created_at, 'restaurant'::text AS source
    FROM public.restaurants r
    WHERE p_status IS NULL OR r.approval_status = p_status
    UNION ALL
    SELECT sp.id, sp.name, au.email AS email, sp.phone, sp.address, sp.category,
           true AS is_partner, sp.is_active_admin, sp.approval_status, sp.approved_at,
           sp.approved_by, sp.rejection_reason, sp.created_at, 'service_provider'::text AS source
    FROM public.service_providers sp
    LEFT JOIN auth.users au ON au.id = sp.user_id
    WHERE p_status IS NULL OR sp.approval_status = p_status
  ) u
  ORDER BY u.created_at DESC;
END;
$function$;

-- ─── 2. approve_service_provider / reject_service_provider (gémeas) ─────────
CREATE OR REPLACE FUNCTION public.approve_service_provider(p_provider_id text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller UUID := auth.uid();
  v_caller_email TEXT;
  v_is_admin BOOLEAN := false;
  v_provider RECORD;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501'; END IF;
  SELECT email, COALESCE(raw_app_meta_data->>'role', '') = 'admin'
    INTO v_caller_email, v_is_admin FROM auth.users WHERE id = v_caller;
  IF NOT v_is_admin AND v_caller_email NOT IN ('nilofulfarotuga@gmail.com','nilofulfaro@gmail.com') THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_provider FROM public.service_providers WHERE id = p_provider_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'service_provider_not_found: %', p_provider_id USING ERRCODE = 'P0002'; END IF;

  UPDATE public.service_providers
  SET approval_status = 'approved', approved_at = now(), approved_by = v_caller, rejection_reason = NULL
  WHERE id = p_provider_id;

  BEGIN
    INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
    VALUES (v_caller, v_caller_email, 'service_provider_approve', 'service_provider', p_provider_id,
      jsonb_build_object('provider_name', v_provider.name, 'category', v_provider.category, 'previous_status', v_provider.approval_status));
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'approve_service_provider audit log failed: %', SQLERRM; END;

  RETURN jsonb_build_object('success', true, 'provider_id', p_provider_id,
    'approval_status', 'approved', 'approved_by', v_caller, 'approved_at', now());
END;
$function$;

CREATE OR REPLACE FUNCTION public.reject_service_provider(p_provider_id text, p_reason text)
 RETURNS jsonb LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public'
AS $function$
DECLARE
  v_caller UUID := auth.uid();
  v_caller_email TEXT;
  v_is_admin BOOLEAN := false;
  v_provider RECORD;
BEGIN
  IF v_caller IS NULL THEN RAISE EXCEPTION 'unauthenticated' USING ERRCODE = '42501'; END IF;
  IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
    RAISE EXCEPTION 'rejection_reason_required' USING ERRCODE = '23514';
  END IF;
  SELECT email, COALESCE(raw_app_meta_data->>'role', '') = 'admin'
    INTO v_caller_email, v_is_admin FROM auth.users WHERE id = v_caller;
  IF NOT v_is_admin AND v_caller_email NOT IN ('nilofulfarotuga@gmail.com','nilofulfaro@gmail.com') THEN
    RAISE EXCEPTION 'forbidden_admin_only' USING ERRCODE = '42501';
  END IF;

  SELECT * INTO v_provider FROM public.service_providers WHERE id = p_provider_id FOR UPDATE;
  IF NOT FOUND THEN RAISE EXCEPTION 'service_provider_not_found: %', p_provider_id USING ERRCODE = 'P0002'; END IF;

  UPDATE public.service_providers
  SET approval_status = 'rejected', approved_at = now(), approved_by = v_caller, rejection_reason = p_reason
  WHERE id = p_provider_id;

  BEGIN
    INSERT INTO public.admin_audit_log (admin_id, admin_email, action, entity_type, entity_id_text, details)
    VALUES (v_caller, v_caller_email, 'service_provider_reject', 'service_provider', p_provider_id,
      jsonb_build_object('provider_name', v_provider.name, 'category', v_provider.category, 'previous_status', v_provider.approval_status, 'rejection_reason', p_reason));
  EXCEPTION WHEN OTHERS THEN RAISE WARNING 'reject_service_provider audit log failed: %', SQLERRM; END;

  RETURN jsonb_build_object('success', true, 'provider_id', p_provider_id,
    'approval_status', 'rejected', 'rejection_reason', p_reason, 'approved_by', v_caller, 'approved_at', now());
END;
$function$;

-- ─── 3. Gatilho: nova candidatura de serviço pendente → notifica admins ─────
CREATE OR REPLACE FUNCTION public._trg_admin_notif_service_provider_app_fn()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO 'public' AS $$
BEGIN
  IF NEW.approval_status = 'pending'
     AND (TG_OP = 'INSERT' OR OLD.approval_status IS DISTINCT FROM 'pending') THEN
    PERFORM public.notify_admin_urgent_push(
      'service_provider_application_pending',
      'Nova candidatura de serviço a aguardar aprovação: ' || COALESCE(NULLIF(NEW.name,''), NEW.id::text)
        || ' (' || COALESCE(NEW.category, 'serviço') || ')',
      'service_provider', NEW.id::text,
      jsonb_build_object('provider_id', NEW.id, 'name', NEW.name, 'category', NEW.category),
      '/admin/partners/pending'
    );
  END IF;
  RETURN NEW;
END; $$;
DROP TRIGGER IF EXISTS trg_admin_notif_service_provider_app ON public.service_providers;
CREATE TRIGGER trg_admin_notif_service_provider_app
  AFTER INSERT OR UPDATE OF approval_status ON public.service_providers
  FOR EACH ROW EXECUTE FUNCTION public._trg_admin_notif_service_provider_app_fn();

GRANT EXECUTE ON FUNCTION public.approve_service_provider(text) TO authenticated;
GRANT EXECUTE ON FUNCTION public.reject_service_provider(text, text) TO authenticated;
