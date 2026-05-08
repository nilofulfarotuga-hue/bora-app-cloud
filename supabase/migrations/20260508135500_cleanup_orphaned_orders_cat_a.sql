-- Cleanup orphaned orders Cat A (9 cash rejected)
-- Data: 2026-05-08 / Sessao 7-alpha-ORPHANED-CLEANUP
--
-- Problema: 9 orders com status=rejected + payment_method=cash
-- + payment_status=pending. Cash + rejected = nunca houve cobranca,
-- payment_status=pending estava incoerente.
--
-- Solucao: payment_status=cancelled_no_charge (alinha com
-- semantica usada em client-cancel-order para cash sem PI).
--
-- Risco: zero (apenas corrige estado incoerente, sem efeitos
-- runtime - orders ja estavam terminadas com status=rejected).

UPDATE public.orders
SET payment_status = 'cancelled_no_charge'
WHERE id IN (
  '79ca3c7a-c3bc-4898-90f1-022c06add0e5',
  '93b7bf00-d7cd-450a-9130-21e8251c2d27',
  'be175307-3584-43dc-8f2c-0a677fe17c44',
  '3ce12489-76b9-41f0-a4e7-6ba8c119f8bf',
  '22d13fb5-c5af-4aa4-91f3-50723f1ee09e',
  'b0a2af78-3e49-48fd-8a4d-9e9b3f40c6c1',
  '5c470d30-ede4-414e-bbad-428c8f6da438',
  'de02d96c-7502-4731-a08e-cd1a48c57ff0',
  'a550efe3-009e-4b0f-8309-1e221305b30f'
)
  AND status = 'rejected'
  AND payment_method = 'cash'
  AND payment_status = 'pending';
