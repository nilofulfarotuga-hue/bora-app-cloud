-- MEGA-FIX 2026-07-18 RODADA 2 Parte 5 — retalho: farmácia marca produtos que exigem receita.
-- Só medicamentos OTC (não sujeitos a receita) devem ser vendidos; os que exigem receita ficam
-- marcados para badge no cliente. Coluna nova, default false (retrocompatível).

ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS requires_prescription boolean NOT NULL DEFAULT false;
