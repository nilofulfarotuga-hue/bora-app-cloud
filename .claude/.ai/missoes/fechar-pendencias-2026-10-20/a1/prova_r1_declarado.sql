-- PROVA A1 · ronda 1 (defeito E) — corre DEPOIS da migração do tipo declarado preso ao
-- pedido, no MESMO lote, e acaba em RAISE EXCEPTION (tudo desfeito). Cliente demo.
do $prova$
declare
  c_cli constant uuid := 'e3c166d2-5e20-4d2d-b4d9-fcd4867805a5';
  r public.tvde_rides; j jsonb; v jsonb := '{}'::jsonb; v_n int;
  v_t0 timestamptz := date_trunc('hour', now()) + interval '3 hours';
begin
  update public.platform_settings set value = 'true'::jsonb where key = 'tvde_encomendas_enabled';
  perform set_config('request.jwt.claim.sub', c_cli::text, true);
  perform set_config('request.jwt.claims', json_build_object('sub', c_cli, 'role', 'authenticated')::text, true);
  perform set_config('role', 'authenticated', true);

  -- ATAQUE do revisor: encomenda por cartão declarada, a Edge falha antes de criar a corrida,
  -- e o cliente pede um Bora Motorista a DINHEIRO (como a app faz: sem p_ride_kind).
  perform public.tvde_definir_tipo_pedido('encomendas', 'card', 40.5373, -7.2675, 40.5500, -7.2675);
  r := public.tvde_request_ride(40.5373, -7.2675, 'A', 40.5500, -7.2675, 'B', 3.0, 'cash', 0);
  v := v || jsonb_build_object('E1_ataque_dinheiro_mesmo_trajecto', r.ride_kind);
  perform set_config('role', 'postgres', true);
  select count(*) into v_n from public.tvde_tipo_pedido where client_id = c_cli;
  v := v || jsonb_build_object('E1_declaracao_gasta', v_n = 0);
  perform set_config('role', 'authenticated', true);
  perform public.tvde_cancel_ride(r.id, 'cliente', 'prova_a1_r1');

  -- variantes: outro trajecto pelo cartão; o mesmo trajecto por MB Way; declaração velha
  perform public.tvde_definir_tipo_pedido('encomendas', 'card', 40.5373, -7.2675, 40.5500, -7.2675);
  r := public.tvde_request_ride(p_origin_lat => 40.5373, p_origin_lng => -7.2675, p_origin_label => 'A',
         p_dest_lat => 40.5800, p_dest_lng => -7.2675, p_dest_label => 'D',
         p_est_distance_km => 7.0, p_payment_method => 'card', p_tokens_to_apply => 0);
  v := v || jsonb_build_object('E2_cartao_outro_trajecto', r.ride_kind);
  perform public.tvde_cancel_ride(r.id, 'cliente', 'prova_a1_r1');

  perform public.tvde_definir_tipo_pedido('encomendas', 'card', 40.5373, -7.2675, 40.5500, -7.2675);
  r := public.tvde_request_ride(p_origin_lat => 40.5373, p_origin_lng => -7.2675, p_origin_label => 'A',
         p_dest_lat => 40.5500, p_dest_lng => -7.2675, p_dest_label => 'B',
         p_est_distance_km => 3.0, p_payment_method => 'mbway', p_tokens_to_apply => 0);
  v := v || jsonb_build_object('E3_mbway_quando_declarou_cartao', r.ride_kind);
  perform public.tvde_cancel_ride(r.id, 'cliente', 'prova_a1_r1');

  perform public.tvde_definir_tipo_pedido('encomendas', 'card', 40.5373, -7.2675, 40.5500, -7.2675);
  perform set_config('role', 'postgres', true);
  update public.tvde_tipo_pedido set definido_em = now() - interval '3 minutes' where client_id = c_cli;
  perform set_config('role', 'authenticated', true);
  r := public.tvde_request_ride(p_origin_lat => 40.5373, p_origin_lng => -7.2675, p_origin_label => 'A',
         p_dest_lat => 40.5500, p_dest_lng => -7.2675, p_dest_label => 'B',
         p_est_distance_km => 3.0, p_payment_method => 'card', p_tokens_to_apply => 0);
  v := v || jsonb_build_object('E4_declaracao_com_3_min', r.ride_kind);
  perform public.tvde_cancel_ride(r.id, 'cliente', 'prova_a1_r1');

  -- dinheiro com p_ride_kind explícito também gasta (e não herda)
  perform public.tvde_definir_tipo_pedido('encomendas', 'card', 40.5373, -7.2675, 40.5500, -7.2675);
  r := public.tvde_request_ride(40.5373, -7.2675, 'A', 40.5500, -7.2675, 'B', 3.0, 'cash', 0, 'passageiros');
  v := v || jsonb_build_object('E5_dinheiro_passageiros_explicito', r.ride_kind);
  perform public.tvde_cancel_ride(r.id, 'cliente', 'prova_a1_r1');
  r := public.tvde_request_ride(p_origin_lat => 40.5373, p_origin_lng => -7.2675, p_origin_label => 'A',
         p_dest_lat => 40.5500, p_dest_lng => -7.2675, p_dest_label => 'B',
         p_est_distance_km => 3.0, p_payment_method => 'card', p_tokens_to_apply => 0);
  v := v || jsonb_build_object('E5b_cartao_a_seguir_sem_declaracao', r.ride_kind);
  perform public.tvde_cancel_ride(r.id, 'cliente', 'prova_a1_r1');

  -- CAMINHO LEGÍTIMO: declarar e a Edge criar a corrida do MESMO pagamento
  perform public.tvde_definir_tipo_pedido('encomendas', 'card', 40.5373, -7.2675, 40.5500, -7.2675);
  r := public.tvde_request_ride(p_origin_lat => 40.5373, p_origin_lng => -7.2675, p_origin_label => 'A',
         p_dest_lat => 40.5500, p_dest_lng => -7.2675, p_dest_label => 'B',
         p_est_distance_km => 3.0, p_payment_method => 'card', p_tokens_to_apply => 0);
  v := v || jsonb_build_object('L1_encomenda_cartao', jsonb_build_object('kind', r.ride_kind, 'cliente', r.est_fare_cents, 'motorista', r.driver_earn_cents));
  perform public.tvde_cancel_ride(r.id, 'cliente', 'prova_a1_r1');

  perform public.tvde_definir_tipo_pedido('encomendas', 'mbway', 40.5373, -7.2675, 40.5700, -7.2675);
  r := public.tvde_schedule_ride(p_origin_lat => 40.5373, p_origin_lng => -7.2675, p_origin_label => 'A',
         p_dest_lat => 40.5700, p_dest_lng => -7.2675, p_dest_label => 'H', p_est_distance_km => 5.0,
         p_scheduled_at => v_t0, p_payment_method => 'mbway', p_note => null);
  v := v || jsonb_build_object('L2_reserva_mbway', jsonb_build_object('kind', r.ride_kind, 'cliente', r.est_fare_cents, 'motorista', r.driver_earn_cents));
  perform public.tvde_cancel_reservation(r.id, 'prova_a1_r1');

  perform public.tvde_definir_tipo_pedido('encomendas', 'card', 40.5373, -7.2675, 40.6200, -7.2675);
  j := public.tvde_schedule_roundtrip(p_origin_lat => 40.5373, p_origin_lng => -7.2675, p_origin_label => 'A',
         p_dest_lat => 40.6200, p_dest_lng => -7.2675, p_dest_label => 'P', p_est_distance_km => 10.0,
         p_outbound_at => v_t0 + interval '3 hours', p_return_at => v_t0 + interval '5 hours',
         p_payment_method => 'card', p_note => null);
  v := v || jsonb_build_object('L3_ida_e_volta_cartao', jsonb_build_object('ida', j->'ida'->>'ride_kind', 'volta', j->'volta'->>'ride_kind',
         'preco', j->>'price_cents', 'ganho_ida', j->'ida'->>'driver_earn_cents', 'ganho_volta', j->'volta'->>'driver_earn_cents'));
  perform public.tvde_cancel_reservation((j->'ida'->>'id')::uuid, 'prova_a1_r1');

  -- passageiros de sempre (chamada antiga, 9 argumentos), sem declaração
  r := public.tvde_request_ride(40.5373, -7.2675, 'A', 40.5500, -7.2675, 'B', 3.0, 'cash', 0);
  v := v || jsonb_build_object('P1_passageiros_antigo', jsonb_build_object('kind', r.ride_kind, 'cliente', r.est_fare_cents, 'motorista', r.driver_earn_cents));
  perform public.tvde_cancel_ride(r.id, 'cliente', 'prova_a1_r1');

  -- declarar a dinheiro é recusado (não há Edge nesse caminho)
  begin
    perform public.tvde_definir_tipo_pedido('encomendas', 'cash', 40.5373, -7.2675, 40.5500, -7.2675);
    v := v || jsonb_build_object('D1_declarar_dinheiro_recusado', false);
  exception when others then
    v := v || jsonb_build_object('D1_declarar_dinheiro_recusado', sqlerrm like 'invalid_payment_method%');
  end;

  perform set_config('role', 'postgres', true);
  v := v || jsonb_build_object(
    'md5_rpcs', (select jsonb_object_agg(p.proname, md5(p.prosrc)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname in ('tvde_request_ride','tvde_schedule_ride','tvde_schedule_roundtrip')),
    'assinaturas_resolver', (select count(*) from pg_proc where proname = '_tvde_ride_kind_resolver'),
    'assinaturas_definir', (select count(*) from pg_proc where proname = 'tvde_definir_tipo_pedido'),
    'anon_definir', has_function_privilege('anon', 'public.tvde_definir_tipo_pedido(text,text,double precision,double precision,double precision,double precision)', 'execute'),
    'cliente_resolver', has_function_privilege('authenticated', 'public._tvde_ride_kind_resolver(uuid,text,text,double precision,double precision,double precision,double precision)', 'execute'),
    'acl_rpcs', (select jsonb_object_agg(p.proname, p.proacl::text) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname in ('tvde_request_ride','tvde_schedule_ride','tvde_schedule_roundtrip')),
    'md5_intactas', (select jsonb_object_agg(p.proname, md5(p.prosrc)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname in ('tvde_offer_to_next','tvde_calculate_fare','tvde_quote_roundtrip',
          'tvde_roundtrip_price_for_km','tvde_fare_breakdown','tvde_finish_ride','tvde_cancel_ride','tvde_accept_ride',
          'compute_driver_settlement','tvde_dispatch_sweep','_tvde_exige_acesso','tvde_reservation_offer_to_next')));
  raise exception 'RESULT %', v::text;
end $prova$;
