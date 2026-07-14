-- Chat guiado por categoria — reforço de seed (PARTE 1, 2026-07-13/14).
-- support_categories/support_category_options já existiam (migration
-- 20260714010000) com 1-2 perguntas por categoria; esta adiciona mais 1 a
-- 3 categorias para aproximar do pedido "3-4 perguntas por categoria".
-- Reusa só factos já citados no system prompt do support-chatbot
-- (supabase/functions/support-chatbot/index.ts) — não inventa valores novos.

INSERT INTO public.support_category_options (category_id, question, answer_md, sort_order)
SELECT c.id, v.question, v.answer, v.sort_order
FROM public.support_categories c
JOIN (VALUES
  ('pedido_restaurante', 'Qual é a taxa de serviço cobrada?', 'É cobrada uma taxa de serviço de 5% sobre o subtotal, visível no recibo do pedido.', 3),
  ('mercado', 'Quanto custam os sacos das compras?', 'Cada saco de mercado custa €0,10, com um máximo de 5 sacos (€0,50 no total). O valor aparece discriminado no recibo final.', 3),
  ('entrega', 'Como é calculado o custo dos sacos?', 'Saco de restaurante: €0,30 fixo. Saco de mercado: €0,10 por saco, com máximo de 5 sacos (€0,50). Vem sempre discriminado no recibo.', 3)
) AS v(cat_slug, question, answer, sort_order) ON v.cat_slug = c.slug
WHERE NOT EXISTS (
  SELECT 1 FROM public.support_category_options existing
  WHERE existing.category_id = c.id AND existing.question = v.question
);
