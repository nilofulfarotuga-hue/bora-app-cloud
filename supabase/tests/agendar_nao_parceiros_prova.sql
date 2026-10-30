-- Prova do agendar nos mercados (tudo desfeito no fim pelo RAISE EXCEPTION).
DO $prova$
DECLARE
  u      uuid := 'd66d1522-ad8e-426e-9a75-76d636004186';  -- cliente de teste (boraapp.test)
  amanha date := (now() AT TIME ZONE 'Europe/Lisbon')::date + 1;
  t10    timestamptz := (amanha::timestamp + interval '10 hours') AT TIME ZONE 'Europe/Lisbon';
  t03    timestamptz := (amanha::timestamp + interval '3 hours') AT TIME ZONE 'Europe/Lisbon';
  rest   record;
  p_in   jsonb;
  w      jsonb;
  r      jsonb;
  oid    text;
  o      record;
  n      integer;
  sai    text := '';
  falhas integer := 0;
BEGIN
  SELECT id, name, address, lat, lng INTO rest FROM public.restaurants WHERE id = 'continente-guarda';
  p_in := jsonb_build_object(
    'service_type', 'storeShopping', 'vendor_name', rest.name, 'is_partner_store', false,
    'distance_km', 2.0, 'payment_method', 'cash', 'subtotal', 5.97, 'apartment_delivery', false,
    'order_type', 'delivery', 'bag_count', 1, 'requires_car', false, 'wallet_applied_cents', 0,
    'pickup_lat', rest.lat, 'pickup_lng', rest.lng, 'pickup_address', rest.address,
    'dropoff_lat', 40.5373, 'dropoff_lng', -7.2676, 'dropoff_address', 'Rua de teste, Guarda',
    'customer_name', 'Teste agendar', 'client_phone', '912345678',
    'items', jsonb_build_array(jsonb_build_object('product_id', 'cont-2003649', 'quantity', 1, 'name', 'Atum', 'price', 5.97)),
    'product_lines', jsonb_build_array(jsonb_build_object('product_id', 'cont-2003649', 'quantity', 1, 'unit_price', 5.19, 'name', 'Atum')));

  -- P1: janelas de amanhã no Continente (não parceiro)
  w := public._sched_windows_core('continente-guarda', amanha, 0);
  IF jsonb_array_length(w) > 0 AND EXISTS (SELECT 1 FROM jsonb_array_elements(w) x WHERE (x->>'inicio')::timestamptz = t10) THEN
    sai := sai || format(' P1 ok(%s janelas amanha, inclui 10:00-10:30)', jsonb_array_length(w));
  ELSE falhas := falhas + 1; sai := sai || ' P1 FALHOU ' || left(w::text, 200); END IF;

  PERFORM set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);

  -- P2: sem hora, com a loja fechada agora: STORE_CLOSED como sempre
  BEGIN
    PERFORM public.create_order(p_in);
    sai := sai || ' P2 (loja aberta agora: criou sem hora)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'STORE_CLOSED%' THEN sai := sai || ' P2 ok(sem hora e loja fechada: STORE_CLOSED)';
    ELSE falhas := falhas + 1; sai := sai || ' P2 FALHOU ' || SQLERRM; END IF;
  END;

  -- P3: hora fora das janelas (03:00): recusa e não cria nada
  BEGIN
    PERFORM public.client_create_order_agendado(p_in, t03);
    falhas := falhas + 1; sai := sai || ' P3 FALHOU (aceitou 03:00)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%schedule_window_invalid%' THEN sai := sai || ' P3 ok(03:00 recusado)';
    ELSE falhas := falhas + 1; sai := sai || ' P3 FALHOU ' || SQLERRM; END IF;
  END;

  -- P4: agendado amanhã 10:00 com a loja fechada: o pedido nasce com scheduled_for
  r := public.client_create_order_agendado(p_in, t10);
  oid := COALESCE(r->>'order_id', r->>'id');
  IF oid IS NULL THEN
    SELECT id INTO oid FROM public.orders WHERE user_id = u ORDER BY created_at DESC LIMIT 1;
  END IF;
  SELECT id, status, scheduled_for, service_type, is_partner_store, payment_method, payment_status, total
    INTO o FROM public.orders WHERE id = oid;
  IF o.scheduled_for = t10 AND o.status = 'created' THEN
    sai := sai || format(' P4 ok(pedido %s criado com scheduled_for=%s, status=%s, total=%s)', left(oid, 8), o.scheduled_for, o.status, o.total);
  ELSE falhas := falhas + 1; sai := sai || format(' P4 FALHOU(%s %s %s)', oid, o.scheduled_for, o.status); END IF;

  -- P5: a app do cliente avança created->preparing->callingDriver: fica em preparing, sem estafeta
  UPDATE public.orders SET status = 'preparing' WHERE id = oid;
  UPDATE public.orders SET status = 'callingDriver' WHERE id = oid;
  SELECT status, assigned_driver_id, current_driver_offer_id INTO o FROM public.orders WHERE id = oid;
  SELECT count(*) INTO n FROM public.order_status_events e WHERE e.order_id::text = oid AND e.to_status = 'callingDriver';
  IF o.status = 'preparing' AND o.assigned_driver_id IS NULL AND o.current_driver_offer_id IS NULL AND n = 0 THEN
    sai := sai || ' P5 ok(callingDriver retido: fica preparing, sem oferta, 0 eventos callingDriver)';
  ELSE falhas := falhas + 1; sai := sai || format(' P5 FALHOU(%s, eventos=%s)', o.status, n); END IF;

  -- P6: o relógio antes da hora não mexe
  n := public.agendados_nao_parceiros_despachar();
  SELECT status INTO o FROM public.orders WHERE id = oid;
  IF o.status = 'preparing' THEN sai := sai || format(' P6 ok(antes da hora o relogio deixa estar; despachou %s)', n);
  ELSE falhas := falhas + 1; sai := sai || ' P6 FALHOU ' || o.status; END IF;

  -- P7: chegou a hora (simulada): o relógio passa a callingDriver
  PERFORM set_config('request.jwt.claims', '', true);
  UPDATE public.orders SET scheduled_for = now() + interval '20 minutes' WHERE id = oid;
  n := public.agendados_nao_parceiros_despachar();
  SELECT status INTO o FROM public.orders WHERE id = oid;
  IF o.status = 'callingDriver' THEN sai := sai || format(' P7 ok(na hora: callingDriver pelo relogio, %s pedido)', n);
  ELSE falhas := falhas + 1; sai := sai || ' P7 FALHOU ' || o.status; END IF;

  SELECT count(*) INTO n FROM public.order_lifecycle_errors WHERE order_id::text = oid;
  sai := sai || format(' | erros_ciclo=%s', n);
  RAISE EXCEPTION 'PROVA(rollback) falhas=% :%', falhas, sai;
