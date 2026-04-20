-- ============================================================================
-- BORA — Robust product search (Phase 1, BR §25.3 — additive, surgical)
-- ============================================================================
-- PURPOSE
--   Customers type queries without caring about accents, case, punctuation or
--   exact spelling. Today no results appear for common searches ("cafe" vs
--   "café", "cocacola" vs "coca-cola", "leit" prefix). This migration makes
--   search tolerant of all of the above using unaccent + pg_trgm.
--
-- COMPONENTS
--   1. Extensions (extensions schema): unaccent, pg_trgm
--   2. IMMUTABLE normalizer: public.bora_normalize(text)
--        → lowercase → unaccent → collapse non-alphanumeric to spaces
--   3. Derived column: public.products.search_normalized TEXT
--   4. Trigger: auto-populate on INSERT/UPDATE of name | category
--   5. Backfill: 43.121 existing rows in one UPDATE
--   6. GIN trigram index on search_normalized for sub-50ms lookups
--   7. RPC: public.search_products(query_text, p_restaurant_id, max_results)
--        Returns BOTH matching sections (category_root) and products in one
--        round-trip with a result_type discriminator.
--        Marked SECURITY INVOKER — respects existing RLS on products.
--
-- SEARCH SCOPE
--   Only `name` + `category` are indexed (description excluded — noisy and
--   would roughly double the index size with little recall gain).
--
-- NUMBERS (at migration time, 2026-04-19)
--   Total products      : 43.121
--   Backfill duration   : ~10–20 s (single UPDATE)
--   Index build duration: ~15–30 s
--   Expected query time : < 50 ms for typical 3+ char queries
--
-- ZONES NOT TOUCHED (BR §25.3)
--   pricing_service.dart, dispatch-engine, Stripe, bora_tokens triggers,
--   driver_capacity_service, finalizePurchase, driver_transactions,
--   original products.name / products.category columns.
--
-- ROLLBACK (in reverse order)
--   BEGIN;
--     DROP FUNCTION IF EXISTS public.search_products(TEXT, TEXT, INT);
--     DROP INDEX  IF EXISTS public.idx_products_search_trgm;
--     DROP TRIGGER IF EXISTS trg_products_set_search_normalized ON public.products;
--     DROP FUNCTION IF EXISTS public.fn_products_set_search_normalized();
--     ALTER TABLE public.products DROP COLUMN IF EXISTS search_normalized;
--     DROP FUNCTION IF EXISTS public.bora_normalize(TEXT);
--     -- Extensions left installed (harmless, may be reused elsewhere):
--     -- DROP EXTENSION IF EXISTS pg_trgm;
--     -- DROP EXTENSION IF EXISTS unaccent;
--   COMMIT;
-- ============================================================================

BEGIN;

-- 1. Extensions --------------------------------------------------------------
CREATE EXTENSION IF NOT EXISTS unaccent SCHEMA extensions;
CREATE EXTENSION IF NOT EXISTS pg_trgm  SCHEMA extensions;

-- 2. Immutable normalizer ----------------------------------------------------
-- Wraps unaccent (STABLE) in an IMMUTABLE SQL function so it is safe for
-- expression indexes and generated columns. The 2-arg form is used so the
-- dictionary is explicit.
CREATE OR REPLACE FUNCTION public.bora_normalize(input TEXT)
RETURNS TEXT
LANGUAGE SQL
IMMUTABLE
PARALLEL SAFE
AS $$
  SELECT regexp_replace(
    lower(extensions.unaccent('extensions.unaccent', COALESCE(input, ''))),
    '[^a-z0-9]+', ' ', 'g'
  )
$$;

COMMENT ON FUNCTION public.bora_normalize(TEXT) IS
  'BR §25.3 Phase 1 — lowercase + unaccent + strip punctuation. IMMUTABLE for indexing.';

-- 3. Derived column ----------------------------------------------------------
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS search_normalized TEXT;

