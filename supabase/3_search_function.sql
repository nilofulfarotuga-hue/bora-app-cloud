-- ============================================================
-- BORA APP — ETAPA 7: FUNÇÃO DE BUSCA COM UNACCENT
-- Executar no Supabase SQL Editor
-- ============================================================

-- Extensão para remover acentos
CREATE EXTENSION IF NOT EXISTS unaccent;

-- Função de busca sem acentos
CREATE OR REPLACE FUNCTION search_products(search_term TEXT, store_id TEXT DEFAULT NULL)
RETURNS SETOF products AS $$
BEGIN
  RETURN QUERY
  SELECT * FROM products
  WHERE
    is_available = true
    AND (store_id IS NULL OR restaurant_id = store_id)
    AND (
      unaccent(LOWER(name)) LIKE '%' || unaccent(LOWER(search_term)) || '%'
      OR unaccent(LOWER(category)) LIKE '%' || unaccent(LOWER(search_term)) || '%'
      OR unaccent(LOWER(COALESCE(description, ''))) LIKE '%' || unaccent(LOWER(search_term)) || '%'
    )
  ORDER BY
    CASE WHEN unaccent(LOWER(name)) LIKE unaccent(LOWER(search_term)) || '%' THEN 0 ELSE 1 END,
    is_popular DESC,
    name ASC;
END;
$$ LANGUAGE plpgsql STABLE;

-- Índice para melhorar performance de busca
CREATE INDEX IF NOT EXISTS idx_products_name_lower ON products (LOWER(name));
CREATE INDEX IF NOT EXISTS idx_products_category ON products (category);
CREATE INDEX IF NOT EXISTS idx_products_restaurant ON products (restaurant_id);

-- Testar a função
-- SELECT * FROM search_products('leite', 'continente-guarda');
-- SELECT * FROM search_products('agua');

-- ============================================================
-- FLUTTER — onde integrar (NÃO ALTERAR AQUI, só referência):
-- lib/stores/restaurant_store.dart ou equivalente
-- Substituir:
--   .from('products').select().ilike('name', '%$query%')
-- Por:
--   .rpc('search_products', params: {'search_term': query, 'store_id': restaurantId})
-- ============================================================
