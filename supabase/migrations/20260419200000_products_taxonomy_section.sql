-- ============================================================================
-- Migration: 20260419200000_products_taxonomy_section.sql
-- Campanha 3/5 pós-testes — Taxonomy Mapper
--
-- Adiciona 3 colunas aditivas a public.products para classificar ~43K produtos
-- em 18 secções canónicas Bora. NÃO toca em colunas existentes.
--
-- Colunas preservadas (NÃO mexer):
--   - products.name
--   - products.category
--   - products.category_root
--   - products.search_normalized
--
-- Rollback simples: DROP COLUMN taxonomy_section, taxonomy_confidence, needs_review.
-- ============================================================================

BEGIN;

-- 1. Adicionar colunas (idempotente via IF NOT EXISTS)
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS taxonomy_section TEXT,
  ADD COLUMN IF NOT EXISTS taxonomy_confidence NUMERIC(3, 2) DEFAULT 0.00,
  ADD COLUMN IF NOT EXISTS needs_review BOOLEAN DEFAULT false;

-- 2. Check constraint opcional — restringir taxonomy_section às 18 canónicas.
--    NÃO aplicado agora para permitir UPDATEs progressivos sem rejeição.
--    Pode ser adicionado após população completa (ver comentário no fim).

-- 3. Índice para queries de filtro por secção
CREATE INDEX IF NOT EXISTS idx_products_taxonomy_section
  ON public.products(taxonomy_section);

-- 4. Índice parcial para revisão manual (só linhas needs_review = true)
CREATE INDEX IF NOT EXISTS idx_products_needs_review
  ON public.products(taxonomy_confidence)
  WHERE needs_review = true;

-- 5. Comentário de documentação
COMMENT ON COLUMN public.products.taxonomy_section IS
  'Uma das 18 secções canónicas Bora. Ver .claude/skills/taxonomy-mapper/references/bora_taxonomy.md';
COMMENT ON COLUMN public.products.taxonomy_confidence IS
  'Score 0.00-1.00. >0.85 = auto-aceite; 0.50-0.85 = aceite com review; <0.50 = Outros+review.';
COMMENT ON COLUMN public.products.needs_review IS
  'True quando confidence<0.85 ou fallback LLM ambíguo. Revisão manual sugerida.';

COMMIT;

-- ============================================================================
-- Pós-população (aplicar só após classify.py ter corrido em todos os produtos):
--
-- ALTER TABLE public.products
--   ADD CONSTRAINT chk_taxonomy_section_canonical
--   CHECK (taxonomy_section IS NULL OR taxonomy_section IN (
--     'Padaria & Pastelaria',
--     'Frutas & Legumes',
--     'Talho',
--     'Peixaria',
--     'Laticínios & Ovos',
--     'Congelados',
--     'Mercearia',
--     'Bebidas',
--     'Bebé',
--     'Animais',
--     'Higiene Pessoal',
--     'Higiene do Lar',
--     'Saúde & Bem-Estar',
--     'Bio & Saudável',
--     'Fitness & Proteínas',
--     'Pronto a Comer',
--     'Festa & Ocasiões',
--     'Outros'
--   ));
-- ============================================================================
