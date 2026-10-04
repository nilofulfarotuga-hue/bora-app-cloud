-- Prova do Bloco 3 (gorjeta), em transação DESFEITA (RAISE no fim).
-- Correr DEPOIS de aplicar 20261004100000_gorjetas.sql. Não toca na Stripe.
-- Esperado (ordem): cliente_update_direto=RECUSADO dinheiro_ok=true espelho=200
--   entregue=cash_collected acerto_antes=X acerto_depois=X+3.00 (gorjeta cartão 300)
--   prestador_ve=2 outro_ve=0
DO $prova$
DECLARE
  res text := '';
  v_cli uuid := (SELECT id FROM auth.users WHERE email = 'demo@bora.app' LIMIT 1);
  v_drv uuid := (SELECT user_id FROM public.drivers WHERE approval_status = 'approved' LIMIT 1);
  v_outro uuid := (SELECT id FROM auth.users WHERE email = 'cliente@bora.app' LIMIT 1);
  j jsonb; n int; antes numeric; depois numeric;
BEGIN
  UPDATE public.platform_settings SET value = 'true'::jsonb WHERE key = 'tips_enabled';

  INSERT INTO public.orders(id, user_id, service_type, status, payment_method, pickup_address, dropoff_address, price, assigned_driver_id)
  VALUES ('prova-b3-cash', v_cli, 'restaurant', 'preparing', 'cash', 'Loja', 'Casa', 12, v_drv::text);

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_cli, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  BEGIN
    UPDATE public.orders SET tip_amount_cents = 500 WHERE id = 'prova-b3-cash';
    res := res || 'cliente_update_direto=PASSOU(MAU)';
  EXCEPTION WHEN insufficient_privilege THEN res := res || 'cliente_update_direto=RECUSADO'; END;

  j := public.tip_registar_dinheiro('prova-b3-cash', 200);
  res := res || ' dinheiro_ok=' || (j->>'ok');
  PERFORM set_config('role', 'postgres', true);
  SELECT tip_amount_cents INTO n FROM public.orders WHERE id = 'prova-b3-cash';
  res := res || ' espelho=' || n;

  PERFORM set_config('app.financial_bypass', 'true', true);
  UPDATE public.orders SET status = 'delivered', delivered_at = now() WHERE id = 'prova-b3-cash';
  res := res || ' entregue=' || (SELECT status FROM public.tips WHERE order_id = 'prova-b3-cash');

  antes := (public.compute_driver_settlement(v_drv, now(), false)->>'total_earnings')::numeric;
  -- gorjeta por cartão já paga (como a charge-tip grava depois da Stripe)
  INSERT INTO public.orders(id, user_id, service_type, status, payment_method, pickup_address, dropoff_address, price, assigned_driver_id)
  VALUES ('prova-b3-card', v_cli, 'restaurant', 'delivered', 'card', 'Loja', 'Casa', 15, v_drv::text);
  INSERT INTO public.tips(target, order_id, client_user_id, provider_user_id, amount_cents, method, moment, status, paid_at, stripe_payment_intent_id)
  VALUES ('order', 'prova-b3-card', v_cli, v_drv, 300, 'card', 'after', 'succeeded', now(), 'pi_prova_b3');
  depois := (public.compute_driver_settlement(v_drv, now(), false)->>'total_earnings')::numeric;
  res := res || ' acerto_antes=' || antes || ' acerto_depois=' || depois;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_drv, 'role', 'authenticated')::text, true);
  PERFORM set_config('role', 'authenticated', true);
  SELECT count(*) INTO n FROM public.tips WHERE order_id LIKE 'prova-b3-%';
  res := res || ' prestador_ve=' || n;
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_outro, 'role', 'authenticated')::text, true);
  SELECT count(*) INTO n FROM public.tips WHERE order_id LIKE 'prova-b3-%';
  res := res || ' outro_ve=' || n;

  RAISE EXCEPTION 'PROVA B3 (desfeita): %', res;
END $prova$;
