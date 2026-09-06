-- ============================================================================
-- BORA — Fix HTML entities in product names (T2 — sessão fixes 2026-04-30)
-- ============================================================================
-- Products scraped from Continente/Auchan/etc. had HTML entities in names
-- (e.g. "L&aacute;pis" instead of "Lápis"). This migration corrects the
-- `name` and `description` columns idempotently (safe to re-run: if no
-- entities remain, no rows are touched).
--
-- Scope: public.products, columns `name` + `description`.
-- Strategy: chained REPLACE() — pure SQL, no extension needed.
-- Does NOT touch photo_url (per permanent rule: NÃO mexer em fotos).
-- ============================================================================

BEGIN;

-- Helper: apply all PT/Latin HTML entity replacements to a TEXT value.
-- Used below in a single UPDATE with SET name = decode_html(name).
CREATE OR REPLACE FUNCTION public._decode_html_entities(p_text TEXT)
RETURNS TEXT
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT
    -- numeric hex &#xHH; → covered by CASE below
    -- numeric decimal &#NNN; → ditto
    -- Named entities (most common in PT product names):
    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
    REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(REPLACE(
    REPLACE(p_text,
      '&amp;',    '&'),
      '&quot;',   '"'),
      '&apos;',   ''''),
      '&#39;',    ''''),
      '&lt;',     '<'),
      '&gt;',     '>'),
      '&aacute;', 'á'),
      '&Aacute;', 'Á'),
      '&agrave;', 'à'),
      '&Agrave;', 'À'),
      '&atilde;', 'ã'),
      '&Atilde;', 'Ã'),
      '&acirc;',  'â'),
      '&Acirc;',  'Â'),
      '&eacute;', 'é'),
      '&Eacute;', 'É'),
      '&egrave;', 'è'),
      '&Egrave;', 'È'),
      '&ecirc;',  'ê'),
      '&Ecirc;',  'Ê'),
      '&iacute;', 'í'),
      '&Iacute;', 'Í'),
      '&icirc;',  'î'),
      '&Icirc;',  'Î'),
      '&oacute;', 'ó'),
      '&Oacute;', 'Ó'),
      '&otilde;', 'õ'),
      '&Otilde;', 'Õ'),
      '&ocirc;',  'ô'),
      '&Ocirc;',  'Ô'),
      '&uacute;', 'ú'),
      '&Uacute;', 'Ú'),
      '&ccedil;', 'ç'),
      '&Ccedil;', 'Ç'),
      '&ntilde;', 'ñ'),
      '&Ntilde;', 'Ñ'),
      '&nbsp;',   ' '),
      '&shy;',    ''),
      '&euro;',   '€'),
      '&pound;',  '£'),
      '&reg;',    '®'),
      '&copy;',   '©'),
      '&trade;',  '™'),
      '&auml;',   'ä'),
      '&Auml;',   'Ä'),
      '&ouml;',   'ö'),
      '&Ouml;',   'Ö'),
      '&uuml;',   'ü'),
      '&Uuml;',   'Ü'),
      '&szlig;',  'ß'),
      '&iuml;',   'ï'),
      '&euml;',   'ë')
$$;

-- Apply to name + description (only rows that actually contain '&')
-- for performance (index scan on LIKE with leading wildcard is full-scan
-- but the table is large — WHERE clause avoids unnecessary updates).
UPDATE public.products
   SET name        = public._decode_html_entities(name),
       description = public._decode_html_entities(description)
 WHERE name LIKE '%&%' OR description LIKE '%&%';

-- Report how many rows were updated (appears in migration output).
DO $$
DECLARE v_count INT;
BEGIN
  SELECT count(*) INTO v_count
    FROM public.products
   WHERE name LIKE '%&%' OR description LIKE '%&%';
  RAISE NOTICE 'fix_html_entities: % products STILL have & after update (should be ~0 for named entities)', v_count;
END $$;

COMMIT;

-- POST-APPLY VERIFICATION:
--   SELECT name FROM products WHERE name LIKE '%&%' LIMIT 5;
--   -- Expect only legitimate & characters (Fácil & Bom) — not entities.
