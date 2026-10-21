-- Bloco D · fechar-pendencias-2026-10-20 — artigos-premio dos marcos do check-in.
-- Um artigo a 0 EUR por loja, so visivel ao servidor e ao admin: entra no carrinho
-- quando o cliente usa o vale (client_checkin_premio_reservar) e o gatilho do pedido
-- confirma o vale. O cliente paga a entrega e as taxas como num pedido normal.
-- Nao mexe em nenhum preco existente: so acrescenta 2 artigos e as suas opcoes.

-- 1) Artigos (preco 0, indisponiveis no menu) -----------------------------------------
INSERT INTO public.products (id, restaurant_id, name, description, photo_url, is_available, price, category, unit)
SELECT 'premio-checkin-salgados', 'sabores-brasil-guarda',
       'Prémio Bora Todo Dia: 2 Salgados Grandes',
       'Prémio do check-in (10 dias seguidos). A Bora paga estes 2 salgados à loja. Os sabores estão nas opções.',
       p.photo_url, false, 0, 'Prémio check-in', 'prémio'
  FROM public.products p
 WHERE p.id = '09a9503f-1ef2-4a92-9486-e53848dc853c'
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.products (id, restaurant_id, name, description, photo_url, is_available, price, category, unit)
SELECT 'premio-checkin-acai', 'goola-acai-guarda',
       'Prémio Bora Todo Dia: Goola Bowl',
       'Prémio do check-in (15 dias seguidos). A Bora paga este bowl à loja. Os 3 acompanhamentos estão nas opções; os extras pagam-se à parte.',
       p.photo_url, false, 0, 'Prémio check-in', 'prémio'
  FROM public.products p
 WHERE p.id = 'goola-bowl'
ON CONFLICT (id) DO NOTHING;

-- 2) Opcoes: sabores dos salgados; copia das opcoes do Goola Bowl ----------------------
INSERT INTO public.product_option_groups (id, product_id, name, description, is_required, min_choices, max_choices, sort_order)
VALUES ('premio-checkin-salgados-1', 'premio-checkin-salgados', '1.º salgado', 'Escolhe o sabor.', true, 1, 1, 1),
       ('premio-checkin-salgados-2', 'premio-checkin-salgados', '2.º salgado', 'Escolhe o sabor.', true, 1, 1, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.product_option_items (id, group_id, name, price_add, is_available, sort_order)
VALUES ('premio-checkin-salgados-1-coxinha', 'premio-checkin-salgados-1', 'Coxinha', 0, true, 1),
       ('premio-checkin-salgados-1-esfirra', 'premio-checkin-salgados-1', 'Esfirra', 0, true, 2),
       ('premio-checkin-salgados-2-coxinha', 'premio-checkin-salgados-2', 'Coxinha', 0, true, 1),
       ('premio-checkin-salgados-2-esfirra', 'premio-checkin-salgados-2', 'Esfirra', 0, true, 2)
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.product_option_groups (id, product_id, name, description, is_required, min_choices, max_choices, sort_order)
SELECT 'premio-checkin-acai-' || CASE WHEN g.id = 'goola-bowl-acomp' THEN 'acomp' ELSE 'extra' END,
       'premio-checkin-acai', g.name, g.description, g.is_required, g.min_choices, g.max_choices, g.sort_order
  FROM public.product_option_groups g
 WHERE g.id IN ('goola-bowl-acomp', 'goola-bowl-extra')
ON CONFLICT (id) DO NOTHING;

INSERT INTO public.product_option_items (id, group_id, name, price_add, is_available, sort_order)
SELECT 'premio-checkin-acai-' || i.id,
       'premio-checkin-acai-' || CASE WHEN i.group_id = 'goola-bowl-acomp' THEN 'acomp' ELSE 'extra' END,
       i.name, i.price_add, i.is_available, i.sort_order
  FROM public.product_option_items i
 WHERE i.group_id IN ('goola-bowl-acomp', 'goola-bowl-extra')
ON CONFLICT (id) DO NOTHING;

-- 3) Os artigos-premio nao aparecem a ninguem (cliente, loja, visitante) -------------
-- Politica RESTRITIVA: soma-se as que ja existem; so o admin os ve e edita.
-- As funcoes do servidor (SECURITY DEFINER) continuam a ve-los.
CREATE POLICY products_premio_checkin_oculto_anon ON public.products
  AS RESTRICTIVE FOR ALL TO anon
  USING (id NOT LIKE 'premio-checkin-%')
  WITH CHECK (id NOT LIKE 'premio-checkin-%');

CREATE POLICY products_premio_checkin_oculto ON public.products
  AS RESTRICTIVE FOR ALL TO authenticated
  USING (id NOT LIKE 'premio-checkin-%' OR (SELECT public.is_admin()))
  WITH CHECK (id NOT LIKE 'premio-checkin-%' OR (SELECT public.is_admin()));
