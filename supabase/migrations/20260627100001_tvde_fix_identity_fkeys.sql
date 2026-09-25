-- ============================================================================
-- BORA MOTORISTA (TVDE) — FIX CRÍTICO (parte 2) · re-apontar FKs para user_id
-- ============================================================================
-- Complementa 20260627100000_tvde_fix_identity_userid.sql.
--
-- DESCOBERTA (não prevista no diagnóstico, confirmada via MCP):
--   tvde_rides.driver_id e tvde_driver_balances.driver_id tinham FK → drivers(id),
--   mas todo o dispatch/lifecycle/saldo TVDE usa auth.uid() = drivers.user_id.
--   Como id <> user_id nos motoristas reais (3 de 4 em prod), gravar
--   driver_id = user_id violaria a FK → o accept NUNCA teria funcionado.
--
-- CORREÇÃO: re-apontar as 2 FKs TVDE para drivers(user_id) — coluna que já é
--   UNIQUE (drivers_user_id_key). Aditivo: 0 linhas referenciam driver_id
--   (0 rides com motorista, 0 balances), logo não há migração de dados.
--   ON DELETE preservado (rides: SET NULL; balances: CASCADE).
--
-- ESCOPO: NÃO toca driver_token_transactions nem driver_weekly_settlements
--   (FKs de DELIVERY → drivers(id); zona protegida, identidade própria do delivery).
-- ============================================================================

BEGIN;

ALTER TABLE public.tvde_rides DROP CONSTRAINT tvde_rides_driver_id_fkey;
ALTER TABLE public.tvde_rides
  ADD CONSTRAINT tvde_rides_driver_id_fkey
  FOREIGN KEY (driver_id) REFERENCES public.drivers(user_id) ON DELETE SET NULL;

ALTER TABLE public.tvde_driver_balances DROP CONSTRAINT tvde_driver_balances_driver_id_fkey;
ALTER TABLE public.tvde_driver_balances
  ADD CONSTRAINT tvde_driver_balances_driver_id_fkey
  FOREIGN KEY (driver_id) REFERENCES public.drivers(user_id) ON DELETE CASCADE;

COMMIT;
