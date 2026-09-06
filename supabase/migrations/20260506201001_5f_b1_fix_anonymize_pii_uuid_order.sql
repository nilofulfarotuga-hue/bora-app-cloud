-- Sessão 5F B1 fix — ordem regex em _anonymize_pii
-- BUG detectado em smoke S2: phone genérico '\+?[1-9]\d{6,14}' consumia
-- segmentos numéricos do UUID antes do regex UUID rodar.
-- Fix: mover regex UUID antes do phone genérico.
-- NOTA: JS 5D analyze-conversations tem mesmo bug — TODO 5F-β corrigir lá.

CREATE OR REPLACE FUNCTION public._anonymize_pii(p_text text)
RETURNS text
LANGUAGE sql
IMMUTABLE
AS $$
  SELECT regexp_replace(
    regexp_replace(
      regexp_replace(
        regexp_replace(
          regexp_replace(coalesce(p_text, ''),
            '[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}',
            '[email]', 'g'),
          '\+?351[\s.-]?9\d{2}[\s.-]?\d{3}[\s.-]?\d{3}',
          '[phone]', 'g'),
        '[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}',
        '[uuid]', 'g'),
      '\+?[1-9]\d{6,14}',
      '[phone]', 'g'),
    '\y\d{4,}\y',
    '[number]', 'g');
$$;
