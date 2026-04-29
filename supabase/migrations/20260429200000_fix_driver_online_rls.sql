-- ============================================================================
-- BORA — BUG 2 fix: drivers RLS bloqueia is_online=true se não aprovado
-- ============================================================================
-- BUG: drivers_update_own policy só verificava `user_id = auth.uid()`. Drivers
--      com approval_status='pending' (ou banidos/eliminados) podiam fazer
--      UPDATE drivers SET is_online=true via PostgREST, ficando "online"
--      no dispatch sem terem sido aprovados pelo admin.
--
-- FIX: WITH CHECK estendido — só permite is_online=true se driver é approved,
--      não banido (is_banned IS false ou NULL), não eliminado (deleted_at NULL).
--      is_online=false continua sempre permitido (driver pode ir offline).
--
-- Não-impacto:
--   - SECURITY DEFINER admin RPCs continuam a poder por is_online=false
--     (ban/delete/force-logout) — bypassam RLS por desenho.
--   - Flutter driver app: chamada `update is_online=false` continua livre.
--   - Approved drivers operam normalmente.
--
-- Investigação: .claude/.ai/reports/2026-04-29-pos-teste-bugs-investigacao.md (BUG 2)
-- ============================================================================

DROP POLICY IF EXISTS drivers_update_own ON public.drivers;

CREATE POLICY drivers_update_own ON public.drivers
FOR UPDATE
TO authenticated
USING (user_id = auth.uid())
WITH CHECK (
  user_id = auth.uid()
  AND (
    -- Driver pode sempre ir offline.
    is_online = false
    OR (
      -- Para ir online: tem que estar approved + não banido + não eliminado.
      approval_status = 'approved'
      AND (is_banned = false OR is_banned IS NULL)
      AND deleted_at IS NULL
    )
  )
);

COMMENT ON POLICY drivers_update_own ON public.drivers IS
  'Driver pode actualizar a própria row. WITH CHECK adicional bloqueia is_online=true se approval_status<>approved OU is_banned OU deleted_at. is_online=false sempre permitido. (FASE 5+ BUG 2 fix)';
