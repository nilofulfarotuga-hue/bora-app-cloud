-- ============================================================================
-- BORA — Fix HTML entities in product NAME / CATEGORY / BRAND (v2 — 2026-07-11)
-- ============================================================================
-- Bug real em produção (foto do Continente): nomes com entidades HTML por
-- descodificar — ex. "Ra&ccedil;&atilde;o" em vez de "Ração", "H&uacute;mida"
-- em vez de "Húmida", "Trela para C&atilde;o".
--
-- Causa: o atributo SFCC `data-product-tile-impression` vem DUPLAMENTE
-- codificado (`&amp;ccedil;`); o crawler descodifica UMA vez (attr → JSON) e
-- a entidade interna (`&ccedil;`) sobra no `name` gravado. A migration
-- 20260430100000 já corria isto, mas (a) só cobria name+description e (b) o
-- crawler continuou a re-introduzir entidades a cada scrape → volta a aparecer.
--
-- Esta v2: aplica a name + category + brand_low (description já limpo em prod),
-- cobrindo também &ordm; &ordf; &ndash; &acute; que a v1 não tinha. Loop por
-- par entidade→char (menos frágil que REPLACE aninhado). Idempotente. Ordem:
-- entidades nomeadas primeiro, `&amp;` por último. NÃO toca photo_url.
-- ============================================================================

DO $$
DECLARE
  p TEXT[];
  pairs TEXT[][] := ARRAY[
    ['&aacute;','á'],['&Aacute;','Á'],['&agrave;','à'],['&Agrave;','À'],
    ['&atilde;','ã'],['&Atilde;','Ã'],['&acirc;','â'],['&Acirc;','Â'],
    ['&auml;','ä'],['&Auml;','Ä'],['&ordf;','ª'],['&ordm;','º'],
    ['&eacute;','é'],['&Eacute;','É'],['&egrave;','è'],['&Egrave;','È'],
    ['&ecirc;','ê'],['&Ecirc;','Ê'],['&euml;','ë'],
    ['&iacute;','í'],['&Iacute;','Í'],['&igrave;','ì'],['&icirc;','î'],['&iuml;','ï'],
    ['&oacute;','ó'],['&Oacute;','Ó'],['&otilde;','õ'],['&Otilde;','Õ'],
    ['&ocirc;','ô'],['&Ocirc;','Ô'],['&ouml;','ö'],['&Ouml;','Ö'],
    ['&uacute;','ú'],['&Uacute;','Ú'],['&ucirc;','û'],['&uuml;','ü'],['&Uuml;','Ü'],
    ['&ccedil;','ç'],['&Ccedil;','Ç'],['&ntilde;','ñ'],['&Ntilde;','Ñ'],['&szlig;','ß'],
    ['&ndash;','–'],['&mdash;','—'],['&acute;','´'],['&hellip;','…'],
    ['&nbsp;',' '],['&shy;',''],['&euro;','€'],['&pound;','£'],
    ['&reg;','®'],['&copy;','©'],['&trade;','™'],
    ['&quot;','"'],['&apos;',''''],['&#39;',''''],['&lt;','<'],['&gt;','>'],
    ['&amp;','&']
  ];
BEGIN
  FOREACH p SLICE 1 IN ARRAY pairs LOOP
    UPDATE public.products
       SET name      = replace(name, p[1], p[2]),
           category  = replace(category, p[1], p[2]),
           brand_low = replace(brand_low, p[1], p[2])
     WHERE name      LIKE '%'||p[1]||'%'
        OR category  LIKE '%'||p[1]||'%'
        OR brand_low LIKE '%'||p[1]||'%';
  END LOOP;
END $$;
