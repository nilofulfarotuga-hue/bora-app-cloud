-- BUG-7E-B-006: criar setting platform para Stripe cancel fee before dispatch
-- Decisão Danilo 2026-05-08: manter €1.50 (alinhar docs com código actual)
-- Edge Function stripe-webhook v17 continua hardcoded; setting fica disponível
-- para futura refactoração ler dela. Não altera comportamento actual.

INSERT INTO public.platform_settings (key, value, description, updated_at)
VALUES (
  'cancel_fee_before_dispatch_cents',
  '150'::jsonb,
  'Taxa de cancelamento aplicada antes do dispatch ser invocado (em cents). Decisão 2026-05-08: €1.50. Stripe webhook v17 ainda hardcoded — refactorar em sessão futura para ler desta setting.',
  NOW()
)
ON CONFLICT (key) DO UPDATE
SET value = EXCLUDED.value,
    description = EXCLUDED.description,
    updated_at = NOW();
