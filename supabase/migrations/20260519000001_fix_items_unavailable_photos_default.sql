-- BUG-SCHEMA-001 (2026-05-19) — corrigir default de items_unavailable_photos
-- de '{}' (JSONB object) para '[]' (JSONB array).
-- A coluna foi adicionada em 20260502050000 com default '{}' por engano.
-- Pedidos existentes mantêm o valor actual (não retroactivo).

ALTER TABLE public.orders
  ALTER COLUMN items_unavailable_photos SET DEFAULT '[]'::jsonb;

-- Corrigir pedidos existentes que ficaram com '{}' (object vazio)
-- para '[]' (array vazio) — inofensivo para pedidos com fotos reais.
UPDATE public.orders
  SET items_unavailable_photos = '[]'::jsonb
  WHERE items_unavailable_photos = '{}'::jsonb;
