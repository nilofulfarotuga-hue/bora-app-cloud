-- B6 (2026-06-12) — Alergénios nos produtos (Regulamento UE 1169/2011).
-- Os 14 alergénios de declaração obrigatória, guardados como slugs:
-- gluten, crustaceos, ovos, peixe, amendoins, soja, leite,
-- frutos_casca_rija, aipo, mostarda, sesamo, sulfitos, tremocos, moluscos.
-- NULL/[] = não preenchido → app mostra disclaimer "consulte o
-- estabelecimento". NÃO bloqueia pedidos (informativo).
-- Índice GIN para pesquisa futura por alergénio.

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS allergens TEXT[];

CREATE INDEX IF NOT EXISTS idx_products_allergens
  ON public.products USING GIN (allergens);
