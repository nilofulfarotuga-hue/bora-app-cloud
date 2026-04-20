-- Seed: 5 restaurantes reais portugueses com produtos realistas
-- Só insere se a tabela estiver vazia (safe to re-run)

DO $$
DECLARE
  r1 uuid := gen_random_uuid();
  r2 uuid := gen_random_uuid();
  r3 uuid := gen_random_uuid();
  r4 uuid := gen_random_uuid();
  r5 uuid := gen_random_uuid();
BEGIN
  -- Só faz seed se não houver restaurantes
  IF (SELECT COUNT(*) FROM restaurants) > 0 THEN
    RETURN;
  END IF;

  -- ── Restaurantes ────────────────────────────────────────────────────
  INSERT INTO restaurants (id, name, category, address, lat, lng, is_partner, is_active, image_url) VALUES
    (r1, 'Tasca do Zé',        'restaurant',   'Rua Augusta 45, Lisboa',          38.7097, -9.1395, true,  true, ''),
    (r2, 'Pingo Doce Express', 'supermarket',  'Av. da Liberdade 110, Lisboa',    38.7167, -9.1423, true,  true, ''),
    (r3, 'Farmácia Saúde',     'pharmacy',     'Rua do Ouro 88, Lisboa',          38.7089, -9.1387, true,  true, ''),
    (r4, 'Burger Palace',      'restaurant',   'Rua de Santa Catarina 20, Porto', 41.1480, -8.6090, true,  true, ''),
    (r5, 'Mini Mercado Silva',  'supermarket',  'Rua do Almada 55, Porto',         41.1460, -8.6102, true,  true, '');

  -- ── Produtos — Tasca do Zé ───────────────────────────────────────────
  INSERT INTO products (restaurant_id, name, description, price, is_available) VALUES
    (r1, 'Bacalhau à Brás',      'Bacalhau desfiado com batata palha, ovos e azeitonas.',           13.50, true),
    (r1, 'Frango no Churrasco',  'Meio frango grelhado com molho piri-piri e batatas fritas.',       9.90, true),
    (r1, 'Caldo Verde',          'Sopa tradicional com chouriço e couve-galega.',                    3.50, true),
    (r1, 'Pastel de Nata',       'Pastel de nata artesanal polvilhado com canela.',                  1.20, true),
    (r1, 'Sangria (1L)',         'Sangria de vinho tinto com fruta da época.',                       8.00, true);

  -- ── Produtos — Pingo Doce Express ───────────────────────────────────
  INSERT INTO products (restaurant_id, name, description, price, is_available) VALUES
    (r2, 'Leite Mimosa 1L',      'Leite meio-gordo UHT.',                                           0.89, true),
    (r2, 'Pão de Forma',         'Pão de forma fatiado 500g.',                                      1.29, true),
    (r2, 'Iogurte Activia x8',   'Pack 8 iogurtes naturais.',                                       2.49, true),
    (r2, 'Água 6x1.5L',          'Pack água mineral natural.',                                      2.19, true),
    (r2, 'Frango Inteiro',       'Frango inteiro refrigerado ±1.3kg.',                               4.99, true),
    (r2, 'Massa Esparguete 500g','Massa esparguete grano duro.',                                    0.79, true);

  -- ── Produtos — Farmácia Saúde ────────────────────────────────────────
  INSERT INTO products (restaurant_id, name, description, price, is_available) VALUES
    (r3, 'Ben-U-Ron 1g x20',     'Paracetamol 1g, comprimidos. Uso adulto.',                        3.20, true),
    (r3, 'Brufen 400mg x20',     'Ibuprofeno 400mg, comprimidos.',                                  4.10, true),
    (r3, 'Protetor Solar SPF50', 'Protetor solar facial 50ml SPF50.',                               12.90, true),
    (r3, 'Vitamina C 1000mg',    'Comprimidos efervescentes de vitamina C, tubo 20 un.',             5.50, true);

  -- ── Produtos — Burger Palace ─────────────────────────────────────────
  INSERT INTO products (restaurant_id, name, description, price, is_available) VALUES
    (r4, 'Classic Burger',       'Hambúrguer de novilho, alface, tomate e molho especial.',          8.50, true),
    (r4, 'Cheese Burger Duplo',  'Dois hambúrgueres com queijo cheddar e pickles.',                 11.90, true),
    (r4, 'Batatas Fritas',       'Batatas fritas crocantes com sal.',                               3.50, true),
    (r4, 'Milkshake Baunilha',   'Milkshake cremoso sabor baunilha 400ml.',                         4.20, true),
    (r4, 'Menu Criança',         'Mini burger + batata frita + sumo.',                              7.50, true);

  -- ── Produtos — Mini Mercado Silva ────────────────────────────────────
  INSERT INTO products (restaurant_id, name, description, price, is_available) VALUES
    (r5, 'Ovos Galinhas Livres x6', 'Ovos de galinhas criadas ao ar livre, meia dúzia.',            1.99, true),
    (r5, 'Banana (kg)',              'Bananas frescas, preço por kg.',                               1.49, true),
    (r5, 'Sumo de Laranja 1L',       'Sumo de laranja natural 100%.',                               2.79, true),
    (r5, 'Queijo Flamengo Fatiado',  'Queijo flamengo fatiado 200g.',                               2.39, true);

END $$;
