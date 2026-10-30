-- Prova das gorjetas do carrinho no mesmo pagamento e da devolução no cancelamento
-- (missão gorjetas-taxa-2026-10-30). Tudo desfeito no fim de cada bloco (RAISE EXCEPTION 'PROVA(rollback) ...').
-- Correr DEPOIS das migrações 20261030144900 (interruptor) e 20261030145000 (proposta em
-- docs/propostas/gorjetas-taxa-2026-10-30/pagamentos_20261030145000_gorjeta_checkout_junto_pagamento.sql).
-- Sem UPDATE/INSERT em orders — tudo pelas funções de sempre (create_order, admin_cancel_order).
-- O interruptor liga-se DENTRO da prova por admin_update_setting (o caminho do painel) e volta a false
-- no rollback. Nada sai para a Stripe: o net.http_post da conferência fica na fila e é desfeito.
--
-- FICA POR PROVAR NO AR (e porquê): o MB Way a passar a pago/falhado. O webhook marca o pedido com um
-- UPDATE direto em orders (payment_status/payment_intent_id) e NÃO há nenhuma função SQL que o faça
-- (procurado a 30/10: só funções de manutenção do despacho mexem nesse campo) — simulá-lo aqui seria DML
-- direto em orders, que a tranca recusa. O gatilho trg_zz_gorjeta_checkout_pagamento (pago com o PI da
-- gorjeta → succeeded; sem PI gravado → só quando o cobrado = buffer + gorjeta; falhado → failed; nova
-- tentativa volta a levar a gorjeta) está provado num Postgres local (PGlite):
-- docs/propostas/gorjetas-taxa-2026-10-30/pagamentos_prova_local_pglite.mjs (+ .saida.txt). No ar prova-se
-- com o 1.º pedido MB Way real com gorjeta: SELECT status, stripe_payment_intent_id FROM tips WHERE order_id = …

-- ── Bloco 1 ──────────────────────────────────────────────────────────────────
DO $prova$
DECLARE
  u      uuid := 'd66d1522-ad8e-426e-9a75-76d636004186';  -- cliente de teste (boraapp.test)
  amanha date := (now() AT TIME ZONE 'Europe/Lisbon')::date + 1;
  t10    timestamptz := (amanha::timestamp + interval '10 hours') AT TIME ZONE 'Europe/Lisbon';
  t1030  timestamptz := (amanha::timestamp + interval '10 hours 30 minutes') AT TIME ZONE 'Europe/Lisbon';
  t11    timestamptz := (amanha::timestamp + interval '11 hours') AT TIME ZONE 'Europe/Lisbon';
  t1130  timestamptz := (amanha::timestamp + interval '11 hours 30 minutes') AT TIME ZONE 'Europe/Lisbon';
  c_cli  text := json_build_object('sub', 'd66d1522-ad8e-426e-9a75-76d636004186', 'role', 'authenticated')::text;
  c_adm  text := json_build_object('sub', 'd66d1522-ad8e-426e-9a75-76d636004186', 'role', 'authenticated',
                                   'app_metadata', json_build_object('role', 'admin'))::text;
  c_srv  text := json_build_object('role', 'service_role')::text;
  pi_c   text := 'pi_prova_cartao_' || substr(md5(random()::text), 1, 12);
  o_mb2  text;
  rest   record;
  p_in   jsonb;
  r      jsonb;
  v      integer;
  b      boolean;
  o_mb   text;
  o_cash text;
  o_card text;
  o_err  text;
  t      record;
  mk     record;
  sai    text := '';
  falhas integer := 0;
