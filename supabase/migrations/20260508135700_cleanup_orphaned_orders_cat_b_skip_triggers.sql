-- Cleanup orphaned orders Cat B (3 stuck driverAccepted >19 dias)
-- Data: 2026-05-08 / Sessao 7-alpha-ORPHANED-CLEANUP
--
-- Problema: 3 orders stuck em status=driverAccepted ha 19-21
-- dias. user_id (f9ad894e) ja nao existe em users - daqui o
-- "orphan". Cancelamento normal falha porque trigger
-- _notify_on_order_cancel tenta INSERT em in_app_notifications
-- com FK para users (que falha).
--
-- Solucao: SET LOCAL session_replication_role='replica' nesta
-- transaction para skip triggers (standard PostgreSQL pattern
-- para manutencao). Apenas afecta esta transaction, sem
-- side-effects globais.
--
-- Risco: baixo. Drivers ja nao estao a aguardar (>19 dias),
-- users nao existem para receber notificacao. Fiscal trail
-- preservada (driver_transactions intactas, ledger nao tocado).

SET LOCAL session_replication_role = 'replica';

UPDATE public.orders
SET
  status = 'cancelled',
  cancel_reason = 'system_orphaned_legacy_2026: driverAccepted >19 dias sem progressao + user_id ja nao existe (cleanup 2026-05-08)',
  cancelled_at = NOW(),
  cancellation_initiator = 'system'
WHERE id IN (
  '94d02b17-2a99-47a3-aba4-822764286e3f',
  'cd0193ab-b7bd-4896-b530-5871ff3c1be8',
  'cc706061-bf49-4da8-83b4-5af5ffb68b33'
)
  AND status = 'driverAccepted';
