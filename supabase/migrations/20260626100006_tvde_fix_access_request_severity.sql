-- ============================================================================
-- BORA MOTORISTA (TVDE) — FASE 6 · FIX: severidade do alerta de pedido de acesso
-- ============================================================================
-- BUG (apanhado no smoke ROLLBACK da Fase 6): tvde_request_access() chamava
-- notify_admin_event(..., 'warning', ...), mas admin_notifications tem
-- CHECK severity IN ('low','medium','high','critical'). 'warning' violava o
-- constraint e quebrava TODO o fluxo de pedido de acesso à categoria escondida.
-- Correcção: 'warning' -> 'medium' (novo pedido = severidade média). Aditivo,
-- só re-cria a função. NÃO toca zonas protegidas.
-- ============================================================================

BEGIN;

CREATE OR REPLACE FUNCTION public.tvde_request_access()
RETURNS public.tvde_access_requests
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public AS $$
DECLARE
  v_uid    UUID := auth.uid();
  v_access BOOLEAN;
  v_name   TEXT;
  v_row    public.tvde_access_requests;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'not_authenticated'; END IF;
  SELECT tvde_access, name INTO v_access, v_name FROM public.users WHERE id = v_uid;
  IF v_access IS TRUE THEN RAISE EXCEPTION 'already_has_access'; END IF;

  SELECT * INTO v_row FROM public.tvde_access_requests
    WHERE client_id = v_uid AND status = 'pendente' LIMIT 1;
  IF FOUND THEN RETURN v_row; END IF;

  INSERT INTO public.tvde_access_requests (client_id)
    VALUES (v_uid) RETURNING * INTO v_row;

  PERFORM public.notify_admin_event(
    'tvde_access_request', 'medium',
    'Novo pedido de acesso Bora Motorista: ' || COALESCE(v_name, 'cliente'),
    'tvde_access_request', v_row.id::text,
    jsonb_build_object('client_id', v_uid, 'client_name', v_name),
    '/admin/tvde/access-requests'
  );
  RETURN v_row;
END; $$;
REVOKE ALL ON FUNCTION public.tvde_request_access() FROM public, anon;
GRANT EXECUTE ON FUNCTION public.tvde_request_access() TO authenticated;

COMMIT;
