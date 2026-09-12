-- Sessão 6 B1 — Marcar pedidos teste pré-launch
-- Data: 2026-05-05
-- 4 pedidos cancelados 30/04+01/05 (€253.08 stripe charges).
-- Coluna BOOLEAN default false para futura filtragem em dashboards admin.

ALTER TABLE public.orders
  ADD COLUMN IF NOT EXISTS is_test_order BOOLEAN NOT NULL DEFAULT false;

CREATE INDEX IF NOT EXISTS idx_orders_is_test_order
  ON public.orders(is_test_order) WHERE is_test_order = true;

COMMENT ON COLUMN public.orders.is_test_order IS
  'Marca pedidos teste pré-launch. Sessão 6, 2026-05-05. '
  '4 pedidos iniciais €253.08 stripe charges (testes Danilo).';

DO $$
DECLARE v_marked int;
BEGIN
  WITH updated AS (
    UPDATE public.orders SET is_test_order = true
    WHERE id IN (
      'b90966bf-31ca-4707-89c2-0cef4f9cc33a',
      '1c561ae0-34a9-4048-a2fc-88d2a168d5d5',
      '88e36c67-d2cf-47e3-a930-6a58166a6dff',
      '31a5ccd3-4596-4967-af96-181fbacca570'
    )
    RETURNING id
  )
  SELECT COUNT(*) INTO v_marked FROM updated;

  IF v_marked != 4 THEN
    RAISE EXCEPTION 'Sessão 6 B1: expected 4 marked, got %. Aborting.', v_marked;
  END IF;
END$$;
