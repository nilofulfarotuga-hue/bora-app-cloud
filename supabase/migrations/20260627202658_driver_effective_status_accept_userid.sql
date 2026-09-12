-- ============================================================================
-- driver_effective_status — aceitar id OU user_id (fix gate id<>user_id)
-- ============================================================================
-- JÁ APLICADA EM PROD via MCP (Claude.ai) — version 20260627202658. Este ficheiro
-- sincroniza o repo com a prod (NÃO re-aplicar).
--
-- CONTEXTO: o motorista TVDE tem id <> user_id (id=fe91c821, user_id=4f61dd31).
-- O gate "Conta em análise" não saía mesmo com approval_status='approved' porque
-- a função procurava WHERE id = p_driver_id, e o app passa auth.uid() (= user_id)
-- → não achava linha → NULL → "em análise". Passa a aceitar id OU user_id.
-- ============================================================================

CREATE OR REPLACE FUNCTION public.driver_effective_status(p_driver_id uuid)
 RETURNS text LANGUAGE sql STABLE SECURITY DEFINER SET search_path TO 'public'
AS $function$
  SELECT CASE
    WHEN deleted_at IS NOT NULL THEN 'deleted'
    WHEN is_banned AND (banned_until IS NULL OR banned_until > now()) THEN
      CASE WHEN banned_until IS NULL THEN 'banned' ELSE 'suspended' END
    WHEN approval_status = 'pending'  THEN 'pending'
    WHEN approval_status = 'rejected' THEN 'rejected'
    ELSE 'active'
  END
  FROM public.drivers
  WHERE id = p_driver_id OR user_id = p_driver_id
  LIMIT 1;
$function$;
