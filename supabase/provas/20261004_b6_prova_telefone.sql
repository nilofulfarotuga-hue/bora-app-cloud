-- Prova do Bloco 6 (encomenda por telefone), em transação DESFEITA (RAISE no fim).
-- Correr DEPOIS de aplicar 20261004110000_lojas_encomenda_por_telefone.sql.
-- Pedido simulado na Pôr do Sol a dinheiro. Tempo acelerado recuando created_at/encomendado_em.
-- Esperado: b6-1 retido=preparing tarefa=1 alerta=1 | b6-2 aos_3min alertas=2 | b6-3 encomendado ok
--           | b6-4 aos_10min_depois_de_encomendar=preparing | b6-5 aos_15min=callingDriver libertado
--           | resumo com TOTAL BALCÃO
DO $prova$
DECLARE
  res text := '';
  v_cli uuid := (SELECT id FROM auth.users WHERE email = 'demo@bora.app' LIMIT 1);
  v_adm uuid := 'c9fccf85-03ee-4efc-83bf-613f211a78ff';
  v_id text := 'prova-b6-' || substr(md5(random()::text), 1, 6);
  s text; j jsonb;
BEGIN
  -- Nenhum estafeta real pode receber isto: a transação é desfeita no fim e o
  -- despacho (pg_net) só sai no COMMIT.
  INSERT INTO public.orders(id, user_id, service_type, status, payment_method, restaurant_id,
                            vendor_name, pickup_address, dropoff_address, price, customer_name, items)
  VALUES (v_id, v_cli, 'restaurant', 'created', 'cash', 'pordosol-guarda', 'Pôr do Sol Kebab & Pizza House',
          'Rua Formosa 26, Guarda', 'Casa, Guarda', 14.95, 'Cliente Prova',
          '[{"name":"Pizza Margarita (média 28 cm)","price":9.20,"basePrice":8.00,"quantity":1,
             "selected_options":[{"group":"Extras","items":["Queijo extra"]}]},
            {"name":"Pepsi 33cl","price":2.30,"basePrice":2.00,"quantity":2}]'::jsonb);

  UPDATE public.orders SET status = 'callingDriver' WHERE id = v_id;
  SELECT status INTO s FROM public.orders WHERE id = v_id;
  res := res || 'b6-1 retido=' || s
      || ' tarefa=' || (SELECT count(*) FROM public.encomendas_telefone WHERE order_id = v_id)
      || ' alerta=' || (SELECT alertas FROM public.encomendas_telefone WHERE order_id = v_id);

  -- 3 minutos depois, ninguém ligou → 2.º aviso
  UPDATE public.encomendas_telefone SET criado_em = now() - interval '3 minutes 5 seconds' WHERE order_id = v_id;
  PERFORM public.encomendas_telefone_relogio();
  res := res || ' | b6-2 aos_3min alertas=' || (SELECT alertas FROM public.encomendas_telefone WHERE order_id = v_id);

  -- Admin carrega "Encomendado à loja"
  PERFORM set_config('request.jwt.claims', json_build_object('sub', v_adm, 'role', 'authenticated')::text, true);
  j := public.admin_encomendado_a_loja(v_id);
  res := res || ' | b6-3 encomendado=' || (j->>'ok') || ' chama_as=' || COALESCE(j->>'estafeta_chamado_as', '?');
  PERFORM set_config('request.jwt.claims', '', true);

  -- 10 minutos depois da chamada → ainda não chama
  UPDATE public.encomendas_telefone SET encomendado_em = now() - interval '10 minutes' WHERE order_id = v_id;
  PERFORM public.encomendas_telefone_relogio();
  SELECT status INTO s FROM public.orders WHERE id = v_id;
  res := res || ' | b6-4 aos_10min=' || s;

  -- 15 minutos depois da chamada → chama o estafeta
  UPDATE public.encomendas_telefone SET encomendado_em = now() - interval '15 minutes 5 seconds' WHERE order_id = v_id;
  PERFORM public.encomendas_telefone_relogio();
  SELECT status INTO s FROM public.orders WHERE id = v_id;
  res := res || ' | b6-5 aos_15min=' || s
      || ' libertado=' || ((SELECT libertado_em FROM public.encomendas_telefone WHERE order_id = v_id) IS NOT NULL);

  res := res || E'\nRESUMO:\n' || (public.encomenda_telefone_resumo(v_id)->>'texto');
  RAISE EXCEPTION 'PROVA B6 (desfeita): %', res;
END $prova$;