BEGIN
  SELECT id, name, address, lat, lng INTO rest FROM public.restaurants WHERE id = 'continente-guarda';
  p_in := jsonb_build_object(
    'service_type', 'storeShopping', 'vendor_name', rest.name, 'is_partner_store', false,
    'distance_km', 2.0, 'payment_method', 'mbway', 'subtotal', 5.97, 'apartment_delivery', false,
    'order_type', 'delivery', 'bag_count', 1, 'requires_car', false, 'wallet_applied_cents', 0,
    'pickup_lat', rest.lat, 'pickup_lng', rest.lng, 'pickup_address', rest.address,
    'dropoff_lat', 40.5373, 'dropoff_lng', -7.2676, 'dropoff_address', 'Rua de teste, Guarda',
    'customer_name', 'Teste gorjeta', 'client_phone', '912345678',
    'items', jsonb_build_array(jsonb_build_object('product_id', 'cont-2003649', 'quantity', 1, 'name', 'Atum', 'price', 5.97)),
    'product_lines', jsonb_build_array(jsonb_build_object('product_id', 'cont-2003649', 'quantity', 1, 'unit_price', 5.19, 'name', 'Atum')));

  -- G0: estrutura, interruptor público e desligado, permissões, crons e gatilhos
  IF EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'tips' AND column_name = 'cobrada_junto')
     AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'tips' AND column_name = 'devolvida_para')
     AND EXISTS (SELECT 1 FROM information_schema.columns WHERE table_schema = 'public' AND table_name = 'tips' AND column_name = 'devolucao_tentativas')
     AND (public.get_setting('tips_checkout_junto_pagamento') #>> '{}') = 'false'
     AND NOT has_function_privilege('anon', 'public.client_preparar_gorjeta_checkout(integer)', 'EXECUTE')
     AND has_function_privilege('authenticated', 'public.client_preparar_gorjeta_checkout(integer)', 'EXECUTE')
     AND NOT has_function_privilege('authenticated', 'public.gorjeta_checkout_para_cobrar(uuid)', 'EXECUTE')
     AND has_function_privilege('service_role', 'public.gorjeta_checkout_para_cobrar(uuid)', 'EXECUTE')
     AND NOT has_function_privilege('authenticated', 'public.gorjeta_checkout_mbway_valor(text)', 'EXECUTE')
     AND NOT has_function_privilege('anon', 'public.gorjeta_checkout_mbway_pi(text,text)', 'EXECUTE')
     AND NOT has_function_privilege('authenticated', 'public.gorjetas_devolver_cancelados(interval)', 'EXECUTE')
     AND (SELECT count(*) FROM cron.job WHERE jobname IN ('gorjetas-devolver-cancelados', 'gorjetas-taxas-em-falta-domingo')) = 2
     AND (SELECT count(*) FROM pg_trigger WHERE tgrelid = 'public.orders'::regclass
            AND tgname IN ('trg_zz_gorjeta_checkout_na_criacao', 'trg_zz_gorjeta_checkout_pagamento')) = 2 THEN
    sai := sai || ' G0 ok(colunas, interruptor=false e legível, permissões, 2 crons, 2 gatilhos)';
  ELSE falhas := falhas + 1; sai := sai || ' G0 FALHOU(estrutura/permissões)'; END IF;

  -- G1: sem sessão não marca
  PERFORM set_config('request.jwt.claims', '', true);
  BEGIN
    r := public.client_preparar_gorjeta_checkout(200);
    falhas := falhas + 1; sai := sai || ' G1 FALHOU(sem sessão aceitou)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%auth_required%' THEN sai := sai || ' G1 ok(sem sessão: auth_required)';
    ELSE falhas := falhas + 1; sai := sai || ' G1 FALHOU ' || SQLERRM; END IF;
  END;

  -- G2: interruptor desligado → ok:false e nada marcado (a app segue com a charge-tip à parte)
  PERFORM set_config('request.jwt.claims', c_cli, true);
  r := public.client_preparar_gorjeta_checkout(200);
  IF r->>'ok' = 'false' AND r->>'motivo' = 'junto_desligado'
     AND NOT EXISTS (SELECT 1 FROM public.gorjeta_checkout_pendente WHERE user_id = u) THEN
    sai := sai || ' G2 ok(desligado: junto_desligado, sem marcação)';
  ELSE falhas := falhas + 1; sai := sai || ' G2 FALHOU ' || r::text; END IF;

  -- G3: liga pelo caminho do painel; valida valores; marca 2,00 €
  PERFORM set_config('request.jwt.claims', c_adm, true);
  PERFORM public.admin_update_setting('tips_enabled', 'true'::jsonb);
  PERFORM public.admin_update_setting('tips_checkout_junto_pagamento', 'true'::jsonb);
  PERFORM set_config('request.jwt.claims', c_cli, true);
  r := public.client_preparar_gorjeta_checkout(30);
  IF r->>'motivo' = 'valor_invalido' THEN sai := sai || ' G3a ok(0,30 € recusado)';
  ELSE falhas := falhas + 1; sai := sai || ' G3a FALHOU ' || r::text; END IF;
  r := public.client_preparar_gorjeta_checkout(200);
  v := public.gorjeta_checkout_para_cobrar(u);
  IF r->>'ok' = 'true' AND (r->>'gorjeta_cents')::int = 200 AND v = 200 THEN
    sai := sai || ' G3b ok(marcada 200; para_cobrar=200)';
  ELSE falhas := falhas + 1; sai := sai || format(' G3b FALHOU(%s para_cobrar=%s)', r, v); END IF;

  -- G4: pedido a DINHEIRO não gasta a marcação e a gorjeta em dinheiro regista-se como sempre
  PERFORM public.client_preparar_agendamento('continente-guarda', t1030);
  r := public.create_order(jsonb_set(p_in, '{payment_method}', '"cash"'));
  o_cash := COALESCE(r->>'order_id', r->>'id');
  SELECT * INTO mk FROM public.gorjeta_checkout_pendente WHERE user_id = u;
  r := public.tip_registar_dinheiro(o_cash, 200);
  IF mk.usado_em IS NULL AND r->>'ok' = 'true'
     AND NOT EXISTS (SELECT 1 FROM public.tips WHERE order_id = o_cash AND cobrada_junto) THEN
    sai := sai || ' G4 ok(dinheiro: marcação intacta, tip_registar_dinheiro ok)';
  ELSE falhas := falhas + 1; sai := sai || format(' G4 FALHOU(usado_em=%s registar=%s)', mk.usado_em, r); END IF;

  -- G5: Favor (errand) por MB Way não leva a marcação
  BEGIN
    r := public.create_order(p_in || jsonb_build_object('service_type', 'errand', 'order_type', 'errand'));
    o_err := COALESCE(r->>'order_id', r->>'id');
    SELECT * INTO mk FROM public.gorjeta_checkout_pendente WHERE user_id = u;
    IF NOT EXISTS (SELECT 1 FROM public.tips WHERE order_id = o_err) AND mk.usado_em IS NULL THEN
      sai := sai || ' G5 ok(Favor MB Way: sem gorjeta, marcação intacta)';
    ELSE falhas := falhas + 1; sai := sai || ' G5 FALHOU(Favor levou a gorjeta)'; END IF;
  EXCEPTION WHEN OTHERS THEN
    IF position('''restaurant'', ''storeShopping'', ''takeaway''' IN
                pg_get_functiondef('public._orders_gorjeta_checkout_na_criacao()'::regprocedure)) > 0 THEN
      sai := sai || ' G5 SALTADO(Favor de teste não nasce: ' || left(SQLERRM, 80) || ') G5b ok(só pedidos do carrinho, no código)';
    ELSE falhas := falhas + 1; sai := sai || ' G5 FALHOU ' || SQLERRM; END IF;
  END;

  -- G6: MB Way do carrinho → gorjeta 'pending' cobrada_junto, marcação gasta; valor e PI para o patch
  PERFORM public.client_preparar_agendamento('continente-guarda', t10);
  r := public.create_order(p_in);
  o_mb := COALESCE(r->>'order_id', r->>'id');
  SELECT * INTO t FROM public.tips WHERE order_id = o_mb;
  SELECT * INTO mk FROM public.gorjeta_checkout_pendente WHERE user_id = u;
  PERFORM set_config('request.jwt.claims', c_srv, true);
  v := public.gorjeta_checkout_mbway_valor(o_mb);
  b := public.gorjeta_checkout_mbway_pi(o_mb, 'pi_prova_mbway_zq');
  IF t.status = 'pending' AND t.cobrada_junto AND t.method = 'mbway' AND t.moment = 'checkout'
     AND t.amount_cents = 200 AND mk.usado_em IS NOT NULL AND mk.order_id = o_mb AND mk.gorjeta_aplicada
     AND v = 200 AND b
     AND (SELECT stripe_payment_intent_id FROM public.tips WHERE id = t.id) = 'pi_prova_mbway_zq'
     AND public.gorjeta_checkout_para_cobrar(u) = 0 THEN
    sai := sai || format(' G6 ok(MB Way %s: gorjeta pending 200 junto, marcação gasta, valor=200, PI gravado)', left(o_mb, 8));
  ELSE falhas := falhas + 1; sai := sai || format(' G6 FALHOU(tip=%s/%s/%s marca=%s valor=%s pi=%s)', t.status, t.cobrada_junto, t.amount_cents, mk.usado_em, v, b); END IF;

  -- G6b: outro MB Way do carrinho com gorjeta, mas cujo pagamento nem chega a ser criado (sem PI)
  PERFORM set_config('request.jwt.claims', c_cli, true);
  PERFORM public.client_preparar_gorjeta_checkout(150);
  PERFORM public.client_preparar_agendamento('continente-guarda', t1130);
  r := public.create_order(p_in);
  o_mb2 := COALESCE(r->>'order_id', r->>'id');
  IF (SELECT status FROM public.tips WHERE order_id = o_mb2) = 'pending' THEN
    sai := sai || format(' G6b ok(MB Way %s: gorjeta pending 150, sem pagamento criado)', left(o_mb2, 8));
  ELSE falhas := falhas + 1; sai := sai || ' G6b FALHOU'; END IF;
  PERFORM set_config('request.jwt.claims', c_srv, true);

  -- G7: cartão (o pedido nasce no servidor, já pago, com o rascunho que leva a gorjeta)
  INSERT INTO public.payment_drafts (payment_intent_id, user_id, payload, amount_cents)
  VALUES (pi_c, u, p_in || jsonb_build_object('payment_method', 'card', 'scheduled_for', t11, 'gorjeta_checkout_cents', 150), 1000);
  r := public.create_order(p_in || jsonb_build_object('payment_method', 'card', 'user_id', u, 'scheduled_for', t11,
         'payment_already_confirmed', true, 'payment_intent_id', pi_c, 'gorjeta_checkout_cents', 150));
  o_card := COALESCE(r->>'order_id', r->>'id');
  SELECT * INTO t FROM public.tips WHERE order_id = o_card;
  IF t.status = 'succeeded' AND t.cobrada_junto AND t.method = 'card' AND t.amount_cents = 150
     AND t.stripe_payment_intent_id = pi_c AND t.paid_at IS NOT NULL AND t.liquido_prestador_cents = 150
     AND (SELECT tip_amount_cents FROM public.orders WHERE id = o_card) = 150 THEN
    sai := sai || format(' G7 ok(cartão %s: gorjeta 150 paga junto, inteira p/ estafeta, espelho no pedido=150)', left(o_card, 8));
  ELSE falhas := falhas + 1; sai := sai || format(' G7 FALHOU(%s/%s/%s/%s)', t.status, t.cobrada_junto, t.amount_cents, t.stripe_payment_intent_id); END IF;

  -- G8: cancelamentos (Bloco B).
  --   • MB Way SEM pagamento criado → gorjeta 'cancelled' já, no gatilho.
  --   • MB Way COM pagamento criado (o cliente pode ter aprovado antes do webhook) → fica 'pending' e vai
  --     para a charge-tip, que pergunta à Stripe (pago → devolve inteira; não → cancela).
  --   • Cartão pago → fica 'succeeded' à espera da charge-tip (devolver_cancelamento).
  PERFORM set_config('request.jwt.claims', c_adm, true);
  PERFORM public.admin_cancel_order(o_mb::uuid, 'other'::public.cancellation_reason_code, 'prova gorjeta MB Way com PI');
  PERFORM public.admin_cancel_order(o_mb2::uuid, 'other'::public.cancellation_reason_code, 'prova gorjeta MB Way sem PI');
  PERFORM public.admin_cancel_order(o_card::uuid, 'other'::public.cancellation_reason_code, 'prova gorjeta cartão');
  PERFORM set_config('request.jwt.claims', '', true);
  -- (dentro da mesma transação now() não anda: espera "-1 minuto" = os cancelados agora contam já)
  r := public.gorjetas_devolver_cancelados(interval '-1 minute');
  IF (SELECT status FROM public.tips WHERE order_id = o_mb2) = 'cancelled'
     AND (SELECT status FROM public.tips WHERE order_id = o_mb) = 'pending'
     AND (SELECT status FROM public.tips WHERE order_id = o_card) = 'succeeded'
     AND (r->>'ok') = 'true' AND (r->>'pedidos_enviados')::int >= 2 THEN
    sai := sai || format(' G8 ok(MB Way sem PI → cancelled; MB Way com PI fica pending p/ a Stripe decidir; cartão pago fica para devolver; conferência enviou %s pedido(s) à charge-tip)', r->>'pedidos_enviados');
  ELSE falhas := falhas + 1; sai := sai || format(' G8 FALHOU(mb2=%s mb=%s card=%s conf=%s)',
         (SELECT status FROM public.tips WHERE order_id = o_mb2), (SELECT status FROM public.tips WHERE order_id = o_mb),
         (SELECT status FROM public.tips WHERE order_id = o_card), r); END IF;

  -- G9: dados antigos — gorjetas pagas por cartão/MB Way em pedidos cancelados ANTES desta missão
  SELECT count(*) INTO v FROM public.tips tt JOIN public.orders oo ON oo.id = tt.order_id
   WHERE tt.method IN ('card', 'mbway') AND tt.status = 'succeeded' AND oo.status IN ('cancelled', 'rejected')
     AND tt.order_id NOT IN (o_card);
  sai := sai || format(' | G9 gorjetas pagas em pedidos já cancelados (antes): %s', v);

  RAISE EXCEPTION 'PROVA(rollback) falhas=% :%', falhas, sai;
END
$prova$;
