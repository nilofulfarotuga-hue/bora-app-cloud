-- PROVA A1 (dinheiro) — corre DEPOIS de supabase/migrations/20261021083257+083355+083510 (encomendas_*) no MESMO lote e acaba em
-- RAISE EXCEPTION: tudo volta atrás (migrações incluídas). Os pg_net feitos
-- dentro de uma transacção desfeita não saem (memória prova-em-rollback-armadilhas-tvde):
-- nenhum motorista real é avisado. Cliente demo.cliente@bora.app (e3c166d2…).
do $prova$
declare
  c_cli constant uuid := 'e3c166d2-5e20-4d2d-b4d9-fcd4867805a5';
  v_kinds text[] := array['passageiros', 'encomendas'];
  v_k text;
  r public.tvde_rides;
  j jsonb;
  v_lin jsonb := '[]'::jsonb;
  v_chk jsonb := '{}'::jsonb;
  v_err text;
  v_n int;
  v_t0 timestamptz := date_trunc('hour', now()) + interval '3 hours';
begin
  -- encomendas ligadas SÓ dentro desta transacção
  update public.platform_settings set value = 'true'::jsonb where key = 'tvde_encomendas_enabled';

  perform set_config('request.jwt.claim.sub', c_cli::text, true);
  perform set_config('request.jwt.claims',
    json_build_object('sub', c_cli, 'role', 'authenticated', 'email', 'demo.cliente@bora.app')::text, true);
  perform set_config('role', 'authenticated', true);

  foreach v_k in array v_kinds loop
    -- C1: corrida/entrega na hora, dinheiro, 3 km
    if v_k = 'passageiros' then
      -- chamada ANTIGA (como as versões instaladas e a Edge: sem p_ride_kind)
      r := public.tvde_request_ride(p_origin_lat => 40.5373, p_origin_lng => -7.2675, p_origin_label => 'Sé da Guarda',
             p_dest_lat => 40.5500, p_dest_lng => -7.2675, p_dest_label => 'Guarda Gare',
             p_est_distance_km => 3.0, p_payment_method => 'cash', p_tokens_to_apply => 0);
    else
      r := public.tvde_request_ride(p_origin_lat => 40.5373, p_origin_lng => -7.2675, p_origin_label => 'Sé da Guarda',
             p_dest_lat => 40.5500, p_dest_lng => -7.2675, p_dest_label => 'Guarda Gare',
             p_est_distance_km => 3.0, p_payment_method => 'cash', p_tokens_to_apply => 0, p_ride_kind => v_k);
    end if;
    v_lin := v_lin || jsonb_build_object('cot', 'C1 na hora dinheiro 3 km', 'pedido', v_k, 'ride_kind', r.ride_kind,
               'cliente_cents', r.est_fare_cents, 'motorista_cents', r.driver_earn_cents, 'bora_cents', r.bora_cut_cents,
               'km', r.est_distance_km);
    perform public.tvde_cancel_ride(r.id, 'cliente', 'prova_a1_rollback');

    -- C2: na hora, dinheiro, 12 km
    r := public.tvde_request_ride(40.5373, -7.2675, 'Sé da Guarda', 40.6100, -7.2675, 'Vila Fernando',
           12.0, 'cash', 0, case when v_k = 'passageiros' then null else v_k end);
    v_lin := v_lin || jsonb_build_object('cot', 'C2 na hora dinheiro 12 km', 'pedido', v_k, 'ride_kind', r.ride_kind,
               'cliente_cents', r.est_fare_cents, 'motorista_cents', r.driver_earn_cents, 'bora_cents', r.bora_cut_cents,
               'km', r.est_distance_km);
    perform public.tvde_cancel_ride(r.id, 'cliente', 'prova_a1_rollback');

    -- C3: na hora, CARTÃO, 7 km — caminho da Edge tvde-payment: sem p_ride_kind;
    -- a encomenda vai pelo tipo DECLARADO (tvde_definir_tipo_pedido) mesmo antes.
    if v_k = 'encomendas' then
      perform public.tvde_definir_tipo_pedido('encomendas');
    end if;
    r := public.tvde_request_ride(p_origin_lat => 40.5373, p_origin_lng => -7.2675, p_origin_label => 'Sé da Guarda',
           p_dest_lat => 40.5800, p_dest_lng => -7.2675, p_dest_label => 'Guarda Norte',
           p_est_distance_km => 7.0, p_payment_method => 'card', p_tokens_to_apply => 0);
    v_lin := v_lin || jsonb_build_object('cot', 'C3 na hora cartao 7 km (caminho Edge)', 'pedido', v_k, 'ride_kind', r.ride_kind,
               'cliente_cents', r.est_fare_cents, 'motorista_cents', r.driver_earn_cents, 'bora_cents', r.bora_cut_cents,
               'km', r.est_distance_km);
    perform set_config('role', 'postgres', true);
    select count(*) into v_n from public.tvde_tipo_pedido where client_id = c_cli;
    v_chk := v_chk || jsonb_build_object('declarado_consumido_' || v_k, v_n = 0);
    perform set_config('role', 'authenticated', true);
    perform public.tvde_cancel_ride(r.id, 'cliente', 'prova_a1_rollback');

    -- C4: IDA-E-VOLTA marcada, dinheiro, 10 km (ida +3h, volta +5h)
    j := public.tvde_schedule_roundtrip(40.5373, -7.2675, 'Sé da Guarda', 40.6200, -7.2675, 'Pêra do Moço',
           10.0, v_t0, v_t0 + interval '2 hours', 'cash', null, case when v_k = 'passageiros' then null else v_k end);
    v_lin := v_lin || jsonb_build_object('cot', 'C4 ida-e-volta marcada dinheiro 10 km', 'pedido', v_k,
               'ride_kind', j->'ida'->>'ride_kind', 'ride_kind_volta', j->'volta'->>'ride_kind',
               'cliente_cents', (j->>'price_cents')::int,
               'motorista_cents', (j->'ida'->>'driver_earn_cents')::int + (j->'volta'->>'driver_earn_cents')::int,
               'motorista_ida_cents', (j->'ida'->>'driver_earn_cents')::int,
               'motorista_volta_cents', (j->'volta'->>'driver_earn_cents')::int,
               'km', (j->'ida'->>'est_distance_km')::numeric);
    perform public.tvde_cancel_reservation((j->'ida'->>'id')::uuid, 'prova_a1_rollback');
    begin
      perform public.tvde_cancel_reservation((j->'volta'->>'id')::uuid, 'prova_a1_rollback');
    exception when others then null;  -- a volta já cai com a ida (gatilho do ciclo); só limpeza da prova
    end;

    -- C5: RESERVA marcada simples, dinheiro, 5 km (+6h)
    r := public.tvde_schedule_ride(40.5373, -7.2675, 'Sé da Guarda', 40.5700, -7.2675, 'Guarda Hospital',
           5.0, v_t0 + interval '3 hours', 'cash', null, case when v_k = 'passageiros' then null else v_k end);
    v_lin := v_lin || jsonb_build_object('cot', 'C5 reserva marcada dinheiro 5 km', 'pedido', v_k, 'ride_kind', r.ride_kind,
               'cliente_cents', r.est_fare_cents, 'motorista_cents', r.driver_earn_cents, 'bora_cents', r.bora_cut_cents,
               'km', r.est_distance_km);
    perform public.tvde_cancel_reservation(r.id, 'prova_a1_rollback');
  end loop;

  -- portões --------------------------------------------------------------------
  begin
    perform public.tvde_request_ride(40.5373, -7.2675, 'x', 40.55, -7.2675, 'y', 3.0, 'cash', 0, 'boleia');
    v_chk := v_chk || jsonb_build_object('tipo_invalido_recusado', false);
  exception when others then
    v_chk := v_chk || jsonb_build_object('tipo_invalido_recusado', sqlerrm like 'invalid_ride_kind%');
  end;

  perform set_config('role', 'postgres', true);
  update public.users set tvde_access = false where id = c_cli;      -- desfeito no fim
  perform set_config('role', 'authenticated', true);
  begin
    perform public.tvde_request_ride(40.5373, -7.2675, 'x', 40.55, -7.2675, 'y', 3.0, 'cash', 0);
    v_chk := v_chk || jsonb_build_object('sem_acesso_passageiros_recusado', false);
  exception when others then
    v_chk := v_chk || jsonb_build_object('sem_acesso_passageiros_recusado', sqlerrm = 'no_tvde_access');
  end;
  begin
    r := public.tvde_request_ride(40.5373, -7.2675, 'x', 40.55, -7.2675, 'y', 3.0, 'cash', 0, 'encomendas');
    v_chk := v_chk || jsonb_build_object('sem_acesso_encomendas_aceite', r.ride_kind = 'encomendas');
    perform public.tvde_cancel_ride(r.id, 'cliente', 'prova_a1_rollback');
  exception when others then
    v_chk := v_chk || jsonb_build_object('sem_acesso_encomendas_aceite', false, 'erro_sem_acesso', sqlerrm);
  end;

  perform set_config('role', 'postgres', true);
  update public.platform_settings set value = 'false'::jsonb where key = 'tvde_encomendas_enabled';
  perform set_config('role', 'authenticated', true);
  begin
    perform public.tvde_request_ride(40.5373, -7.2675, 'x', 40.55, -7.2675, 'y', 3.0, 'cash', 0, 'encomendas');
    v_chk := v_chk || jsonb_build_object('interruptor_off_recusa', false);
  exception when others then
    v_chk := v_chk || jsonb_build_object('interruptor_off_recusa', sqlerrm = 'encomendas_desligadas');
  end;
  begin
    perform public.tvde_definir_tipo_pedido('encomendas');
    v_chk := v_chk || jsonb_build_object('interruptor_off_recusa_declarar', false);
  exception when others then
    v_chk := v_chk || jsonb_build_object('interruptor_off_recusa_declarar', sqlerrm = 'encomendas_desligadas');
  end;

  -- assinaturas e permissões -------------------------------------------------------
  perform set_config('role', 'postgres', true);
  v_chk := v_chk || jsonb_build_object(
    'uma_assinatura_cada', (select jsonb_object_agg(p.proname, c) from (select p.proname, count(*) c
         from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname in ('tvde_request_ride','tvde_schedule_ride','tvde_schedule_roundtrip')
        group by 1) p),
    'anon_nao_executa', not (has_function_privilege('anon', 'public.tvde_request_ride(double precision,double precision,text,double precision,double precision,text,numeric,text,integer,text)', 'execute')
                        or has_function_privilege('anon', 'public.tvde_schedule_ride(double precision,double precision,text,double precision,double precision,text,numeric,timestamptz,text,text,text)', 'execute')
                        or has_function_privilege('anon', 'public.tvde_schedule_roundtrip(double precision,double precision,text,double precision,double precision,text,numeric,timestamptz,timestamptz,text,text,text)', 'execute')
                        or has_function_privilege('anon', 'public.tvde_definir_tipo_pedido(text)', 'execute')
                        or has_function_privilege('anon', 'public._tvde_ride_kind_resolver(uuid,text)', 'execute')
                        or has_function_privilege('anon', 'public.admin_tvde_acertos_por_tipo(timestamptz)', 'execute')),
    'cliente_nao_executa_resolver', not has_function_privilege('authenticated', 'public._tvde_ride_kind_resolver(uuid,text)', 'execute'),
    'acl_request_ride', (select proacl::text from pg_proc where oid = 'public.tvde_request_ride(double precision,double precision,text,double precision,double precision,text,numeric,text,integer,text)'::regprocedure),
    'md5_novos', (select jsonb_object_agg(p.proname, md5(p.prosrc)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname in ('tvde_request_ride','tvde_schedule_ride','tvde_schedule_roundtrip')),
    'md5_intactas', (select jsonb_object_agg(p.proname, md5(p.prosrc)) from pg_proc p join pg_namespace n on n.oid = p.pronamespace
        where n.nspname = 'public' and p.proname in ('tvde_offer_to_next','tvde_calculate_fare','tvde_quote_roundtrip',
          'tvde_roundtrip_price_for_km','tvde_fare_breakdown','tvde_finish_ride','tvde_cancel_ride','tvde_accept_ride',
          'compute_driver_settlement','tvde_create_roundtrip_credit_cash','tvde_request_return_ride',
          'tvde_roundtrip_schedule_return_core','tvde_reservation_offer_to_next','tvde_dispatch_sweep','_tvde_exige_acesso',
          'tvde_ride_charge_cents','tvde_request_plan','tvde_quote_plan','tvde_create_roundtrip_credit')),
    'corridas_antigas_passageiros', (select count(*) filter (where ride_kind = 'passageiros') = count(*) from public.tvde_rides
        where created_at < now() - interval '1 minute'));

  raise exception 'RESULT %', jsonb_build_object('linhas', v_lin, 'checks', v_chk)::text;
end $prova$;
