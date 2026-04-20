-- ============================================================================
-- BORA — products.category_root (Phase 1, BR §25.3 — additive, surgical)
-- ============================================================================
-- WHY
--   The `category` field stores a hierarchical path like
--   "Mercearia/Chocolate, Gomas e Rebuçados/Gomas, Pastilhas e Rebuçados".
--   The client UI was treating each distinct path as a separate category,
--   fragmenting the Mercearia section into 53 variants and producing a
--   1.333-category menu that is unusable on mobile.
--
-- NUMBERS (at migration time, 2026-04-19)
--   Total products          : 43.121
--   Distinct category paths : 1.333
--   Distinct root categories: ~798 (after TRIM + split on '/')
--   Paths with hierarchy    : 4.876 (11%)
--   Paths without '/'       : 38.242 (89%)
--
-- APPROACH
--   1. Add derived column `category_root TEXT` on products.
--   2. Install a BEFORE INSERT/UPDATE trigger that keeps it in sync with
--      `category` (TRIM + split_part by '/').
--   3. Backfill all 43.121 existing rows in one UPDATE.
--   4. Add btree index for fast filtering by root.
--
--   The original `category` column is NEVER mutated — safe for rollback and
--   for the Phase 2/3 editorial mapping table that will collapse ~798 roots
--   down to ~25–30 user-facing sections (future work, NOT this migration).
--
-- ZONES NOT TOUCHED (BR §25.3)
--   pricing_service.dart, dispatch-engine, Stripe, bora_tokens triggers,
--   driver_capacity_service, finalizePurchase, driver_transactions.
--
-- ROLLBACK
--   BEGIN;
--     DROP TRIGGER IF EXISTS trg_products_set_category_root ON public.products;
--     DROP FUNCTION IF EXISTS public.fn_products_set_category_root();
--     DROP INDEX IF EXISTS public.idx_products_category_root;
--     ALTER TABLE public.products DROP COLUMN IF EXISTS category_root CASCADE;
--   COMMIT;
--
-- TECH DEBT (post-launch)
--   Add `category_mapping (raw_root TEXT PK, display_root TEXT)` to aggregate
--   similar roots editorially (e.g. "Queijaria" + "Charcutaria" → "Frios").
-- ============================================================================

BEGIN;

-- 1. Derived column -----------------------------------------------------------
ALTER TABLE public.products
  ADD COLUMN IF NOT EXISTS category_root TEXT;

COMMENT ON COLUMN public.products.category_root IS
  'BR §25.3 Phase 1 — first segment of category (TRIM + split on /). '
  'Auto-maintained by trigger trg_products_set_category_root. '
  'Source of truth for UI grouping; original `category` is preserved.';

-- 2. Trigger function + trigger ----------------------------------------------
CREATE OR REPLACE FUNCTION public.fn_products_set_category_root()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
  NEW.category_root := NULLIF(
    TRIM(split_part(COALESCE(NEW.category, ''), '/', 1)),
    ''
  );
  RETURN NEW;
END;
$$;

COMMENT ON FUNCTION public.fn_products_set_category_root() IS
  'BR §25.3 Phase 1 — keeps products.category_root in sync with products.category.';

DROP TRIGGER IF EXISTS trg_products_set_category_root ON public.products;

CREATE TRIGGER trg_products_set_category_root
  BEFORE INSERT OR UPDATE OF category ON public.products
  FOR EACH ROW
  EXECUTE FUNCTION public.fn_products_set_category_root();

-- 3. Backfill existing 43.121 rows (single UPDATE) ---------------------------
UPDATE public.products
SET category_root = NULLIF(
  TRIM(split_part(COALESCE(category, ''), '/', 1)),
  ''
);

-- 4. Index for fast GROUP BY / WHERE category_root = ... ---------------------
CREATE INDEX IF NOT EXISTS idx_products_category_root
  ON public.products(category_root);

COMMIT;
