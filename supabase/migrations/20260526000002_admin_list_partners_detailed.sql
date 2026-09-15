-- Sessão 2026-05-26 — Admin list partners with detailed approval info
-- RPC para admin panel listar parceiros com status de aprovação, documentos,
-- e dados de review. Inclui owner_name extraído de metadata auth.users.
-- Filtrável por approval_status (pending/approved/rejected).

DROP FUNCTION IF EXISTS public.admin_list_partners_detailed(text, integer, integer);

CREATE OR REPLACE FUNCTION public.admin_list_partners_detailed(
  p_status text DEFAULT NULL::text,
  p_limit integer DEFAULT 50,
  p_offset integer DEFAULT 0
)
RETURNS TABLE(
  id text,
  name text,
  email text,
  phone text,
  nif text,
  iban text,
  owner_doc_url text,
  activity_doc_url text,
  approval_status text,
  rejection_reason text,
  submitted_at timestamp with time zone,
  reviewed_at timestamp with time zone,
  approved_at timestamp with time zone,
  owner_name text,
  created_at timestamp with time zone
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path TO 'public', 'auth'
AS $function$
DECLARE
  v_admin RECORD;
BEGIN
  SELECT admin_id, admin_email INTO v_admin FROM public._admin_op_guard();
  IF p_limit < 1 OR p_limit > 500 THEN RAISE EXCEPTION 'limit 1..500'; END IF;

  RETURN QUERY
  SELECT
    r.id,
    r.name,
    r.email,
    r.phone,
    r.nif,
    r.iban,
    r.owner_doc_url,
    r.activity_doc_url,
    r.approval_status,
    r.rejection_reason,
    r.submitted_at,
    r.reviewed_at,
    r.approved_at,
    COALESCE(au.raw_user_meta_data->>'bora_name', au.email)::TEXT AS owner_name,
    r.created_at
  FROM public.restaurants r
  LEFT JOIN auth.users au ON au.email = r.email
  WHERE r.is_partner = true
    AND (p_status IS NULL OR r.approval_status = p_status)
  ORDER BY r.submitted_at DESC
  LIMIT p_limit OFFSET p_offset;
END;
$function$;

COMMENT ON FUNCTION public.admin_list_partners_detailed(text, integer, integer) IS
  'Lista parceiros com detalhes de aprovação. Filtrável por status (pending/approved/rejected).';
