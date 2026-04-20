-- ============================================================================
-- apply_migration.sql — TEMPLATE
--
-- Este ficheiro é um template para UPDATEs transaccionais em batch.
-- É gerado dinamicamente por classify.py (modo --dry-run) ou aplicado via
-- supabase MCP apply_migration. NÃO executar em produção sem revisão.
--
-- Estrutura:
--   BEGIN;
--     UPDATE public.products SET taxonomy_section=..., taxonomy_confidence=..., needs_review=... WHERE id='...';
--     UPDATE public.products SET taxonomy_section=..., taxonomy_confidence=..., needs_review=... WHERE id='...';
--     ...
--   COMMIT;
--
-- Cada batch deve ter no máximo 1.000 UPDATEs para manter transacções rápidas.
-- ============================================================================

-- Pre-condições (validar antes de correr):
--   1. Colunas taxonomy_section, taxonomy_confidence, needs_review existem
--      (ver migration 20260419200000_products_taxonomy_section.sql)
--   2. Índice idx_products_taxonomy_section existe
--   3. Utilizador tem permissão UPDATE na tabela public.products

-- Validação rápida:
-- SELECT column_name FROM information_schema.columns
--   WHERE table_name = 'products' AND column_name IN ('taxonomy_section', 'taxonomy_confidence', 'needs_review');

-- ============================================================================
-- EXEMPLO (substituído pelo classify.py no momento do run)
-- ============================================================================

BEGIN;

-- UPDATE public.products
--   SET taxonomy_section = 'Frutas & Legumes',
--       taxonomy_confidence = 0.95,
--       needs_review = false
--   WHERE id = '00000000-0000-0000-0000-000000000001';

-- UPDATE public.products
--   SET taxonomy_section = 'Congelados',
--       taxonomy_confidence = 0.90,
--       needs_review = false
--   WHERE id = '00000000-0000-0000-0000-000000000002';

-- ... (gerado em batch pelo classify.py)

COMMIT;

-- ============================================================================
-- Rollback manual (se necessário)
-- ============================================================================
-- UPDATE public.products
--   SET taxonomy_section = NULL,
--       taxonomy_confidence = 0.00,
--       needs_review = false
--   WHERE id IN ('<list-of-ids>');

-- ============================================================================
-- Queries de validação pós-batch
-- ============================================================================

-- Distribuição por secção:
-- SELECT taxonomy_section, COUNT(*) AS n
-- FROM public.products
-- GROUP BY taxonomy_section
-- ORDER BY n DESC;

-- Circuit breaker: % de "Outros"
-- SELECT
--   COUNT(*) FILTER (WHERE taxonomy_section = 'Outros')::FLOAT
--     / COUNT(*) AS outros_pct
-- FROM public.products
-- WHERE taxonomy_section IS NOT NULL;

-- TOP 20 menos confiantes:
-- SELECT id, name, category_root, taxonomy_section, taxonomy_confidence
-- FROM public.products
-- WHERE needs_review = true
-- ORDER BY taxonomy_confidence ASC
-- LIMIT 20;