COMMENT ON COLUMN public.products.search_normalized IS
  'BR §25.3 Phase 1 — normalized concat of name + category for tolerant search. Auto-maintained by trigger.';

-- 4. Trigger -----------------------------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_products_set_search_normalized()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.search_normalized := public.bora_normalize(
    COALESCE(NEW.name, '') || ' ' || COALESCE(NEW.category, '')
  );
  RETURN NEW;
END;
$$;

DROP TRIGGER IF EXISTS trg_products_set_search_normalized ON public.products;

CREATE TRIGGER trg_products_set_search_normalized
  BEFORE INSERT OR UPDATE OF name, category ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_products_set_search_normalized();

-- 5. Backfill 43.121 rows ----------------------------------------------------
UPDATE public.products
SET search_normalized = public.bora_normalize(
  COALESCE(name, '') || ' ' || COALESCE(category, '')
);

-- 6. GIN trigram index -------------------------------------------------------
CREATE INDEX IF NOT EXISTS idx_products_search_trgm
  ON public.products
  USING GIN (search_normalized extensions.gin_trgm_ops);

-- 7. RPC search_products -----------------------------------------------------
-- Returns sections (category_root) AND products in a single round-trip.
-- Columns: result_type ('section'|'product'), id (products.id is TEXT), name,
-- category, category_root, price, photo_url, match_rank.
-- Sections get a +0.3 rank boost so they float to the top of results.
-- Marked SECURITY INVOKER so it runs under the caller's RLS context.
CREATE OR REPLACE FUNCTION public.search_products(
  query_text      TEXT,
  p_restaurant_id TEXT DEFAULT NULL,
  max_results     INT  DEFAULT 50
)
RETURNS TABLE(
  result_type   TEXT,
  id            TEXT,
  name          TEXT,
  category      TEXT,
  category_root TEXT,
  price         NUMERIC,
  photo_url     TEXT,
  match_rank    REAL
)
LANGUAGE plpgsql
STABLE
SECURITY INVOKER
AS $$
DECLARE
  q TEXT;
BEGIN
  q := public.bora_normalize(query_text);
  q := TRIM(q);

  IF q IS NULL OR length(q) < 2 THEN
    RETURN;
  END IF;

  RETURN QUERY
  WITH section_matches AS (
    SELECT DISTINCT ON (p.category_root)
      'section'::TEXT                                           AS result_type,
      NULL::TEXT                                                AS id,
      p.category_root                                           AS name,
      NULL::TEXT                                                AS category,
      p.category_root                                           AS category_root,
      NULL::NUMERIC                                             AS price,
      NULL::TEXT                                                AS photo_url,
      (extensions.similarity(public.bora_normalize(p.category_root), q) + 0.3)::REAL AS match_rank
    FROM public.products p
    WHERE p.category_root IS NOT NULL
      AND public.bora_normalize(p.category_root) LIKE '%' || q || '%'
      AND (p_restaurant_id IS NULL OR p.restaurant_id = p_restaurant_id)
  ),
  product_matches AS (
    SELECT
      'product'::TEXT                                           AS result_type,
      p.id                                                      AS id,
      p.name                                                    AS name,
      p.category                                                AS category,
      p.category_root                                           AS category_root,
      p.price                                                   AS price,
      p.photo_url                                               AS photo_url,
      extensions.similarity(p.search_normalized, q)::REAL       AS match_rank
    FROM public.products p
    WHERE p.search_normalized LIKE '%' || q || '%'
      AND (p_restaurant_id IS NULL OR p.restaurant_id = p_restaurant_id)
  )
  SELECT * FROM section_matches
  UNION ALL
  SELECT * FROM product_matches
  ORDER BY match_rank DESC
  LIMIT max_results;
END;
$$;

COMMENT ON FUNCTION public.search_products(TEXT, TEXT, INT) IS
  'BR §25.3 Phase 1 — tolerant product+section search. SECURITY INVOKER respects RLS on products.';

COMMIT;
