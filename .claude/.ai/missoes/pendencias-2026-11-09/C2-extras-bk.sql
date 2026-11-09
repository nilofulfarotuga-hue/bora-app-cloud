-- ============================================================================
-- C2 (pendencias-2026-11-09) — Extras do Burger King: "EXTRA Bacon" 0,91 → 1,22 (65 opções)
-- ⚠️ ISTO MEXE EM PREÇOS. NÃO CORRER sem o "autorizo" do Danilo (com data).
-- Raciocínio e tabela: C2-extras-bk-proposta.md (mesma pasta).
--   balcão 2,50 (talão a244493e, 08/11) · Glovo Guarda 1,40 (lido a 09/11) · margem 15% em runtime
--   1,22 × 1,15 = 1,403 → o cliente vê 1,40 = Glovo. Só sobe (guarda "price_add < 1.22").
-- Os extras vivem em product_option_items.price_add (não em products). A tabela de cópia chama-se
-- bkp_products_bk_extras_20261109 (nome pedido na missão) e guarda TODAS as opções "EXTRA…" do BK
-- (515 linhas a 09/11), com o produto a que pertencem.
-- ============================================================================

BEGIN;

-- 1) cópia das linhas atuais (só a primeira vez; se já existir, fica a cópia original)
CREATE TABLE IF NOT EXISTS public.bkp_products_bk_extras_20261109 AS
SELECT i.id, i.group_id, i.name, i.price_add, i.is_available, i.sort_order, i.created_at,
       g.product_id, p.name AS produto_nome, now() AS guardado_em
  FROM public.product_option_items i
  JOIN public.product_option_groups g ON g.id = i.group_id
  JOIN public.products p ON p.id = g.product_id
 WHERE p.restaurant_id = 'burgerking-guarda'
   AND i.name ILIKE 'extra%';
ALTER TABLE public.bkp_products_bk_extras_20261109 ENABLE ROW LEVEL SECURITY;

-- conferir a cópia: esperado 515 linhas, 65 delas "EXTRA Bacon" a 0,91
SELECT count(*) AS linhas_copiadas,
       count(*) FILTER (WHERE name = 'EXTRA Bacon') AS bacon,
       min(price_add) FILTER (WHERE name = 'EXTRA Bacon') AS bacon_min,
       max(price_add) FILTER (WHERE name = 'EXTRA Bacon') AS bacon_max
  FROM public.bkp_products_bk_extras_20261109;

-- 2) subir o bacon (só a subir: price_add < 1.22). Esperado: 65 linhas, todas 0,91 → 1,22.
WITH mudou AS (
  UPDATE public.product_option_items i
     SET price_add = 1.22
    FROM public.product_option_groups g, public.products p
   WHERE g.id = i.group_id
     AND p.id = g.product_id
     AND p.restaurant_id = 'burgerking-guarda'
     AND i.name = 'EXTRA Bacon'
     AND i.price_add < 1.22
  RETURNING i.id, i.price_add
)
SELECT count(*) AS linhas_mudadas, min(price_add) AS novo_min, max(price_add) AS novo_max FROM mudou;

-- 3) prova: nenhuma opção "EXTRA Bacon" do BK abaixo de 1,22 e o cliente vê 1,40
SELECT i.name, count(*) AS opcoes, min(i.price_add) AS guardado, round(min(i.price_add) * 1.15, 2) AS cliente_ve
  FROM public.product_option_items i
  JOIN public.product_option_groups g ON g.id = i.group_id
  JOIN public.products p ON p.id = g.product_id
 WHERE p.restaurant_id = 'burgerking-guarda' AND i.name = 'EXTRA Bacon'
 GROUP BY i.name;

-- Se as contas não baterem (linhas_mudadas <> 65), trocar COMMIT por ROLLBACK.
COMMIT;

-- REVERTER (se for preciso):
-- UPDATE public.product_option_items i SET price_add = b.price_add
--   FROM public.bkp_products_bk_extras_20261109 b
--  WHERE b.id = i.id AND i.price_add IS DISTINCT FROM b.price_add;
