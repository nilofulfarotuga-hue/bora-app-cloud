-- ============================================================
-- BORA APP — BLOCO 1: AUDITORIA
-- Executar ANTES e DEPOIS da expansão
-- ============================================================

SELECT COUNT(*) AS total_produtos FROM products;

SELECT COUNT(*) AS sem_imagem FROM products
WHERE photo_url IS NULL OR photo_url = '';

SELECT COUNT(*) AS sem_preco FROM products
WHERE price IS NULL OR price = 0;

SELECT COUNT(*) AS preco_absurdo FROM products
WHERE price > 100 OR price < 0.10;

SELECT COUNT(DISTINCT category) AS total_categorias FROM products;

SELECT category, COUNT(*) AS total
FROM products GROUP BY category ORDER BY total DESC;

SELECT id, name, category, price, photo_url
FROM products ORDER BY created_at LIMIT 10;
