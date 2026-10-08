-- Prova do servidor, ponta a ponta, numa transação DESFEITA (08/10/2026).
-- Dois Favores de teste da conta demo (demo@bora.app), pelas mesmas funções que
-- a app chama: create_order → errand_set_home_stop (só o B) → o estafeta demo
-- (dede…0001) recolhe, fecha o talão e entrega. No fim RAISE EXCEPTION 'RESULT …'
-- desfaz tudo: nenhum pedido fica, nenhum aviso sai (o pg_net também é desfeito).
--   A = farmácia, com foto, SEM passar em casa (talão 1,88 €)
--   B = COM "passar em casa primeiro" (talão 1,88 €)
-- O que se mede em cada passo: errand_passo, errand_home_stop_*, price/total/
-- customer_total/cash_total_due/final_total, is_test_order.
DO $$
DECLARE
  r      text := '';
  ja     jsonb;
  jb     jsonb;
  ida    text;
  idb    text;
  j      jsonb;
  v      record;
  c_cli  constant text := 'd5b0c0a1-f49e-4593-a919-147edfc069c2';
  c_drv  constant text := 'dede0000-0000-4000-8000-000000000001';
  c_adm  constant text := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
  base   jsonb := jsonb_build_object(
    'service_type','errand','is_partner_store',false,'distance_km',3.4,
    'payment_method','cash','subtotal',0,'apartment_delivery',false,
    'order_type','errand','bag_count',0,'requires_car',false,
    'wallet_applied_cents',0,
    'dropoff_lat',40.5370,'dropoff_lng',-7.2680,
    'dropoff_address','Rua de Prova 1, Guarda (TESTE)',
    'errand_location','Farmácia Tavares, Avenida Cidade de Safed, Guarda',
    'errand_location_lat',40.5420,'errand_location_lng',-7.2560,
    'errand_speed','normal','errand_has_purchase',true,
    'errand_estimated_purchase_cents',400,
    'customer_name','Demo Bora','items','[]'::jsonb);
BEGIN
  -- ── Cliente demo cria os dois favores ─────────────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', c_cli, 'role', 'authenticated', 'email', 'demo@bora.app')::text, true);
  PERFORM set_config('role', 'authenticated', true);

  ja := public.create_order(base || jsonb_build_object(
    'errand_home_stop', false,
    'pickup_address', 'Farmácia Tavares, Avenida Cidade de Safed, Guarda',
    'errand_description', 'PROVA 08/10 A — farmácia, receita por foto (teste)',
    'errand_request_photo_url', 'order-photos/' || c_cli || '/errand_request_prova_a.jpg'));
  ida := ja->>'order_id';
  jb := public.create_order(base || jsonb_build_object(
    'errand_home_stop', true, 'errand_home_stop_reason', 'outro',
    'pickup_lat', 40.5370, 'pickup_lng', -7.2680,
    'pickup_address', 'Rua de Prova 1, Guarda (TESTE)',
    'errand_description', 'PROVA 08/10 B — passar em casa primeiro (teste)'));
  idb := jb->>'order_id';
  -- a app (corrigida) grava a paragem logo a seguir, com a sessão tirada antes
  j := public.errand_set_home_stop(idb, 'Rua de Prova 1, Guarda (TESTE)', 40.5370, -7.2680, NULL, false);

  SELECT is_test_order, status, errand_passo, errand_home_stop, price, total INTO v FROM orders WHERE id = ida;
  r := r || 'A criado: ' || row_to_json(v)::text;
  SELECT is_test_order, status, errand_passo, errand_home_stop, errand_home_stop_address a,
         errand_home_stop_lat lat, errand_home_stop_lng lng, price INTO v FROM orders WHERE id = idb;
  r := r || E'\nB criado: ' || row_to_json(v)::text;

  -- ── Admin passa os dois ao estafeta demo pela PESSOA (user_id) ─────────────
  -- (o gatilho dos pedidos demo entrega-os a drivers.id dede…0002, que a app
  -- do estafeta não vê — achado reportado, não corrigido aqui)
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', c_adm, 'role', 'authenticated', 'email', 'nilofulfarotuga@gmail.com',
    'app_metadata', json_build_object('role', 'admin'))::text, true);
  j := public.admin_reassign_order(ida, c_drv, 'prova rollback 08/10');
  j := public.admin_reassign_order(idb, c_drv, 'prova rollback 08/10');
  SELECT assigned_driver_id, status, errand_passo INTO v FROM orders WHERE id = idb;
  r := r || E'\nB atribuído: ' || row_to_json(v)::text;

  -- ── Estafeta demo: B (casa → favor → entrega) ──────────────────────────────
  PERFORM set_config('request.jwt.claims', json_build_object(
    'sub', c_drv, 'role', 'authenticated', 'email', 'demo-estafeta@bora.app')::text, true);
  UPDATE orders SET status = 'pickedUp' WHERE id = idb;          -- "Confirmar recolha"
  SELECT status, errand_passo INTO v FROM orders WHERE id = idb;
  r := r || E'\nB recolhido em casa: ' || row_to_json(v)::text;
  j := public.finalize_errand_purchase(idb, 188, 'receipts/' || idb || '.jpg');   -- talão 1,88
  SELECT errand_passo, subtotal, price, total, customer_total, cash_total_due, final_total INTO v FROM orders WHERE id = idb;
  r := r || E'\nB talão 1,88: ' || row_to_json(v)::text;
  UPDATE orders SET status = 'onTheWay' WHERE id = idb;
  UPDATE orders SET status = 'delivered' WHERE id = idb;
  SELECT status, errand_passo, price, final_total INTO v FROM orders WHERE id = idb;
  r := r || E'\nB entregue: ' || row_to_json(v)::text;

  -- ── Estafeta demo: A (favor → entrega) ─────────────────────────────────────
  SELECT status, errand_passo INTO v FROM orders WHERE id = ida;
  r := r || E'\nA no favor: ' || row_to_json(v)::text;
  j := public.finalize_errand_purchase(ida, 188, 'receipts/' || ida || '.jpg');
  SELECT errand_passo, price, total, cash_total_due, final_total INTO v FROM orders WHERE id = ida;
  r := r || E'\nA talão 1,88: ' || row_to_json(v)::text;
  UPDATE orders SET status = 'pickedUp' WHERE id = ida;
  UPDATE orders SET status = 'onTheWay' WHERE id = ida;
  SELECT status, errand_passo INTO v FROM orders WHERE id = ida;
  r := r || E'\nA a caminho: ' || row_to_json(v)::text;

  RAISE EXCEPTION 'RESULT %', r;
END $$;
