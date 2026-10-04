-- Prova do Bloco 2 (missão única 2026-10-03), em transação DESFEITA (RAISE no fim).
-- Correr DEPOIS de aplicar 20261004093000_pedido_duplicado_pacote_e_compras.sql.
-- Esperado: 'pacote_1=ok pacote_2=RECUSADO compras_1=ok compras_2=RECUSADO compras_outra_loja=ok'
DO $prova$
DECLARE
  res text := '';
  v_uid uuid := (SELECT id FROM auth.users WHERE email = 'demo@bora.app' LIMIT 1);
  v_cols text;
BEGIN
  IF v_uid IS NULL THEN RAISE EXCEPTION 'sem conta demo@bora.app'; END IF;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_uid, 'role', 'authenticated')::text, true);

  INSERT INTO public.orders(id, user_id, service_type, status, pickup_address, dropoff_address, price)
  VALUES ('prova-b2-p1', v_uid, 'sendPackage', 'created', 'Rua A, Guarda', 'Rua B, Guarda', 7.5);
  res := res || 'pacote_1=ok';
  BEGIN
    INSERT INTO public.orders(id, user_id, service_type, status, pickup_address, dropoff_address, price)
    VALUES ('prova-b2-p2', v_uid, 'sendPackage', 'created', 'Rua A, Guarda', 'Rua B, Guarda', 7.5);
    res := res || ' pacote_2=PASSOU(MAU)';
  EXCEPTION WHEN raise_exception THEN res := res || ' pacote_2=RECUSADO'; END;

  INSERT INTO public.orders(id, user_id, service_type, status, pickup_address, dropoff_address, price)
  VALUES ('prova-b2-c1', v_uid, 'carryGroceries', 'created', 'Continente Guarda', 'Rua B, Guarda', 5);
  res := res || ' compras_1=ok';
  BEGIN
    INSERT INTO public.orders(id, user_id, service_type, status, pickup_address, dropoff_address, price)
    VALUES ('prova-b2-c2', v_uid, 'carryGroceries', 'created', 'Continente Guarda', 'Rua B, Guarda', 5);
    res := res || ' compras_2=PASSOU(MAU)';
  EXCEPTION WHEN raise_exception THEN res := res || ' compras_2=RECUSADO'; END;
  BEGIN
    INSERT INTO public.orders(id, user_id, service_type, status, pickup_address, dropoff_address, price)
    VALUES ('prova-b2-c3', v_uid, 'carryGroceries', 'created', 'Lidl Guarda', 'Rua B, Guarda', 5);
    res := res || ' compras_outra_loja=ok';
  EXCEPTION WHEN raise_exception THEN res := res || ' compras_outra_loja=RECUSADO(MAU)'; END;

  RAISE EXCEPTION 'PROVA B2 (desfeita): %', res;
END $prova$;
