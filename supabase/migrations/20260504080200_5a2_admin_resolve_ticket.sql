-- Sessão 5A-2 B16 — admin_resolve_ticket
-- RPC para admin marcar ticket resolvido com audit inline em admin_notes.
-- Audit: timestamp + auth.uid() + nota opcional.

CREATE OR REPLACE FUNCTION public.admin_resolve_ticket(
  p_ticket_id uuid,
  p_notes text DEFAULT NULL
) RETURNS void
LANGUAGE plpgsql SECURITY DEFINER SET search_path = public
AS $fn$
BEGIN
  IF NOT public.is_admin() THEN
    RAISE EXCEPTION 'NOT_ADMIN';
  END IF;
  UPDATE public.support_tickets
  SET
    status = 'resolved',
    resolved_at = now(),
    updated_at = now(),
    admin_notes = COALESCE(admin_notes, '') ||
                  E'\n[' || now()::text || '] resolved by ' ||
                  auth.uid()::text ||
                  CASE WHEN p_notes IS NULL OR length(trim(p_notes)) = 0
                       THEN ''
                       ELSE ': ' || p_notes
                  END
  WHERE id = p_ticket_id;
END$fn$;

REVOKE ALL ON FUNCTION public.admin_resolve_ticket(uuid, text) FROM public, anon;
GRANT EXECUTE ON FUNCTION public.admin_resolve_ticket(uuid, text) TO authenticated;
