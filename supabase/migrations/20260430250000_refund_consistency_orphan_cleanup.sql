-- 20260430250000_refund_consistency_orphan_cleanup.sql
-- Fase 1 — bug fix sessão 2026-04-30:
--   • BUG-NEW-3: limpar fantasmas refund_amount sem refund_method
--   • CHECK constraint: (refund_amount IS NULL) OR (refund_method IS NOT NULL)
--   • BUG 1 órfãos: marcar 4 pedidos noite 30/04 com payment_status='cancelled_no_charge'
--
-- Idempotente: usa IF NOT EXISTS / IF EXISTS guards.
-- Não toca dispatch / driver_balances / ledger_entries.

BEGIN;

-- ── 1. Limpar fantasmas refund_amount sem refund_method ─────────────────
-- Estes pedidos têm refund_amount escrito mas refund nunca foi executado
-- (Edge Fn marcava refund_amount mesmo quando Stripe falhava).
-- Após este cleanup, a Edge Fn nova só escreve refund_amount em sucesso.
UPDATE public.orders
SET refund_amount = NULL
WHERE refund_amount IS NOT NULL
  AND refund_method IS NULL;

-- ── 2. Constraint de consistência refund_amount ↔ refund_method ─────────
ALTER TABLE public.orders
  DROP CONSTRAINT IF EXISTS refund_consistency;

ALTER TABLE public.orders
  ADD CONSTRAINT refund_consistency
  CHECK (
    (refund_amount IS NULL)
    OR (refund_method IS NOT NULL)
  ) NOT VALID;

-- VALIDATE separa para não bloquear a constraint addition se houver
-- algum caso edge ainda. Se VALIDATE falhar, o problema deve ser tratado
-- antes do próximo deploy.
ALTER TABLE public.orders
  VALIDATE CONSTRAINT refund_consistency;

-- ── 3. Marcar as 4 órfãs noite 30/04 ─────────────────────────────────────
-- IDs verificados via Supabase MCP query (2026-04-30):
--   1c561ae0-... mbway falhou
--   88e36c67-... card payment_abandoned
--   31a5ccd3-... card payment_abandoned
--   72c3d5c8-... card cancel manual com refund=wallet OK (este já paid → mantemos)
-- Marcamos só os 3 sem charge real. O quarto (72c3d5c8) tem refund_method='wallet'
-- e refund_status='completed' — é legítimo, NÃO tocar.
UPDATE public.orders
SET payment_status = 'cancelled_no_charge',
    cancel_reason = COALESCE(cancel_reason, 'orphan_payment_intent_failed'),
    -- Limpar refund_amount fantasma para os mbway/abandoned se ainda existir
    refund_amount = NULL
WHERE id IN (
    '1c561ae0-34a9-4048-a2fc-88d2a168d5d5',
    '88e36c67-d2cf-47e3-a930-6a58166a6dff',
    '31a5ccd3-4596-4967-af96-181fbacca570'
  )
  AND status = 'cancelled'
  AND payment_status = 'failed'
  AND refund_method IS NULL;

COMMIT;