END
$prova$;
-- Prova da marcação prévia (tudo desfeito no fim pelo RAISE EXCEPTION).
DO $prova$
DECLARE
  u      uuid := 'd66d1522-ad8e-426e-9a75-76d636004186';
  amanha date := (now() AT TIME ZONE 'Europe/Lisbon')::date + 1;
  t10    timestamptz := (amanha::timestamp + interval '10 hours') AT TIME ZONE 'Europe/Lisbon';
  t03    timestamptz := (amanha::timestamp + interval '3 hours') AT TIME ZONE 'Europe/Lisbon';
  rest   record;
  p_in   jsonb;
  r      jsonb;
  oid    text;
  o      record;
  n      integer;
  sai    text := '';
  falhas integer := 0;
BEGIN
  SELECT id, name, address, lat, lng INTO rest FROM public.restaurants WHERE id = 'continente-guarda';
  p_in := jsonb_build_object(
    'service_type', 'storeShopping', 'vendor_name', rest.name, 'is_partner_store', false,
    'distance_km', 2.0, 'payment_method', 'cash', 'subtotal', 5.97, 'apartment_delivery', false,
    'order_type', 'delivery', 'bag_count', 1, 'requires_car', false, 'wallet_applied_cents', 0,
    'pickup_lat', rest.lat, 'pickup_lng', rest.lng, 'pickup_address', rest.address,
    'dropoff_lat', 40.5373, 'dropoff_lng', -7.2676, 'dropoff_address', 'Rua de teste, Guarda',
    'customer_name', 'Teste agendar', 'client_phone', '912345678',
    'items', jsonb_build_array(jsonb_build_object('product_id', 'cont-2003649', 'quantity', 1, 'name', 'Atum', 'price', 5.97)),
    'product_lines', jsonb_build_array(jsonb_build_object('product_id', 'cont-2003649', 'quantity', 1, 'unit_price', 5.19, 'name', 'Atum')));
  PERFORM set_config('request.jwt.claims', json_build_object('sub', u, 'role', 'authenticated')::text, true);

  BEGIN
    PERFORM public.client_preparar_agendamento('continente-guarda', t03);
    falhas := falhas + 1; sai := sai || ' Q1 FALHOU (aceitou 03:00)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE '%schedule_window_invalid%' THEN sai := sai || ' Q1 ok(03:00 recusado)';
    ELSE falhas := falhas + 1; sai := sai || ' Q1 FALHOU ' || SQLERRM; END IF;
  END;

  r := public.client_preparar_agendamento('continente-guarda', t10);
  r := public.create_order(p_in);   -- exatamente o que a app já chama
  SELECT id, status, scheduled_for INTO o FROM public.orders WHERE user_id = u ORDER BY created_at DESC LIMIT 1;
  SELECT count(*) INTO n FROM public.pedido_agendamento_pendente WHERE user_id = u AND usado_em IS NOT NULL AND order_id = o.id;
  IF o.scheduled_for = t10 AND o.status = 'created' AND n = 1 THEN
    sai := sai || format(' Q2 ok(create_order de sempre + marcacao: pedido %s com scheduled_for=%s, marcacao usada)', left(o.id, 8), o.scheduled_for);
  ELSE falhas := falhas + 1; sai := sai || format(' Q2 FALHOU(%s %s usada=%s)', o.id, o.scheduled_for, n); END IF;

  r := public.client_preparar_agendamento('continente-guarda', NULL);
  BEGIN
    PERFORM public.create_order(p_in);
    sai := sai || ' Q3 (loja aberta agora: criou sem hora)';
  EXCEPTION WHEN OTHERS THEN
    IF SQLERRM LIKE 'STORE_CLOSED%' THEN sai := sai || ' Q3 ok(Entregar agora apaga a marcacao: loja fechada recusa)';
    ELSE falhas := falhas + 1; sai := sai || ' Q3 FALHOU ' || SQLERRM; END IF;
  END;

  IF position('is_partner_store' in pg_get_functiondef('public.admin_scheduled_orders()'::regprocedure)) > 0 THEN
    sai := sai || ' Q4 ok(painel recebe parceiro/nao-parceiro)';
  ELSE falhas := falhas + 1; sai := sai || ' Q4 FALHOU'; END IF;

  RAISE EXCEPTION 'PROVA(rollback) falhas=% :%', falhas, sai;
END
$prova$;
