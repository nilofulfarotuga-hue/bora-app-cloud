-- ============================================================
-- BORA APP — ETAPA 1: AUDITORIA
-- Executar no Supabase SQL Editor antes de qualquer alteração
-- ============================================================

-- Total de produtos
SELECT COUNT(*) AS total_produtos FROM products;

-- Sem imagem
SELECT COUNT(*) AS sem_imagem FROM products
WHERE photo_url IS NULL OR photo_url = '';

-- Sem preço
SELECT COUNT(*) AS sem_preco FROM products
WHERE price IS NULL OR price = 0;

-- Por categoria
SELECT category, COUNT(*) AS total
FROM products GROUP BY category ORDER BY total DESC;

-- Total de categorias
SELECT COUNT(DISTINCT category) AS total_categorias FROM products;

-- 10 produtos exemplo
SELECT id, name, category, price, photo_url
FROM products ORDER BY created_at LIMIT 10;

-- Preços absurdos
SELECT id, name, category, price FROM products
WHERE price > 100 OR price < 0.10 OR price IS NULL;

-- Produtos sem categoria
SELECT COUNT(*) AS sem_categoria FROM products
WHERE category IS NULL OR category = '';
